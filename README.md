# Veldmuis Linux

Veldmuis Linux is a small Arch-based KDE Plasma distribution project focused on
transparent release engineering: package composition, signed pacman
repositories, keyring packaging, archiso image construction, Calamares
installer integration, systemd-boot installation, and automated GitHub
releases.

The project is intentionally narrow. It is public so the packaging, installer
configuration, release workflow, and known limitations can be inspected from
one repository.

## What This Is

- An Arch-based x86_64 KDE Plasma install image.
- A Veldmuis package set built from the `packages/` tree.
- Signed `veldmuis-core` and `veldmuis-extra` pacman repositories.
- A Calamares installer profile for installing the Veldmuis desktop stack.
- A UEFI and systemd-boot install path.
- Release automation for building packages, publishing the package repository,
  building an ISO, and creating GitHub releases.

## What This Is Not

- A general replacement for Arch Linux, EndeavourOS, Manjaro, CachyOS, Garuda,
  or `archinstall`.
- A mass-market community distribution.
- A BIOS or legacy-boot target.
- A promise that every hardware, graphics, or update path is supported.
- An official Arch Linux project or an Arch Linux affiliate.

## Current Scope

Veldmuis is best read as a public Linux distribution engineering project. The
current default install target is a KDE Plasma desktop with Veldmuis release,
keyring, boot, display-manager, multimedia, and branding packages.

The installer supports open-source graphics choices and an optional NVIDIA
580xx DKMS path. Optional application groups currently include gaming, download,
sync, and development packages. The default KDE package set does not currently
include Discover, Flatpak, Steam, Lutris, Discord, qBittorrent, or Syncthing;
those are either absent from the default install or exposed through optional
metapackages.

The current ISO embeds the signed Veldmuis package repositories used by the
installer. Arch packages are still resolved from Arch mirrors during
installation, so the image should be treated as a network installer unless a
future offline-install path is documented.

## Official Links

- Website: https://veldmuislinux.org/
- Source, issues, and releases: https://github.com/ruannnebornman/veldmuis
- Issue tracker: https://github.com/ruannnebornman/veldmuis/issues
- Package repository: https://packages.veldmuislinux.org/

Official Veldmuis communication currently happens through the website and
GitHub repository above. Veldmuis does not currently have official outside
affiliations, community platforms, or fundraising pages. If that changes, it
will be announced through those official links.

## Before Installing

The current supported install target requires:

- An x86_64 computer with UEFI firmware.
- At least 2 GiB of RAM and 12 GiB of available storage.
- A working internet connection throughout installation.
- Secure Boot disabled.
- A backup of data that could be affected by partitioning.

BIOS and legacy boot are not supported. The listed RAM and storage values are
installer minimums, not recommended capacity for normal desktop use.

Read [Installing Veldmuis](docs/installing.md) before writing the ISO or
changing disk partitions.

## Download And Verify

Current public ISO files:

- ISO: https://downloads.veldmuislinux.org/iso/latest.iso
- SHA-256 checksum: https://downloads.veldmuislinux.org/iso/latest.iso.sha256
- Manifest: https://downloads.veldmuislinux.org/iso/latest.manifest.txt

The public ISO path is latest-only and always points to the current image.
Historical GitHub releases retain release notes, checksum assets, manifest
assets, tags, and commit metadata, but not release-specific ISO downloads.

Before installing, check the ISO against the published checksum and manifest.
See [Security and verification](SECURITY.md) for the full verification flow and
current signing-key details.

## Documentation

### Install And Use

- [Installing Veldmuis](docs/installing.md)
- [Updating Veldmuis](docs/updating.md)
- [Package composition](docs/packages.md)
- [NVIDIA 580xx support](docs/nvidia.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Support scope](SUPPORT.md)
- [Security and verification](SECURITY.md)

### Understand And Maintain

- [Documentation index](docs/index.md)
- [Architecture](docs/architecture.md)
- [Building packages and ISOs](docs/building.md)
- [Release process](docs/release.md)
- [Contributing and issue triage](CONTRIBUTING.md)

## Repository Layout

- `archiso/veldmuis/`
  Archiso profile used to build the live/install image.
- `development/`
  Helper scripts for local package, repository, ISO, VM, USB, key, and
  publishing workflows.
- `development/release-notes/`
  Maintainer-authored release notes that are prepended to generated GitHub
  release notes.
- `docs/`
  Project documentation beyond the README.
- `packages/`
  Package definitions for the Veldmuis stack, installer integration, keyring,
  release files, and optional package groups.
- `repos/`
  Local pacman repository output generated during development and ignored from
  Git.

## Core Package Groups

- `veldmuis-base`
- `veldmuis-common`
- `veldmuis-boot`
- `veldmuis-displaymanager`
- `veldmuis-desktop-kde`
- `veldmuis-multimedia`
- `veldmuis-branding`
- `veldmuis-desktop`

Optional package groups include:

- `veldmuis-development`
- `veldmuis-gaming`
- `veldmuis-downloads`
- `veldmuis-sync`
- `veldmuis-nvidia-legacy`

Infrastructure and installer packages include:

- `calamares`
- `veldmuis-calamares-config`
- `veldmuis-keyring`
- `veldmuis-lsb-release`
- `veldmuis-mirrorlist`
- `veldmuis-release`

## License

Repository code and documentation are licensed under the MIT License unless a
file states otherwise. Upstream packages, Arch packages, AUR-derived packages,
and proprietary driver components keep their own licenses.
