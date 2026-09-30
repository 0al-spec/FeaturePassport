# Observation receipt issuance v1

This implements the first bounded issuer slice of SpecGraph proposal 0047's
cross-repository handoff. FeaturePassport remains provider-neutral: no graph IDs,
service or schema is required. The issuer accepts exact contract-matched
observation bytes under an explicitly authorized policy; it does not attest
execution origin, deployment, replay uniqueness, successful execution or outcomes.
A matched failure or neutral observation may receive a receipt with empty claims.

## Policy input

The strict `observation_receipt_policy` envelope has these exact fields:

```json
{
  "artifact_kind": "observation_receipt_policy",
  "schema_version": 1,
  "policy_id": "local-contract-match",
  "policy_version": "1",
  "predicate_profile": "exact_contract_match_v1",
  "allowed_environments": ["local-test"],
  "maximum_receipt_lifetime_seconds": 3600
}
```

Only this predicate is implemented. Unknown/duplicate JSON fields and unsupported
profiles are rejected. Policy bytes are limited to 256 KB; environments are a
nonempty unique list of at most 64 names; identifiers/names are at most 128 UTF-8
bytes; lifetime is 1 second to 30 days. The policy digest is SHA-256 of exact input
bytes. Reformatting changes authorization. The observation must match both the
passport and allowed environment; its result is not required to be success.

## Issuance API and authorization

`EvidenceReceiptIssuer.issue` receives exact passport/observation/policy bytes,
an `EvidenceReceiptTrustedKey` authorization, an explicit
`EvidenceReceiptIssuanceRequest`, and an injected `EvidenceReceiptSigner`.
The authority must authorize that exact policy ID/version/digest and public key.
The key's validity interval must be ordered. No authority is selected implicitly.

Passport, observation, authorization and time checks precede `sign`. The shared
receipt model/profile is used by issuer and verifier. An unsigned placeholder
passes through verifier preflight and may fail only signature validation; all
other failures prevent signer invocation. The signer signs the 32 raw bytes of
the receipt payload SHA-256. The issued receipt is reverified before returning.
A bad signer output never becomes an issued receipt. Receipt request ID is
nonblank and at most 1,024 UTF-8 bytes; existing verifier size limits apply.

Receipt validity/acceptance time must pass policy/key bounds with zero issuer
clock skew. Observation time cannot be later than acceptance. The caller owns
the supplied acceptance time; this local profile does not independently attest a
clock or bind an observation to an issuer-controlled execution. Receipts use the
existing [signed observation profile](signed-observation-receipt-v1.md).

## Local CLI boundary

```sh
feature-passport issue-receipt passport.json observation.json \
  --policy policy.json \
  --authorization issuer-authorization.json \
  --request request.json \
  --signing-key-file /absolute/private/key
```

`issuer-authorization.json` uses the existing receipt trust-store wire envelope,
with exactly one key entry. This is issuer-side configuration, not installation of
trust in any consumer. The policy controls issuance lifetime; trust-store envelope
lifetime/skew settings are not used to relax issuer checks. Consumers separately
choose their own verification trust stores.

`request.json` has exactly `receipt_id`, `accepted_at`, `valid_from`, `valid_until`;
times use supported RFC 3339 UTC syntax. It is at most 16 KB and rejects duplicate
or unknown fields. The CLI requires an existing caller-owned 32-byte raw Ed25519
private-key file, an absolute path, a regular file, no final symlink, current user
ownership and no group/other permissions. It reads through the checked file
descriptor. Keys are neither generated nor persisted by the CLI, and never belong
in the checkout, release archive, image or logs. This minimal file adapter is not
Keychain/HSM custody or a production signer service.

Exit 0 writes only exact receipt bytes to stdout, without a trailing newline.
Exit 2 reports input, policy, authorization or signing failure to stderr and emits
no receipt. Redirect only to a fresh destination; the CLI does not maintain a
receipt ledger or prevent shell redirection from overwriting an existing file.
Use `verify-receipt` with separately selected trust to validate the result.
`capabilities` emits bounded JSON naming implemented commands and the issuance
profile; `--help` exits 0. Neither command declares authority or readiness.

## Evidence and remaining work

Tests use ephemeral in-memory keys; the CLI test creates a temporary key file
outside Git and deletes it afterward. `make test-receipt-issuer` includes the
actual executable round trip and rejection of overly permissive key files.
The initial test-first run failed compilation because the issuer API was absent;
this is compile Red, not an observed behavioral rejection. Existing verifier
vectors are retained. No real authority key, policy adoption, accepted Zeusus
receipt, aggregate decision, production deployment or SpecGraph gate change is
created by this slice. Release packaging and Platform integration follow in
separate PRs under the same handoff.
