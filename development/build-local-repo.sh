#!/usr/bin/env bash

set -euo pipefail

# The extra repo intentionally includes CI-built NVIDIA 580xx artifacts from the
# active AUR flow. See development/nvidia-580xx-package-flow.md before changing
# the AUR artifact handling below.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
packages_root="${repo_root}/packages"
repos_root="${repo_root}/repos"
aur_package_dir="${VELDMUIS_AUR_PACKAGE_DIR:-${repo_root}/artifacts/aur-packages/current}"
arch="${VELDMUIS_ARCH:-x86_64}"
core_repo="veldmuis-core"
extra_repo="veldmuis-extra"
key_fpr_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"
repo_package_suffix="${VELDMUIS_REPO_PACKAGE_SUFFIX:-build$(date -u +%Y%m%d%H%M%S)}"

# shellcheck source=development/package-manifest.sh
. "${script_dir}/package-manifest.sh"

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

  rm -f "${package_path}.sig"
  gpg --batch --yes --local-user "${key_fpr}" --detach-sign "${package_path}"
}

copy_signed_package() {
  local source_path="$1"
  local dest_dir="$2"
  local -n package_array="$3"
  local source_name
  local dest_name
  local dest_path

  source_name="$(basename "${source_path}")"
  dest_name="${source_name%.pkg.tar.zst}+${repo_package_suffix}.pkg.tar.zst"
  dest_path="${dest_dir}/${dest_name}"

  cp -f "${source_path}" "${dest_path}"
  sign_package "${dest_path}"
  package_array+=("${dest_path}")
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
require_cmd find
require_cmd sort
require_cmd date

if [[ ! "${repo_package_suffix}" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  echo "Repository package suffix contains unsafe characters: ${repo_package_suffix}" >&2
  exit 1
fi

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
declare -a extra_packages=()

for pkg_name in "${veldmuis_core_package_order[@]}"; do
  pkg_path="$(latest_pkg "${pkg_name}")"

  if [[ -z "${pkg_path}" ]]; then
    echo "Built package not found for ${pkg_name}" >&2
    exit 1
  fi

  copy_signed_package "${pkg_path}" "${core_dir}" core_packages
done

for pkg_name in "${veldmuis_extra_package_order[@]}"; do
  pkg_path="$(latest_pkg "${pkg_name}")"

  if [[ -z "${pkg_path}" ]]; then
    echo "Built package not found for ${pkg_name}" >&2
    exit 1
  fi

  copy_signed_package "${pkg_path}" "${extra_dir}" extra_packages
done

if [[ ! -d "${aur_package_dir}" ]]; then
  echo "AUR package artifact directory not found: ${aur_package_dir}" >&2
  echo "Run development/build-aur-packages.sh first, preferably inside the disposable Arch builder." >&2
  exit 1
fi

while IFS= read -r pkg_path; do
  copy_signed_package "${pkg_path}" "${extra_dir}" extra_packages
done < <(
  find "${aur_package_dir}" -maxdepth 1 -type f \
    -name '*.pkg.tar.zst' \
    ! -name '*-debug-*.pkg.tar.zst' \
    | sort -V
)

if ((${#extra_packages[@]} == ${#veldmuis_extra_package_order[@]})); then
  echo "No AUR package artifacts found under: ${aur_package_dir}" >&2
  exit 1
fi

build_repo_db "${core_repo}" "${core_dir}" "${core_packages[@]}"
build_repo_db "${extra_repo}" "${extra_dir}" "${extra_packages[@]}"

echo "Built local pacman repos:"
echo "  ${core_dir}"
echo "  ${extra_dir}"
