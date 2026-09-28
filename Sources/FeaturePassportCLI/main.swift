import FeaturePassport
import Foundation

guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "validate" else {
    fputs("Usage: feature-passport validate <passport.json>\n", stderr)
    exit(2)
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let issues = try PassportValidator().validate(data)
    if issues.isEmpty {
        print("valid")
    } else {
        for issue in issues {
            fputs("\(issue.code): \(issue.message)\n", stderr)
        }
        exit(1)
    }
} catch {
    fputs("validation_error: \(error)\n", stderr)
    exit(2)
}
