#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
release_tag="2099.12.31"
temp_root="$(mktemp -d -t veldmuis-publisher-check.XXXXXX)"

cleanup() {
  [[ -n "${temp_root}" && "${temp_root}" == /tmp/veldmuis-publisher-check.* ]] || return 0
  rm -rf -- "${temp_root}"
}
trap cleanup EXIT

write_fixture() {
  local installer="$1"
  local output_root="${temp_root}/${installer}"
  local artifact_stem="veldmuis-${release_tag}-${installer}-x86_64"
  local iso_name="${artifact_stem}.iso"
  local manifest_name="${artifact_stem}.manifest.txt"
  local iso_sha256=""
  local file_name=""
  local -a file_names=(
    "${iso_name}"
    "${artifact_stem}.packages.tsv"
    "${artifact_stem}.spdx"
    "${artifact_stem}.build-inputs.txt"
    "${artifact_stem}.aur-packages.manifest.txt"
    "${manifest_name}.sig"
  )

  mkdir -p "${output_root}"
  printf 'fixture-%s-iso\n' "${installer}" > "${output_root}/${iso_name}"
  iso_sha256="$(sha256sum "${output_root}/${iso_name}" | awk '{ print $1 }')"
  printf '%s  %s\n' "${iso_sha256}" "${iso_name}" > "${output_root}/${iso_name}.sha256"
  for file_name in "${file_names[@]}"; do
    [[ -e "${output_root}/${file_name}" ]] || printf 'fixture\n' > "${output_root}/${file_name}"
  done
  if [[ "${installer}" == "offline" ]]; then
    printf 'fixture\n' > "${output_root}/${artifact_stem}.offline-packages.tsv"
  fi
  {
    printf 'release_tag=%s\n' "${release_tag}"
    printf 'installer=%s\n' "${installer}"
    printf 'iso_name=%s\n' "${iso_name}"
    printf 'sha256=%s\n' "${iso_sha256}"
    printf 'built_at_utc=2099-12-31T00:00:00Z\n'
  } > "${output_root}/${manifest_name}"
}

check_installer() {
  local installer="$1"
  local output_root="${temp_root}/${installer}"
  local output=""
  local iso_name="veldmuis-${release_tag}-${installer}-x86_64.iso"

  write_fixture "${installer}"
  output="$(
    VELDMUIS_RELEASE_OUTPUT_DIR="${output_root}" \
    VELDMUIS_RELEASE_TAG="${release_tag}" \
    VELDMUIS_ISO_MODE="${installer}" \
    CF_R2_BUCKET=fixture-releases \
    CF_R2_ACCOUNT_ID=fixture-account \
    CF_R2_PUBLIC_BASE_URL=https://downloads.example.test/iso \
    R2_RELEASE_DRY_RUN=1 \
      "${script_dir}/publish-r2-release.sh"
  )"

  grep -qF "iso/releases/${release_tag}/${iso_name}" <<<"${output}"
  grep -qF "iso/channels/${installer}.json" <<<"${output}"
  if grep -Eq 's3://fixture-releases/iso/latest[^[:space:]]*[[:space:]]' <<<"${output}"; then
    printf '[check-release-publisher] ERROR: %s dry run writes a legacy latest object.\n' \
      "${installer}" >&2
    exit 1
  fi
}

check_storage_prune() {
  local aws_log="${temp_root}/aws.log"
  local fake_bin="${temp_root}/bin"
  local output=""

  output="$(
    VELDMUIS_RELEASE_TAG="${release_tag}" \
    CF_R2_BUCKET=fixture-releases \
    CF_R2_ACCOUNT_ID=fixture-account \
    CF_R2_PREFIX=iso \
    RELEASE_STORAGE_PRUNE_DRY_RUN=1 \
      "${script_dir}/prune-release-storage.sh"
  )"

  grep -qF "s3://fixture-releases/iso/releases/" <<<"${output}"
  grep -qF -- "--exclude ${release_tag}/\\*" <<<"${output}"
  if grep -qF "iso/channels/" <<<"${output}"; then
    printf '[check-release-publisher] ERROR: release pruning targets channel objects.\n' >&2
    exit 1
  fi

  mkdir -p "${fake_bin}"
  cat > "${fake_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"${AWS_LOG}"
printf '\n' >>"${AWS_LOG}"
if [[ "${1:-}" == "s3api" ]]; then
  printf '%s\n' "${AWS_LIST_OUTPUT:-None}"
fi
EOF
  chmod +x "${fake_bin}/aws"

  PATH="${fake_bin}:${PATH}" \
  AWS_LOG="${aws_log}" \
  AWS_ACCESS_KEY_ID=fixture-access \
  AWS_SECRET_ACCESS_KEY=fixture-secret \
  VELDMUIS_RELEASE_TAG="${release_tag}" \
  CF_R2_BUCKET=fixture-releases \
  CF_R2_ACCOUNT_ID=fixture-account \
  CF_R2_PREFIX=iso \
    "${script_dir}/prune-release-storage.sh" >/dev/null

  grep -qF "s3 rm s3://fixture-releases/iso/releases/ --recursive --exclude ${release_tag}/\\*" \
    "${aws_log}"
  grep -qF "s3api list-objects-v2 --bucket fixture-releases --prefix iso/releases/" \
    "${aws_log}"

  if PATH="${fake_bin}:${PATH}" \
    AWS_LOG="${aws_log}" \
    AWS_LIST_OUTPUT="iso/releases/2099.12.30/old.iso" \
    AWS_ACCESS_KEY_ID=fixture-access \
    AWS_SECRET_ACCESS_KEY=fixture-secret \
    VELDMUIS_RELEASE_TAG="${release_tag}" \
    CF_R2_BUCKET=fixture-releases \
    CF_R2_ACCOUNT_ID=fixture-account \
    CF_R2_PREFIX=iso \
      "${script_dir}/prune-release-storage.sh" >/dev/null 2>&1
  then
    printf '[check-release-publisher] ERROR: release pruning accepted an old remaining object.\n' >&2
    exit 1
  fi

  if VELDMUIS_RELEASE_TAG="${release_tag}" \
    CF_R2_BUCKET=fixture-releases \
    CF_R2_ACCOUNT_ID=fixture-account \
    CF_R2_PREFIX=../iso \
    RELEASE_STORAGE_PRUNE_DRY_RUN=1 \
      "${script_dir}/prune-release-storage.sh" >/dev/null 2>&1
  then
    printf '[check-release-publisher] ERROR: release pruning accepted an unsafe prefix.\n' >&2
    exit 1
  fi
}

check_installer network
check_installer offline
check_storage_prune
printf '[check-release-publisher] Publication plans prune previous releases, protect the current tag, and use small channels.\n'
