# Feature Passport development

- Feature Passport is a provider-neutral part of the 0AL software factory.
  SpecGraph is an optional adapter source/consumer, never a mandatory core
  schema, service, ID format, or evidence authority.
- Current deliverables are architecture proposals and worked examples. Mark
  draft syntax explicitly and distinguish it from implemented schemas, SDKs,
  resolvers, runtime observations, and accepted evidence receipts.
- Keep local acceptance criteria and feature/passport identities usable without
  external contract references. Provider locator semantics belong to adapters.
- Implementation links may identify policies, strategies, compositions, ordinary
  types, call sites, and tests. Do not infer behavioral coverage from source
  names, annotations, inventories, or the existence of a passing test suite.
- Receipts record acceptance by an identified authority under a versioned
  policy. Preserve environment, source/build, and passport-version boundaries.
- Keep compatibility notes for renamed fields/events and documents. Never
  suggest rewriting signed historical evidence in place.
- Put repeatable checks in `Makefile`, preserve unrelated work, and finish
  changes with focused commits and a reviewable PR.
