import Foundation
import SwiftParser
import SwiftSyntax

/// A source anchor resolved against one immutable Git commit. Resolution does not
/// establish behavioral coverage, compilation, test execution, or module ownership.
public struct SourceAnchorResolution: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case resolved
        case repositoryNotConfigured = "repository_not_configured"
        case invalidRevision = "invalid_revision"
        case revisionNotFound = "revision_not_found"
        case invalidPath = "invalid_path"
        case pathNotFound = "path_not_found"
        case unsupportedLanguage = "unsupported_language"
        case invalidSymbol = "invalid_symbol"
        case symbolNotFound = "symbol_not_found"
        case ambiguousSymbol = "ambiguous_symbol"
        case malformedSource = "malformed_source"
        case gitFailure = "git_failure"
    }

    public let elementID: String
    public let anchorIndex: Int
    public let repository: String
    public let revision: String
    public let module: String
    public let path: String
    public let symbol: String
    public let status: Status
    public let blobOID: String?
    public let detail: String

    enum CodingKeys: String, CodingKey {
        case repository, revision, module, path, symbol, status, detail
        case elementID = "element_id"
        case anchorIndex = "anchor_index"
        case blobOID = "blob_oid"
    }
}

public struct SourceResolutionReport: Codable, Sendable {
    public let validationIssues: [ValidationIssue]
    public let anchors: [SourceAnchorResolution]

    public var isResolved: Bool {
        validationIssues.isEmpty && anchors.allSatisfy { $0.status == .resolved }
    }

    enum CodingKeys: String, CodingKey {
        case anchors
        case validationIssues = "validation_issues"
    }
}

/// Resolves authored Swift anchors against explicitly supplied local Git checkouts.
/// The working tree is never read and no network access is performed.
public struct SourceResolver: Sendable {
    public let repositories: [String: URL]

    public init(repositories: [String: URL]) {
        self.repositories = repositories
    }

    public func resolve(_ data: Data) throws -> SourceResolutionReport {
        let issues = try PassportValidator().validate(data)
        guard issues.isEmpty else {
            return SourceResolutionReport(validationIssues: issues, anchors: [])
        }
        let document = try JSONDecoder().decode(SourcePassport.self, from: data)
        let anchors = (document.spec.implementation?.elements ?? []).flatMap { element in
            element.anchors.enumerated().map { index, anchor in
                resolve(anchor, elementID: element.id, index: index)
            }
        }
        guard !anchors.isEmpty else {
            return SourceResolutionReport(
                validationIssues: [.init(code: "no_source_anchors", message: "Passport has no source anchors to resolve")],
                anchors: []
            )
        }
        return SourceResolutionReport(validationIssues: [], anchors: anchors)
    }

    private func resolve(
        _ anchor: SourceAnchor,
        elementID: String,
        index: Int
    ) -> SourceAnchorResolution {
        func result(
            _ status: SourceAnchorResolution.Status,
            _ detail: String,
            blobOID: String? = nil
        ) -> SourceAnchorResolution {
            .init(elementID: elementID, anchorIndex: index,
                  repository: anchor.repository, revision: anchor.revision,
                  module: anchor.module, path: anchor.path, symbol: anchor.symbol,
                  status: status, blobOID: blobOID, detail: detail)
        }

        guard let checkout = repositories[anchor.repository] else {
            return result(.repositoryNotConfigured, "No checkout was configured for this repository")
        }
        guard isFullGitObjectID(anchor.revision) else {
            return result(.invalidRevision, "Revision must be a full 40- or 64-digit Git object ID")
        }
        guard isSafeGitPath(anchor.path) else {
            return result(.invalidPath, "Path must be a relative Git path without traversal")
        }
        guard anchor.language == "swift" else {
            return result(.unsupportedLanguage, "Only Swift declarations are supported")
        }
        guard SwiftSymbolIndex.isSupportedSymbol(anchor.symbol) else {
            return result(.invalidSymbol, "Expected a qualified Swift type or function signature")
        }

        do {
            let root = try git(["rev-parse", "--show-toplevel"], in: checkout)
            guard root.status == 0 else {
                return result(.gitFailure, "Configured path is not inside a Git checkout")
            }
            let commitType = try git(["cat-file", "-t", anchor.revision], in: checkout)
            guard commitType.status == 0,
                  String(data: commitType.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "commit" else {
                return result(.revisionNotFound, "Revision is not an available Git commit")
            }
            let object = "\(anchor.revision):\(anchor.path)"
            let blobType = try git(["cat-file", "-t", object], in: checkout)
            guard blobType.status == 0,
                  String(data: blobType.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "blob" else {
                return result(.pathNotFound, "Path is not a file in the pinned commit")
            }
            let oid = try git(["rev-parse", "--verify", object], in: checkout)
            let blob = try git(["cat-file", "blob", object], in: checkout)
            guard oid.status == 0, blob.status == 0,
                  let blobOID = String(data: oid.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let source = String(data: blob.output, encoding: .utf8) else {
                return result(.gitFailure, "Unable to read the pinned UTF-8 source blob")
            }
            let index = SwiftSymbolIndex(source: source)
            guard !index.hasError else {
                return result(.malformedSource, "Swift parser reported syntax errors", blobOID: blobOID)
            }
            switch index.count(of: anchor.symbol) {
            case 0:
                return result(.symbolNotFound, "No matching declaration exists in the pinned file", blobOID: blobOID)
            case 1:
                return result(.resolved, "One matching declaration exists in the pinned file", blobOID: blobOID)
            default:
                return result(.ambiguousSymbol, "Multiple matching declarations exist in the pinned file", blobOID: blobOID)
            }
        } catch {
            return result(.gitFailure, "Unable to inspect the configured Git checkout: \(error)")
        }
    }
}

private struct SourcePassport: Decodable {
    let spec: SourceSpec
}

private struct SourceSpec: Decodable {
    let implementation: SourceImplementation?
}

private struct SourceImplementation: Decodable {
    let elements: [SourceElement]?
}

private struct SourceElement: Decodable {
    let id: String
    let anchors: [SourceAnchor]
}

private struct SourceAnchor: Decodable {
    let repository: String
    let revision: String
    let language: String
    let module: String
    let path: String
    let symbol: String
}

private func isFullGitObjectID(_ value: String) -> Bool {
    (value.utf8.count == 40 || value.utf8.count == 64)
        && value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102) }
}

private func isSafeGitPath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
        && !path.contains(":") && !path.contains("\0")
        && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
}

private struct GitOutput {
    let status: Int32
    let output: Data
}

private func git(_ arguments: [String], in checkout: URL) throws -> GitOutput {
    #if os(macOS) || os(Linux)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", checkout.path] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return GitOutput(status: process.terminationStatus, output: data)
    #else
    throw SourceResolverError.unsupportedPlatform
    #endif
}

private enum SourceResolverError: Error {
    case unsupportedPlatform
}

/// A syntactic index. It deliberately does not type-check or expand macros.
struct SwiftSymbolIndex {
    let hasError: Bool
    private let counts: [String: Int]

    init(source: String) {
        let tree = Parser.parse(source: source)
        hasError = tree.hasError
        var found: [String: Int] = [:]
        Self.walk(Syntax(tree), scope: [], found: &found)
        counts = found
    }

    func count(of symbol: String) -> Int { counts[symbol, default: 0] }

    static func isSupportedSymbol(_ symbol: String) -> Bool {
        let pattern = #"^[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*(?:\((?:(?:[A-Za-z_][A-Za-z_0-9]*|_):)*\))?$"#
        return symbol.range(of: pattern, options: .regularExpression) != nil
    }

    private static func walk(_ syntax: Syntax, scope: [String], found: inout [String: Int]) {
        if let node = syntax.as(StructDeclSyntax.self) {
            walkNominal(node.name.text, members: Syntax(node.memberBlock), scope: scope, found: &found)
            return
        }
        if let node = syntax.as(ClassDeclSyntax.self) {
            walkNominal(node.name.text, members: Syntax(node.memberBlock), scope: scope, found: &found)
            return
        }
        if let node = syntax.as(EnumDeclSyntax.self) {
            walkNominal(node.name.text, members: Syntax(node.memberBlock), scope: scope, found: &found)
            return
        }
        if let node = syntax.as(ActorDeclSyntax.self) {
            walkNominal(node.name.text, members: Syntax(node.memberBlock), scope: scope, found: &found)
            return
        }
        if let node = syntax.as(ProtocolDeclSyntax.self) {
            walkNominal(node.name.text, members: Syntax(node.memberBlock), scope: scope, found: &found)
            return
        }
        if let node = syntax.as(ExtensionDeclSyntax.self) {
            let name = node.extendedType.trimmedDescription
            for child in Syntax(node.memberBlock).children(viewMode: .sourceAccurate) {
                walk(child, scope: scope + name.split(separator: ".").map(String.init), found: &found)
            }
            return
        }
        if let node = syntax.as(FunctionDeclSyntax.self) {
            let labels = node.signature.parameterClause.parameters.map { "\($0.firstName.text):" }.joined()
            let symbol = (scope + ["\(node.name.text)(\(labels))"]).joined(separator: ".")
            found[symbol, default: 0] += 1
            return // Do not mistake a local function for a member declaration.
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            walk(child, scope: scope, found: &found)
        }
    }

    private static func walkNominal(
        _ name: String, members: Syntax, scope: [String], found: inout [String: Int]
    ) {
        let qualified = (scope + [name]).joined(separator: ".")
        found[qualified, default: 0] += 1
        for child in members.children(viewMode: .sourceAccurate) {
            walk(child, scope: scope + [name], found: &found)
        }
    }
}
