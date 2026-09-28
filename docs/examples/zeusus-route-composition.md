# Zeusus route composition: implementation-binding pilot

Status: draft example for RFC `FP-RFC-0001` v0.3.0. The executable
[JSON passport](../../examples/zeusus-route-composition.json) passes local
document validation. It is an authored binding inventory, not a resolved
external contract, verified runtime observation, or signed receipt.

Zeusus supplies a concrete software-factory pilot: route strategies are composed
in order, receive a read-only planning context and preceding results, and select
the first available route. SpecificationCore classifies candidate availability.
The default composition contains one straight-first strategy. Multiple passes
are exercised by test doubles; several production route algorithms are not
claimed to be integrated.

## Source and Contract Provenance

Implementation anchors below identify the local Zeusus repository at commit
`09a8455e03e3047c19a3f6f33a69ba14ac3c084e`. The repository name `zeusus` must be
resolved by the deployment to its checkout or source archive; a hosted remote
is not required. The internal Swift symbols were inspected directly in that
revision. Feature Passport's Swift source resolver now resolves all four
anchors against that pinned revision. A Zeusus local pilot checks that the
current source and test trees match the pinned revision before resolving them.

The optional SpecGraph reference identifies `ZEU-SPEC-0016` and scenario
`ZEU-ROAD-STRATEGY-COMPOSITION-001` in workspace `zeusus`. The product spec lives
in a separate local worktree. This example has not pinned its content digest,
so its external reference remains unresolved for evidence purposes. The
implementation commit is not assumed to be the revision of that spec.

Local acceptance criteria state the relevant contract independently. Removing
`contract_refs` and the binding's `contract_ref_ids` leaves the draft usable.
Replacing the provider requires changing its locator and resolution evidence,
not the feature, element, or probe identities.

## Proposed Passport

```yaml
artifact_kind: feature_passport
schema_version: 1
metadata:
  passport_id: fp.zeusus.route-composition
  feature_id: feature.zeusus.route-composition
  title: Deterministic route strategy composition
  owner: zeusus
  issuer: zeusus.contract-author
  version: 0.2.0
  status: draft
spec:
  intent:
    summary: Compose route strategies and select their result deterministically.
    acceptance_criteria:
      - id: ordered-composition
        text: Passes receive the same read-only context and ordered prior results; each result retains component identity and invocation order.
      - id: deterministic-selection
        text: Select the first available route in configured order, or noPath when no pass supplies a route, without mutating the world.
  contract_refs:
    - id: route-composition-contract
      relation: implements
      provider: specgraph
      locator:
        workspace: zeusus
        node_id: ZEU-SPEC-0016
        scenario_id: ZEU-ROAD-STRATEGY-COMPOSITION-001
  implementation:
    repositories:
      - name: zeusus
    commits:
      - repository: zeusus
        sha: 09a8455e03e3047c19a3f6f33a69ba14ac3c084e
        role: primary_implementation
    elements:
      - id: route-composition
        role: composition
        anchors:
          - repository: zeusus
            revision: 09a8455e03e3047c19a3f6f33a69ba14ac3c084e
            language: swift
            module: ZeususInput
            path: Sources/ZeususInput/OrthogonalRoadRouteStrategy.swift
            symbol: RoadRouteStrategyComposition.evaluate(in:recordingTo:)
        uses:
          - element_id: straight-first-pass
            relation: invokes
            invocation_order: 0
          - element_id: candidate-selection
            relation: evaluates
      - id: straight-first-pass
        role: strategy
        anchors:
          - repository: zeusus
            revision: 09a8455e03e3047c19a3f6f33a69ba14ac3c084e
            language: swift
            module: ZeususInput
            path: Sources/ZeususInput/OrthogonalRoadRouteStrategy.swift
            symbol: StraightFirstRoadRoutePass.evaluate(in:priorResults:)
      - id: candidate-selection
        role: policy
        anchors:
          - repository: zeusus
            revision: 09a8455e03e3047c19a3f6f33a69ba14ac3c084e
            language: swift
            module: ZeususInput
            path: Sources/ZeususInput/OrthogonalRoadRouteStrategy.swift
            symbol: RoadRouteCompositionSpecifications.candidateSelection()
      - id: composition-scenario-test
        role: test
        anchors:
          - repository: zeusus
            revision: 09a8455e03e3047c19a3f6f33a69ba14ac3c084e
            language: swift
            module: ZeususSimulationTests
            path: Tests/ZeususSimulationTests/RoadStrokeAdapterTests.swift
            symbol: RoadStrokeAdapterTests.routeStrategyCompositionPassesReadOnlyResultsInOrder()
    bindings:
      - id: composition-realization
        contract_ref_ids: [route-composition-contract]
        acceptance_criteria_ids: [ordered-composition, deterministic-selection]
        element_ids: [route-composition, straight-first-pass, candidate-selection]
        test_element_ids: [composition-scenario-test]
  evidence:
    required_level: L6
    probes:
      - id: zeusus.route-composition.executed.v1
        event: fp.feature.code_path.executed
        level: L6
        required: true
        element_ids: [route-composition, straight-first-pass, candidate-selection]
        attributes: [invocation_order, candidate_outcome, selected_element_id]
  privacy:
    pii_allowed: false
    retention_days: 30
    raw_payload_storage: false
```

`required_level: L6` is a future delivery/runtime evidence target, not the current
result. Claiming that level still requires lower applicable levels and matching
environment/build evidence. Zeusus now records route diagnostics through an
operation-scoped sink, but it does not emit this Feature Passport probe's
canonical observation envelope or an accepted receipt.

## Evidence Available Today

At the implementation revision, Zeusus records **21 passing
`RoadStrokeAdapterTests`** and **5 passing route-trace tests** via SwiftPM.
The open Xcode project also built successfully on the iPad Air M3 Simulator
destination. The source record is `docs/evidence/route-runtime-tracing.md` in
the local Zeusus repository. The focused composition scenario was separately
run by the Zeusus local Feature Passport pilot; its card, source-resolution
result, and xUnit report are recorded at
`docs/evidence/feature-passport-route-pilot.md`. The same pipeline is checked
into a Zeusus GitHub Actions workflow, but Zeusus has no Git remote, so no
hosted run is claimed.

The named scenario test checks order, prior-result handoff, first-route
selection, repeated-evaluation equality, and unchanged world state. The single
test binding above is intentionally not a coverage claim for all local criteria
or every rule in `ZEU-SPEC-0016`; for example, it does not directly exercise a
composition where every pass returns noPath.

| Aspect | Pilot status |
| --- | --- |
| Source anchors | Four of four resolved by the Swift source resolver at the pinned Zeusus commit in a local pilot |
| Local document validation | `make validate-zeusus` passes schema and local reference checks |
| External contract resolution | Unresolved; spec revision/digest not pinned here |
| Local implementation mapping | Authored in this draft; not automatically extracted |
| Tests | 21 route-adapter and 5 route-trace SwiftPM tests passed; one focused scenario also passed in the local pilot |
| FP runtime probe | Route diagnostics exist; canonical FP observation and receipt are not implemented |
| Passport signature / receipt | None |
| Production delivery or adoption | Not established |

## Next Implementation Boundary

The provider-neutral envelope and local references validate, and the Swift
source resolver checks these four anchors. The Zeusus test card is a diagnostic
report, not a canonical Feature Passport test-report adapter or accepted
evidence receipt. The next independent boundaries are a SpecGraph locator
adapter and a test-report adapter. A passport with only local criteria uses the
same core path. Runtime events and evidence acceptance require separately
defined instrumentation and authority.
