import Foundation

/// Provider-neutral normalized runtime observation envelope (FP-RFC-0001 v0.3).
public struct RuntimeObservation: Codable, Equatable, Sendable {
    public struct PassportReference: Codable, Equatable, Sendable {
        public let featureID: String
        public let passportID: String
        public let version: String
        public let digest: String
        public let probeID: String

        enum CodingKeys: String, CodingKey {
            case featureID = "feature_id"
            case passportID = "passport_id"
            case version, digest
            case probeID = "probe_id"
        }
    }

    public struct Delivery: Codable, Equatable, Sendable {
        public let environment: String
        public let platform: String
        public let gitSHA: String?
        public let artifactDigest: String?
        public let releaseID: String?
        public let buildNumber: String?

        enum CodingKeys: String, CodingKey {
            case environment, platform
            case gitSHA = "git_sha"
            case artifactDigest = "artifact_digest"
            case releaseID = "release_id"
            case buildNumber = "build_number"
        }
    }

    public struct Runtime: Codable, Equatable, Sendable {
        public let sessionID: String?
        public let userHash: String?
        public let operationID: String?
        public let invocationID: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case userHash = "user_hash"
            case operationID = "operation_id"
            case invocationID = "invocation_id"
        }
    }

    public struct Observation: Codable, Equatable, Sendable {
        public enum Result: String, Codable, Sendable { case success, failure, neutral }
        public let occurredAt: String
        public let result: Result
        public let attributes: [String: String]

        enum CodingKeys: String, CodingKey {
            case occurredAt = "occurred_at"
            case result, attributes
        }
    }

    public struct Integrity: Codable, Equatable, Sendable {
        public let eventID: String
        public let idempotencyKey: String

        enum CodingKeys: String, CodingKey {
            case eventID = "event_id"
            case idempotencyKey = "idempotency_key"
        }
    }

    public let artifactKind: String
    public let schemaVersion: Int
    public let eventName: String
    public let featurePassport: PassportReference
    public let implementationElementID: String?
    public let delivery: Delivery
    public let runtime: Runtime?
    public let observation: Observation
    public let integrity: Integrity

    enum CodingKeys: String, CodingKey {
        case artifactKind = "artifact_kind"
        case schemaVersion = "schema_version"
        case eventName = "event_name"
        case featurePassport = "feature_passport"
        case implementationElementID = "implementation_element_id"
        case delivery, runtime, observation, integrity
    }
}

public struct RuntimeEvaluation: Codable, Equatable, Sendable {
    /// `matchedUntrusted` means the observation matches the local passport
    /// contract. No cryptographic signature or authority receipt was verified.
    public enum Verdict: String, Codable, Sendable {
        case matchedUntrusted = "matched_untrusted"
        case insufficient
        case untrusted
    }

    public let verdict: Verdict
    public let matched: Bool
    public let issues: [ValidationIssue]
    public let featureID: String?
    public let passportID: String?
    public let probeID: String?
    public let eventID: String?

    public init(verdict: Verdict, matched: Bool, issues: [ValidationIssue], featureID: String?, passportID: String?, probeID: String?, eventID: String?) {
        self.verdict = verdict
        self.matched = matched
        self.issues = issues
        self.featureID = featureID
        self.passportID = passportID
        self.probeID = probeID
        self.eventID = eventID
    }
}

/// Checks a normalized observation against one exact passport version.
/// This is contract matching only; it does not verify signatures, trust policy,
/// delivery attestations, replay windows, or issue evidence receipts.
public struct RuntimeObservationEvaluator: Sendable {
    public init() {}

    public func evaluate(passportData: Data, passportDigest: String, observationData: Data) throws -> RuntimeEvaluation {
        let observation: RuntimeObservation
        do {
            observation = try JSONDecoder().decode(RuntimeObservation.self, from: observationData)
        } catch {
            return RuntimeEvaluation(verdict: .insufficient, matched: false,
                issues: [.init(code: "observation_schema", message: "Observation does not match the normalized envelope: \(error)")],
                featureID: nil, passportID: nil, probeID: nil, eventID: nil)
        }

        let passportIssues = try PassportValidator().validate(passportData)
        guard passportIssues.isEmpty else {
            return result(.insufficient, false, passportIssues.map {
                .init(code: "passport_\($0.code)", message: $0.message)
            }, observation)
        }

        let passport = try JSONDecoder().decode(PassportEnvelope.self, from: passportData)
        let ref = observation.featurePassport
        var issues: [ValidationIssue] = []
        for (name, value) in [
            ("feature_passport.feature_id", ref.featureID),
            ("feature_passport.passport_id", ref.passportID),
            ("feature_passport.version", ref.version),
            ("feature_passport.digest", ref.digest),
            ("feature_passport.probe_id", ref.probeID),
            ("event_name", observation.eventName),
            ("delivery.environment", observation.delivery.environment),
            ("delivery.platform", observation.delivery.platform),
            ("observation.occurred_at", observation.observation.occurredAt),
            ("integrity.event_id", observation.integrity.eventID),
            ("integrity.idempotency_key", observation.integrity.idempotencyKey)
        ] where value.isEmpty {
            issues.append(.init(code: "missing_observation_field", message: "Required field is empty: \(name)"))
        }
        func mismatch(_ condition: Bool, _ field: String) {
            if !condition { issues.append(.init(code: "identity_mismatch", message: "Observation \(field) does not match the exact passport/probe declaration")) }
        }

        mismatch(observation.artifactKind == "feature_observation", "artifact_kind")
        mismatch(observation.schemaVersion == 1, "schema_version")
        mismatch(ref.featureID == passport.metadata.featureID, "feature_id")
        mismatch(ref.passportID == passport.metadata.passportID, "passport_id")
        mismatch(ref.version == passport.metadata.version, "version")
        // Equality binds the observation to the supplied digest string only. The
        // digest and passport signature are not cryptographically verified here.
        mismatch(!passportDigest.isEmpty && ref.digest == passportDigest, "digest")

        guard let probe = passport.spec.evidence.probes.first(where: { $0.id == ref.probeID }) else {
            issues.append(.init(code: "unknown_probe", message: "Probe ID is not declared by this passport"))
            return result(.untrusted, false, issues, observation)
        }
        mismatch(observation.eventName == probe.event, "event_name")

        let suppliedAttributes = Set(observation.observation.attributes.keys)
        let allowedAttributes = Set(probe.attributes ?? [])
        for key in suppliedAttributes.subtracting(allowedAttributes).sorted() {
            issues.append(.init(code: "attribute_not_allowed", message: "Attribute is not allowlisted by probe: \(key)"))
        }

        if let elementID = observation.implementationElementID {
            let declaredElements = Set(probe.elementIDs ?? [])
            if !declaredElements.contains(elementID) {
                issues.append(.init(code: "element_not_allowed", message: "Implementation element is not declared by this probe: \(elementID)"))
            }
        }
        let requiredRuntimeFields = Set(probe.requiredRuntimeFields ?? [])
        for field in requiredRuntimeFields.sorted() {
            let value = field == "operation_id" ? observation.runtime?.operationID : observation.runtime?.invocationID
            if value?.isEmpty != false {
                issues.append(.init(code: "missing_runtime_correlation", message: "Probe requires nonempty runtime.\(field)"))
            }
        }
        if observation.runtime?.operationID == "" || observation.runtime?.invocationID == "" {
            issues.append(.init(code: "invalid_runtime_correlation", message: "Runtime correlation identifiers must be nonempty when supplied"))
        }
        guard issues.isEmpty else { return result(.untrusted, false, issues, observation) }
        return result(.matchedUntrusted, true, [], observation)
    }

    private func result(_ verdict: RuntimeEvaluation.Verdict, _ matched: Bool, _ issues: [ValidationIssue], _ observation: RuntimeObservation) -> RuntimeEvaluation {
        RuntimeEvaluation(verdict: verdict, matched: matched, issues: issues,
            featureID: observation.featurePassport.featureID,
            passportID: observation.featurePassport.passportID,
            probeID: observation.featurePassport.probeID,
            eventID: observation.integrity.eventID)
    }
}

private struct PassportEnvelope: Decodable {
    let metadata: Metadata
    let spec: Spec
    enum CodingKeys: String, CodingKey { case metadata, spec }
}
private struct Metadata: Decodable {
    let featureID: String
    let passportID: String
    let version: String
    enum CodingKeys: String, CodingKey { case featureID = "feature_id", passportID = "passport_id", version }
}
private struct Spec: Decodable { let evidence: Evidence }
private struct Evidence: Decodable { let probes: [Probe] }
private struct Probe: Decodable {
    let id: String
    let event: String
    let attributes: [String]?
    let elementIDs: [String]?
    let requiredRuntimeFields: [String]?
    enum CodingKeys: String, CodingKey {
        case id, event, attributes
        case elementIDs = "element_ids"
        case requiredRuntimeFields = "required_runtime_fields"
    }
}
