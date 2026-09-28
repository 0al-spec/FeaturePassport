import Foundation
import JSONSchema

public struct ValidationIssue: Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct PassportValidator: Sendable {
    public init() {}

    public func validate(_ data: Data) throws -> [ValidationIssue] {
        guard let document = String(data: data, encoding: .utf8) else {
            return [ValidationIssue(code: "schema", message: "Passport must be UTF-8 JSON")]
        }
        guard let resource = Bundle.module.url(
            forResource: "feature-passport.v1.schema", withExtension: "json"
        ) else {
            throw ValidatorError.schemaResourceMissing
        }
        let schema = try Schema(
            instance: String(contentsOf: resource, encoding: .utf8),
            dialect: .draft2020_12
        )
        let result: ValidationResult
        do {
            result = try schema.validate(instance: document)
        } catch {
            return [ValidationIssue(code: "schema", message: "Invalid JSON: \(error)")]
        }
        guard result.isValid else {
            let detail = try result.renderedOutput(level: .basic).serialized()
            return [ValidationIssue(code: "schema", message: detail)]
        }

        let decoder = JSONDecoder()
        let passport = try decoder.decode(Passport.self, from: data)
        return checkReferences(in: passport)
    }

    private func checkReferences(in passport: Passport) -> [ValidationIssue] {
        let spec = passport.spec
        let implementation = spec.implementation
        var issues: [ValidationIssue] = []

        func unique(_ ids: [String], scope: String) {
            var seen = Set<String>()
            for id in ids where !seen.insert(id).inserted {
                issues.append(.init(code: "duplicate_id", message: "Duplicate \(scope) ID: \(id)"))
            }
        }

        let criteria = spec.intent.acceptanceCriteria.map(\.id)
        let contracts = spec.contractRefs?.map(\.id) ?? []
        let repositories = implementation?.repositories?.map(\.name) ?? []
        let elements = implementation?.elements ?? []
        let bindings = implementation?.bindings ?? []
        let probes = spec.evidence.probes
        unique(criteria, scope: "acceptance criterion")
        unique(contracts, scope: "contract reference")
        unique(repositories, scope: "repository")
        unique(elements.map(\.id), scope: "element")
        unique(bindings.map(\.id), scope: "binding")
        unique(probes.map(\.id), scope: "probe")

        let criterionIDs = Set(criteria)
        let contractIDs = Set(contracts)
        let elementIDs = Set(elements.map(\.id))
        let testIDs = Set(elements.filter { $0.role == "test" }.map(\.id))

        func require(_ ids: [String], in available: Set<String>, scope: String) {
            for id in ids where !available.contains(id) {
                issues.append(.init(code: "missing_reference", message: "Unknown \(scope) ID: \(id)"))
            }
        }

        for element in elements {
            require(element.uses?.map(\.elementID) ?? [], in: elementIDs,
                    scope: "element used by \(element.id)")
        }
        for binding in bindings {
            require(binding.acceptanceCriteriaIDs, in: criterionIDs,
                    scope: "acceptance criterion in \(binding.id)")
            require(binding.contractRefIDs ?? [], in: contractIDs,
                    scope: "contract reference in \(binding.id)")
            require(binding.elementIDs, in: elementIDs,
                    scope: "element in \(binding.id)")
            require(binding.testElementIDs ?? [], in: testIDs,
                    scope: "test element in \(binding.id)")
        }
        for probe in probes {
            require(probe.elementIDs ?? [], in: elementIDs,
                    scope: "element in probe \(probe.id)")
        }
        return issues
    }
}

public enum ValidatorError: Error {
    case schemaResourceMissing
}

private struct Passport: Decodable {
    let spec: Spec
}

private struct Spec: Decodable {
    let intent: Intent
    let contractRefs: [NamedID]?
    let implementation: Implementation?
    let evidence: Evidence

    enum CodingKeys: String, CodingKey {
        case intent, implementation, evidence
        case contractRefs = "contract_refs"
    }
}

private struct Intent: Decodable {
    let acceptanceCriteria: [NamedID]

    enum CodingKeys: String, CodingKey {
        case acceptanceCriteria = "acceptance_criteria"
    }
}

private struct NamedID: Decodable {
    let id: String
}

private struct Implementation: Decodable {
    let repositories: [Repository]?
    let elements: [Element]?
    let bindings: [Binding]?
}

private struct Repository: Decodable {
    let name: String
}

private struct Element: Decodable {
    let id: String
    let role: String
    let uses: [ElementUse]?
}

private struct ElementUse: Decodable {
    let elementID: String

    enum CodingKeys: String, CodingKey {
        case elementID = "element_id"
    }
}

private struct Binding: Decodable {
    let id: String
    let contractRefIDs: [String]?
    let acceptanceCriteriaIDs: [String]
    let elementIDs: [String]
    let testElementIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case contractRefIDs = "contract_ref_ids"
        case acceptanceCriteriaIDs = "acceptance_criteria_ids"
        case elementIDs = "element_ids"
        case testElementIDs = "test_element_ids"
    }
}

private struct Evidence: Decodable {
    let probes: [Probe]
}

private struct Probe: Decodable {
    let id: String
    let elementIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case elementIDs = "element_ids"
    }
}
