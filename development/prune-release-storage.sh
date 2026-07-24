#!/usr/bin/env bash

set -euo pipefail

bucket="${CF_R2_BUCKET:-}"
account_id="${CF_R2_ACCOUNT_ID:-}"
endpoint="${CF_R2_ENDPOINT_URL:-}"
prefix="${CF_R2_PREFIX:-iso}"
release_tag="${VELDMUIS_RELEASE_TAG:-}"
dry_run="${RELEASE_STORAGE_PRUNE_DRY_RUN:-0}"
release_root=""
protected_prefix=""

log() {
  printf '[prune-release-storage] %s\n' "$*"
}

die() {
  printf '[prune-release-storage] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_dry_run() {
  [[ "${dry_run}" == "1" || "${dry_run}" == "true" ]]
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

run_aws() {
  if is_dry_run; then
    printf '[prune-release-storage] DRY RUN: aws'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  aws "$@"
}

remove_previous_releases() {
  log "Removing release objects outside protected prefix: ${protected_prefix}"
  run_aws s3 rm "s3://${bucket}/${release_root}/" \
    --recursive \
    --exclude "${release_tag}/*" \
    --endpoint-url "${endpoint}" \
    --only-show-errors
}

verify_previous_releases_removed() {
  local unexpected_keys=""

  is_dry_run && return 0

  unexpected_keys="$(
    aws s3api list-objects-v2 \
      --bucket "${bucket}" \
      --prefix "${release_root}/" \
      --endpoint-url "${endpoint}" \
      --query "Contents[?starts_with(Key, '${protected_prefix}') == \`false\`].Key" \
      --output text
  )"
  if [[ -n "${unexpected_keys}" && "${unexpected_keys}" != "None" ]]; then
    printf '%s\n' "${unexpected_keys}" >&2
    die "Previous release objects remain under ${release_root}/."
  fi

  log "Only ${protected_prefix} may remain under ${release_root}/"
}

main() {
  if ! is_dry_run; then
    require_cmd aws
  fi

  [[ -n "${bucket}" ]] || die "Missing CF_R2_BUCKET."
  [[ "${bucket}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || \
    die "CF_R2_BUCKET is not a valid bucket name: ${bucket}"
  [[ "${release_tag}" =~ ^[0-9]{4}\.[0-9]{2}(\.[0-9]{2}(\.[0-9]+)?)?$ ]] || \
    die "Invalid release tag: ${release_tag}"

  prefix="${prefix#/}"
  prefix="${prefix%/}"
  [[ -n "${prefix}" ]] || die "CF_R2_PREFIX resolves to an empty path."
  [[ "${prefix}" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || \
    die "CF_R2_PREFIX contains unsupported characters: ${prefix}"
  [[ "${prefix}" != *"//"* && "/${prefix}/" != *"/../"* && "/${prefix}/" != *"/./"* ]] || \
    die "CF_R2_PREFIX contains an unsafe path component: ${prefix}"

  if [[ -z "${endpoint}" ]]; then
    [[ -n "${account_id}" ]] || die "Missing CF_R2_ACCOUNT_ID or CF_R2_ENDPOINT_URL."
    endpoint="https://${account_id}.r2.cloudflarestorage.com"
  fi
  endpoint="${endpoint%/}"
  [[ "${endpoint}" =~ ^https:// ]] || die "Release-storage endpoint must use HTTPS."

  release_root="${prefix}/releases"
  protected_prefix="${release_root}/${release_tag}/"
  configure_credentials
  remove_previous_releases
  verify_previous_releases_removed
}

main "$@"
