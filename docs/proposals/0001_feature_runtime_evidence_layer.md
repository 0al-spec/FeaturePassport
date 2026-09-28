# Feature Passport Runtime Evidence Contract

RFC: FP-RFC-0001
Version: 0.3.0
Status: Draft / ADR-level Proposal

Decision scope: architecture and product evidence contract. This document does
not implement SDKs, ingestion services, storage engines, or hosted UI.

All YAML/JSON examples are illustrative draft shapes; sample signatures,
digests, issuers, and invoice data are placeholders, not issued artifacts.
Normative wording defines the proposed contract for future implementations.

## Summary

The Feature Passport Runtime Evidence Contract defines a provider-neutral product
evidence model for proving that a user-requested feature progressed from
specification intent to implementation, build, release, production runtime
observation, feature execution, and user-visible outcome.

The layer is stronger than ordinary analytics. It does not merely count events.
It links contract references, implementation symbols, commits, build artifacts, releases, runtime sessions,
feature probes, and signed evidence receipts into a verifiable evidence chain.

## Motivation

A software factory needs to answer a product-critical question:

> Did the feature requested by the user actually reach production and work for
> users?

The answer must be stronger than:

- the commit appears in release notes;
- the pull request was merged;
- a dashboard contains an unrelated analytics event;
- a feature flag was enabled.

The desired claim is:

- the feature declares intent and acceptance criteria, with optional references to external contracts;
- the feature has a declared Feature Passport;
- implementation commits are linked to the feature;
- build artifacts include those commits and have provenance;
- the artifacts were released or deployed to production;
- production runtime sessions reported the build identity;
- feature-specific probes observed exposure, execution, effect, and outcome;
- a configured evidence authority accepted and sealed those observations as evidence receipts under a declared policy.

## Architecture Decision

An evidence evaluator should not treat telemetry volume, feature flag evaluation, release
notes, or merged pull requests as proof that a feature worked for users.

Feature Passport defines typed evidence for evaluators:

- Feature Passport declares what must be proven.
- Evidence claims state the proof target.
- Observations report what happened.
- Attestations bind trusted delivery systems to artifacts or deployments.
- Receipts seal what a named evidence authority accepted under its policy.
- Evidence levels explain how strong the current proof is.

This makes the proposal an evidence architecture decision, not an analytics
dashboard, SDK design, or runtime profiling mechanism.

## Canonical Chain

```text
Local intent / external contract reference
  -> Feature Passport
  -> pull request / commit
  -> build artifact / app binary / container image
  -> release / deployment
  -> runtime session
  -> feature exposure
  -> feature code path executed
  -> effect committed
  -> user-visible outcome
  -> evidence receipt
```

## Design Principle

Feature Passport owns its identity, evidence vocabulary, and reference contracts.
A passport can declare local intent without a graph service or external registry.
SpecGraph is an optional producer and consumer connected through an adapter.

CI/CD systems provide build attestations. Release systems provide deployment
attestations. Telemetry systems provide runtime observations. Feature flag
systems provide exposure or evaluation observations. Adapters normalize these
inputs; an independently configured evidence authority evaluates and seals them.

### Dependency Direction

```text
SpecGraph adapter -> Feature Passport contracts
SpecGraph adapter -> SpecGraph API / exported artifacts
Swift instrumentation -> Feature Passport contracts
Evidence evaluator -> Feature Passport contracts + configured trust policy
SpecSpace or another viewer -> Feature Passport projections
```

The core contract MUST NOT import SpecGraph schemas, require SpecGraph IDs,
resolve its graph, or call its service to validate a passport or observation.
SpecGraph-specific selectors, lifecycle states, and review gates belong to its
adapter. Other providers may use an ADR repository, an issue tracker, another
spec registry, or archived contract files through the same boundary.

### Evidence Authority

An evidence authority is an explicitly configured role, not a particular product
or a requirement for a hosted server. A local verifier, CI service, or remote
service can perform that role. Its identity, policy revision/digest, trusted
issuers, allowed environments, and accepted evidence kinds define its scope.
A receipt MUST identify the authority and policy used. Consumers decide which
authorities and policies they trust; a valid signature alone grants no authority.

One party may issue passports and evaluate evidence, but those are distinct
roles. A local test receipt remains local test evidence; it cannot establish a
production claim. SpecGraph can host an authority or consume its receipts when
explicitly configured, with no privileged position in the base contract.

## Terminology

### Feature Passport

A machine-readable contract that declares a feature's identity, origin,
implementation links, delivery expectations, required runtime probes, privacy
constraints, and signature metadata.

### Evidence Claim

A statement an evidence consumer wants to prove under a declared policy.

Example:

```text
Feature feature.invoice.smart_summary reached production and completed its
intended user-visible outcome for at least one production user.
```

Future schemas should represent claims as machine-readable objects rather than
free text.

```yaml
claim_id: "claim.invoice_summary.outcome"
feature_passport:
  feature_id: "feature.invoice.smart_summary"
  passport_id: "fp.invoice.smart_summary"
  version: "0.1.0"
  digest: "sha256:example-passport-digest"
contract_ref_ids: ["invoice-summary-requirement"]
min_evidence_level: "L8"
target_entities:
  environments:
    - "production"
  platforms:
    - "ios"
success_condition:
  min_users: 1
  min_sessions: 1
  required_probe_ids:
    - "invoice_summary.release_seen.v1"
    - "invoice_summary.render.v1"
    - "invoice_summary.completed.v1"
```

A claim's `min_evidence_level` must not exceed the passport's
`spec.evidence.required_level`; the passport value is the default target when a
claim does not narrow it. A claim demanding a level above what the passport
declares provable is invalid.

Claim-local reference IDs resolve only against the exact passport version and
digest in `feature_passport`. They cannot be resolved against whichever draft
or version is latest when evaluation runs.

### Observation

A raw runtime signal emitted by a client, backend, agent, or service.

### Attestation

A signed statement from a trusted system, such as a CI/CD build provenance
attestation or deployment attestation.

### Evidence Receipt

An authority-issued, signed or hash-linked record that an observation or
attestation was accepted under a named evidence policy.

Observation is what a producer reported. Receipt records what a named authority
accepted as evidence; it does not make the observation universally trusted.

### Evidence Chain

A traversable graph path connecting feature intent or a referenced contract to implementation,
delivery, runtime execution, and outcome receipts.

## Evidence Levels

| Level | Name | Meaning |
| --- | --- | --- |
| L0 | Specified | Passport declares intent and acceptance criteria; external contract references are optional |
| L1 | Implemented | Pull request or commit is linked to the feature |
| L2 | Built | Commit is included in an attested artifact |
| L3 | Released | Artifact is released or deployed to production |
| L4 | Runtime Seen | Production runtime reports build identity |
| L5 | Feature Exposed | User was exposed to the feature surface |
| L6 | Code Path Executed | Feature implementation path executed |
| L7 | Effect Committed | Durable state change or accepted side effect occurred |
| L8 | Outcome Completed | Intended user-visible outcome completed |

The phrase "commit reached production" requires at least L4.

The phrase "feature worked for users" requires L7 or L8.

Levels form a ladder over the levels that are applicable to a feature. A level
is reached only when all lower applicable levels are also evidenced. A level
can be inapplicable — for example L5 for a backend-only feature — when its
probes are excluded by `required_when` predicates; inapplicable levels are
reported as not applicable and do not block higher levels.

Only observations with `observation.result: "success"` count toward reaching a
level. Failure observations are recorded as evidence of execution attempts but
do not satisfy claims.

## Feature Passport Shape

Artifacts use `artifact_kind` and an integer `schema_version` owned by Feature
Passport. Validation does not depend on another product's artifact envelope.

This is a provisional convention decision for this repository. A future 0AL-wide
declaration profile should align Feature Passport, Agent Passport, and related
declarative artifacts on a shared set of top-level identity keys. The important
requirement is not the exact spelling of `artifact_kind` versus `kind`, but that
all passports remain machine-discoverable, versioned, and schema-addressable.

```yaml
artifact_kind: feature_passport
schema_version: 1
metadata:
  feature_id: "feature.invoice.smart_summary"
  passport_id: "fp.invoice.smart_summary"
  title: "Smart invoice summary"
  owner: "ios-product"
  version: "0.1.0"
  status: "sealed"
  issued_at: "2026-05-25T12:00:00Z"
  issuer: "product.release-authority"
spec:
  intent:
    summary: "Show an AI-generated summary before invoice payment."
    acceptance_criteria:
      - id: "AC-1"
        text: "Summary block is visible on invoice screen."
      - id: "AC-2"
        text: "User can expand summary details."
      - id: "AC-3"
        text: "Backend records successful summary generation."
  contract_refs:
    - id: "invoice-summary-requirement"
      relation: "implements"
      provider: "repository-document"
      locator:
        repository: "product-ios"
        path: "requirements/invoice-summary.md"
        revision: "example-immutable-commit"
        selector: "smart-summary"
  implementation:
    repositories:
      - name: "product-ios"
        url: "git@github.com:org/product-ios.git"
    pull_requests:
      - repository: "product-ios"
        number: 1842
    commits:
      - repository: "product-ios"
        sha: "8ae73a0f..."
        role: "primary_implementation"
  delivery:
    artifacts:
      - platform: "ios"
        artifact_type: "ipa"
        digest: "sha256:abc123..."
        build_number: "134"
        provenance_ref: "slsa://..."
    production_environments:
      - "production"
  runtime:
    required_resource_attributes:
      service.name: "product-ios"
      service.version: "2.7.0+134"
      deployment.environment.name: "production"
  evidence:
    required_level: "L8"
    probes:
      - id: "invoice_summary.release_seen.v1"
        event: "fp.release_seen"
        level: "L4"
        required: true
      - id: "invoice_summary.visible.v1"
        event: "fp.feature.exposed"
        level: "L5"
        required: true
        required_when: "ui_or_user_entry_point"
      - id: "invoice_summary.render.v1"
        event: "fp.feature.code_path.executed"
        level: "L6"
        required: true
        attributes:
          - "surface"
          - "operation"
      - id: "invoice_summary.backend_accepted.v1"
        event: "fp.feature.effect_committed"
        level: "L7"
        required: true
        required_when: "durable_effect_expected"
      - id: "invoice_summary.completed.v1"
        event: "fp.feature.outcome_completed"
        level: "L8"
        required: true
        required_when: "user_visible_outcome_expected"
  adoption:
    minimum_evidence:
      users: 1
      sessions: 1
      environments:
        - "production"
    aggregation_window: "P7D"
    sampling_allowed: false
  privacy:
    pii_allowed: false
    user_identifier: "pseudonymous_hash"
    retention_days: 90
    raw_payload_storage: false
signature:
  algorithm: "Ed25519"
  public_key_ref: "urn:example:product:release-authority:key-1"
  signed_by: "product.release-authority"
  value: "base64-signature"
```

### Feature Passport Field Contract

The first normative schema should preserve this field boundary:

| Field | Requirement | Purpose |
| --- | --- | --- |
| `artifact_kind` | required, constant `feature_passport` | Artifact discriminator |
| `schema_version` | required integer | Schema compatibility |
| `metadata.feature_id` | required | Stable feature identity |
| `metadata.passport_id` | required | Stable passport identity, distinct from feature identity |
| `spec.contract_refs[]` | optional | References to external contracts through provider adapters |
| `metadata.version` | required | Passport versioning and probe drift control |
| `metadata.status` | required, `draft` or `sealed` | Whether operational integrity requirements apply |
| `metadata.issuer` | required | Authority that issued the contract |
| `spec.intent.acceptance_criteria[]` | required | User-visible success semantics |
| `spec.implementation` | optional before code, required for L1+ claims | Source linkage |
| `spec.implementation.elements[]`, `.bindings[]` | optional | Typed code anchors and criterion-to-implementation relations |
| `spec.delivery.artifacts[]` | required for L2+ claims | Build artifact linkage |
| `spec.runtime.required_resource_attributes` | required for L4+ claims | Runtime identity requirements |
| `spec.evidence.required_level` | required | Target evidence level |
| `spec.evidence.probes[]` | required | Declared observations that can satisfy claims |
| `spec.evidence.probes[].attributes` | required when the probe emits attributes | Allowlist of `observation.attributes` keys |
| `spec.evidence.probes[].element_ids` | required when observations identify implementation elements | Allowed runtime implementation identities |
| `spec.adoption.minimum_evidence` | required for adoption claims | Aggregation threshold |
| `spec.privacy` | required | PII, retention, and sampling boundary |
| `signature` | required when passport is operational | Integrity and issuer verification |

External contracts supplement the passport's local acceptance criteria. A
passport with no external references remains valid. Several requests, specs,
or scenarios can be linked without selecting one provider as the identity root.
The passport's `feature_id` MUST NOT be inferred from a provider's node ID.

### External Contract References

Each entry in `spec.contract_refs` has a unique passport-local `id`, a
`relation` (`originates_from`, `implements`, or `constrained_by`), a provider
key, and an opaque `locator` object. Core validation checks that envelope and
passport-local references. A provider adapter owns the locator schema, identity
resolution, revision semantics, and extraction of source content.

For example, the optional SpecGraph adapter could resolve this reference:

```yaml
contract_refs:
  - id: route-composition-contract
    relation: implements
    provider: specgraph
    locator:
      workspace: zeusus
      node_id: ZEU-SPEC-0016
      scenario_id: ZEU-ROAD-STRATEGY-COMPOSITION-001
      revision: "example-pinned-source-revision"
```

`workspace`, `node_id`, and `scenario_id` are adapter-owned fields. Their names
and values impose no requirements on other providers or on passport identity.
Source lifecycle states such as `linked` or `reviewed` remain provider facts;
they do not establish implementation coverage or evidence acceptance.

Resolution is recorded separately as `resolved`, `unresolved`, `unsupported`,
or `mismatch`, with resolver version, source revision and content digest when
available. Missing adapters do not invalidate a provider-neutral envelope, but
an unresolved reference cannot satisfy a claim requiring verified source
linkage. A resolver may use an archived source snapshot without network access.
A mutable locator is acceptable in a draft; evidence relying on its content
must pin the resolved revision/digest. Resolver results cannot silently alter a
sealed passport. Multiple references may point to the same provider or to
different providers.

### Implementation Bindings

`spec.implementation` may declare repositories, PRs, commits, `elements`, and
`bindings`. Repository entries have a unique `name` and either an explicit
location or a deployment-configured resolver for that name. No Git hosting
service is mandatory.

An element has a stable passport-local `id`, an open role vocabulary (for
example `policy`, `composition`, `strategy`, `strategy_interface`, `adapter`,
`call_site`, or `test`), and one or more source anchors. An anchor identifies
repository, immutable revision, language, module, path, and a provider-specific
symbol locator. Line numbers may aid navigation but MUST NOT be the identity.
Overloads and nested declarations need an unambiguous selector; a compiler
symbol ID may supplement a readable symbol name. Internal Swift symbols must
be resolvable by the chosen indexer too; public symbol graphs alone may omit them.

The element ID represents a logical role across refactors. Renaming or moving a
symbol updates its source anchor and passport version. Splitting or changing
the responsibility requires explicit identity review; IDs must not silently
attach to unrelated code. An element may support several contracts and a
contract may require several elements.

Each binding has an `id`, optional `contract_ref_ids`, required nonempty local
`acceptance_criteria_ids`, nonempty `element_ids`, and optional `test_element_ids`.
Every referenced ID must exist in the same passport; test references must name
elements with role `test`. An external source reference can further identify a
scenario, while local criteria keep the binding meaningful without that provider.
The declared test relation does not establish that the test passed.

Element `uses` relationships are optional directed edges between element IDs
with a relation such as `invokes` or `evaluates`. They express authored
architecture. An optional invocation order describes a declared composition;
it is not a measured runtime call graph. The element resolver checks anchors,
and test/runtime evidence can separately corroborate declared relationships.

The core MUST preserve unknown role labels without inferring their behavior.
It MUST NOT require SpecificationCore, Swift, a particular design pattern, or a
code-generation tool. SpecificationCore objects, ordinary classes, functions,
and strategy compositions are all eligible implementation elements.

An implementation inventory is not a new product-spec graph. Consumers can
project these typed relationships together with external contract graphs.
Passport authors retain responsibility for mapping semantics: matching symbol
names or finding a spec ID in a string is insufficient evidence of a binding.

### Runtime Correlation and Coverage

A probe may declare `element_ids` from the implementation inventory. An
observation may name one `implementation_element_id` only when it belongs to
that probe. Its `runtime.operation_id` and `runtime.invocation_id` distinguish
the operation from an invocation of a strategy or composition. These runtime
IDs are optional except for claims requiring execution order or cross-span
correlation; then the probe declares them required. Probe-allowlisted attributes
can carry invocation order, candidate outcome, and selected element ID.
The proposed declaration is `required_runtime_fields`, a list restricted to
`operation_id` and `invocation_id`; absent fields listed there reject the
observation for that probe. These identifiers also follow the privacy policy.

A runtime execution event must come from instrumentation at the relevant
boundary. It cannot be manufactured from a static inventory or a passing test
name. Declared order and observed order are separate evidence. Instrumentation
must not alter domain decisions; trace timings cannot become simulation inputs.

Coverage reports must distinguish declared mappings, resolved code anchors,
test observations, runtime observations, and authority-accepted claims. Each
report identifies the passport version, build/source revision, environment,
and the denominator of applicable criteria. Missing mappings or unsupported
resolvers remain explicit gaps. A test that covers one scenario does not prove
every normative rule of its parent spec. No aggregate coverage metric or
extractor is implemented by this proposal.

### Versioning Semantics

Feature Passport uses three separate version axes:

- RFC version: version of this architecture document, such as `FP-RFC-0001`
  `0.1.0`.
- Schema version: integer compatibility version for machine validation, such as
  `schema_version: 1`.
- Passport version: feature contract version in `metadata.version`, used when
  probes, acceptance criteria, delivery expectations, or privacy rules evolve.

Historical evidence must remain interpretable under the passport version that
was active when the receipt was sealed. Breaking schema changes should ship with
a migration note and retain enough compatibility to verify old receipts.

All three artifacts use integer `schema_version` with an `artifact_kind`
discriminator: `feature_passport`, `feature_observation`, or `evidence_receipt`.
These are proposed v1 shapes, not published schemas or implemented validators.

### Passport Lifecycle

A passport is issued before some of its facts exist: commit SHAs and artifact
digests are unknown until implementation and build complete. The first schema
should define an explicit lifecycle:

- `draft`: intent and acceptance criteria exist; implementation and delivery
  sections may be absent or partial.
- `sealed`: the issuer signed the passport for operational use.
- Amendment: adding implementation links, artifact digests, or probe changes
  re-issues the passport with an incremented `metadata.version` and a new
  issuer signature. Receipts reference the passport version that was active at
  sealing time.

## Canonical Event Envelope

All evidence events should share a stable envelope so SDKs, ingestion services,
and adapters do not invent incompatible payloads.

The envelope identifies the feature, exact passport version/digest, and probe.
External contract references are optional IDs declared in that passport;
observations need no provider-specific request identity or online resolver.

For a sealed passport, its digest is the SHA-256 of its canonical JSON content
excluding only `signature.value`; signature metadata remains covered. The
signature signs that digest. Verifiers must use a pinned canonicalization
profile; implementing and validating that profile remains future work.

```json
{
  "artifact_kind": "feature_observation",
  "schema_version": 1,
  "event_name": "fp.feature.code_path.executed",
  "feature_passport": {
    "feature_id": "feature.invoice.smart_summary",
    "passport_id": "fp.invoice.smart_summary",
    "version": "0.1.0",
    "digest": "sha256:example-passport-digest",
    "probe_id": "invoice_summary.render.v1"
  },
  "delivery": {
    "environment": "production",
    "platform": "ios",
    "service_name": "product-ios",
    "service_version": "2.7.0+134",
    "build_number": "134",
    "git_sha": "8ae73a0f...",
    "artifact_digest": "sha256:abc123...",
    "release_id": "ios-2.7.0-134"
  },
  "runtime": {
    "session_id": "s_01J...",
    "user_hash": "u_01J...",
    "device_class": "iphone",
    "os_name": "iOS",
    "os_version": "18.5",
    "trace_id": "01HV..."
  },
  "observation": {
    "occurred_at": "2026-05-25T15:03:44Z",
    "result": "success",
    "attributes": {
      "surface": "invoice_screen",
      "operation": "render_summary"
    }
  },
  "integrity": {
    "event_id": "evt_01J...",
    "idempotency_key": "ios:s_01J:invoice_summary.render.v1:001",
    "client_sequence": 42
  }
}
```

Common required fields:

- `schema_version`;
- `event_name`;
- `artifact_kind`;
- `feature_passport.feature_id`;
- `feature_passport.passport_id`, `feature_passport.version`, and `feature_passport.digest`;
- `feature_passport.probe_id`;
- `delivery.environment`;
- `delivery.platform`;
- `observation.occurred_at`;
- `observation.result`;
- `integrity.event_id`;
- `integrity.idempotency_key`.

Conditional fields:

- `delivery.git_sha`, `delivery.artifact_digest`, and `delivery.release_id` are
  required when claiming delivery or release linkage.
- `runtime.user_hash` and `runtime.session_id` are required for user-session
  evidence, but may be omitted for backend, batch, service-side, or headless
  evidence where no user session exists.

`runtime.user_hash` must be pseudonymous and non-portable across unrelated
deployments. The recommended baseline is keyed hashing such as HMAC with a
deployment-specific secret and an explicit salt rotation policy. Raw user
identifiers, emails, device advertising identifiers, or cross-application
tracking IDs must not be used as Feature Passport evidence identifiers.

Salt rotation must be coordinated with adoption aggregation windows: rotating
inside an open window splits one user into two hashes and inflates
`minimum_evidence.users` counting.

`observation.attributes` must be restricted to the keys declared in the probe's
`attributes` allowlist in the Feature Passport. Ingestion should drop
undeclared attributes; otherwise the `pii_allowed: false` boundary is
unenforceable.

`integrity.idempotency_key` uniqueness is scoped per `feature_id` and
`probe_id`. The recommended key structure is
`platform:session_id:probe_id:client_sequence`, where `client_sequence` is a
monotonically increasing per-session counter. Ingestion should additionally
enforce an acceptance window on `observation.occurred_at` with bounded client
clock skew to limit replay.

### Event Envelope Field Contract

The event envelope is the normalization target for SDKs, OpenTelemetry,
analytics tools, feature flag providers, and custom runtime events.

| Field | Requirement | Purpose |
| --- | --- | --- |
| `artifact_kind` | required, constant `feature_observation` | Observation discriminator |
| `schema_version` | required integer | Event schema compatibility |
| `event_name` | required | Vocabulary item such as `fp.release_seen` |
| `contract_ref_ids[]` | optional | IDs declared in the referenced passport |
| `feature_passport.feature_id` | required | Feature Passport linkage |
| `feature_passport.passport_id`, `.version`, `.digest` | required | Exact passport linkage |
| `feature_passport.probe_id` | required | Declared probe linkage |
| `implementation_element_id` | optional | Element declared by this probe |
| `delivery.environment` | required | Production/staging/dev boundary |
| `delivery.platform` | required | Runtime platform boundary |
| `delivery.git_sha` | conditional | Required for delivery/build claims |
| `delivery.artifact_digest` | conditional | Required for artifact claims |
| `delivery.release_id` | conditional | Required for release claims |
| `runtime.session_id` | conditional | Required for session-scoped evidence |
| `runtime.user_hash` | conditional | Required for user-scoped evidence |
| `runtime.operation_id`, `runtime.invocation_id` | conditional | Required when a probe claims correlated execution/order |
| `observation.occurred_at` | required | Runtime occurrence time |
| `observation.result` | required | Success/failure/neutral result |
| `integrity.event_id` | required | Event identity |
| `integrity.idempotency_key` | required | Replay and deduplication control |

## Event Vocabulary

### `fp.release_seen`

A production runtime instance or session reported a known build identity.

### `fp.feature.exposed`

The user was presented with a feature surface, entry point, UI element, API
capability, or workflow state.

For non-UI, backend-only, batch, headless, or background features, exposure may
be explicitly marked not applicable. In those cases, L6 or server-confirmed L7
is the first meaningful runtime evidence level.

The first schema should support `required_when` predicates for probes, including:

- `ui_or_user_entry_point`;
- `durable_effect_expected`;
- `user_visible_outcome_expected`;
- `backend_only`;
- `headless_or_batch`;
- `always`.

These predicates allow validators to skip impossible evidence levels without
weakening the evidence model.

`required_when` scopes `required`: a probe carrying both fields is required
only when the predicate applies to the feature, and is otherwise not applicable
rather than optional. A probe without `required_when` is treated as
`required_when: "always"`.

### `fp.feature.code_path.executed`

The implementation path associated with the feature was entered.

### `fp.feature.effect_committed`

The feature produced a durable state change, accepted backend command, stored
record, emitted durable message, or equivalent committed effect.

### `fp.feature.outcome_completed`

The intended user-visible result was completed.

`effect_committed` and `outcome_completed` are not interchangeable.

Example:

```text
feature.exposed:
  user saw "Generate summary" button
feature.code_path.executed:
  renderSummary() was called
feature.effect_committed:
  backend stored summary_id
feature.outcome_completed:
  summary text was rendered to the user
```

## Evidence Receipts

Runtime observations become accepted evidence only within the scope of the
authority and policy that evaluates them.

An evidence receipt records:

- receipt id;
- event id;
- event hash;
- previous receipt hash, if hash-linked;
- validation results;
- satisfied claims;
- ingestion timestamp;
- sealing timestamp;
- signature metadata.

```json
{
  "artifact_kind": "evidence_receipt",
  "schema_version": 1,
  "authority": {
    "id": "product.evidence-evaluator",
    "policy_id": "product.production-evidence",
    "policy_version": "1",
    "policy_digest": "sha256:example-policy-digest"
  },
  "feature_passport": {
    "feature_id": "feature.invoice.smart_summary",
    "passport_id": "fp.invoice.smart_summary",
    "version": "0.1.0",
    "digest": "sha256:example-passport-digest"
  },
  "receipt_id": "rcpt_01J...",
  "event_id": "evt_01J...",
  "accepted_claims": [
    {
      "claim_id": "claim.invoice_summary.runtime_execution",
      "level": "L6",
      "satisfied": true
    }
  ],
  "validation": {
    "known_feature_passport": true,
    "probe_declared": true,
    "known_artifact_digest": true,
    "known_release": true,
    "environment_allowed": true,
    "idempotency_key_unique": true,
    "schema_valid": true
  },
  "hashing": {
    "canonicalization": "jcs-rfc8785",
    "event_hash": "sha256:...",
    "previous_receipt_hash": "sha256:...",
    "receipt_hash": "sha256:..."
  },
  "signature": {
    "algorithm": "Ed25519",
    "signed_by": "product.evidence-evaluator",
    "public_key_ref": "urn:example:product:evidence-evaluator:key-1",
    "value": "base64-signature"
  },
  "timestamps": {
    "observed_at": "2026-05-25T15:03:44Z",
    "ingested_at": "2026-05-25T15:03:47Z",
    "sealed_at": "2026-05-25T15:03:48Z"
  }
}
```

Receipts record probe-level claim contributions. Aggregate claims — such as
"at least N users completed the outcome" — are never satisfied by a single
receipt; they are evaluated by a separate claim evaluation step over the set of
sealed receipts inside the claim's aggregation window.

Hash-linked receipts must cover the receipt content itself, not only the
accepted event, so that validation results and accepted claims are also
tamper-evident:

```text
event_hash_n   = sha256(canonical_json(event_n))
receipt_hash_n = sha256(canonical_json(receipt_n excluding
                 hashing.receipt_hash and signature.value))
```

`receipt_n` includes `hashing.event_hash`, `hashing.previous_receipt_hash`, and
the signature metadata (`algorithm`, `signed_by`, `public_key_ref`), so the
chain covers the accepted event, the receipt fields, and the key binding —
only `signature.value` itself is excluded from the hash. The receipt signature
is computed over `receipt_hash`; because the key metadata is inside the hash,
a verifier cannot be redirected to a different allowed key without breaking
the chain.

For the first receipt in a chain, `previous_receipt_hash` is a declared genesis
value.

Each receipt chain must declare its scope. The recommended default is one chain
per Feature Passport per environment; a single global chain would serialize all
ingestion. Tree-based transparency-log structures are a possible future
alternative for high-volume deployments.

Producers emit observations. The configured authority issues receipts, locally
or remotely. Consumers accept them only under an explicit trust policy.
A producer's self-issued receipt is not independent corroboration.

### Receipt Field Contract

The receipt schema is the canonical evidence record. It should be stricter than
runtime observations because it represents an authority's scoped acceptance.

| Field | Requirement | Purpose |
| --- | --- | --- |
| `artifact_kind` | required, constant `evidence_receipt` | Receipt discriminator |
| `schema_version` | required integer | Receipt schema compatibility |
| `authority` | required | Evaluator identity and exact policy revision/digest |
| `feature_passport` | required | Feature and exact passport identity, version, digest |
| `receipt_id` | required | Stable evidence receipt identity |
| `event_id` | required | Accepted observation linkage |
| `accepted_claims[]` | required | Claims satisfied by the receipt |
| `validation.known_feature_passport` | required | Passport existence check |
| `validation.probe_declared` | required | Probe declared in passport |
| `validation.known_artifact_digest` | conditional | Artifact provenance check |
| `validation.known_release` | conditional | Release/deployment check |
| `validation.environment_allowed` | required | Environment boundary check |
| `validation.idempotency_key_unique` | required | Replay prevention |
| `validation.schema_valid` | required | Event shape validation |
| `hashing.canonicalization` | required | Canonical JSON/hash method |
| `hashing.event_hash` | required | Accepted event integrity |
| `hashing.previous_receipt_hash` | required for hash chains | Tamper-evident ordering |
| `hashing.receipt_hash` | required | Receipt integrity |
| `signature` | required when operational | Issuer integrity; authorization comes from consumer trust policy |
| `timestamps` | required | Observed, ingested, and sealed times |

## Honesty and Trust Boundaries

The Feature Runtime Evidence Layer does not claim that all client-side
observations are cryptographically trustworthy.

A mobile or desktop client may be compromised, modified, offline, blocked from
uploading telemetry, sampled out, or unable to send events before termination.

Therefore:

- client-side events are observations, not final proof;
- authority-issued receipts record policy-scoped acceptance;
- server-confirmed effects have stronger evidence value than client-only events;
- absence of evidence is not automatically evidence of absence;
- adoption metrics must declare sampling, retention, and upload policies.

| Claim | Strength |
| --- | --- |
| Commit included in artifact | Strong, with build attestation |
| Artifact released to production | Strong, with deploy or release attestation |
| Runtime reported build identity | Client-bound observation; strong when corroborated by server-side traffic for that build identity |
| Feature UI exposed on client | Useful but client-bound observation |
| Feature code path executed on client | Useful but client-bound observation |
| Backend effect committed | Stronger, server-confirmed evidence |
| User-visible outcome completed | Strong if confirmed by server or durable state |

## Absence Semantics

No event does not necessarily mean the feature was not used.

It may mean telemetry was disabled, blocked, sampled out, delayed, offline,
dropped, retained for a shorter period, or not yet backfilled.

## Minimum Viable Evidence

Minimum claim for "commit reached production":

- commit is listed in the exact feature/passport version's
  `spec.implementation.commits`; no external request is required;
- artifact attestation includes commit;
- release or deploy record references artifact;
- at least one production runtime emitted `fp.release_seen` for that
  artifact/build.

Minimum claim for "feature worked in production":

- all of the above;
- required Feature Passport probes are declared;
- `fp.feature.code_path.executed` was observed;
- `fp.feature.effect_committed` or `fp.feature.outcome_completed` was sealed by
  receipt.

## Vendor Compatibility

The layer may consume signals from:

- OpenTelemetry;
- SLSA provenance;
- GitHub Artifact Attestations;
- Sigstore/Cosign;
- OpenFeature;
- Sentry;
- Datadog;
- LaunchDarkly;
- custom product telemetry.

These systems connect through adapters or transports. Their fields are mapped
to Feature Passport contracts with source provenance preserved.

## Viewer Model

Viewers should display applicable evidence levels and authority/environment
scope rather than a single completion boolean.

Example:

```text
feature.invoice.smart_summary: Smart invoice summary
L0 Specified                  yes
L1 Implemented                yes, PR #1842 / commit 8ae73a
L2 Built                      yes, artifact sha256:abc123
L3 Released                   yes, ios 2.7.0 build 134
L4 Runtime Seen               yes, runtime fp.release_seen received
L5 Feature Exposed            yes, 4,882 users
L6 Code Path Executed         yes, 2,744 users
L7 Effect Committed           yes, 2,603 users
L8 Outcome Completed          yes, 2,571 users
Evidence Strength: L8 / Strong
```

The viewer-facing ladder is a required product model, but this proposal does not
define the concrete UI implementation.

## Compatibility with Draft v0.2.0

This is a breaking refactor of a draft architecture. No schemas, SDKs, or
migration tools are shipped in this repository. Keeping the proposed integer
schema version `1` does not assert wire compatibility with earlier examples.
The RFC version advances from 0.2.0 to 0.3.0; any external experimental producer
using earlier shapes needs an explicitly versioned adapter.

| Earlier draft | v0.3.0 proposal |
| --- | --- |
| Required `metadata.request_id` / SpecGraph request | Optional `spec.contract_refs` with provider-owned locator; feature/passport identity stays local |
| `specgraph` event envelope | `feature_passport` identity, version, digest, and probe |
| `specgraph.feature_passport_id` | `feature_passport.passport_id` |
| `specgraph.request_id` / `specgraph_request_id` | Adapter-created contract reference; never inferred to be a feature ID |
| `sg.release_seen`, `sg.feature.*` | `fp.release_seen`, `fp.feature.*` vocabulary |
| `specgraph.evidence.event.v1` / `.receipt.v1` | `artifact_kind` plus integer `schema_version` |
| SpecGraph acceptance as the sole authority | Explicit evaluator identity and versioned trust policy |
| PR/commit implementation links | Existing links plus optional typed elements, bindings, and source resolution evidence |

A compatibility adapter preserves the original artifact bytes, source format,
digest, and signature verification result. It emits a new normalized artifact
with explicit derivation provenance; it must not rewrite signed events or
receipts in place, copy an old signature onto a new envelope, or invent missing
passport versions/digests. Missing inputs remain unresolved. The `sg.*` names
are legacy adapter inputs only, never alternate core event names. Consumers
must prevent the derived representation from being counted as another execution.

The historical proposal path remains a compatibility link. SpecGraph and
SpecSpace integrations are optional follow-up work; this refactor does not
change their code or claim that they accept the new shapes.

## Acceptance Scenarios for the Future Contract

These scenarios guide later schema/adapter implementation; they are not test
results produced by this documentation change.

- Given a passport with local intent and criteria and no `contract_refs`, its
  core validation succeeds without SpecGraph or any graph service installed.
- Given equivalent references from SpecGraph and a repository-document
  provider, their adapter-specific resolution preserves the same feature,
  implementation element, and probe identities.
- Given an unknown provider, the core validates the reference envelope and
  records `unsupported`; a claim requiring verified external linkage remains
  unsatisfied while unrelated local-criteria claims can be evaluated.
- Given a strategy rename, its stable logical element ID survives, its source
  anchor changes in a new passport version, and historical observations still
  resolve against their original passport and commit.
- Given a declared composition and passing scenario test, no runtime execution
  or production coverage is inferred until matching observations exist.
- Given a receipt from an untrusted authority or a local-test environment,
  it cannot satisfy a claim requiring trusted production evidence.
- Given a signed `sg.feature.*` event, adapter normalization preserves original
  evidence and provenance and does not reuse its signature as a signature of
  the new `fp.feature.*` representation.

The [Zeusus pilot](../examples/zeusus-route-composition.md) supplies real source
anchors and known evidence gaps for the implementation-binding path.

## Future Work

- Feature Passport JSON Schema.
- Evidence event JSON Schema.
- Receipt JSON Schema.
- Feature Passport signing and verification profile.
- SDK guidance for Swift, backend services, and web runtimes.
- Provider-neutral evidence evaluator and ingestion adapters, including SpecGraph.
- SpecSpace evidence ladder UI.
- Hypercode / HCS probe binding.
- Vendor adapters for OpenTelemetry, OpenFeature, CI/CD provenance, release
  systems, and product analytics systems.
- 0AL-wide declaration profile alignment with Agent Passport.
- Formal `EvidenceClaim` schema and claim-to-receipt matching rules.
- Privacy profile for pseudonymous user/session identifiers and salt rotation.
- Failure and abort event vocabulary, such as `fp.feature.error`.

## Standards and References

Later implementation documents should normatively reference the standards and
systems they depend on. Initial candidates:

- JSON Canonicalization Scheme, RFC 8785, for deterministic receipt and
  passport hashing; YAML passports are normalized to JSON before
  canonicalization and signing.
- Ed25519 / EdDSA profiles for receipt and passport signatures.
- SLSA provenance for build attestation semantics.
- GitHub Artifact Attestations for GitHub-hosted build provenance.
- Sigstore / Cosign for artifact signatures and attestations.
- OpenTelemetry semantic conventions for service, deployment, and runtime
  resource attributes.
- OpenFeature hooks for feature flag evaluation observations.

## Non-Goals

This proposal does not define:

- telemetry SDK implementation;
- ingestion infrastructure;
- storage backend;
- hosted UI or SpecSpace UI;
- vendor-specific integrations;
- performance profiling;
- perfect remote attestation of arbitrary client devices.

## Risks and Mitigations

| Risk | Why It Matters | Mitigation |
| --- | --- | --- |
| Analytics masquerading as proof | Dashboards can look convincing without proving a chain | Receipt model and typed claims |
| Client spoofing | iOS/macOS clients are not trusted roots | Explicit authority policy, source trust, and independently corroborated outcomes |
| Replay events | Old events can be resent | Idempotency key, nonce, timestamp window |
| Missing telemetry | No event is not proof of non-usage | Absence semantics |
| Vendor lock-in | Vendors may become accidental truth sources | Adapter-only role |
| Privacy leakage | Feature events can reveal user behavior | Pseudonymous IDs, PII ban, retention policy |
| Probe drift | Code changes while probes stay stale | Feature Passport versioning |
| Rollback confusion | Events may arrive from old builds | Release/build identity required; claim evaluation respects release validity windows, so receipts from rolled-back builds stay historical but stop satisfying current-production claims |
| Sampling ambiguity | Adoption numbers lose meaning | Sampling policy in passport |

## Boundary of the First Proposal

This proposal defines the product evidence architecture. Later specifications
may define SDKs, ingestion services, storage engines, UI components, query
languages, or vendor adapters.

The central formula is:

```text
Feature Passport declares what must be proven.
Runtime events observe what happened.
Evidence receipts seal what a named authority accepts under a declared policy.
Evidence levels explain how strong the proof is.
```
