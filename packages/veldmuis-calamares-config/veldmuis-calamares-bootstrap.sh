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

has_non_loopback_nameserver() {
  local resolver_path="$1"

  awk '
    $1 == "nameserver" && $2 !~ /^(127\.|::1$|0\.0\.0\.0$)/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "${resolver_path}"
}

pick_resolver_source() {
  local candidate

  for candidate in \
    /run/systemd/resolve/resolv.conf \
    /run/NetworkManager/no-stub-resolv.conf \
    /run/NetworkManager/resolv.conf \
    /etc/resolv.conf
  do
    [[ -f "${candidate}" ]] || continue
    if has_non_loopback_nameserver "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
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

prepare_target_root() {
  local resolver_source=""

  install -d -m755 "${target_root}/etc"
  install -Dm644 /dev/null "${target_root}/etc/vconsole.conf"

  if resolver_source="$(pick_resolver_source)"; then
    log "Copying resolver config from ${resolver_source} into ${target_root}"
    install -Dm644 "${resolver_source}" "${target_root}/etc/resolv.conf"
  else
    die "Could not find a non-loopback resolver config in the live environment."
  fi
}

main() {
  require_cmd pacstrap
  require_cmd pacman-key

  exec > >(tee "${log_file}") 2>&1

  [[ -n "${target_root}" ]] || die "Missing target root argument."
  [[ -d "${target_root}" ]] || die "Target root does not exist: ${target_root}"
  [[ -d "${live_repo_root}/veldmuis-core/os/x86_64" ]] || \
    die "Embedded Veldmuis repo not found at ${live_repo_root}"
  [[ -f /usr/share/pacman/keyrings/veldmuis.gpg ]] || \
    die "Veldmuis keyring is missing from the live environment."

  trap cleanup EXIT
  write_pacman_conf
  prepare_target_root

  if ! pacman-key --list-keys >/dev/null 2>&1; then
    log "Initializing live pacman keyring"
    pacman-key --init
  fi

  log "Ensuring Arch and Veldmuis signing keys are available in the live keyring"
  pacman-key --populate archlinux veldmuis
  pacman-key --updatedb

  log "Installing Veldmuis package stack into ${target_root}"
  pacstrap -C "${tmp_pacman_conf}" "${target_root}" veldmuis-desktop

  if [[ -f /etc/pacman.d/mirrorlist ]]; then
    install -Dm644 /etc/pacman.d/mirrorlist "${target_root}/etc/pacman.d/mirrorlist"
  fi

  if ! grep -qxF 'Include = /etc/pacman.conf.d/veldmuis.conf' "${target_root}/etc/pacman.conf"; then
    printf '\nInclude = /etc/pacman.conf.d/veldmuis.conf\n' >> "${target_root}/etc/pacman.conf"
  fi

  log "Bootstrap complete"
}

main "$@"
