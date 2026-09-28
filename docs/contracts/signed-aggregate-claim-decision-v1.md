# Signed aggregate claim decision v1

This bounded profile signs a fresh rerun of the local aggregate predicate. It
provides a scoped decision artifact for exact supplied bytes; it is not a
delivery attestation, replay ledger, production issuer service, or feature
outcome claim. No signing key or production signer is included in this
repository. Library callers inject an Ed25519 signer and an authorization that
allowlists the exact SHA-256 digest of the claim-policy input bytes.

`accepted` means only that the authorized policy's exact local aggregate
predicate was satisfied by the supplied passport, bundle, observations,
receipts, and receipt trust-store bytes at the signed evaluation time.
`not_satisfied` is a valid signed result when the policy is structurally valid
but its predicate fails. The artifact has no `accepted_claims` and never emits
`runtime_verified` or an outcome statement.

## Exact inputs and binding

The issuer and verifier receive the exact passport, policy, bundle, and receipt
trust-store bytes, plus resolved observation/receipt byte pairs. Each resolved
pair includes its bundle path references. The library verifies that the
references exactly match the decoded bundle entries in order. Inputs retain
the bounds of the local evaluator: 10 MB passport, 256 KB policy/bundle, 1 MB
receipt trust store, 64 pairs, 10 MB per observation, 256 KB per receipt, and
64 MB total pair bytes. The issuer's sorted-key JSON serialization and the
verifier's raw decision input are both capped at 1 MB. The issuer checks a
same-length signature/digest placeholder before calling the signer, so an
oversized artifact is never issued. Call `AggregateClaimDecision.encoded()` to
obtain the bounded sorted-key representation.

The signed decision records SHA-256 digests of the exact passport, policy,
bundle, and receipt trust-store bytes. It also records both exact byte digests
and the path references for every observation/receipt pair. The policy digest,
passport metadata, claim ID, predicate profile, decision authority/key, and
explicit RFC 3339 UTC evaluation time are signed. The verifier recomputes every
digest, rechecks bundle-to-pair references, verifies the authority signature,
then reruns `LocalAggregateClaimEvaluator` at the signed time. It accepts only
when the rerun's identity and accepted/not-satisfied decision match the signed
artifact.

The exact evidence receipt trust-store bytes are bound into the artifact. The
decision authority trust store is separate verifier configuration; it is
provided explicitly and is not an implicit network or global trust source.

## Signing profile

`decision_profile` and `signature.profile` are exactly
`fp-aggregate-decision-v1-fields`; `signature.algorithm` is [Ed25519
(RFC 8032)](https://www.rfc-editor.org/rfc/rfc8032).
The signing message begins with the distinct domain separator
`FeaturePassport\0AggregateClaimDecision\0v1\0`, followed by the fixed v1
ordered name/value fields. Each UTF-8 field name and value is prefixed with its
32-bit big-endian byte length. Pair references and digests follow bundle order.
The profile is versioned binary field encoding, **not JCS**. `decision_digest`
is SHA-256 of the complete signing message and provides the repeatable decision
identity for fixed inputs and evaluation time.

The [Swift CryptoKit Ed25519 implementation](https://github.com/apple/swift-crypto/blob/4.5.1/Sources/Crypto/Signatures/Ed25519.swift#L73-L82)
documents that its Ed25519 implementation may randomize signature bytes across
calls for the same key and message. Therefore equal
`decision_digest` values identify the same decision payload, while valid
signature byte strings need not be identical. Verifiers validate each
signature independently.

## Decision authority trust

The verifier's explicit offline trust store has this exact envelope:

```json
{
  "trusted_keys": [
    {
      "authority_id": "local-aggregate-authority",
      "key_id": "decision-key-1",
      "public_key": "<base64-32-byte-raw-ed25519-key>",
      "authorized_claim_policy_digests": ["sha256:<64-lowercase-hex>"]
    }
  ]
}
```

Unknown fields, duplicate JSON names, duplicate authority/key pairs, malformed
keys, duplicate or malformed digests, empty allowlists, and stores over 1 MB
are rejected. The trust store is capped at 1 MB and 1,024 keys; each key may
allowlist at most 1,024 claim-policy digests. Direct library trust-store values
are subject to the same checks. The signing-side
`AggregateClaimDecisionAuthorization` has the same authority/key identity and
an exact allowlist of at most 1,024 policy digests. The injected signer's
public key must equal the public key in that authorization. This profile does
not distribute, rotate, or revoke authority keys.

## CLI verification

```sh
feature-passport verify-decision passport.json claim-policy.json bundle.json \
  decision.json --trust-store evidence-receipt-trust.json \
  --decision-trust aggregate-decision-trust.json
```

The verifier uses the evaluation time embedded in the signed artifact; it does
not accept a caller override. Exit status `0` means the signed decision is
trusted and its local predicate was freshly reproduced. This includes a
trusted `not_satisfied` decision. Exit `1` means the artifact is rejected or
the exact inputs/predicate do not match; exit `2` means invocation, file,
trust-store, bundle, or internal error.

There is no production issuance CLI or key store. Tests use ephemeral in-memory
keys only. The profile has no durable replay or idempotency ledger, so it
cannot establish that the same decision was not issued or consumed before.
It does not prove the provenance or deployment of any delivery identity, nor
does it infer user exposure or outcome from observations.
