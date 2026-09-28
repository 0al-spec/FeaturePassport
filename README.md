# Feature Passport

Feature Passport defines provider-neutral feature evidence contracts for the
0AL software factory. SpecGraph, code indexers, build systems, runtime probes,
and viewers connect through adapters; none is a required dependency of the core.

The initial design target is a machine-readable contract that declares what
must be proven for a product feature: intent, implementation links, delivery
artifacts, runtime probes, privacy boundaries, and accepted evidence receipts.

The repository contains an experimental Swift validator for the passport
document envelope and passport-local references, a read-only resolver for
Swift declarations in pinned Git commits, and a bounded matcher for normalized
runtime observations. Provider adapters, signature verification, authority
policy, accepted receipts, and runtime integrations remain proposals.

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
swift run feature-passport evaluate-observation passport.json \
  --passport-digest sha256:expected-digest observation.json
```

The CLI prints `valid` and exits 0 for a valid document, exits 1 with
diagnostics for invalid documents, and exits 2 for invocation or file errors.
The first validator accepts JSON input. This is an experimental subset of the
proposed v1 contract; it is not yet a complete operational passport verifier.
`make validate-zeusus` checks the authored Zeusus binding pilot against the
same local contract.

The observation evaluator checks exact passport/probe linkage and the probe's
declared attribute, element, and runtime-correlation boundaries. Its
`matched_untrusted` verdict means only that this local contract matched; it is
not a signature-verified observation, accepted receipt, or `runtime_verified`
claim. See the [runtime observation evaluation contract](docs/contracts/runtime-observation-evaluation.md).

## Pinned source resolution

```sh
swift run feature-passport resolve-sources path/to/passport.json \
  --repository zeusus=/absolute/path/to/Zeusus
make resolve-zeusus ZEUSUS_CHECKOUT=/absolute/path/to/Zeusus
```

The command emits a JSON report for each source anchor. Exit status 0 means
every anchor has exactly one matching Swift declaration at its full pinned Git
commit; 1 means an unresolved anchor or invalid passport; 2 means an invocation
or internal error. The resolver reads committed Git blobs only, without using
working-tree files or fetching from the network. The configured checkout must
already contain the commit. It does not verify module ownership, compilation,
behavior, test execution, or provider contracts. See the
[source-resolution contract](docs/contracts/source-resolution.md).

## Documents

- [Feature Passport Runtime Evidence Contract, RFC 0001 v0.3.0](docs/proposals/0001_feature_runtime_evidence_layer.md)
- [Zeusus route composition: implementation-binding pilot](docs/examples/zeusus-route-composition.md)
- [ADR 0001: Swift validation stack](docs/adr/0001-swift-validation-stack.md)
- [Passport v1 document validation profile](docs/contracts/passport-v1-validation.md)
- [Pinned Swift source-resolution contract](docs/contracts/source-resolution.md)
- [Runtime observation evaluation contract](docs/contracts/runtime-observation-evaluation.md)
- [Swift validation spike evidence](docs/evidence/swift-validation-spike.md)
- [Passport v1 profile evidence](docs/evidence/passport-v1-profile.md)
- [Zeusus passport validation evidence](docs/evidence/zeusus-passport-validation.md)
- [Pinned source resolver evidence](docs/evidence/source-resolver.md)

Run `make test` to check the Swift package and repository documentation.
