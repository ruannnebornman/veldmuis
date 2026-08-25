#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
audit_script="${script_dir}/audit-aur-update.sh"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT

# shellcheck disable=SC1090,SC1091
source "${audit_script}"

repo_path="${test_root}/aur-package"
git init --quiet "${repo_path}"
git -C "${repo_path}" config user.name 'AUR audit test'
git -C "${repo_path}" config user.email 'aur-audit-test@example.invalid'

write_pkgbuild() {
  local version="$1"
  local checksum="$2"

  printf '%s\n' \
    "pkgname=nvidia-580xx-utils" \
    "pkgver=${version}" \
    'pkgrel=1' \
    'source=("https://example.invalid/nvidia.tar.gz")' \
    "sha256sums=('${checksum}')" >"${repo_path}/PKGBUILD"
}

commit_repo() {
  local message="$1"

  git -C "${repo_path}" add -A
  git -C "${repo_path}" commit --quiet -m "${message}"
  git -C "${repo_path}" rev-parse HEAD
}

assert_risk() {
  local label="$1"
  local package_base="$2"
  local old_ref="$3"
  local new_ref="$4"
  local expected="$5"

  # shellcheck disable=SC2034
  report_file="${test_root}/${label}.md"
  highest_risk=low
  # shellcheck disable=SC2034
  updates_available=false
  classify_change "${package_base}" "${repo_path}" "${old_ref}" "${new_ref}"
  [[ "${highest_risk}" == "${expected}" ]] || {
    printf 'Expected %s to be %s, got %s\n' "${label}" "${expected}" "${highest_risk}" >&2
    return 1
  }
}

write_pkgbuild 580.1.1 oldchecksum
accepted_ref="$(commit_repo 'accepted package recipe')"

write_pkgbuild 580.1.2 newchecksum
metadata_ref="$(commit_repo 'update package metadata')"
assert_risk metadata-only nvidia-580xx-utils "${accepted_ref}" "${metadata_ref}" low

unsafe_command_substitution=$'\x24('
printf '%s\n' \
  'pkgname=nvidia-580xx-utils' \
  'pkgver=580.1.2' \
  'pkgrel=1' \
  'source=(' \
  "  \"${unsafe_command_substitution}printf unsafe)\"" \
  ')' \
  "sha256sums=('newchecksum')" >"${repo_path}/PKGBUILD"
command_substitution_ref="$(commit_repo 'add command substitution')"
assert_risk command-substitution nvidia-580xx-utils "${metadata_ref}" "${command_substitution_ref}" high

printf '\n# Build commands are not metadata\nbuild() {\n  make\n}\n' >>"${repo_path}/PKGBUILD"
build_ref="$(commit_repo 'change build recipe')"
assert_risk build-recipe nvidia-580xx-utils "${command_substitution_ref}" "${build_ref}" high

printf 'post_install() {\n  printf done\n}\n' >"${repo_path}/nvidia-580xx-utils.install"
install_ref="$(commit_repo 'add install hook')"
assert_risk install-hook nvidia-580xx-utils "${build_ref}" "${install_ref}" high

assert_risk non-nvidia-package other-package "${accepted_ref}" "${metadata_ref}" high

git -C "${repo_path}" switch --quiet --orphan unrelated
git -C "${repo_path}" clean --quiet -fdx
write_pkgbuild 590.1.1 unrelatedchecksum
unrelated_ref="$(commit_repo 'unrelated package history')"
assert_risk non-descendant nvidia-580xx-utils "${accepted_ref}" "${unrelated_ref}" high

printf 'audit-aur-update policy tests passed\n'
