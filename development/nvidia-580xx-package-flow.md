# NVIDIA 580xx Package Flow

The NVIDIA 580xx package path is intentional and active.

`packages/veldmuis-nvidia-legacy` is a metapackage. It does not build the real
driver binaries. The real NVIDIA 580xx packages are built from the configured
AUR package bases, collected as package artifacts, and published into the
`veldmuis-extra` pacman repository.

Do not remove the AUR builder, known-good fallback, or AUR manifest publishing
until another source for the NVIDIA 580xx binary package artifacts is wired into
the package repo build.

## Source Of Truth

`packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh` defines:

- AUR package bases to build.
- Repository package names expected from those builds.
- Runtime dependencies used by `veldmuis-nvidia-legacy`.
- Expected package licenses used by artifact validation.

## Build Flow

1. `development/build-aur-packages.sh` builds or resolves the configured AUR
   package bases and writes artifacts under `artifacts/aur-packages/current`.
2. `development/run-ci-arch-builder.sh` runs the AUR build before the local repo
   build. If enabled, it restores the known-good NVIDIA package set when a fresh
   AUR build fails.
3. `development/build-local-repo.sh` copies `veldmuis-nvidia-legacy` plus the
   NVIDIA 580xx artifacts into `veldmuis-extra`.
4. `development/publish-r2-package-repo.sh` publishes the pacman repositories
   and includes the AUR manifest when present.
5. `development/publish-known-good-nvidia-packages.sh` updates the known-good
   NVIDIA package cache after a successful non-fallback build.
6. `development/restore-known-good-nvidia-packages.sh` restores that cache when
   the active AUR build path cannot produce a complete package set.

## Audit Rule

The AUR flow may be removed only after a replacement source provides the same
NVIDIA 580xx repository packages and `development/build-local-repo.sh`,
package-refresh automation, release automation, and this document are updated to
use that replacement source.
