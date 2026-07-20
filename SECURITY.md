# Security Policy

This document describes the current public trust and verification model for
Veldmuis Linux.

## Official Sources

Use only these project-controlled sources for downloads, source, releases, and
support:

- Website: https://veldmuislinux.org/
- Source, issues, and releases: https://github.com/ruannnebornman/veldmuis
- Package repository: https://packages.veldmuislinux.org/
- Current ISO: https://downloads.veldmuislinux.org/iso/latest.iso

Veldmuis does not currently have official outside affiliations, community
platforms, fundraising pages, or alternate download mirrors.

## Current Signing Key

The current Veldmuis package signing key is packaged in
`packages/veldmuis-keyring`.

```text
UID:                    Veldmuis Linux Release <veldmuis@veldmuislinux.org>
Primary fingerprint:    022A 2A63 9A21 666F 1F48  BD5E BD3E AF48 5786 AAEF
Signing subkey:          E76D 738D 74AA 940D 429B  D9F5 BC27 E50C B16F 2302
Created:                 2026-03-21
Expires:                 2031-03-20
```

The packaged keyring files are:

```text
packages/veldmuis-keyring/veldmuis.gpg
packages/veldmuis-keyring/veldmuis-trusted
packages/veldmuis-keyring/veldmuis-revoked
```

## What Is Signed

The current release and package workflows sign:

- Veldmuis package files in `veldmuis-core`.
- Veldmuis package files and NVIDIA 580xx artifacts in `veldmuis-extra`.
- Pacman repository databases for `veldmuis-core` and `veldmuis-extra`.

The current release workflow publishes:

- `latest.iso`
- `latest.iso.sha256`
- `latest.manifest.txt`
- GitHub release checksum and manifest assets

The ISO itself does not currently have a detached GPG signature. Verify the ISO
with the published SHA-256 checksum and manifest.

## Verify The Current ISO

Download the current ISO, checksum, and manifest:

```sh
curl -fL -o veldmuis.iso https://downloads.veldmuislinux.org/iso/latest.iso
curl -fL -o latest.iso.sha256 https://downloads.veldmuislinux.org/iso/latest.iso.sha256
curl -fL -o latest.manifest.txt https://downloads.veldmuislinux.org/iso/latest.manifest.txt
```

Compare the checksum:

```sh
expected_sha256="$(awk '{ print $1; exit }' latest.iso.sha256)"
actual_sha256="$(sha256sum veldmuis.iso | awk '{ print $1; exit }')"
test "${actual_sha256}" = "${expected_sha256}"
```

Compare the manifest:

```sh
grep '^release_tag=' latest.manifest.txt
grep '^release_sha=' latest.manifest.txt
grep '^iso_name=' latest.manifest.txt
grep '^sha256=' latest.manifest.txt
grep '^signing_fingerprint=' latest.manifest.txt
```

The `sha256=` value in `latest.manifest.txt` should match the checksum above.
The `signing_fingerprint=` value should match the current signing fingerprint
documented in this file, unless the release notes or keyring package document a
key rotation.

## Verify A GitHub Release

GitHub releases keep checksum and manifest assets. Veldmuis does not archive a
release-specific ISO download for each historical release; the public ISO path
always points to the current ISO.

For a release page:

1. Confirm the release tag uses the documented date format.
2. Download the release manifest asset.
3. Confirm `release_tag=` matches the GitHub release tag.
4. Confirm `release_sha=` matches the tagged commit.
5. Confirm the release checksum asset matches the ISO checksum recorded in the
   manifest.

## Package Repository Trust

Installed systems use the `veldmuis-release` package for repository
configuration and the `veldmuis-keyring` package for pacman trust data.

The repository configuration is:

```ini
[veldmuis-core]
SigLevel = Required DatabaseOptional
Include = /etc/pacman.d/veldmuis-mirrorlist

[veldmuis-extra]
SigLevel = Required DatabaseOptional
Include = /etc/pacman.d/veldmuis-mirrorlist
```

Pacman verifies package signatures during normal package operations. The
Calamares bootstrap also initializes the target keyring with Arch and Veldmuis
keys before installing the target system.

## AUR-Derived Packages

The NVIDIA 580xx packages are built from configured AUR package bases, validated
as package artifacts, and then signed into the Veldmuis package repository.

Current AUR package bases:

- `nvidia-580xx-utils`
- `lib32-nvidia-580xx-utils`
- `nvidia-580xx-settings`

The AUR build stage does not receive the Veldmuis signing key. Signing happens
later in a network-disabled signing stage after artifact validation. See
[NVIDIA 580xx Package Flow](development/nvidia-580xx-package-flow.md) and
[NVIDIA 580xx Support](docs/nvidia.md).

## Key Rotation

The current primary key is not replaced for routine package or image releases.
Normal signing uses its signing subkey. The helpers under
`development/key-rotation/` are limited to encrypted backup, verify/restore,
and signing-subkey export; they do not generate, delete, revoke, or replace
keys.

A routine signing-subkey rotation keeps the primary fingerprint and distributes
the new public subkey before repository signatures switch to it. Replacing the
primary key is a separate staged operation: existing systems must first receive
a transition keyring authenticated by the old trusted key, then be tested
through the full update path before the repository changes signing authority.

Users should treat any key change as security-sensitive. A future rotation
must be visible in the keyring package, release notes, and this file. See the
[signing-key operations runbook](development/key-rotation/README.md).

## Report A Vulnerability

Open a GitHub issue if the report can be public:

```text
https://github.com/ruannnebornman/veldmuis/issues
```

If the issue involves an exploitable vulnerability, signing-key exposure, a
malicious package, or a private disclosure concern, do not publish exploit
details in the issue body. Open a minimal issue asking for a private contact
path, or contact the maintainer through the official website if a private
contact path is available there.

## Current Limitations

- The ISO has a SHA-256 checksum and manifest but no detached GPG signature.
- Historical GitHub releases do not retain release-specific ISO files.
- The NVIDIA 580xx path depends on AUR-derived package sources.
- Veldmuis is a small project with a narrow support scope, not a general-purpose
  commercial Linux distribution.
