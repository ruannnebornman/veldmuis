#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
package_base="${PACKAGE_BASE_URL:-https://packages.veldmuislinux.org}"
package_dir="${VELDMUIS_AUR_PACKAGE_DIR:-${repo_root}/artifacts/aur-packages/current}"
manifest_path="${VELDMUIS_AUR_MANIFEST:-${package_dir}/veldmuis-aur-packages.manifest.txt}"
work_root="${VELDMUIS_KNOWN_GOOD_WORK_ROOT:-${repo_root}/artifacts/aur-packages/known-good-work}"
known_good_url="${VELDMUIS_KNOWN_GOOD_NVIDIA_URL:-}"
known_good_manifest_name="${KNOWN_GOOD_NVIDIA_MANIFEST_NAME:-veldmuis-known-good-nvidia-580xx.manifest.txt}"
failed_ref_mode="${VELDMUIS_AUR_REF_MODE:-unknown}"
package_keyring="${VELDMUIS_PACKAGE_KEYRING:-${repo_root}/packages/veldmuis-keyring/veldmuis.gpg}"
nvidia_package_set="${VELDMUIS_NVIDIA_580XX_PACKAGE_SET:-${repo_root}/packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh}"

[[ -r "${nvidia_package_set}" ]] || {
  printf '[restore-known-good-nvidia-packages] ERROR: NVIDIA package set not readable: %s\n' "${nvidia_package_set}" >&2
  exit 1
}
# shellcheck source=packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
. "${nvidia_package_set}"

expected_packages=("${veldmuis_nvidia_580xx_repository_packages[@]}")

log() {
  printf '[restore-known-good-nvidia-packages] %s\n' "$*"
}

die() {
  printf '[restore-known-good-nvidia-packages] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

configure_known_good_url() {
  if [[ -z "${known_good_url}" ]]; then
    package_base="${package_base%/}"
    [[ -n "${package_base}" ]] || die "PACKAGE_BASE_URL resolves to an empty value"
    known_good_url="${package_base}/_known-good/nvidia-580xx/current"
  fi

  known_good_url="${known_good_url%/}"
}

download_file() {
  local url="$1"
  local output_path="$2"

  curl --fail --silent --show-error --location "${url}" --output "${output_path}"
}

safe_file_name() {
  local file_name="$1"

  [[ -n "${file_name}" ]] || return 1
  [[ "${file_name}" != */* ]] || return 1
  [[ "${file_name}" != .* ]] || return 1
}

manifest_value() {
  local manifest_file="$1"
  local key="$2"

  awk -F '=' -v key="${key}" '$1 == key { print $2; found = 1; exit } END { exit !found }' \
    "${manifest_file}" 2>/dev/null || true
}

parse_package_files() {
  local manifest_file="$1"

  awk '
    /^\[package_files\]$/ {
      in_package_files = 1
      next
    }
    /^\[/ {
      in_package_files = 0
      next
    }
    in_package_files && NF >= 2 && $1 !~ /^#/ {
      print $1 " " $2
    }
  ' "${manifest_file}"
}

parse_signature_files() {
  local manifest_file="$1"

  awk '
    /^\[signature_files\]$/ {
      in_signature_files = 1
      next
    }
    /^\[/ {
      in_signature_files = 0
      next
    }
    in_signature_files && NF >= 2 && $1 !~ /^#/ {
      print $1 " " $2
    }
  ' "${manifest_file}"
}

parse_package_bases() {
  local manifest_file="$1"

  awk '
    /^\[package_bases\]$/ {
      in_package_bases = 1
      next
    }
    /^\[/ {
      in_package_bases = 0
      next
    }
    in_package_bases && NF >= 2 && $1 !~ /^#/ {
      print
    }
  ' "${manifest_file}"
}

parse_source_inputs() {
  local manifest_file="$1"

  awk '
    /^\[source_inputs\]$/ {
      in_source_inputs = 1
      next
    }
    /^\[/ {
      in_source_inputs = 0
      next
    }
    in_source_inputs && NF >= 2 && $1 !~ /^#/ {
      print
    }
  ' "${manifest_file}"
}

ensure_expected_package_set() {
  local package_name package_path

  for package_name in "${expected_packages[@]}"; do
    package_path="$(find "${package_dir}" -maxdepth 1 -type f \
      -name "${package_name}-*.pkg.tar.zst" \
      ! -name '*-debug-*.pkg.tar.zst' \
      | sort -V \
      | head -n 1)"

    [[ -n "${package_path}" ]] || die "Known-good package missing after restore: ${package_name}"
  done
}

verify_package_signatures() {
  local package_path signature_path

  while IFS= read -r package_path; do
    signature_path="${package_path}.sig"
    [[ -r "${signature_path}" ]] || die "Known-good package signature missing: ${signature_path}"
    gpgv --keyring "${package_keyring}" "${signature_path}" "${package_path}" >/dev/null 2>&1 || \
      die "Known-good package signature is invalid: ${package_path}"
  done < <(
    find "${package_dir}" -maxdepth 1 -type f \
      -name '*.pkg.tar.zst' \
      ! -name '*-debug-*.pkg.tar.zst' \
      | sort -V
  )
}

restore_packages() {
  local known_good_manifest="${work_root}/${known_good_manifest_name}"
  local source_aur_manifest
  local source_aur_manifest_path
  local expected_hash file_name output_path actual_hash

  rm -rf "${work_root}" "${package_dir}"
  mkdir -p "${work_root}" "${package_dir}"

  log "Downloading known-good manifest: ${known_good_url}/${known_good_manifest_name}"
  download_file "${known_good_url}/${known_good_manifest_name}" "${known_good_manifest}"

  source_aur_manifest="$(manifest_value "${known_good_manifest}" source_aur_manifest)"
  [[ -n "${source_aur_manifest}" ]] || die "Known-good manifest is missing source_aur_manifest"
  safe_file_name "${source_aur_manifest}" || die "Unsafe source_aur_manifest in known-good manifest: ${source_aur_manifest}"
  source_aur_manifest_path="${work_root}/${source_aur_manifest}"

  log "Downloading source AUR manifest: ${known_good_url}/${source_aur_manifest}"
  download_file "${known_good_url}/${source_aur_manifest}" "${source_aur_manifest_path}"

  while read -r expected_hash file_name; do
    safe_file_name "${file_name}" || die "Unsafe package file name in known-good manifest: ${file_name}"
    output_path="${package_dir}/${file_name}"

    log "Downloading known-good package: ${file_name}"
    download_file "${known_good_url}/${file_name}" "${output_path}"

    actual_hash="$(sha256sum "${output_path}" | awk '{print $1}')"
    [[ "${actual_hash}" == "${expected_hash}" ]] \
      || die "Checksum mismatch for ${file_name}: expected ${expected_hash}, got ${actual_hash}"
  done < <(parse_package_files "${known_good_manifest}")

  while read -r expected_hash file_name; do
    safe_file_name "${file_name}" || die "Unsafe signature file name in known-good manifest: ${file_name}"
    output_path="${package_dir}/${file_name}"

    log "Downloading known-good signature: ${file_name}"
    download_file "${known_good_url}/${file_name}" "${output_path}"

    actual_hash="$(sha256sum "${output_path}" | awk '{print $1}')"
    [[ "${actual_hash}" == "${expected_hash}" ]] \
      || die "Checksum mismatch for ${file_name}: expected ${expected_hash}, got ${actual_hash}"
  done < <(parse_signature_files "${known_good_manifest}")

  ensure_expected_package_set
  verify_package_signatures
  write_fallback_manifest "${known_good_manifest}" "${source_aur_manifest_path}"
}

write_fallback_manifest() {
  local known_good_manifest="$1"
  local source_aur_manifest_path="$2"
  local manifest_tmp="${manifest_path}.tmp"
  local package_path

  {
    printf 'built_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'source=known-good\n'
    printf 'fallback_used=true\n'
    printf 'failed_ref_mode=%s\n' "${failed_ref_mode}"
    printf 'known_good_manifest_url=%s/%s\n' "${known_good_url}" "${known_good_manifest_name}"
    printf 'known_good_created_at_utc=%s\n' "$(manifest_value "${known_good_manifest}" created_at_utc)"
    printf 'package_dir=%s\n' "${package_dir}"
    printf '\n[package_bases]\n'
    parse_package_bases "${source_aur_manifest_path}"
    printf '\n[source_inputs]\n'
    parse_source_inputs "${source_aur_manifest_path}"
    printf '\n[package_files]\n'
    while IFS= read -r package_path; do
      sha256sum "${package_path}" | awk -v file_name="${package_path##*/}" '{print $1 "\t" file_name}'
    done < <(
      find "${package_dir}" -maxdepth 1 -type f \
        -name '*.pkg.tar.zst' \
        | sort -V
    )
  } > "${manifest_tmp}"

  mv -f "${manifest_tmp}" "${manifest_path}"
}

main() {
  require_cmd awk
  require_cmd curl
  require_cmd date
  require_cmd find
  require_cmd gpgv
  require_cmd sha256sum
  require_cmd sort
  [[ -r "${package_keyring}" ]] || die "Package keyring not readable: ${package_keyring}"

  configure_known_good_url
  restore_packages
  log "Restored known-good NVIDIA package artifacts under: ${package_dir}"
  log "Wrote fallback manifest: ${manifest_path}"
}

main "$@"
