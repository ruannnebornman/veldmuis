#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bucket="${CF_R2_BUCKET:-}"
account_id="${CF_R2_ACCOUNT_ID:-}"
endpoint="${CF_R2_ENDPOINT_URL:-}"
cors_file="${R2_RELEASE_CORS_FILE:-${script_dir}/r2-release-cors.json}"

die() {
  printf '[configure-r2-release-cors] ERROR: %s\n' "$*" >&2
  exit 1
}

command -v aws >/dev/null 2>&1 || die "Missing required command: aws"
[[ -n "${bucket}" ]] || die "Missing CF_R2_BUCKET."
[[ -r "${cors_file}" ]] || die "CORS policy is unavailable: ${cors_file}"

if [[ -z "${endpoint}" ]]; then
  [[ -n "${account_id}" ]] || die "Missing CF_R2_ACCOUNT_ID or CF_R2_ENDPOINT_URL."
  endpoint="https://${account_id}.r2.cloudflarestorage.com"
fi

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"
export AWS_REQUEST_CHECKSUM_CALCULATION="WHEN_REQUIRED"

aws s3api put-bucket-cors \
  --bucket "${bucket}" \
  --cors-configuration "file://${cors_file}" \
  --endpoint-url "${endpoint}"

aws s3api get-bucket-cors \
  --bucket "${bucket}" \
  --endpoint-url "${endpoint}" >/dev/null

printf '[configure-r2-release-cors] Applied browser read policy to bucket %s.\n' "${bucket}"
