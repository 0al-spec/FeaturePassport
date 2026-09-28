import FeaturePassport
import Foundation

private func usage() -> Never {
    fputs("Usage:\n  feature-passport validate <passport.json>\n  feature-passport evaluate-observation <passport.json> --passport-digest <digest> <observation.json>\n  feature-passport verify-receipt <passport.json> <observation.json> <receipt.json> --trust-store <trust-store.json> [--at <RFC3339-UTC>]\n  feature-passport evaluate-claim <passport.json> <claim-policy.json> <bundle.json> --trust-store <trust-store.json> [--at <RFC3339-UTC>]\n  feature-passport verify-decision <passport.json> <claim-policy.json> <bundle.json> <decision.json> --trust-store <receipt-trust.json> --decision-trust <decision-trust.json>\n  feature-passport resolve-sources <passport.json> --repository <name>=<absolute-checkout> [--repository ...]\n", stderr)
    exit(2)
}

private enum CLIInputError: Error { case sizeLimit }

private func readBoundedFile(_ url: URL, maximumBytes: Int) throws -> Data {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes else {
        throw CLIInputError.sizeLimit
    }
    let data = try Data(contentsOf: url)
    guard data.count <= maximumBytes else { throw CLIInputError.sizeLimit }
    return data
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { usage() }

do {
    let passportURL = URL(fileURLWithPath: arguments[1])
    let data = ["evaluate-claim", "verify-decision"].contains(arguments[0])
        ? try readBoundedFile(passportURL, maximumBytes: 10_000_000)
        : try Data(contentsOf: passportURL)
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
            guard let parsed = EvidenceReceiptTimestamp.parseRFC3339UTC(timestamp) else { usage() }
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
    case "evaluate-claim":
        guard arguments.count == 6 || arguments.count == 8,
              arguments[4] == "--trust-store",
              arguments.count == 6 || arguments[6] == "--at" else { usage() }
        let policyData = try readBoundedFile(URL(fileURLWithPath: arguments[2]), maximumBytes: 256_000)
        let bundleURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
        let bundle = try LocalAggregateClaimBundle.decode(from: readBoundedFile(bundleURL, maximumBytes: 256_000))
        let trustStore = try EvidenceReceiptTrustStore.decode(from: readBoundedFile(URL(fileURLWithPath: arguments[5]), maximumBytes: 1_000_000))
        let verificationTime: Date
        if arguments.count == 8 {
            guard let parsed = EvidenceReceiptTimestamp.parseRFC3339UTC(arguments[7]) else { usage() }
            verificationTime = parsed
        } else {
            verificationTime = Date()
        }
        var totalPairBytes = 0
        let pairs = try bundle.pairs.map { reference -> LocalAggregateClaimPair in
            func resolve(_ path: String) -> URL {
                URL(fileURLWithPath: path, relativeTo: bundleURL.deletingLastPathComponent()).standardizedFileURL
            }
            let observationData = try readBoundedFile(resolve(reference.observation), maximumBytes: 10_000_000)
            let receiptData = try readBoundedFile(resolve(reference.receipt), maximumBytes: 256_000)
            totalPairBytes += observationData.count + receiptData.count
            guard totalPairBytes <= 64_000_000 else { throw CLIInputError.sizeLimit }
            return LocalAggregateClaimPair(
                observationData: observationData,
                receiptData: receiptData
            )
        }
        let report = try LocalAggregateClaimEvaluator().evaluate(
            passportData: data, policyData: policyData, pairs: pairs,
            trustStore: trustStore, verificationTime: verificationTime
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
        if !report.satisfied { exit(1) }
    case "verify-decision":
        guard arguments.count == 9, arguments[5] == "--trust-store", arguments[7] == "--decision-trust" else { usage() }
        let policyData = try readBoundedFile(URL(fileURLWithPath: arguments[2]), maximumBytes: 256_000)
        let bundleURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
        let bundleData = try readBoundedFile(bundleURL, maximumBytes: 256_000)
        let bundle = try LocalAggregateClaimBundle.decode(from: bundleData)
        let receiptTrustData = try readBoundedFile(URL(fileURLWithPath: arguments[6]), maximumBytes: 1_000_000)
        _ = try EvidenceReceiptTrustStore.decode(from: receiptTrustData)
        let decisionData = try readBoundedFile(URL(fileURLWithPath: arguments[4]), maximumBytes: 1_000_000)
        let decisionTrustData = try readBoundedFile(URL(fileURLWithPath: arguments[8]), maximumBytes: 1_000_000)
        let decisionTrust = try AggregateClaimDecisionTrustStore.decode(from: decisionTrustData)
        var totalPairBytes = 0
        let pairs = try bundle.pairs.map { reference -> AggregateClaimDecisionInputs.Pair in
            func resolve(_ path: String) -> URL {
                URL(fileURLWithPath: path, relativeTo: bundleURL.deletingLastPathComponent()).standardizedFileURL
            }
            let observationData = try readBoundedFile(resolve(reference.observation), maximumBytes: 10_000_000)
            let receiptData = try readBoundedFile(resolve(reference.receipt), maximumBytes: 256_000)
            totalPairBytes += observationData.count + receiptData.count
            guard totalPairBytes <= 64_000_000 else { throw CLIInputError.sizeLimit }
            return .init(observationPath: reference.observation, receiptPath: reference.receipt,
                         observationData: observationData, receiptData: receiptData)
        }
        let inputs = AggregateClaimDecisionInputs(passportData: data, claimPolicyData: policyData,
            bundleData: bundleData, receiptTrustStoreData: receiptTrustData, pairs: pairs)
        let report = try AggregateClaimDecisionVerifier().verify(
            decisionData: decisionData, inputs: inputs, trustStore: decisionTrust
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
