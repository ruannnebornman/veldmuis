# Release Process

Veldmuis releases are date-tagged builds from `main`. The release workflow
builds packages, publishes the package repository, builds the ISO, publishes
the current ISO files, and creates a GitHub release.

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

The release workflow is defined in `.github/workflows/release.yml`.

It can run in two ways:

- Scheduled monthly release on the first day of each month.
- Manual workflow dispatch with an explicit daily release tag.

Manual release tags must be the next valid tag for that UTC date. For example,
if `2026.04.22` exists, the next release on that date must be
`2026.04.22.2`.

## Immutability Policy

Release tags are treated as immutable.

Do not move, delete, or reuse a published release tag. If a published release is
wrong, fix the source and publish the next valid release tag.

The workflow rejects a release if:

- The tag format is unsupported.
- A same-day manual release sequence is skipped.
- The tag already exists.
- A GitHub release already exists for the tag.

## Current Workflow Shape

At a high level, the workflow:

1. Checks repository release policy.
2. Resolves the release tag.
3. Creates an annotated release tag from `origin/main`.
4. Checks out the release tag.
5. Checks repository hygiene.
6. Validates required release secrets and environment variables.
7. Builds Veldmuis packages, AUR-derived NVIDIA artifacts, signed pacman
   repositories, and the ISO in isolated Arch containers.
8. Publishes the package repository.
9. Updates the known-good NVIDIA package cache.
10. Generates the ISO SHA-256 checksum and manifest.
11. Uploads the current ISO, checksum, and manifest to object storage.
12. Creates the GitHub release and uploads checksum and manifest assets.
13. Verifies published release policy.

Current limitation: the workflow creates the release tag before the package and
ISO build completes. If the build fails, the tag is consumed and the correction
must use the next valid tag rather than reusing the failed tag.

## Published Artifacts

The public ISO path always points to the current ISO:

```text
https://downloads.veldmuislinux.org/iso/latest.iso
https://downloads.veldmuislinux.org/iso/latest.iso.sha256
https://downloads.veldmuislinux.org/iso/latest.manifest.txt
```

Historical GitHub releases retain:

- Human-authored and generated release notes.
- A checksum asset.
- A manifest asset.
- The release tag and tagged commit.

Historical GitHub releases do not retain a release-specific ISO download. This
avoids a historical release page linking to a mutable `latest.iso` object.

## Manifest Fields

The release manifest records:

```text
release_tag
release_sha
iso_name
sha256
signing_fingerprint
built_at_utc
```

Use the manifest to connect a GitHub release, tagged commit, checksum, and
signing fingerprint. See [Security Policy](../SECURITY.md) for verification
commands.

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

The package repository manifest records the source commit and repository
metadata used by package-refresh checks.

## Release Notes

Maintainer-authored release notes live under:

```text
development/release-notes/
```

One file may be added per release tag, with the file name matching the tag:

```text
development/release-notes/2026.04.22.md
```

When the file exists, the workflow prepends it to generated commit-list output.
When the file does not exist, the workflow generates a minimal release body.

For meaningful releases, prefer a human-authored note with:

- User-visible highlights.
- Known issues or upgrade notes.
- A clear change summary grouped by area.
- No empty changelog sections.
- No outdated comparison labels or retired release terminology.

See `development/release-notes/README.md` for the maintainer convention.

## Release Checks

Local source checks:

```sh
./development/check-release-policy.sh
```

Remote release checks require GitHub CLI authentication:

```sh
VELDMUIS_LATEST_ISO_URL=https://downloads.veldmuislinux.org/iso/latest.iso \
  ./development/check-release-policy.sh --remote
```
