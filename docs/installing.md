# Installing Veldmuis

This guide covers the supported path for installing the current Veldmuis ISO
on an x86_64 system.

Veldmuis is a small Arch-based distribution project with a narrow support
scope. Read the requirements and limitations below, verify the ISO, and back up
important data before changing disk partitions.

## Requirements

- An x86_64 computer.
- UEFI firmware. BIOS and legacy boot are not supported.
- At least 2 GiB of RAM and 12 GiB of available storage. These are installer
  minimums; normal desktop use needs additional capacity.
- A working internet connection throughout installation. The ISO contains the
  Veldmuis repositories, but downloads Arch packages from Arch mirrors.
- A USB drive or other bootable medium large enough for the ISO.
- A backup of any data that must survive repartitioning.

Secure Boot is not part of the current supported target. Disable Secure Boot in
the system firmware before booting the installer.

## 1. Download And Verify The ISO

Download the current ISO, checksum, and manifest:

```sh
curl -fL -o veldmuis.iso https://downloads.veldmuislinux.org/iso/latest.iso
curl -fL -o latest.iso.sha256 https://downloads.veldmuislinux.org/iso/latest.iso.sha256
curl -fL -o latest.manifest.txt https://downloads.veldmuislinux.org/iso/latest.manifest.txt
```

Verify the checksum:

```sh
expected_sha256="$(awk '{ print $1; exit }' latest.iso.sha256)"
actual_sha256="$(sha256sum veldmuis.iso | awk '{ print $1; exit }')"
test "${actual_sha256}" = "${expected_sha256}"
```

A successful `test` command produces no output and exits with status zero.
Follow [Security and verification](../SECURITY.md) to inspect the manifest and
current signing-key details before installing.

## 2. Create The Bootable Medium

A graphical ISO writer such as KDE ISO Image Writer or Rufus can write the ISO
to a USB drive.

On Linux, identify the whole USB device carefully:

```sh
lsblk --paths --output NAME,SIZE,TYPE,MOUNTPOINTS,MODEL
```

Unmount any mounted partitions from that device, then write the ISO:

```sh
sudo dd if=veldmuis.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with the whole USB device, not a partition such as
`/dev/sdX1`. This command overwrites the selected device. Confirm the device
path before running it.

## 3. Boot The Live Environment

1. Reboot and open the firmware boot menu.
2. Select the UEFI entry for the installation medium.
3. Start the normal Veldmuis live entry.

If the live session does not reach a graphical desktop, reboot and use the
safe-graphics entry. It starts the live system with:

```text
nomodeset nouveau.modeset=0
```

Safe graphics is a recovery path for the live environment, not a permanent
installed-system configuration.

## 4. Connect To The Network

Connect to a wired or wireless network in the live session before starting the
installer. Confirm that web pages or Arch mirrors are reachable.

The installer ranks Arch mirrors and downloads Arch packages while building the
target system. Installation cannot complete as an offline operation.

## 5. Run The Installer

Launch the Calamares installer from the live desktop. It guides you through:

1. Locale and keyboard settings.
2. Disk partitioning.
3. Graphics selection.
4. Optional application groups.
5. User and password creation.
6. A final summary before installation begins.

Review the summary carefully. The installer disables cancellation while it is
writing the target system.

### Partitioning

The default filesystem is ext4. The installer also exposes btrfs and XFS, LUKS2
encryption, LVM, and several swap choices.

For UEFI installations, the EFI system partition is mounted at `/boot`. The
configured minimum EFI partition size is 512 MiB and the recommended size is
1024 MiB.

An erase-disk choice destroys the existing contents of the selected disk.
Manual partitioning can preserve existing partitions, but it requires a clear
understanding of mount points and the EFI system partition.

Dual-boot partitioning and integration with another operating system are
advanced configurations and are not part of the current support promise.
Back up the other operating system and its recovery keys before attempting
manual partitioning.

### Graphics

Choose the option that matches the target hardware:

| Installer choice | Intended stack |
| --- | --- |
| All open-source | Broad AMD, Intel, Nouveau, and VM support; the default |
| AMD / ATI open-source | Mesa and the AMD Vulkan stack |
| Intel open-source | Mesa and the Intel media and Vulkan stack |
| NVIDIA open-source | Mesa and Nouveau |
| NVIDIA 580xx DKMS | Veldmuis-packaged proprietary 580xx DKMS driver |

The NVIDIA 580xx path is optional, depends on DKMS and matching kernel headers,
and has a higher update risk on a rolling Arch base. Read
[NVIDIA 580xx support](nvidia.md) before selecting it.

### Optional Applications

The extras page can add these metapackages:

| Selection | Package group | Applications or integration |
| --- | --- | --- |
| Gaming | `veldmuis-gaming` | Steam, Lutris, and Discord |
| Downloads | `veldmuis-downloads` | qBittorrent |
| Sync | `veldmuis-sync` | Syncthing and Veldmuis integration |
| Development | `veldmuis-development` | Visual Studio Code and GitHub CLI |

These groups can also be installed later. They are not required for the base
desktop.

## 6. Finish And Reboot

Wait for Calamares to report that installation has completed. Close the
installer or select its reboot option, remove the installation medium when
prompted, and boot the installed system.

After the first login, perform a full system update:

```sh
sudo pacman -Syu
```

Veldmuis is rolling release. A newer dated ISO does not normally require an
existing installation to be reinstalled. See [Updating Veldmuis](updating.md)
for the normal update policy.

## If Installation Fails

Installer logs are written to:

```text
/tmp/veldmuis-calamares-debug.log
/tmp/veldmuis-calamares-bootstrap.log
```

Keep the live session open while copying the logs to another drive or preparing
an issue. Do not publish secrets, account tokens, private keys, or private
service URLs.

See [Troubleshooting](troubleshooting.md) for network, boot, package-signature,
and graphics recovery steps. If the problem remains within the supported
scope, follow [Support](../SUPPORT.md) when opening an issue.
