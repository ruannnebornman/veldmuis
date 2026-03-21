#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  restore-key.sh [repo-root]
  restore-key.sh <backup-dir> [repo-root]

Behavior:
  - imports the Veldmuis signing key from the backup bundle
  - restores the local fingerprint marker used by build-local-repo.sh
  - restores the repo keyring files under packages/veldmuis-keyring
  - optionally rebuilds the veldmuis-keyring package

Environment overrides:
  VELDMUIS_KEY_FPR_FILE          Default: ~/.local/share/veldmuis/keyring-private/current-signing-key.fpr
  VELDMUIS_BUILD_KEYRING_PACKAGE Default: 1
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

prepare_gpg_home() {
  local gpg_home="${GNUPGHOME:-${HOME}/.gnupg}"

  mkdir -p "${gpg_home}"
  chmod 700 "${gpg_home}"
}

resolve_paths() {
  if [[ -f "${script_dir}/veldmuis-private-key.asc" && -f "${script_dir}/current-signing-key.fpr" ]]; then
    backup_root="${script_dir}"
    repo_root="${1:-${HOME}/Documents/veldmuis}"
    return 0
  fi

  backup_root="${1:-}"
  repo_root="${2:-${HOME}/Documents/veldmuis}"

  [[ -n "${backup_root}" ]] || {
    usage >&2
    exit 1
  }
}

verify_backup_bundle() {
  local required_file

  for required_file in \
    "${backup_root}/veldmuis-private-key.asc" \
    "${backup_root}/veldmuis-public-key.asc" \
    "${backup_root}/current-signing-key.fpr" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/PKGBUILD" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis.gpg" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis-trusted" \
    "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis-revoked"
  do
    [[ -f "${required_file}" ]] || {
      printf 'Backup bundle is missing: %s\n' "${required_file}" >&2
      exit 1
    }
  done
}

restore_key_material() {
  gpg --import "${backup_root}/veldmuis-private-key.asc"
  gpg --import "${backup_root}/veldmuis-public-key.asc"

  if [[ -f "${backup_root}/ownertrust.txt" ]]; then
    gpg --import-ownertrust "${backup_root}/ownertrust.txt" || true
  fi
}

restore_marker_file() {
  install -Dm644 "${backup_root}/current-signing-key.fpr" "${marker_file}"
}

restore_repo_files() {
  local repo_keyring_dir="${repo_root}/packages/veldmuis-keyring"

  [[ -d "${repo_keyring_dir}" ]] || {
    printf 'Repo keyring directory not found: %s\n' "${repo_keyring_dir}" >&2
    exit 1
  }

  install -Dm644 "${backup_root}/repo-files/packages/veldmuis-keyring/PKGBUILD" \
    "${repo_keyring_dir}/PKGBUILD"
  install -Dm644 "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis.gpg" \
    "${repo_keyring_dir}/veldmuis.gpg"
  install -Dm644 "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis-trusted" \
    "${repo_keyring_dir}/veldmuis-trusted"
  install -Dm644 "${backup_root}/repo-files/packages/veldmuis-keyring/veldmuis-revoked" \
    "${repo_keyring_dir}/veldmuis-revoked"
}

verify_restored_key() {
  local fingerprint

  fingerprint="$(tr -d '[:space:]' < "${marker_file}")"
  [[ -n "${fingerprint}" ]] || {
    printf 'Fingerprint marker is empty: %s\n' "${marker_file}" >&2
    exit 1
  }

  gpg --list-secret-keys "${fingerprint}" >/dev/null 2>&1 || {
    printf 'Restored secret key not found in GPG keyring: %s\n' "${fingerprint}" >&2
    exit 1
  }
}

maybe_build_keyring_package() {
  local repo_keyring_dir="${repo_root}/packages/veldmuis-keyring"

  [[ "${build_keyring_package}" == "1" ]] || return 0

  require_cmd makepkg
  (
    cd "${repo_keyring_dir}"
    makepkg -f
  )
}

main() {
  local backup_root=""
  local repo_root=""

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  require_cmd gpg
  require_cmd install

  prepare_gpg_home
  resolve_paths "${1:-}" "${2:-}"
  verify_backup_bundle

  marker_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"
  build_keyring_package="${VELDMUIS_BUILD_KEYRING_PACKAGE:-1}"

  restore_key_material
  restore_marker_file
  restore_repo_files
  verify_restored_key
  maybe_build_keyring_package

  printf 'Restored signing key fingerprint: %s\n' "$(tr -d '[:space:]' < "${marker_file}")"
  printf 'Marker file: %s\n' "${marker_file}"
  printf 'Repo keyring restored under: %s\n' "${repo_root}/packages/veldmuis-keyring"
}

main "$@"
