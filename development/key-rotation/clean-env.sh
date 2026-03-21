#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
keyring_dir="${repo_root}/packages/veldmuis-keyring"

usage() {
  cat <<'EOF'
Usage:
  clean-env.sh

Behavior:
  - finds any existing Veldmuis signing key in the current GPG home
  - deletes matching public and secret keys
  - removes the local current-signing-key marker
  - records deleted fingerprints for the next key generation step

Environment overrides:
  VELDMUIS_KEY_FPR_FILE       Default: ~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
  VELDMUIS_KEY_OLD_FPRS_FILE  Default: ~/.local/share/veldmuis/keyring-private/last-cleaned-fingerprints.txt
  VELDMUIS_SIGNING_KEY_NAME   Default: Veldmuis Linux Release
  VELDMUIS_SIGNING_KEY_EMAIL  Default: veldmuis@veldmuislinux.org
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

collect_existing_fingerprints() {
  declare -A seen=()
  local fingerprint

  if [[ -f "${marker_file}" ]]; then
    fingerprint="$(tr -d '[:space:]' < "${marker_file}")"
    [[ -n "${fingerprint}" ]] && seen["${fingerprint}"]=1
  fi

  if [[ -f "${keyring_dir}/veldmuis-trusted" ]]; then
    fingerprint="$(awk -F: 'NF { print $1; exit }' "${keyring_dir}/veldmuis-trusted")"
    [[ -n "${fingerprint}" ]] && seen["${fingerprint}"]=1
  fi

  while IFS= read -r fingerprint; do
    [[ -n "${fingerprint}" ]] || continue
    seen["${fingerprint}"]=1
  done < <(key_uid_fingerprints)

  for fingerprint in "${!seen[@]}"; do
    printf '%s\n' "${fingerprint}"
  done | sort -u
}

delete_fingerprint_from_keyring() {
  local fingerprint="$1"

  gpg --batch --yes --delete-secret-keys "${fingerprint}" >/dev/null 2>&1 || true
  gpg --batch --yes --delete-keys "${fingerprint}" >/dev/null 2>&1 || true
}

main() {
  local fingerprints=()
  local fingerprint

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
  cleaned_fingerprints_file="${VELDMUIS_KEY_OLD_FPRS_FILE:-${HOME}/.local/share/veldmuis/keyring-private/last-cleaned-fingerprints.txt}"

  mkdir -p "$(dirname "${cleaned_fingerprints_file}")"

  mapfile -t fingerprints < <(collect_existing_fingerprints)

  if [[ "${#fingerprints[@]}" -eq 0 ]]; then
    rm -f "${marker_file}" "${cleaned_fingerprints_file}"
    printf 'No existing Veldmuis signing key was found in the current GPG home.\n'
    exit 0
  fi

  printf '%s\n' "${fingerprints[@]}" > "${cleaned_fingerprints_file}"

  for fingerprint in "${fingerprints[@]}"; do
    delete_fingerprint_from_keyring "${fingerprint}"
  done

  rm -f "${marker_file}"

  printf 'Deleted %d Veldmuis signing fingerprint(s).\n' "${#fingerprints[@]}"
  for fingerprint in "${fingerprints[@]}"; do
    printf '  %s\n' "${fingerprint}"
  done
  printf 'Recorded deleted fingerprints in: %s\n' "${cleaned_fingerprints_file}"
}

main "$@"
