# Swift validation spike evidence

The first `swift test` run compiled the package and ran five Swift Testing
scenarios. Three negative cases failed because the validator was still a stub;
two positive cases passed. This was the expected Red step.

After implementing JSON Schema validation and local ID/reference checks, the
same five scenarios passed. Two further cases check a sealed passport without
a signature envelope and malformed JSON. The cases also cover a standalone
passport, missing feature identity, duplicate implementation element IDs, a
binding to a missing element, and an opaque unknown contract provider.

This is evidence for document shape and local consistency only. It does not
resolve provider locators, inspect source symbols, validate signatures, execute
probes, or accept evidence receipts. The schema is an experimental subset of
the proposed v1 contract; acceptance of future fields does not imply their
semantics were checked.

Local verification on 2026-09-28: `make test` passed seven Swift Testing cases
and Markdown lint (seven files, zero issues). `make validate-example` printed
`valid` for the standalone JSON fixture. Running the CLI on a non-JSON file
returned a `schema` diagnostic and exit code 1.
