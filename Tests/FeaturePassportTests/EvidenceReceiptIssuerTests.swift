import Crypto
@testable import FeaturePassport
import Foundation
import Testing

@Suite("Policy-scoped receipt issuance")
struct EvidenceReceiptIssuerTests {
    struct Signer: EvidenceReceiptSigner {
        let key: Curve25519.Signing.PrivateKey
        var publicKey: Data { key.publicKey.rawRepresentation }
        func sign(message: Data) throws -> Data { try key.signature(for: message) }
    }
    struct NeverSigner: EvidenceReceiptSigner {
        let publicKey: Data
        func sign(message: Data) throws -> Data { throw CalledSigner.unexpected }
    }
    struct InvalidSignatureSigner: EvidenceReceiptSigner {
        let publicKey: Data
        func sign(message: Data) throws -> Data { Data(repeating: 0, count: 64) }
    }
    enum CalledSigner: Error { case unexpected }

    func policy(environment: String = "test") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "observation_receipt_policy", "schema_version": 1,
            "policy_id": "contract-match", "policy_version": "1",
            "predicate_profile": "exact_contract_match_v1",
            "allowed_environments": [environment], "maximum_receipt_lifetime_seconds": 3600
        ], options: [.sortedKeys])
    }
    func authorization(policy: Data, key: Data) -> EvidenceReceiptTrustedKey {
        .init(authorityID: "local-authority", policyID: "contract-match", policyVersion: "1",
              policyDigest: EvidenceReceiptVerifier.sha256(policy), keyID: "key-1",
              publicKey: key.base64EncodedString(), validFrom: "2026-09-28T20:00:00Z",
              validUntil: "2026-09-29T20:00:00Z")
    }
    let request = EvidenceReceiptIssuanceRequest(receiptID: "receipt-1",
        acceptedAt: "2026-09-28T20:30:00Z", validFrom: "2026-09-28T20:30:00Z",
        validUntil: "2026-09-28T21:00:00Z")

    @Test("A matched failure observation can be accepted without a success claim")
    func issuesCompatibleReceipt() throws {
        let fixture = try EvidenceReceiptVerifierTests().makeFixture()
        let signer = Signer(key: Curve25519.Signing.PrivateKey())
        let policyData = try policy()
        let auth = authorization(policy: policyData, key: signer.publicKey)
        let receipt = try EvidenceReceiptIssuer().issue(passportData: fixture.passport,
            observationData: fixture.observation, policyData: policyData,
            authorization: auth, request: request, signer: signer)
        let report = try EvidenceReceiptVerifier().verify(passportData: fixture.passport,
            observationData: fixture.observation, receiptData: receipt,
            trustStore: .init(trustedKeys: [auth]), verificationTime: fixture.verificationTime)
        #expect(report.trusted)
        #expect(report.acceptedClaims.isEmpty)
    }

    @Test("Invalid input is rejected before signing", arguments: ["environment", "policy", "timestamp", "observation", "key", "expired", "too-long", "future"])
    func rejectsBeforeSigning(_ kind: String) throws {
        let fixture = try EvidenceReceiptVerifierTests().makeFixture()
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        let policyData = try policy(environment: kind == "environment" ? "production" : "test")
        let auth = authorization(policy: kind == "policy" ? Data("different".utf8) : policyData, key: key)
        let actualRequest = kind == "timestamp"
            ? EvidenceReceiptIssuanceRequest(receiptID: "r", acceptedAt: "bad", validFrom: request.validFrom, validUntil: request.validUntil)
             : (kind == "expired" || kind == "too-long" || kind == "future")
                ? EvidenceReceiptIssuanceRequest(receiptID: "r", acceptedAt: request.acceptedAt,
                    validFrom: kind == "future" ? "2026-09-28T20:40:00Z" : request.validFrom,
                    validUntil: kind == "expired" ? "2026-09-28T20:00:00Z" : kind == "too-long" ? "2026-09-29T20:00:00Z" : request.validUntil)
                : request
        do {
            _ = try EvidenceReceiptIssuer().issue(passportData: fixture.passport,
                observationData: kind == "observation" ? Data("{}".utf8) : fixture.observation,
                policyData: policyData, authorization: auth, request: actualRequest,
                signer: NeverSigner(publicKey: kind == "key" ? Data(repeating: 0, count: 32) : key))
            Issue.record("Invalid input was accepted")
        } catch is EvidenceReceiptIssuanceError {
            // The signer must not be reached.
        } catch { Issue.record("Unexpected signer or error: \(error)") }
    }

    @Test("Duplicate policy fields are rejected")
    func rejectsDuplicatePolicy() throws {
        let fixture = try EvidenceReceiptVerifierTests().makeFixture()
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        let good = try policy()
        let duplicate = Data(String(decoding: good, as: UTF8.self).replacingOccurrences(of: "{", with: "{\"schema_version\":1,", options: [], range: nil).utf8)
        #expect(throws: EvidenceReceiptIssuanceError.self) {
            try EvidenceReceiptIssuer().issue(passportData: fixture.passport, observationData: fixture.observation,
                policyData: duplicate, authorization: authorization(policy: duplicate, key: key),
                request: request, signer: NeverSigner(publicKey: key))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FEATURE_PASSPORT_TEST_CLI"] != nil))
    func cliRoundTripAndPrivateKeyPermissions() throws {
        let executable = try #require(ProcessInfo.processInfo.environment["FEATURE_PASSPORT_TEST_CLI"])
        let fixture = try EvidenceReceiptVerifierTests().makeFixture()
        let signer = Signer(key: Curve25519.Signing.PrivateKey())
        let policyData = try policy()
        let auth = authorization(policy: policyData, key: signer.publicKey)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ name: String, _ data: Data) throws -> String {
            let url = folder.appendingPathComponent(name)
            try data.write(to: url)
            return url.path
        }
        let passport = try write("passport.json", fixture.passport)
        let observation = try write("observation.json", fixture.observation)
        let policyPath = try write("policy.json", policyData)
        let authorizationPath = try write("authorization.json", JSONEncoder().encode(EvidenceReceiptTrustStore(trustedKeys: [auth])))
        let requestPath = try write("request.json", JSONEncoder().encode(request))
        let keyPath = try write("ephemeral-test-key", signer.key.rawRepresentation)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath)
        let arguments = ["issue-receipt", passport, observation, "--policy", policyPath,
                         "--authorization", authorizationPath, "--request", requestPath,
                         "--signing-key-file", keyPath]
        func run(_ arguments: [String]) throws -> (Int32, Data) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, data)
        }
        let (status, receipt) = try run(arguments)
        #expect(status == 0)
        let report = try EvidenceReceiptVerifier().verify(passportData: fixture.passport,
            observationData: fixture.observation, receiptData: receipt,
            trustStore: .init(trustedKeys: [auth]), verificationTime: fixture.verificationTime)
        #expect(report.trusted)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: keyPath)
        let (rejected, output) = try run(arguments)
        #expect(rejected == 2)
        #expect(output.isEmpty)
        let (_, capabilities) = try run(["capabilities"])
        let description = try #require(JSONSerialization.jsonObject(with: capabilities) as? [String: Any])
        #expect(description["receipt_issuance_profile"] as? String == "exact_contract_match_v1")
    }

    @Test("A signer returning invalid signature bytes cannot issue a receipt")
    func rejectsInvalidSignerOutput() throws {
        let fixture = try EvidenceReceiptVerifierTests().makeFixture()
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        let policyData = try policy()
        #expect(throws: EvidenceReceiptIssuanceError.self) {
            try EvidenceReceiptIssuer().issue(passportData: fixture.passport,
                observationData: fixture.observation, policyData: policyData,
                authorization: authorization(policy: policyData, key: key), request: request,
                signer: InvalidSignatureSigner(publicKey: key))
        }
    }
}
