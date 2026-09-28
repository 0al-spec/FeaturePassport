import FeaturePassport
import Foundation

private func usage() -> Never {
    fputs("Usage:\n  feature-passport validate <passport.json>\n  feature-passport resolve-sources <passport.json> --repository <name>=<absolute-checkout> [--repository ...]\n", stderr)
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { usage() }

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    switch arguments[0] {
    case "validate":
        guard arguments.count == 2 else { usage() }
        let issues = try PassportValidator().validate(data)
        if issues.isEmpty {
            print("valid")
        } else {
            for issue in issues {
                fputs("\(issue.code): \(issue.message)\n", stderr)
            }
            exit(1)
        }
    case "resolve-sources":
        guard arguments.count >= 4, (arguments.count - 2).isMultiple(of: 2) else { usage() }
        var repositories: [String: URL] = [:]
        for index in stride(from: 2, to: arguments.count, by: 2) {
            guard arguments[index] == "--repository",
                  let separator = arguments[index + 1].firstIndex(of: "=") else { usage() }
            let name = String(arguments[index + 1][..<separator])
            let path = String(arguments[index + 1][arguments[index + 1].index(after: separator)...])
            guard !name.isEmpty, path.hasPrefix("/"), repositories[name] == nil else { usage() }
            repositories[name] = URL(fileURLWithPath: path, isDirectory: true)
        }
        let report = try SourceResolver(repositories: repositories).resolve(data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = try encoder.encode(report)
        print(String(decoding: output, as: UTF8.self))
        if !report.isResolved { exit(1) }
    default:
        usage()
    }
} catch {
    fputs("feature_passport_error: \(error)\n", stderr)
    exit(2)
}
