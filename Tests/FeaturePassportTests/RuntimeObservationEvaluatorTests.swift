import FeaturePassport
import Foundation
import Testing

@Suite("Runtime observation contract matching")
struct RuntimeObservationEvaluatorTests {
    @Test("An exact observation match remains untrusted and is not a receipt")
    func exactMatch() throws {
        let evaluation = try evaluate()
        #expect(evaluation.verdict == .matchedUntrusted)
        #expect(evaluation.matched)
        #expect(evaluation.issues.isEmpty)
    }

    @Test("Passport digest and event name must match exactly")
    func identityMismatch() throws {
        let evaluation = try evaluate(digest: "sha256:other", event: "fp.other")
        #expect(evaluation.verdict == .untrusted)
        #expect(!evaluation.matched)
        #expect(evaluation.issues.filter { $0.code == "identity_mismatch" }.count == 2)
    }

    @Test("Undeclared attributes and implementation elements are rejected")
    func undeclaredEvidence() throws {
        let evaluation = try evaluate(elementID: "external", attributes: ["operation": "run", "secret": "value"])
        #expect(evaluation.verdict == .untrusted)
        #expect(evaluation.issues.contains { $0.code == "attribute_not_allowed" })
        #expect(evaluation.issues.contains { $0.code == "element_not_allowed" })
    }

    @Test("Operation and invocation correlation are enforced when required by the probe")
    func requiredCorrelation() throws {
        let evaluation = try evaluate(runtime: [:])
        #expect(evaluation.verdict == .untrusted)
        #expect(evaluation.issues.filter { $0.code == "missing_runtime_correlation" }.count == 2)
    }

    @Test("An unknown probe cannot be matched")
    func unknownProbe() throws {
        let evaluation = try evaluate(probeID: "missing")
        #expect(evaluation.verdict == .untrusted)
        #expect(evaluation.issues.contains { $0.code == "unknown_probe" })
    }

    @Test("Required observation identity and integrity fields cannot be empty")
    func emptyRequiredEnvelopeField() throws {
        let input = try JSONSerialization.jsonObject(with: observationData()) as! [String: Any]
        var observation = input
        observation["integrity"] = ["event_id": "", "idempotency_key": "key"]
        let evaluation = try RuntimeObservationEvaluator().evaluate(
            passportData: passport(), passportDigest: "sha256:abc",
            observationData: JSONSerialization.data(withJSONObject: observation)
        )
        #expect(evaluation.verdict == .untrusted)
        #expect(evaluation.issues.contains { $0.code == "missing_observation_field" })
    }

    @Test("Delivery provenance survives normalized observation decoding")
    func deliveryProvenanceRoundTrips() throws {
        var observation = try JSONSerialization.jsonObject(with: observationData()) as! [String: Any]
        observation["delivery"] = [
            "environment": "production", "platform": "ios", "git_sha": "abc123",
            "artifact_digest": "sha256:artifact", "release_id": "release-4", "build_number": "4"
        ]
        let decoded = try JSONDecoder().decode(RuntimeObservation.self, from: JSONSerialization.data(withJSONObject: observation))
        let encoded = try JSONEncoder().encode(decoded)
        let delivery = try #require((JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["delivery"] as? [String: Any])
        #expect(delivery["git_sha"] as? String == "abc123")
        #expect(delivery["artifact_digest"] as? String == "sha256:artifact")
        #expect(delivery["release_id"] as? String == "release-4")
        #expect(delivery["build_number"] as? String == "4")
    }

    private func evaluate(
        digest: String = "sha256:abc",
        event: String = "fp.feature.code_path.executed",
        probeID: String = "route.run.v1",
        elementID: String? = "route",
        attributes: [String: String] = ["operation": "run"],
        runtime: [String: Any] = ["operation_id": "op-1", "invocation_id": "inv-1"]
    ) throws -> RuntimeEvaluation {
        var observation: [String: Any] = [
            "artifact_kind": "feature_observation",
            "schema_version": 1,
            "event_name": event,
            "feature_passport": [
                "feature_id": "feature.demo.route", "passport_id": "fp.demo.route",
                "version": "1.0.0", "digest": digest, "probe_id": probeID
            ],
            "delivery": ["environment": "test", "platform": "macos"],
            "runtime": runtime,
            "observation": ["occurred_at": "2026-09-28T20:00:00Z", "result": "success", "attributes": attributes],
            "integrity": ["event_id": "evt-1", "idempotency_key": "test:evt-1"]
        ]
        if let elementID { observation["implementation_element_id"] = elementID }
        return try RuntimeObservationEvaluator().evaluate(passportData: passport(), passportDigest: "sha256:abc",
            observationData: JSONSerialization.data(withJSONObject: observation))
    }

    private func observationData() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "feature_observation", "schema_version": 1,
            "event_name": "fp.feature.code_path.executed",
            "feature_passport": ["feature_id": "feature.demo.route", "passport_id": "fp.demo.route", "version": "1.0.0", "digest": "sha256:abc", "probe_id": "route.run.v1"],
            "delivery": ["environment": "test", "platform": "macos"],
            "runtime": ["operation_id": "op-1", "invocation_id": "inv-1"],
            "observation": ["occurred_at": "2026-09-28T20:00:00Z", "result": "success", "attributes": ["operation": "run"]],
            "integrity": ["event_id": "evt-1", "idempotency_key": "test:evt-1"]
        ])
    }

    private func passport() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "feature_passport", "schema_version": 1,
            "metadata": ["feature_id": "feature.demo.route", "passport_id": "fp.demo.route", "version": "1.0.0", "status": "draft", "issuer": "demo"],
            "spec": [
                "intent": ["summary": "Route", "acceptance_criteria": [["id": "works", "text": "Route works"]]],
                "implementation": [
                    "repositories": [["name": "demo"]],
                    "elements": [["id": "route", "role": "function", "anchors": [[
                        "repository": "demo", "revision": "0123456789abcdef0123456789abcdef01234567",
                        "language": "swift", "module": "Demo", "path": "Sources/Demo/Route.swift", "symbol": "route()"
                    ]]]]
                ],
                "evidence": ["required_level": "L6", "probes": [[
                    "id": "route.run.v1", "event": "fp.feature.code_path.executed", "level": "L6", "required": true,
                    "attributes": ["operation"], "element_ids": ["route"],
                    "required_runtime_fields": ["operation_id", "invocation_id"]
                ]]],
                "privacy": ["pii_allowed": false, "retention_days": 30, "raw_payload_storage": false]
            ]
        ])
    }
}
