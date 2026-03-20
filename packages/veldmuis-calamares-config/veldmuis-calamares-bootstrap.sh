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

  # The installer should favor reliability over throughput on weak Wi-Fi.
  # Multiple concurrent downloads and pacman's low-speed timeout have caused
  # large desktop installs to fail on bare metal.
  if grep -q '^ParallelDownloads' "${tmp_pacman_conf}"; then
    sed -i 's/^ParallelDownloads.*/ParallelDownloads = 1/' "${tmp_pacman_conf}"
  else
    sed -i '/^\[options\]/a ParallelDownloads = 1' "${tmp_pacman_conf}"
  fi

  if ! grep -q '^DisableDownloadTimeout$' "${tmp_pacman_conf}"; then
    sed -i '/^\[options\]/a DisableDownloadTimeout' "${tmp_pacman_conf}"
  fi

  cat >>"${tmp_pacman_conf}" <<EOF

[veldmuis-core]
SigLevel = Required DatabaseOptional
Server = file://${live_repo_root}/veldmuis-core/os/\$arch

[veldmuis-extra]
SigLevel = Required DatabaseOptional
Server = file://${live_repo_root}/veldmuis-extra/os/\$arch
EOF
}

has_secret_key() {
  local gpgdir="$1"

  gpg --homedir "${gpgdir}" --batch --with-colons -K 2>/dev/null | grep -q '^sec:'
}

target_has_secret_key() {
  arch-chroot "${target_root}" /usr/bin/bash -lc \
    "gpg --homedir /etc/pacman.d/gnupg --batch --with-colons -K 2>/dev/null | grep -q '^sec:'"
}

release_key_id_from_dir() {
  local keyring_dir="$1"
  local trusted_file="${keyring_dir}/veldmuis-trusted"

  [[ -f "${trusted_file}" ]] || return 0

  awk -F: '
    NF && $1 !~ /^#/ {
      print $1
      exit
    }
  ' "${trusted_file}"
}

ensure_keyring_populated() {
  local gpgdir="$1"
  local keyring_dir="$2"
  local label="$3"
  local release_key_id=""

  install -d -m700 "${gpgdir}"

  if ! has_secret_key "${gpgdir}"; then
    log "Initializing ${label} pacman keyring"
    pacman-key --gpgdir "${gpgdir}" --init
  fi

  log "Populating ${label} pacman keyring with Arch and Veldmuis signing keys"
  pacman-key --gpgdir "${gpgdir}" --populate-from "${keyring_dir}" --populate archlinux veldmuis
  log "Updating ${label} pacman trust database"
  pacman-key --gpgdir "${gpgdir}" --updatedb

  release_key_id="$(release_key_id_from_dir "${keyring_dir}")"
  if [[ -n "${release_key_id}" ]]; then
    log "Locally signing the Veldmuis release key in the ${label} keyring"
    pacman-key --gpgdir "${gpgdir}" --lsign-key "${release_key_id}"
  fi
}

ensure_target_keyring_populated() {
  local release_key_id="$1"

  if ! target_has_secret_key; then
    log "Initializing target pacman keyring"
    arch-chroot "${target_root}" pacman-key --init
  fi

  log "Populating target pacman keyring with Arch and Veldmuis signing keys"
  arch-chroot "${target_root}" pacman-key --populate archlinux veldmuis
  log "Updating target pacman trust database"
  arch-chroot "${target_root}" pacman-key --updatedb

  if [[ -n "${release_key_id}" ]]; then
    log "Locally signing the Veldmuis release key in the target keyring"
    arch-chroot "${target_root}" pacman-key --lsign-key "${release_key_id}"
  fi
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
  require_cmd gpg
  require_cmd arch-chroot
  local release_key_id=""

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

  ensure_keyring_populated /etc/pacman.d/gnupg /usr/share/pacman/keyrings live
  release_key_id="$(release_key_id_from_dir /usr/share/pacman/keyrings)"

  log "Installing Veldmuis package stack into ${target_root}"
  pacstrap -C "${tmp_pacman_conf}" "${target_root}" veldmuis-desktop

  ensure_target_keyring_populated "${release_key_id}"

  if [[ -f /etc/pacman.d/mirrorlist ]]; then
    install -Dm644 /etc/pacman.d/mirrorlist "${target_root}/etc/pacman.d/mirrorlist"
  fi

  if ! grep -qxF 'Include = /etc/pacman.conf.d/veldmuis.conf' "${target_root}/etc/pacman.conf"; then
    printf '\nInclude = /etc/pacman.conf.d/veldmuis.conf\n' >> "${target_root}/etc/pacman.conf"
  fi

  if [[ -x "${target_root}/usr/bin/flatpak" && \
        -f "${target_root}/usr/share/flatpak/remotes.d/flathub.flatpakrepo" ]]; then
    log "Configuring Flathub in the target system"
    arch-chroot "${target_root}" \
      /usr/bin/flatpak remote-add --if-not-exists --system --from \
      flathub /usr/share/flatpak/remotes.d/flathub.flatpakrepo
  fi

  log "Bootstrap complete"
}

main "$@"
