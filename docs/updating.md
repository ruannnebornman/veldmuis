# Updating Veldmuis

Veldmuis is a rolling-release Arch-based system. Installed systems receive Arch
and Veldmuis package updates through pacman; dated Veldmuis releases identify
install-media and release-pipeline snapshots rather than separate editions that
must be reinstalled.

## Before Updating

- Back up important data.
- Avoid starting a large update when the system may lose power or network
  access.
- Read the pacman transaction before confirming removals, replacements, or
  package conflicts.
- If the system uses NVIDIA 580xx, review the driver precautions below before
  rebooting after kernel or driver changes.

Veldmuis follows the Arch full-upgrade model. Partial upgrades are unsupported.

## Normal Update

Refresh package databases and upgrade the complete system in one transaction:

```sh
sudo pacman -Syu
```

Run the command regularly enough that individual updates remain understandable.
Do not interrupt pacman while it is installing packages.

## Avoid Partial Upgrades

Do not refresh package databases with `pacman -Sy` and then install or upgrade
only selected packages. That can combine new repository metadata with an old
installed dependency set.

Use `pacman -Syu` for the normal update path. If a package requires manual
intervention, resolve the reported conflict as part of a full upgrade rather
than forcing files or bypassing dependency checks.

Do not disable package-signature checking to work around repository or keyring
errors. Follow the keyring recovery steps in
[Troubleshooting](troubleshooting.md) instead.

## When A New ISO Is Released

An existing Veldmuis installation normally does not need the new ISO. Continue
updating the installed system with:

```sh
sudo pacman -Syu
```

Use the current ISO for a new installation or as rescue media. Historical
release tags, manifests, and checksums document release builds, while the
public ISO download path always points to the current image.

## Rebooting After Updates

Not every update requires an immediate reboot. Reboot after updates that replace
the running kernel, graphics driver, initramfs, systemd, or other components
that cannot be fully replaced in the current session.

If pacman reports a failed hook, DKMS build, initramfs generation, or boot-entry
refresh, resolve that failure before treating the next reboot as safe.

## NVIDIA 580xx Systems

The optional NVIDIA 580xx driver uses DKMS. Kernel headers must match every
kernel that should load the driver.

After a kernel or NVIDIA update, check:

```sh
dkms status
```

If the module did not build for the updated kernel, run:

```sh
sudo dkms autoinstall
sudo mkinitcpio -P
```

For the default kernel, confirm that both packages are installed:

```sh
sudo pacman -S linux linux-headers
```

For an optional LTS recovery kernel, install both:

```sh
sudo pacman -S linux-lts linux-lts-headers
```

Confirm that a usable systemd-boot entry exists for the intended recovery
kernel. See [NVIDIA 580xx support](nvidia.md) for the full support and recovery
boundary.

## Mirror Problems

If Arch mirrors are unreachable or stale, run the Veldmuis mirror refresh
service:

```sh
sudo systemctl start veldmuis-refresh-arch-mirrors.service
```

Inspect its result if needed:

```sh
systemctl status veldmuis-refresh-arch-mirrors.service
```

Then retry the full update:

```sh
sudo pacman -Syu
```

## Installing Optional Groups

Optional application groups can be added during a full update:

```sh
sudo pacman -Syu veldmuis-gaming
sudo pacman -Syu veldmuis-downloads
sudo pacman -Syu veldmuis-sync
sudo pacman -Syu veldmuis-development
```

Install only the groups you want. Their current contents are documented in
[Package composition](packages.md).

## If An Update Fails

Keep the exact pacman output. Do not repeatedly force the transaction or delete
package database files.

Start with [Troubleshooting](troubleshooting.md). For a support issue, include:

- Whether the update completed or stopped partway through.
- The complete pacman command and relevant output.
- The installed kernel package and version.
- Relevant Veldmuis and graphics package versions.
- `dkms status` output for NVIDIA failures.
- Whether the system can still reach a TTY or an older boot entry.

The best-supported installed state is a system that can complete a normal full
`pacman -Syu`. Unsupported partial upgrades, custom repository mixes, and
untraceable local package replacements may require restoration from backup
before a Veldmuis-specific issue can be reproduced.
