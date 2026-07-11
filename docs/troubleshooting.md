# Troubleshooting

This guide covers the first checks for common Veldmuis install, boot, package,
and graphics problems.

## Verify The ISO First

Before debugging install behavior, verify the ISO checksum:

```sh
curl -fL -o veldmuis.iso https://downloads.veldmuislinux.org/iso/latest.iso
curl -fL -o latest.iso.sha256 https://downloads.veldmuislinux.org/iso/latest.iso.sha256
expected_sha256="$(awk '{ print $1; exit }' latest.iso.sha256)"
actual_sha256="$(sha256sum veldmuis.iso | awk '{ print $1; exit }')"
test "${actual_sha256}" = "${expected_sha256}"
```

See [Security Policy](../SECURITY.md) for the full verification flow.

## Live ISO Does Not Reach Graphics

Use the safe-graphics live boot entry. The live ISO includes a safe-graphics
entry with:

```text
nomodeset nouveau.modeset=0
```

If safe graphics works, include that fact in any issue report.

## Installer Fails

Collect these logs from the live session:

```text
/tmp/veldmuis-calamares-debug.log
/tmp/veldmuis-calamares-bootstrap.log
```

The current installer is a network installer for Arch packages. It embeds
Veldmuis repositories, but Arch packages are resolved from Arch mirrors during
installation. Check:

- Network is connected in the live session.
- DNS resolution works.
- The selected Arch mirror is reachable.
- System time is reasonable.
- The target disk is visible and not mounted unexpectedly.

To retry Arch mirror ranking in an installed system:

```sh
sudo systemctl start veldmuis-refresh-arch-mirrors.service
```

In the live session, restarting the installer is often simpler after fixing
network or partitioning state.

## Package Signature Or Keyring Errors

On an installed system, refresh package databases with a normal full update:

```sh
sudo pacman -Syu
```

If pacman reports keyring initialization or trust issues, repopulate the Arch
and Veldmuis keyrings:

```sh
sudo pacman-key --init
sudo pacman-key --populate archlinux veldmuis
sudo pacman-key --updatedb
```

Then retry:

```sh
sudo pacman -Syu
```

If this happens during installation, collect the Calamares bootstrap log instead
of running manual commands in the target root first.

## Installed System Does Not Boot

Veldmuis uses UEFI and systemd-boot.

From rescue media or a live environment, check:

```sh
bootctl status
ls -R /boot
ls /boot/loader/entries
```

If the installed system is mounted and you can chroot into it, refresh boot
entries:

```sh
sudo arch-chroot /mnt /usr/lib/veldmuis/veldmuis-kernel-install-sync
```

Check that `/boot` contains the expected kernel and initramfs files:

```text
/boot/vmlinuz-linux
/boot/initramfs-linux.img
```

## Installed System Boots But Graphics Fail

Try a TTY:

```text
Ctrl+Alt+F3
```

Then complete a full update and rebuild initramfs:

```sh
sudo pacman -Syu
sudo mkinitcpio -P
sudo reboot
```

For NVIDIA 580xx systems, also check:

```sh
dkms status
sudo dkms autoinstall
```

See [NVIDIA 580xx Support](nvidia.md).

## Package Updates Fail

Avoid partial upgrades. Prefer:

```sh
sudo pacman -Syu
```

Do not install one package from updated repositories while leaving the rest of
the system behind unless you understand the dependency risk.

If mirror issues are suspected:

```sh
sudo systemctl start veldmuis-refresh-arch-mirrors.service
sudo pacman -Syu
```

## AppImage Reports Missing libfuse.so.2

Veldmuis installs the FUSE 2 compatibility runtime through `veldmuis-common`.
Systems installed before that dependency was added can install it with a full
system upgrade:

```sh
sudo pacman -Syu fuse2
```

Verify that the package and compatibility library are available:

```sh
pacman -Q fuse2
ldconfig -p | grep 'libfuse\.so\.2'
```

Then run the AppImage again.

## Optional Extras Are Missing

Optional application groups are not part of the default desktop install.

Install them manually with:

```sh
sudo pacman -S veldmuis-gaming
sudo pacman -S veldmuis-downloads
sudo pacman -S veldmuis-sync
sudo pacman -S veldmuis-development
```

Current optional groups are documented in [Package Composition](packages.md).

## What To Include In An Issue

Include:

- Veldmuis release tag or ISO name.
- Hardware or VM details.
- Installer graphics choice and extras choice.
- Whether the live safe-graphics entry works.
- `pacman -Q` output for relevant packages.
- Exact error messages.
- Installer logs for install failures.
- `dkms status` for NVIDIA failures.

Do not include secrets, private keys, account tokens, or private service URLs.
