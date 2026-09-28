@testable import FeaturePassport
import Foundation
import Testing

@Suite("Pinned Swift source resolution")
struct SourceResolverTests {
    @Test("Syntax index matches declarations and labels, not comments or strings")
    func syntaxIndex() {
        let source = """
        // Route.fake()
        let text = "Route.fake()"
        struct Route {
            func evaluate(_ value: Int) {
                func local() {}
            }
        }
        extension Route {
            func evaluate(to value: Int) {}
        }
        """
        let index = SwiftSymbolIndex(source: source)
        #expect(!index.hasError)
        #expect(index.count(of: "Route") == 1)
        #expect(index.count(of: "Route.evaluate(_:)") == 1)
        #expect(index.count(of: "Route.evaluate(to:)") == 1)
        #expect(index.count(of: "Route.evaluate(from:)") == 0)
        #expect(index.count(of: "Route.fake()") == 0)
        #expect(index.count(of: "Route.local()") == 0)
    }

    @Test("Pinned blob is read even when the working tree changes")
    func pinnedBlobIgnoresWorkingTree() throws {
        try withRepository(source: "struct Route { func evaluate() {} }\n") { root, revision in
            let file = root.appendingPathComponent("Route.swift")
            try "struct Different {}\n".write(to: file, atomically: true, encoding: .utf8)
            let report = try SourceResolver(repositories: ["demo": root])
                .resolve(passport(revision: revision, symbol: "Route.evaluate()"))
            let anchor = try #require(report.anchors.first)
            #expect(report.isResolved)
            #expect(anchor.status == .resolved)
            #expect(anchor.blobOID?.count == 40)
        }
    }

    @Test("A duplicate declaration is ambiguous and a missing one stays unresolved")
    func ambiguityAndMissingSymbol() throws {
        try withRepository(source: "struct Route { func evaluate() {} }\nextension Route { func evaluate() {} }\n") { root, revision in
            let resolver = SourceResolver(repositories: ["demo": root])
            let ambiguous = try resolver.resolve(passport(revision: revision, symbol: "Route.evaluate()"))
            #expect(ambiguous.anchors.first?.status == .ambiguousSymbol)
            let missing = try resolver.resolve(passport(revision: revision, symbol: "Route.missing()"))
            #expect(missing.anchors.first?.status == .symbolNotFound)
        }
    }

    @Test("Invalid revision, traversal, missing file, and absent checkout have distinct results")
    func invalidInputs() throws {
        try withRepository(source: "struct Route {}\n") { root, revision in
            let resolver = SourceResolver(repositories: ["demo": root])
            let invalidRevision = try resolver.resolve(passport(revision: "HEAD", symbol: "Route"))
            let invalidPath = try resolver.resolve(passport(revision: revision, path: "../Route.swift", symbol: "Route"))
            let missingPath = try resolver.resolve(passport(revision: revision, path: "Missing.swift", symbol: "Route"))
            let missingCheckout = try SourceResolver(repositories: [:])
                .resolve(passport(revision: revision, symbol: "Route"))
            #expect(invalidRevision.anchors.first?.status == .invalidRevision)
            #expect(invalidPath.anchors.first?.status == .invalidPath)
            #expect(missingPath.anchors.first?.status == .pathNotFound)
            #expect(missingCheckout.anchors.first?.status == .repositoryNotConfigured)
        }
    }

    @Test("Invalid passport stops resolution before repository access")
    func invalidPassport() throws {
        let report = try SourceResolver(repositories: [:]).resolve(Data("{".utf8))
        #expect(report.validationIssues.contains { $0.code == "schema" })
        #expect(report.anchors.isEmpty)
        #expect(!report.isResolved)
    }

    @Test("A valid draft without implementation anchors has no resolution claim")
    func noAnchors() throws {
        let object = try #require(JSONSerialization.jsonObject(with: passport(
            revision: String(repeating: "0", count: 40), symbol: "Route"
        )) as? [String: Any])
        var changed = object
        var spec = try #require(changed["spec"] as? [String: Any])
        spec.removeValue(forKey: "implementation")
        changed["spec"] = spec
        let report = try SourceResolver(repositories: [:])
            .resolve(JSONSerialization.data(withJSONObject: changed))
        #expect(report.validationIssues.contains { $0.code == "no_source_anchors" })
        #expect(!report.isResolved)
    }

    private func passport(
        revision: String, path: String = "Route.swift", symbol: String
    ) throws -> Data {
        let object: [String: Any] = [
            "artifact_kind": "feature_passport", "schema_version": 1,
            "metadata": ["feature_id": "feature.demo", "passport_id": "fp.demo",
                         "version": "0.1.0", "status": "draft", "issuer": "demo"],
            "spec": [
                "intent": ["summary": "Resolve a declaration", "acceptance_criteria": [
                    ["id": "AC-1", "text": "Declaration exists"]]],
                "implementation": [
                    "repositories": [["name": "demo"]],
                    "elements": [["id": "route", "role": "policy", "anchors": [[
                        "repository": "demo", "revision": revision, "language": "swift",
                        "module": "Demo", "path": path, "symbol": symbol]]]],
                    "bindings": [["id": "binding", "acceptance_criteria_ids": ["AC-1"],
                                   "element_ids": ["route"]]]],
                "evidence": ["required_level": "L0", "probes": []],
                "privacy": ["pii_allowed": false, "retention_days": 30,
                            "raw_payload_storage": false]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func withRepository(
        source: String, body: (URL, String) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("feature-passport-resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try source.write(to: root.appendingPathComponent("Route.swift"), atomically: true, encoding: .utf8)
        _ = try git(["init", "-q"], in: root)
        _ = try git(["add", "Route.swift"], in: root)
        _ = try git(["-c", "user.name=Resolver Test", "-c", "user.email=resolver@example.invalid",
                 "commit", "-qm", "source"], in: root)
        let revision = try git(["rev-parse", "HEAD"], in: root)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try body(root, revision)
    }

    private func git(_ arguments: [String], in root: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TestGitError.commandFailed }
        return String(decoding: data, as: UTF8.self)
    }
}

private enum TestGitError: Error {
    case commandFailed
}
