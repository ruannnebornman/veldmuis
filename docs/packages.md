# Package Composition

Veldmuis uses pacman metapackages to define most of the install composition.
Many Veldmuis packages intentionally have empty `package()` bodies because their
dependency lists are the product: they describe what gets installed together.

The package build order is defined in:

```text
development/package-manifest.sh
```

## Repository Split

Veldmuis currently builds two package repositories:

- `veldmuis-core`
  Native Veldmuis packages and the Calamares package used by the installer.
- `veldmuis-extra`
  Optional NVIDIA 580xx support packages and AUR-derived NVIDIA artifacts.

Installed systems receive repository configuration from `veldmuis-release`.

## Default Install Target

The installer default target is:

```text
veldmuis-desktop
```

`veldmuis-desktop` currently depends on:

```text
veldmuis-common
veldmuis-boot
veldmuis-displaymanager
veldmuis-desktop-kde
veldmuis-multimedia
veldmuis-branding
```

## Base And Common Packages

`veldmuis-base` defines the minimal bootable/networked base:

```text
base
btrfs-progs
dosfstools
linux
linux-firmware
mkinitcpio
networkmanager
sudo
veldmuis-release
xfsprogs
```

`veldmuis-common` adds common CLI and user-facing basics:

```text
fuse2
bash-completion
nano
git
openssh
curl
wget
unzip
zip
htop
btop
noto-fonts
noto-fonts-emoji
```

`fuse2` provides the legacy `libfuse.so.2` runtime required by many AppImages.

## Boot Policy

`veldmuis-boot` defines the UEFI/systemd-boot policy. It depends on:

```text
systemd
efibootmgr
```

It also installs a pacman hook and helper that refresh Veldmuis systemd-boot
entries after kernel package transactions.

## Display Manager

`veldmuis-displaymanager` currently uses Plasma Login Manager:

```text
plasma-login-manager
polkit
veldmuis-branding
```

The install script disables legacy `greetd.service` and `sddm.service` units
and enables `plasmalogin.service`.

## KDE Desktop

`veldmuis-desktop-kde` defines the default KDE Plasma desktop and default GUI
applications.

Current highlights include:

- Plasma desktop and workspace packages.
- KDE settings, lock screen, display, network, Bluetooth, and power tools.
- Firefox.
- Dolphin, Ark, Kate, Gwenview, Okular, Spectacle, Filelight, Partition
  Manager, and Plasma System Monitor.
- KDE and Qt image/thumbnail support.
- Breeze and Breeze GTK integration.

Current non-defaults:

- Discover is not in the default KDE package set.
- Flatpak is not in the default KDE package set.
- Steam, Lutris, and Discord are optional through `veldmuis-gaming`.
- qBittorrent is optional through `veldmuis-downloads`.
- Syncthing is optional through `veldmuis-sync`.
- Yakuake and Spice guest tools are not in the default KDE package set.

## Multimedia

`veldmuis-multimedia` provides the default audio/video stack:

```text
pipewire
wireplumber
pipewire-pulse
plasma-pa
mpv
strawberry
```

It also installs the Veldmuis `mpv` configuration.

## Branding

`veldmuis-branding` owns Veldmuis visual defaults and KDE configuration assets,
including wallpaper, KDE defaults, wallet defaults, and the Plasma desktop
layout package.

## Optional Application Groups

Optional groups are installed only when selected in the installer or installed
manually later.

`veldmuis-gaming`:

```text
steam
lutris
discord
```

`veldmuis-downloads`:

```text
qbittorrent
```

`veldmuis-sync`:

```text
syncthing
```

`veldmuis-sync` also installs Syncthing user-service integration, a setup
helper, and a one-time editable Firefox bookmark for the local Syncthing UI.

`veldmuis-development`:

```text
code
github-cli
```

## Graphics Choices

Graphics package selection is handled by the Calamares bootstrap, not by the
default KDE metapackage alone.

Current choices:

- `all-open-source`
- `amd-open-source`
- `intel-open-source`
- `nvidia-open-source`
- `nvidia-580xx-dkms`

The NVIDIA 580xx choice installs `veldmuis-nvidia-legacy` from
`veldmuis-extra`. See [NVIDIA 580xx Support](nvidia.md).

## Infrastructure Packages

Installer, release, keyring, and repository infrastructure packages include:

- `calamares`
- `veldmuis-calamares-config`
- `veldmuis-keyring`
- `veldmuis-lsb-release`
- `veldmuis-mirrorlist`
- `veldmuis-release`

`veldmuis-release` owns `/etc/os-release`, `/etc/veldmuis-release`, and the
Veldmuis pacman repository include file.

`veldmuis-keyring` owns the Veldmuis pacman keyring files.

`veldmuis-mirrorlist` owns the Veldmuis mirrorlist and Arch mirror refresh
tooling.

## Installer Package Flow

The Calamares bootstrap starts with:

```text
veldmuis-desktop
```

It then adds:

- CPU microcode for detected AMD or Intel CPUs.
- The selected graphics package set.
- Optional gaming, download, sync, and development metapackages.

Current ISO behavior: Veldmuis repositories are embedded in the ISO, while
Arch packages are still resolved from Arch mirrors during installation.
