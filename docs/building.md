# Building Packages And ISOs

This guide documents the current build flow. It is intended for maintainers and
reviewers who want to understand or reproduce the repository behavior.

## Current Build Model

Veldmuis builds in these stages:

1. Build native packages from `packages/`.
2. Build NVIDIA 580xx artifacts from configured AUR package bases.
3. Sign packages and repository databases into local pacman repositories.
4. Build an archiso image using the signed local repositories.
5. Generate and sign release metadata for release builds.
6. Publish package and ISO artifacts from CI workflows.

The package order is defined in:

```text
development/package-manifest.sh
```

## Host Expectations

Use an Arch Linux environment for local builds. The scripts assume Arch tools
and package names.

Common local build tools include:

```text
base-devel
git
gnupg
pacman-contrib
repo-add
docker
archiso
rsync
squashfs-tools
```

Some packages, such as Calamares, need additional build dependencies. The CI
builder image installs the expected dependency set in
`development/run-ci-arch-builder.sh`.

## Important Reproducibility Notes

Local package builds currently use:

```text
makepkg --nodeps -f
```

That is intentional in the current scripts because the CI builder prepares
build dependencies ahead of time. It also means a clean host must install the
required build dependencies before running local package builds.

Current reproducibility limits:

- Native and live-filesystem Arch build dependencies are not yet pinned to an
  Arch Linux Archive snapshot.
- Native package build dependencies are prepared by the host or CI image.
- AUR-derived NVIDIA packages can be built from locked refs or latest refs,
  depending on `VELDMUIS_AUR_REF_MODE`.
- The network installer resolves Arch packages from mirrors during
  installation.

Full offline ISO candidates use one dated Arch Linux Archive snapshot for the
complete install-time dependency closure. Candidate metadata records that
snapshot, the package manifest, package count, and repository byte count.

## Build Native Packages

Build the full package set:

```sh
./development/build-all-packages.sh
```

Build a subset:

```sh
./development/build-all-packages.sh veldmuis-branding veldmuis-release
```

Native package artifacts are written beside their PKGBUILDs under `packages/`.
Generated package artifacts are ignored by Git.

## Build AUR-Derived NVIDIA Packages

The NVIDIA 580xx AUR package bases are defined in:

```text
packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
```

Build using locked refs from `development/aur-packages.lock`:

```sh
VELDMUIS_AUR_REF_MODE=locked ./development/build-aur-packages.sh
```

Build using the latest AUR refs:

```sh
VELDMUIS_AUR_REF_MODE=latest ./development/build-aur-packages.sh
```

Resolve refs without building:

```sh
./development/build-aur-packages.sh --resolve-only
```

Validate already-built AUR artifacts:

```sh
./development/build-aur-packages.sh --validate-only
```

The AUR output directory defaults to:

```text
artifacts/aur-packages/current/
```

## Build The Local Package Repository

After native packages and AUR artifacts exist, build signed local repositories:

```sh
./development/build-local-repo.sh
```

This creates:

```text
repos/veldmuis-core/os/x86_64/
repos/veldmuis-extra/os/x86_64/
```

Requirements:

- A usable GnuPG signing key.
- A signing fingerprint marker, by default:

```text
~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
```

The script signs package files and repository databases.

## Build The Offline Installation Repository

After the two Veldmuis repositories exist, resolve the complete installer seed
against a dated Arch Linux Archive snapshot:

```sh
VELDMUIS_ARCH_SNAPSHOT=YYYY/MM/DD \
  ./development/build-offline-install-repo.sh
```

The CI path splits this into a networked `download` phase without private key
material and a network-disabled `sign` phase. It creates:

```text
repos/veldmuis-offline/os/x86_64/
repos/manifests/veldmuis-offline-packages.tsv
repos/manifests/veldmuis-offline-build.txt
```

Validate every installer selection using only local repositories:

```sh
./development/check-offline-install-repo.sh
```

## Build The ISO

Build the ISO from the current local repositories:

```sh
./development/build-archiso.sh
```

Build a full offline candidate after creating and validating the offline
repository:

```sh
VELDMUIS_ISO_MODE=offline ./development/build-archiso.sh
```

The ISO build requires:

- `mkarchiso`
- root privileges through `sudo`
- a built local `repos/` tree
- Veldmuis keyring files under `packages/veldmuis-keyring/`

The script copies the local repositories into the live image at:

```text
/opt/veldmuis/repo/
```

Local ISO output is written outside the repository, under the workspace-level
build directory:

```text
../build/archiso/out/
```

## CI Container Build

The release and package-refresh workflows use
`development/run-ci-arch-builder.sh` to build inside Arch containers.

Targets:

```sh
./development/run-ci-arch-builder.sh packages
./development/run-ci-arch-builder.sh iso
./development/run-ci-arch-builder.sh offline-iso
```

The outer script requires Docker and release environment variables, including
the signing key material used only by network-disabled signing stages. The
`iso` target additionally requires `VELDMUIS_RELEASE_TAG` and the exact
`VELDMUIS_RELEASE_SHA`.

The container flow separates stages:

- Native package build stage: no signing key.
- AUR package build stage: no signing key.
- Signing stage: receives signing key, validates AUR artifacts, has no network.
- Offline download stage: receives no signing key and resolves the full package
  closure from the requested Arch Linux Archive snapshot.
- Offline signing stage: receives the signing key, has no network, and signs
  the offline repository database.
- Offline validation stage: receives no signing key, has no network, and proves
  every installer choice resolves only to embedded files.
- ISO stage: no signing key, repository mounted read-only.
- Release-metadata stage: receives signing key, has no network, and creates the
  signed manifest, checksum, package inventory, SPDX SBOM, build-input record,
  and release-specific AUR-input manifest.

The outer builder pulls its configured base image, resolves the immutable
repository digest, and uses that digest in the generated Dockerfile. Release
metadata records the requested image, resolved base digest, resulting image ID,
Docker version, relevant build-tool versions, release source commit, and exact
AUR refs.

The `Offline Installer Release` workflow runs the `offline-iso` target,
generates signed metadata, prints the exact ISO and embedded repository sizes,
and publishes immutable artifacts plus the small offline channel documents.
Every scheduled or manually dispatched network release calls it with a frozen
tag, source commit, and Arch snapshot after network publication succeeds. It
cannot be dispatched independently, does not publish the rolling package
repository, and does not upload the large ISO as a GitHub artifact.

Release metadata can be generated inside an appropriately prepared Arch build
environment with:

```sh
./development/generate-release-metadata.sh
```

The object-storage publisher is:

```sh
./development/publish-r2-release.sh
```

The release workflow first runs `prune-release-storage.sh` to remove every
older release prefix while protecting the tag being published. The publisher
then uploads and verifies release-specific objects before promoting the small
channel documents. The signed manifest is updated last and objects under the
current tag are never overwritten.

## Publish The Package Repository

The package repository publisher is:

```sh
./development/publish-r2-package-repo.sh
```

It publishes:

- `veldmuis-core`
- `veldmuis-extra`
- repository metadata and signatures
- `veldmuis-package-repo.manifest.txt`
- `veldmuis-aur-packages.manifest.txt` when present

Publishing requires Cloudflare R2-compatible credentials and environment
variables used by the workflow.

## Package Refresh Checks

The package-refresh workflow checks whether the published package repository is
current:

```sh
./development/check-package-repo-refresh.sh
```

It compares:

- current source commit versus the published package repository manifest
- resolved AUR refs versus the published AUR manifest

The workflow can force a refresh or simulate an AUR failure to test the
known-good NVIDIA fallback path.

## Local VM And USB Helpers

Rebuild changed packages, rebuild the local repo and ISO, then create a fresh
test VM:

```sh
./development/rebuild-iso-vm.sh
```

Create a VM with no network interface from boot for an offline installation
test:

```sh
NETWORK_MODE=none ./development/create-arch-test-vm.sh /path/to/veldmuis.iso
```

The full offline candidate is not release-ready until default, NVIDIA 580xx
with all extras, and all-open-source with all extras have each installed and
booted successfully in this mode.

Rebuild changed packages, rebuild the local repo and ISO, then write the newest
ISO to a USB disk:

```sh
USB_DEVICE=/dev/sdX ./development/rebuild-iso-usb.sh
```

The USB helper writes to a block device. Confirm the target device before
running it.
