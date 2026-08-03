# Veldmuis Linux

Shaped around the African veld at sunset: a small Arch-based KDE Plasma desktop
whose packages, installer, and release workflow are built in the open and can be
followed end to end from this repository.

Veldmuis is an Arch-based KDE Plasma distribution project focused on transparent
release engineering: package composition, signed pacman repositories, keyring
packaging, archiso image construction, Calamares installer integration,
systemd-boot installation, and automated GitHub releases.

The project is intentionally narrow. It is public so the packaging, installer
configuration, release workflow, and known limitations can be inspected from one
repository.

## Why Veldmuis

The veld at sunset is an open place: dry grass, a long horizon, and light that
does not hide anything. Veldmuis is built in that spirit. It is a small desktop
distribution that keeps its work visible — every package is defined in
`packages/`, every installer step is documented in `docs/`, every release is
signed and verifiable from `SECURITY.md`.

That means Veldmuis makes no promises it cannot keep:

- It is a desktop for people who like Arch and want to see everything a distro
  does before they run it.
- It does not pretend to be a mass-market distribution, and it does not
  accumulate feature groups by default. The default install stays close to KDE
  Plasma, and optional groups (gaming, downloads, sync, development, NVIDIA)
  are opt-in.
- Release metadata records signed repositories, signed release manifests, and
  immutable ISO paths. Verify those records before using an official download.

Veldmuis is for people who want to inspect the whole path from package definition
to installed desktop.

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

The current default install target is a KDE Plasma desktop with Veldmuis
release, keyring, boot, display-manager, multimedia, and branding packages.

The installer supports open-source graphics choices and an optional NVIDIA
580xx DKMS path. Optional application groups currently include gaming, download,
sync, and development packages. The default KDE package set does not currently
include Discover, Flatpak, Steam, Lutris, Discord, qBittorrent, or Syncthing;
those are either absent from the default install or exposed through optional
metapackages.

The current ISO embeds the signed Veldmuis package repositories used by the
installer. Arch packages are still resolved from Arch mirrors during
installation, so the public image remains a network installer. A full offline
candidate build and size-measurement path is documented in
[Building Packages And ISOs](docs/building.md); it is not yet the public release
path.

## Official Links

- Website: https://veldmuislinux.org/
- Source, issues, and releases: https://github.com/ruannnebornman/veldmuis
- Issue tracker: https://github.com/ruannnebornman/veldmuis/issues
- Package repository: https://packages.veldmuislinux.org/
- ISO releases: https://downloads.veldmuislinux.org/iso/

Official Veldmuis communication currently happens through the website and
GitHub repository above. Veldmuis does not currently have official outside
affiliations, community platforms, or fundraising pages. If that changes, it
will be announced through those official links. A Discord community is planned,
and a Twitter/X account is being prepared, but neither has an official invite
or handle published yet.

Treat similarly named websites, accounts, mirrors, download pages, and direct
messages as unofficial unless they are listed here or in [SECURITY.md](SECURITY.md).
Veldmuis will not ask for signing keys, passwords, or recovery material through
an unlisted channel.

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

Current installer channels:

- Network installer: https://downloads.veldmuislinux.org/iso/channels/network.json
- Offline installer: https://downloads.veldmuislinux.org/iso/channels/offline.json
- Network signed manifest: https://downloads.veldmuislinux.org/iso/channels/network.manifest.txt
- Network manifest signature: https://downloads.veldmuislinux.org/iso/channels/network.manifest.txt.sig

The small channel documents point to immutable release-specific ISOs and avoid
storing duplicate `latest` ISO objects. Publishing a new release prunes older
installer objects, while historical GitHub releases retain authenticated
metadata for verification.

Before installing, verify the manifest signature and then check the ISO against
the authenticated checksum.
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

## FAQ

**Is Veldmuis a "rat"?**
Veldmuis is Afrikaans for "field mouse" — a small, quiet animal of the veld.
It is not a remote access trojan. The repository and release metadata are
public, the ISO and repositories are signed, and every release can be checked
using [SECURITY.md](SECURITY.md).

**Why another Arch distribution?**
Because a distro can be a small thing, honestly built. Veldmuis exists to show
that a one-person project can ship signed packages, a verifiable installer, and
a documented release pipeline — and to give people a desktop they can inspect
from the first commit. If you want a larger community around your Arch desktop,
EndeavourOS and CachyOS do that well; Veldmuis is not trying to outrun them.

**Why KDE Plasma?**
KDE Plasma is the default desktop: mature, configurable, and comfortable in the
evening light. The Veldmuis branding package carries a dusk-and-ember color
scheme, and optional groups add gaming, downloads, sync, and development tools
without cluttering the default install.

**Why is it a network installer?**
The public image resolves Arch packages from Arch mirrors during installation,
so the download stays small and current. An offline candidate build is
documented in [Building Packages And ISOs](docs/building.md) but is not yet the
public release path.

**Why is Secure Boot not supported?**
The install path targets UEFI with systemd-boot and Secure Boot disabled. This
is a documented limitation, not an oversight; see
[Installing Veldmuis](docs/installing.md).

**Is this a serious project?**
It is a small project with a defined support scope. Releases are signed and
verifiable, the security model is described in [SECURITY.md](SECURITY.md), and
known limitations are listed in [SUPPORT.md](SUPPORT.md).

## Maintainer

Veldmuis is maintained by **Ruanne Bornman**:

- Personal site: https://ruannebornman.com/
- GitHub: https://github.com/ruannnebornman
- The project's voice and look are its own — shaped around the African veld at
  sunset — not an extension of any one personality.

The Veldmuis signing key is the project's key, and the security model does not
depend on the maintainer's reputation alone. See [SECURITY.md](SECURITY.md) for
the full verification flow.

## License

Repository code and documentation are licensed under the MIT License unless a
file states otherwise. Upstream packages, Arch packages, AUR-derived packages,
and proprietary driver components keep their own licenses.
