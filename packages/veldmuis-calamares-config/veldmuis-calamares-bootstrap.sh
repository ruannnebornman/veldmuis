#!/usr/bin/env bash

set -euo pipefail

target_root="${1:-}"
graphics_choice="${2:-all-open-source}"
extras_choice="${3:-}"
gaming_choice="no-gaming"
downloads_choice="no-downloads"
sync_choice="no-sync"
development_choice="no-development"
live_repo_root="/opt/veldmuis/repo"
offline_install_marker="/etc/veldmuis/offline-install"
installer_package_sets="/usr/lib/veldmuis/installer-package-sets.sh"
offline_manifest="${live_repo_root}/manifests/veldmuis-offline-packages.tsv"
offline_build_info="${live_repo_root}/manifests/veldmuis-offline-build.txt"
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

offline_install_enabled() {
  [[ -f "${offline_install_marker}" ]]
}

offline_build_value() {
  local key="$1"

  awk -F= -v wanted="${key}" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' \
    "${offline_build_info}"
}

validate_offline_repository() {
  local offline_dir="${live_repo_root}/veldmuis-offline/os/x86_64"
  local offline_db="${offline_dir}/veldmuis-offline.db.tar.gz"
  local repo_name=""
  local repo_db=""
  local expected_manifest_hash=""
  local actual_manifest_hash=""
  local expected_count=""
  local actual_count=""
  local package_name=""
  local package_version=""
  local package_arch=""
  local source_repo=""
  local expected_size=""
  local expected_hash=""
  local package_filename=""
  local package_path=""

  [[ -s "${offline_db}" && -s "${offline_db}.sig" ]] || \
    die "Embedded offline repository database or signature is missing."
  [[ -s "${offline_manifest}" && -s "${offline_build_info}" ]] || \
    die "Embedded offline repository manifest or build record is missing."
  [[ "$(head -n 1 "${offline_manifest}")" == $'package\tversion\tarchitecture\toriginal_repository\tfile_size\tsha256\tfilename' ]] || \
    die "Embedded offline repository manifest has an invalid header."

  for repo_name in veldmuis-core veldmuis-extra veldmuis-offline; do
    repo_db="${live_repo_root}/${repo_name}/os/x86_64/${repo_name}.db.tar.gz"
    [[ -s "${repo_db}" && -s "${repo_db}.sig" ]] || \
      die "Embedded repository database or signature is missing: ${repo_name}"
    gpgv --keyring /usr/share/pacman/keyrings/veldmuis.gpg \
      "${repo_db}.sig" "${repo_db}" >/dev/null 2>&1 || \
      die "Embedded repository database signature is invalid: ${repo_name}"
  done

  expected_manifest_hash="$(offline_build_value offline_manifest_sha256)"
  actual_manifest_hash="$(sha256sum "${offline_manifest}" | awk '{ print $1 }')"
  [[ "${expected_manifest_hash}" =~ ^[0-9a-f]{64}$ && \
    "${actual_manifest_hash}" == "${expected_manifest_hash}" ]] || \
    die "Embedded offline repository manifest checksum is invalid."

  expected_count="$(offline_build_value offline_package_count)"
  actual_count="$(awk 'END { print NR > 0 ? NR - 1 : 0 }' "${offline_manifest}")"
  [[ "${expected_count}" =~ ^[1-9][0-9]*$ && "${actual_count}" == "${expected_count}" ]] || \
    die "Embedded offline repository package count is invalid."

  log "Verifying ${expected_count} embedded offline package files"
  while IFS=$'\t' read -r \
    package_name package_version package_arch source_repo expected_size \
    expected_hash package_filename
  do
    [[ "${package_name}" != package ]] || continue
    [[ -n "${package_name}" && -n "${package_version}" && \
      "${package_arch}" =~ ^(any|x86_64)$ && \
      "${source_repo}" =~ ^(core|extra|multilib)$ && \
      "${expected_size}" =~ ^[1-9][0-9]*$ && \
      "${expected_hash}" =~ ^[0-9a-f]{64}$ && \
      "${package_filename}" =~ ^[A-Za-z0-9@._+:-]+\.pkg\.tar\.[A-Za-z0-9.]+$ ]] || \
      die "Embedded offline manifest contains an invalid entry for ${package_name:-unknown}."

    package_path="${offline_dir}/${package_filename}"
    [[ -s "${package_path}" && -s "${package_path}.sig" ]] || \
      die "Embedded offline package or signature is missing: ${package_filename}"
    [[ "$(stat --format '%s' "${package_path}")" == "${expected_size}" ]] || \
      die "Embedded offline package size is invalid: ${package_filename}"
    [[ "$(sha256sum "${package_path}" | awk '{ print $1 }')" == "${expected_hash}" ]] || \
      die "Embedded offline package checksum is invalid: ${package_filename}"
  done <"${offline_manifest}"

  log "Embedded offline repository passed manifest and database checks"
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

normalize_gaming_choice() {
  case "${gaming_choice}" in
    no-gaming|gaming)
      ;;
    "")
      gaming_choice="no-gaming"
      ;;
    *)
      log "Unknown gaming choice '${gaming_choice}', defaulting to no-gaming"
      gaming_choice="no-gaming"
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

normalize_development_choice() {
  case "${development_choice}" in
    no-development|code)
      ;;
    "")
      development_choice="no-development"
      ;;
    *)
      log "Unknown development choice '${development_choice}', defaulting to no-development"
      development_choice="no-development"
      ;;
  esac
}

normalize_extras_choice() {
  local extra
  local -a extras=()

  gaming_choice="no-gaming"
  downloads_choice="no-downloads"
  sync_choice="no-sync"
  development_choice="no-development"

  [[ -n "${extras_choice}" ]] || return 0

  IFS=',' read -r -a extras <<<"${extras_choice}"
  for extra in "${extras[@]}"; do
    case "${extra}" in
      gaming|steam|lutris|discord)
        gaming_choice="gaming"
        ;;
      qbittorrent)
        downloads_choice="qbittorrent"
        ;;
      syncthing)
        sync_choice="syncthing"
        ;;
      code)
        development_choice="code"
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
  tmp_pacman_conf="$(mktemp -t veldmuis-calamares-pacman.XXXXXX)"

  if offline_install_enabled; then
    cat >"${tmp_pacman_conf}" <<EOF
[options]
HoldPkg = pacman glibc
Architecture = auto
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Required
ParallelDownloads = 1

[veldmuis-core]
SigLevel = Required DatabaseRequired
Server = file://${live_repo_root}/veldmuis-core/os/\$arch

[veldmuis-extra]
SigLevel = Required DatabaseRequired
Server = file://${live_repo_root}/veldmuis-extra/os/\$arch

[veldmuis-offline]
SigLevel = Required DatabaseRequired
Server = file://${live_repo_root}/veldmuis-offline/os/\$arch
EOF
    log "Using local-only package sources for the offline installation"
    return
  fi

  write_arch_mirrorlist
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
SigLevel = Required DatabaseRequired
Server = file://${live_repo_root}/veldmuis-core/os/\$arch

[veldmuis-extra]
SigLevel = Required DatabaseRequired
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
  elif offline_install_enabled; then
    log "No external resolver is available; continuing in offline installation mode"
    install -Dm644 /dev/null "${target_root}/etc/resolv.conf"
  else
    die "Could not find a non-loopback resolver config in the live environment."
  fi
}

install_target_arch_mirrorlist() {
  [[ -n "${tmp_arch_mirrorlist}" ]] || write_live_arch_mirrorlist
  log "Installing Arch mirrorlist into target system"
  install -Dm644 "${tmp_arch_mirrorlist}" "${target_root}/etc/pacman.d/mirrorlist"
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
      printf '%s\n' "${veldmuis_installer_cpu_amd_packages[@]}"
      ;;
    GenuineIntel)
      printf '%s\n' "${veldmuis_installer_cpu_intel_packages[@]}"
      ;;
    *)
      ;;
  esac
}

selected_graphics_packages() {
  case "${graphics_choice}" in
    all-open-source)
      printf '%s\n' "${veldmuis_installer_graphics_all_open_source_packages[@]}"
      ;;
    amd-open-source)
      printf '%s\n' "${veldmuis_installer_graphics_amd_open_source_packages[@]}"
      ;;
    intel-open-source)
      printf '%s\n' "${veldmuis_installer_graphics_intel_open_source_packages[@]}"
      ;;
    nvidia-open-source)
      printf '%s\n' "${veldmuis_installer_graphics_nvidia_open_source_packages[@]}"
      ;;
    nvidia-580xx-dkms)
      printf '%s\n' "${veldmuis_installer_graphics_nvidia_580xx_packages[@]}"
      ;;
  esac
}

selected_gaming_packages() {
  case "${gaming_choice}" in
    gaming)
      printf '%s\n' "${veldmuis_installer_gaming_packages[@]}"
      ;;
  esac
}

selected_downloads_packages() {
  case "${downloads_choice}" in
    qbittorrent)
      printf '%s\n' "${veldmuis_installer_downloads_packages[@]}"
      ;;
  esac
}

selected_sync_packages() {
  case "${sync_choice}" in
    syncthing)
      printf '%s\n' "${veldmuis_installer_sync_packages[@]}"
      ;;
  esac
}

selected_development_packages() {
  case "${development_choice}" in
    code)
      printf '%s\n' "${veldmuis_installer_development_packages[@]}"
      ;;
  esac
}

initial_target_packages() {
  local package
  local -a packages=("${veldmuis_installer_base_packages[@]}")

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

  while IFS= read -r package; do
    [[ -n "${package}" ]] || continue
    packages+=("${package}")
  done < <(selected_development_packages)

  printf '%s\n' "${packages[@]}"
}

main() {
  require_cmd pacstrap
  require_cmd pacman-key
  require_cmd gpg
  require_cmd arch-chroot
  require_cmd sha256sum
  require_cmd stat
  local release_key_id=""
  local -a bootstrap_packages=()

  exec > >(tee "${log_file}") 2>&1

  [[ -n "${target_root}" ]] || die "Missing target root argument."
  [[ -d "${target_root}" ]] || die "Target root does not exist: ${target_root}"
  [[ -s "${live_repo_root}/veldmuis-core/os/x86_64/veldmuis-core.db.tar.gz" && \
    -s "${live_repo_root}/veldmuis-extra/os/x86_64/veldmuis-extra.db.tar.gz" ]] || \
    die "Embedded Veldmuis repositories are incomplete at ${live_repo_root}"
  [[ -f /usr/share/pacman/keyrings/veldmuis.gpg ]] || \
    die "Veldmuis keyring is missing from the live environment."
  [[ -r "${installer_package_sets}" ]] || \
    die "Installer package-set definition is missing: ${installer_package_sets}"

  # shellcheck source=packages/veldmuis-calamares-config/installer-package-sets.sh
  . "${installer_package_sets}"
  if offline_install_enabled; then
    require_cmd gpgv
    validate_offline_repository
  fi

  trap cleanup EXIT
  normalize_graphics_choice
  normalize_extras_choice
  normalize_gaming_choice
  normalize_downloads_choice
  normalize_sync_choice
  normalize_development_choice
  write_pacman_conf
  prepare_target_root

  ensure_keyring_populated /etc/pacman.d/gnupg /usr/share/pacman/keyrings live
  release_key_id="$(release_key_id_from_dir /usr/share/pacman/keyrings)"

  mapfile -t bootstrap_packages < <(initial_target_packages)
  log "Installing Veldmuis package stack into ${target_root}: ${bootstrap_packages[*]}"
  pacstrap -C "${tmp_pacman_conf}" "${target_root}" "${bootstrap_packages[@]}"
  install_target_arch_mirrorlist

  ensure_target_keyring_populated "${release_key_id}"
  normalize_keyring_permissions "${target_root}/etc/pacman.d/gnupg"

  if ! grep -qxF 'Include = /etc/pacman.conf.d/veldmuis.conf' "${target_root}/etc/pacman.conf"; then
    printf '\nInclude = /etc/pacman.conf.d/veldmuis.conf\n' >> "${target_root}/etc/pacman.conf"
  fi

  log "Selected graphics choice: ${graphics_choice}"
  log "Selected extras choices: ${extras_choice:-none}"
  log "Selected gaming choice: ${gaming_choice}"
  log "Selected downloads choice: ${downloads_choice}"
  log "Selected sync choice: ${sync_choice}"
  log "Selected development choice: ${development_choice}"

  log "Bootstrap complete"
}

main "$@"
