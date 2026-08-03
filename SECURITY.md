# Security Policy

This document describes the public trust, verification, and vulnerability-
reporting model for Veldmuis Linux.

## Official Sources

Use only these project-controlled sources for downloads, source, releases, and
support:

- Website: https://veldmuislinux.org/
- Source, issues, and releases: https://github.com/ruannnebornman/veldmuis
- Package repository: https://packages.veldmuislinux.org/
- ISO releases: https://downloads.veldmuislinux.org/iso/

Veldmuis does not currently have official outside affiliations, community
platforms, fundraising pages, or alternate download mirrors.

A Discord community is planned, and a Twitter/X account is being prepared. No
official invite or handle has been published yet. Until a channel is listed in
this document, treat similarly named accounts, download pages, mirrors, and
direct messages as unofficial. Do not provide signing keys, passwords, or
recovery material through them.

The project is maintained by Ruanne Bornman. The maintainer's personal site
(https://ruannebornman.com/) identifies the maintainer and links to this
repository, but it is not a download channel. Project trust is carried by the
signed release workflow described below, not by any individual's reputation.

## Current Signing Key

The current Veldmuis release signing key is packaged in
`packages/veldmuis-keyring`.

```text
UID:                    Veldmuis Linux Release <veldmuis@veldmuislinux.org>
Primary fingerprint:    022A 2A63 9A21 666F 1F48  BD5E BD3E AF48 5786 AAEF
Signing subkey:          E76D 738D 74AA 940D 429B  D9F5 BC27 E50C B16F 2302
Created:                 2026-03-21
Expires:                 2031-03-20
```

The public key is available from two official distribution paths:

- Repository source: `packages/veldmuis-keyring/veldmuis.gpg`
- Installed/live systems: `/usr/share/pacman/keyrings/veldmuis.gpg`

The packaged keyring also contains `veldmuis-trusted` and `veldmuis-revoked`.
Confirm the primary fingerprint above when obtaining the key for the first
time.

## What Is Signed

The release and package workflows sign:

- Veldmuis package files in `veldmuis-core` and `veldmuis-extra`.
- Pacman repository databases for both Veldmuis repositories.
- The release manifest that authenticates the ISO checksum, release commit,
  immutable artifact path, package inventory, SPDX SBOM, build inputs, and
  resolved AUR-input manifest.

The manifest has a detached OpenPGP signature. The ISO does not have a separate
detached signature; its SHA-256 digest is authenticated by the signed manifest.

## Verify The Current ISO

First obtain the public key from the source repository and confirm its
fingerprint:

```sh
curl -fL -o veldmuis.gpg \
  https://raw.githubusercontent.com/ruannnebornman/veldmuis/main/packages/veldmuis-keyring/veldmuis.gpg
gpg --show-keys --with-fingerprint veldmuis.gpg
```

Download and authenticate the current manifest before selecting the ISO:

```sh
curl -fL -o network.manifest.txt \
  https://downloads.veldmuislinux.org/iso/channels/network.manifest.txt
curl -fL -o network.manifest.txt.sig \
  https://downloads.veldmuislinux.org/iso/channels/network.manifest.txt.sig
gpgv --keyring ./veldmuis.gpg network.manifest.txt.sig network.manifest.txt
```

After a successful signature check, use the immutable release path named by the
manifest:

```sh
release_path="$(awk -F= '$1 == "release_path" { print $2; exit }' network.manifest.txt)"
iso_name="$(awk -F= '$1 == "iso_name" { print $2; exit }' network.manifest.txt)"
expected_sha256="$(awk -F= '$1 == "sha256" { print $2; exit }' network.manifest.txt)"
case "${release_path}/${iso_name}" in
  releases/*/veldmuis-*.iso) ;;
  *) echo 'Unsafe artifact path in manifest' >&2; exit 1 ;;
esac
curl -fL -o "${iso_name}" \
  "https://downloads.veldmuislinux.org/iso/${release_path}/${iso_name}"
actual_sha256="$(sha256sum "${iso_name}" | awk '{ print $1; exit }')"
test "${actual_sha256}" = "${expected_sha256}"
```

This flow treats the signed channel manifest as the publication marker. The
verified manifest directs the download to release-specific immutable objects.

## Verify A Historical Release

Releases produced by the current workflow retain the signed manifest, detached
signature, checksum, package inventory, SPDX SBOM, build inputs, and resolved
AUR-input manifest. Their release notes link to the immutable ISO on the
download origin. Older releases may predate signed release manifests.

For a historical release:

1. Confirm the release tag uses the documented date format.
2. Download the manifest and `.manifest.txt.sig` assets.
3. Verify the signature with the Veldmuis public key.
4. Confirm `release_tag=` matches the release and `release_sha=` matches the
   tagged commit.
5. If the release is still current, download the ISO from `release_path=` and
   verify it against `sha256=`.

Before a new installer release is published, the publication workflow removes
older release-specific objects. Historical tags, signed manifests, checksums,
and other authenticated metadata remain on the corresponding GitHub release.
Release-specific paths are never reused.

## Package Repository Trust

Installed systems use `veldmuis-release` for repository configuration and
`veldmuis-keyring` for pacman trust data. Veldmuis repositories require trusted
signatures on both packages and repository databases:

```ini
[veldmuis-core]
SigLevel = Required DatabaseRequired
Include = /etc/pacman.d/veldmuis-mirrorlist

[veldmuis-extra]
SigLevel = Required DatabaseRequired
Include = /etc/pacman.d/veldmuis-mirrorlist
```

The live ISO and Calamares bootstrap use the same Veldmuis-specific policy.
Arch repositories retain their upstream-compatible database-signature policy.
Pacman checks package and repository signatures automatically under this policy;
do not bypass it with `SigLevel = Never` or an untrusted replacement keyring.

## AUR-Derived Packages

The NVIDIA 580xx packages are built from configured AUR package bases,
validated as package artifacts, and then signed into the Veldmuis package
repository. The release build records the exact resolved refs, the AUR
`PKGBUILD` hashes, and downloaded source-file hashes in its AUR-input and
build-input manifests.

The AUR build stage does not receive the signing key. Signing happens later in
a network-disabled stage after artifact validation. See
[NVIDIA 580xx Package Flow](development/nvidia-580xx-package-flow.md) and
[NVIDIA 580xx Support](docs/nvidia.md).

## Key Operations

The current primary key is not replaced for routine package or image releases.
Normal signing uses its signing subkey. The helpers under
`development/key-rotation/` are limited to encrypted backup, verify/restore,
and signing-subkey export; they do not generate, delete, revoke, or replace
keys. See the [signing-key operations runbook](development/key-rotation/README.md).

## Report A Vulnerability

Submit sensitive reports through the repository's private vulnerability form:

```text
https://github.com/ruannnebornman/veldmuis/security/advisories/new
```

Do not put exploit details, signing material, non-public service information,
or malicious-package samples in a public issue. Public issues are suitable for
non-sensitive security improvements and already-public defects only.

Please include affected versions, impact, reproduction details, and a safe way
to validate the report. The project aims to acknowledge a private report as
soon as practical — within seven days when possible. Investigation and
remediation time depends on severity and maintainer availability; this is a
coordination target, not a commercial service-level guarantee. The reporter
will be told when public disclosure is appropriate.

There is currently no separately published project PGP key or alternate
encrypted reporting address. Use the private GitHub form rather than sending
sensitive material to an address or account found elsewhere.

For suspected signing-key compromise or a malicious package, the maintainer
will preserve evidence, stop affected publication paths, identify the last
known-good release and repository state, revoke or replace affected signing
material where necessary, publish a security notice through official sources,
and provide explicit recovery instructions before normal publication resumes.

## Current Limitations

- Arch repository inputs are not pinned to an Arch Linux Archive snapshot, so
  byte-for-byte rebuilds are not currently guaranteed.
- The NVIDIA 580xx path depends on AUR-derived package sources.
- Build-input manifests authenticate the recorded refs, source hashes, and build
  metadata; they do not constitute a source audit or a byte-for-byte
  reproducibility guarantee.
- Veldmuis is a small project with a narrow support scope, not a general-purpose
  commercial Linux distribution.
