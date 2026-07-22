#!/usr/bin/env bash

set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_repo_root=""
if resolved_repo_root="$(cd "${script_dir}/../.." 2>/dev/null && pwd)"; then
  default_repo_root="${resolved_repo_root}"
fi

action=""
archive_path=""
backup_root=""
confirm_fingerprint=""
expected_fingerprint=""
keyring_dir=""
marker_file=""
passphrase_file=""
repo_root=""
stage_parent=""
verify_home=""
plaintext_tar=""

usage() {
  cat <<'EOF'
Usage:
  restore-key.sh --verify [options] ARCHIVE
  restore-key.sh --restore [options] ARCHIVE

Actions:
  --verify   Decrypt and validate the archive in a temporary directory only.
  --restore  Verify, require exact fingerprint confirmation, import the secret
             key, and write the local signing-fingerprint marker.

Options:
  --passphrase-file PATH       Read the archive passphrase from a protected file.
  --repo-root PATH             Compare the backup with this repository checkout.
  --confirm-fingerprint FPR    Non-interactive exact confirmation for --restore.

The restore action does not overwrite repository files, build packages, update
hosted automation secrets, publish artifacts, revoke keys, or rotate trust.

Environment overrides:
  VELDMUIS_KEY_FPR_FILE  Default: ~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
  VELDMUIS_KEYRING_DIR   Test/recovery override for the public keyring directory
EOF
}

die() {
  printf '[restore-key] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  if [[ -n "${verify_home}" && -d "${verify_home}" ]] && command -v gpgconf >/dev/null 2>&1; then
    gpgconf --homedir "${verify_home}" --kill gpg-agent >/dev/null 2>&1 || true
  fi
  if [[ -n "${stage_parent}" && -d "${stage_parent}" ]]; then
    rm -rf -- "${stage_parent}"
  fi
}

normalize_fingerprint() {
  tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

validate_fingerprint() {
  [[ "$1" =~ ^[0-9A-F]{40}$ ]] || die "Invalid OpenPGP fingerprint: $1"
}

validate_passphrase_file() {
  local permissions=""

  [[ -n "${passphrase_file}" ]] || return 0
  [[ -f "${passphrase_file}" && ! -L "${passphrase_file}" ]] || \
    die "Passphrase file must be a regular, non-symlink file: ${passphrase_file}"
  [[ -s "${passphrase_file}" ]] || die "Passphrase file is empty: ${passphrase_file}"

  permissions="$(stat -c '%a' "${passphrase_file}")"
  (( (8#${permissions} & 077) == 0 )) || \
    die "Passphrase file must not be accessible by group or other users: ${passphrase_file}"
}

gpg_passphrase_args() {
  if [[ -n "${passphrase_file}" ]]; then
    printf '%s\n' \
      --batch \
      --pinentry-mode loopback \
      --passphrase-file "${passphrase_file}"
  fi
}

resolve_repo_paths() {
  if [[ -n "${VELDMUIS_KEYRING_DIR:-}" ]]; then
    keyring_dir="${VELDMUIS_KEYRING_DIR}"
    return 0
  fi

  if [[ -z "${repo_root}" && -n "${default_repo_root}" && \
    -d "${default_repo_root}/packages/veldmuis-keyring" ]]
  then
    repo_root="${default_repo_root}"
  fi
  if [[ -z "${repo_root}" && -d "${PWD}/packages/veldmuis-keyring" ]]; then
    repo_root="${PWD}"
  fi
  if [[ -n "${repo_root}" ]]; then
    keyring_dir="${repo_root}/packages/veldmuis-keyring"
  fi
}

extract_archive() {
  local -a passphrase_args=()
  local temp_root="${TMPDIR:-/tmp}"

  stage_parent="$(mktemp -d -p "${temp_root}" veldmuis-key-restore.XXXXXX)"
  chmod 700 "${stage_parent}"
  plaintext_tar="${stage_parent}/backup.tar"
  mapfile -t passphrase_args < <(gpg_passphrase_args)

  gpg --quiet --no-symkey-cache "${passphrase_args[@]}" \
    --output "${plaintext_tar}" --decrypt "${archive_path}"
  chmod 600 "${plaintext_tar}"

  LC_ALL=C tar --list --file "${plaintext_tar}" | awk '
    !/^veldmuis-key-backup(\/[A-Za-z0-9._-]+)*\/?$/ { exit 1 }
    /(^|\/)\.\.(\/|$)/ { exit 1 }
  ' || die "Archive contains an unsafe member path."

  LC_ALL=C tar --list --verbose --file "${plaintext_tar}" | \
    awk 'substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { exit 1 }' || \
    die "Archive contains a link or special file."

  tar --extract --file "${plaintext_tar}" --directory "${stage_parent}" \
    --keep-old-files --no-overwrite-dir --no-same-owner --no-same-permissions
  rm -f -- "${plaintext_tar}"
  plaintext_tar=""

  backup_root="${stage_parent}/veldmuis-key-backup"
  [[ -d "${backup_root}" ]] || die "Archive does not contain veldmuis-key-backup/."

  [[ "$(find "${stage_parent}" -mindepth 1 -maxdepth 1 -printf '%f\n')" == \
    "veldmuis-key-backup" ]] || die "Archive contains unexpected top-level entries."

  if find "${backup_root}" -type l -o ! -type f ! -type d | grep -q .; then
    die "Archive contains a symlink or special file."
  fi
}

verify_manifest() {
  local calculated_manifest="${stage_parent}/CALCULATED-MANIFEST.sha256"
  local manifest="${backup_root}/BACKUP-MANIFEST.sha256"
  local required_file=""

  for required_file in \
    "${backup_root}/BACKUP-FORMAT" \
    "${backup_root}/RESTORE-INSTRUCTIONS.md" \
    "${backup_root}/restore-key.sh" \
    "${backup_root}/veldmuis-private-key.asc" \
    "${backup_root}/veldmuis-public-key.asc" \
    "${backup_root}/veldmuis-revocation-cert.rev" \
    "${backup_root}/current-signing-key.fpr" \
    "${backup_root}/ownertrust.txt" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/PKGBUILD" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis.gpg" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis-trusted" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis-revoked" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis-keyring.install" \
    "${manifest}"
  do
    [[ -f "${required_file}" && ! -L "${required_file}" ]] || \
      die "Backup bundle is missing a required regular file: ${required_file}"
  done

  awk '
    NF != 2 { exit 1 }
    $1 !~ /^[0-9a-f]{64}$/ { exit 1 }
    $2 !~ /^\.\/[A-Za-z0-9._\/-]+$/ { exit 1 }
    $2 ~ /(^|\/)\.\.(\/|$)/ { exit 1 }
  ' "${manifest}" || die "Backup manifest contains an unsafe or malformed entry."

  (
    cd "${backup_root}"
    find . -type f ! -name BACKUP-MANIFEST.sha256 -print0 | \
      LC_ALL=C sort -z | xargs -0 sha256sum
  ) > "${calculated_manifest}"
  cmp --silent "${manifest}" "${calculated_manifest}" || \
    die "Backup manifest is incomplete or does not match the archive contents."

  [[ "$(tr -d '[:space:]' < "${backup_root}/BACKUP-FORMAT")" == "1" ]] || \
    die "Unsupported backup format version."
}

primary_fingerprint_from_key() {
  gpg --batch --show-keys --with-colons "$1" 2>/dev/null | \
    awk -F: '$1 == "fpr" { print $10; exit }' | normalize_fingerprint
}

verify_fingerprints() {
  local public_fingerprint=""
  local snapshot_public_fingerprint=""
  local snapshot_fingerprint=""

  expected_fingerprint="$(normalize_fingerprint < "${backup_root}/current-signing-key.fpr")"
  validate_fingerprint "${expected_fingerprint}"

  public_fingerprint="$(primary_fingerprint_from_key "${backup_root}/veldmuis-public-key.asc")"
  validate_fingerprint "${public_fingerprint}"
  [[ "${public_fingerprint}" == "${expected_fingerprint}" ]] || \
    die "Backup public key does not match its fingerprint marker."

  snapshot_fingerprint="$(
    awk -F: 'NF && $1 !~ /^#/ { print $1; exit }' \
      "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis-trusted" | \
      normalize_fingerprint
  )"
  validate_fingerprint "${snapshot_fingerprint}"
  [[ "${snapshot_fingerprint}" == "${expected_fingerprint}" ]] || \
    die "Backup keyring snapshot does not trust the backed-up key."

  snapshot_public_fingerprint="$(
    primary_fingerprint_from_key \
      "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis.gpg"
  )"
  validate_fingerprint "${snapshot_public_fingerprint}"
  [[ "${snapshot_public_fingerprint}" == "${expected_fingerprint}" ]] || \
    die "Backup keyring snapshot contains an unexpected public key."

  if [[ -n "${keyring_dir}" ]]; then
    local current_fingerprint=""
    local current_public_fingerprint=""
    [[ -r "${keyring_dir}/veldmuis-trusted" ]] || \
      die "Current repository trusted file is missing: ${keyring_dir}/veldmuis-trusted"
    current_fingerprint="$(
      awk -F: 'NF && $1 !~ /^#/ { print $1; exit }' \
        "${keyring_dir}/veldmuis-trusted" | normalize_fingerprint
    )"
    validate_fingerprint "${current_fingerprint}"
    [[ "${current_fingerprint}" == "${expected_fingerprint}" ]] || \
      die "Backup fingerprint does not match the current repository keyring."

    [[ -r "${keyring_dir}/veldmuis.gpg" ]] || \
      die "Current repository public key is missing: ${keyring_dir}/veldmuis.gpg"
    current_public_fingerprint="$(
      primary_fingerprint_from_key "${keyring_dir}/veldmuis.gpg"
    )"
    validate_fingerprint "${current_public_fingerprint}"
    [[ "${current_public_fingerprint}" == "${expected_fingerprint}" ]] || \
      die "Current repository public key does not match its trusted fingerprint."
  fi
}

verify_ownertrust() {
  awk -F: -v wanted="${expected_fingerprint}" '
    NF {
      if ($1 != wanted || $2 !~ /^[0-9]+$/ || NF > 3) exit 1
      seen++
    }
    END { if (seen > 1) exit 1 }
  ' "${backup_root}/ownertrust.txt" || \
    die "Ownertrust backup contains an unexpected fingerprint or value."
}

verify_secret_key() {
  verify_home="${stage_parent}/verify-gnupg"
  install -d -m700 "${verify_home}"

  GNUPGHOME="${verify_home}" gpg --batch --import \
    "${backup_root}/veldmuis-public-key.asc" \
    "${backup_root}/veldmuis-private-key.asc" >/dev/null 2>&1
  GNUPGHOME="${verify_home}" gpg --batch --list-secret-keys \
    "${expected_fingerprint}" >/dev/null 2>&1 || \
    die "Backup does not contain the expected secret key."
}

verify_backup() {
  extract_archive
  verify_manifest
  verify_fingerprints
  verify_ownertrust
  verify_secret_key

  printf '[restore-key] Encrypted backup verified.\n'
  printf '  Fingerprint: %s\n' "${expected_fingerprint}"
  if [[ -n "${keyring_dir}" ]]; then
    printf '  Repository keyring: %s\n' "${keyring_dir}"
  else
    printf '  Repository comparison: skipped (no repository root supplied)\n'
  fi
}

confirm_restore() {
  local typed_fingerprint=""

  if [[ -n "${confirm_fingerprint}" ]]; then
    typed_fingerprint="$(printf '%s' "${confirm_fingerprint}" | normalize_fingerprint)"
  elif [[ -t 0 ]]; then
    printf 'Type the full fingerprint to restore %s: ' "${expected_fingerprint}" >&2
    read -r typed_fingerprint
    typed_fingerprint="$(printf '%s' "${typed_fingerprint}" | normalize_fingerprint)"
  else
    die "--restore requires an interactive confirmation or --confirm-fingerprint."
  fi

  [[ "${typed_fingerprint}" == "${expected_fingerprint}" ]] || \
    die "Restore fingerprint confirmation did not match."
}

restore_key() {
  local existing_marker=""
  local marker_dir=""

  [[ -n "${keyring_dir}" ]] || \
    die "--restore requires --repo-root or a repository checkout containing the keyring."
  confirm_restore

  if [[ -f "${marker_file}" ]]; then
    existing_marker="$(normalize_fingerprint < "${marker_file}")"
    validate_fingerprint "${existing_marker}"
    [[ "${existing_marker}" == "${expected_fingerprint}" ]] || \
      die "Existing signing marker names a different key: ${existing_marker}"
  fi

  gpg --batch --import "${backup_root}/veldmuis-public-key.asc"
  gpg --batch --import "${backup_root}/veldmuis-private-key.asc"
  if [[ -s "${backup_root}/ownertrust.txt" ]]; then
    gpg --batch --import-ownertrust "${backup_root}/ownertrust.txt"
  fi

  gpg --batch --list-secret-keys "${expected_fingerprint}" >/dev/null 2>&1 || \
    die "Secret key import verification failed."

  marker_dir="$(dirname "${marker_file}")"
  install -d -m700 "${marker_dir}"
  printf '%s\n' "${expected_fingerprint}" > "${marker_file}"
  chmod 600 "${marker_file}"

  printf '[restore-key] Signing key restored locally.\n'
  printf '  Fingerprint: %s\n' "${expected_fingerprint}"
  printf '  Marker: %s\n' "${marker_file}"
  printf '  Repository files were not modified.\n'
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --verify|--restore)
        [[ -z "${action}" ]] || die "Choose exactly one of --verify or --restore."
        action="${1#--}"
        shift
        ;;
      --passphrase-file)
        (($# >= 2)) || die "--passphrase-file requires a path"
        passphrase_file="$2"
        shift 2
        ;;
      --repo-root)
        (($# >= 2)) || die "--repo-root requires a path"
        repo_root="$2"
        shift 2
        ;;
      --confirm-fingerprint)
        (($# >= 2)) || die "--confirm-fingerprint requires a fingerprint"
        confirm_fingerprint="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --*)
        die "Unknown option: $1"
        ;;
      *)
        [[ -z "${archive_path}" ]] || die "Only one backup archive may be supplied."
        archive_path="$1"
        shift
        ;;
    esac
  done

  [[ -n "${action}" ]] || die "Choose --verify or --restore."
  [[ -n "${archive_path}" ]] || die "Missing encrypted backup archive path."
  [[ -f "${archive_path}" && ! -L "${archive_path}" ]] || \
    die "Backup archive must be a regular, non-symlink file: ${archive_path}"
}

main() {
  parse_args "$@"
  trap cleanup EXIT

  require_cmd awk
  require_cmd cmp
  require_cmd find
  require_cmd gpg
  require_cmd gpgconf
  require_cmd grep
  require_cmd install
  require_cmd sha256sum
  require_cmd sort
  require_cmd stat
  require_cmd tar
  require_cmd xargs

  marker_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"

  validate_passphrase_file
  resolve_repo_paths
  verify_backup

  if [[ "${action}" == "restore" ]]; then
    restore_key
  fi
}

main "$@"
