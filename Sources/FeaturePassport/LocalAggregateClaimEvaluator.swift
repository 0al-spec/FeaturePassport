import Foundation

/// A deliberately local, unsigned claim policy. Its digest is the SHA-256 of
/// the exact policy JSON bytes supplied to the evaluator.
struct LocalAggregateClaimPolicy: Codable, Equatable, Sendable {
    struct PassportIdentity: Codable, Equatable, Sendable {
        let featureID: String
        let passportID: String
        let version: String
        let digest: String

        enum CodingKeys: String, CodingKey {
            case featureID = "feature_id"
            case passportID = "passport_id"
            case version, digest
        }

        init(featureID: String, passportID: String, version: String, digest: String) {
            self.featureID = featureID
            self.passportID = passportID
            self.version = version
            self.digest = digest
        }
    }

    struct ReceiptPolicy: Codable, Equatable, Sendable {
        let authorityID: String
        let policyID: String
        let policyVersion: String
        let policyDigest: String

        enum CodingKeys: String, CodingKey {
            case authorityID = "authority_id"
            case policyID = "policy_id"
            case policyVersion = "policy_version"
            case policyDigest = "policy_digest"
        }

        init(authorityID: String, policyID: String, policyVersion: String, policyDigest: String) {
            self.authorityID = authorityID
            self.policyID = policyID
            self.policyVersion = policyVersion
            self.policyDigest = policyDigest
        }
    }

    struct OrderedProbe: Codable, Equatable, Sendable {
        let probeID: String
        let allowedResults: [RuntimeObservation.Observation.Result]

        enum CodingKeys: String, CodingKey {
            case probeID = "probe_id"
            case allowedResults = "allowed_results"
        }

        init(probeID: String, allowedResults: [RuntimeObservation.Observation.Result]) {
            self.probeID = probeID
            self.allowedResults = allowedResults
        }
    }

    let artifactKind: String
    let schemaVersion: Int
    let policyID: String
    let policyVersion: String
    let claimID: String
    let featurePassport: PassportIdentity
    let receiptPolicy: ReceiptPolicy
    let environment: String
    let sequenceAttribute: String
    let orderedProbes: [OrderedProbe]

    enum CodingKeys: String, CodingKey {
        case artifactKind = "artifact_kind"
        case schemaVersion = "schema_version"
        case policyID = "policy_id"
        case policyVersion = "policy_version"
        case claimID = "claim_id"
        case featurePassport = "feature_passport"
        case receiptPolicy = "receipt_policy"
        case environment
        case sequenceAttribute = "sequence_attribute"
        case orderedProbes = "ordered_probes"
    }
}

/// One observation and its candidate authority receipt for fresh verification.
public struct LocalAggregateClaimPair: Sendable {
    /// The exact normalized observation JSON bytes.
    public let observationData: Data
    /// The exact receipt JSON bytes to verify against the observation.
    public let receiptData: Data

    /// Creates a pair from exact observation and receipt bytes.
    ///
    /// - Parameters:
    ///   - observationData: The normalized observation document bytes.
    ///   - receiptData: The associated signed receipt document bytes.
    public init(observationData: Data, receiptData: Data) {
        self.observationData = observationData
        self.receiptData = receiptData
    }
}

/// File references for the CLI's local observation/receipt input bundle.
public struct LocalAggregateClaimBundle: Codable, Equatable, Sendable {
    /// One observation and receipt file path in a local bundle document.
    public struct PairReference: Codable, Equatable, Sendable {
        /// The path to the normalized observation JSON file.
        public let observation: String
        /// The path to the signed receipt JSON file.
        public let receipt: String

        /// Creates one observation/receipt path pair.
        ///
        /// - Parameters:
        ///   - observation: The observation path.
        ///   - receipt: The receipt path.
        public init(observation: String, receipt: String) {
            self.observation = observation
            self.receipt = receipt
        }
    }

    /// The bundle discriminator, `local_aggregate_claim_bundle`.
    public let artifactKind: String
    /// The supported bundle schema version, `1`.
    public let schemaVersion: Int
    /// Observation/receipt file pairs supplied by the caller.
    public let pairs: [PairReference]

    enum CodingKeys: String, CodingKey {
        case artifactKind = "artifact_kind"
        case schemaVersion = "schema_version"
        case pairs
    }

    /// Decodes a strict v1 bundle with unique JSON member names and bounded size.
    ///
    /// - Parameter data: The exact bundle JSON bytes.
    /// - Returns: The decoded local bundle.
    /// - Throws: If the bundle is malformed, ambiguous, or outside profile bounds.
    public static func decode(from data: Data) throws -> LocalAggregateClaimBundle {
        guard data.count <= 256_000 else { throw AggregateClaimPolicyError.invalidBundle }
        try JSONMemberUniqueness.validate(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["artifact_kind", "schema_version", "pairs"]),
              let pairs = root["pairs"] as? [[String: Any]], pairs.count <= 64,
              pairs.allSatisfy({ Set($0.keys) == Set(["observation", "receipt"]) }) else {
            throw AggregateClaimPolicyError.invalidBundle
        }
        let bundle = try JSONDecoder().decode(LocalAggregateClaimBundle.self, from: data)
        guard bundle.artifactKind == "local_aggregate_claim_bundle", bundle.schemaVersion == 1,
              !bundle.pairs.isEmpty,
              bundle.pairs.allSatisfy({ !$0.observation.isEmpty && !$0.receipt.isEmpty }) else {
            throw AggregateClaimPolicyError.invalidBundle
        }
        return bundle
    }
}

public struct LocalAggregateClaimEvaluation: Codable, Equatable, Sendable {
    /// The exact local predicate result without an authority acceptance claim.
    public enum Verdict: String, Codable, Sendable {
        /// Every requirement in the supplied local policy matched.
        case localPredicateSatisfied = "local_predicate_satisfied"
        /// One or more requirements in the supplied local policy failed.
        case localPredicateNotSatisfied = "local_predicate_not_satisfied"
    }

    /// The output discriminator, `local_aggregate_claim_evaluation`.
    public let artifactKind: String
    /// The output schema version, `1`.
    public let schemaVersion: Int
    /// Whether this local report has an authority signature; always `false`.
    public let signed: Bool
    /// Whether a durable replay ledger was consulted; always `false`.
    public let replayProtection: Bool
    /// The bounded local predicate verdict.
    public let verdict: Verdict
    /// Whether the exact predicate in the supplied local policy was satisfied.
    public let satisfied: Bool
    /// The claim identifier from the unsigned local policy.
    public let claimID: String?
    /// The local policy identifier.
    public let policyID: String?
    /// The local policy version.
    public let policyVersion: String?
    /// SHA-256 digest of exact local policy input bytes.
    public let policyDigest: String?
    /// The bound passport feature identity.
    public let featureID: String?
    /// The bound passport identity.
    public let passportID: String?
    /// The bound passport version.
    public let passportVersion: String?
    /// SHA-256 digest of the exact passport input bytes.
    public let passportDigest: String?
    /// The exact authority identity required by policy, when available.
    public let evidenceAuthorityID: String?
    /// The exact evidence policy identifier required by policy, when available.
    public let evidencePolicyID: String?
    /// The exact evidence policy version required by policy, when available.
    public let evidencePolicyVersion: String?
    /// The exact evidence policy digest required by policy, when available.
    public let evidencePolicyDigest: String?
    /// The exact environment required by policy.
    public let environment: String?
    /// Number of observation/receipt pairs supplied for evaluation.
    public let observationCount: Int
    /// Stable, sorted diagnostics explaining an unsatisfied predicate.
    public let issues: [ValidationIssue]

    enum CodingKeys: String, CodingKey {
        case artifactKind = "artifact_kind"
        case schemaVersion = "schema_version"
        case signed
        case replayProtection = "replay_protection"
        case verdict, satisfied
        case claimID = "claim_id"
        case policyID = "policy_id"
        case policyVersion = "policy_version"
        case policyDigest = "policy_digest"
        case featureID = "feature_id"
        case passportID = "passport_id"
        case passportVersion = "passport_version"
        case passportDigest = "passport_digest"
        case evidenceAuthorityID = "evidence_authority_id"
        case evidencePolicyID = "evidence_policy_id"
        case evidencePolicyVersion = "evidence_policy_version"
        case evidencePolicyDigest = "evidence_policy_digest"
        case environment
        case observationCount = "observation_count"
        case issues
    }

    init(satisfied: Bool, claimID: String?, policyID: String?, policyVersion: String?,
                policyDigest: String?, featureID: String?, passportID: String?, passportVersion: String?,
                passportDigest: String?, evidenceAuthorityID: String?, evidencePolicyID: String?,
                evidencePolicyVersion: String?, evidencePolicyDigest: String?, environment: String?,
                observationCount: Int, issues: [ValidationIssue]) {
        self.artifactKind = "local_aggregate_claim_evaluation"
        self.schemaVersion = 1
        self.signed = false
        self.replayProtection = false
        self.verdict = satisfied ? .localPredicateSatisfied : .localPredicateNotSatisfied
        self.satisfied = satisfied
        self.claimID = claimID
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.policyDigest = policyDigest
        self.featureID = featureID
        self.passportID = passportID
        self.passportVersion = passportVersion
        self.passportDigest = passportDigest
        self.evidenceAuthorityID = evidenceAuthorityID
        self.evidencePolicyID = evidencePolicyID
        self.evidencePolicyVersion = evidencePolicyVersion
        self.evidencePolicyDigest = evidencePolicyDigest
        self.environment = environment
        self.observationCount = observationCount
        self.issues = issues
    }
}

/// Re-verifies every receipt and evaluates one explicit, ordered local policy.
/// This is not an issuer, replay ledger, or runtime/outcome authority.
public struct LocalAggregateClaimEvaluator: Sendable {
    /// Creates a local aggregate claim evaluator.
    public init() {}

    /// Re-verifies every receipt and evaluates the exact unsigned local policy.
    ///
    /// - Parameters:
    ///   - passportData: Exact Feature Passport JSON bytes.
    ///   - policyData: Exact local aggregate claim policy v1 JSON bytes.
    ///   - pairs: Observation/receipt byte pairs, each of which is verified afresh.
    ///   - trustStore: The caller-supplied offline receipt trust store.
    ///   - verificationTime: The time used to verify receipt validity windows.
    /// - Returns: A deterministic unsigned local predicate report.
    /// - Throws: If an internal passport or receipt verifier operation cannot complete.
    public func evaluate(passportData: Data, policyData: Data, pairs: [LocalAggregateClaimPair],
                         trustStore: EvidenceReceiptTrustStore,
                         verificationTime: Date = Date()) throws -> LocalAggregateClaimEvaluation {
        guard passportData.count <= 10_000_000, policyData.count <= 256_000, pairs.count <= 64 else {
            return failure(code: "size_limit", message: "Passport exceeds 10 MB, policy exceeds 256 KB, or bundle exceeds 64 pairs", pairCount: pairs.count)
        }
        let pairBytes = pairs.reduce(0) { $0 + $1.observationData.count + $1.receiptData.count }
        guard pairBytes <= 64_000_000 else {
            return failure(code: "size_limit", message: "Bundle inputs exceed the 64 MB aggregate size limit", pairCount: pairs.count)
        }

        let policy: LocalAggregateClaimPolicy
        do {
            try JSONMemberUniqueness.validate(policyData)
            try Self.validatePolicyEnvelope(policyData)
            policy = try JSONDecoder().decode(LocalAggregateClaimPolicy.self, from: policyData)
            try Self.validatePolicySemantics(policy)
        } catch {
            return failure(code: "claim_policy_invalid", message: "Local aggregate claim policy is malformed or outside profile v1", pairCount: pairs.count)
        }

        let policyDigest = EvidenceReceiptVerifier.sha256(policyData)
        let passportDigest = EvidenceReceiptVerifier.sha256(passportData)
        var issues: [ValidationIssue] = []

        do {
            try JSONMemberUniqueness.validate(passportData)
            issues += try PassportValidator().validate(passportData)
        } catch {
            issues.append(.init(code: "passport_invalid", message: "Passport validation could not complete: \(error)"))
        }
        let passportIdentity = Self.passportIdentity(from: passportData)
        if passportDigest != policy.featurePassport.digest {
            issues.append(.init(code: "passport_digest_mismatch", message: "Exact passport input digest does not match claim policy"))
        }
        if let passportIdentity {
            if passportIdentity.featureID != policy.featurePassport.featureID ||
                passportIdentity.passportID != policy.featurePassport.passportID ||
                passportIdentity.version != policy.featurePassport.version {
                issues.append(.init(code: "passport_identity_mismatch", message: "Passport metadata does not match claim policy identity"))
            }
        } else {
            issues.append(.init(code: "passport_identity_missing", message: "Passport feature/passport/version identity is unavailable"))
        }

        let expectedProbeIDs = policy.orderedProbes.map(\.probeID)
        if pairs.count != expectedProbeIDs.count {
            issues.append(.init(code: "bundle_cardinality_mismatch", message: "Bundle must contain exactly one pair for every ordered probe"))
        }

        var observationsByProbe: [String: RuntimeObservation] = [:]
        var eventIDs = Set<String>()
        var receiptIDs = Set<String>()
        var operationID: String?
        var evidenceAuthorityID: String?
        var evidencePolicyID: String?
        var evidencePolicyVersion: String?
        var evidencePolicyDigest: String?
        let verifier = EvidenceReceiptVerifier()

        for (index, pair) in pairs.enumerated() {
            let prefix = "pair[\(index)]"
            let verification: EvidenceReceiptVerificationReport
            do {
                verification = try verifier.verify(passportData: passportData,
                    observationData: pair.observationData, receiptData: pair.receiptData,
                    trustStore: trustStore, verificationTime: verificationTime)
            } catch {
                issues.append(.init(code: "receipt_verification_error", message: "\(prefix): receipt verifier could not complete: \(error)"))
                continue
            }
            if !verification.trusted {
                for issue in verification.issues {
                    issues.append(.init(code: "receipt_\(issue.code)", message: "\(prefix): \(issue.message)"))
                }
            }
            if let receiptID = verification.receiptID, !receiptIDs.insert(receiptID).inserted {
                issues.append(.init(code: "duplicate_receipt_id", message: "\(prefix): receipt ID is repeated in the bundle"))
            }
            if let authorityID = verification.authorityID {
                if let evidenceAuthorityID, evidenceAuthorityID != authorityID {
                    issues.append(.init(code: "receipt_authority_mismatch", message: "\(prefix): receipt authority differs within the bundle"))
                } else {
                    evidenceAuthorityID = authorityID
                }
                if authorityID != policy.receiptPolicy.authorityID {
                    issues.append(.init(code: "receipt_authority_mismatch", message: "\(prefix): receipt authority does not match claim policy"))
                }
            }
            let receiptPolicyIdentity: ReceiptPolicyIdentity?
            if verification.trusted,
               (try? JSONMemberUniqueness.validate(pair.receiptData)) != nil,
               let document = try? JSONDecoder().decode(ReceiptPolicyEnvelope.self, from: pair.receiptData) {
                receiptPolicyIdentity = document.authority
            } else {
                receiptPolicyIdentity = nil
            }
            if verification.trusted && receiptPolicyIdentity == nil {
                issues.append(.init(code: "receipt_policy_unavailable", message: "\(prefix): verified receipt policy fields could not be read"))
            }
            if let policyID = receiptPolicyIdentity?.policyID {
                if let evidencePolicyID, evidencePolicyID != policyID {
                    issues.append(.init(code: "receipt_policy_mismatch", message: "\(prefix): receipt policy ID differs within the bundle"))
                } else {
                    evidencePolicyID = policyID
                }
                if policyID != policy.receiptPolicy.policyID {
                    issues.append(.init(code: "receipt_policy_mismatch", message: "\(prefix): receipt policy ID does not match claim policy"))
                }
            }
            if let policyVersion = receiptPolicyIdentity?.policyVersion {
                if let evidencePolicyVersion, evidencePolicyVersion != policyVersion {
                    issues.append(.init(code: "receipt_policy_mismatch", message: "\(prefix): receipt policy version differs within the bundle"))
                } else {
                    evidencePolicyVersion = policyVersion
                }
                if policyVersion != policy.receiptPolicy.policyVersion {
                    issues.append(.init(code: "receipt_policy_mismatch", message: "\(prefix): receipt policy version does not match claim policy"))
                }
            }
            if let policyDigest = verification.policyDigest {
                if let evidencePolicyDigest, evidencePolicyDigest != policyDigest {
                    issues.append(.init(code: "receipt_policy_mismatch", message: "\(prefix): receipt policy digest differs within the bundle"))
                } else {
                    evidencePolicyDigest = policyDigest
                }
                if policyDigest != policy.receiptPolicy.policyDigest || receiptPolicyIdentity?.policyDigest != policyDigest {
                    issues.append(.init(code: "receipt_policy_mismatch", message: "\(prefix): receipt policy digest does not match claim policy"))
                }
            }

            let observation: RuntimeObservation
            do {
                try JSONMemberUniqueness.validate(pair.observationData)
                observation = try JSONDecoder().decode(RuntimeObservation.self, from: pair.observationData)
            } catch {
                issues.append(.init(code: "observation_schema", message: "\(prefix): observation is malformed: \(error)"))
                continue
            }

            let probeID = observation.featurePassport.probeID
            if observationsByProbe.updateValue(observation, forKey: probeID) != nil {
                issues.append(.init(code: "duplicate_probe", message: "\(prefix): probe ID is repeated in the bundle: \(probeID)"))
            }
            if !expectedProbeIDs.contains(probeID) {
                issues.append(.init(code: "unexpected_probe", message: "\(prefix): probe ID is not required by claim policy: \(probeID)"))
            }
            if !eventIDs.insert(observation.integrity.eventID).inserted {
                issues.append(.init(code: "duplicate_event_id", message: "\(prefix): event ID is repeated in the bundle"))
            }
            if observation.featurePassport.featureID != policy.featurePassport.featureID ||
                observation.featurePassport.passportID != policy.featurePassport.passportID ||
                observation.featurePassport.version != policy.featurePassport.version ||
                observation.featurePassport.digest != passportDigest {
                issues.append(.init(code: "observation_passport_mismatch", message: "\(prefix): observation is not bound to the exact claim passport"))
            }
            if observation.delivery.environment != policy.environment {
                issues.append(.init(code: "environment_mismatch", message: "\(prefix): observation environment does not match claim policy"))
            }
            guard let observedOperationID = observation.runtime?.operationID, !observedOperationID.isEmpty else {
                issues.append(.init(code: "operation_id_missing", message: "\(prefix): observation requires a nonempty runtime.operation_id"))
                continue
            }
            if let operationID, operationID != observedOperationID {
                issues.append(.init(code: "operation_id_mismatch", message: "\(prefix): observation operation_id differs within the bundle"))
            } else {
                operationID = observedOperationID
            }
            guard let sequenceText = observation.observation.attributes[policy.sequenceAttribute],
                  Self.parseCanonicalUInt64(sequenceText) != nil else {
                issues.append(.init(code: "sequence_invalid", message: "\(prefix): required attribute '\(policy.sequenceAttribute)' must be canonical UInt64 decimal"))
                continue
            }
            if let probePolicy = policy.orderedProbes.first(where: { $0.probeID == probeID }),
               !probePolicy.allowedResults.contains(observation.observation.result) {
                issues.append(.init(code: "result_not_allowed", message: "\(prefix): observation result is not allowed for probe \(probeID)"))
            }
            // `sequence` is extracted from the signed observation digest; it is
            // not derived from receipt time or caller-provided pair ordering.
        }

        for probeID in expectedProbeIDs where observationsByProbe[probeID] == nil {
            issues.append(.init(code: "required_probe_missing", message: "Required probe is missing: \(probeID)"))
        }

        var previousSequence: UInt64?
        var seenSequences = Set<UInt64>()
        for probePolicy in policy.orderedProbes {
            guard let observation = observationsByProbe[probePolicy.probeID],
                  let text = observation.observation.attributes[policy.sequenceAttribute],
                  let sequence = Self.parseCanonicalUInt64(text) else { continue }
            if !seenSequences.insert(sequence).inserted {
                issues.append(.init(code: "sequence_duplicate", message: "Sequence values must be unique across the required ordered probes"))
            }
            if let previousSequence, sequence <= previousSequence {
                issues.append(.init(code: "sequence_not_increasing", message: "Sequence values must strictly increase in policy probe order"))
            }
            previousSequence = sequence
        }

        let sortedIssues = Self.sorted(issues)
        let satisfied = sortedIssues.isEmpty
        return LocalAggregateClaimEvaluation(satisfied: satisfied, claimID: policy.claimID,
            policyID: policy.policyID, policyVersion: policy.policyVersion, policyDigest: policyDigest,
            featureID: policy.featurePassport.featureID, passportID: policy.featurePassport.passportID,
            passportVersion: policy.featurePassport.version, passportDigest: passportDigest,
            evidenceAuthorityID: evidenceAuthorityID, evidencePolicyID: evidencePolicyID,
            evidencePolicyVersion: evidencePolicyVersion, evidencePolicyDigest: evidencePolicyDigest,
            environment: policy.environment, observationCount: pairs.count, issues: sortedIssues)
    }

    private func failure(code: String, message: String, pairCount: Int) -> LocalAggregateClaimEvaluation {
        LocalAggregateClaimEvaluation(satisfied: false, claimID: nil, policyID: nil, policyVersion: nil,
            policyDigest: nil, featureID: nil, passportID: nil, passportVersion: nil, passportDigest: nil,
            evidenceAuthorityID: nil, evidencePolicyID: nil, evidencePolicyVersion: nil,
            evidencePolicyDigest: nil, environment: nil, observationCount: pairCount,
            issues: [.init(code: code, message: message)])
    }

    private static func validatePolicyEnvelope(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["artifact_kind", "schema_version", "policy_id", "policy_version", "claim_id", "feature_passport", "receipt_policy", "environment", "sequence_attribute", "ordered_probes"]),
              let passport = root["feature_passport"] as? [String: Any],
              Set(passport.keys) == Set(["feature_id", "passport_id", "version", "digest"]),
              let receiptPolicy = root["receipt_policy"] as? [String: Any],
              Set(receiptPolicy.keys) == Set(["authority_id", "policy_id", "policy_version", "policy_digest"]),
              let probes = root["ordered_probes"] as? [[String: Any]],
              probes.allSatisfy({ Set($0.keys) == Set(["probe_id", "allowed_results"]) }) else {
            throw AggregateClaimPolicyError.invalidEnvelope
        }
    }

    private static func validatePolicySemantics(_ policy: LocalAggregateClaimPolicy) throws {
        guard policy.artifactKind == "local_aggregate_claim_policy", policy.schemaVersion == 1,
              ![policy.policyID, policy.policyVersion, policy.claimID,
                policy.featurePassport.featureID, policy.featurePassport.passportID,
                policy.featurePassport.version, policy.featurePassport.digest,
                policy.receiptPolicy.authorityID, policy.receiptPolicy.policyID,
                policy.receiptPolicy.policyVersion, policy.receiptPolicy.policyDigest,
                policy.environment, policy.sequenceAttribute].contains(where: \.isEmpty),
              policy.orderedProbes.count >= 2, policy.orderedProbes.count <= 64,
              policy.orderedProbes.allSatisfy({ !$0.probeID.isEmpty && !$0.allowedResults.isEmpty }),
              Set(policy.orderedProbes.map(\.probeID)).count == policy.orderedProbes.count,
              policy.orderedProbes.allSatisfy({ Set($0.allowedResults).count == $0.allowedResults.count }),
              isSHA256Digest(policy.featurePassport.digest), isSHA256Digest(policy.receiptPolicy.policyDigest) else {
            throw AggregateClaimPolicyError.invalidSemantics
        }
    }

    private static func passportIdentity(from data: Data) -> (featureID: String, passportID: String, version: String)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = root["metadata"] as? [String: Any],
              let featureID = metadata["feature_id"] as? String,
              let passportID = metadata["passport_id"] as? String,
              let version = metadata["version"] as? String else { return nil }
        return (featureID, passportID, version)
    }

    private static func parseCanonicalUInt64(_ value: String) -> UInt64? {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.allSatisfy({ (48...57).contains($0) }),
              bytes.count == 1 || bytes.first != 48,
              let parsed = UInt64(value), String(parsed) == value else { return nil }
        return parsed
    }

    private static func isSHA256Digest(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:") else { return false }
        let digits = value.dropFirst("sha256:".count)
        return digits.count == 64 && digits.allSatisfy({ "0123456789abcdef".contains($0) })
    }

    private static func sorted(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.sorted { ($0.code, $0.message) < ($1.code, $1.message) }
    }
}

private enum AggregateClaimPolicyError: Error {
    case invalidEnvelope
    case invalidSemantics
    case invalidBundle
}

private struct ReceiptPolicyEnvelope: Decodable {
    let authority: ReceiptPolicyIdentity
}

private struct ReceiptPolicyIdentity: Decodable {
    let id: String
    let policyID: String
    let policyVersion: String
    let policyDigest: String

    var authorityID: String { id }

    enum CodingKeys: String, CodingKey {
        case id
        case policyID = "policy_id"
        case policyVersion = "policy_version"
        case policyDigest = "policy_digest"
    }
}
