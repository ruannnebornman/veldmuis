#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
keyring_dir="${repo_root}/packages/veldmuis-keyring"

usage() {
  cat <<'EOF'
Usage:
  new-key-gen.sh

Behavior:
  - requires a clean Veldmuis key environment
  - generates a new non-interactive signing key
  - updates packages/veldmuis-keyring to trust the new key
  - refreshes the local fingerprint marker for repo builds
  - rebuilds the veldmuis-keyring package

Run clean-env.sh first if an old Veldmuis key exists.

Environment overrides:
  VELDMUIS_KEY_FPR_FILE          Default: ~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
  VELDMUIS_KEY_OLD_FPRS_FILE     Default: ~/.local/share/veldmuis/keyring-private/last-cleaned-fingerprints.txt
  VELDMUIS_SIGNING_KEY_NAME      Default: Veldmuis Linux Release
  VELDMUIS_SIGNING_KEY_EMAIL     Default: veldmuis@veldmuislinux.org
  VELDMUIS_SIGNING_KEY_EXPIRE    Default: 5y
  VELDMUIS_BUILD_KEYRING_PACKAGE Default: 1
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

ensure_clean_env() {
  local existing=()

  mapfile -t existing < <(key_uid_fingerprints)
  if [[ "${#existing[@]}" -gt 0 ]]; then
    printf 'Existing Veldmuis signing key(s) are still present in GPG.\n' >&2
    for fingerprint in "${existing[@]}"; do
      printf '  %s\n' "${fingerprint}" >&2
    done
    printf 'Run %s first.\n' "${script_dir}/clean-env.sh" >&2
    exit 1
  fi
}

prepare_gpg_home() {
  local gpg_home="${GNUPGHOME:-${HOME}/.gnupg}"

  mkdir -p "${gpg_home}"
  chmod 700 "${gpg_home}"
  mkdir -p "${gpg_home}/private-keys-v1.d"
  chmod 700 "${gpg_home}/private-keys-v1.d"
  mkdir -p "${gpg_home}/openpgp-revocs.d"
  chmod 700 "${gpg_home}/openpgp-revocs.d"
  mkdir -p "$(dirname "${marker_file}")"
}

load_old_fingerprints() {
  declare -A seen=()
  local fingerprint

  if [[ -f "${keyring_dir}/veldmuis-trusted" ]]; then
    fingerprint="$(awk -F: 'NF { print $1; exit }' "${keyring_dir}/veldmuis-trusted")"
    [[ -n "${fingerprint}" ]] && seen["${fingerprint}"]=1
  fi

  if [[ -f "${cleaned_fingerprints_file}" ]]; then
    while IFS= read -r fingerprint; do
      [[ -n "${fingerprint}" ]] || continue
      seen["${fingerprint}"]=1
    done < "${cleaned_fingerprints_file}"
  fi

  if [[ -f "${marker_file}" ]]; then
    fingerprint="$(tr -d '[:space:]' < "${marker_file}")"
    [[ -n "${fingerprint}" ]] && seen["${fingerprint}"]=1
  fi

  for fingerprint in "${!seen[@]}"; do
    printf '%s\n' "${fingerprint}"
  done | sort -u
}

generate_new_key() {
  local batch_file

  batch_file="$(mktemp -t veldmuis-signing-key.XXXXXX)"
  trap 'rm -f "${batch_file}"' RETURN

  cat >"${batch_file}" <<EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: cert
Subkey-Type: eddsa
Subkey-Curve: ed25519
Subkey-Usage: sign
Name-Real: ${key_name}
Name-Email: ${key_email}
Expire-Date: ${key_expire}
%commit
EOF

  gpg --batch --generate-key "${batch_file}"
  rm -f "${batch_file}"
  trap - RETURN
}

resolve_new_fingerprint() {
  new_fingerprint="$(key_uid_fingerprints | tail -n 1)"
  [[ -n "${new_fingerprint}" ]] || {
    printf 'Failed to resolve new signing key fingerprint.\n' >&2
    exit 1
  }
}

append_revoked_fingerprints() {
  local fingerprint

  touch "${keyring_dir}/veldmuis-revoked"

  for fingerprint in "${old_fingerprints[@]}"; do
    [[ -n "${fingerprint}" ]] || continue
    [[ "${fingerprint}" == "${new_fingerprint}" ]] && continue
    if ! grep -qxF "${fingerprint}" "${keyring_dir}/veldmuis-revoked"; then
      printf '%s\n' "${fingerprint}" >> "${keyring_dir}/veldmuis-revoked"
    fi
  done
}

update_repo_keyring_files() {
  gpg --batch --yes --export "${new_fingerprint}" > "${keyring_dir}/veldmuis.gpg"
  printf '%s:6:\n' "${new_fingerprint}" > "${keyring_dir}/veldmuis-trusted"
  append_revoked_fingerprints
}

update_local_marker() {
  install -Dm644 /dev/null "${marker_file}"
  printf '%s\n' "${new_fingerprint}" > "${marker_file}"
}

refresh_keyring_pkgbuild_checksums() {
  local gpg_sum
  local trusted_sum
  local revoked_sum
  local tmp_pkgbuild

  gpg_sum="$(sha256sum "${keyring_dir}/veldmuis.gpg" | awk '{print $1}')"
  trusted_sum="$(sha256sum "${keyring_dir}/veldmuis-trusted" | awk '{print $1}')"
  revoked_sum="$(sha256sum "${keyring_dir}/veldmuis-revoked" | awk '{print $1}')"
  tmp_pkgbuild="$(mktemp -t veldmuis-keyring-pkgbuild.XXXXXX)"

  awk \
    -v gpg_sum="${gpg_sum}" \
    -v trusted_sum="${trusted_sum}" \
    -v revoked_sum="${revoked_sum}" \
    '
      BEGIN { in_sums = 0 }
      /^sha256sums=\(/ {
        print "sha256sums=("
        print "  \"" gpg_sum "\""
        print "  \"" trusted_sum "\""
        print "  \"" revoked_sum "\""
        print ")"
        in_sums = 1
        next
      }
      in_sums {
        if (/^\)/) {
          in_sums = 0
        }
        next
      }
      { print }
    ' "${keyring_dir}/PKGBUILD" > "${tmp_pkgbuild}"

  mv -f "${tmp_pkgbuild}" "${keyring_dir}/PKGBUILD"
}

maybe_build_keyring_package() {
  [[ "${build_keyring_package}" == "1" ]] || return 0
  require_cmd makepkg
  (
    cd "${keyring_dir}"
    makepkg -f
  )
}

main() {
  old_fingerprints=()
  new_fingerprint=""

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  require_cmd gpg
  require_cmd install
  require_cmd sha256sum

  key_name="${VELDMUIS_SIGNING_KEY_NAME:-Veldmuis Linux Release}"
  key_email="${VELDMUIS_SIGNING_KEY_EMAIL:-veldmuis@veldmuislinux.org}"
  key_uid="${key_name} <${key_email}>"
  key_expire="${VELDMUIS_SIGNING_KEY_EXPIRE:-5y}"
  marker_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"
  cleaned_fingerprints_file="${VELDMUIS_KEY_OLD_FPRS_FILE:-${HOME}/.local/share/veldmuis/keyring-private/last-cleaned-fingerprints.txt}"
  build_keyring_package="${VELDMUIS_BUILD_KEYRING_PACKAGE:-1}"

  [[ -d "${keyring_dir}" ]] || {
    printf 'Keyring directory not found: %s\n' "${keyring_dir}" >&2
    exit 1
  }

  prepare_gpg_home
  ensure_clean_env
  mapfile -t old_fingerprints < <(load_old_fingerprints)
  generate_new_key
  resolve_new_fingerprint
  update_repo_keyring_files
  update_local_marker
  refresh_keyring_pkgbuild_checksums
  maybe_build_keyring_package
  rm -f "${cleaned_fingerprints_file}"

  printf 'New signing fingerprint: %s\n' "${new_fingerprint}"
  printf 'Marker file: %s\n' "${marker_file}"
}

main "$@"
