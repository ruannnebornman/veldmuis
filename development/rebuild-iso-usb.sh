#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
workspace_root="$(cd "${repo_root}/.." && pwd)"
development_root="${repo_root}/development"
packages_root="${repo_root}/packages"
usb_device="${USB_DEVICE:-}"
dd_bs="${DD_BS:-4M}"
sudo_cmd=(sudo)
makepkg_config_override=""

log() {
  printf '[rebuild-iso-usb] %s\n' "$*"
}

die() {
  printf '[rebuild-iso-usb] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  [[ -n "${makepkg_config_override}" ]] && rm -f "${makepkg_config_override}"
}

setup_askpass_support() {
  if [[ -z "${SUDO_ASKPASS:-}" ]]; then
    if command -v ksshaskpass >/dev/null 2>&1; then
      export SUDO_ASKPASS="$(command -v ksshaskpass)"
    elif command -v ssh-askpass >/dev/null 2>&1; then
      export SUDO_ASKPASS="$(command -v ssh-askpass)"
    fi
  fi

  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo_cmd=(sudo -A -p "Password: ")
    makepkg_config_override="$(mktemp -t veldmuis-makepkg.XXXXXX)"
    cp /etc/makepkg.conf "${makepkg_config_override}"
    cat >>"${makepkg_config_override}" <<'EOF'
PACMAN_AUTH=(sudo -A -p "Password: ")
EOF
  fi
}

usage() {
  cat <<'EOF'
Usage:
  rebuild-iso-usb.sh
  rebuild-iso-usb.sh veldmuis-branding veldmuis-desktop-kde

Behavior:
  - rebuilds the listed packages with makepkg, or auto-detects changed package
    directories under packages/ when no package names are provided
  - rebuilds the local Veldmuis repo
  - rebuilds the ISO
  - keeps only a rolling window of local archiso build trees and ISOs
  - writes the newest ISO to a USB disk

Environment overrides:
  USB_DEVICE  Explicit block device path, for example /dev/sda
  DD_BS       dd block size. Default: 4M
  ARCHISO_KEEP_BUILDS  Default: 3
  ARCHISO_KEEP_ISOS    Default: 3
EOF
}

collect_changed_packages() {
  local line path package_name

  require_cmd git

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    path="${line:3}"
    [[ "${path}" == packages/* ]] || continue
    package_name="${path#packages/}"
    package_name="${package_name%%/*}"
    [[ -n "${package_name}" ]] || continue
    printf '%s\n' "${package_name}"
  done < <(git -C "${repo_root}" status --porcelain --untracked-files=all -- packages)
}

build_package() {
  local package_name="$1"
  local package_dir="${packages_root}/${package_name}"
  local -a makepkg_cmd=(makepkg)

  [[ -d "${package_dir}" ]] || die "Package directory not found: ${package_dir}"

  if [[ -n "${makepkg_config_override}" ]]; then
    makepkg_cmd+=(--config "${makepkg_config_override}")
  fi

  log "Building package: ${package_name}"
  (
    cd "${package_dir}"
    if [[ "${package_name}" == veldmuis-* ]]; then
      "${makepkg_cmd[@]}" --nodeps -f
    else
      "${makepkg_cmd[@]}" -sf
    fi
  )
}

find_latest_iso() {
  local iso_path

  iso_path="$(find "${workspace_root}/build/archiso/out" -maxdepth 1 -type f -name 'veldmuis-*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
  [[ -n "${iso_path}" ]] || die "No built ISO found under build/archiso/out"
  printf '%s\n' "${iso_path}"
}

autodetect_usb_device() {
  local -a candidates=()

  mapfile -t candidates < <(lsblk -dnpo PATH,TRAN,TYPE | awk '$2 == "usb" && $3 == "disk" { print $1 }')

  case "${#candidates[@]}" in
    0)
      die "No USB disk detected. Plug the target stick in or set USB_DEVICE=/dev/sdX"
      ;;
    1)
      usb_device="${candidates[0]}"
      ;;
    *)
      printf '[rebuild-iso-usb] ERROR: Multiple USB disks detected:\n' >&2
      printf '  %s\n' "${candidates[@]}" >&2
      die "Set USB_DEVICE=/dev/sdX explicitly"
      ;;
  esac
}

show_target_device() {
  lsblk -o NAME,SIZE,TYPE,MODEL,TRAN,HOTPLUG,MOUNTPOINTS "${usb_device}"
}

unmount_usb_partitions() {
  local -a partitions=()

  mapfile -t partitions < <(lsblk -lnpo NAME,TYPE "${usb_device}" | awk '$2 == "part" { print $1 }')
  for partition in "${partitions[@]}"; do
    "${sudo_cmd[@]}" umount "${partition}" >/dev/null 2>&1 || true
  done
}

main() {
  local -a package_targets=()
  local iso_path

  if (( EUID == 0 )); then
    die "Do not run this script with sudo. Run it as your normal user; it will use sudo only for the ISO write step."
  fi

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  require_cmd makepkg
  require_cmd lsblk
  require_cmd awk
  require_cmd find
  require_cmd sort
  require_cmd head
  require_cmd cut
  require_cmd dd
  require_cmd sync
  require_cmd sudo

  trap cleanup EXIT
  setup_askpass_support

  if (($# > 0)); then
    package_targets=("$@")
  else
    mapfile -t package_targets < <(collect_changed_packages | awk '!seen[$0]++')
  fi

  if ((${#package_targets[@]} > 0)); then
    for package_name in "${package_targets[@]}"; do
      build_package "${package_name}"
    done
  else
    log "No changed package directories detected. Skipping makepkg."
  fi

  log "Rebuilding local Veldmuis repo"
  "${development_root}/build-local-repo.sh"

  log "Rebuilding Veldmuis ISO"
  "${development_root}/build-archiso.sh"

  iso_path="$(find_latest_iso)"

  if [[ -z "${usb_device}" ]]; then
    autodetect_usb_device
  fi

  [[ -b "${usb_device}" ]] || die "USB device not found: ${usb_device}"

  log "Target USB device: ${usb_device}"
  show_target_device

  log "Unmounting partitions on ${usb_device}"
  unmount_usb_partitions

  log "Writing ${iso_path} to ${usb_device}"
  "${sudo_cmd[@]}" dd if="${iso_path}" of="${usb_device}" bs="${dd_bs}" status=progress conv=fsync
  sync

  log "ISO written to ${usb_device}"
}

main "$@"
