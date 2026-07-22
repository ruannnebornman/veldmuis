# Architecture

Veldmuis is organized around four build outputs:

- Native Veldmuis packages from `packages/`.
- Signed pacman repositories under `repos/`.
- A live/install ISO from `archiso/veldmuis/`.
- Immutable ISO releases with signed metadata, package inventories, and SPDX
  SBOMs.

## Package Layer

The package list is defined in `development/package-manifest.sh`.

`veldmuis-core` contains the native Veldmuis packages and the Calamares package
used by the installer. `veldmuis-extra` contains the NVIDIA legacy metapackage
plus the NVIDIA 580xx artifacts built from the configured AUR package bases.

Most desktop policy packages are metapackages. They intentionally carry little
or no payload; their dependency lists define the install composition. Packages
with real payloads include release files, keyring files, mirror tooling, boot
hooks, installer configuration, multimedia defaults, Syncthing integration, and
branding assets.

## Repository Layer

`development/build-local-repo.sh` copies the latest built packages into:

```text
repos/
  veldmuis-core/os/x86_64/
  veldmuis-extra/os/x86_64/
  veldmuis-offline/os/x86_64/
  manifests/
```

`veldmuis-offline` is created only for full offline ISO candidates. It contains
unchanged official Arch package files and upstream signatures resolved from one
dated Arch Linux Archive snapshot. Its repository database is signed with the
Veldmuis release key. It is an ISO input, not part of the hosted Veldmuis
package repository.

Package files and repository databases are signed with the Veldmuis release
signing key. The public package repository is published by
`development/publish-r2-package-repo.sh` and exposed through:

```text
https://packages.veldmuislinux.org/
```

Installed systems receive Veldmuis repository configuration from the
`veldmuis-release` package. The Veldmuis repository sections require trusted
signatures on both packages and repository databases.

## ISO Layer

`development/build-archiso.sh` copies the current local `repos/` tree into the
archiso profile before running `mkarchiso`. The live image therefore includes
the signed Veldmuis repositories under:

```text
/opt/veldmuis/repo/
```

The ISO profile is UEFI-only and uses systemd-boot loader entries. The live
session exposes Calamares as the graphical installer.

Offline candidates include `/etc/veldmuis/offline-install` in the live root.
That marker selects a local-only Calamares pacman configuration. Builds without
the marker retain the current network-installer behavior.

## Installer Layer

Calamares configuration lives under `packages/veldmuis-calamares-config/`.

During installation, `veldmuis-calamares-bootstrap.sh` prepares a temporary
pacman configuration, initializes Arch and Veldmuis keyrings, and installs the
selected package stack into the target root with `pacstrap`.

The default target package is:

```text
veldmuis-desktop
```

Installer choices can add graphics-specific packages and optional application
groups such as gaming, downloads, sync, and development.

The shared selection definition is
`packages/veldmuis-calamares-config/installer-package-sets.sh`. Both Calamares
and the offline repository builder consume it, and the offline validator checks
every individual and maximal selection with container networking disabled.

## Release Layer

The release workflow resolves an exact `main` commit, builds packages and the
ISO in isolated Arch containers, and creates authenticated release metadata in
a network-disabled signing stage. It publishes the package repository and
release-specific ISO objects before advancing the `latest` aliases.

GitHub releases keep release notes, the signed manifest and signature,
checksum, package inventory, SPDX SBOM, build inputs, and resolved AUR inputs.
The current convenience path is:

```text
https://downloads.veldmuislinux.org/iso/latest.iso
```

The signed `latest.manifest.txt` points users to immutable artifacts under
`iso/releases/TAG/`. Release-specific paths are never reused.

See [Release Process](release.md) for the full public release policy.
