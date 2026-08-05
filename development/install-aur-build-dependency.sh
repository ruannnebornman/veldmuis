#!/usr/bin/env bash

set -euo pipefail

# This helper is mounted read-only by run-ci-arch-builder.sh and is the only
# package-install capability granted to the untrusted AUR build user.
# The container workspace is fixed by run-ci-arch-builder.sh. Do not accept a
# path from the build user's environment.
work_root="/workspace/veldmuis/artifacts/aur-packages/work/nvidia-580xx-utils"

die() {
  printf '[install-aur-build-dependency] ERROR: %s\n' "$*" >&2
  exit 1
}

package_path="$({
  /usr/bin/find "${work_root}" -maxdepth 1 -type f \
    -name 'nvidia-580xx-utils-*.pkg.tar.zst' \
    ! -name '*-debug-*.pkg.tar.zst'
} | /usr/bin/sort -V | /usr/bin/tail -n 1)"

[[ -n "${package_path}" ]] || die "Built nvidia-580xx-utils package was not found"
[[ "${package_path}" == "${work_root}"/* ]] || die "Dependency package escaped its build directory"

package_name="$(
  /usr/bin/bsdtar -xOf "${package_path}" .PKGINFO \
    | /usr/bin/awk -F ' = ' '$1 == "pkgname" { print $2; exit }'
)"
[[ "${package_name}" == nvidia-580xx-utils ]] || \
  die "Unexpected dependency package: ${package_name}"

/usr/bin/pacman -U --noconfirm --needed "${package_path}"
