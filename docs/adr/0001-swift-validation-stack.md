# ADR 0001: Swift for the first Feature Passport validator

Status: accepted for the first schema and validator spike, 2026-09-28.

The Feature Passport interchange contract is JSON Schema Draft 2020-12.
Acceptance criteria and implementation references are defined by that
language-neutral schema and by explicitly documented semantic rules.

Use Swift 6.1 or newer and SwiftPM for the first validator library and CLI.
The `FeaturePassport` library loads the checked-in JSON Schema with the MIT
licensed `swift-json-schema` package, pinned to a tested version. A separate
semantic pass checks cross-references and ID uniqueness, which JSON Schema
cannot express by matching an ID field across arrays. The CLI exposes the
same result to non-Swift tools, including a future SpecGraph adapter. A Swift
consumer such as Zeusus can link the library directly when appropriate.

Swift is already used by the Zeusus pilot and runs on macOS and Linux. Rust
remains an alternative for future evidence ingestion or validation if actual
conformance, operational, or performance evidence warrants it. Language choice
does not change the passport wire format or make SpecGraph a required provider.

This ADR covers document validation only. It does not assert that a document's
external contract was resolved, that an implementation symbol exists, or that
an event/receipt signature is valid. Signing requires a separate RFC 8785
canonicalization implementation and cross-language test vectors.

The spike succeeds when a local passport validates without provider adapters,
invalid schema shape, duplicate IDs, and broken bindings produce distinct
diagnostics, and the SwiftPM test suite passes. The initial supported input is
JSON; YAML intake can be added after its normalization rules are specified.
