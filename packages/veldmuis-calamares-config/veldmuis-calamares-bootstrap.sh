#!/usr/bin/env bash

set -euo pipefail

target_root="${1:-}"
graphics_choice="${2:-all-open-source}"
extras_choice="${3:-}"
steam_choice="no-steam"
lutris_choice="no-lutris"
discord_choice="no-discord"
downloads_choice="no-downloads"
sync_choice="no-sync"
live_repo_root="/opt/veldmuis/repo"
tmp_pacman_conf=""
tmp_arch_mirrorlist=""
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
  [[ -n "${tmp_arch_mirrorlist}" ]] && rm -f "${tmp_arch_mirrorlist}"
}

write_live_arch_mirrorlist() {
  tmp_arch_mirrorlist="$(mktemp -t veldmuis-calamares-mirrorlist.XXXXXX)"

  [[ -f /etc/pacman.d/mirrorlist ]] || \
    die "Live Arch mirrorlist is missing at /etc/pacman.d/mirrorlist."

  awk '
    /^[[:space:]]*Server[[:space:]]*=/ {
      sub(/^[[:space:]]*/, "")
      print
      found = 1
    }
    END { exit found ? 0 : 1 }
  ' /etc/pacman.d/mirrorlist >"${tmp_arch_mirrorlist}" || \
    die "Live Arch mirrorlist has no active Server entries. The ISO mirror hook likely did not run."

  chmod 644 "${tmp_arch_mirrorlist}"
  log "Using active Arch mirrors from the live mirrorlist"
}

write_ranked_arch_mirrorlist() {
  local ranked_mirrorlist=""

  if ! command -v veldmuis-refresh-arch-mirrors >/dev/null 2>&1; then
    log "Veldmuis mirror refresh helper is unavailable; using live Arch mirrorlist"
    write_live_arch_mirrorlist
    return
  fi

  ranked_mirrorlist="$(mktemp -t veldmuis-calamares-ranked-mirrorlist.XXXXXX)"
  if veldmuis-refresh-arch-mirrors --output "${ranked_mirrorlist}" --no-backup; then
    tmp_arch_mirrorlist="${ranked_mirrorlist}"
    chmod 644 "${tmp_arch_mirrorlist}"
    log "Using ranked Arch mirrors from reflector"
    return
  fi

  log "Reflector mirror ranking failed; using live Arch mirrorlist"
  rm -f "${ranked_mirrorlist}"
  write_live_arch_mirrorlist
}

write_arch_mirrorlist() {
  write_ranked_arch_mirrorlist
}

normalize_graphics_choice() {
  case "${graphics_choice}" in
    all-open-source|amd-open-source|intel-open-source|nvidia-open-source|nvidia-580xx-dkms)
      ;;
    "")
      graphics_choice="all-open-source"
      ;;
    *)
      log "Unknown graphics choice '${graphics_choice}', defaulting to all-open-source"
      graphics_choice="all-open-source"
      ;;
  esac
}

normalize_steam_choice() {
  case "${steam_choice}" in
    no-steam|steam)
      ;;
    "")
      steam_choice="no-steam"
      ;;
    *)
      log "Unknown Steam choice '${steam_choice}', defaulting to no-steam"
      steam_choice="no-steam"
      ;;
  esac
}

normalize_lutris_choice() {
  case "${lutris_choice}" in
    no-lutris|lutris)
      ;;
    "")
      lutris_choice="no-lutris"
      ;;
    *)
      log "Unknown Lutris choice '${lutris_choice}', defaulting to no-lutris"
      lutris_choice="no-lutris"
      ;;
  esac
}

normalize_discord_choice() {
  case "${discord_choice}" in
    no-discord|discord)
      ;;
    "")
      discord_choice="no-discord"
      ;;
    *)
      log "Unknown Discord choice '${discord_choice}', defaulting to no-discord"
      discord_choice="no-discord"
      ;;
  esac
}

normalize_downloads_choice() {
  case "${downloads_choice}" in
    no-downloads|qbittorrent)
      ;;
    "")
      downloads_choice="no-downloads"
      ;;
    *)
      log "Unknown downloads choice '${downloads_choice}', defaulting to no-downloads"
      downloads_choice="no-downloads"
      ;;
  esac
}

normalize_sync_choice() {
  case "${sync_choice}" in
    no-sync|syncthing)
      ;;
    "")
      sync_choice="no-sync"
      ;;
    *)
      log "Unknown sync choice '${sync_choice}', defaulting to no-sync"
      sync_choice="no-sync"
      ;;
  esac
}

normalize_extras_choice() {
  local extra
  local -a extras=()

  steam_choice="no-steam"
  lutris_choice="no-lutris"
  discord_choice="no-discord"
  downloads_choice="no-downloads"
  sync_choice="no-sync"

  [[ -n "${extras_choice}" ]] || return 0

  IFS=',' read -r -a extras <<<"${extras_choice}"
  for extra in "${extras[@]}"; do
    case "${extra}" in
      gaming)
        steam_choice="steam"
        lutris_choice="lutris"
        ;;
      steam)
        steam_choice="steam"
        ;;
      lutris)
        lutris_choice="lutris"
        ;;
      discord)
        discord_choice="discord"
        ;;
      qbittorrent)
        downloads_choice="qbittorrent"
        ;;
      syncthing)
        sync_choice="syncthing"
        ;;
      "")
        ;;
      *)
        log "Unknown extras choice '${extra}', ignoring it"
        ;;
    esac
  done
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
  write_arch_mirrorlist

  tmp_pacman_conf="$(mktemp -t veldmuis-calamares-pacman.XXXXXX)"
  cat >"${tmp_pacman_conf}" <<EOF
[options]
HoldPkg = pacman glibc
Architecture = auto
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 1
DisableDownloadTimeout

[core]
Include = ${tmp_arch_mirrorlist}

[extra]
Include = ${tmp_arch_mirrorlist}

[multilib]
Include = ${tmp_arch_mirrorlist}

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

install_target_arch_mirrorlist() {
  log "Installing Arch mirrorlist into target system"
  install -Dm644 "${tmp_arch_mirrorlist}" "${target_root}/etc/pacman.d/mirrorlist"
}

install_target_greetd_config() {
  local source_path="${target_root}/usr/share/veldmuis/greetd/config.toml"
  local target_path="${target_root}/etc/greetd/config.toml"

  [[ -f "${source_path}" ]] || \
    die "Veldmuis greetd configuration is missing from the installed target."

  log "Installing Veldmuis greetd configuration into target system"
  install -Dm644 "${source_path}" "${target_path}"
}

normalize_keyring_permissions() {
  local gpgdir="$1"

  [[ -d "${gpgdir}" ]] || return 0

  chmod 755 "${gpgdir}"

  for dir_name in crls.d openpgp-revocs.d private-keys-v1.d; do
    [[ -d "${gpgdir}/${dir_name}" ]] || continue
    chmod 700 "${gpgdir}/${dir_name}"
  done

  for file_name in pubring.gpg trustdb.gpg gpg.conf gpg-agent.conf tofu.db; do
    [[ -f "${gpgdir}/${file_name}" ]] || continue
    chmod 644 "${gpgdir}/${file_name}"
  done

  [[ -f "${gpgdir}/secring.gpg" ]] && chmod 600 "${gpgdir}/secring.gpg"
}

install_target_packages() {
  (($# > 0)) || return 0

  log "Installing target packages: $*"
  arch-chroot "${target_root}" pacman -S --noconfirm --needed "$@"
}

cpu_microcode_packages() {
  local vendor_id=""

  vendor_id="$(awk -F ': ' '/^vendor_id[[:space:]]*: / { print $2; exit }' /proc/cpuinfo)"

  case "${vendor_id}" in
    AuthenticAMD)
      printf '%s\n' amd-ucode
      ;;
    GenuineIntel)
      printf '%s\n' intel-ucode
      ;;
    *)
      ;;
  esac
}

selected_graphics_packages() {
  case "${graphics_choice}" in
    all-open-source)
      printf '%s\n' \
        mesa \
        libva-intel-driver \
        intel-media-driver \
        vulkan-radeon \
        lib32-vulkan-radeon \
        vulkan-intel \
        lib32-vulkan-intel \
        vulkan-nouveau \
        lib32-vulkan-nouveau
      ;;
    amd-open-source)
      printf '%s\n' \
        mesa \
        vulkan-radeon \
        lib32-vulkan-radeon
      ;;
    intel-open-source)
      printf '%s\n' \
        mesa \
        libva-intel-driver \
        intel-media-driver \
        vulkan-intel \
        lib32-vulkan-intel
      ;;
    nvidia-open-source)
      printf '%s\n' \
        mesa \
        vulkan-nouveau \
        lib32-vulkan-nouveau
      ;;
    nvidia-580xx-dkms)
      printf '%s\n' \
        veldmuis-nvidia-legacy
      ;;
  esac
}

selected_gaming_packages() {
  if [[ "${steam_choice}" == "steam" ]]; then
    printf '%s\n' steam
  fi
  if [[ "${lutris_choice}" == "lutris" ]]; then
    printf '%s\n' lutris
  fi
  if [[ "${discord_choice}" == "discord" ]]; then
    printf '%s\n' discord
  fi
}

selected_downloads_packages() {
  case "${downloads_choice}" in
    qbittorrent)
      printf '%s\n' \
        veldmuis-downloads
      ;;
  esac
}

selected_sync_packages() {
  case "${sync_choice}" in
    syncthing)
      printf '%s\n' \
        veldmuis-sync
      ;;
  esac
}

initial_target_packages() {
  local package
  local -a packages=(veldmuis-desktop)

  while IFS= read -r package; do
    [[ -n "${package}" ]] || continue
    packages+=("${package}")
  done < <(cpu_microcode_packages)

  while IFS= read -r package; do
    [[ -n "${package}" ]] || continue
    packages+=("${package}")
  done < <(selected_graphics_packages)

  while IFS= read -r package; do
    [[ -n "${package}" ]] || continue
    packages+=("${package}")
  done < <(selected_gaming_packages)

  while IFS= read -r package; do
    [[ -n "${package}" ]] || continue
    packages+=("${package}")
  done < <(selected_downloads_packages)

  while IFS= read -r package; do
    [[ -n "${package}" ]] || continue
    packages+=("${package}")
  done < <(selected_sync_packages)

  printf '%s\n' "${packages[@]}"
}

main() {
  require_cmd pacstrap
  require_cmd pacman-key
  require_cmd gpg
  require_cmd arch-chroot
  local release_key_id=""
  local -a bootstrap_packages=()

  exec > >(tee "${log_file}") 2>&1

  [[ -n "${target_root}" ]] || die "Missing target root argument."
  [[ -d "${target_root}" ]] || die "Target root does not exist: ${target_root}"
  [[ -d "${live_repo_root}/veldmuis-core/os/x86_64" ]] || \
    die "Embedded Veldmuis repo not found at ${live_repo_root}"
  [[ -f /usr/share/pacman/keyrings/veldmuis.gpg ]] || \
    die "Veldmuis keyring is missing from the live environment."

  trap cleanup EXIT
  normalize_graphics_choice
  normalize_extras_choice
  normalize_steam_choice
  normalize_lutris_choice
  normalize_discord_choice
  normalize_downloads_choice
  normalize_sync_choice
  write_pacman_conf
  prepare_target_root

  ensure_keyring_populated /etc/pacman.d/gnupg /usr/share/pacman/keyrings live
  release_key_id="$(release_key_id_from_dir /usr/share/pacman/keyrings)"

  mapfile -t bootstrap_packages < <(initial_target_packages)
  log "Installing Veldmuis package stack into ${target_root}: ${bootstrap_packages[*]}"
  pacstrap -C "${tmp_pacman_conf}" "${target_root}" "${bootstrap_packages[@]}"
  install_target_greetd_config
  install_target_arch_mirrorlist

  ensure_target_keyring_populated "${release_key_id}"
  normalize_keyring_permissions "${target_root}/etc/pacman.d/gnupg"

  if ! grep -qxF 'Include = /etc/pacman.conf.d/veldmuis.conf' "${target_root}/etc/pacman.conf"; then
    printf '\nInclude = /etc/pacman.conf.d/veldmuis.conf\n' >> "${target_root}/etc/pacman.conf"
  fi

  log "Selected graphics choice: ${graphics_choice}"
  log "Selected extras choices: ${extras_choice:-none}"
  log "Selected Steam choice: ${steam_choice}"
  log "Selected Lutris choice: ${lutris_choice}"
  log "Selected Discord choice: ${discord_choice}"
  log "Selected downloads choice: ${downloads_choice}"
  log "Selected sync choice: ${sync_choice}"

  log "Bootstrap complete"
}

main "$@"
