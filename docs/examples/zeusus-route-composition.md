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
`7e3d9d848fbca3425c2122bc76a08cc47edc09c5`. The repository name `zeusus` must be
resolved by the deployment to its checkout or source archive; a hosted remote
is not required. The internal Swift symbols were inspected directly in that
revision. An automatic symbol resolver has not been implemented.

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
  version: 0.1.0
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
        sha: 7e3d9d848fbca3425c2122bc76a08cc47edc09c5
        role: primary_implementation
    elements:
      - id: route-composition
        role: composition
        anchors:
          - repository: zeusus
            revision: 7e3d9d848fbca3425c2122bc76a08cc47edc09c5
            language: swift
            module: ZeususInput
            path: Sources/ZeususInput/OrthogonalRoadRouteStrategy.swift
            symbol: RoadRouteStrategyComposition.evaluate(in:)
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
            revision: 7e3d9d848fbca3425c2122bc76a08cc47edc09c5
            language: swift
            module: ZeususInput
            path: Sources/ZeususInput/OrthogonalRoadRouteStrategy.swift
            symbol: StraightFirstRoadRoutePass.evaluate(in:priorResults:)
      - id: candidate-selection
        role: policy
        anchors:
          - repository: zeusus
            revision: 7e3d9d848fbca3425c2122bc76a08cc47edc09c5
            language: swift
            module: ZeususInput
            path: Sources/ZeususInput/OrthogonalRoadRouteStrategy.swift
            symbol: RoadRouteCompositionSpecifications.candidateSelection()
      - id: composition-scenario-test
        role: test
        anchors:
          - repository: zeusus
            revision: 7e3d9d848fbca3425c2122bc76a08cc47edc09c5
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
environment/build evidence. The proposed probe is not instrumented in Zeusus.

## Evidence Available Today

At the implementation revision, Zeusus records **21 passing
`RoadStrokeAdapterTests`** through the open Xcode workspace, on iPad Air M3
Simulator with iOS 18.6. The source record is
`docs/evidence/road-stroke-routing.md`, section
`Composition-of-strategies implementation — 2026-09-28`. This is a cited existing
test report, not a new execution performed by Feature Passport.

The named scenario test checks order, prior-result handoff, first-route
selection, repeated-evaluation equality, and unchanged world state. The single
test binding above is intentionally not a coverage claim for all local criteria
or every rule in `ZEU-SPEC-0016`; for example, it does not directly exercise a
composition where every pass returns noPath.

| Aspect | Pilot status |
| --- | --- |
| Source anchors | Manually inspected at the pinned Zeusus commit |
| Local document validation | `make validate-zeusus` passes schema and local reference checks |
| External contract resolution | Unresolved; spec revision/digest not pinned here |
| Local implementation mapping | Authored in this draft; not automatically extracted |
| Tests | Existing simulator test report referenced, not re-run |
| FP runtime probe | Proposed; not implemented |
| Passport signature / receipt | None |
| Production delivery or adoption | Not established |

## Next Implementation Boundary

The provider-neutral envelope and local references now validate. Next add a
Swift source resolver, a SpecGraph locator adapter, and an explicit test-report
adapter independently. A passport with only local criteria uses the same core
path. Only after those boundaries work should Zeusus emit the proposed runtime
events and connect them to an explicitly configured evidence authority.
