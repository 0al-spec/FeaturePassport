import Crypto
@testable import FeaturePassport
import Foundation
import Testing

@Suite("Signed observation receipt verification")
struct EvidenceReceiptVerifierTests {
    @Test("An allowed Ed25519 authority receipt verifies as a scoped observation acceptance")
    func verifiesTrustedReceipt() throws {
        let fixture = try makeFixture()
        let report = try verify(fixture)
        #expect(report.verdict == .trustedObservationReceipt)
        #expect(report.trusted)
        #expect(report.acceptedClaims.isEmpty)
        #expect(report.eventID == "event-1")
    }

    @Test("Exact passport bytes are recomputed and bound into the receipt")
    func passportByteChangeRejects() throws {
        let fixture = try makeFixture()
        let changedPassport = fixture.passport + Data(" ".utf8)
        let report = try EvidenceReceiptVerifier().verify(
            passportData: changedPassport, observationData: fixture.observation,
            receiptData: fixture.receipt, trustStore: fixture.trustStore,
            verificationTime: fixture.verificationTime
        )
        #expect(!report.trusted)
        #expect(report.issues.contains { $0.code == "passport_digest_mismatch" || $0.code == "observation_not_matched" })
    }

    @Test("Exact observation bytes and the event identity are recomputed")
    func observationByteChangeRejects() throws {
        let fixture = try makeFixture()
        let changed = fixture.observation + Data(" ".utf8)
        let report = try EvidenceReceiptVerifier().verify(
            passportData: fixture.passport, observationData: changed,
            receiptData: fixture.receipt, trustStore: fixture.trustStore,
            verificationTime: fixture.verificationTime
        )
        #expect(!report.trusted)
        #expect(report.issues.contains { $0.code == "event_digest_mismatch" })
    }

    @Test("A valid signature from an unallowlisted policy is rejected")
    func rejectsUntrustedPolicy() throws {
        let fixture = try makeFixture()
        let key = EvidenceReceiptTrustedKey(
            authorityID: "authority.demo", policyID: "runtime-only", policyVersion: "1",
            policyDigest: "sha256:" + String(repeating: "b", count: 64), keyID: "key-1", publicKey: fixture.publicKeyBase64,
            validFrom: "2026-09-28T20:00:00Z", validUntil: "2026-09-28T22:00:00Z"
        )
        let store = EvidenceReceiptTrustStore(trustedKeys: [key])
        let report = try EvidenceReceiptVerifier().verify(
            passportData: fixture.passport, observationData: fixture.observation,
            receiptData: fixture.receipt, trustStore: store,
            verificationTime: fixture.verificationTime
        )
        #expect(!report.trusted)
        #expect(report.issues.contains { $0.code == "untrusted_issuer_or_policy" })
    }

    @Test("Receipt timestamps must be valid at the requested verification time")
    func expiredAtVerificationIsRejected() throws {
        let fixture = try makeFixture()
        let report = try EvidenceReceiptVerifier().verify(
            passportData: fixture.passport, observationData: fixture.observation,
            receiptData: fixture.receipt, trustStore: fixture.trustStore,
            verificationTime: Date(timeIntervalSince1970: 0)
        )
        #expect(!report.trusted)
        #expect(report.issues.contains { $0.code == "receipt_not_current" })
    }

    @Test("Nonempty accepted claims are rejected by this profile")
    func rejectsClaims() throws {
        let fixture = try makeFixture()
        var object = try JSONSerialization.jsonObject(with: fixture.receipt) as! [String: Any]
        object["accepted_claims"] = [["claim_id": "outcome", "level": "L8", "satisfied": true]]
        let report = try EvidenceReceiptVerifier().verify(
            passportData: fixture.passport, observationData: fixture.observation,
            receiptData: JSONSerialization.data(withJSONObject: object), trustStore: fixture.trustStore,
            verificationTime: fixture.verificationTime
        )
        #expect(!report.trusted)
        #expect(report.issues.contains { $0.code == "receipt_schema" })
    }

    @Test("Duplicate JSON names are rejected before dictionary decoding")
    func rejectsDuplicateKeys() throws {
        let fixture = try makeFixture()
        let receiptText = String(decoding: fixture.receipt, as: UTF8.self)
        let duplicated = Data(("{\"receipt_id\":\"shadow\"," + receiptText.dropFirst()).utf8)
        let report = try EvidenceReceiptVerifier().verify(
            passportData: fixture.passport, observationData: fixture.observation,
            receiptData: duplicated, trustStore: fixture.trustStore,
            verificationTime: fixture.verificationTime
        )
        #expect(!report.trusted)
        #expect(report.issues.contains { $0.code == "receipt_schema" })
    }

    @Test("Receipt signature bytes are verified, not trusted from their envelope")
    func rejectsModifiedSignature() throws {
        let fixture = try makeFixture()
        var object = try JSONSerialization.jsonObject(with: fixture.receipt) as! [String: Any]
        var signature = object["signature"] as! [String: Any]
        signature["value"] = Data(repeating: 0, count: 64).base64EncodedString()
        object["signature"] = signature
        let report = try EvidenceReceiptVerifier().verify(
            passportData: fixture.passport, observationData: fixture.observation,
            receiptData: JSONSerialization.data(withJSONObject: object), trustStore: fixture.trustStore,
            verificationTime: fixture.verificationTime
        )
        #expect(!report.trusted)
        #expect(report.issues.contains { $0.code == "signature_invalid" })
    }

    @Test("Versioned binary signing profile uses fixed length-prefixed UTF-8 fields")
    func signingProfileVector() {
        let bytes = ReceiptSigningProfile.payload(fields: [("a", "x"), ("bb", "yz")])
        var expected = Data("FeaturePassport\0EvidenceReceipt\0v1\0".utf8)
        for component in [Data([0, 0, 0, 1]), Data("a".utf8), Data([0, 0, 0, 1]), Data("x".utf8),
                          Data([0, 0, 0, 2]), Data("bb".utf8), Data([0, 0, 0, 2]), Data("yz".utf8)] {
            expected.append(component)
        }
        #expect(bytes == expected)
    }

    @Test("Offline trust-store JSON rejects unknown and duplicate fields")
    func strictTrustStoreEnvelope() throws {
        let fixture = try makeFixture()
        let encoded = try JSONEncoder().encode(fixture.trustStore)
        #expect(throws: Never.self) { try EvidenceReceiptTrustStore.decode(from: encoded) }

        let invalid = Data("""
        {"trusted_keys":[],"maximum_receipt_lifetime_seconds":86400,"clock_skew_seconds":60,"implicit_network_discovery":true}
        """.utf8)
        #expect(throws: (any Error).self) { try EvidenceReceiptTrustStore.decode(from: invalid) }
        let duplicate = Data("""
        {"trusted_keys":[],"maximum_receipt_lifetime_seconds":86400,"clock_skew_seconds":60,"clock_skew_seconds":30}
        """.utf8)
        #expect(throws: (any Error).self) { try EvidenceReceiptTrustStore.decode(from: duplicate) }
    }

    private struct Fixture {
        let passport: Data
        let observation: Data
        let receipt: Data
        let trustStore: EvidenceReceiptTrustStore
        let verificationTime: Date
        let publicKeyBase64: String
    }

    private func verify(_ fixture: Fixture) throws -> EvidenceReceiptVerificationReport {
        try EvidenceReceiptVerifier().verify(
            passportData: fixture.passport, observationData: fixture.observation,
            receiptData: fixture.receipt, trustStore: fixture.trustStore,
            verificationTime: fixture.verificationTime
        )
    }

    private func makeFixture() throws -> Fixture {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let passport = try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "feature_passport", "schema_version": 1,
            "metadata": ["feature_id": "feature.demo", "passport_id": "fp.demo", "version": "1", "status": "draft", "issuer": "demo"],
            "spec": [
                "intent": ["summary": "Demo", "acceptance_criteria": [["id": "works", "text": "It works"]]],
                "evidence": ["required_level": "L6", "probes": [["id": "run.v1", "event": "fp.feature.code_path.executed", "level": "L6", "required": true]]],
                "privacy": ["pii_allowed": false, "retention_days": 30, "raw_payload_storage": false]
            ]
        ])
        let passportDigest = EvidenceReceiptVerifier.sha256(passport)
        let observation = try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "feature_observation", "schema_version": 1,
            "event_name": "fp.feature.code_path.executed",
            "feature_passport": ["feature_id": "feature.demo", "passport_id": "fp.demo", "version": "1", "digest": passportDigest, "probe_id": "run.v1"],
            "delivery": ["environment": "test", "platform": "macos"],
            "observation": ["occurred_at": "2026-09-28T20:25:00Z", "result": "failure", "attributes": [:]],
            "integrity": ["event_id": "event-1", "idempotency_key": "test:event-1"]
        ])
        let eventDigest = EvidenceReceiptVerifier.sha256(observation)
        let acceptedAt = "2026-09-28T20:30:00Z"
        let validFrom = "2026-09-28T20:00:00Z"
        let validUntil = "2026-09-28T21:00:00Z"
        let policyDigest = "sha256:" + String(repeating: "a", count: 64)
        let fields: [(String, String)] = [
            ("artifact_kind", "evidence_receipt"), ("schema_version", "1"),
            ("authority.id", "authority.demo"), ("authority.policy_id", "runtime-only"),
            ("authority.policy_version", "1"), ("authority.policy_digest", policyDigest),
            ("feature_passport.feature_id", "feature.demo"), ("feature_passport.passport_id", "fp.demo"),
            ("feature_passport.version", "1"), ("feature_passport.digest", passportDigest),
            ("probe.id", "run.v1"), ("probe.event_name", "fp.feature.code_path.executed"),
            ("observation.event_id", "event-1"), ("observation.occurred_at", "2026-09-28T20:25:00Z"),
            ("receipt_id", "receipt-1"), ("accepted_claims", "[]"),
            ("hashing.canonicalization", ReceiptSigningProfile.identifier),
            ("hashing.digest_profile", ReceiptSigningProfile.digestIdentifier), ("hashing.event_hash", eventDigest),
            ("timestamps.accepted_at", acceptedAt), ("timestamps.valid_from", validFrom),
            ("timestamps.valid_until", validUntil), ("signature.algorithm", "Ed25519"), ("signature.key_id", "key-1")
        ]
        let payload = ReceiptSigningProfile.payload(fields: fields)
        let receiptHash = "sha256:" + SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let signature = try privateKey.signature(for: Data(SHA256.hash(data: payload))).base64EncodedString()
        let receipt = try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "evidence_receipt", "schema_version": 1,
            "authority": ["id": "authority.demo", "policy_id": "runtime-only", "policy_version": "1", "policy_digest": policyDigest],
            "feature_passport": ["feature_id": "feature.demo", "passport_id": "fp.demo", "version": "1", "digest": passportDigest],
            "probe": ["id": "run.v1", "event_name": "fp.feature.code_path.executed"],
            "observation": ["event_id": "event-1", "occurred_at": "2026-09-28T20:25:00Z"],
            "receipt_id": "receipt-1", "accepted_claims": [],
            "hashing": ["canonicalization": ReceiptSigningProfile.identifier,
                        "digest_profile": ReceiptSigningProfile.digestIdentifier,
                        "event_hash": eventDigest, "receipt_hash": receiptHash],
            "signature": ["algorithm": "Ed25519", "key_id": "key-1", "value": signature],
            "timestamps": ["accepted_at": acceptedAt, "valid_from": validFrom, "valid_until": validUntil]
        ])
        let trustedKey = EvidenceReceiptTrustedKey(
            authorityID: "authority.demo", policyID: "runtime-only", policyVersion: "1",
            policyDigest: policyDigest, keyID: "key-1", publicKey: publicKeyBase64,
            validFrom: validFrom, validUntil: validUntil
        )
        return Fixture(passport: passport, observation: observation, receipt: receipt,
            trustStore: EvidenceReceiptTrustStore(trustedKeys: [trustedKey]),
            verificationTime: ISO8601DateFormatter().date(from: "2026-09-28T20:35:00Z")!,
            publicKeyBase64: publicKeyBase64)
    }
}
