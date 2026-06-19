#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
repos_root="${REPOS_ROOT:-${repo_root}/repos}"
build_root="${R2_PACKAGE_BUILD_ROOT:-$HOME/.cache/veldmuis/r2-package-repo}"
stage_dir="${build_root}/staging"
arch="${VELDMUIS_ARCH:-x86_64}"
core_repo="${VELDMUIS_CORE_REPO:-veldmuis-core}"
extra_repo="${VELDMUIS_EXTRA_REPO:-veldmuis-extra}"
bucket="${CF_R2_PACKAGE_BUCKET:-}"
account_id="${CF_R2_ACCOUNT_ID:-}"
endpoint="${CF_R2_ENDPOINT_URL:-}"
package_base="${PACKAGE_BASE_URL:-https://packages.veldmuislinux.org}"
manifest_name="${R2_PACKAGE_MANIFEST_NAME:-veldmuis-package-repo.manifest.txt}"
aur_manifest_path="${VELDMUIS_AUR_MANIFEST:-${repo_root}/artifacts/aur-packages/current/veldmuis-aur-packages.manifest.txt}"
aur_manifest_name="${R2_AUR_MANIFEST_NAME:-veldmuis-aur-packages.manifest.txt}"
dry_run="${R2_PACKAGE_DRY_RUN:-0}"
repo_cache_control="${R2_PACKAGE_REPO_CACHE_CONTROL:-public, max-age=31536000, immutable}"
metadata_cache_control="${R2_PACKAGE_METADATA_CACHE_CONTROL:-no-store, max-age=0, must-revalidate}"
root_cache_control="${R2_PACKAGE_ROOT_CACHE_CONTROL:-public, max-age=60, must-revalidate}"

log() {
  printf '[publish-r2-package-repo] %s\n' "$*"
}

die() {
  printf '[publish-r2-package-repo] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

trim_trailing_slash() {
  printf '%s' "${1%/}"
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
  [[ "${bucket}" != "veldmuis-releases" ]] || die "Refusing to publish packages to ISO bucket ${bucket}"

  if [[ -z "${endpoint}" ]]; then
    [[ -n "${account_id}" ]] || die "Missing CF_R2_ACCOUNT_ID or CF_R2_ENDPOINT_URL"
    endpoint="https://${account_id}.r2.cloudflarestorage.com"
  fi
}

require_repo_dir() {
  local repo_name="$1"
  local repo_dir="${repos_root}/${repo_name}/os/${arch}"

  [[ -d "${repo_dir}" ]] || die "Missing built repo directory: ${repo_dir}"
}

validate_repo_files() {
  local repo_name="$1"
  local repo_dir="${repos_root}/${repo_name}/os/${arch}"

  require_repo_dir "${repo_name}"

  [[ -e "${repo_dir}/${repo_name}.db" || -f "${repo_dir}/${repo_name}.db.tar.gz" ]] \
    || die "Missing repo database for ${repo_name}"
  [[ -e "${repo_dir}/${repo_name}.db.sig" || -f "${repo_dir}/${repo_name}.db.tar.gz.sig" ]] \
    || die "Missing repo database signature for ${repo_name}"
  [[ -e "${repo_dir}/${repo_name}.files" || -f "${repo_dir}/${repo_name}.files.tar.gz" ]] \
    || die "Missing repo files database for ${repo_name}"
  [[ -e "${repo_dir}/${repo_name}.files.sig" || -f "${repo_dir}/${repo_name}.files.tar.gz.sig" ]] \
    || die "Missing repo files database signature for ${repo_name}"

  while IFS= read -r -d '' pkg; do
    [[ -f "${pkg}.sig" ]] || die "Missing package signature: ${pkg}.sig"
  done < <(find "${repo_dir}" -type f -name '*.pkg.tar.zst' -print0)
}

materialize_repo_alias() {
  local repo_dir="$1"
  local repo_name="$2"
  local kind="$3"
  local plain="${repo_dir}/${repo_name}.${kind}"
  local compressed="${repo_dir}/${repo_name}.${kind}.tar.gz"
  local plain_sig="${plain}.sig"
  local compressed_sig="${compressed}.sig"

  if [[ ! -e "${plain}" && -f "${compressed}" ]]; then
    cp -f "${compressed}" "${plain}"
  fi

  if [[ ! -e "${plain_sig}" && -f "${compressed_sig}" ]]; then
    cp -f "${compressed_sig}" "${plain_sig}"
  fi

  [[ -f "${plain}" ]] || die "Unable to materialize ${plain}"
  [[ -f "${plain_sig}" ]] || die "Unable to materialize ${plain_sig}"
}

prepare_stage() {
  rm -rf "${stage_dir}"
  mkdir -p "${stage_dir}"

  cp -aL "${repos_root}/${core_repo}" "${stage_dir}/${core_repo}"
  cp -aL "${repos_root}/${extra_repo}" "${stage_dir}/${extra_repo}"

  if [[ -r "${aur_manifest_path}" ]]; then
    cp -f "${aur_manifest_path}" "${stage_dir}/${aur_manifest_name}"
  else
    log "AUR manifest not found, package refresh checks will rebuild next time: ${aur_manifest_path}"
  fi

  materialize_repo_alias "${stage_dir}/${core_repo}/os/${arch}" "${core_repo}" "db"
  materialize_repo_alias "${stage_dir}/${core_repo}/os/${arch}" "${core_repo}" "files"
  materialize_repo_alias "${stage_dir}/${extra_repo}/os/${arch}" "${extra_repo}" "db"
  materialize_repo_alias "${stage_dir}/${extra_repo}/os/${arch}" "${extra_repo}" "files"
}

log_repo_metadata() {
  local repo_name="$1"
  local repo_dir="${stage_dir}/${repo_name}/os/${arch}"

  log "Prepared metadata for ${repo_name}:"
  find "${repo_dir}" -maxdepth 1 -type f \
    \( -name "${repo_name}.db*" -o -name "${repo_name}.files*" \) \
    -printf '  %f\t%s bytes\n' \
    | sort
}

render_index() {
  cat > "${stage_dir}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Veldmuis Package Repository</title>
</head>
<body>
  <main>
    <h1>Veldmuis Package Repository</h1>
    <p>Base URL: <a href="${package_base}">${package_base}</a></p>
    <ul>
      <li><a href="./${core_repo}/os/${arch}/">${core_repo}/os/${arch}/</a></li>
      <li><a href="./${extra_repo}/os/${arch}/">${extra_repo}/os/${arch}/</a></li>
    </ul>
    <p><code>Server = ${package_base}/\$repo/os/\$arch</code></p>
  </main>
</body>
</html>
EOF
}

render_manifest() {
  local commit="unknown"
  local published_at

  published_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  commit="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || printf 'unknown')"

  {
    printf 'published_at=%s\n' "${published_at}"
    printf 'source_commit=%s\n' "${commit}"
    printf 'package_base=%s\n' "${package_base}"
    printf 'bucket=%s\n' "${bucket}"
    printf 'arch=%s\n' "${arch}"
    printf 'repositories=%s,%s\n' "${core_repo}" "${extra_repo}"
    if [[ -f "${stage_dir}/${aur_manifest_name}" ]]; then
      printf 'aur_manifest=%s\n' "${aur_manifest_name}"
    fi
    printf '\n[file_manifest]\n'
    find "${stage_dir}" -type f -printf '%P\t%s\n' | sort
  } > "${stage_dir}/${manifest_name}"
}

is_dry_run() {
  [[ "${dry_run}" == "1" || "${dry_run}" == "true" ]]
}

run_aws() {
  if is_dry_run; then
    printf '[publish-r2-package-repo] DRY RUN: aws'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  aws "$@"
}

sync_repo_prefix() {
  local repo_name="$1"
  local source_dir="${stage_dir}/${repo_name}"
  local target="s3://${bucket}/${repo_name}"

  run_aws s3 sync "${source_dir}" "${target}" \
    --exclude "${repo_name}.db*" \
    --exclude "${repo_name}.files*" \
    --cache-control "${repo_cache_control}" \
    --delete \
    --endpoint-url "${endpoint}" \
    --only-show-errors
}

upload_repo_metadata() {
  local repo_name="$1"
  local repo_dir="${stage_dir}/${repo_name}/os/${arch}"
  local file_name

  # Publish mutable repo metadata only after package payloads finish syncing.
  # Keeping these objects out of the bulk sync reduces the window where clients
  # can see a stale database paired with a newer detached signature.
  while IFS= read -r file_name; do
    upload_file \
      "${repo_dir}/${file_name}" \
      "${repo_name}/os/${arch}/${file_name}" \
      "${metadata_cache_control}"
  done < <(
    find "${repo_dir}" -maxdepth 1 -type f \
      \( -name "${repo_name}.db*" -o -name "${repo_name}.files*" \) \
      -printf '%f\n' \
      | sort
  )
}

upload_file() {
  local source_path="$1"
  local target_key="$2"
  local cache_control="${3:-}"
  local args=(
    s3 cp "${source_path}" "s3://${bucket}/${target_key}"
    --endpoint-url "${endpoint}"
    --only-show-errors
  )

  if [[ -n "${cache_control}" ]]; then
    args+=(--cache-control "${cache_control}")
  fi

  run_aws "${args[@]}"
}

verify_bucket_object() {
  local key="$1"

  log "Verifying bucket object: ${key}"
  aws s3api head-object \
    --bucket "${bucket}" \
    --key "${key}" \
    --endpoint-url "${endpoint}" \
    >/dev/null
}

verify_public_url() {
  local url="$1"

  log "Verifying public URL: ${url}"
  curl --fail --silent --show-error --location --head "${url}" >/dev/null
}

verify_repo_metadata() {
  local repo_name="$1"
  local public_base

  public_base="$(trim_trailing_slash "${package_base}")/${repo_name}/os/${arch}/${repo_name}"

  verify_bucket_object "${repo_name}/os/${arch}/${repo_name}.db"
  verify_bucket_object "${repo_name}/os/${arch}/${repo_name}.db.sig"
  verify_bucket_object "${repo_name}/os/${arch}/${repo_name}.db.tar.gz"
  verify_bucket_object "${repo_name}/os/${arch}/${repo_name}.db.tar.gz.sig"
  verify_bucket_object "${repo_name}/os/${arch}/${repo_name}.files"
  verify_bucket_object "${repo_name}/os/${arch}/${repo_name}.files.sig"
  verify_bucket_object "${repo_name}/os/${arch}/${repo_name}.files.tar.gz"
  verify_bucket_object "${repo_name}/os/${arch}/${repo_name}.files.tar.gz.sig"

  verify_public_url "${public_base}.db"
  verify_public_url "${public_base}.db.sig"
  verify_public_url "${public_base}.files"
  verify_public_url "${public_base}.files.sig"
}

verify_published_repo() {
  local public_root

  public_root="$(trim_trailing_slash "${package_base}")"

  verify_bucket_object "index.html"
  verify_bucket_object "${manifest_name}"
  verify_public_url "${public_root}/index.html"
  verify_public_url "${public_root}/${manifest_name}"

  if [[ -f "${stage_dir}/${aur_manifest_name}" ]]; then
    verify_bucket_object "${aur_manifest_name}"
    verify_public_url "${public_root}/${aur_manifest_name}"
  fi

  verify_repo_metadata "${core_repo}"
  verify_repo_metadata "${extra_repo}"
}

main() {
  require_cmd aws
  require_cmd curl
  require_cmd find
  require_cmd git

  configure_credentials
  configure_endpoint

  validate_repo_files "${core_repo}"
  validate_repo_files "${extra_repo}"

  prepare_stage
  render_index
  render_manifest
  log_repo_metadata "${core_repo}"
  log_repo_metadata "${extra_repo}"

  log "Publishing package repo to bucket ${bucket}"
  log "Endpoint: ${endpoint}"
  log "Package base URL: ${package_base}"
  log "Dry run: ${dry_run}"

  sync_repo_prefix "${core_repo}"
  sync_repo_prefix "${extra_repo}"
  upload_repo_metadata "${core_repo}"
  upload_repo_metadata "${extra_repo}"
  upload_file "${stage_dir}/index.html" "index.html" "${root_cache_control}"
  if [[ -f "${stage_dir}/${aur_manifest_name}" ]]; then
    upload_file "${stage_dir}/${aur_manifest_name}" "${aur_manifest_name}" "${metadata_cache_control}"
  fi
  upload_file "${stage_dir}/${manifest_name}" "${manifest_name}" "${root_cache_control}"

  if is_dry_run; then
    log "Skipping bucket/public verification in dry run mode"
  else
    verify_published_repo
  fi

  log "Published package repo prefixes: ${core_repo}/, ${extra_repo}/"
}

main "$@"
