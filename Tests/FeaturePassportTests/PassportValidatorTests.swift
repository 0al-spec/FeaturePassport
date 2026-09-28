import FeaturePassport
import Foundation
import Testing

@Suite("Feature Passport validation")
struct PassportValidatorTests {
    @Test("A local passport is valid without SpecGraph or another provider")
    func validWithoutProvider() throws {
        let issues = try PassportValidator().validate(passport())
        #expect(issues.isEmpty)
    }

    @Test("The JSON Schema rejects a missing feature identity")
    func missingFeatureIdentity() throws {
        let issues = try PassportValidator().validate(passport(featureID: nil))
        #expect(issues.contains { $0.code == "schema" })
    }

    @Test("Duplicate implementation IDs are rejected")
    func duplicateElementID() throws {
        let issues = try PassportValidator().validate(passport(elementIDs: ["composition", "composition"]))
        #expect(issues.contains { $0.code == "duplicate_id" })
    }

    @Test("A binding cannot point to a missing implementation element")
    func missingBindingTarget() throws {
        let issues = try PassportValidator().validate(passport(bindingElementID: "missing"))
        #expect(issues.contains { $0.code == "missing_reference" })
    }

    @Test("An unknown external provider does not block local validation")
    func unknownProviderIsOpaque() throws {
        let issues = try PassportValidator().validate(passport(provider: "other-registry"))
        #expect(issues.isEmpty)
    }

    @Test("A sealed passport needs a signature envelope")
    func sealedNeedsSignature() throws {
        var object = try #require(JSONSerialization.jsonObject(with: passport()) as? [String: Any])
        var metadata = try #require(object["metadata"] as? [String: Any])
        metadata["status"] = "sealed"
        object["metadata"] = metadata
        let data = try JSONSerialization.data(withJSONObject: object)
        let issues = try PassportValidator().validate(data)
        #expect(issues.contains { $0.code == "schema" })
    }

    @Test("Malformed JSON produces a schema diagnostic")
    func malformedJSON() throws {
        let issues = try PassportValidator().validate(Data("{".utf8))
        #expect(issues.contains { $0.code == "schema" })
    }

    private func passport(
        featureID: String? = "feature.demo.route",
        elementIDs: [String] = ["composition"],
        bindingElementID: String = "composition",
        provider: String? = nil
    ) throws -> Data {
        var metadata: [String: Any] = [
            "passport_id": "fp.demo.route",
            "version": "0.1.0",
            "status": "draft",
            "issuer": "demo"
        ]
        if let featureID {
            metadata["feature_id"] = featureID
        }
        var spec: [String: Any] = [
            "intent": [
                "summary": "Route strategy composition",
                "acceptance_criteria": [
                    ["id": "route-selected", "text": "The first available route is selected."]
                ]
            ],
            "implementation": [
                "elements": elementIDs.map { ["id": $0, "role": "composition"] },
                "bindings": [[
                    "id": "route-binding",
                    "acceptance_criteria_ids": ["route-selected"],
                    "element_ids": [bindingElementID]
                ]]
            ],
            "evidence": ["required_level": "L0", "probes": []],
            "privacy": ["pii_allowed": false, "retention_days": 30, "raw_payload_storage": false]
        ]
        if let provider {
            spec["contract_refs"] = [[
                "id": "external-rule",
                "relation": "implements",
                "provider": provider,
                "locator": ["id": "external:route"]
            ]]
        }
        return try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "feature_passport",
            "schema_version": 1,
            "metadata": metadata,
            "spec": spec
        ])
    }
}
