# Feature Passport

Feature Passport defines provider-neutral feature evidence contracts for the
0AL software factory. SpecGraph, code indexers, build systems, runtime probes,
and viewers connect through adapters; none is a required dependency of the core.

The initial design target is a machine-readable contract that declares what
must be proven for a product feature: intent, implementation links, delivery
artifacts, runtime probes, privacy boundaries, and accepted evidence receipts.

The repository contains an experimental Swift validator for the passport
document envelope and passport-local references, a read-only resolver for
Swift declarations in pinned Git commits, a bounded matcher for normalized
runtime observations, a bounded local issuer and verifier for signed observation receipts
against a caller-supplied offline trust store. An experimental library issuer
and verifier also sign and verify bounded local aggregate predicate decisions
using caller-injected keys and explicit policy allowlists. Production receipt
issuance, production claim acceptance, general authority-policy services,
provider adapters, and runtime integrations remain proposals.

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

The bounded `verify-receipt` command verifies an Ed25519 authority signature
against a caller-supplied offline trust store, exact passport and observation
byte digests, and the local observation contract. Its
`trusted_observation_receipt` verdict does not establish delivery provenance,
replay uniqueness, successful execution, or a feature outcome. The receipt
profile uses versioned length-prefixed signing fields and deliberately does
not claim JCS conformance. See the [signed observation receipt profile](docs/contracts/signed-observation-receipt-v1.md).

`evaluate-claim` reruns the receipt verifier for every observation/receipt pair
and evaluates a versioned local predicate over exact passport identity, one
operation, an identical source/build tuple, an explicit per-probe result
allowlist, environment, receipt policy, and allowlisted semantic sequence
values. Its unsigned `satisfied` result does not establish `runtime_verified`,
production evidence, or replay protection.
See the [local aggregate claim evaluation profile](docs/contracts/local-aggregate-claim-evaluation-v1.md).

`verify-decision` verifies a signed, input-bound decision and reruns the local
aggregate evaluator at the signed time. The experimental library issuer needs
an injected Ed25519 signer and explicit authorization for the exact claim
policy digest; the repository contains no aggregate-decision issuance CLI or private
key store. The separate local observation issuer does not issue aggregate decisions. `accepted` means only that the bounded local predicate passed. It does
not assert a feature outcome, delivery provenance, production deployment,
`runtime_verified`, or replay protection. Its versioned signing encoding is
not JCS. See the [signed aggregate claim decision profile](docs/contracts/signed-aggregate-claim-decision-v1.md).

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
- [Signed observation receipt verifier v1](docs/contracts/signed-observation-receipt-v1.md)
- [Local aggregate claim evaluation v1](docs/contracts/local-aggregate-claim-evaluation-v1.md)
- [Signed aggregate claim decision v1](docs/contracts/signed-aggregate-claim-decision-v1.md)
- [Swift validation spike evidence](docs/evidence/swift-validation-spike.md)
- [Passport v1 profile evidence](docs/evidence/passport-v1-profile.md)
- [Zeusus passport validation evidence](docs/evidence/zeusus-passport-validation.md)
- [Pinned source resolver evidence](docs/evidence/source-resolver.md)

Run `make test` to check the Swift package and repository documentation.

## Bounded receipt issuance

The provider-neutral `EvidenceReceiptIssuer` and local `issue-receipt` CLI now
implement exact contract-match acceptance under explicit policy/key authorization.
They do not infer runtime origin, production delivery or outcome claims. Key
custody remains caller-owned. See [issuance v1](docs/contracts/observation-receipt-issuance-v1.md)
for strict inputs, CLI exit codes and limits. `make test-receipt-issuer` exercises
the actual CLI with ephemeral test keys. SpecGraph proposal 0047 owns coordination;
FeaturePassport does not depend on SpecGraph.

## Native CLI candidate archives

`make package-cli` builds and smoke-checks a clean native release archive with
SwiftPM resources, executable/asset digests and source/toolchain metadata.
The candidate workflow qualifies native targets; it does not publish stable
releases, adopt authority keys or deploy Platform. See
[packaging v1](docs/contracts/cli-release-packaging-v1.md) for the delivery contract.
