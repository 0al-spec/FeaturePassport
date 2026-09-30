import Crypto
import Foundation

/// Caller-owned signing capability. No key generation, storage or trust installation.
public protocol EvidenceReceiptSigner: Sendable {
    var publicKey: Data { get }
    func sign(message: Data) throws -> Data
}

public struct EvidenceReceiptIssuanceRequest: Codable, Sendable {
    public let receiptID: String
    public let acceptedAt: String
    public let validFrom: String
    public let validUntil: String

    public init(receiptID: String, acceptedAt: String, validFrom: String, validUntil: String) {
        self.receiptID = receiptID
        self.acceptedAt = acceptedAt
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
    enum CodingKeys: String, CodingKey {
        case receiptID = "receipt_id", acceptedAt = "accepted_at"
        case validFrom = "valid_from", validUntil = "valid_until"
    }
    public static func decode(from data: Data) throws -> Self {
        guard data.count <= 16_384 else { throw EvidenceReceiptIssuanceError.invalidRequest }
        try JSONMemberUniqueness.validate(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["receipt_id", "accepted_at", "valid_from", "valid_until"]) else {
            throw EvidenceReceiptIssuanceError.invalidRequest
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

public enum EvidenceReceiptIssuanceError: Error {
    case invalidPolicy, unauthorizedPolicy, invalidRequest, invalidSigner
    case observationRejected, preflightRejected, signingFailed, signatureRejected
}

/// Issues only acceptance of an exact contract-matched observation. It does not
/// attest execution origin, production delivery, successful execution or outcomes.
public struct EvidenceReceiptIssuer: Sendable {
    public init() {}

    public func issue(passportData: Data, observationData: Data, policyData: Data,
                      authorization: EvidenceReceiptTrustedKey,
                      request: EvidenceReceiptIssuanceRequest,
                      signer: any EvidenceReceiptSigner) throws -> Data {
        let policy: ObservationReceiptPolicy
        do { policy = try ObservationReceiptPolicy.decode(policyData) }
        catch { throw EvidenceReceiptIssuanceError.invalidPolicy }
        guard authorization.policyID == policy.policyID,
              authorization.policyVersion == policy.policyVersion,
              authorization.policyDigest == EvidenceReceiptVerifier.sha256(policyData) else {
            throw EvidenceReceiptIssuanceError.unauthorizedPolicy
        }
        guard let key = Data(base64Encoded: authorization.publicKey), key.count == 32,
              signer.publicKey == key else { throw EvidenceReceiptIssuanceError.invalidSigner }
        guard !request.receiptID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.receiptID.utf8.count <= 1024,
              let at = EvidenceReceiptTimestamp.parseRFC3339UTC(request.acceptedAt),
              let keyFrom = EvidenceReceiptTimestamp.parseRFC3339UTC(authorization.validFrom),
              let keyUntil = EvidenceReceiptTimestamp.parseRFC3339UTC(authorization.validUntil),
              keyFrom < keyUntil else { throw EvidenceReceiptIssuanceError.invalidRequest }
        guard passportData.count <= 10_000_000, observationData.count <= 10_000_000 else {
            throw EvidenceReceiptIssuanceError.observationRejected
        }
        let observation: RuntimeObservation
        do {
            try JSONMemberUniqueness.validate(passportData)
            try JSONMemberUniqueness.validate(observationData)
            observation = try JSONDecoder().decode(RuntimeObservation.self, from: observationData)
            let evaluation = try RuntimeObservationEvaluator().evaluate(passportData: passportData,
                passportDigest: EvidenceReceiptVerifier.sha256(passportData), observationData: observationData)
            guard evaluation.matched, evaluation.verdict == .matchedUntrusted,
                  policy.allowedEnvironments.contains(observation.delivery.environment) else {
                throw EvidenceReceiptIssuanceError.observationRejected
            }
        } catch { throw EvidenceReceiptIssuanceError.observationRejected }
        let store = EvidenceReceiptTrustStore(trustedKeys: [authorization],
            maximumReceiptLifetimeSeconds: policy.maximumReceiptLifetimeSeconds, clockSkewSeconds: 0)
        func document(hash: String, signature: Data) -> ReceiptDocument {
            ReceiptDocument(artifactKind: "evidence_receipt", schemaVersion: 1,
                authority: .init(id: authorization.authorityID, policyID: policy.policyID,
                    policyVersion: policy.policyVersion, policyDigest: authorization.policyDigest),
                featurePassport: .init(featureID: observation.featurePassport.featureID,
                    passportID: observation.featurePassport.passportID, version: observation.featurePassport.version,
                    digest: EvidenceReceiptVerifier.sha256(passportData)),
                probe: .init(id: observation.featurePassport.probeID, eventName: observation.eventName),
                observation: .init(eventID: observation.integrity.eventID, occurredAt: observation.observation.occurredAt),
                receiptID: request.receiptID, acceptedClaims: [],
                hashing: .init(canonicalization: ReceiptSigningProfile.identifier,
                    digestProfile: ReceiptSigningProfile.digestIdentifier,
                    eventHash: EvidenceReceiptVerifier.sha256(observationData), receiptHash: hash),
                signature: .init(algorithm: "Ed25519", keyID: authorization.keyID, value: signature.base64EncodedString()),
                timestamps: .init(acceptedAt: request.acceptedAt, validFrom: request.validFrom, validUntil: request.validUntil))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let placeholder = Data(repeating: 0, count: 64)
        let unsigned = document(hash: "", signature: placeholder)
        let hashBytes = Data(SHA256.hash(data: ReceiptSigningProfile.payload(fields: unsigned.signingFields)))
        let hash = "sha256:" + hashBytes.map { String(format: "%02x", $0) }.joined()
        let prepared = try encoder.encode(document(hash: hash, signature: placeholder))
        // Reuse the complete verifier preflight. Only the absent signature may fail.
        let preflight = try EvidenceReceiptVerifier().verify(passportData: passportData,
            observationData: observationData, receiptData: prepared, trustStore: store, verificationTime: at)
        guard preflight.issues.map(\.code) == ["signature_invalid"] else {
            throw EvidenceReceiptIssuanceError.preflightRejected
        }
        let signature: Data
        do { signature = try signer.sign(message: hashBytes) }
        catch { throw EvidenceReceiptIssuanceError.signingFailed }
        guard signature.count == 64 else { throw EvidenceReceiptIssuanceError.signatureRejected }
        let result = try encoder.encode(document(hash: hash, signature: signature))
        let verified = try EvidenceReceiptVerifier().verify(passportData: passportData,
            observationData: observationData, receiptData: result, trustStore: store, verificationTime: at)
        guard verified.trusted else { throw EvidenceReceiptIssuanceError.signatureRejected }
        return result
    }
}

private struct ObservationReceiptPolicy: Decodable {
    let schemaVersion: Int
    let policyID: String
    let policyVersion: String
    let allowedEnvironments: [String]
    let maximumReceiptLifetimeSeconds: Int64
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case policyID = "policy_id", policyVersion = "policy_version"
        case allowedEnvironments = "allowed_environments"
        case maximumReceiptLifetimeSeconds = "maximum_receipt_lifetime_seconds"
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 256_000 else { throw EvidenceReceiptIssuanceError.invalidPolicy }
        try JSONMemberUniqueness.validate(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["artifact_kind", "schema_version", "policy_id", "policy_version",
                                    "predicate_profile", "allowed_environments", "maximum_receipt_lifetime_seconds"]),
              root["artifact_kind"] as? String == "observation_receipt_policy",
              root["schema_version"] as? Int == 1,
              root["predicate_profile"] as? String == "exact_contract_match_v1" else {
            throw EvidenceReceiptIssuanceError.invalidPolicy
        }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, !value.policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.policyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.allowedEnvironments.isEmpty, value.allowedEnvironments.count <= 64,
              Set(value.allowedEnvironments).count == value.allowedEnvironments.count,
              ([value.policyID, value.policyVersion] + value.allowedEnvironments).allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 128
              }), (1...2_592_000).contains(value.maximumReceiptLifetimeSeconds) else {
            throw EvidenceReceiptIssuanceError.invalidPolicy
        }
        return value
    }
}
