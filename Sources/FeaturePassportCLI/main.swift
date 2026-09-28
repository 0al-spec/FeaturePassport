import FeaturePassport
import Foundation

private func usage() -> Never {
    fputs("Usage:\n  feature-passport validate <passport.json>\n  feature-passport evaluate-observation <passport.json> --passport-digest <digest> <observation.json>\n  feature-passport verify-receipt <passport.json> <observation.json> <receipt.json> --trust-store <trust-store.json> [--at <RFC3339-UTC>]\n  feature-passport resolve-sources <passport.json> --repository <name>=<absolute-checkout> [--repository ...]\n", stderr)
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
    case "evaluate-observation":
        guard arguments.count == 5, arguments[2] == "--passport-digest", !arguments[3].isEmpty else { usage() }
        let observationData = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))
        let evaluation = try RuntimeObservationEvaluator().evaluate(
            passportData: data, passportDigest: arguments[3], observationData: observationData
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(evaluation), as: UTF8.self))
        if !evaluation.matched { exit(1) }
    case "verify-receipt":
        guard arguments.count == 6 || arguments.count == 8,
              arguments[4] == "--trust-store",
              arguments.count == 6 || arguments[6] == "--at" else { usage() }
        let observationData = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        let receiptData = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
        let trustData = try Data(contentsOf: URL(fileURLWithPath: arguments[5]))
        let trustStore = try EvidenceReceiptTrustStore.decode(from: trustData)
        let verificationTime: Date
        if arguments.count == 8 {
            let timestamp = arguments[7]
            let timestampPattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$"#
            guard timestamp.range(of: timestampPattern, options: .regularExpression) != nil else { usage() }
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.formatOptions = timestamp.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            guard let parsed = formatter.date(from: timestamp), timestamp.hasSuffix("Z") else { usage() }
            verificationTime = parsed
        } else {
            verificationTime = Date()
        }
        let report = try EvidenceReceiptVerifier().verify(
            passportData: data, observationData: observationData, receiptData: receiptData,
            trustStore: trustStore, verificationTime: verificationTime
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
        if !report.trusted { exit(1) }
    default:
        usage()
    }
} catch {
    fputs("feature_passport_error: \(error)\n", stderr)
    exit(2)
}
