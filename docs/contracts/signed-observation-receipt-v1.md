# Signed observation receipt verifier v1

This experimental verifier accepts a single policy-scoped authority receipt
for one Feature Passport and one normalized observation. It verifies an
Ed25519 signature against an explicit offline allowlist and reruns the local
runtime observation matcher. A trusted result means only that the allowlisted
authority signed acceptance of this contract-matched observation under the
allowlisted policy digest.

The verifier does not create receipts. The separate
[bounded issuer](observation-receipt-issuance-v1.md) can issue local contract-match
receipts using an explicitly configured signing capability. No private signing keys belong in this repository.

## Digest and signature profile

The receipt schema is a bounded profile of FP-RFC-0001 v0.3:

- `hashing.digest_profile` is exactly `fp-exact-bytes-sha256-v1`.
- `feature_passport.digest` is `sha256:` plus lowercase hex SHA-256 of the
  exact passport input bytes supplied to the verifier.
- `hashing.event_hash` is `sha256:` plus lowercase hex SHA-256 of the exact
  normalized observation input bytes supplied to the verifier.
- The observation's `feature_passport.digest` must equal the first digest.
  This links one exact passport byte stream and prevents a whitespace or
  serialization change from inheriting the old receipt.
- Both input files must be valid under the local passport/observation
  validators. Raw-byte digesting is deliberate and versioned here; this
  profile does not claim to implement the RFC's proposed canonical passport
  digest or JSON Canonicalization Scheme (JCS).
- `hashing.canonicalization` is exactly `fp-receipt-v1-fields`. The receipt
  signing input begins with UTF-8 bytes `FeaturePassport\0EvidenceReceipt\0v1\0`
  and then encodes each field name and value as UTF-8, each preceded by its
  32-bit unsigned big-endian byte length. The verifier uses the fixed field
  sequence in `EvidenceReceiptVerifier`; it rejects extra or missing JSON
  fields and duplicate JSON object names. The `receipt_hash` and signature
  value are excluded; all authority, policy, passport, probe, event, timestamp,
  receipt identity, signature algorithm, and key ID fields are covered.
- `hashing.receipt_hash` is SHA-256 of those signing-input bytes. Ed25519 signs
  the 32 raw receipt-hash bytes. This is a versioned binary profile, **not JCS**.

The profile intentionally hashes exact input bytes instead of introducing a
partial or unverified JCS implementation. Reformatting a passport or
observation changes its digest and requires a newly issued receipt.

## Receipt JSON

The only accepted v1 envelope is:

```json
{
  "artifact_kind": "evidence_receipt",
  "schema_version": 1,
  "authority": {
    "id": "evidence-authority",
    "policy_id": "runtime-contract-match",
    "policy_version": "1",
    "policy_digest": "sha256:<64-lowercase-hex>"
  },
  "feature_passport": {
    "feature_id": "feature.demo",
    "passport_id": "fp.demo",
    "version": "1.0.0",
    "digest": "sha256:<64-lowercase-hex>"
  },
  "probe": { "id": "demo.run.v1", "event_name": "fp.feature.code_path.executed" },
  "observation": {
    "event_id": "event-1",
    "occurred_at": "2026-09-28T20:25:00Z"
  },
  "receipt_id": "receipt-1",
  "accepted_claims": [],
  "hashing": {
    "canonicalization": "fp-receipt-v1-fields",
    "digest_profile": "fp-exact-bytes-sha256-v1",
    "event_hash": "sha256:<64-lowercase-hex>",
    "receipt_hash": "sha256:<64-lowercase-hex>"
  },
  "signature": {
    "algorithm": "Ed25519",
    "key_id": "authority-key-1",
    "value": "<base64-64-byte-signature>"
  },
  "timestamps": {
    "accepted_at": "2026-09-28T20:30:00Z",
    "valid_from": "2026-09-28T20:30:00Z",
    "valid_until": "2026-09-29T20:30:00Z"
  }
}
```

`accepted_claims` must be empty. Aggregate, successful-execution, and user
outcome claims are outside this profile. The receipt may accept an observation
whose `result` is `failure` or `neutral`; its trusted verdict certifies the
authority's signature and local contract match, not success.

## Offline trust store and CLI

The trust store is caller-supplied local configuration. It pins the authority,
policy ID/version/digest, key ID, raw Ed25519 public key, and key validity
window. No network resolution, PKI discovery, or implicit global key store is
used. A trust store is limited to 1,024 keys and 1 MB; configured receipt
lifetime is capped at 30 days and clock skew at 300 seconds.

```json
{
  "trusted_keys": [
    {
      "authority_id": "evidence-authority",
      "policy_id": "runtime-contract-match",
      "policy_version": "1",
      "policy_digest": "sha256:<64-lowercase-hex>",
      "key_id": "authority-key-1",
      "public_key": "<base64-32-byte-raw-ed25519-key>",
      "valid_from": "2026-01-01T00:00:00Z",
      "valid_until": "2027-01-01T00:00:00Z"
    }
  ],
  "maximum_receipt_lifetime_seconds": 86400,
  "clock_skew_seconds": 60
}
```

```sh
feature-passport verify-receipt passport.json observation.json receipt.json \
  --trust-store trust-store.json [--at 2026-09-28T20:35:00Z]
```

The verifier checks exact input-byte digests under the named digest profile,
receipt/observation identity,
passport/probe/event contract matching, the empty-claims restriction, the
allowlisted authority/policy/key tuple, RFC 3339 UTC timestamp bounds, receipt
hash, and Ed25519 signature. It fails closed for malformed input, duplicate
JSON member names, unsupported algorithms/profiles, untrusted keys or policies,
expired/out-of-window receipts, and contract mismatch.

Exit status is 0 for `trusted_observation_receipt`, 1 for a rejected receipt,
and 2 for usage, file, or verifier errors. Verification at a supplied `--at`
time is deterministic; without it, the local current time is used.

## Explicit limits

This receipt is not a delivery attestation and does not prove that a build was
released, deployed, or observed in production. It does not independently
corroborate the client signal, enforce idempotency uniqueness or replay
prevention, validate artifact provenance, issue receipts, or claim
`runtime_verified`. The trust store is an offline allowlist controlled by the
caller and must be protected and reviewed as authority configuration.

Ed25519 and SHA-256 use Apple's `swift-crypto` package (`Crypto` product),
distributed under Apache-2.0. The verifier uses its CryptoKit-compatible API
on Apple platforms and the package's BoringSSL-backed implementation on Linux.
