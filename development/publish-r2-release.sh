#!/usr/bin/env bash

set -euo pipefail

output_root="${VELDMUIS_RELEASE_OUTPUT_DIR:-}"
release_tag="${VELDMUIS_RELEASE_TAG:-}"
bucket="${CF_R2_BUCKET:-}"
account_id="${CF_R2_ACCOUNT_ID:-}"
prefix="${CF_R2_PREFIX:-iso}"
public_base="${CF_R2_PUBLIC_BASE_URL:-}"
endpoint="${CF_R2_ENDPOINT_URL:-}"
dry_run="${R2_RELEASE_DRY_RUN:-0}"
immutable_cache_control="${R2_RELEASE_IMMUTABLE_CACHE_CONTROL:-public, max-age=31536000, immutable}"
latest_cache_control="${R2_RELEASE_LATEST_CACHE_CONTROL:-public, max-age=60, must-revalidate}"

declare -a artifact_names=()
declare -a latest_names=()

log() {
  printf '[publish-r2-release] %s\n' "$*"
}

die() {
  printf '[publish-r2-release] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_dry_run() {
  [[ "${dry_run}" == "1" || "${dry_run}" == "true" ]]
}

run_aws() {
  if is_dry_run; then
    printf '[publish-r2-release] DRY RUN: aws'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  aws "$@"
}

configure_credentials() {
  if [[ -z "${AWS_ACCESS_KEY_ID:-}" && -n "${CF_R2_ACCESS_KEY_ID:-}" ]]; then
    export AWS_ACCESS_KEY_ID="${CF_R2_ACCESS_KEY_ID}"
  fi
  if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" && -n "${CF_R2_SECRET_ACCESS_KEY:-}" ]]; then
    export AWS_SECRET_ACCESS_KEY="${CF_R2_SECRET_ACCESS_KEY}"
  fi
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"

  if ! is_dry_run; then
    [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || die "Missing release-storage access key."
    [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] || die "Missing release-storage secret key."
  fi
}

content_type_for() {
  case "$1" in
    *.iso) printf 'application/octet-stream\n' ;;
    *.sig) printf 'application/pgp-signature\n' ;;
    *.tsv) printf 'text/tab-separated-values\n' ;;
    *.spdx) printf 'text/spdx\n' ;;
    *) printf 'text/plain\n' ;;
  esac
}

immutable_key_for() {
  printf '%s/releases/%s/%s\n' "${prefix}" "${release_tag}" "$1"
}

latest_key_for() {
  printf '%s/%s\n' "${prefix}" "$1"
}

upload_immutable_artifact() {
  local file_name="$1"
  local source_path="${output_root}/${file_name}"
  local target_key=""
  local content_type=""

  target_key="$(immutable_key_for "${file_name}")"
  content_type="$(content_type_for "${file_name}")"
  log "Uploading immutable artifact: ${target_key}"
  run_aws s3 cp "${source_path}" "s3://${bucket}/${target_key}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors \
    --cache-control "${immutable_cache_control}" \
    --content-disposition "attachment; filename=\"${file_name}\"" \
    --content-type "${content_type}"
}

copy_latest_alias() {
  local file_name="$1"
  local latest_name="$2"
  local source_key=""
  local target_key=""
  local content_type=""

  source_key="$(immutable_key_for "${file_name}")"
  target_key="$(latest_key_for "${latest_name}")"
  content_type="$(content_type_for "${file_name}")"
  log "Updating latest alias from verified immutable object: ${target_key}"
  run_aws s3 cp "s3://${bucket}/${source_key}" "s3://${bucket}/${target_key}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors \
    --metadata-directive REPLACE \
    --cache-control "${latest_cache_control}" \
    --content-disposition "attachment; filename=\"${file_name}\"" \
    --content-type "${content_type}"
}

bucket_object_size() {
  aws s3api head-object \
    --bucket "${bucket}" \
    --key "$1" \
    --endpoint-url "${endpoint}" \
    --query ContentLength \
    --output text
}

verify_object_size() {
  local key="$1"
  local expected_size="$2"
  local actual_size=""

  actual_size="$(bucket_object_size "${key}")"
  [[ "${actual_size}" == "${expected_size}" ]] || \
    die "Published object has unexpected size: ${key} (${actual_size}, expected ${expected_size})"
}

verify_public_url() {
  local relative_path="$1"

  curl --fail --silent --show-error --location --head \
    "${public_base}/${relative_path}" >/dev/null
}

ensure_immutable_target_absent() {
  local file_name="$1"
  local key=""
  local head_output=""

  key="$(immutable_key_for "${file_name}")"
  if is_dry_run; then
    log "DRY RUN: require immutable target to be absent: ${key}"
    return 0
  fi

  if head_output="$(
    aws s3api head-object \
      --bucket "${bucket}" \
      --key "${key}" \
      --endpoint-url "${endpoint}" 2>&1
  )"; then
    die "Immutable release object already exists and will not be overwritten: ${key}"
  fi

  if ! grep -Eqi '\(404\)|not found|nosuchkey' <<<"${head_output}"; then
    die "Unable to prove immutable release object is absent: ${key}: ${head_output}"
  fi
}

verify_immutable_artifacts() {
  local file_name=""
  local key=""
  local size=""

  for file_name in "${artifact_names[@]}"; do
    key="$(immutable_key_for "${file_name}")"
    size="$(stat -c '%s' "${output_root}/${file_name}")"
    verify_object_size "${key}" "${size}"
    verify_public_url "releases/${release_tag}/${file_name}"
  done
}

verify_latest_aliases() {
  local index=0
  local file_name=""
  local latest_name=""
  local key=""
  local size=""

  for ((index = 0; index < ${#artifact_names[@]}; index++)); do
    file_name="${artifact_names[index]}"
    latest_name="${latest_names[index]}"
    key="$(latest_key_for "${latest_name}")"
    size="$(stat -c '%s' "${output_root}/${file_name}")"
    verify_object_size "${key}" "${size}"
    verify_public_url "${latest_name}"
  done
}

main() {
  local artifact_stem=""
  local index=0
  local file_name=""
  local manifest_name=""

  if ! is_dry_run; then
    require_cmd aws
    require_cmd curl
    require_cmd stat
  fi

  [[ -n "${output_root}" && -d "${output_root}" ]] || \
    die "VELDMUIS_RELEASE_OUTPUT_DIR must name the release output directory."
  [[ "${release_tag}" =~ ^[0-9]{4}\.[0-9]{2}(\.[0-9]{2}(\.[0-9]+)?)?$ ]] || \
    die "Invalid release tag: ${release_tag}"
  [[ -n "${bucket}" ]] || die "Missing CF_R2_BUCKET."
  [[ "${public_base}" =~ ^https:// ]] || die "CF_R2_PUBLIC_BASE_URL must use HTTPS."
  public_base="${public_base%/}"
  prefix="${prefix#/}"
  prefix="${prefix%/}"
  [[ -n "${prefix}" ]] || die "CF_R2_PREFIX resolves to an empty path."
  if [[ -z "${endpoint}" ]]; then
    [[ -n "${account_id}" ]] || die "Missing CF_R2_ACCOUNT_ID or CF_R2_ENDPOINT_URL."
    endpoint="https://${account_id}.r2.cloudflarestorage.com"
  fi

  configure_credentials

  artifact_stem="veldmuis-${release_tag}-x86_64"
  manifest_name="${artifact_stem}.manifest.txt"
  artifact_names=(
    "${artifact_stem}.iso"
    "${artifact_stem}.iso.sha256"
    "${artifact_stem}.packages.tsv"
    "${artifact_stem}.spdx"
    "${artifact_stem}.build-inputs.txt"
    "${artifact_stem}.aur-packages.manifest.txt"
    "${manifest_name}.sig"
    "${manifest_name}"
  )
  latest_names=(
    latest.iso
    latest.iso.sha256
    latest.packages.tsv
    latest.spdx
    latest.build-inputs.txt
    latest.aur-packages.manifest.txt
    latest.manifest.txt.sig
    latest.manifest.txt
  )

  for file_name in "${artifact_names[@]}"; do
    ensure_immutable_target_absent "${file_name}"
  done

  for file_name in "${artifact_names[@]}"; do
    [[ -s "${output_root}/${file_name}" ]] || \
      die "Required release artifact is missing or empty: ${output_root}/${file_name}"
    upload_immutable_artifact "${file_name}"
  done

  if is_dry_run; then
    log "Skipping storage and public verification in dry-run mode."
  else
    verify_immutable_artifacts
  fi

  # The signed manifest is intentionally last. It is the commit point for the
  # latest alias set and points users to immutable release-specific artifacts.
  for ((index = 0; index < ${#artifact_names[@]}; index++)); do
    copy_latest_alias "${artifact_names[index]}" "${latest_names[index]}"
  done

  if is_dry_run; then
    log "Skipping latest-alias verification in dry-run mode."
  else
    verify_latest_aliases
  fi

  log "Published immutable release: ${public_base}/releases/${release_tag}/"
  log "Updated latest manifest last: ${public_base}/latest.manifest.txt"
}

main "$@"
