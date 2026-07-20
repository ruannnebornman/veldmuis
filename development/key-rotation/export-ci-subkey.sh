#!/usr/bin/env bash

set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
keyring_dir="${VELDMUIS_KEYRING_DIR:-${repo_root}/packages/veldmuis-keyring}"

current_fingerprint=""
fingerprint_file=""
force=0
notes_file=""
output_dir=""
private_key_file=""
stage_dir=""
verification_summary=""

usage() {
  cat <<'EOF'
Usage:
  export-ci-subkey.sh [--force] [output-dir]

Behavior:
  - requires the local marker, committed trusted fingerprint, and public key to
    identify the same primary key
  - exports signing-subkey secret material without the primary certifying secret
  - verifies the isolated export with a detached-signature test
  - writes files with mode 0600 inside a mode-0700 directory

Existing output files are not replaced unless --force is supplied. Delete the
export directory after configuring and testing the release environment.

Environment overrides:
  VELDMUIS_KEY_FPR_FILE          Default: ~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
  VELDMUIS_CI_SUBKEY_EXPORT_DIR  Default: ~/.local/share/veldmuis/keyring-private/ci-release-secrets
  VELDMUIS_KEYRING_DIR           Test/recovery override for the public keyring directory
EOF
}

die() {
  printf '[export-ci-subkey] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  if [[ -n "${stage_dir}" && -d "${stage_dir}/verify-gnupg" ]] && \
    command -v gpgconf >/dev/null 2>&1
  then
    gpgconf --homedir "${stage_dir}/verify-gnupg" --kill gpg-agent >/dev/null 2>&1 || true
  fi
  if [[ -n "${stage_dir}" && -d "${stage_dir}" ]]; then
    rm -rf -- "${stage_dir}"
  fi
}

normalize_fingerprint() {
  tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

validate_fingerprint() {
  [[ "$1" =~ ^[0-9A-F]{40}$ ]] || die "Invalid OpenPGP fingerprint: $1"
}

primary_fingerprint_from_key() {
  gpg --batch --show-keys --with-colons "$1" 2>/dev/null | \
    awk -F: '$1 == "fpr" { print $10; exit }' | normalize_fingerprint
}

resolve_current_fingerprint() {
  local marker_fingerprint=""
  local public_fingerprint=""
  local trusted_fingerprint=""
  local trusted_file="${keyring_dir}/veldmuis-trusted"

  [[ -r "${trusted_file}" ]] || die "Trusted fingerprint file is missing: ${trusted_file}"
  [[ -r "${keyring_dir}/veldmuis.gpg" ]] || \
    die "Public keyring is missing: ${keyring_dir}/veldmuis.gpg"
  [[ -r "${marker_file}" ]] || die "Current signing marker is missing: ${marker_file}"

  trusted_fingerprint="$(
    awk -F: 'NF && $1 !~ /^#/ { print $1; exit }' "${trusted_file}" | \
      normalize_fingerprint
  )"
  marker_fingerprint="$(normalize_fingerprint < "${marker_file}")"
  public_fingerprint="$(primary_fingerprint_from_key "${keyring_dir}/veldmuis.gpg")"

  validate_fingerprint "${trusted_fingerprint}"
  validate_fingerprint "${marker_fingerprint}"
  validate_fingerprint "${public_fingerprint}"

  [[ "${marker_fingerprint}" == "${trusted_fingerprint}" ]] || \
    die "Local signing marker does not match the committed trusted fingerprint."
  [[ "${public_fingerprint}" == "${trusted_fingerprint}" ]] || \
    die "Committed public key does not match the trusted fingerprint."
  gpg --batch --list-secret-keys "${trusted_fingerprint}" >/dev/null 2>&1 || \
    die "Current secret key is not available in GnuPG: ${trusted_fingerprint}"

  current_fingerprint="${trusted_fingerprint}"
}

prepare_output() {
  local resolved_output=""
  local resolved_repo=""

  [[ ! -L "${output_dir}" ]] || die "Output directory must not be a symlink: ${output_dir}"
  [[ ! -e "${output_dir}" || -d "${output_dir}" ]] || \
    die "Output path is not a directory: ${output_dir}"

  resolved_output="$(realpath -m -- "${output_dir}")"
  resolved_repo="$(realpath -e -- "${repo_root}")"
  case "${resolved_output}" in
    "${resolved_repo}"|"${resolved_repo}"/*)
      die "Refusing to write secret signing material inside the repository."
      ;;
  esac

  install -d -m700 "${output_dir}"

  private_key_file="${output_dir}/VELDMUIS_GPG_PRIVATE_KEY.asc"
  fingerprint_file="${output_dir}/VELDMUIS_GPG_FPR.txt"
  notes_file="${output_dir}/README.md"

  if [[ "${force}" != "1" ]]; then
    for output_file in "${private_key_file}" "${fingerprint_file}" "${notes_file}"; do
      [[ ! -e "${output_file}" ]] || \
        die "Output already exists; use --force to replace it: ${output_file}"
    done
  fi

  stage_dir="$(mktemp -d "${output_dir}/.ci-subkey-export.XXXXXX")"
  chmod 700 "${stage_dir}"
}

export_secret_material() {
  gpg --batch --yes --armor --export-secret-subkeys "${current_fingerprint}" \
    > "${stage_dir}/VELDMUIS_GPG_PRIVATE_KEY.asc"
  printf '%s\n' "${current_fingerprint}" > "${stage_dir}/VELDMUIS_GPG_FPR.txt"

  cat > "${stage_dir}/README.md" <<EOF
# Release Signing-Subkey Export

Use these values in the protected release environment:

- \`VELDMUIS_GPG_PRIVATE_KEY\`: contents of \`VELDMUIS_GPG_PRIVATE_KEY.asc\`
- \`VELDMUIS_GPG_FPR\`: contents of \`VELDMUIS_GPG_FPR.txt\`

The armored export contains secret subkeys only. The primary certifying secret
key is not included. Delete this directory after the release environment has
been configured and a signing workflow has completed successfully.
EOF

  chmod 600 "${stage_dir}/"*
}

verify_export() {
  local verify_home="${stage_dir}/verify-gnupg"
  local verify_input="${stage_dir}/verify-input.txt"
  local verify_signature="${verify_input}.sig"
  local imported_fingerprint=""

  install -d -m700 "${verify_home}"
  GNUPGHOME="${verify_home}" gpg --batch --import \
    "${stage_dir}/VELDMUIS_GPG_PRIVATE_KEY.asc" >/dev/null 2>&1

  imported_fingerprint="$(
    GNUPGHOME="${verify_home}" gpg --batch --list-secret-keys \
      --with-colons --fingerprint 2>/dev/null | \
      awk -F: '$1 == "fpr" { print $10; exit }' | normalize_fingerprint
  )"
  [[ "${imported_fingerprint}" == "${current_fingerprint}" ]] || \
    die "CI subkey export imported with an unexpected primary fingerprint."

  printf 'veldmuis ci signing-subkey verification\n' > "${verify_input}"
  GNUPGHOME="${verify_home}" gpg --batch --yes --pinentry-mode loopback \
    --passphrase '' --local-user "${current_fingerprint}" \
    --detach-sign "${verify_input}" >/dev/null 2>&1

  verification_summary="$(
    GNUPGHOME="${verify_home}" gpg --verify \
      "${verify_signature}" "${verify_input}" 2>&1 | sed -n '1,8p'
  )"

  rm -rf -- "${verify_home}"
  rm -f -- "${verify_input}" "${verify_signature}"
}

publish_export() {
  mv -f -- "${stage_dir}/VELDMUIS_GPG_PRIVATE_KEY.asc" "${private_key_file}"
  mv -f -- "${stage_dir}/VELDMUIS_GPG_FPR.txt" "${fingerprint_file}"
  mv -f -- "${stage_dir}/README.md" "${notes_file}"
}

parse_args() {
  output_dir="${VELDMUIS_CI_SUBKEY_EXPORT_DIR:-${HOME}/.local/share/veldmuis/keyring-private/ci-release-secrets}"

  while (($# > 0)); do
    case "$1" in
      --force)
        force=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --*)
        die "Unknown option: $1"
        ;;
      *)
        output_dir="$1"
        shift
        (($# == 0)) || die "Only one output directory may be supplied."
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  trap cleanup EXIT

  require_cmd awk
  require_cmd gpg
  require_cmd gpgconf
  require_cmd install
  require_cmd mv
  require_cmd realpath
  require_cmd sed

  marker_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"

  resolve_current_fingerprint
  prepare_output
  export_secret_material
  verify_export
  publish_export

  printf '[export-ci-subkey] Exported and verified CI signing material.\n'
  printf '  Fingerprint: %s\n' "${current_fingerprint}"
  printf '  Private subkeys: %s\n' "${private_key_file}"
  printf '  Fingerprint file: %s\n' "${fingerprint_file}"
  printf '  Notes: %s\n' "${notes_file}"
  printf '\nVerification summary:\n%s\n' "${verification_summary}"
}

main "$@"
