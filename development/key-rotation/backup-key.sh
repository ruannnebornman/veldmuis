#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
keyring_dir="${repo_root}/packages/veldmuis-keyring"
restore_script_path="${script_dir}/restore-key.sh"

usage() {
  cat <<'EOF'
Usage:
  backup-key.sh

Behavior:
  - exports the current Veldmuis signing key and ownertrust
  - copies the repo keyring files and local marker file
  - writes restore instructions
  - creates a backup folder and zip

Environment overrides:
  VELDMUIS_KEY_FPR_FILE      Default: ~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
  VELDMUIS_KEY_BACKUP_DIR    Default: ~/Documents/backup key
  VELDMUIS_KEY_BACKUP_ZIP    Default: ~/Documents/backup key.zip
  VELDMUIS_SIGNING_KEY_NAME  Default: Veldmuis Linux Release
  VELDMUIS_SIGNING_KEY_EMAIL Default: veldmuis@veldmuislinux.org
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

prepare_backup_layout() {
  mkdir -p "${backup_dir}"
  rm -rf "${backup_dir:?}/"*

  mkdir -p "${backup_dir}/repo-files/packages/veldmuis-keyring"
  mkdir -p "${backup_dir}/home-files/.local/share/veldmuis/keyring-private"

  gpg --batch --yes --armor --export "${current_fingerprint}" > "${backup_dir}/veldmuis-public-key.asc"
  gpg --batch --yes --armor --export-secret-keys "${current_fingerprint}" > "${backup_dir}/veldmuis-private-key.asc"
  gpg --export-ownertrust > "${backup_dir}/ownertrust.txt"
  cp -f "${GNUPGHOME:-${HOME}/.gnupg}/openpgp-revocs.d/${current_fingerprint}.rev" \
    "${backup_dir}/veldmuis-revocation-cert.rev"

  cp -f "${keyring_dir}/veldmuis.gpg" "${backup_dir}/veldmuis.gpg"
  cp -f "${keyring_dir}/veldmuis-trusted" "${backup_dir}/veldmuis-trusted"
  cp -f "${keyring_dir}/veldmuis-revoked" "${backup_dir}/veldmuis-revoked"
  cp -f "${marker_file}" "${backup_dir}/current-signing-key.fpr"

  cp -f "${keyring_dir}/PKGBUILD" "${backup_dir}/repo-files/packages/veldmuis-keyring/PKGBUILD"
  cp -f "${keyring_dir}/veldmuis.gpg" "${backup_dir}/repo-files/packages/veldmuis-keyring/veldmuis.gpg"
  cp -f "${keyring_dir}/veldmuis-trusted" "${backup_dir}/repo-files/packages/veldmuis-keyring/veldmuis-trusted"
  cp -f "${keyring_dir}/veldmuis-revoked" "${backup_dir}/repo-files/packages/veldmuis-keyring/veldmuis-revoked"
  cp -f "${marker_file}" "${backup_dir}/home-files/.local/share/veldmuis/keyring-private/current-signing-key.fpr"

  install -Dm755 "${restore_script_path}" "${backup_dir}/restore-key.sh"
  write_restore_instructions
}

write_restore_instructions() {
  cat >"${backup_dir}/RESTORE-INSTRUCTIONS.md" <<EOF
# Veldmuis Signing Key Backup

This backup bundle contains the current Veldmuis release signing key and everything needed to restore it on another machine.

Current signing fingerprint:

\`${current_fingerprint}\`

Important:

- \`veldmuis-private-key.asc\` is the private signing key.
- The key is intentionally unencrypted so local build scripts can sign packages non-interactively.
- Store this backup on an encrypted disk or another secure location.

## Fast Restore

1. Clone the Veldmuis repo on the new machine.
2. Extract this zip somewhere.
3. Run:

\`\`\`bash
cd /path/to/extracted/backup\ key
./restore-key.sh ~/Documents/veldmuis
\`\`\`

That will:

- import the private and public keys into GnuPG
- restore the local fingerprint marker file
- copy the repo keyring files into \`packages/veldmuis-keyring\`
- rebuild the \`veldmuis-keyring\` package

## Manual Restore Paths

- Repo files go in:
  - \`packages/veldmuis-keyring/PKGBUILD\`
  - \`packages/veldmuis-keyring/veldmuis.gpg\`
  - \`packages/veldmuis-keyring/veldmuis-trusted\`
  - \`packages/veldmuis-keyring/veldmuis-revoked\`
- Local marker file goes in:
  - \`~/.local/share/veldmuis/keyring-private/current-signing-key.fpr\`

## Files In This Bundle

- \`veldmuis-private-key.asc\`
- \`veldmuis-public-key.asc\`
- \`veldmuis-revocation-cert.rev\`
- \`current-signing-key.fpr\`
- \`ownertrust.txt\`
- \`repo-files/\`
- \`home-files/\`
- \`restore-key.sh\`

## Rebuild Command After Restore

\`\`\`bash
cd ~/Documents/veldmuis
./development/rebuild-iso-usb.sh veldmuis-keyring veldmuis-calamares-config
\`\`\`
EOF
}

write_backup_zip() {
  local backup_parent
  local backup_name

  backup_parent="$(dirname "${backup_dir}")"
  backup_name="$(basename "${backup_dir}")"

  mkdir -p "${backup_parent}"
  rm -f "${backup_zip}"
  (
    cd "${backup_parent}"
    zip -r "${backup_zip}" "${backup_name}"
  )
}

main() {
  current_fingerprint=""

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  require_cmd gpg
  require_cmd install
  require_cmd zip

  key_name="${VELDMUIS_SIGNING_KEY_NAME:-Veldmuis Linux Release}"
  key_email="${VELDMUIS_SIGNING_KEY_EMAIL:-veldmuis@veldmuislinux.org}"
  key_uid="${key_name} <${key_email}>"
  marker_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"
  backup_dir="${VELDMUIS_KEY_BACKUP_DIR:-${HOME}/Documents/backup key}"
  backup_zip="${VELDMUIS_KEY_BACKUP_ZIP:-${HOME}/Documents/backup key.zip}"

  [[ -d "${keyring_dir}" ]] || {
    printf 'Keyring directory not found: %s\n' "${keyring_dir}" >&2
    exit 1
  }
  [[ -x "${restore_script_path}" ]] || {
    printf 'Restore script not found or not executable: %s\n' "${restore_script_path}" >&2
    exit 1
  }
  [[ -f "${marker_file}" ]] || {
    printf 'Current signing marker not found: %s\n' "${marker_file}" >&2
    exit 1
  }

  resolve_current_fingerprint
  prepare_backup_layout
  write_backup_zip

  printf 'Backed up signing fingerprint: %s\n' "${current_fingerprint}"
  printf 'Backup directory: %s\n' "${backup_dir}"
  printf 'Backup zip: %s\n' "${backup_zip}"
}

main "$@"
