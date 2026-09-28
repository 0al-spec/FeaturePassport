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

    @Test("An implementation element needs an anchored source identity")
    func elementNeedsAnchor() throws {
        let data = try modifiedPassport { object in
            var spec = object["spec"] as! [String: Any]
            var implementation = spec["implementation"] as! [String: Any]
            implementation["elements"] = [["id": "composition", "role": "composition"]]
            spec["implementation"] = implementation
            object["spec"] = spec
        }
        let issues = try PassportValidator().validate(data)
        #expect(issues.contains { $0.code == "schema" })
    }

    @Test("An anchor repository must be declared locally")
    func anchorRepositoryMustExist() throws {
        let data = try modifiedPassport { object in
            var spec = object["spec"] as! [String: Any]
            var implementation = spec["implementation"] as! [String: Any]
            var elements = implementation["elements"] as! [[String: Any]]
            var anchors = elements[0]["anchors"] as! [[String: Any]]
            anchors[0]["repository"] = "missing-repo"
            elements[0]["anchors"] = anchors
            implementation["elements"] = elements
            spec["implementation"] = implementation
            object["spec"] = spec
        }
        let issues = try PassportValidator().validate(data)
        #expect(issues.contains { $0.code == "missing_reference" })
    }

    @Test("A test binding must reference an element whose role is test")
    func testBindingRole() throws {
        let data = try modifiedPassport { object in
            var spec = object["spec"] as! [String: Any]
            var implementation = spec["implementation"] as! [String: Any]
            var bindings = implementation["bindings"] as! [[String: Any]]
            bindings[0]["test_element_ids"] = ["composition"]
            implementation["bindings"] = bindings
            spec["implementation"] = implementation
            object["spec"] = spec
        }
        let issues = try PassportValidator().validate(data)
        #expect(issues.contains { $0.code == "invalid_reference_role" })
    }

    @Test("A probe can require only supported runtime correlation fields")
    func probeRuntimeFieldVocabulary() throws {
        let data = try modifiedPassport { object in
            var spec = object["spec"] as! [String: Any]
            spec["evidence"] = [
                "required_level": "L6",
                "probes": [[
                    "id": "route", "event": "fp.feature.code_path.executed",
                    "level": "L6", "required": true,
                    "required_runtime_fields": ["unknown_field"]
                ]]
            ]
            object["spec"] = spec
        }
        let issues = try PassportValidator().validate(data)
        #expect(issues.contains { $0.code == "schema" })
    }

    @Test("A draft may target L6 before delivery or runtime evidence exists")
    func futureEvidenceTargetIsNotAClaim() throws {
        let data = try modifiedPassport { object in
            var spec = object["spec"] as! [String: Any]
            spec["evidence"] = ["required_level": "L6", "probes": []]
            object["spec"] = spec
        }
        let issues = try PassportValidator().validate(data)
        #expect(issues.isEmpty)
    }

    private func modifiedPassport(_ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: passport()) as? [String: Any])
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: object)
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
                "repositories": [["name": "demo"]],
                "elements": elementIDs.map { id in
                    [
                        "id": id,
                        "role": "composition",
                        "anchors": [[
                            "repository": "demo",
                            "revision": "0123456789abcdef0123456789abcdef01234567",
                            "language": "swift",
                            "module": "Demo",
                            "path": "Sources/Demo/Route.swift",
                            "symbol": "Route.evaluate()"
                        ]]
                    ]
                },
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
