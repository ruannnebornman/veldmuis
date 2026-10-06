# NVIDIA 580xx Package Flow

The NVIDIA 580xx package path is intentional and active.

`packages/veldmuis-nvidia-legacy` is a metapackage. It does not build the real
driver binaries. The real NVIDIA 580xx packages are built from package recipes
vendored under `packages/nvidia-580xx-src`, collected as package artifacts, and
published into the `veldmuis-extra` pacman repository.

Do not remove the vendored recipe builder, known-good fallback, or manifest
publishing until another source for the NVIDIA 580xx binary package artifacts is
wired into the package repo build.

## Source Of Truth

`packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh` defines:

- Package bases to build.
- Repository package names expected from those builds.
- Runtime dependencies used by `veldmuis-nvidia-legacy`.
- Expected package licenses used by artifact validation.

`packages/nvidia-580xx-src/<package_base>/` holds the build recipes. They are
copied from the upstream AUR package repositories, and
`packages/nvidia-580xx-src/upstream-refs.txt` records the upstream commit each
recipe was last synced from. The driver payload itself still comes from the
official NVIDIA `.run` installer referenced by each PKGBUILD.

## Build Flow

1. `development/run-ci-arch-builder.sh` prepares a disposable Arch builder
   image and a read-only snapshot of the trusted build tooling.
2. Veldmuis packages are built without the repository signing key.
3. `development/build-nvidia-packages.sh` runs in a separate container with the
   repository mounted read-only. By default (`VELDMUIS_NVIDIA_SOURCE=local`) it
   builds from the vendored recipes under `packages/nvidia-580xx-src` and can
   write only to `artifacts/nvidia-packages`. Setting `VELDMUIS_NVIDIA_SOURCE=upstream`
   restores the legacy upstream-clone path for ad-hoc use.
4. If enabled, the stage restores the known-good NVIDIA package set when a fresh
   build fails, verifying the project's detached package signatures before the
   artifacts enter the signing stage.
5. A network-disabled signing container validates the expected NVIDIA artifact
   set, imports the signing key, and runs `development/build-local-repo.sh`.
6. `development/build-local-repo.sh` copies `veldmuis-nvidia-legacy` plus the
   NVIDIA 580xx artifacts into `veldmuis-extra` and signs the repository.
7. `development/publish-r2-package-repo.sh` publishes the pacman repositories
   and includes the NVIDIA manifest, including recipe hashes and source hashes.
8. `development/publish-known-good-nvidia-packages.sh` updates the known-good
   NVIDIA package cache after a successful non-fallback build, then prunes
   cached objects the new manifest no longer references.
9. `development/restore-known-good-nvidia-packages.sh` restores that cache when
   the active build path cannot produce a complete package set.

## Recipe Sync Policy

The vendored recipes are the build source, so there is no dependency lock pull
request to merge. The scheduled package refresh rebuilds and publishes whenever the
vendored recipes or other package inputs change on `main`. The build,
package-set, license, signature, and repository checks all run for every
refresh. The payload scan runs and records review signals for the built package
set, but it does not block publishing: the NVIDIA packages always carry setuid
and privileged integration paths, so the scan is a tripwire rather than a gate,
and the recipes are reviewed when they are synced.

Upstream recipe changes are surfaced by the scheduled `NVIDIA Recipe Watch`
workflow. It runs `development/check-nvidia-recipe-drift.sh`, which compares the
vendored recipes against the upstream AUR package repositories. When they
differ, `development/sync-nvidia-recipes.sh` mirrors the changed recipes into
`packages/nvidia-580xx-src/<package_base>/` and updates
`packages/nvidia-580xx-src/upstream-refs.txt`, and the workflow opens an assigned
pull request on a `chore/nvidia-recipe-sync` branch for review. The package
refresh rebuilds and publishes only after that pull request is merged. This
keeps the build independent of AUR availability while still making upstream
changes visible and reviewable.

The signing key must never be passed to either package build container. The
signing stage may read completed package artifacts but must not execute
PKGBUILDs or have network access.

## Audit Rule

The vendored recipe flow may be replaced only after a replacement source
provides the same NVIDIA 580xx repository packages and
`development/build-local-repo.sh`, package-refresh automation, release
automation, and this document are updated to use that replacement source.
