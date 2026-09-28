# Feature Passport

Feature Passport defines provider-neutral feature evidence contracts for the
0AL software factory. SpecGraph, code indexers, build systems, runtime probes,
and viewers connect through adapters; none is a required dependency of the core.

The initial design target is a machine-readable contract that declares what
must be proven for a product feature: intent, implementation links, delivery
artifacts, runtime probes, privacy boundaries, and accepted evidence receipts.

The repository is at the architecture-proposal stage. It does not yet ship JSON
Schemas, validators, SDKs, an evidence evaluator, or runtime integrations.

## Documents

- [Feature Passport Runtime Evidence Contract, RFC 0001 v0.3.0](docs/proposals/0001_feature_runtime_evidence_layer.md)
- [Zeusus route composition: implementation-binding pilot](docs/examples/zeusus-route-composition.md)

Run `make markdown-lint` to check repository documentation.
