#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
keyring_dir="${repo_root}/packages/veldmuis-keyring"

usage() {
  cat <<'EOF'
Usage:
  export-ci-subkey.sh [output_dir]

Behavior:
  - resolves the current Veldmuis signing key fingerprint
  - exports subkeys-only secret material for CI usage
  - writes the primary fingerprint for VELDMUIS_GPG_FPR
  - verifies the export in a temporary GNUPGHOME with a detached-sign test

Environment overrides:
  VELDMUIS_KEY_FPR_FILE          Default: ~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
  VELDMUIS_CI_SUBKEY_EXPORT_DIR  Default: ~/.local/share/veldmuis/keyring-private/github-release-secrets
  VELDMUIS_SIGNING_KEY_NAME      Default: Veldmuis Linux Release
  VELDMUIS_SIGNING_KEY_EMAIL     Default: veldmuis@veldmuislinux.org
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

key_uid_fingerprints() {
  gpg --list-secret-keys --with-colons --fingerprint 2>/dev/null | \
    awk -F: -v wanted_uid="${key_uid}" '
      /^sec:/ { primary="" }
      /^fpr:/ && primary == "" { primary = $10 }
      /^uid:/ && $10 == wanted_uid && primary != "" {
        print primary
        primary = ""
      }
    '
}

resolve_current_fingerprint() {
  if [[ -f "${marker_file}" ]]; then
    current_fingerprint="$(tr -d '[:space:]' < "${marker_file}")"
  elif [[ -f "${keyring_dir}/veldmuis-trusted" ]]; then
    current_fingerprint="$(awk -F: 'NF { print $1; exit }' "${keyring_dir}/veldmuis-trusted")"
  else
    current_fingerprint="$(key_uid_fingerprints | tail -n 1)"
  fi

  [[ -n "${current_fingerprint}" ]] || {
    printf 'Could not resolve a current Veldmuis signing fingerprint.\n' >&2
    exit 1
  }

  gpg --list-secret-keys "${current_fingerprint}" >/dev/null 2>&1 || {
    printf 'Current signing key not found in GPG: %s\n' "${current_fingerprint}" >&2
    exit 1
  }
}

prepare_output_dir() {
  mkdir -p "${output_dir}"
  chmod 700 "${output_dir}"
}

export_secret_material() {
  private_key_file="${output_dir}/VELDMUIS_GPG_PRIVATE_KEY.asc"
  fingerprint_file="${output_dir}/VELDMUIS_GPG_FPR.txt"
  notes_file="${output_dir}/README.md"

  gpg --batch --yes --armor --export-secret-subkeys "${current_fingerprint}" > "${private_key_file}"
  printf '%s\n' "${current_fingerprint}" > "${fingerprint_file}"

  chmod 600 "${private_key_file}" "${fingerprint_file}"

  cat > "${notes_file}" <<EOF
# GitHub Release Secrets

Use these files for the GitHub \`release\` environment:

- \`VELDMUIS_GPG_PRIVATE_KEY\`: contents of \`VELDMUIS_GPG_PRIVATE_KEY.asc\`
- \`VELDMUIS_GPG_FPR\`: contents of \`VELDMUIS_GPG_FPR.txt\`

Important:

- The armored key export contains secret subkeys only.
- The primary certifying secret key is not included in this export.
- Delete these local files after the GitHub environment is configured and tested.
EOF

  chmod 600 "${notes_file}"
}

verify_export() {
  local verify_home
  local verify_input
  local verify_signature

  verify_home="$(mktemp -d)"
  chmod 700 "${verify_home}"
  verify_input="$(mktemp)"
  verify_signature="${verify_input}.sig"

  GNUPGHOME="${verify_home}" gpg --batch --import "${private_key_file}" >/dev/null 2>&1
  printf 'veldmuis ci signing subkey verification\n' > "${verify_input}"

  GNUPGHOME="${verify_home}" \
    gpg --batch --yes --pinentry-mode loopback --passphrase '' \
    --local-user "${current_fingerprint}" \
    --detach-sign "${verify_input}" >/dev/null 2>&1

  verification_summary="$(
    GNUPGHOME="${verify_home}" \
      gpg --verify "${verify_signature}" "${verify_input}" 2>&1 | sed -n '1,8p'
  )"

  rm -rf "${verify_home}"
  rm -f "${verify_input}" "${verify_signature}"
}

main() {
  current_fingerprint=""
  private_key_file=""
  fingerprint_file=""
  notes_file=""
  verification_summary=""

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  require_cmd gpg

  key_name="${VELDMUIS_SIGNING_KEY_NAME:-Veldmuis Linux Release}"
  key_email="${VELDMUIS_SIGNING_KEY_EMAIL:-veldmuis@veldmuislinux.org}"
  key_uid="${key_name} <${key_email}>"
  marker_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"
  output_dir="${1:-${VELDMUIS_CI_SUBKEY_EXPORT_DIR:-${HOME}/.local/share/veldmuis/keyring-private/github-release-secrets}}"

  resolve_current_fingerprint
  prepare_output_dir
  export_secret_material
  verify_export

  printf 'Exported GitHub signing material.\n'
  printf '  Fingerprint: %s\n' "${current_fingerprint}"
  printf '  Private subkeys file: %s\n' "${private_key_file}"
  printf '  Fingerprint file: %s\n' "${fingerprint_file}"
  printf '  Notes file: %s\n' "${notes_file}"
  printf '\nVerification summary:\n%s\n' "${verification_summary}"
}

main "$@"
