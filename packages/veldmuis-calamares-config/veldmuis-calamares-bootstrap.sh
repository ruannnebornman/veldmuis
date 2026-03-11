#!/usr/bin/env bash

set -euo pipefail

target_root="${1:-}"
live_repo_root="/opt/veldmuis/repo"
tmp_pacman_conf=""
log_file="/tmp/veldmuis-calamares-bootstrap.log"

log() {
  printf '[veldmuis-calamares-bootstrap] %s\n' "$*"
}

die() {
  printf '[veldmuis-calamares-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  [[ -n "${tmp_pacman_conf}" ]] && rm -f "${tmp_pacman_conf}"
}

write_pacman_conf() {
  tmp_pacman_conf="$(mktemp -t veldmuis-calamares-pacman.XXXXXX)"
  cp /etc/pacman.conf "${tmp_pacman_conf}"

  cat >>"${tmp_pacman_conf}" <<EOF

[veldmuis-core]
SigLevel = Required DatabaseOptional
Server = file://${live_repo_root}/veldmuis-core/os/\$arch

[veldmuis-extra]
SigLevel = Required DatabaseOptional
Server = file://${live_repo_root}/veldmuis-extra/os/\$arch
EOF
}

main() {
  require_cmd pacstrap
  require_cmd pacman-key

  exec > >(tee -a "${log_file}") 2>&1

  [[ -n "${target_root}" ]] || die "Missing target root argument."
  [[ -d "${target_root}" ]] || die "Target root does not exist: ${target_root}"
  [[ -d "${live_repo_root}/veldmuis-core/os/x86_64" ]] || \
    die "Embedded Veldmuis repo not found at ${live_repo_root}"
  [[ -f /usr/share/pacman/keyrings/veldmuis.gpg ]] || \
    die "Veldmuis keyring is missing from the live environment."

  trap cleanup EXIT
  write_pacman_conf

  if ! pacman-key --list-keys >/dev/null 2>&1; then
    log "Initializing live pacman keyring"
    pacman-key --init
  fi

  log "Ensuring Arch and Veldmuis signing keys are available in the live keyring"
  pacman-key --populate archlinux veldmuis
  pacman-key --updatedb

  log "Installing Veldmuis package stack into ${target_root}"
  pacstrap -C "${tmp_pacman_conf}" "${target_root}" veldmuis-desktop

  if ! grep -qxF 'Include = /etc/pacman.conf.d/veldmuis.conf' "${target_root}/etc/pacman.conf"; then
    printf '\nInclude = /etc/pacman.conf.d/veldmuis.conf\n' >> "${target_root}/etc/pacman.conf"
  fi

  log "Bootstrap complete"
}

main "$@"
