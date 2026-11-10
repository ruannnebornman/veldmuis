#!/usr/bin/env bash

set -euo pipefail

# This helper is mounted read-only by run-ci-arch-builder.sh and is the only
# package-install capability granted to the untrusted package build user.
# The container workspace is fixed by run-ci-arch-builder.sh. Do not accept a
# path from the build user's environment.
work_root="/workspace/veldmuis/artifacts/nvidia-packages/work/nvidia-580xx-utils"

die() {
  printf '[install-nvidia-build-dependency] ERROR: %s\n' "$*" >&2
  exit 1
}

package_path="$({
  /usr/bin/find "${work_root}" -maxdepth 1 -type f \
    -name 'nvidia-580xx-utils-*.pkg.tar.zst' \
    ! -name '*-debug-*.pkg.tar.zst'
} | /usr/bin/sort -V | /usr/bin/tail -n 1)"

[[ -n "${package_path}" ]] || die "Built nvidia-580xx-utils package was not found"
[[ "${package_path}" == "${work_root}"/* ]] || die "Dependency package escaped its build directory"

pkg_info="$(/usr/bin/bsdtar -xOf "${package_path}" .PKGINFO)"

package_name="$(/usr/bin/awk -F ' = ' '$1 == "pkgname" { print $2; exit }' <<<"${pkg_info}")"
package_version="$(/usr/bin/awk -F ' = ' '$1 == "pkgver" { print $2; exit }' <<<"${pkg_info}")"
package_release="$(/usr/bin/awk -F ' = ' '$1 == "pkgrel" { print $2; exit }' <<<"${pkg_info}")"
package_version_release="${package_version}"
if [[ -n "${package_release}" ]]; then
  package_version_release="${package_version}-${package_release}"
fi

[[ "${package_name}" == nvidia-580xx-utils ]] || \
  die "Unexpected dependency package: ${package_name}"
[[ -n "${package_version_release}" ]] || \
  die "Dependency package metadata is incomplete"

recipe="/workspace/veldmuis/packages/nvidia-580xx-src/nvidia-580xx-utils/PKGBUILD"
[[ -r "${recipe}" ]] || die "Vendored dependency recipe is not readable: ${recipe}"
recipe_version="$(/usr/bin/awk -F= '$1 == "pkgver" { print $2; exit }' "${recipe}")"
recipe_release="$(/usr/bin/awk -F= '$1 == "pkgrel" { print $2; exit }' "${recipe}")"
expected_version_release="${recipe_version}-${recipe_release}"
[[ "${package_version_release}" == "${expected_version_release}" ]] || \
  die "Dependency package version does not match the vendored recipe: ${package_version_release} vs ${expected_version_release}"

expected_name="nvidia-580xx-utils-${package_version_release}-"
[[ "$(/usr/bin/basename "${package_path}")" == "${expected_name}"*.pkg.tar.zst ]] || \
  die "Dependency package filename does not match its metadata: $(/usr/bin/basename "${package_path}")"

checksum_file="${work_root}/.veldmuis-nvidia-utils.sha256"
[[ -r "${checksum_file}" ]] || die "Dependency checksum manifest is missing: ${checksum_file}"
expected_checksum="$(/usr/bin/tr -d '[:space:]' < "${checksum_file}")"
[[ "${expected_checksum}" =~ ^[0-9a-fA-F]{64}$ ]] || \
  die "Dependency checksum manifest is malformed"
actual_checksum="$(/usr/bin/sha256sum "${package_path}" | /usr/bin/awk '{ print $1 }')"
[[ "${actual_checksum}" == "${expected_checksum}" ]] || \
  die "Dependency package checksum mismatch: ${actual_checksum} vs ${expected_checksum}"

printf '[install-nvidia-build-dependency] Verified %s (%s)\n' \
  "$(/usr/bin/basename "${package_path}")" "${actual_checksum}"

/usr/bin/pacman -U --noconfirm --needed "${package_path}"
