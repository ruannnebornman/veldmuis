# NVIDIA 580xx Support

Veldmuis includes an optional NVIDIA 580xx DKMS path for systems that need that
legacy driver branch. The default graphics choice remains the open-source stack.

## Support Boundary

The NVIDIA 580xx path is:

- Optional.
- Proprietary-driver dependent.
- DKMS and kernel-header dependent.
- Built from vendored package recipes, then signed into the Veldmuis package
  repository.
- Higher risk than the open-source graphics choices on a rolling Arch base.

It is not a general NVIDIA support promise. If the open-source Nouveau path is
usable for a system, that path is simpler and safer.

## Installer Choices

The installer graphics page currently exposes:

- `all-open-source`
- `amd-open-source`
- `intel-open-source`
- `nvidia-open-source`
- `nvidia-580xx-dkms`

Selecting `nvidia-580xx-dkms` installs:

```text
veldmuis-nvidia-legacy
```

That metapackage depends on:

```text
dkms
linux-headers
nvidia-580xx-dkms
nvidia-580xx-utils
opencl-nvidia-580xx
lib32-nvidia-580xx-utils
lib32-opencl-nvidia-580xx
nvidia-580xx-settings
```

It also declares optional `linux-lts` and `linux-lts-headers` recovery
dependencies.

## Package Source

`veldmuis-nvidia-legacy` is only a metapackage. It does not build driver
binaries itself.

The real NVIDIA 580xx package artifacts are built from these vendored package
recipes under `packages/nvidia-580xx-src`:

```text
nvidia-580xx-utils
lib32-nvidia-580xx-utils
nvidia-580xx-settings
```

The expected package set is defined in:

```text
packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
```

The maintainer-facing flow is documented in:

```text
development/nvidia-580xx-package-flow.md
```

## Supply-Chain Controls

The current automation:

- Builds the vendored recipes under `packages/nvidia-580xx-src` from the
  repository checkout, so the build does not depend on AUR availability.
- Builds the packages without the Veldmuis signing key.
- Validates the expected package names and license metadata.
- Records the recipe content hash and pre-build source-input hashes.
- Signs packages only in a later network-disabled signing stage.
- Publishes the signed package set through `veldmuis-extra`.
- Publishes a known-good NVIDIA package cache after successful non-fallback
  builds, then prunes cached objects the new manifest no longer references.
- Can restore the known-good NVIDIA package set if a fresh build fails.
- Rebuilds and publishes automatically when the vendored recipes or other
  package inputs change on `main`.
- Runs a scheduled `NVIDIA Recipe Watch` job that compares the vendored recipes
  against the upstream AUR package repositories and opens an issue when they
  differ. Syncing a recipe change is a reviewed commit.
- Runs a payload scan over the built package set and records its findings. The
  scan is a tripwire, not a gate: the NVIDIA packages always carry setuid and
  privileged integration paths, so it does not block publishing.

These controls reduce risk, but they do not remove the upstream risk. The
vendored recipes and the NVIDIA source archives are third-party inputs;
Veldmuis does not claim to have performed a full source audit or an independent
byte-for-byte rebuild before signing them. Vendoring a recipe makes the build
reproducible from this repository and makes an upstream change reviewable, not
trusted by itself. DKMS rebuild failures and rolling-kernel incompatibility
remain possible.

The vendored recipe is a snapshot, not a standing trust decision. Review the
`NVIDIA Recipe Watch` diff before syncing an upstream change, and treat the
payload scan findings as review signals rather than proof. The isolated build,
package-set and license validation, and network-disabled signing controls still
run for every build.

## Update Precautions

Avoid partial upgrades. Use full system updates:

```sh
sudo pacman -Syu
```

Before rebooting after a kernel or NVIDIA update, check DKMS state:

```sh
dkms status
```

If DKMS did not build for the current kernel, try:

```sh
sudo dkms autoinstall
sudo mkinitcpio -P
```

Make sure the matching kernel headers are installed:

```sh
sudo pacman -S linux linux-headers
```

If you use the optional LTS kernel as a recovery path, install both pieces:

```sh
sudo pacman -S linux-lts linux-lts-headers
```

Confirm that the systemd-boot entries you rely on actually include the kernel
you intend to boot before treating `linux-lts` as a working fallback.

## Recovery From Broken Graphics

If the graphical session fails after an update:

1. Switch to a TTY with `Ctrl+Alt+F3`.
2. Log in as your user.
3. Complete any interrupted update:

```sh
sudo pacman -Syu
```

4. Check DKMS:

```sh
dkms status
sudo dkms autoinstall
```

5. Rebuild initramfs:

```sh
sudo mkinitcpio -P
```

6. Reboot:

```sh
sudo reboot
```

If the system cannot reach a usable graphical or text login, boot the ISO and
use it as rescue media.

## Temporary Boot Options

The live ISO has a safe-graphics boot entry using:

```text
nomodeset nouveau.modeset=0
```

For an installed system, you can temporarily edit a systemd-boot entry at boot
time and add conservative kernel parameters such as `nomodeset` to reach a
text login. Treat this as a rescue step, not a permanent fix.

## Return To Open-Source Graphics

To move away from the NVIDIA 580xx path, remove the metapackage and any
unneeded NVIDIA dependencies:

```sh
sudo pacman -Rns veldmuis-nvidia-legacy
```

Then install the open-source NVIDIA graphics stack used by the installer:

```sh
sudo pacman -S mesa vulkan-nouveau lib32-vulkan-nouveau
sudo mkinitcpio -P
sudo reboot
```

Review the pacman removal list before confirming. Do not remove packages that
other local workflows still need.

## When To Open An Issue

Open an issue with:

- GPU model.
- Selected installer graphics option.
- Kernel package and version.
- NVIDIA package versions.
- `dkms status` output.
- Relevant pacman transaction output.
- Whether the system can reach a TTY.
- Whether the live ISO safe-graphics entry boots.

Do not paste private logs, secrets, or account tokens into public issues.
