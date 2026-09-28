import Crypto
@testable import FeaturePassport
import Foundation
import Testing

@Suite("Local aggregate claim evaluation")
struct LocalAggregateClaimEvaluatorTests {
    @Test("Three trusted observations satisfy the explicit sequence predicate even at equal timestamps")
    func threeEventBundleSatisfies() throws {
        let fixture = try makeFixture()
        let report = try evaluate(fixture, pairs: Array(fixture.pairs.reversed()))
        #expect(report.satisfied)
        #expect(report.verdict == .localPredicateSatisfied)
        #expect(!report.signed)
        #expect(!report.replayProtection)
        #expect(report.issues.isEmpty)
        #expect(report.observationCount == 3)
        #expect(fixture.observations.map(\.occurredAt).allSatisfy { $0 == fixture.observations[0].occurredAt })
        let output = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
        #expect(output["artifact_kind"] as? String == "local_aggregate_claim_evaluation")
        #expect(output["signed"] as? Bool == false)
        #expect(output["replay_protection"] as? Bool == false)
        #expect(output["satisfied"] as? Bool == true)
        #expect(output["runtime_verified"] == nil)
    }

    @Test("A missing required probe fails closed")
    func missingProbeFails() throws {
        let fixture = try makeFixture()
        let report = try evaluate(fixture, pairs: Array(fixture.pairs.prefix(2)))
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "required_probe_missing" })
    }

    @Test("Observations from mixed operation IDs cannot be aggregated")
    func mixedOperationFails() throws {
        let fixture = try makeFixture(operationIDs: ["op-1", "op-2", "op-1"])
        let report = try evaluate(fixture)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "operation_id_mismatch" })
    }

    @Test("Probe order is established by signed semantic sequence, not wall clock or bundle order")
    func outOfOrderSequenceFails() throws {
        let fixture = try makeFixture(sequences: [10, 12, 11])
        let report = try evaluate(fixture)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "sequence_not_increasing" })
    }

    @Test("Duplicate semantic sequence values fail")
    func duplicateSequenceFails() throws {
        let fixture = try makeFixture(sequences: [10, 10, 12])
        let report = try evaluate(fixture)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "sequence_duplicate" })
    }

    @Test("Exact passport bytes are bound by the local claim policy")
    func passportDigestMismatchFails() throws {
        let fixture = try makeFixture()
        var policy = try JSONSerialization.jsonObject(with: fixture.policy) as! [String: Any]
        var passport = policy["feature_passport"] as! [String: Any]
        passport["digest"] = "sha256:" + String(repeating: "b", count: 64)
        policy["feature_passport"] = passport
        let changedPolicy = try JSONSerialization.data(withJSONObject: policy)
        let report = try evaluate(fixture, policy: changedPolicy)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "passport_digest_mismatch" })
    }

    @Test("Every pair must use the exact evidence receipt policy declared by the claim policy")
    func receiptPolicyMismatchFails() throws {
        let fixture = try makeFixture()
        var policy = try JSONSerialization.jsonObject(with: fixture.policy) as! [String: Any]
        var receiptPolicy = policy["receipt_policy"] as! [String: Any]
        receiptPolicy["policy_digest"] = "sha256:" + String(repeating: "b", count: 64)
        policy["receipt_policy"] = receiptPolicy
        let changedPolicy = try JSONSerialization.data(withJSONObject: policy)
        let report = try evaluate(fixture, policy: changedPolicy)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "receipt_policy_mismatch" })
    }

    @Test("Repeated event IDs fail even when each observation has a valid receipt")
    func duplicateEventIDFails() throws {
        let fixture = try makeFixture(eventIDs: ["event-1", "event-1", "event-3"])
        let report = try evaluate(fixture)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "duplicate_event_id" })
    }

    @Test("A matched failure result is rejected when that probe policy allows only success")
    func disallowedFailureResultFails() throws {
        let fixture = try makeFixture(results: [.success, .failure, .success])
        let report = try evaluate(fixture)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "result_not_allowed" })
        #expect(!report.issues.contains { $0.code.hasPrefix("receipt_") })
    }

    @Test("A receipt with an invalid signature cannot contribute to the local predicate")
    func untrustedReceiptFails() throws {
        let fixture = try makeFixture()
        var receipt = try JSONSerialization.jsonObject(with: fixture.pairs[0].receiptData) as! [String: Any]
        var signature = receipt["signature"] as! [String: Any]
        signature["value"] = Data(repeating: 0, count: 64).base64EncodedString()
        receipt["signature"] = signature
        let changedReceipt = try JSONSerialization.data(withJSONObject: receipt)
        var pairs = fixture.pairs
        pairs[0] = LocalAggregateClaimPair(observationData: pairs[0].observationData, receiptData: changedReceipt)
        let report = try evaluate(fixture, pairs: pairs)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "receipt_signature_invalid" })
    }

    @Test("Every event must match the exact environment declared by policy")
    func environmentMismatchFails() throws {
        let fixture = try makeFixture(environments: ["test", "production", "test"])
        let report = try evaluate(fixture)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "environment_mismatch" })
    }

    @Test("Mixed source/build identities fail even when every receipt verifies")
    func deliveryIdentityMismatchFails() throws {
        let fixture = try makeFixture(artifactDigests: ["sha256:build-a", "sha256:build-b", "sha256:build-a"])
        let report = try evaluate(fixture)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "delivery_identity_mismatch" })
        #expect(!report.issues.contains { $0.code.hasPrefix("receipt_") })
    }

    @Test("Absent and present delivery identity values are not treated as equal")
    func optionalDeliveryIdentityMismatchFails() throws {
        let fixture = try makeFixture(releaseIDs: [nil, "release-1", nil])
        let report = try evaluate(fixture)
        #expect(!report.satisfied)
        #expect(report.issues.contains { $0.code == "delivery_identity_mismatch" })
    }

    @Test("Noncanonical and overflowing sequence values fail")
    func invalidSequenceFails() throws {
        let leadingZero = try makeFixture(sequenceTexts: ["10", "011", "12"])
        let leadingReport = try evaluate(leadingZero)
        #expect(!leadingReport.satisfied)
        #expect(leadingReport.issues.contains { $0.code == "sequence_invalid" })

        let overflow = try makeFixture(sequenceTexts: ["10", "18446744073709551616", "12"])
        let overflowReport = try evaluate(overflow)
        #expect(!overflowReport.satisfied)
        #expect(overflowReport.issues.contains { $0.code == "sequence_invalid" })
    }

    @Test("An authorized signed decision verifies only after exact input binding and fresh evaluation")
    func signedDecisionVerifies() throws {
        let fixture = try makeFixture()
        let context = try decisionContext(fixture)
        let issued = try AggregateClaimDecisionIssuer().issue(
            inputs: context.inputs, authorization: context.authorization,
            signer: context.signer, evaluationTime: "2026-09-28T20:35:00Z"
        )
        #expect(issued.decision == .accepted)
        #expect(issued.predicateProfile == "local-aggregate-claim-evaluation-v1")
        #expect(issued.signature.profile == "fp-aggregate-decision-v1-fields")
        #expect(issued.signature.profile != "JCS")
        let data = try issued.encoded()
        #expect(data.count <= AggregateClaimDecision.maximumArtifactBytes)
        let report = try AggregateClaimDecisionVerifier().verify(
            decisionData: data, inputs: context.inputs, trustStore: context.decisionTrust
        )
        #expect(report.trusted)
        #expect(report.decision == .accepted)
        #expect(report.claimID == "claim.demo.route")
        let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(envelope["accepted_claims"] == nil)
        #expect(envelope["runtime_verified"] == nil)
    }

    @Test("Fixed inputs, evaluation time, and Ed25519 key produce the same decision identity")
    func signedDecisionIsRepeatable() throws {
        let fixture = try makeFixture()
        let context = try decisionContext(fixture)
        let issuer = AggregateClaimDecisionIssuer()
        let first = try issuer.issue(inputs: context.inputs, authorization: context.authorization,
            signer: context.signer, evaluationTime: "2026-09-28T20:35:00Z")
        let second = try issuer.issue(inputs: context.inputs, authorization: context.authorization,
            signer: context.signer, evaluationTime: "2026-09-28T20:35:00Z")
        #expect(first.decisionDigest == second.decisionDigest)
        let firstPayload = AggregateClaimDecisionSigningProfile.payload(for: first)
        let secondPayload = AggregateClaimDecisionSigningProfile.payload(for: second)
        #expect(firstPayload == secondPayload)
        let authorizedPublicKey = Data(base64Encoded: context.decisionTrust.trustedKeys[0].publicKey)!
        #expect(context.signer.publicKey == authorizedPublicKey)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: context.signer.publicKey)
        #expect(publicKey.isValidSignature(Data(base64Encoded: first.signature.value)!, for: firstPayload))
        #expect(publicKey.isValidSignature(Data(base64Encoded: second.signature.value)!, for: secondPayload))
        let firstReport = try AggregateClaimDecisionVerifier().verify(decisionData: encodeSorted(first),
            inputs: context.inputs, trustStore: context.decisionTrust)
        let secondReport = try AggregateClaimDecisionVerifier().verify(decisionData: encodeSorted(second),
            inputs: context.inputs, trustStore: context.decisionTrust)
        #expect(firstReport.trusted)
        #expect(secondReport.trusted)
    }

    @Test("Every exact input byte stream is bound by the signed decision")
    func decisionRejectsTamperedInputs() throws {
        let fixture = try makeFixture()
        let context = try decisionContext(fixture)
        let decision = try AggregateClaimDecisionIssuer().issue(inputs: context.inputs,
            authorization: context.authorization, signer: context.signer,
            evaluationTime: "2026-09-28T20:35:00Z")
        let decisionData = try encodeSorted(decision)
        var variants: [AggregateClaimDecisionInputs] = []

        variants.append(.init(passportData: fixture.passport + Data([0x20]),
            claimPolicyData: context.inputs.claimPolicyData, bundleData: context.inputs.bundleData,
            receiptTrustStoreData: context.inputs.receiptTrustStoreData, pairs: context.inputs.pairs))
        variants.append(.init(passportData: fixture.passport,
            claimPolicyData: fixture.policy + Data([0x20]), bundleData: context.inputs.bundleData,
            receiptTrustStoreData: context.inputs.receiptTrustStoreData, pairs: context.inputs.pairs))
        variants.append(.init(passportData: fixture.passport, claimPolicyData: fixture.policy,
            bundleData: context.inputs.bundleData + Data([0x20]),
            receiptTrustStoreData: context.inputs.receiptTrustStoreData, pairs: context.inputs.pairs))
        variants.append(.init(passportData: fixture.passport, claimPolicyData: fixture.policy,
            bundleData: context.inputs.bundleData,
            receiptTrustStoreData: context.inputs.receiptTrustStoreData + Data([0x20]), pairs: context.inputs.pairs))
        var observationPairs = context.inputs.pairs
        observationPairs[0] = .init(observationPath: observationPairs[0].observationPath,
            receiptPath: observationPairs[0].receiptPath,
            observationData: observationPairs[0].observationData + Data([0x20]),
            receiptData: observationPairs[0].receiptData)
        variants.append(.init(passportData: fixture.passport, claimPolicyData: fixture.policy,
            bundleData: context.inputs.bundleData, receiptTrustStoreData: context.inputs.receiptTrustStoreData,
            pairs: observationPairs))
        var receiptPairs = context.inputs.pairs
        receiptPairs[0] = .init(observationPath: receiptPairs[0].observationPath,
            receiptPath: receiptPairs[0].receiptPath, observationData: receiptPairs[0].observationData,
            receiptData: receiptPairs[0].receiptData + Data([0x20]))
        variants.append(.init(passportData: fixture.passport, claimPolicyData: fixture.policy,
            bundleData: context.inputs.bundleData, receiptTrustStoreData: context.inputs.receiptTrustStoreData,
            pairs: receiptPairs))

        for changedInputs in variants {
            let report = try AggregateClaimDecisionVerifier().verify(
                decisionData: decisionData, inputs: changedInputs, trustStore: context.decisionTrust
            )
            #expect(!report.trusted)
            #expect(report.issues.contains { $0.code == "decision_input_mismatch" })
        }
    }

    @Test("Policy authorization and signing key identity are checked before issuance")
    func unauthorizedPolicyAndKeyCannotIssue() throws {
        let fixture = try makeFixture()
        let context = try decisionContext(fixture)
        let wrongPolicy = AggregateClaimDecisionAuthorization(authorityID: "decision.authority",
            keyID: "decision-key", publicKey: context.signer.publicKey,
            authorizedClaimPolicyDigests: ["sha256:" + String(repeating: "0", count: 64)])
        do {
            _ = try AggregateClaimDecisionIssuer().issue(inputs: context.inputs, authorization: wrongPolicy,
                signer: context.signer, evaluationTime: "2026-09-28T20:35:00Z")
            Issue.record("Issuer accepted a policy digest absent from its authorization allowlist")
        } catch { }
        let wrongKey = AggregateClaimDecisionAuthorization(authorityID: "decision.authority",
            keyID: "decision-key", publicKey: Data(repeating: 0, count: 32),
            authorizedClaimPolicyDigests: [EvidenceReceiptVerifier.sha256(fixture.policy)])
        do {
            _ = try AggregateClaimDecisionIssuer().issue(inputs: context.inputs, authorization: wrongKey,
                signer: context.signer, evaluationTime: "2026-09-28T20:35:00Z")
            Issue.record("Issuer accepted a signer key different from its authorization")
        } catch { }
    }

    @Test("Decision trust authority must allowlist the exact policy and signature")
    func decisionVerifierRequiresAuthorizedKey() throws {
        let fixture = try makeFixture()
        let context = try decisionContext(fixture)
        let issued = try AggregateClaimDecisionIssuer().issue(inputs: context.inputs,
            authorization: context.authorization, signer: context.signer,
            evaluationTime: "2026-09-28T20:35:00Z")
        let deniedTrust = AggregateClaimDecisionTrustStore(trustedKeys: [
            .init(authorityID: "decision.authority", keyID: "decision-key",
                  publicKey: context.signer.publicKey.base64EncodedString(),
                  authorizedClaimPolicyDigests: ["sha256:" + String(repeating: "0", count: 64)])
        ])
        let denied = try AggregateClaimDecisionVerifier().verify(decisionData: encodeSorted(issued),
            inputs: context.inputs, trustStore: deniedTrust)
        #expect(!denied.trusted)
        #expect(denied.issues.contains { $0.code == "decision_authority_untrusted" })

        let oversizedTrustStore = AggregateClaimDecisionTrustStore(trustedKeys: [
            .init(authorityID: String(repeating: "x", count: 1_000_001), keyID: "decision-key",
                  publicKey: context.signer.publicKey.base64EncodedString(),
                  authorizedClaimPolicyDigests: [EvidenceReceiptVerifier.sha256(fixture.policy)])
        ])
        let oversizedTrustReport = try AggregateClaimDecisionVerifier().verify(
            decisionData: encodeSorted(issued), inputs: context.inputs, trustStore: oversizedTrustStore
        )
        #expect(!oversizedTrustReport.trusted)
        #expect(oversizedTrustReport.issues.contains { $0.code == "decision_trust_store_invalid" })

        var envelope = try JSONSerialization.jsonObject(with: encodeSorted(issued)) as! [String: Any]
        envelope["signature"] = ["algorithm": "Ed25519", "profile": "fp-aggregate-decision-v1-fields",
                                  "value": Data(repeating: 0, count: 64).base64EncodedString()]
        let tamperedSignature = try JSONSerialization.data(withJSONObject: envelope)
        let invalid = try AggregateClaimDecisionVerifier().verify(decisionData: tamperedSignature,
            inputs: context.inputs, trustStore: context.decisionTrust)
        #expect(!invalid.trusted)
        #expect(invalid.issues.contains { $0.code == "decision_signature_invalid" })
    }

    @Test("Direct verifier rejects an oversized decision before parsing JSON")
    func oversizedDecisionFailsBeforeParsing() throws {
        let fixture = try makeFixture()
        let context = try decisionContext(fixture)
        let oversized = Data(repeating: 0x20, count: 1_000_001)
        let report = try AggregateClaimDecisionVerifier().verify(decisionData: oversized,
            inputs: context.inputs, trustStore: context.decisionTrust)
        #expect(!report.trusted)
        #expect(report.issues.map(\.code) == ["size_limit"])
    }

    @Test("Issuer refuses oversized authority identifiers before signing an unverifiable artifact")
    func issuerRejectsOversizedIdentityFields() throws {
        let fixture = try makeFixture()
        let context = try decisionContext(fixture)
        let countingSigner = CallCountingDecisionSigner(wrapped: context.signer)
        let largeID = String(repeating: "x", count: 1_000_001)
        let authorizations = [
            AggregateClaimDecisionAuthorization(authorityID: largeID, keyID: "decision-key",
                publicKey: context.signer.publicKey,
                authorizedClaimPolicyDigests: context.authorization.authorizedClaimPolicyDigests),
            AggregateClaimDecisionAuthorization(authorityID: "decision.authority", keyID: largeID,
                publicKey: context.signer.publicKey,
                authorizedClaimPolicyDigests: context.authorization.authorizedClaimPolicyDigests)
        ]
        for authorization in authorizations {
            do {
                _ = try AggregateClaimDecisionIssuer().issue(inputs: context.inputs,
                    authorization: authorization, signer: countingSigner,
                    evaluationTime: "2026-09-28T20:35:00Z")
                Issue.record("Issuer returned an artifact larger than the verifier byte limit")
            } catch { }
            #expect(countingSigner.signCallCount == 0)
        }
    }

    @Test("A trusted not-satisfied decision records only the local predicate result")
    func notSatisfiedDecisionVerifies() throws {
        let fixture = try makeFixture(results: [.success, .failure, .success])
        let context = try decisionContext(fixture)
        let issued = try AggregateClaimDecisionIssuer().issue(inputs: context.inputs,
            authorization: context.authorization, signer: context.signer,
            evaluationTime: "2026-09-28T20:35:00Z")
        #expect(issued.decision == .notSatisfied)
        let report = try AggregateClaimDecisionVerifier().verify(decisionData: encodeSorted(issued),
            inputs: context.inputs, trustStore: context.decisionTrust)
        #expect(report.trusted)
        #expect(report.decision == .notSatisfied)
    }

    private struct TestDecisionSigner: AggregateClaimDecisionSigner {
        let key: Curve25519.Signing.PrivateKey
        var publicKey: Data { key.publicKey.rawRepresentation }
        func sign(message: Data) throws -> Data { try key.signature(for: message) }
    }

    private final class CallCountingDecisionSigner: AggregateClaimDecisionSigner, @unchecked Sendable {
        let wrapped: TestDecisionSigner
        private let lock = NSLock()
        private var calls = 0

        init(wrapped: TestDecisionSigner) { self.wrapped = wrapped }
        var publicKey: Data { wrapped.publicKey }
        var signCallCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }
        func sign(message: Data) throws -> Data {
            lock.lock()
            calls += 1
            lock.unlock()
            return try wrapped.sign(message: message)
        }
    }

    private func decisionContext(_ fixture: Fixture) throws -> (
        inputs: AggregateClaimDecisionInputs,
        signer: TestDecisionSigner,
        authorization: AggregateClaimDecisionAuthorization,
        decisionTrust: AggregateClaimDecisionTrustStore
    ) {
        let bundle = LocalAggregateClaimBundle(artifactKind: "local_aggregate_claim_bundle", schemaVersion: 1,
            pairs: fixture.pairs.enumerated().map { index, _ in
                .init(observation: "observations/\(index).json", receipt: "receipts/\(index).json")
            })
        let bundleEncoder = JSONEncoder()
        bundleEncoder.outputFormatting = [.sortedKeys]
        let bundleData = try bundleEncoder.encode(bundle)
        let references = try LocalAggregateClaimBundle.decode(from: bundleData).pairs
        let inputPairs = fixture.pairs.enumerated().map { index, pair in
            AggregateClaimDecisionInputs.Pair(observationPath: references[index].observation,
                receiptPath: references[index].receipt, observationData: pair.observationData,
                receiptData: pair.receiptData)
        }
        let receiptStoreEncoder = JSONEncoder()
        receiptStoreEncoder.outputFormatting = [.sortedKeys]
        let receiptTrustData = try receiptStoreEncoder.encode(fixture.trustStore)
        let inputs = AggregateClaimDecisionInputs(passportData: fixture.passport,
            claimPolicyData: fixture.policy, bundleData: bundleData,
            receiptTrustStoreData: receiptTrustData, pairs: inputPairs)
        let key = Curve25519.Signing.PrivateKey()
        let signer = TestDecisionSigner(key: key)
        let policyDigest = EvidenceReceiptVerifier.sha256(fixture.policy)
        let authorization = AggregateClaimDecisionAuthorization(authorityID: "decision.authority",
            keyID: "decision-key", publicKey: signer.publicKey,
            authorizedClaimPolicyDigests: [policyDigest])
        let decisionTrust = AggregateClaimDecisionTrustStore(trustedKeys: [
            .init(authorityID: "decision.authority", keyID: "decision-key",
                  publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
                  authorizedClaimPolicyDigests: [policyDigest])
        ])
        return (inputs, signer, authorization, decisionTrust)
    }

    private func encodeSorted<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private struct Fixture {
        let passport: Data
        let policy: Data
        let pairs: [LocalAggregateClaimPair]
        let trustStore: EvidenceReceiptTrustStore
        let verificationTime: Date
        let observations: [RuntimeObservation.Observation]
    }

    private func evaluate(_ fixture: Fixture, pairs: [LocalAggregateClaimPair]? = nil,
                          policy: Data? = nil) throws -> LocalAggregateClaimEvaluation {
        try LocalAggregateClaimEvaluator().evaluate(
            passportData: fixture.passport, policyData: policy ?? fixture.policy,
            pairs: pairs ?? fixture.pairs, trustStore: fixture.trustStore,
            verificationTime: fixture.verificationTime
        )
    }

    private func makeFixture(sequences: [UInt64] = [10, 11, 12],
                             sequenceTexts: [String]? = nil,
                             operationIDs: [String] = ["op-1", "op-1", "op-1"],
                             eventIDs: [String] = ["event-1", "event-2", "event-3"],
                             environments: [String] = ["test", "test", "test"],
                             artifactDigests: [String?] = ["sha256:build-a", "sha256:build-a", "sha256:build-a"],
                             releaseIDs: [String?] = [nil, nil, nil],
                             buildNumbers: [String?] = [nil, nil, nil],
                             results: [RuntimeObservation.Observation.Result] = [.success, .success, .success]) throws -> Fixture {
        let key = Curve25519.Signing.PrivateKey()
        let policyID = "receipt-policy"
        let policyVersion = "1"
        let receiptPolicyDigest = "sha256:" + String(repeating: "a", count: 64)
        let passport = try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "feature_passport", "schema_version": 1,
            "metadata": ["feature_id": "feature.demo", "passport_id": "fp.demo", "version": "1", "status": "draft", "issuer": "demo"],
            "spec": [
                "intent": ["summary": "Demo", "acceptance_criteria": [["id": "works", "text": "It works"]]],
                "evidence": ["required_level": "L6", "probes": (1...3).map { index in
                    ["id": "probe-\(index)", "event": "event.probe-\(index)", "level": "L6", "required": true,
                     "attributes": ["sequence"], "required_runtime_fields": ["operation_id"]]
                }],
                "privacy": ["pii_allowed": false, "retention_days": 30, "raw_payload_storage": false]
            ]
        ])
        let passportDigest = EvidenceReceiptVerifier.sha256(passport)
        let observations = (0..<3).map { index -> RuntimeObservation.Observation in
            let text = sequenceTexts?[index] ?? String(sequences[index])
            return RuntimeObservation.Observation(
                occurredAt: "2026-09-28T20:25:00Z", result: results[index], attributes: ["sequence": text]
            )
        }
        let eventJSONs = try (0..<3).map { index in
            let delivery: [String: Any] = [
                "environment": environments[index], "platform": "ios",
                "git_sha": "commit-demo", "artifact_digest": jsonValue(artifactDigests[index]),
                "release_id": jsonValue(releaseIDs[index]), "build_number": jsonValue(buildNumbers[index])
            ]
            return try JSONSerialization.data(withJSONObject: [
                "artifact_kind": "feature_observation", "schema_version": 1,
                "event_name": "event.probe-\(index + 1)",
                "feature_passport": ["feature_id": "feature.demo", "passport_id": "fp.demo", "version": "1", "digest": passportDigest, "probe_id": "probe-\(index + 1)"],
                "delivery": delivery,
                "runtime": ["operation_id": operationIDs[index]],
                "observation": ["occurred_at": "2026-09-28T20:25:00Z", "result": results[index].rawValue, "attributes": ["sequence": observations[index].attributes["sequence"]!]],
                "integrity": ["event_id": eventIDs[index], "idempotency_key": "test:\(index)"]
            ])
        }
        let eventDigests = eventJSONs.map(EvidenceReceiptVerifier.sha256)
        let acceptedAt = "2026-09-28T20:30:00Z"
        let validFrom = "2026-09-28T20:00:00Z"
        let validUntil = "2026-09-28T21:00:00Z"
        let receiptPairs = try (0..<3).map { index -> LocalAggregateClaimPair in
            let eventID = eventIDs[index]
            let probeID = "probe-\(index + 1)"
            let eventName = "event.\(probeID)"
            let fields: [(String, String)] = [
                ("artifact_kind", "evidence_receipt"), ("schema_version", "1"),
                ("authority.id", "authority.demo"), ("authority.policy_id", policyID),
                ("authority.policy_version", policyVersion), ("authority.policy_digest", receiptPolicyDigest),
                ("feature_passport.feature_id", "feature.demo"), ("feature_passport.passport_id", "fp.demo"),
                ("feature_passport.version", "1"), ("feature_passport.digest", passportDigest),
                ("probe.id", probeID), ("probe.event_name", eventName),
                ("observation.event_id", eventID), ("observation.occurred_at", "2026-09-28T20:25:00Z"),
                ("receipt_id", "receipt-\(index + 1)"), ("accepted_claims", "[]"),
                ("hashing.canonicalization", "fp-receipt-v1-fields"),
                ("hashing.digest_profile", "fp-exact-bytes-sha256-v1"), ("hashing.event_hash", eventDigests[index]),
                ("timestamps.accepted_at", acceptedAt), ("timestamps.valid_from", validFrom),
                ("timestamps.valid_until", validUntil), ("signature.algorithm", "Ed25519"),
                ("signature.key_id", "key-1")
            ]
            let payload = ReceiptSigningProfile.payload(fields: fields)
            let receiptHash = "sha256:" + SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            let signature = try key.signature(for: Data(SHA256.hash(data: payload))).base64EncodedString()
            let receipt = try JSONSerialization.data(withJSONObject: [
                "artifact_kind": "evidence_receipt", "schema_version": 1,
                "authority": ["id": "authority.demo", "policy_id": policyID, "policy_version": policyVersion, "policy_digest": receiptPolicyDigest],
                "feature_passport": ["feature_id": "feature.demo", "passport_id": "fp.demo", "version": "1", "digest": passportDigest],
                "probe": ["id": probeID, "event_name": eventName],
                "observation": ["event_id": eventID, "occurred_at": "2026-09-28T20:25:00Z"],
                "receipt_id": "receipt-\(index + 1)", "accepted_claims": [],
                "hashing": ["canonicalization": "fp-receipt-v1-fields", "digest_profile": "fp-exact-bytes-sha256-v1", "event_hash": eventDigests[index], "receipt_hash": receiptHash],
                "signature": ["algorithm": "Ed25519", "key_id": "key-1", "value": signature],
                "timestamps": ["accepted_at": acceptedAt, "valid_from": validFrom, "valid_until": validUntil]
            ])
            return LocalAggregateClaimPair(observationData: eventJSONs[index], receiptData: receipt)
        }
        let policy = try JSONSerialization.data(withJSONObject: [
            "artifact_kind": "local_aggregate_claim_policy", "schema_version": 1,
            "policy_id": "local-demo", "policy_version": "1", "claim_id": "claim.demo.route",
            "feature_passport": ["feature_id": "feature.demo", "passport_id": "fp.demo", "version": "1", "digest": passportDigest],
            "receipt_policy": ["authority_id": "authority.demo", "policy_id": policyID, "policy_version": policyVersion, "policy_digest": receiptPolicyDigest],
            "environment": "test", "sequence_attribute": "sequence",
            "ordered_probes": (1...3).map { ["probe_id": "probe-\($0)", "allowed_results": ["success"]] }
        ])
        let trustedKey = EvidenceReceiptTrustedKey(
            authorityID: "authority.demo", policyID: policyID, policyVersion: policyVersion,
            policyDigest: receiptPolicyDigest, keyID: "key-1",
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(), validFrom: validFrom, validUntil: validUntil
        )
        return Fixture(passport: passport, policy: policy, pairs: receiptPairs,
            trustStore: EvidenceReceiptTrustStore(trustedKeys: [trustedKey]),
            verificationTime: EvidenceReceiptTimestamp.parseRFC3339UTC("2026-09-28T20:35:00Z")!,
            observations: observations)
    }

    private func jsonValue(_ value: String?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }
}
