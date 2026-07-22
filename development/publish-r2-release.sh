#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_root="${VELDMUIS_RELEASE_OUTPUT_DIR:-}"
release_tag="${VELDMUIS_RELEASE_TAG:-}"
installer="${VELDMUIS_ISO_MODE:-network}"
bucket="${CF_R2_BUCKET:-}"
account_id="${CF_R2_ACCOUNT_ID:-}"
prefix="${CF_R2_PREFIX:-iso}"
public_base="${CF_R2_PUBLIC_BASE_URL:-}"
endpoint="${CF_R2_ENDPOINT_URL:-}"
release_keyring="${VELDMUIS_RELEASE_KEYRING:-${repo_root}/packages/veldmuis-keyring/veldmuis.gpg}"
dry_run="${R2_RELEASE_DRY_RUN:-0}"
remove_legacy_aliases="${R2_RELEASE_REMOVE_LEGACY_ALIASES:-0}"
immutable_cache_control="${R2_RELEASE_IMMUTABLE_CACHE_CONTROL:-public, max-age=31536000, immutable}"
channel_cache_control="${R2_RELEASE_CHANNEL_CACHE_CONTROL:-public, max-age=60, must-revalidate}"

declare -a artifact_names=()
declare -a legacy_aliases=()
iso_name=""
checksum_name=""
manifest_name=""
signature_name=""
channel_document_path=""

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

cleanup_channel_document() {
  [[ -n "${channel_document_path}" ]] || return 0
  rm -f -- "${channel_document_path}"
}

is_dry_run() {
  [[ "${dry_run}" == "1" || "${dry_run}" == "true" ]]
}

should_remove_legacy_aliases() {
  [[ "${remove_legacy_aliases}" == "1" || "${remove_legacy_aliases}" == "true" ]]
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
    *.json) printf 'application/json\n' ;;
    *.sig) printf 'application/pgp-signature\n' ;;
    *.tsv) printf 'text/tab-separated-values\n' ;;
    *.spdx) printf 'text/spdx\n' ;;
    *) printf 'text/plain\n' ;;
  esac
}

immutable_key_for() {
  printf '%s/releases/%s/%s\n' "${prefix}" "${release_tag}" "$1"
}

channel_key_for() {
  printf '%s/channels/%s.%s\n' "${prefix}" "${installer}" "$1"
}

manifest_value() {
  local key="$1"
  awk -F= -v wanted="${key}" \
    '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' \
    "${output_root}/${manifest_name}"
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

copy_channel_metadata() {
  local file_name="$1"
  local extension="$2"
  local source_key=""
  local target_key=""
  local content_type=""

  source_key="$(immutable_key_for "${file_name}")"
  target_key="$(channel_key_for "${extension}")"
  content_type="$(content_type_for "${file_name}")"
  log "Promoting channel metadata: ${target_key}"
  run_aws s3 cp "s3://${bucket}/${source_key}" "s3://${bucket}/${target_key}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors \
    --metadata-directive REPLACE \
    --cache-control "${channel_cache_control}" \
    --content-disposition inline \
    --content-type "${content_type}"
}

upload_channel_document() {
  local channel_path="$1"
  local target_key=""

  target_key="$(channel_key_for json)"
  log "Promoting channel document last: ${target_key}"
  run_aws s3 cp "${channel_path}" "s3://${bucket}/${target_key}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors \
    --cache-control "${channel_cache_control}" \
    --content-disposition inline \
    --content-type application/json
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

remove_legacy_alias_if_present() {
  local relative_key="$1"
  local key="${prefix}/${relative_key}"
  local head_output=""

  if is_dry_run; then
    log "DRY RUN: remove legacy mutable alias if present: ${key}"
    return 0
  fi

  if head_output="$(
    aws s3api head-object \
      --bucket "${bucket}" \
      --key "${key}" \
      --endpoint-url "${endpoint}" 2>&1
  )"; then
    log "Removing legacy mutable alias: ${key}"
    aws s3api delete-object \
      --bucket "${bucket}" \
      --key "${key}" \
      --endpoint-url "${endpoint}" >/dev/null
    if head_output="$(
      aws s3api head-object \
        --bucket "${bucket}" \
        --key "${key}" \
        --endpoint-url "${endpoint}" 2>&1
    )"; then
      die "Legacy mutable alias still exists after deletion: ${key}"
    fi
    grep -Eqi '\(404\)|not found|nosuchkey' <<<"${head_output}" || \
      die "Unable to verify legacy alias deletion for ${key}: ${head_output}"
    return 0
  fi

  grep -Eqi '\(404\)|not found|nosuchkey' <<<"${head_output}" || \
    die "Unable to inspect legacy alias ${key}: ${head_output}"
}

verify_local_artifacts() {
  local expected_sha256=""
  local checksum_sha256=""
  local checksum_file_name=""

  for file_name in "${artifact_names[@]}"; do
    [[ -s "${output_root}/${file_name}" ]] || \
      die "Required release artifact is missing or empty: ${output_root}/${file_name}"
  done

  is_dry_run && return 0

  expected_sha256="$(sha256sum "${output_root}/${iso_name}" | awk '{ print $1 }')"
  read -r checksum_sha256 checksum_file_name < "${output_root}/${checksum_name}"
  [[ "${checksum_sha256}" == "${expected_sha256}" && "${checksum_file_name}" == "${iso_name}" ]] || \
    die "ISO checksum file does not match ${iso_name}."
  [[ "$(manifest_value release_tag)" == "${release_tag}" ]] || \
    die "Signed manifest release tag does not match ${release_tag}."
  [[ "$(manifest_value installer)" == "${installer}" ]] || \
    die "Signed manifest installer does not match ${installer}."
  [[ "$(manifest_value iso_name)" == "${iso_name}" ]] || \
    die "Signed manifest ISO name does not match ${iso_name}."
  [[ "$(manifest_value sha256)" == "${expected_sha256}" ]] || \
    die "Signed manifest ISO checksum does not match ${iso_name}."
  gpgv --keyring "${release_keyring}" \
    "${output_root}/${signature_name}" "${output_root}/${manifest_name}" >/dev/null
}

render_channel_document() {
  local channel_path="$1"
  local iso_sha256=""
  local iso_bytes=""
  local built_at=""
  local immutable_base=""

  iso_sha256="$(manifest_value sha256)"
  iso_bytes="$(stat -c '%s' "${output_root}/${iso_name}")"
  built_at="$(manifest_value built_at_utc)"
  immutable_base="${public_base}/releases/${release_tag}"

  cat > "${channel_path}" <<EOF
{
  "schema_version": 1,
  "channel": "stable",
  "installer": "${installer}",
  "release_tag": "${release_tag}",
  "published_at": "${built_at}",
  "iso": {
    "name": "${iso_name}",
    "url": "${immutable_base}/${iso_name}",
    "bytes": ${iso_bytes},
    "sha256": "${iso_sha256}",
    "checksum_url": "${immutable_base}/${checksum_name}"
  },
  "manifest": {
    "url": "${immutable_base}/${manifest_name}",
    "signature_url": "${immutable_base}/${signature_name}"
  }
}
EOF
}

verify_published_artifacts() {
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

verify_channel() {
  local channel_path="$1"
  local channel_body=""

  verify_object_size "$(channel_key_for manifest.txt.sig)" \
    "$(stat -c '%s' "${output_root}/${signature_name}")"
  verify_object_size "$(channel_key_for manifest.txt)" \
    "$(stat -c '%s' "${output_root}/${manifest_name}")"
  verify_object_size "$(channel_key_for json)" "$(stat -c '%s' "${channel_path}")"
  verify_public_url "channels/${installer}.manifest.txt.sig"
  verify_public_url "channels/${installer}.manifest.txt"
  channel_body="$(curl --fail --silent --show-error \
    "${public_base}/channels/${installer}.json?release=${release_tag}")"
  grep -qF "\"release_tag\": \"${release_tag}\"" <<<"${channel_body}" || \
    die "Public ${installer} channel does not name release ${release_tag}."
}

main() {
  local artifact_stem=""
  local file_name=""

  if ! is_dry_run; then
    require_cmd aws
    require_cmd curl
    require_cmd gpgv
    require_cmd sha256sum
    require_cmd stat
  fi

  [[ -n "${output_root}" && -d "${output_root}" ]] || \
    die "VELDMUIS_RELEASE_OUTPUT_DIR must name the release output directory."
  [[ "${release_tag}" =~ ^[0-9]{4}\.[0-9]{2}(\.[0-9]{2}(\.[0-9]+)?)?$ ]] || \
    die "Invalid release tag: ${release_tag}"
  case "${installer}" in
    network|offline) ;;
    *) die "VELDMUIS_ISO_MODE must be network or offline, got: ${installer}" ;;
  esac
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

  artifact_stem="veldmuis-${release_tag}-${installer}-x86_64"
  iso_name="${artifact_stem}.iso"
  checksum_name="${iso_name}.sha256"
  manifest_name="${artifact_stem}.manifest.txt"
  signature_name="${manifest_name}.sig"
  artifact_names=(
    "${iso_name}"
    "${checksum_name}"
    "${artifact_stem}.packages.tsv"
    "${artifact_stem}.spdx"
    "${artifact_stem}.build-inputs.txt"
    "${artifact_stem}.aur-packages.manifest.txt"
    "${signature_name}"
    "${manifest_name}"
  )
  if [[ "${installer}" == "offline" ]]; then
    artifact_names+=("${artifact_stem}.offline-packages.tsv")
    legacy_aliases=(
      latest-offline.iso
      latest-offline.iso.sha256
      latest-offline.manifest.txt
      latest-offline.manifest.txt.sig
      offline/latest.iso
      offline/latest.iso.sha256
      offline/latest.manifest.txt
      offline/latest.manifest.txt.sig
    )
  else
    legacy_aliases=(
      latest.iso
      latest.iso.sha256
      latest.packages.tsv
      latest.spdx
      latest.build-inputs.txt
      latest.aur-packages.manifest.txt
      latest.manifest.txt.sig
      latest.manifest.txt
    )
  fi

  verify_local_artifacts
  for file_name in "${artifact_names[@]}"; do
    ensure_immutable_target_absent "${file_name}"
  done
  for file_name in "${artifact_names[@]}"; do
    upload_immutable_artifact "${file_name}"
  done

  if is_dry_run; then
    log "Skipping storage and public verification in dry-run mode."
  else
    verify_published_artifacts
  fi

  channel_document_path="$(mktemp -t "veldmuis-${installer}-channel.XXXXXX.json")"
  trap cleanup_channel_document EXIT
  render_channel_document "${channel_document_path}"

  # Promote the signature before the manifest so an interrupted update fails
  # closed. The small JSON document is the final channel commit point.
  copy_channel_metadata "${signature_name}" manifest.txt.sig
  copy_channel_metadata "${manifest_name}" manifest.txt
  upload_channel_document "${channel_document_path}"

  if is_dry_run; then
    log "Skipping channel verification in dry-run mode."
  else
    verify_channel "${channel_document_path}"
  fi

  if should_remove_legacy_aliases; then
    for file_name in "${legacy_aliases[@]}"; do
      remove_legacy_alias_if_present "${file_name}"
    done
  fi

  log "Published immutable ${installer} release: ${public_base}/releases/${release_tag}/${iso_name}"
  log "Promoted ${installer} channel: ${public_base}/channels/${installer}.json"
}

main "$@"
