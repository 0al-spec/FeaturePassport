# Zeusus passport validation evidence

The [JSON passport](../../examples/zeusus-route-composition.json) materializes
the existing [Zeusus route-composition draft](../examples/zeusus-route-composition.md)
without assigning SpecGraph authority to Feature Passport. It includes local
criteria, one optional `specgraph` contract reference, a composition, strategy,
SpecificationCore policy, scenario test, binding, and a proposed L6 probe.

On 2026-09-28, `make validate-zeusus` printed `valid`. This checks the v1
document shape, passport-local IDs, binding references, element relationships,
probe references, and repository names. The validator did not contact SpecGraph
or Zeusus.

The same checkpoint's `make test` passed 12 Swift Testing cases, Markdown lint
with zero issues in ten files, and all three JSON fixtures. No Zeusus build or
scenario test was run as part of this Feature Passport checkpoint.

The source anchors were manually checked against Zeusus commit
`7e3d9d848fbca3425c2122bc76a08cc47edc09c5`:

| Element | Pinned source |
| --- | --- |
| `route-composition` | `Sources/ZeususInput/OrthogonalRoadRouteStrategy.swift:63–66`, `RoadRouteStrategyComposition.evaluate(in:)` |
| `straight-first-pass` | same file, line 291 onward, `StraightFirstRoadRoutePass.evaluate(in:priorResults:)` |
| `candidate-selection` | same file, line 49, `RoadRouteCompositionSpecifications.candidateSelection()` |
| `composition-scenario-test` | `Tests/ZeususSimulationTests/RoadStrokeAdapterTests.swift:10`, `routeStrategyCompositionPassesReadOnlyResultsInOrder()` |

The pinned file and symbol inspection is separate from the validator result;
an automated source resolver is not implemented. The SpecGraph locator has no
pinned spec digest here, and the proposed runtime probe does not exist in the
game. The passport remains `draft`. No L6 claim or accepted evidence receipt
follows from this check.
