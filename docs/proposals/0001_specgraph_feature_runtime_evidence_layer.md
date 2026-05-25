# SpecGraph Feature Runtime Evidence Layer

Status: Draft / Proposal

## Summary

The SpecGraph Feature Runtime Evidence Layer defines a canonical product
evidence model for proving that a user-requested feature progressed from
specification intent to implementation, build, release, production runtime
observation, feature execution, and user-visible outcome.

The layer is stronger than ordinary analytics. It does not merely count events.
It links SpecGraph nodes, commits, build artifacts, releases, runtime sessions,
feature probes, and signed evidence receipts into a verifiable evidence chain.

## Motivation

SpecGraph needs to answer a product-critical question:

> Did the feature requested by the user actually reach production and work for
> users?

The answer must be stronger than:

- the commit appears in release notes;
- the pull request was merged;
- a dashboard contains an unrelated analytics event;
- a feature flag was enabled.

The desired claim is:

- the user request is represented as a SpecGraph node;
- the feature has a declared FeaturePassport;
- implementation commits are linked to the feature;
- build artifacts include those commits and have provenance;
- the artifacts were released or deployed to production;
- production runtime sessions reported the build identity;
- feature-specific probes observed exposure, execution, effect, and outcome;
- SpecGraph accepted and sealed those observations as evidence receipts.

## Canonical Chain

```text
SpecGraph request / spec node
  -> FeaturePassport
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

External systems may provide evidence inputs, but they do not define SpecGraph
truth.

CI/CD systems provide build attestations. Release systems provide deployment
attestations. Telemetry systems provide runtime observations. Feature flag
systems provide exposure or evaluation observations.

SpecGraph normalizes all of them into evidence claims, observations,
attestations, and receipts.

## Terminology

### FeaturePassport

A machine-readable contract that declares a feature's identity, origin,
implementation links, delivery expectations, required runtime probes, privacy
constraints, and signature metadata.

### Evidence Claim

A statement SpecGraph wants to prove.

Example:

```text
Feature feature.invoice.smart_summary reached production and completed its
intended user-visible outcome for at least one production user.
```

### Observation

A raw runtime signal emitted by a client, backend, agent, or service.

### Attestation

A signed statement from a trusted system, such as a CI/CD build provenance
attestation or deployment attestation.

### Evidence Receipt

A server-issued, signed or hash-linked record that SpecGraph accepted an
observation or attestation as evidence.

Observation is what happened. Receipt is what SpecGraph accepted as evidence.

### Evidence Chain

A traversable graph path connecting a SpecGraph request to implementation,
delivery, runtime execution, and outcome receipts.

## Evidence Levels

| Level | Name | Meaning |
| --- | --- | --- |
| L0 | Specified | User request or spec node exists |
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

## FeaturePassport Shape

The first schema should follow SpecGraph artifact conventions rather than
Kubernetes-style `apiVersion` / `kind` fields.

```yaml
artifact_kind: feature_passport
schema_version: 1
metadata:
  feature_id: "feature.invoice.smart_summary"
  request_id: "SG-REQ-2026-001"
  title: "Smart invoice summary"
  owner: "ios-product"
  version: "0.1.0"
  issued_at: "2026-05-25T12:00:00Z"
  issuer: "specgraph.internal.release-authority"
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
  implementation:
    repositories:
      - name: "product-ios"
        url: "git@github.com:org/product-ios.git"
    pull_requests:
      - "1842"
    commits:
      - sha: "8ae73a0f..."
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
        event: "sg.release_seen"
        level: "L4"
        required: true
      - id: "invoice_summary.visible.v1"
        event: "sg.feature.exposed"
        level: "L5"
        required: true
        required_when: "ui_or_user_entry_point"
      - id: "invoice_summary.render.v1"
        event: "sg.feature.code_path.executed"
        level: "L6"
        required: true
      - id: "invoice_summary.backend_accepted.v1"
        event: "sg.feature.effect_committed"
        level: "L7"
        required: true
      - id: "invoice_summary.completed.v1"
        event: "sg.feature.outcome_completed"
        level: "L8"
        required: true
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
  algorithm: "EdDSA"
  public_key_ref: "did:specgraph:issuer:release-authority#key-1"
  signed_by: "specgraph.internal.release-authority"
  value: "base64-signature"
```

## Canonical Event Envelope

All evidence events should share a stable envelope so SDKs, ingestion services,
and adapters do not invent incompatible payloads.

`request_id` is the canonical key. External or older producers may send
`specgraph_request_id`, but ingestion must normalize it into `request_id` before
the event is accepted.

```json
{
  "schema_version": "specgraph.evidence.event.v1",
  "event_name": "sg.feature.code_path.executed",
  "specgraph": {
    "request_id": "SG-REQ-2026-001",
    "feature_id": "feature.invoice.smart_summary",
    "feature_passport_id": "fp_01J...",
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
- `specgraph.request_id`;
- `specgraph.feature_id`;
- `specgraph.probe_id`;
- `delivery.environment`;
- `delivery.platform`;
- `observation.occurred_at`;
- `integrity.event_id`;
- `integrity.idempotency_key`.

Conditional fields:

- `delivery.git_sha`, `delivery.artifact_digest`, and `delivery.release_id` are
  required when claiming delivery or release linkage.
- `runtime.user_hash` and `runtime.session_id` are required for user-session
  evidence, but may be omitted for backend, batch, service-side, or headless
  evidence where no user session exists.

## Event Vocabulary

### `sg.release_seen`

A production runtime instance or session reported a known build identity.

### `sg.feature.exposed`

The user was presented with a feature surface, entry point, UI element, API
capability, or workflow state.

For non-UI, backend-only, batch, headless, or background features, exposure may
be explicitly marked not applicable. In those cases, L6 or server-confirmed L7
is the first meaningful runtime evidence level.

### `sg.feature.code_path.executed`

The implementation path associated with the feature was entered.

### `sg.feature.effect_committed`

The feature produced a durable state change, accepted backend command, stored
record, emitted durable message, or equivalent committed effect.

### `sg.feature.outcome_completed`

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

Runtime observations are not canonical evidence until accepted by SpecGraph.

A SpecGraph evidence receipt records:

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
  "schema_version": "specgraph.evidence.receipt.v1",
  "receipt_id": "rcpt_01J...",
  "event_id": "evt_01J...",
  "accepted_claims": [
    {
      "claim_id": "claim_feature_runtime_execution",
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
    "signed_by": "specgraph.evidence-ingestor.production",
    "public_key_ref": "did:specgraph:evidence-ingestor#key-1",
    "value": "base64-signature"
  },
  "timestamps": {
    "observed_at": "2026-05-25T15:03:44Z",
    "ingested_at": "2026-05-25T15:03:47Z",
    "sealed_at": "2026-05-25T15:03:48Z"
  }
}
```

Hash-linked receipts use the sealed previous receipt hash:

```text
receipt_hash_n = sha256(canonical_json(event_n) + previous_hash)
```

For the first receipt, `previous_hash` is a declared genesis value.

The client may emit observations. The server must issue evidence receipts. Only
receipts are considered canonical SpecGraph evidence.

## Honesty and Trust Boundaries

The Feature Runtime Evidence Layer does not claim that all client-side
observations are cryptographically trustworthy.

A mobile or desktop client may be compromised, modified, offline, blocked from
uploading telemetry, sampled out, or unable to send events before termination.

Therefore:

- client-side events are observations, not final proof;
- server-issued receipts are canonical evidence;
- server-confirmed effects have stronger evidence value than client-only events;
- absence of evidence is not automatically evidence of absence;
- adoption metrics must declare sampling, retention, and upload policies.

| Claim | Strength |
| --- | --- |
| Commit included in artifact | Strong, with build attestation |
| Artifact released to production | Strong, with deploy or release attestation |
| Runtime reported build identity | Strong operational evidence |
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

- commit is linked to request;
- artifact attestation includes commit;
- release or deploy record references artifact;
- at least one production runtime emitted `sg.release_seen` for that
  artifact/build.

Minimum claim for "feature worked in production":

- all of the above;
- required FeaturePassport probes are declared;
- `sg.feature.code_path.executed` was observed;
- `sg.feature.effect_committed` or `sg.feature.outcome_completed` was sealed by
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

These systems are adapters or transports. They are not the canonical SpecGraph
evidence model.

## Viewer Model

SpecGraph viewers should display evidence as a ladder, not a boolean.

Example:

```text
SG-REQ-2026-001: Smart invoice summary
L0 Specified                  yes
L1 Implemented                yes, PR #1842 / commit 8ae73a
L2 Built                      yes, artifact sha256:abc123
L3 Released                   yes, ios 2.7.0 build 134
L4 Runtime Seen               yes, runtime sg.release_seen received
L5 Feature Exposed            yes, 4,882 users
L6 Code Path Executed         yes, 2,744 users
L7 Effect Committed           yes, 2,603 users
L8 Outcome Completed          yes, 2,571 users
Evidence Strength: L8 / Strong
```

The viewer-facing ladder is a required product model, but this proposal does not
define the concrete UI implementation.

## Future Work

- FeaturePassport JSON Schema.
- Evidence event JSON Schema.
- Receipt JSON Schema.
- FeaturePassport signing and verification profile.
- SDK guidance for Swift, backend services, and web runtimes.
- SpecGraph evidence ingestion service.
- SpecSpace evidence ladder UI.
- Hypercode / HCS probe binding.
- Vendor adapters for OpenTelemetry, OpenFeature, CI/CD provenance, release
  systems, and product analytics systems.

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
| Client spoofing | iOS/macOS clients are not trusted roots | Server-side receipts and backend outcomes |
| Replay events | Old events can be resent | Idempotency key, nonce, timestamp window |
| Missing telemetry | No event is not proof of non-usage | Absence semantics |
| Vendor lock-in | Vendors may become accidental truth sources | Adapter-only role |
| Privacy leakage | Feature events can reveal user behavior | Pseudonymous IDs, PII ban, retention policy |
| Probe drift | Code changes while probes stay stale | FeaturePassport versioning |
| Rollback confusion | Events may arrive from old builds | Release/build identity required |
| Sampling ambiguity | Adoption numbers lose meaning | Sampling policy in passport |

## Boundary of the First Proposal

This proposal defines the product evidence architecture. Later specifications
may define SDKs, ingestion services, storage engines, UI components, query
languages, or vendor adapters.

The central formula is:

```text
FeaturePassport declares what must be proven.
Runtime events observe what happened.
Evidence receipts seal what SpecGraph accepts.
Evidence levels explain how strong the proof is.
```
