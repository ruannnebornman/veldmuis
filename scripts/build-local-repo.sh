#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages_root="${repo_root}/packages"
repos_root="${repo_root}/repos"
arch="${VELDMUIS_ARCH:-x86_64}"
core_repo="veldmuis-core"
extra_repo="veldmuis-extra"
key_fpr_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"

required_packages=(
  "calamares"
  "veldmuis-calamares-config"
  "veldmuis-keyring"
  "veldmuis-mirrorlist"
  "veldmuis-release"
  "veldmuis-base"
  "veldmuis-common"
  "veldmuis-boot"
  "veldmuis-displaymanager"
  "veldmuis-desktop-kde"
  "veldmuis-multimedia"
  "veldmuis-branding"
  "veldmuis-desktop"
  "veldmuis-devel"
)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

latest_pkg() {
  local pkg_name="$1"
  local pkg_dir="${packages_root}/${pkg_name}"

  find "${pkg_dir}" -maxdepth 1 -type f \
    -name "${pkg_name}-*.pkg.tar.zst" \
    ! -name "${pkg_name}-debug-*.pkg.tar.zst" \
    | sort -V \
    | tail -n 1
}

sign_package() {
  local package_path="$1"
  local -a gpg_args=(
    --batch
    --yes
    --local-user "${key_fpr}"
  )

  if [[ -n "${VELDMUIS_GPG_PASSPHRASE_FILE:-}" ]]; then
    gpg_args+=(--pinentry-mode loopback --passphrase-file "${VELDMUIS_GPG_PASSPHRASE_FILE}")
  elif [[ -n "${VELDMUIS_GPG_PASSPHRASE:-}" ]]; then
    gpg_args+=(--pinentry-mode loopback --passphrase "${VELDMUIS_GPG_PASSPHRASE}")
  fi

  rm -f "${package_path}.sig"
  gpg "${gpg_args[@]}" --detach-sign "${package_path}"
}

build_repo_db() {
  local repo_name="$1"
  local repo_dir="$2"
  shift 2
  local db_path="${repo_dir}/${repo_name}.db.tar.gz"
  local args=(
    --sign
    --key "${key_fpr}"
    "${db_path}"
  )

  if (($# > 0)); then
    args=(--sign --key "${key_fpr}" --include-sigs "${db_path}" "$@")
  fi

  repo-add "${args[@]}"
}

require_cmd gpg
require_cmd repo-add

if [[ ! -r "${key_fpr_file}" ]]; then
  echo "Signing key marker not found: ${key_fpr_file}" >&2
  exit 1
fi

key_fpr="$(tr -d '[:space:]' < "${key_fpr_file}")"
core_dir="${repos_root}/${core_repo}/os/${arch}"
extra_dir="${repos_root}/${extra_repo}/os/${arch}"

rm -rf "${core_dir}" "${extra_dir}"
mkdir -p "${core_dir}" "${extra_dir}"

declare -a core_packages=()

for pkg_name in "${required_packages[@]}"; do
  pkg_path="$(latest_pkg "${pkg_name}")"

  if [[ -z "${pkg_path}" ]]; then
    echo "Built package not found for ${pkg_name}" >&2
    exit 1
  fi

  dest_path="${core_dir}/$(basename "${pkg_path}")"
  cp -f "${pkg_path}" "${dest_path}"
  sign_package "${dest_path}"
  core_packages+=("${dest_path}")
done

build_repo_db "${core_repo}" "${core_dir}" "${core_packages[@]}"
build_repo_db "${extra_repo}" "${extra_dir}"

echo "Built local pacman repos:"
echo "  ${core_dir}"
echo "  ${extra_dir}"
