#!/usr/bin/env bash

set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
keyring_dir="${VELDMUIS_KEYRING_DIR:-${repo_root}/packages/veldmuis-keyring}"
restore_script_path="${script_dir}/restore-key.sh"

archive_path=""
archive_tmp=""
bundle_root=""
current_fingerprint=""
force=0
passphrase_file=""
stage_parent=""

usage() {
  cat <<'EOF'
Usage:
  backup-key.sh [--output PATH] [--passphrase-file PATH] [--force]

Behavior:
  - verifies the current secret key against the committed trusted fingerprint
  - stages secret material in a mode-0700 temporary directory
  - creates an AES-256 encrypted OpenPGP archive
  - verifies the encrypted archive before publishing it atomically
  - removes plaintext staging files on exit

The command prompts for the archive passphrase during encryption and again
during verification. --passphrase-file is intended for controlled recovery
testing; the file must not be accessible by group or other users.

Environment overrides:
  VELDMUIS_KEY_FPR_FILE        Default: ~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
  VELDMUIS_KEY_BACKUP_ARCHIVE  Default: ~/.local/share/veldmuis/keyring-backup.tar.gpg
  VELDMUIS_KEY_BACKUP_TMPDIR   Default: /dev/shm when writable, otherwise ${TMPDIR:-/tmp}
  VELDMUIS_KEYRING_DIR         Test/recovery override for the public keyring directory
EOF
}

die() {
  printf '[backup-key] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  if [[ -n "${archive_tmp}" && -f "${archive_tmp}" ]]; then
    rm -f -- "${archive_tmp}"
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

trusted_fingerprint() {
  local trusted_file="${keyring_dir}/veldmuis-trusted"

  [[ -r "${trusted_file}" ]] || die "Trusted fingerprint file is missing: ${trusted_file}"
  awk -F: 'NF && $1 !~ /^#/ { print $1; exit }' "${trusted_file}" | normalize_fingerprint
}

public_key_fingerprint() {
  local public_key_file="${keyring_dir}/veldmuis.gpg"

  [[ -r "${public_key_file}" ]] || die "Public keyring is missing: ${public_key_file}"
  gpg --batch --show-keys --with-colons "${public_key_file}" 2>/dev/null | \
    awk -F: '$1 == "fpr" { print $10; exit }' | normalize_fingerprint
}

resolve_current_fingerprint() {
  local marker_fingerprint=""
  local public_fingerprint=""
  local trusted=""

  trusted="$(trusted_fingerprint)"
  validate_fingerprint "${trusted}"

  public_fingerprint="$(public_key_fingerprint)"
  validate_fingerprint "${public_fingerprint}"
  [[ "${public_fingerprint}" == "${trusted}" ]] || \
    die "Committed public key does not match the trusted fingerprint."

  if [[ -f "${marker_file}" ]]; then
    marker_fingerprint="$(normalize_fingerprint < "${marker_file}")"
    validate_fingerprint "${marker_fingerprint}"
    [[ "${marker_fingerprint}" == "${trusted}" ]] || \
      die "Local signing marker does not match the committed trusted fingerprint."
  fi

  gpg --batch --list-secret-keys "${trusted}" >/dev/null 2>&1 || \
    die "Current secret key is not available in GnuPG: ${trusted}"

  current_fingerprint="${trusted}"
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

validate_output_path() {
  local resolved_archive=""
  local resolved_passphrase=""
  local resolved_repo=""

  [[ ! -d "${archive_path}" ]] || die "Backup output is a directory: ${archive_path}"
  [[ ! -L "${archive_path}" ]] || die "Backup output must not be a symlink: ${archive_path}"

  resolved_archive="$(realpath -m -- "${archive_path}")"
  resolved_repo="$(realpath -e -- "${repo_root}")"
  case "${resolved_archive}" in
    "${resolved_repo}"|"${resolved_repo}"/*)
      die "Refusing to write secret-key backup material inside the repository."
      ;;
  esac

  if [[ -n "${passphrase_file}" ]]; then
    resolved_passphrase="$(realpath -e -- "${passphrase_file}")"
    [[ "${resolved_archive}" != "${resolved_passphrase}" ]] || \
      die "Backup output and passphrase file must be different paths."
  fi
}

gpg_passphrase_args() {
  if [[ -n "${passphrase_file}" ]]; then
    printf '%s\n' \
      --batch \
      --pinentry-mode loopback \
      --passphrase-file "${passphrase_file}"
  fi
}

select_temp_root() {
  local candidate="${VELDMUIS_KEY_BACKUP_TMPDIR:-}"

  if [[ -z "${candidate}" && -d /dev/shm && -w /dev/shm ]]; then
    candidate=/dev/shm
  fi
  if [[ -z "${candidate}" ]]; then
    candidate="${TMPDIR:-/tmp}"
  fi

  [[ -d "${candidate}" && -w "${candidate}" ]] || \
    die "Backup temporary directory is not writable: ${candidate}"
  printf '%s\n' "${candidate}"
}

write_restore_instructions() {
  cat > "${bundle_root}/RESTORE-INSTRUCTIONS.md" <<EOF
# Veldmuis Signing-Key Backup

This encrypted archive contains the complete secret key for:

\`${current_fingerprint}\`

Treat every extracted file as secret. Do not extract the archive into a source
checkout, synced folder, or ordinary long-lived directory.

Verify without restoring:

\`\`\`sh
./development/key-rotation/restore-key.sh --verify /path/to/keyring-backup.tar.gpg
\`\`\`

Restore only after verification, on the intended trusted machine:

\`\`\`sh
./development/key-rotation/restore-key.sh --restore /path/to/keyring-backup.tar.gpg
\`\`\`

The restore command imports the key and writes the local fingerprint marker. It
does not overwrite repository files, build packages, publish artifacts, or
rotate trust.
EOF
}

prepare_backup_layout() {
  local gpg_home="${GNUPGHOME:-${HOME}/.gnupg}"
  local revocation_cert="${gpg_home}/openpgp-revocs.d/${current_fingerprint}.rev"
  local manifest_tmp=""
  local temp_root=""

  temp_root="$(select_temp_root)"
  stage_parent="$(mktemp -d -p "${temp_root}" veldmuis-key-backup.XXXXXX)"
  chmod 700 "${stage_parent}"
  bundle_root="${stage_parent}/veldmuis-key-backup"
  install -d -m700 "${bundle_root}/repo-files/packages/veldmuis-keyring"

  [[ -r "${revocation_cert}" ]] || \
    die "Revocation certificate is missing: ${revocation_cert}"

  gpg --batch --yes --armor --export "${current_fingerprint}" \
    > "${bundle_root}/veldmuis-public-key.asc"
  gpg --batch --yes --armor --export-secret-keys "${current_fingerprint}" \
    > "${bundle_root}/veldmuis-private-key.asc"
  [[ -s "${bundle_root}/veldmuis-public-key.asc" ]] || \
    die "Public-key export produced an empty file."
  [[ -s "${bundle_root}/veldmuis-private-key.asc" ]] || \
    die "Secret-key export produced an empty file."
  gpg --batch --export-ownertrust | \
    awk -F: -v wanted="${current_fingerprint}" '$1 == wanted { print }' \
    > "${bundle_root}/ownertrust.txt"
  install -m600 "${revocation_cert}" "${bundle_root}/veldmuis-revocation-cert.rev"
  printf '1\n' > "${bundle_root}/BACKUP-FORMAT"
  printf '%s\n' "${current_fingerprint}" > "${bundle_root}/current-signing-key.fpr"

  for file_name in PKGBUILD veldmuis.gpg veldmuis-trusted veldmuis-revoked \
    veldmuis-keyring.install
  do
    [[ -f "${keyring_dir}/${file_name}" ]] || \
      die "Required keyring file is missing: ${keyring_dir}/${file_name}"
    install -m600 "${keyring_dir}/${file_name}" \
      "${bundle_root}/repo-files/packages/veldmuis-keyring/${file_name}"
  done

  install -m700 "${restore_script_path}" "${bundle_root}/restore-key.sh"
  write_restore_instructions

  manifest_tmp="$(mktemp "${stage_parent}/BACKUP-MANIFEST.sha256.XXXXXX")"
  (
    cd "${bundle_root}"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
  ) > "${manifest_tmp}"
  install -m600 "${manifest_tmp}" "${bundle_root}/BACKUP-MANIFEST.sha256"
  rm -f "${manifest_tmp}"
}

encrypt_archive() {
  local -a passphrase_args=()
  local archive_parent=""

  mapfile -t passphrase_args < <(gpg_passphrase_args)
  archive_parent="$(dirname "${archive_path}")"
  mkdir -p "${archive_parent}"

  [[ ! -e "${archive_path}" || "${force}" == "1" ]] || \
    die "Backup archive already exists; use --force to replace it: ${archive_path}"

  archive_tmp="$(mktemp "${archive_path}.tmp.XXXXXX")"
  chmod 600 "${archive_tmp}"

  tar -C "${stage_parent}" -cf - veldmuis-key-backup | \
    gpg --quiet --no-symkey-cache --cipher-algo AES256 \
      --s2k-digest-algo SHA512 "${passphrase_args[@]}" \
      --symmetric --output - > "${archive_tmp}"
}

verify_encrypted_archive() {
  local -a passphrase_args=()

  mapfile -t passphrase_args < <(gpg_passphrase_args)
  gpg --quiet --no-symkey-cache "${passphrase_args[@]}" \
    --decrypt "${archive_tmp}" | \
    tar -tf - | grep -qx 'veldmuis-key-backup/BACKUP-MANIFEST.sha256'
}

publish_archive() {
  if [[ "${force}" == "1" ]]; then
    mv -f -- "${archive_tmp}" "${archive_path}"
  else
    mv -- "${archive_tmp}" "${archive_path}"
  fi
  archive_tmp=""
  chmod 600 "${archive_path}"
}

parse_args() {
  archive_path="${VELDMUIS_KEY_BACKUP_ARCHIVE:-${HOME}/.local/share/veldmuis/keyring-backup.tar.gpg}"

  while (($# > 0)); do
    case "$1" in
      --output)
        (($# >= 2)) || die "--output requires a path"
        archive_path="$2"
        shift 2
        ;;
      --passphrase-file)
        (($# >= 2)) || die "--passphrase-file requires a path"
        passphrase_file="$2"
        shift 2
        ;;
      --force)
        force=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  trap cleanup EXIT

  require_cmd awk
  require_cmd find
  require_cmd gpg
  require_cmd grep
  require_cmd install
  require_cmd realpath
  require_cmd sha256sum
  require_cmd sort
  require_cmd stat
  require_cmd tar
  require_cmd xargs

  marker_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"

  [[ -d "${keyring_dir}" ]] || die "Keyring directory not found: ${keyring_dir}"
  [[ -x "${restore_script_path}" ]] || \
    die "Restore script not found or not executable: ${restore_script_path}"

  validate_passphrase_file
  validate_output_path
  resolve_current_fingerprint
  prepare_backup_layout
  encrypt_archive
  verify_encrypted_archive
  publish_archive

  printf '[backup-key] Encrypted backup verified and written.\n'
  printf '  Fingerprint: %s\n' "${current_fingerprint}"
  printf '  Archive: %s\n' "${archive_path}"
  printf '  Mode: %s\n' "$(stat -c '%a' "${archive_path}")"
}

main "$@"
