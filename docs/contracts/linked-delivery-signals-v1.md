# Linked delivery signals v1

Status: experimental integration profile, `linked_delivery_signals_v1`.

## Purpose

Connect a feature's intent, specification, tests, delivery and runtime signals
using reports already produced by its delivery pipeline. A product adapter can
start with one passport, a list of required tests and an existing runtime check.
No contract provider, programming language or CI vendor is required.

This profile defines a **derived, provider-reported observation**, not an
evidence receipt or an admission decision. It leaves the signed receipt,
aggregate decision and passport lifecycle contracts unchanged. A later consumer
can apply those stronger profiles when its use case requires them.

## Identity and shape

A report has:

- `artifact_kind: feature_delivery_signals`, `schema_version: 1`;
- `profile: linked_delivery_signals_v1`;
- `feature_passport`: feature ID, passport ID, version and exact-file SHA-256;
- `source`: repository and full tested source revision;
- `provenance`: report producer, report environment, projection time and
  run/attempt URL or another provider-native execution reference;
- `stages`: intent, spec, tests, deploy, runtime and acceptance records;
- `trust_model: provider_reported` and `admission: not_evaluated`.

Each stage has a `result`, a short `summary`, `evidence` references and its own
`provenance` with two required members:

- `observer`: provider, execution `environment`, execution `uri` and native
  run/attempt identity when available. This identifies where the underlying
  observation ran, which may differ from the report producer. Use `null` when
  there is no observation or its execution context is unknown; such a stage
  cannot claim `observed_success`.
- `target`: the observed or intended target's `environment` and `uri`. Use an
  explicit adapter-defined environment such as `repository`, `ci`, `staging`
  or `production`; use `unknown` when it is not established. A missing stage's
  target describes the intended scope, not proof of deployment there.

The top-level report environment is not inherited by stages. An adapter must
document how it establishes each target environment and preserve the original
observer identity when projecting retained reports in another environment.
For example, an HTTP check executed in CI against a production origin records:

```json
{
  "provenance": {
    "observer": {
      "provider": "github_actions",
      "environment": "ci",
      "uri": "https://github.com/example/product/actions/runs/123",
      "run_id": "123",
      "run_attempt": "1"
    },
    "target": {
      "environment": "production",
      "uri": "https://product.example"
    }
  }
}
```

An evidence reference has a `uri`; use a repository-relative path, immutable
source URL, artifact URL or provider run URL. Include a `sha256` when exact
artifact bytes are available.
Adapters may add bounded details such as test obligations or a bundle digest.
These details are adapter-owned and must be documented.

Stage results are `observed_success`, `observed_failure`, `missing` or
`not_applicable`. Missing, skipped or incomplete work cannot be reported as
success. A negative test that successfully detects bad input is a successful
test observation; the corresponding real failed operation remains a failure.

An exact-file digest identifies input bytes. It is not a canonical passport
digest, signature, provider authentication or proof of origin. Keep that
distinction when adapting this profile to signed contracts.

## Producer responsibilities

1. Preserve the feature/passport identity across stages.
2. Record the actual tested revision, selected obligations and source reports.
3. Keep evidence run-local and distinguish run attempts.
4. Join stages only when their source and artifact identities agree. Report a
   missing link instead of borrowing a passing result from another revision.
5. Preserve the difference between a test result, deployed bytes and execution
   of a particular code path. Record observer and target environments separately
   in every stage's provenance; a CI execution is not a production execution.
6. Retain the native reports alongside this projection, with a stated retention
   period. A report describes its recorded run, not current deployment health.

For example, a post-deploy HTTP digest check can observe expected published
bytes while its Python verifier executes in CI. Both observations are useful;
they describe different execution environments.

The first adapter can consume ordinary JUnit and deployment JSON. It need not
instrument every assertion, introduce a new runner, or operate a signer.
Name the reviewed test-to-criterion bindings; a passing unrelated suite cannot
fill a missing obligation. Function-level test observations do not establish
assertion-level coverage or satisfy a stronger `tests_verified` admission profile.

## Acceptance and outcome

Declare what counts as acceptance in the feature's intent. For software delivery
this may be a merged pull request or explicit customer acceptance tied to the
requirement and delivered revision. A closed, unmerged pull request is not a
successful merge signal. A production benefit requires its own observable
success condition; it cannot be inferred from a merge.

Keep acceptance `missing` until its source signal exists. No observation changes
canonical spec maturity or grants execution authority automatically.

## Compatibility and integration

This profile adds a separate report kind. It does not weaken or reinterpret
existing `tests_verified_v1`, signed receipt or runtime admission policies.
Consumers opt into this report explicitly and display its trust model.

An adapter's documentation should identify its passport, required tests,
commands, artifact locations, retention, runtime observer and limitations.
The SpecGraph static-publication pilot is one optional integration, not a core
dependency or mandatory ID format.
