# Feature Passport

Feature Passport defines provider-neutral feature evidence contracts for the
0AL software factory. SpecGraph, code indexers, build systems, runtime probes,
and viewers connect through adapters; none is a required dependency of the core.

The initial design target is a machine-readable contract that declares what
must be proven for a product feature: intent, implementation links, delivery
artifacts, runtime probes, privacy boundaries, and accepted evidence receipts.

The repository contains an experimental Swift validator for the passport
document envelope and passport-local references. The broader evidence
evaluator, provider adapters, signature verification, source resolution, and
runtime integrations remain proposals.

## Swift validation spike

The checked-in [JSON Schema](Sources/FeaturePassport/Resources/feature-passport.v1.schema.json)
defines the initial JSON envelope. The `FeaturePassport` Swift library uses
that schema and checks unique local IDs and references in bindings, element
relationships, and probes. A passport can validate without `contract_refs`.
Provider locators remain opaque: validation does not prove that a referenced
contract or implementation symbol exists.

```sh
make swift-test
make validate-example
swift run feature-passport validate path/to/passport.json
```

The CLI prints `valid` and exits 0 for a valid document, exits 1 with
diagnostics for invalid documents, and exits 2 for invocation or file errors.
The first validator accepts JSON input. This is an experimental subset of the
proposed v1 contract; it is not yet a complete operational passport verifier.

## Documents

- [Feature Passport Runtime Evidence Contract, RFC 0001 v0.3.0](docs/proposals/0001_feature_runtime_evidence_layer.md)
- [Zeusus route composition: implementation-binding pilot](docs/examples/zeusus-route-composition.md)
- [ADR 0001: Swift validation stack](docs/adr/0001-swift-validation-stack.md)
- [Swift validation spike evidence](docs/evidence/swift-validation-spike.md)

Run `make test` to check the Swift package and repository documentation.
