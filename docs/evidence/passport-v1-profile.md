# Passport v1 profile evidence

This stacked layer extends the experimental passport validator without
changing the provider-neutral identity boundary.

The Red run had four expected failures: missing anchor shape, unknown anchor
repository, non-test element in `test_element_ids`, and an unsupported probe
runtime field. After implementing the profile and local checks, `make test`
passed 12 Swift Testing cases, Markdown lint reported zero issues in eight
files, and both standalone and RFC-derived JSON fixtures printed `valid`.

The RFC-derived fixture contains illustrative digest and signature strings.
Successful validation proves only document shape and local consistency. It
does not verify those strings or promote the fixture to operational evidence.
