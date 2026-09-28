import Crypto
import Foundation

/// Exact source bytes consumed by an aggregate decision issuer or verifier.
public struct AggregateClaimDecisionInputs: Sendable {
    /// A resolved observation/receipt pair corresponding to one bundle entry.
    public struct Pair: Sendable {
        public let observationPath: String
        public let receiptPath: String
        public let observationData: Data
        public let receiptData: Data

        public init(observationPath: String, receiptPath: String,
                    observationData: Data, receiptData: Data) {
            self.observationPath = observationPath
            self.receiptPath = receiptPath
            self.observationData = observationData
            self.receiptData = receiptData
        }
    }

    public let passportData: Data
    public let claimPolicyData: Data
    public let bundleData: Data
    public let receiptTrustStoreData: Data
    public let pairs: [Pair]

    public init(passportData: Data, claimPolicyData: Data, bundleData: Data,
                receiptTrustStoreData: Data, pairs: [Pair]) {
        self.passportData = passportData
        self.claimPolicyData = claimPolicyData
        self.bundleData = bundleData
        self.receiptTrustStoreData = receiptTrustStoreData
        self.pairs = pairs
    }

    fileprivate var localPairs: [LocalAggregateClaimPair] {
        pairs.map { .init(observationData: $0.observationData, receiptData: $0.receiptData) }
    }
}

/// Authorization to sign decisions for an exact set of claim-policy byte digests.
public struct AggregateClaimDecisionAuthorization: Sendable {
    public let authorityID: String
    public let keyID: String
    public let publicKey: Data
    public let authorizedClaimPolicyDigests: Set<String>

    public init(authorityID: String, keyID: String, publicKey: Data,
                authorizedClaimPolicyDigests: Set<String>) {
        self.authorityID = authorityID
        self.keyID = keyID
        self.publicKey = publicKey
        self.authorizedClaimPolicyDigests = authorizedClaimPolicyDigests
    }
}

/// Injected Ed25519 signing capability. Production key custody remains with the caller.
public protocol AggregateClaimDecisionSigner: Sendable {
    var publicKey: Data { get }
    func sign(message: Data) throws -> Data
}

/// A decision-authority key and the exact claim-policy digests it may sign.
public struct AggregateClaimDecisionTrustedKey: Codable, Equatable, Sendable {
    public let authorityID: String
    public let keyID: String
    public let publicKey: String
    public let authorizedClaimPolicyDigests: [String]

    public init(authorityID: String, keyID: String, publicKey: String,
                authorizedClaimPolicyDigests: [String]) {
        self.authorityID = authorityID
        self.keyID = keyID
        self.publicKey = publicKey
        self.authorizedClaimPolicyDigests = authorizedClaimPolicyDigests
    }

    enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case keyID = "key_id"
        case publicKey = "public_key"
        case authorizedClaimPolicyDigests = "authorized_claim_policy_digests"
    }
}

/// Explicit offline trust configuration for aggregate decision authorities.
public struct AggregateClaimDecisionTrustStore: Codable, Equatable, Sendable {
    public let trustedKeys: [AggregateClaimDecisionTrustedKey]

    public init(trustedKeys: [AggregateClaimDecisionTrustedKey]) {
        self.trustedKeys = trustedKeys
    }

    enum CodingKeys: String, CodingKey { case trustedKeys = "trusted_keys" }

    /// Decodes the exact, bounded v1 trust envelope and rejects duplicate JSON names.
    public static func decode(from data: Data) throws -> Self {
        guard data.count <= 1_000_000 else { throw AggregateClaimDecisionError.invalidTrustStore }
        try JSONMemberUniqueness.validate(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["trusted_keys"]),
              let keys = root["trusted_keys"] as? [[String: Any]],
              !keys.isEmpty, keys.count <= 1024 else {
            throw AggregateClaimDecisionError.invalidTrustStore
        }
        let expected = Set(["authority_id", "key_id", "public_key", "authorized_claim_policy_digests"])
        guard keys.allSatisfy({ Set($0.keys) == expected }) else {
            throw AggregateClaimDecisionError.invalidTrustStore
        }
        let store = try JSONDecoder().decode(Self.self, from: data)
        let identities = store.trustedKeys.map { "\($0.authorityID)|\($0.keyID)" }
        guard Set(identities).count == identities.count,
              store.trustedKeys.allSatisfy({ key in
                  !key.authorityID.isEmpty && !key.keyID.isEmpty &&
                  Data(base64Encoded: key.publicKey)?.count == 32 &&
                  !key.authorizedClaimPolicyDigests.isEmpty &&
                  Set(key.authorizedClaimPolicyDigests).count == key.authorizedClaimPolicyDigests.count &&
                  key.authorizedClaimPolicyDigests.allSatisfy(AggregateClaimDecisionSigningProfile.isDigest)
              }) else {
            throw AggregateClaimDecisionError.invalidTrustStore
        }
        return store
    }
}

/// Signed result of one exact, repeatable local aggregate predicate evaluation.
public struct AggregateClaimDecision: Codable, Equatable, Sendable {
    public enum Decision: String, Codable, Sendable {
        case accepted
        case notSatisfied = "not_satisfied"
    }

    public struct PairDigest: Codable, Equatable, Sendable {
        public let observationPath: String
        public let receiptPath: String
        public let observationDigest: String
        public let receiptDigest: String

        enum CodingKeys: String, CodingKey {
            case observationPath = "observation_path"
            case receiptPath = "receipt_path"
            case observationDigest = "observation_digest"
            case receiptDigest = "receipt_digest"
        }
    }

    public struct Issuer: Codable, Equatable, Sendable {
        public let authorityID: String
        public let keyID: String
        enum CodingKeys: String, CodingKey { case authorityID = "authority_id"; case keyID = "key_id" }
    }

    public struct Signature: Codable, Equatable, Sendable {
        public let algorithm: String
        public let profile: String
        public let value: String
    }

    public let artifactKind: String
    public let schemaVersion: Int
    public let decisionProfile: String
    public let decisionDigest: String
    public let decision: Decision
    public let featureID: String
    public let passportID: String
    public let passportVersion: String
    public let claimID: String
    public let claimPolicyID: String
    public let claimPolicyVersion: String
    public let claimPolicyDigest: String
    public let predicateProfile: String
    public let evaluationTime: String
    public let passportDigest: String
    public let bundleDigest: String
    public let receiptTrustStoreDigest: String
    public let pairDigests: [PairDigest]
    public let issuer: Issuer
    public let signature: Signature

    enum CodingKeys: String, CodingKey {
        case artifactKind = "artifact_kind"
        case schemaVersion = "schema_version"
        case decisionProfile = "decision_profile"
        case decisionDigest = "decision_digest"
        case decision
        case featureID = "feature_id"
        case passportID = "passport_id"
        case passportVersion = "passport_version"
        case claimID = "claim_id"
        case claimPolicyID = "claim_policy_id"
        case claimPolicyVersion = "claim_policy_version"
        case claimPolicyDigest = "claim_policy_digest"
        case predicateProfile = "predicate_profile"
        case evaluationTime = "evaluation_time"
        case passportDigest = "passport_digest"
        case bundleDigest = "bundle_digest"
        case receiptTrustStoreDigest = "receipt_trust_store_digest"
        case pairDigests = "pair_digests"
        case issuer, signature
    }
}

public struct AggregateClaimDecisionVerificationReport: Codable, Equatable, Sendable {
    public let trusted: Bool
    public let decision: AggregateClaimDecision.Decision?
    public let claimID: String?
    public let issues: [ValidationIssue]

    enum CodingKeys: String, CodingKey {
        case trusted, decision
        case claimID = "claim_id"
        case issues
    }
}

/// Issues signed decisions only for policy digests explicitly authorized by the caller.
public struct AggregateClaimDecisionIssuer: Sendable {
    public init() {}

    /// Reruns the local evaluator and signs its bounded result with an injected key.
    public func issue(inputs: AggregateClaimDecisionInputs, authorization: AggregateClaimDecisionAuthorization,
                      signer: any AggregateClaimDecisionSigner, evaluationTime: String) throws -> AggregateClaimDecision {
        guard EvidenceReceiptTimestamp.parseRFC3339UTC(evaluationTime) != nil else {
            throw AggregateClaimDecisionError.invalidEvaluationTime
        }
        try AggregateClaimDecisionVerifier.validateInputs(inputs)
        let policyDigest = EvidenceReceiptVerifier.sha256(inputs.claimPolicyData)
        guard authorization.authorizedClaimPolicyDigests.contains(policyDigest),
              !authorization.authorityID.isEmpty, !authorization.keyID.isEmpty else {
            throw AggregateClaimDecisionError.unauthorizedPolicy
        }
        guard signer.publicKey == authorization.publicKey,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: authorization.publicKey),
              publicKey.rawRepresentation.count == 32 else {
            throw AggregateClaimDecisionError.invalidSigner
        }
        let receiptTrustStore = try EvidenceReceiptTrustStore.decode(from: inputs.receiptTrustStoreData)
        let at = EvidenceReceiptTimestamp.parseRFC3339UTC(evaluationTime)!
        let evaluation = try LocalAggregateClaimEvaluator().evaluate(
            passportData: inputs.passportData, policyData: inputs.claimPolicyData,
            pairs: inputs.localPairs, trustStore: receiptTrustStore, verificationTime: at
        )
        guard let featureID = evaluation.featureID, let passportID = evaluation.passportID,
              let passportVersion = evaluation.passportVersion, let claimID = evaluation.claimID,
              let policyID = evaluation.policyID, let policyVersion = evaluation.policyVersion,
              let passportDigest = evaluation.passportDigest else {
            throw AggregateClaimDecisionError.invalidPredicateInputs
        }

        let unsigned = AggregateClaimDecision(
            artifactKind: "aggregate_claim_decision", schemaVersion: 1,
            decisionProfile: AggregateClaimDecisionSigningProfile.identifier,
            decisionDigest: "", decision: evaluation.satisfied ? .accepted : .notSatisfied,
            featureID: featureID, passportID: passportID, passportVersion: passportVersion,
            claimID: claimID, claimPolicyID: policyID, claimPolicyVersion: policyVersion,
            claimPolicyDigest: policyDigest, predicateProfile: "local-aggregate-claim-evaluation-v1",
            evaluationTime: evaluationTime, passportDigest: passportDigest,
            bundleDigest: EvidenceReceiptVerifier.sha256(inputs.bundleData),
            receiptTrustStoreDigest: EvidenceReceiptVerifier.sha256(inputs.receiptTrustStoreData),
            pairDigests: Self.pairDigests(inputs.pairs),
            issuer: .init(authorityID: authorization.authorityID, keyID: authorization.keyID),
            signature: .init(algorithm: "Ed25519", profile: AggregateClaimDecisionSigningProfile.identifier, value: "")
        )
        let payload = AggregateClaimDecisionSigningProfile.payload(for: unsigned)
        let signature = try signer.sign(message: payload)
        guard signature.count == 64, publicKey.isValidSignature(signature, for: payload) else {
            throw AggregateClaimDecisionError.signerReturnedInvalidSignature
        }
        return AggregateClaimDecision(
            artifactKind: unsigned.artifactKind, schemaVersion: unsigned.schemaVersion,
            decisionProfile: unsigned.decisionProfile,
            decisionDigest: EvidenceReceiptVerifier.sha256(payload), decision: unsigned.decision,
            featureID: unsigned.featureID, passportID: unsigned.passportID,
            passportVersion: unsigned.passportVersion, claimID: unsigned.claimID,
            claimPolicyID: unsigned.claimPolicyID, claimPolicyVersion: unsigned.claimPolicyVersion,
            claimPolicyDigest: unsigned.claimPolicyDigest, predicateProfile: unsigned.predicateProfile,
            evaluationTime: unsigned.evaluationTime, passportDigest: unsigned.passportDigest,
            bundleDigest: unsigned.bundleDigest, receiptTrustStoreDigest: unsigned.receiptTrustStoreDigest,
            pairDigests: unsigned.pairDigests, issuer: unsigned.issuer,
            signature: .init(algorithm: "Ed25519", profile: AggregateClaimDecisionSigningProfile.identifier,
                            value: signature.base64EncodedString())
        )
    }

    private static func pairDigests(_ pairs: [AggregateClaimDecisionInputs.Pair]) -> [AggregateClaimDecision.PairDigest] {
        pairs.map {
            .init(observationPath: $0.observationPath, receiptPath: $0.receiptPath,
                  observationDigest: EvidenceReceiptVerifier.sha256($0.observationData),
                  receiptDigest: EvidenceReceiptVerifier.sha256($0.receiptData))
        }
    }
}

/// Verifies decision signature and exact input links, then reruns the local predicate.
public struct AggregateClaimDecisionVerifier: Sendable {
    public init() {}

    public func verify(decisionData: Data, inputs: AggregateClaimDecisionInputs,
                       trustStore: AggregateClaimDecisionTrustStore) throws -> AggregateClaimDecisionVerificationReport {
        guard decisionData.count <= 1_000_000 else {
            return Self.rejected("size_limit", "Decision artifact exceeds the 1 MB verifier input limit")
        }
        try Self.validateInputs(inputs)
        guard Self.isValid(trustStore: trustStore) else {
            return Self.rejected("decision_trust_store_invalid", "Decision authority trust configuration is malformed or ambiguous")
        }
        let decision: AggregateClaimDecision
        do {
            try JSONMemberUniqueness.validate(decisionData)
            try Self.validateDecisionEnvelope(decisionData)
            decision = try JSONDecoder().decode(AggregateClaimDecision.self, from: decisionData)
        } catch {
            return Self.rejected("decision_schema", "Decision artifact is malformed or outside profile v1")
        }
        guard decision.artifactKind == "aggregate_claim_decision", decision.schemaVersion == 1,
              decision.decisionProfile == AggregateClaimDecisionSigningProfile.identifier,
              decision.predicateProfile == "local-aggregate-claim-evaluation-v1",
              decision.signature.algorithm == "Ed25519",
              decision.signature.profile == AggregateClaimDecisionSigningProfile.identifier,
              EvidenceReceiptTimestamp.parseRFC3339UTC(decision.evaluationTime) != nil else {
            return Self.rejected("decision_profile_mismatch", "Decision artifact uses unsupported schema, signing, predicate, or time profile")
        }
        guard decision.passportDigest == EvidenceReceiptVerifier.sha256(inputs.passportData),
              decision.claimPolicyDigest == EvidenceReceiptVerifier.sha256(inputs.claimPolicyData),
              decision.bundleDigest == EvidenceReceiptVerifier.sha256(inputs.bundleData),
              decision.receiptTrustStoreDigest == EvidenceReceiptVerifier.sha256(inputs.receiptTrustStoreData),
              decision.pairDigests == AggregateClaimDecisionIssuer.pairDigestsForVerification(inputs.pairs) else {
            return Self.rejected("decision_input_mismatch", "One or more exact decision input byte digests differ")
        }
        guard let key = trustStore.trustedKeys.first(where: {
            $0.authorityID == decision.issuer.authorityID && $0.keyID == decision.issuer.keyID
        }), key.authorizedClaimPolicyDigests.contains(decision.claimPolicyDigest),
              let keyData = Data(base64Encoded: key.publicKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signatureData = Data(base64Encoded: decision.signature.value) else {
            return Self.rejected("decision_authority_untrusted", "Decision authority, key, or exact policy digest is not allowlisted")
        }
        let payload = AggregateClaimDecisionSigningProfile.payload(for: decision)
        guard decision.decisionDigest == EvidenceReceiptVerifier.sha256(payload),
              publicKey.isValidSignature(signatureData, for: payload) else {
            return Self.rejected("decision_signature_invalid", "Decision digest or Ed25519 signature is invalid")
        }

        let receiptTrustStore = try EvidenceReceiptTrustStore.decode(from: inputs.receiptTrustStoreData)
        let evaluation = try LocalAggregateClaimEvaluator().evaluate(
            passportData: inputs.passportData, policyData: inputs.claimPolicyData,
            pairs: inputs.localPairs, trustStore: receiptTrustStore,
            verificationTime: EvidenceReceiptTimestamp.parseRFC3339UTC(decision.evaluationTime)!
        )
        guard decision.decision == (evaluation.satisfied ? .accepted : .notSatisfied),
              decision.featureID == evaluation.featureID, decision.passportID == evaluation.passportID,
              decision.passportVersion == evaluation.passportVersion, decision.claimID == evaluation.claimID,
              decision.claimPolicyID == evaluation.policyID, decision.claimPolicyVersion == evaluation.policyVersion,
              decision.claimPolicyDigest == evaluation.policyDigest else {
            return Self.rejected("decision_predicate_mismatch", "Signed decision does not match a fresh evaluation at its signed time")
        }
        return AggregateClaimDecisionVerificationReport(trusted: true, decision: decision.decision,
                                                         claimID: decision.claimID, issues: [])
    }

    fileprivate static func validateInputs(_ inputs: AggregateClaimDecisionInputs) throws {
        guard inputs.passportData.count <= 10_000_000, inputs.claimPolicyData.count <= 256_000,
              inputs.bundleData.count <= 256_000, inputs.receiptTrustStoreData.count <= 1_000_000,
              inputs.pairs.count <= 64,
              inputs.pairs.allSatisfy({ $0.observationData.count <= 10_000_000 && $0.receiptData.count <= 256_000 }),
              inputs.pairs.reduce(0, { $0 + $1.observationData.count + $1.receiptData.count }) <= 64_000_000 else {
            throw AggregateClaimDecisionError.inputLimit
        }
        let bundle = try LocalAggregateClaimBundle.decode(from: inputs.bundleData)
        guard bundle.pairs.count == inputs.pairs.count,
              zip(bundle.pairs, inputs.pairs).allSatisfy({ reference, pair in
                  reference.observation == pair.observationPath && reference.receipt == pair.receiptPath
              }) else {
            throw AggregateClaimDecisionError.bundlePairMismatch
        }
    }

    private static func isValid(trustStore: AggregateClaimDecisionTrustStore) -> Bool {
        guard !trustStore.trustedKeys.isEmpty, trustStore.trustedKeys.count <= 1024 else { return false }
        let identities = trustStore.trustedKeys.map { "\($0.authorityID)|\($0.keyID)" }
        return Set(identities).count == identities.count && trustStore.trustedKeys.allSatisfy { key in
            !key.authorityID.isEmpty && !key.keyID.isEmpty && Data(base64Encoded: key.publicKey)?.count == 32 &&
                !key.authorizedClaimPolicyDigests.isEmpty &&
                Set(key.authorizedClaimPolicyDigests).count == key.authorizedClaimPolicyDigests.count &&
                key.authorizedClaimPolicyDigests.allSatisfy(AggregateClaimDecisionSigningProfile.isDigest)
        }
    }

    private static func validateDecisionEnvelope(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["artifact_kind", "schema_version", "decision_profile", "decision_digest", "decision", "feature_id", "passport_id", "passport_version", "claim_id", "claim_policy_id", "claim_policy_version", "claim_policy_digest", "predicate_profile", "evaluation_time", "passport_digest", "bundle_digest", "receipt_trust_store_digest", "pair_digests", "issuer", "signature"]),
              let issuer = root["issuer"] as? [String: Any], Set(issuer.keys) == Set(["authority_id", "key_id"]),
              let signature = root["signature"] as? [String: Any], Set(signature.keys) == Set(["algorithm", "profile", "value"]),
              let pairs = root["pair_digests"] as? [[String: Any]],
              pairs.allSatisfy({ Set($0.keys) == Set(["observation_path", "receipt_path", "observation_digest", "receipt_digest"]) }) else {
            throw AggregateClaimDecisionError.invalidDecision
        }
    }

    private static func rejected(_ code: String, _ message: String) -> AggregateClaimDecisionVerificationReport {
        AggregateClaimDecisionVerificationReport(trusted: false, decision: nil, claimID: nil,
                                                  issues: [.init(code: code, message: message)])
    }
}

enum AggregateClaimDecisionSigningProfile {
    static let identifier = "fp-aggregate-decision-v1-fields"
    private static let domain = Data("FeaturePassport\0AggregateClaimDecision\0v1\0".utf8)

    static func payload(for decision: AggregateClaimDecision) -> Data {
        var fields: [(String, String)] = [
            ("decision_profile", identifier), ("decision", decision.decision.rawValue),
            ("feature_id", decision.featureID), ("passport_id", decision.passportID),
            ("passport_version", decision.passportVersion), ("claim_id", decision.claimID),
            ("claim_policy_id", decision.claimPolicyID), ("claim_policy_version", decision.claimPolicyVersion),
            ("claim_policy_digest", decision.claimPolicyDigest), ("predicate_profile", decision.predicateProfile),
            ("evaluation_time", decision.evaluationTime), ("passport_digest", decision.passportDigest),
            ("bundle_digest", decision.bundleDigest), ("receipt_trust_store_digest", decision.receiptTrustStoreDigest),
            ("issuer.authority_id", decision.issuer.authorityID), ("issuer.key_id", decision.issuer.keyID),
            ("pair_count", String(decision.pairDigests.count))
        ]
        for (index, pair) in decision.pairDigests.enumerated() {
            fields += [("pairs[\(index)].observation_path", pair.observationPath),
                       ("pairs[\(index)].receipt_path", pair.receiptPath),
                       ("pairs[\(index)].observation_digest", pair.observationDigest),
                       ("pairs[\(index)].receipt_digest", pair.receiptDigest)]
        }
        return encode(fields)
    }

    private static func encode(_ fields: [(String, String)]) -> Data {
        var output = domain
        for (name, value) in fields {
            append(Data(name.utf8), to: &output)
            append(Data(value.utf8), to: &output)
        }
        return output
    }

    private static func append(_ data: Data, to output: inout Data) {
        var length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
        output.append(data)
    }

    static func isDigest(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:") else { return false }
        let hex = value.dropFirst(7)
        return hex.count == 64 && hex.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

private enum AggregateClaimDecisionError: Error {
    case invalidEvaluationTime, invalidTrustStore, unauthorizedPolicy, invalidSigner
    case signerReturnedInvalidSignature, invalidPredicateInputs, inputLimit
    case bundlePairMismatch, invalidDecision
}

extension AggregateClaimDecisionIssuer {
    fileprivate static func pairDigestsForVerification(_ pairs: [AggregateClaimDecisionInputs.Pair]) -> [AggregateClaimDecision.PairDigest] {
        pairs.map {
            .init(observationPath: $0.observationPath, receiptPath: $0.receiptPath,
                  observationDigest: EvidenceReceiptVerifier.sha256($0.observationData),
                  receiptDigest: EvidenceReceiptVerifier.sha256($0.receiptData))
        }
    }
}
