# Passport v1 document validation profile

Status: proposed for review. This profile describes the experimental JSON
Schema and Swift validator in this repository. It is a document-validation
slice of [RFC 0001](../proposals/0001_feature_runtime_evidence_layer.md),
not an evidence acceptance policy.

## Shape and lifecycle

- A document has `artifact_kind: feature_passport`, `schema_version: 1`,
  `metadata`, and `spec`.
- `metadata` supplies local `feature_id`, `passport_id`, `version`, `status`,
  and `issuer`. Both IDs stay independent of every contract provider.
- `draft` requires intent, at least one local acceptance criterion, a target
  evidence level, a probe list, and privacy boundaries. Implementation,
  delivery, runtime, and adoption may be incomplete.
- `sealed` additionally requires a signature envelope. Shape validation does
  not verify the signature, issuer authority, digest, or canonicalization.
- `required_level` is a target. It does not claim that level has been reached;
  missing delivery or runtime evidence does not invalidate a draft targeting
  L6 or above.

## Local consistency

| Collection | Unique key | Checked references |
| --- | --- | --- |
| Acceptance criteria | `id` | Binding `acceptance_criteria_ids` |
| Contract references | `id` | Binding `contract_ref_ids` |
| Repositories | `name` | Pull requests, commits, source anchors |
| Elements | `id` | Bindings, `uses`, probes |
| Bindings | `id` | None |
| Probes | `id` | None |

Every implementation element has a nonempty `anchors` list. Each anchor
declares repository, revision, language, module, path, and symbol. These are
authored source identities; the validator checks their shape and repository
reference but does not inspect a checkout or resolve the symbol. A binding's
`test_element_ids` must refer to elements with role `test`. Other role labels
remain open vocabulary.

Provider-owned `contract_refs[].locator` objects remain opaque. Unknown
providers do not block document validation. Resolution state, pinned source
content, and contract authority belong to a separate adapter result.

Probe declarations specify event name, evidence level, required flag, optional
`required_when` predicate, optional attribute and element allowlists, and
optional `required_runtime_fields`. The latter can contain only `operation_id`
and `invocation_id`. This validator checks declaration shape and local element
references; it does not inspect observations.

## Validation result

The Swift API returns `schema`, `duplicate_id`, `missing_reference`, or
`invalid_reference_role` diagnostics. Malformed JSON is a `schema` diagnostic.
The CLI exits 0 when there are no diagnostics, 1 when the document is invalid,
and 2 for invocation, file, or internal validator errors. A successful result
means only that the document satisfies this local profile.

Unknown fields in v1 objects are currently accepted for forward-compatible
experiments but receive no semantic validation. A production v1 contract must
decide how extensions are namespaced and whether misspelled core fields are
rejected. This is an explicit review item before using the validator as an
operational admission gate.

The [invoice fixture](../../examples/invoice-passport-schema-fixture.json) is
JSON converted from the RFC's complete sample. It checks schema compatibility
with the proposed delivery, runtime, adoption, and probe sections. Its digest
and signature are illustrative placeholders; a successful local validation
does not make it a genuine sealed passport.

Compatibility note: the earlier experimental validator accepted elements
without anchors and probes containing only an ID. Those drafts need source
anchors and probe declarations to pass this profile. Do not rewrite signed
historical passports or receipts; versioned migration and verification remain
future work.

## Deferred checks

- Verify issuer signatures and canonical JSON digests.
- Resolve provider contract locators. Pinned Swift source anchors can now be
  inspected by the separate read-only resolver; other languages remain open.
- Validate observation and receipt artifact schemas.
- Evaluate required evidence levels, probe conditions, adoption thresholds,
  privacy handling, and authority-issued receipts.

The [Zeusus example](../examples/zeusus-route-composition.md) can establish
declared source bindings under this profile. It cannot establish execution or
accepted coverage until separate evidence exists.
