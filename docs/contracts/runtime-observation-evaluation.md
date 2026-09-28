# Runtime observation evaluation (experimental)

`RuntimeObservationEvaluator` implements the first local, provider-neutral
matching slice from FP-RFC-0001 v0.3. It consumes one Feature Passport JSON
document, its expected digest supplied by the caller, and one normalized
`feature_observation` JSON event. No SpecGraph or other provider ID is needed.

```sh
swift run feature-passport evaluate-observation passport.json \
  --passport-digest sha256:expected-observed-version observation.json
```

The observation uses the RFC v1 envelope: `artifact_kind`, `schema_version`,
`event_name`, exact `feature_passport` identity (`feature_id`, `passport_id`,
`version`, `digest`, `probe_id`), `delivery`, optional `runtime`,
`observation`, and `integrity`. Its payload attributes are string-valued in this
initial SDK model. The implementation element ID is optional. Optional
`delivery.git_sha`, `artifact_digest`, `release_id`, and `build_number` values
are retained during decode/encode so the event preserves its source/build
boundary; this matcher does not verify them against an attestation or passport
artifact.

The evaluator validates the passport with the existing local validator, then
checks exact feature/passport/version/digest identity, declared probe ID, event
name, probe attribute allowlist, and (when supplied) probe element allowlist.
`required_runtime_fields` requires nonempty `operation_id` and/or
`invocation_id`. A probe without those requirements may omit them. Evaluations
are deterministic for the same JSON inputs and expected digest.

## Verdicts

| Verdict | Meaning |
| --- | --- |
| `matched_untrusted` | Local passport contract matched; the event is still an untrusted observation. |
| `untrusted` | The normalized event conflicts with the declared identity/probe contract or contains undeclared evidence. |
| `insufficient` | The event could not be normalized or the supplied passport failed local validation. |

`matched_untrusted` is not an accepted receipt and does not establish
`runtime_verified`, production delivery, successful execution, or a user outcome.
The CLI exits 0 only for this contract-match result and prints the verdict; it
exits 1 for other verdicts and 2 for invocation/I/O errors.

The caller supplies `passportDigest` because the RFC leaves canonicalization
and digest verification to a later trust stage. This implementation compares
that expected string with the observation; it does not calculate the digest,
verify passport or observation signatures, establish issuer/authority trust,
evaluate delivery attestations or environment policy, enforce replay windows,
aggregate evidence, or issue a receipt. A caller must not treat the argument as
validated provenance. Those checks belong in the future configured evidence
authority, with its explicit trust policy and accepted evidence policy revision.
