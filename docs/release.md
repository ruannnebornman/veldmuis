# Release Process

Veldmuis releases are date-tagged builds from `main`. The rolling package
repository has its own workflow. The installer release workflow publishes the
network installer and then calls the reusable offline-installer workflow with
the same tag, commit, and Arch snapshot. Installer artifacts use immutable
versioned paths while published; small channel documents select the currently
promoted build without storing a second copy of either ISO.

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

The `Installer Release` workflow is defined in
`.github/workflows/release.yml`. It runs as a monthly schedule or by manual
dispatch with an explicit daily tag. After successful network publication,
every run calls the reusable offline installer workflow in
`.github/workflows/offline-iso-size.yml` with the same release tag, exact
source commit, and Arch Linux Archive snapshot resolved before the network
build starts. The offline workflow cannot be dispatched independently. Manual
release dispatch is accepted only from `main`.

Manual release tags must be the next valid tag for that UTC date. For example,
if `2026.04.22` exists, the next release on that date must be
`2026.04.22.2`.

## Immutability Policy

Release tags and release-specific object paths are immutable while published.
Do not move, overwrite, or reuse them. Before publishing a new network
installer, the workflow removes every older release prefix while protecting
the new tag. Git tags, GitHub releases, and their authenticated metadata remain
the historical record. If a published release is wrong, fix the source and
publish the next valid release tag.

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
9. Removes all earlier installer release prefixes while protecting the new tag.
10. Uploads and verifies immutable network-installer release objects.
11. Promotes the small network channel document and signed channel manifest.
12. Removes legacy mutable ISO aliases after the channel is usable.
13. Creates the GitHub release and attaches the authenticated metadata.
14. Downloads the published manifest and signature and verifies them with the
    packaged public key.
15. Calls the offline installer workflow with the frozen tag, commit, and
    snapshot after network publication succeeds.

Reusable workflow actions are pinned to complete commit SHAs. Workflow token
permissions are read-only by default and elevated only for the publication job.
Signing material is passed only to network-disabled signing stages, while
object-storage credentials are passed only to publisher steps. Release jobs do
not receive bucket-administration credentials or modify bucket configuration.

The reusable `Offline Installer Release` workflow builds and validates a full
offline installer from the selected snapshot, reports its exact size, uploads
immutable release objects, and promotes the offline channel. It verifies and
checks out the exact tagged commit supplied by the network release workflow.
It does not publish the rolling package repository, create a GitHub tag, or
create a GitHub release.

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

The two `CF_R2_*` credential pairs use Object Read & Write access scoped to
their respective buckets. Do not grant the release environment administrative
bucket permissions.

## Cloudflare R2 Bucket Configuration

The website reads the installer channel documents from the download domain,
so the release bucket must allow browser reads from the website origins. CORS
is bucket infrastructure, not part of an individual release. Configure it once
in the Cloudflare dashboard before the first channel publication.

Open R2 Object Storage, select `veldmuis-releases`, open **Settings**, and add
this policy under **CORS Policy** using the JSON editor:

```json
[
  {
    "AllowedOrigins": [
      "https://veldmuislinux.org",
      "https://www.veldmuislinux.org"
    ],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["Content-Length", "ETag"],
    "MaxAgeSeconds": 3600
  }
]
```

The installer workflows deliberately cannot modify bucket configuration with
their object-scoped publication credentials. If the custom domain already has
cached objects when the policy changes, purge that hostname's cache before
testing browser access.

## Published Artifacts

Each release has an immutable directory:

```text
https://downloads.veldmuislinux.org/iso/releases/TAG/
```

It contains:

```text
veldmuis-TAG-network-x86_64.iso
veldmuis-TAG-network-x86_64.iso.sha256
veldmuis-TAG-network-x86_64.manifest.txt
veldmuis-TAG-network-x86_64.manifest.txt.sig
veldmuis-TAG-network-x86_64.packages.tsv
veldmuis-TAG-network-x86_64.spdx
veldmuis-TAG-network-x86_64.build-inputs.txt
veldmuis-TAG-network-x86_64.aur-packages.manifest.txt

veldmuis-TAG-offline-x86_64.iso
veldmuis-TAG-offline-x86_64.iso.sha256
veldmuis-TAG-offline-x86_64.manifest.txt
veldmuis-TAG-offline-x86_64.manifest.txt.sig
veldmuis-TAG-offline-x86_64.offline-packages.tsv
```

Small channel documents identify the promoted installer releases:

```text
https://downloads.veldmuislinux.org/iso/channels/network.json
https://downloads.veldmuislinux.org/iso/channels/network.manifest.txt
https://downloads.veldmuislinux.org/iso/channels/network.manifest.txt.sig
https://downloads.veldmuislinux.org/iso/channels/offline.json
https://downloads.veldmuislinux.org/iso/channels/offline.manifest.txt
https://downloads.veldmuislinux.org/iso/channels/offline.manifest.txt.sig
```

Each JSON channel document contains the immutable ISO, checksum, signed
manifest, and detached-signature URLs. The manifest and signature are also
copied to small channel-specific paths for command-line verification. The JSON
document is promoted last and no mutable path contains ISO bytes.

The currently published release retains the checksum, signed manifest and
signature, package inventory, SPDX SBOM, build inputs, and exact AUR-input
manifest. Release notes retain authenticated metadata for historical releases,
but their object-storage ISO links expire when the next release prunes the old
prefix. Release-specific paths are never reused.

## Manifest And Build Inputs

The signed release manifest records:

```text
release_tag
release_sha
installer
release_path
iso_name
sha256
iso_bytes
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

Full offline candidate manifests additionally record:

```text
offline_manifest_name
offline_manifest_sha256
offline_repo_bytes
offline_package_count
arch_repository_snapshot
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
VELDMUIS_NETWORK_CHANNEL_URL=https://downloads.veldmuislinux.org/iso/channels/network.json \
VELDMUIS_NETWORK_MANIFEST_URL=https://downloads.veldmuislinux.org/iso/channels/network.manifest.txt \
VELDMUIS_NETWORK_MANIFEST_SIGNATURE_URL=https://downloads.veldmuislinux.org/iso/channels/network.manifest.txt.sig \
  ./development/check-release-policy.sh --remote
```
