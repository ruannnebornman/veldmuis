# Release Process

Veldmuis releases are date-tagged builds from `main`. The release workflow
builds packages and an ISO, authenticates the resulting metadata, publishes
release-specific artifacts, advances the `latest` aliases, and creates a
GitHub release.

## Tag Formats

Supported release tags are:

- Monthly scheduled release: `YYYY.MM`
- First manual release on a UTC date: `YYYY.MM.DD`
- Later manual releases on the same UTC date: `YYYY.MM.DD.N`, starting at `.2`

Examples:

```text
2026.04
2026.04.22
2026.04.22.2
```

No `v` prefix, semantic version, alpha, beta, or preview tag format is
supported.

## Scheduled And Manual Releases

The release workflow is defined in `.github/workflows/release.yml`. It runs as
a monthly schedule or by manual dispatch with an explicit daily tag. Manual
dispatch is accepted only from `main`.

Manual release tags must be the next valid tag for that UTC date. For example,
if `2026.04.22` exists, the next release on that date must be
`2026.04.22.2`.

## Immutability Policy

Release tags and release-specific object paths are immutable. Do not move,
delete, overwrite, or reuse them. If a published release is wrong, fix the
source and publish the next valid release tag.

The workflow rejects a release if:

- The tag format is unsupported.
- A same-day manual release sequence is skipped.
- The tag or GitHub release already exists.
- The source no longer matches the `main` commit resolved during validation.
- Signed metadata is absent, invalid, or inconsistent with the build.

The release tag is created only after packages, repositories, the ISO, and its
signed metadata have built successfully. A later external publication failure
can still consume a tag; recovery uses the next valid tag rather than moving or
reusing the failed one.

## Current Workflow Shape

At a high level, the workflow:

1. Resolves a valid tag and exact `main` commit.
2. Checks out that commit with persisted credentials disabled.
3. Checks repository hygiene and the release environment contract.
4. Builds native packages and resolved AUR-derived artifacts without signing
   material.
5. Signs packages and repository databases in a network-disabled container.
6. Builds the ISO without signing material.
7. Generates the package inventory, SPDX SBOM, build-input record, checksum,
   and signed manifest in a network-disabled container.
8. Creates the annotated tag for the exact built commit.
9. Publishes and verifies the package repositories.
10. Uploads and verifies immutable ISO release objects.
11. Copies the verified objects to short-lived `latest` aliases, with the
    detached signature immediately before the signed manifest and the manifest
    last.
12. Creates the GitHub release and attaches the authenticated metadata.
13. Downloads the published manifest and signature and verifies them with the
    packaged public key.

Reusable workflow actions are pinned to complete commit SHAs. Workflow token
permissions are read-only by default and elevated only for the publication job.
Signing material is passed only to network-disabled signing stages, while
object-storage credentials are passed only to publisher steps.

## Protected Release Environment

The hosted environment must be named `release` and restricted to `main`.
Required reviewers may be enabled when practical for the maintainer model. Its
secret inventory is limited to:

```text
VELDMUIS_GPG_PRIVATE_KEY
VELDMUIS_GPG_FPR
CF_R2_ACCESS_KEY_ID
CF_R2_SECRET_ACCESS_KEY
CF_R2_PACKAGE_ACCESS_KEY_ID
CF_R2_PACKAGE_SECRET_ACCESS_KEY
```

The workflow checks that those named secrets and the required non-secret
variables are populated, without retrieving or printing secret values. Review
the hosted environment against this list after any publication-provider or
maintainer-access change.

## Published Artifacts

Each release has an immutable directory:

```text
https://downloads.veldmuislinux.org/iso/releases/YYYY.MM.DD/
```

It contains:

```text
veldmuis-TAG-x86_64.iso
veldmuis-TAG-x86_64.iso.sha256
veldmuis-TAG-x86_64.manifest.txt
veldmuis-TAG-x86_64.manifest.txt.sig
veldmuis-TAG-x86_64.packages.tsv
veldmuis-TAG-x86_64.spdx
veldmuis-TAG-x86_64.build-inputs.txt
veldmuis-TAG-x86_64.aur-packages.manifest.txt
```

Convenience aliases identify the current release:

```text
https://downloads.veldmuislinux.org/iso/latest.iso
https://downloads.veldmuislinux.org/iso/latest.iso.sha256
https://downloads.veldmuislinux.org/iso/latest.manifest.txt
https://downloads.veldmuislinux.org/iso/latest.manifest.txt.sig
https://downloads.veldmuislinux.org/iso/latest.packages.tsv
https://downloads.veldmuislinux.org/iso/latest.spdx
https://downloads.veldmuislinux.org/iso/latest.build-inputs.txt
https://downloads.veldmuislinux.org/iso/latest.aur-packages.manifest.txt
```

The signed manifest is the `latest` publication marker and points back to
immutable objects. A reader may fail closed during the short alias-copy window,
but cannot authenticate a mixed release as valid.

Releases produced by the current workflow retain the checksum, signed manifest
and signature, package inventory, SPDX SBOM, build inputs, and exact AUR-input
manifest. Release notes link to the immutable ISO rather than a mutable
`latest` URL. Older releases may predate signed manifests. Release-specific
objects are retained for at least 12 months and their paths are never reused.

## Manifest And Build Inputs

The signed release manifest records:

```text
release_tag
release_sha
release_path
iso_name
sha256
checksum_name
package_inventory_name
package_inventory_sha256
sbom_name
sbom_sha256
build_inputs_name
build_inputs_sha256
aur_manifest_name
aur_manifest_sha256
signing_fingerprint
builder_base_digest
built_at_utc
```

The build-input record adds the requested builder image, immutable base-image
digest, resulting builder image ID, Docker version, repository source commit,
build-tool versions, and exact AUR refs. The TSV and SPDX files record the
installed ISO package names, exact versions, and source repository
classification.

See [Security Policy](../SECURITY.md) for the signature-first verification
flow.

## Package Repository Publication

The release workflow publishes `veldmuis-core` and `veldmuis-extra` to:

```text
https://packages.veldmuislinux.org/
```

The package repository publication writes:

- `index.html`
- `veldmuis-package-repo.manifest.txt`
- Repository databases and signatures.
- Package files and detached package signatures.
- `veldmuis-aur-packages.manifest.txt` when AUR artifacts are present.

Veldmuis pacman configurations require both package and repository-database
signatures.

## Release Notes

Maintainer-authored release notes live under `development/release-notes/`, with
one optional file named for the release tag, such as:

```text
development/release-notes/2026.04.22.md
```

When present, the workflow prepends it to generated commit-list output.
Otherwise it generates a minimal release body. See
`development/release-notes/README.md` for the maintainer convention.

## Release Checks

Local source checks:

```sh
./development/check-release-policy.sh
```

Remote release checks require GitHub CLI authentication:

```sh
VELDMUIS_LATEST_ISO_URL=https://downloads.veldmuislinux.org/iso/latest.iso \
VELDMUIS_LATEST_MANIFEST_URL=https://downloads.veldmuislinux.org/iso/latest.manifest.txt \
VELDMUIS_LATEST_MANIFEST_SIGNATURE_URL=https://downloads.veldmuislinux.org/iso/latest.manifest.txt.sig \
  ./development/check-release-policy.sh --remote
```
