# Local aggregate claim evaluation v1

`LocalAggregateClaimEvaluator` derives an **unsigned local result** from an
explicit claim policy and a fresh bundle of observation/receipt pairs. It
reverifies every signed observation receipt with the caller's offline trust
store on every run. It does not consume cached verifier reports or receipt
success JSON.

The output's `satisfied: true` means only that the exact local predicate below
passed for the supplied bytes and verification time. It is not a signed
authority decision, a production claim, `runtime_verified`, or proof of a user
outcome. The output declares `signed: false` and `replay_protection: false`.

## Policy profile

The policy is an unsigned v1 JSON document. Its policy digest is SHA-256 of the
exact policy input bytes. Duplicate JSON names and unknown fields are rejected.

```json
{
  "artifact_kind": "local_aggregate_claim_policy",
  "schema_version": 1,
  "policy_id": "local.route-evaluation",
  "policy_version": "1",
  "claim_id": "claim.route-composition",
  "feature_passport": {
    "feature_id": "feature.demo",
    "passport_id": "fp.demo",
    "version": "1",
    "digest": "sha256:<64-lowercase-hex-of-exact-passport-bytes>"
  },
  "receipt_policy": {
    "authority_id": "test-authority",
    "policy_id": "runtime-contract-match",
    "policy_version": "1",
    "policy_digest": "sha256:<64-lowercase-hex>"
  },
  "environment": "test",
  "sequence_attribute": "sequence",
  "ordered_probes": [
    { "probe_id": "route.plan", "allowed_results": ["success"] },
    { "probe_id": "route.select", "allowed_results": ["success", "neutral"] },
    { "probe_id": "route.finish", "allowed_results": ["success"] }
  ]
}
```

`ordered_probes` contains at least two distinct passport probe IDs; array order
is the policy order. Every probe must declare `sequence_attribute` in its
attribute allowlist. `allowed_results` is required separately for each probe
and contains one or more values from the normalized observation result enum:
`success`, `failure`, or `neutral`. There is no default success rule.

`feature_passport.digest` binds the policy to the SHA-256 digest of the exact
passport bytes. `receipt_policy` pins the exact authority, policy ID, policy
version, and policy digest expected on every receipt. The trust store separately
decides which keys may attest that receipt policy.

## Bundle and CLI

The bundle lists local file paths. Relative paths are resolved relative to the
bundle JSON file; absolute paths are also accepted. The bundle itself has an
exact v1 envelope and cannot contain more than 64 pairs.

```json
{
  "artifact_kind": "local_aggregate_claim_bundle",
  "schema_version": 1,
  "pairs": [
    { "observation": "observations/plan.json", "receipt": "receipts/plan.json" },
    { "observation": "observations/select.json", "receipt": "receipts/select.json" },
    { "observation": "observations/finish.json", "receipt": "receipts/finish.json" }
  ]
}
```

```sh
feature-passport evaluate-claim passport.json claim-policy.json bundle.json \
  --trust-store trust-store.json [--at 2026-09-28T20:35:00Z]
```

Exit status is `0` only when `satisfied` is true, `1` for a well-formed
evaluation whose bounded predicate fails, and `2` for invocation, file,
trust-store, bundle-decoding, or internal errors. `--at` fixes the receipt
verification time for deterministic offline evaluation; without it, local
current time is used. No prior evaluation result is accepted as input.

The JSON result uses `artifact_kind: "local_aggregate_claim_evaluation"`,
`schema_version: 1`, `signed: false`, `replay_protection: false`, a
`local_predicate_satisfied` or `local_predicate_not_satisfied` verdict, the
`satisfied` boolean, policy/passport/evidence-policy identities and digests,
`observation_count`, and stable `issues`. The result is derived output and is
not an input to another verification step in this profile.

## Exact predicate

The evaluator requires all of the following:

1. The supplied passport validates locally, matches the policy's exact identity,
   and its exact input-byte digest equals the policy digest.
2. The bundle has exactly one pair for every policy probe and no additional
   probes. Every receipt is reverified against that passport, observation,
   verification time, and explicit trust store.
3. Every observation matches the same feature/passport/version/digest,
   allowlisted receipt authority/policy tuple, and exact policy environment.
4. Event IDs and receipt IDs are unique within the bundle. Every event has one
   nonempty `runtime.operation_id`, and all values are identical.
5. For each probe, `observation.attributes[sequence_attribute]` is canonical
   unsigned 64-bit decimal: ASCII digits only, no leading zero except `0`, and
   within `UInt64`. Sequence values are unique and strictly increase in
   `ordered_probes` order. The sequence attribute is within each probe's
   passport allowlist and is covered by the exact observation digest in its
   receipt.
6. Each probe's normalized `observation.result` is in that probe's explicit
   `allowed_results` list.

The order of the pair entries inside `bundle.json` is irrelevant; the evaluator
maps them by exact passport probe ID, then checks sequence values in policy
array order.

The predicate does not compare `occurred_at` values for order. Receipt
verification still checks their timestamp validity and bounds. Ordering uses
the allowlisted signed/bound semantic sequence attribute only; it does not
establish that the event producer or sequence source was independently
attested.

Diagnostics use stable codes and are sorted by code and message. A local
predicate failure has `satisfied: false`, including missing/mismatched probes,
mixed operations, duplicate IDs/sequences, untrusted receipts, wrong passport,
environment or receipt policy, non-increasing/invalid sequence, and disallowed
per-probe results. A receipt on a `failure` or `neutral` observation remains a
valid receipt only if its receipt signature is valid; the local claim passes
only if that result is explicitly allowed for its probe.

## Limits

The evaluator is a provider-neutral local predicate engine, not a production
issuer or aggregate authority. The policy and output are unsigned. The caller
controls both; this profile does not prove policy provenance. It has no durable
replay/idempotency ledger, so it detects duplicates only inside the supplied
bundle. It does not prove delivery provenance, production deployment, user
identity, feature exposure, or outcome beyond the exact per-probe result values
listed in the policy. It never emits `runtime_verified` or a signed accepted
claim. Inputs are bounded to 10 MB for the passport, 256 KB for policy and
bundle files, 1 MB for the trust store, 10 MB per observation, 256 KB per
receipt, 64 pairs, and 64 MB total observation/receipt bytes.
