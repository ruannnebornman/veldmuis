#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
repos_root="${REPOS_ROOT:-${repo_root}/repos}"
package_dir="${VELDMUIS_AUR_PACKAGE_DIR:-${repo_root}/artifacts/aur-packages/current}"
aur_manifest_path="${VELDMUIS_AUR_MANIFEST:-${package_dir}/veldmuis-aur-packages.manifest.txt}"
build_root="${KNOWN_GOOD_BUILD_ROOT:-${RUNNER_TEMP:-/tmp}/veldmuis-known-good-nvidia}"
stage_dir="${build_root}/stage"
manifest_name="${KNOWN_GOOD_NVIDIA_MANIFEST_NAME:-veldmuis-known-good-nvidia-580xx.manifest.txt}"
aur_manifest_name="${R2_AUR_MANIFEST_NAME:-veldmuis-aur-packages.manifest.txt}"
prefix="${KNOWN_GOOD_NVIDIA_PREFIX:-_known-good/nvidia-580xx/current}"
arch="${VELDMUIS_ARCH:-x86_64}"
extra_repo="${VELDMUIS_EXTRA_REPO:-veldmuis-extra}"
signed_package_dir="${VELDMUIS_SIGNED_PACKAGE_DIR:-${repos_root}/${extra_repo}/os/${arch}}"
bucket="${CF_R2_PACKAGE_BUCKET:-}"
account_id="${CF_R2_ACCOUNT_ID:-}"
endpoint="${CF_R2_ENDPOINT_URL:-}"
cache_control="${KNOWN_GOOD_CACHE_CONTROL:-no-store, max-age=0, must-revalidate}"
nvidia_package_set="${VELDMUIS_NVIDIA_580XX_PACKAGE_SET:-${repo_root}/packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh}"

[[ -r "${nvidia_package_set}" ]] || {
  printf '[publish-known-good-nvidia-packages] ERROR: NVIDIA package set not readable: %s\n' "${nvidia_package_set}" >&2
  exit 1
}
# shellcheck source=packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
. "${nvidia_package_set}"

expected_packages=("${veldmuis_nvidia_580xx_repository_packages[@]}")

log() {
  printf '[publish-known-good-nvidia-packages] %s\n' "$*"
}

die() {
  printf '[publish-known-good-nvidia-packages] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

configure_credentials() {
  if [[ -z "${AWS_ACCESS_KEY_ID:-}" && -n "${CF_R2_PACKAGE_ACCESS_KEY_ID:-}" ]]; then
    export AWS_ACCESS_KEY_ID="${CF_R2_PACKAGE_ACCESS_KEY_ID}"
  fi

  if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" && -n "${CF_R2_PACKAGE_SECRET_ACCESS_KEY:-}" ]]; then
    export AWS_SECRET_ACCESS_KEY="${CF_R2_PACKAGE_SECRET_ACCESS_KEY}"
  fi

  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"

  [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || die "Missing AWS_ACCESS_KEY_ID or CF_R2_PACKAGE_ACCESS_KEY_ID"
  [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] || die "Missing AWS_SECRET_ACCESS_KEY or CF_R2_PACKAGE_SECRET_ACCESS_KEY"
}

configure_endpoint() {
  [[ -n "${bucket}" ]] || die "Missing CF_R2_PACKAGE_BUCKET"
  [[ "${bucket}" != "veldmuis-releases" ]] || die "Refusing to use ISO bucket ${bucket}"

  if [[ -z "${endpoint}" ]]; then
    [[ -n "${account_id}" ]] || die "Missing CF_R2_ACCOUNT_ID or CF_R2_ENDPOINT_URL"
    endpoint="https://${account_id}.r2.cloudflarestorage.com"
  fi

  prefix="${prefix#/}"
  prefix="${prefix%/}"
  [[ -n "${prefix}" ]] || die "Known-good prefix resolves to an empty path"
}

manifest_value() {
  local key="$1"

  awk -F '=' -v key="${key}" '$1 == key { print $2; found = 1; exit } END { exit !found }' \
    "${aur_manifest_path}" 2>/dev/null || true
}

is_fallback_manifest() {
  [[ "$(manifest_value fallback_used)" == "true" ]]
}

find_package() {
  local package_name="$1"
  local -a matches=()

  mapfile -t matches < <(
    find "${signed_package_dir}" -maxdepth 1 -type f \
      -name "${package_name}-*.pkg.tar.zst" \
      ! -name '*-debug-*.pkg.tar.zst' \
      | sort -V
  )

  ((${#matches[@]} == 1)) || die "Expected exactly one artifact for ${package_name}, found ${#matches[@]}"
  printf '%s' "${matches[0]}"
}

copy_known_good_files() {
  local package_name package_path

  rm -rf "${stage_dir}"
  mkdir -p "${stage_dir}"

  [[ -r "${aur_manifest_path}" ]] || die "AUR manifest not readable: ${aur_manifest_path}"
  cp -f "${aur_manifest_path}" "${stage_dir}/${aur_manifest_name}"

  for package_name in "${expected_packages[@]}"; do
    package_path="$(find_package "${package_name}")"
    cp -f "${package_path}" "${stage_dir}/"
    [[ -f "${package_path}.sig" ]] || die "Missing package signature: ${package_path}.sig"
    cp -f "${package_path}.sig" "${stage_dir}/"
  done
}

render_manifest() {
  local source_commit="unknown"

  source_commit="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || printf 'unknown')"

  {
    printf 'created_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'source_commit=%s\n' "${source_commit}"
    printf 'cache_prefix=%s\n' "${prefix}"
    printf 'source_aur_manifest=%s\n' "${aur_manifest_name}"
    printf 'fallback_used=false\n'
    printf '\n[package_bases]\n'
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
    ' "${aur_manifest_path}"
    printf '\n[source_inputs]\n'
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
    ' "${aur_manifest_path}"
    printf '\n[package_files]\n'
    find "${stage_dir}" -maxdepth 1 -type f \
      -name '*.pkg.tar.zst' \
      -printf '%f\n' \
      | sort -V \
      | while IFS= read -r file_name; do
          sha256sum "${stage_dir}/${file_name}" | awk -v file_name="${file_name}" '{print $1 "\t" file_name}'
        done
    printf '\n[signature_files]\n'
    find "${stage_dir}" -maxdepth 1 -type f \
      -name '*.pkg.tar.zst.sig' \
      -printf '%f\n' \
      | sort -V \
      | while IFS= read -r file_name; do
          sha256sum "${stage_dir}/${file_name}" | awk -v file_name="${file_name}" '{print $1 "\t" file_name}'
        done
  } > "${stage_dir}/${manifest_name}"
}

upload_known_good() {
  log "Publishing known-good NVIDIA package set to s3://${bucket}/${prefix}"
  aws s3 sync "${stage_dir}" "s3://${bucket}/${prefix}" \
    --delete \
    --cache-control "${cache_control}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors
}

verify_known_good() {
  local file_name

  while IFS= read -r file_name; do
    log "Verifying known-good object: ${prefix}/${file_name}"
    aws s3api head-object \
      --bucket "${bucket}" \
      --key "${prefix}/${file_name}" \
      --endpoint-url "${endpoint}" \
      >/dev/null
  done < <(find "${stage_dir}" -maxdepth 1 -type f -printf '%f\n' | sort)
}

main() {
  require_cmd aws
  require_cmd date
  require_cmd find
  require_cmd git
  require_cmd sha256sum
  require_cmd sort

  [[ -d "${package_dir}" ]] || die "Package artifact directory not found: ${package_dir}"
  [[ -d "${signed_package_dir}" ]] || die "Signed package directory not found: ${signed_package_dir}"
  [[ -r "${aur_manifest_path}" ]] || die "AUR manifest not readable: ${aur_manifest_path}"

  if is_fallback_manifest; then
    log "Skipping known-good update because current package set came from fallback"
    exit 0
  fi

  configure_credentials
  configure_endpoint
  copy_known_good_files
  render_manifest
  upload_known_good
  verify_known_good
  log "Published known-good NVIDIA package set"
}

main "$@"
