import Crypto
import Foundation

/// One offline trust allowlist entry. Policy identity is matched exactly; a
/// cryptographically valid signature from any other key or policy is rejected.
public struct EvidenceReceiptTrustedKey: Codable, Equatable, Sendable {
    public let authorityID: String
    public let policyID: String
    public let policyVersion: String
    public let policyDigest: String
    public let keyID: String
    /// Base64-encoded 32-byte Ed25519 public key (raw representation).
    public let publicKey: String
    /// RFC 3339 UTC bounds during which this key may issue receipts.
    public let validFrom: String
    public let validUntil: String

    public init(authorityID: String, policyID: String, policyVersion: String,
                policyDigest: String, keyID: String, publicKey: String,
                validFrom: String, validUntil: String) {
        self.authorityID = authorityID
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.policyDigest = policyDigest
        self.keyID = keyID
        self.publicKey = publicKey
        self.validFrom = validFrom
        self.validUntil = validUntil
    }

    enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case policyID = "policy_id"
        case policyVersion = "policy_version"
        case policyDigest = "policy_digest"
        case keyID = "key_id"
        case publicKey = "public_key"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
    }
}

/// Explicit offline allowlist plus bounds for receipt validity and clock skew.
public struct EvidenceReceiptTrustStore: Codable, Equatable, Sendable {
    public let trustedKeys: [EvidenceReceiptTrustedKey]
    public let maximumReceiptLifetimeSeconds: Int64
    public let clockSkewSeconds: Int64

    public init(trustedKeys: [EvidenceReceiptTrustedKey],
                maximumReceiptLifetimeSeconds: Int64 = 86_400,
                clockSkewSeconds: Int64 = 60) {
        self.trustedKeys = trustedKeys
        self.maximumReceiptLifetimeSeconds = maximumReceiptLifetimeSeconds
        self.clockSkewSeconds = clockSkewSeconds
    }

    public static func decode(from data: Data) throws -> EvidenceReceiptTrustStore {
        guard data.count <= 1_000_000 else { throw TrustStoreShapeError.invalidEnvelope }
        try JSONMemberUniqueness.validate(data)
        let root = try JSONSerialization.jsonObject(with: data)
        guard let object = root as? [String: Any],
              Set(object.keys) == Set(["trusted_keys", "maximum_receipt_lifetime_seconds", "clock_skew_seconds"]),
              let keys = object["trusted_keys"] as? [[String: Any]], keys.count <= 1024 else {
            throw TrustStoreShapeError.invalidEnvelope
        }
        let expected = Set(["authority_id", "policy_id", "policy_version", "policy_digest", "key_id", "public_key", "valid_from", "valid_until"])
        guard keys.allSatisfy({ Set($0.keys) == expected }) else { throw TrustStoreShapeError.invalidKeyEntry }
        return try JSONDecoder().decode(EvidenceReceiptTrustStore.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case trustedKeys = "trusted_keys"
        case maximumReceiptLifetimeSeconds = "maximum_receipt_lifetime_seconds"
        case clockSkewSeconds = "clock_skew_seconds"
    }
}

public struct EvidenceReceiptVerificationReport: Codable, Equatable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case trustedObservationReceipt = "trusted_observation_receipt"
        case rejected
    }

    public let verdict: Verdict
    public let trusted: Bool
    public let issues: [ValidationIssue]
    public let receiptID: String?
    public let eventID: String?
    public let authorityID: String?
    public let policyDigest: String?
    /// This bounded profile never asserts aggregate or outcome claims.
    public let acceptedClaims: [String]

    public init(verdict: Verdict, trusted: Bool, issues: [ValidationIssue],
                receiptID: String?, eventID: String?, authorityID: String?,
                policyDigest: String?) {
        self.verdict = verdict
        self.trusted = trusted
        self.issues = issues
        self.receiptID = receiptID
        self.eventID = eventID
        self.authorityID = authorityID
        self.policyDigest = policyDigest
        self.acceptedClaims = []
    }
}

/// Verifies a policy-scoped signed receipt over one exact passport and one
/// normalized observation. A trusted result establishes receipt authenticity
/// and local contract matching only; it does not prove delivery, replay
/// uniqueness, successful execution, or a feature outcome.
public struct EvidenceReceiptVerifier: Sendable {
    public init() {}

    public func verify(passportData: Data, observationData: Data, receiptData: Data,
                       trustStore: EvidenceReceiptTrustStore,
                       verificationTime: Date = Date()) throws -> EvidenceReceiptVerificationReport {
        guard passportData.count <= 10_000_000, observationData.count <= 10_000_000,
              receiptData.count <= 256_000 else {
            return rejected([.init(code: "size_limit", message: "Passport, observation, or receipt exceeds the verifier input size limit")])
        }

        do {
            try JSONMemberUniqueness.validate(passportData)
            try JSONMemberUniqueness.validate(observationData)
        } catch {
            return rejected([.init(code: "duplicate_or_invalid_json", message: "Passport and observation must be unambiguous valid JSON: \(error)")])
        }

        let receipt: ReceiptDocument
        do {
            try ReceiptDocument.validateExactEnvelope(receiptData)
            receipt = try JSONDecoder().decode(ReceiptDocument.self, from: receiptData)
        } catch {
            return rejected([.init(code: "receipt_schema", message: "Receipt is malformed or contains fields outside this profile: \(error)")])
        }

        var issues = validate(trustStore: trustStore)
        if !issues.isEmpty { return rejected(issues, receipt: receipt) }

        let passportDigest = Self.sha256(passportData)
        let eventDigest = Self.sha256(observationData)
        let observation: RuntimeObservation
        do {
            observation = try JSONDecoder().decode(RuntimeObservation.self, from: observationData)
        } catch {
            return rejected([.init(code: "observation_schema", message: "Observation does not match the normalized envelope: \(error)")], receipt: receipt)
        }

        if receipt.featurePassport.digest != passportDigest {
            issues.append(.init(code: "passport_digest_mismatch", message: "Receipt passport digest does not match the exact passport input bytes"))
        }
        if receipt.hashing.eventHash != eventDigest {
            issues.append(.init(code: "event_digest_mismatch", message: "Receipt event hash does not match the exact observation input bytes"))
        }
        if receipt.observation.eventID != observation.integrity.eventID {
            issues.append(.init(code: "event_id_mismatch", message: "Receipt event ID does not match the observation"))
        }
        if receipt.observation.occurredAt != observation.observation.occurredAt {
            issues.append(.init(code: "observed_at_mismatch", message: "Receipt observed_at does not match the observation"))
        }
        if receipt.featurePassport.featureID != observation.featurePassport.featureID ||
            receipt.featurePassport.passportID != observation.featurePassport.passportID ||
            receipt.featurePassport.version != observation.featurePassport.version ||
            receipt.featurePassport.digest != observation.featurePassport.digest ||
            receipt.probe.id != observation.featurePassport.probeID ||
            receipt.probe.eventName != observation.eventName {
            issues.append(.init(code: "receipt_observation_link_mismatch", message: "Receipt feature/passport/probe/event identity does not match the observation"))
        }

        let match = try RuntimeObservationEvaluator().evaluate(
            passportData: passportData, passportDigest: passportDigest, observationData: observationData
        )
        if match.verdict != .matchedUntrusted {
            issues.append(.init(code: "observation_not_matched", message: "Observation does not match the supplied passport under the local runtime contract"))
        }
        if !receipt.acceptedClaims.isEmpty {
            issues.append(.init(code: "claims_not_supported", message: "This profile requires accepted_claims to be empty"))
        }
        if receipt.artifactKind != "evidence_receipt" || receipt.schemaVersion != 1 {
            issues.append(.init(code: "receipt_profile_mismatch", message: "Receipt must use artifact_kind evidence_receipt and schema_version 1"))
        }
        if receipt.hashing.canonicalization != ReceiptSigningProfile.identifier {
            issues.append(.init(code: "receipt_profile_mismatch", message: "Receipt uses an unsupported signing profile"))
        }
        if receipt.hashing.digestProfile != ReceiptSigningProfile.digestIdentifier {
            issues.append(.init(code: "receipt_profile_mismatch", message: "Receipt uses an unsupported input digest profile"))
        }
        if receipt.signature.algorithm != "Ed25519" {
            issues.append(.init(code: "unsupported_signature_algorithm", message: "This verifier accepts only Ed25519 signatures"))
        }
        if receipt.signingFields.contains(where: { $0.1.isEmpty }) {
            issues.append(.init(code: "empty_receipt_field", message: "Signed receipt fields must be nonempty"))
        }
        guard issues.isEmpty else { return rejected(issues, receipt: receipt) }

        guard let key = trustStore.trustedKeys.first(where: {
            $0.authorityID == receipt.authority.id && $0.policyID == receipt.authority.policyID &&
            $0.policyVersion == receipt.authority.policyVersion && $0.policyDigest == receipt.authority.policyDigest &&
            $0.keyID == receipt.signature.keyID
        }) else {
            return rejected([.init(code: "untrusted_issuer_or_policy", message: "Authority, policy digest, or key ID is not present in the explicit trust allowlist")], receipt: receipt)
        }

        guard let acceptedAt = EvidenceReceiptTimestamp.parseRFC3339UTC(receipt.timestamps.acceptedAt),
              let validFrom = EvidenceReceiptTimestamp.parseRFC3339UTC(receipt.timestamps.validFrom),
              let validUntil = EvidenceReceiptTimestamp.parseRFC3339UTC(receipt.timestamps.validUntil),
              let observedAt = EvidenceReceiptTimestamp.parseRFC3339UTC(receipt.observation.occurredAt),
              let keyValidFrom = EvidenceReceiptTimestamp.parseRFC3339UTC(key.validFrom),
              let keyValidUntil = EvidenceReceiptTimestamp.parseRFC3339UTC(key.validUntil) else {
            return rejected([.init(code: "invalid_timestamp", message: "Receipt and trust-store timestamps must use supported RFC 3339 UTC syntax")], receipt: receipt)
        }
        let skew = TimeInterval(trustStore.clockSkewSeconds)
        let maximumLifetime = TimeInterval(trustStore.maximumReceiptLifetimeSeconds)
        if validUntil <= validFrom || validUntil.timeIntervalSince(validFrom) > maximumLifetime {
            issues.append(.init(code: "receipt_validity_bounds", message: "Receipt validity interval is empty, inverted, or exceeds the trust-store maximum"))
        }
        if acceptedAt < validFrom || acceptedAt > validUntil || observedAt > acceptedAt.addingTimeInterval(skew) {
            issues.append(.init(code: "receipt_timestamp_bounds", message: "Acceptance time must be inside receipt validity and not precede the observation beyond allowed skew"))
        }
        if verificationTime < validFrom.addingTimeInterval(-skew) || verificationTime > validUntil.addingTimeInterval(skew) || acceptedAt > verificationTime.addingTimeInterval(skew) {
            issues.append(.init(code: "receipt_not_current", message: "Receipt is outside its validity window at verification time"))
        }
        if acceptedAt < keyValidFrom || acceptedAt > keyValidUntil {
            issues.append(.init(code: "key_validity_bounds", message: "Receipt was accepted outside the trusted key validity interval"))
        }
        guard issues.isEmpty else { return rejected(issues, receipt: receipt) }

        let fields = receipt.signingFields
        let signedBytes = ReceiptSigningProfile.payload(fields: fields)
        let recomputedReceiptHash = Self.sha256Bytes(signedBytes)
        if receipt.hashing.receiptHash != Self.formatDigest(recomputedReceiptHash) {
            issues.append(.init(code: "receipt_hash_mismatch", message: "Receipt hash does not match its versioned signing payload"))
        }
        guard let publicKeyBytes = Data(base64Encoded: key.publicKey), publicKeyBytes.count == 32,
              let signatureBytes = Data(base64Encoded: receipt.signature.value), signatureBytes.count == 64 else {
            issues.append(.init(code: "invalid_key_or_signature_encoding", message: "Ed25519 public key and signature must be valid base64 with 32 and 64 bytes"))
            return rejected(issues, receipt: receipt)
        }
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyBytes)
            if !publicKey.isValidSignature(signatureBytes, for: recomputedReceiptHash) {
                issues.append(.init(code: "signature_invalid", message: "Ed25519 signature verification failed"))
            }
        } catch {
            issues.append(.init(code: "public_key_invalid", message: "Trusted Ed25519 public key could not be parsed"))
        }
        guard issues.isEmpty else { return rejected(issues, receipt: receipt) }
        return EvidenceReceiptVerificationReport(verdict: .trustedObservationReceipt, trusted: true,
            issues: [], receiptID: receipt.receiptID, eventID: receipt.observation.eventID,
            authorityID: receipt.authority.id, policyDigest: receipt.authority.policyDigest)
    }

    public static func sha256(_ data: Data) -> String {
        formatDigest(sha256Bytes(data))
    }

    private static func sha256Bytes(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func formatDigest(_ bytes: Data) -> String {
        "sha256:" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func validate(trustStore: EvidenceReceiptTrustStore) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if trustStore.trustedKeys.isEmpty || trustStore.trustedKeys.count > 1024 || trustStore.maximumReceiptLifetimeSeconds <= 0 ||
            trustStore.maximumReceiptLifetimeSeconds > 2_592_000 || trustStore.clockSkewSeconds < 0 || trustStore.clockSkewSeconds > 300 {
            issues.append(.init(code: "invalid_trust_store", message: "Trust store needs keys, a 1 second–30 day maximum lifetime, and 0–300 seconds of clock skew"))
        }
        let identities = trustStore.trustedKeys.map { "\($0.authorityID)|\($0.policyID)|\($0.policyVersion)|\($0.policyDigest)|\($0.keyID)" }
        if Set(identities).count != identities.count {
            issues.append(.init(code: "ambiguous_trust_store", message: "Trust store contains duplicate authority/policy/key entries"))
        }
        for key in trustStore.trustedKeys {
            if [key.authorityID, key.policyID, key.policyVersion, key.policyDigest, key.keyID, key.publicKey].contains(where: \.isEmpty) ||
                !Self.isSHA256Digest(key.policyDigest) || Data(base64Encoded: key.publicKey)?.count != 32 ||
                EvidenceReceiptTimestamp.parseRFC3339UTC(key.validFrom) == nil || EvidenceReceiptTimestamp.parseRFC3339UTC(key.validUntil) == nil {
                issues.append(.init(code: "invalid_trust_key", message: "Trusted key entry is incomplete or malformed: \(key.keyID)"))
            }
        }
        return issues
    }

    private func rejected(_ issues: [ValidationIssue], receipt: ReceiptDocument? = nil) -> EvidenceReceiptVerificationReport {
        EvidenceReceiptVerificationReport(verdict: .rejected, trusted: false, issues: issues,
            receiptID: receipt?.receiptID, eventID: receipt?.observation.eventID,
            authorityID: receipt?.authority.id, policyDigest: receipt?.authority.policyDigest)
    }

    private static func isSHA256Digest(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:") else { return false }
        let hex = value.dropFirst("sha256:".count)
        let digits = Set("0123456789abcdef")
        return hex.count == 64 && hex.allSatisfy(digits.contains)
    }
}

/// The profile is intentionally not JCS. `fp-receipt-v1-fields` encodes a
/// fixed, versioned sequence of UTF-8 name/value pairs, each preceded by a
/// 32-bit big-endian byte length. No JSON canonicalization is implied.
enum ReceiptSigningProfile {
    static let identifier = "fp-receipt-v1-fields"
    static let digestIdentifier = "fp-exact-bytes-sha256-v1"
    static let domain = Data("FeaturePassport\0EvidenceReceipt\0v1\0".utf8)

    static func payload(fields: [(String, String)]) -> Data {
        var output = domain
        for (name, value) in fields {
            append(Data(name.utf8), to: &output)
            append(Data(value.utf8), to: &output)
        }
        return output
    }

    private static func append(_ bytes: Data, to output: inout Data) {
        var length = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
        output.append(bytes)
    }
}

private struct ReceiptDocument: Decodable {
    struct Authority: Decodable { let id: String; let policyID: String; let policyVersion: String; let policyDigest: String
        enum CodingKeys: String, CodingKey { case id; case policyID = "policy_id"; case policyVersion = "policy_version"; case policyDigest = "policy_digest" }
    }
    struct Passport: Decodable { let featureID: String; let passportID: String; let version: String; let digest: String
        enum CodingKeys: String, CodingKey { case featureID = "feature_id"; case passportID = "passport_id"; case version, digest }
    }
    struct Probe: Decodable { let id: String; let eventName: String
        enum CodingKeys: String, CodingKey { case id; case eventName = "event_name" }
    }
    struct Observation: Decodable { let eventID: String; let occurredAt: String
        enum CodingKeys: String, CodingKey { case eventID = "event_id"; case occurredAt = "occurred_at" }
    }
    struct Hashing: Decodable { let canonicalization: String; let digestProfile: String; let eventHash: String; let receiptHash: String
        enum CodingKeys: String, CodingKey { case canonicalization; case digestProfile = "digest_profile"; case eventHash = "event_hash"; case receiptHash = "receipt_hash" }
    }
    struct Signature: Decodable { let algorithm: String; let keyID: String; let value: String
        enum CodingKeys: String, CodingKey { case algorithm; case keyID = "key_id"; case value }
    }
    struct Timestamps: Decodable { let acceptedAt: String; let validFrom: String; let validUntil: String
        enum CodingKeys: String, CodingKey { case acceptedAt = "accepted_at"; case validFrom = "valid_from"; case validUntil = "valid_until" }
    }

    let artifactKind: String
    let schemaVersion: Int
    let authority: Authority
    let featurePassport: Passport
    let probe: Probe
    let observation: Observation
    let receiptID: String
    let acceptedClaims: [JSONClaim]
    let hashing: Hashing
    let signature: Signature
    let timestamps: Timestamps
    enum CodingKeys: String, CodingKey {
        case artifactKind = "artifact_kind"; case schemaVersion = "schema_version"
        case authority, probe, observation, hashing, signature, timestamps
        case featurePassport = "feature_passport"; case receiptID = "receipt_id"
        case acceptedClaims = "accepted_claims"
    }

    var signingFields: [(String, String)] {
        [
            ("artifact_kind", artifactKind), ("schema_version", String(schemaVersion)),
            ("authority.id", authority.id), ("authority.policy_id", authority.policyID),
            ("authority.policy_version", authority.policyVersion), ("authority.policy_digest", authority.policyDigest),
            ("feature_passport.feature_id", featurePassport.featureID), ("feature_passport.passport_id", featurePassport.passportID),
            ("feature_passport.version", featurePassport.version), ("feature_passport.digest", featurePassport.digest),
            ("probe.id", probe.id), ("probe.event_name", probe.eventName),
            ("observation.event_id", observation.eventID), ("observation.occurred_at", observation.occurredAt),
            ("receipt_id", receiptID), ("accepted_claims", "[]"),
            ("hashing.canonicalization", hashing.canonicalization), ("hashing.digest_profile", hashing.digestProfile),
            ("hashing.event_hash", hashing.eventHash),
            ("timestamps.accepted_at", timestamps.acceptedAt), ("timestamps.valid_from", timestamps.validFrom),
            ("timestamps.valid_until", timestamps.validUntil),
            ("signature.algorithm", signature.algorithm), ("signature.key_id", signature.keyID)
        ]
    }

    static func validateExactEnvelope(_ data: Data) throws {
        try JSONMemberUniqueness.validate(data)
        let root = try JSONSerialization.jsonObject(with: data)
        try exactKeys(root, ["artifact_kind", "schema_version", "authority", "feature_passport", "probe", "observation", "receipt_id", "accepted_claims", "hashing", "signature", "timestamps"], at: "receipt")
        guard let object = root as? [String: Any] else { throw ReceiptShapeError.objectExpected("receipt") }
        try exactKeys(object["authority"], ["id", "policy_id", "policy_version", "policy_digest"], at: "authority")
        try exactKeys(object["feature_passport"], ["feature_id", "passport_id", "version", "digest"], at: "feature_passport")
        try exactKeys(object["probe"], ["id", "event_name"], at: "probe")
        try exactKeys(object["observation"], ["event_id", "occurred_at"], at: "observation")
        try exactKeys(object["hashing"], ["canonicalization", "digest_profile", "event_hash", "receipt_hash"], at: "hashing")
        try exactKeys(object["signature"], ["algorithm", "key_id", "value"], at: "signature")
        try exactKeys(object["timestamps"], ["accepted_at", "valid_from", "valid_until"], at: "timestamps")
        guard let claims = object["accepted_claims"] as? [Any], claims.isEmpty else { throw ReceiptShapeError.claimsMustBeEmpty }
    }

    private static func exactKeys(_ value: Any?, _ expected: Set<String>, at path: String) throws {
        guard let object = value as? [String: Any] else { throw ReceiptShapeError.objectExpected(path) }
        guard Set(object.keys) == expected else { throw ReceiptShapeError.keysMismatch(path) }
    }
}

private struct JSONClaim: Decodable {}

private enum ReceiptShapeError: Error {
    case objectExpected(String)
    case keysMismatch(String)
    case claimsMustBeEmpty
    case invalidJSON
    case duplicateKey(String)
}

private enum TrustStoreShapeError: Error {
    case invalidEnvelope
    case invalidKeyEntry
}

/// Foundation dictionaries erase duplicate names; reject duplicates before
/// decoding so the signed profile has one interpretation for every object.
private struct JSONMemberUniqueness {
    private let bytes: [UInt8]
    private var index = 0
    private var nestingDepth = 0

    static func validate(_ data: Data) throws {
        var scanner = JSONMemberUniqueness(bytes: Array(data))
        scanner.skipWhitespace()
        try scanner.parseValue()
        scanner.skipWhitespace()
        guard scanner.index == scanner.bytes.count else { throw ReceiptShapeError.invalidJSON }
    }

    private init(bytes: [UInt8]) { self.bytes = bytes }

    private mutating func parseValue() throws {
        nestingDepth += 1
        defer { nestingDepth -= 1 }
        guard nestingDepth <= 64 else { throw ReceiptShapeError.invalidJSON }
        skipWhitespace()
        guard index < bytes.count else { throw ReceiptShapeError.invalidJSON }
        switch bytes[index] {
        case 0x7B: try parseObject()
        case 0x5B: try parseArray()
        case 0x22: _ = try parseString()
        default:
            let start = index
            while index < bytes.count && ![0x2C, 0x5D, 0x7D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
            guard index > start else { throw ReceiptShapeError.invalidJSON }
        }
    }

    private mutating func parseObject() throws {
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }
        var keys = Set<String>()
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x22 else { throw ReceiptShapeError.invalidJSON }
            let keyToken = try parseString()
            let decoded = try JSONSerialization.jsonObject(with: Data("[\(keyToken)]".utf8)) as? [String]
            guard let key = decoded?.first else { throw ReceiptShapeError.invalidJSON }
            guard keys.insert(key).inserted else { throw ReceiptShapeError.duplicateKey(key) }
            skipWhitespace()
            guard consume(0x3A) else { throw ReceiptShapeError.invalidJSON }
            try parseValue()
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw ReceiptShapeError.invalidJSON }
        }
    }

    private mutating func parseArray() throws {
        index += 1
        skipWhitespace()
        if consume(0x5D) { return }
        while true {
            try parseValue()
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw ReceiptShapeError.invalidJSON }
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        index += 1
        while index < bytes.count {
            if bytes[index] == 0x5C { index += 2; continue }
            if bytes[index] == 0x22 {
                index += 1
                guard let token = String(bytes: bytes[start..<index], encoding: .utf8) else { throw ReceiptShapeError.invalidJSON }
                return token
            }
            index += 1
        }
        throw ReceiptShapeError.invalidJSON
    }

    private mutating func skipWhitespace() {
        while index < bytes.count && [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}

public enum EvidenceReceiptTimestamp {
    /// Parses the profile's RFC 3339 UTC timestamps without Foundation's lenient normalization.
    public static func parseRFC3339UTC(_ value: String) -> Date? {
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let dateText = String(value.prefix(19))
        let components = dateText.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard components.count == 6 else { return nil }
        let year = components[0], month = components[1], day = components[2]
        let hour = components[3], minute = components[4], second = components[5]
        guard
              (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
              (0...59).contains(minute), (0...59).contains(second) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var requested = DateComponents()
        requested.calendar = calendar
        requested.timeZone = calendar.timeZone
        requested.year = year
        requested.month = month
        requested.day = day
        requested.hour = hour
        requested.minute = minute
        requested.second = second
        guard let date = calendar.date(from: requested) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day,
              roundTrip.hour == hour, roundTrip.minute == minute, roundTrip.second == second else { return nil }

        if let decimal = value.firstIndex(of: ".") {
            let fraction = value[value.index(after: decimal)..<value.index(before: value.endIndex)]
            guard let digits = Double("0." + fraction) else { return nil }
            return date.addingTimeInterval(digits)
        }
        return date
    }
}
