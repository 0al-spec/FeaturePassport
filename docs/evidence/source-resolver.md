# Pinned source resolver evidence

Date: 2026-09-28. Scope: experimental Swift source identity resolution.

## Checks

- `make test`: passed, including 18 Swift tests, Markdown lint, and all three
  passport fixture validations.
- `make resolve-zeusus`: passed against the local Zeusus checkout without
  changing its working tree. All four authored anchors resolved from commit
  `7e3d9d848fbca3425c2122bc76a08cc47edc09c5`.
- `git diff --check`: passed.

The three strategy/policy declarations came from blob
`99526e0b854cedb20be22f9f768370a848a44cb6`; the scenario-test declaration
came from blob `f4511da6fc0f9bd62f67008c3246ef3a7e03729e`.

Tests also cover a changed working tree, comments and strings, parameter
labels, missing and duplicate declarations, invalid revision and path, missing
file and checkout, invalid document, and a valid draft with no anchors.

This evidence confirms source declarations and local tool behavior only. It
does not establish compilation of the Zeusus commit, scenario satisfaction,
runtime observations, or accepted evidence receipts.
