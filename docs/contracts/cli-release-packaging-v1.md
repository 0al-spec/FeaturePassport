# CLI release packaging v1

This is the delivery slice of SpecGraph proposal 0047. FeaturePassport packages
the native executable and SwiftPM schema resources; Platform owns subsequent
reviewed dependency pins, compatible runner installation and image delivery.
SpecGraph consumes admission results and SpecSpace displays read models. Neither
a CLI archive nor an image digest installs signing authority or consumer trust.

## Local packaging

```sh
make test-package-cli
make package-cli CLI_RELEASE_VERSION=0.0.0-local
```

Packaging requires a clean committed checkout and locked Swift dependencies. It
builds native release configuration, discovers the actual bin path, checks issuer
capability, archives the executable plus resource bundles, adjacent dynamic
libraries and dependency license notices, rejects symlinks, and refuses an existing output directory. It emits:

- A target-specific `.tar.gz` archive with normalized tar metadata.
- A JSON `feature_passport_cli_release` manifest, version 1, with source commit,
  target, toolchain, actual capabilities, per-file size/SHA-256 and archive digest.
- A `.sha256` file covering archive and manifest bytes.

It temporarily hides the original build resource bundles (restoring them even
after a smoke failure), so SwiftPM fallback cannot mask an incomplete archive.
It then extracts the archive into a fresh temporary directory, executes help and
capability checks, validates a passport through the bundled schema, compares
asset digests and rechecks clean source identity. Failed smoke validation must
not be published. Artifacts from a failed attempt may remain for diagnosis; only
a successful process exit is a completed packaging run.

The target is the native host OS/architecture, not a cross-compilation promise.
The initial candidate workflow builds macOS arm64 and native Linux amd64/arm64;
Linux uses an explicit digest of the official Swift 6.1.3 Noble image. CI must
pass each target before a consumer may treat it as supported. No local Linux or
x86_64 macOS proof is implied by a successful arm64 macOS build.

## Runtime and authority limits

Archives are not claimed to be static or universally portable. The manifest
records the build toolchain/host and declares compatible runtime/system-library
requirements. Platform must qualify its actual Linux runner, including Swift
runtime and dependency resources, rather than copying a macOS executable or
assuming its Python base image supplies them. A checksum verifies against an
approved pin; it does not authenticate a publisher or constitute a build
attestation. This packager issues no provenance attestation.

The `.github/workflows/cli-release.yml` workflow produces **candidate** CI assets
on relevant PRs or explicit dispatch. It does not create a GitHub Release, publish
a stable tag, deploy Platform or install keys. Promotion to an approved immutable
release and publisher/provenance trust remains an explicit subsequent review.
No release candidate automatically becomes a Platform dependency lock.

The archive deliberately contains no authority configuration, private keys,
receipts or product-specific evidence. Signed inputs must retain exact bytes
when carried through a runner; read models are separate projections. Match,
receipt acceptance, aggregate decision, admission and delivery are distinct.

## Verification evidence

The packaging unit suite first failed because the packager module did not exist.
Its Green covers resource inclusion/digest inventory, refusal to overwrite output,
missing resources, symlink rejection and build-resource isolation/restoration. A native archive smoke result is separate
from those unit checks and from uncompleted Linux CI.
