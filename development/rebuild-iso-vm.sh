#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
workspace_root="$(cd "${repo_root}/.." && pwd)"
development_root="${repo_root}/development"
packages_root="${repo_root}/packages"
vm_name="${VM_NAME:-arch-veldmuis-test}"
connect_uri="${CONNECT_URI:-qemu:///session}"
pool_dir="${POOL_DIR:-$HOME/.local/share/libvirt/images}"
disk_path="${pool_dir}/${vm_name}.qcow2"

log() {
  printf '[rebuild-iso-vm] %s\n' "$*"
}

die() {
  printf '[rebuild-iso-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage:
  rebuild-iso-vm.sh
  rebuild-iso-vm.sh veldmuis-branding veldmuis-desktop

Behavior:
  - rebuilds the listed packages with makepkg, or auto-detects changed package
    directories under packages/ when no package names are provided
  - package builds intentionally skip host-side dependency resolution because
    Veldmuis package deps are satisfied through the local repo, not the host
  - rebuilds the local Veldmuis repo
  - purges cached copies of locally built Veldmuis packages during the ISO
    build so pacman cannot reuse stale package files with newer signatures
  - rebuilds the ISO
  - keeps only a rolling window of local archiso build trees and ISOs
  - deletes the existing test VM if present
  - creates a fresh VM from the newest ISO

Environment overrides:
  VM_NAME      Default: arch-veldmuis-test
  CONNECT_URI  Default: qemu:///session
  POOL_DIR     Default: ~/.local/share/libvirt/images
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

  [[ -d "${package_dir}" ]] || die "Package directory not found: ${package_dir}"

  log "Building package: ${package_name}"
  (
    cd "${package_dir}"
    if [[ "${package_name}" == veldmuis-* ]]; then
      makepkg --nodeps -f
    else
      makepkg -sf
    fi
  )
}

find_latest_iso() {
  local iso_path

  iso_path="$(find "${workspace_root}/build/archiso/out" -maxdepth 1 -type f -name 'veldmuis-*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
  [[ -n "${iso_path}" ]] || die "No built ISO found under build/archiso/out"
  printf '%s\n' "${iso_path}"
}

delete_existing_vm() {
  if virsh --connect "${connect_uri}" dominfo "${vm_name}" >/dev/null 2>&1; then
    log "Removing existing VM: ${vm_name}"
    virsh --connect "${connect_uri}" destroy "${vm_name}" >/dev/null 2>&1 || true
    virsh --connect "${connect_uri}" undefine "${vm_name}" --nvram --managed-save --snapshots-metadata >/dev/null 2>&1 || \
      virsh --connect "${connect_uri}" undefine "${vm_name}" --nvram >/dev/null 2>&1 || \
      virsh --connect "${connect_uri}" undefine "${vm_name}" >/dev/null 2>&1 || \
      die "Failed to undefine VM: ${vm_name}"
  fi

  if [[ -e "${disk_path}" ]]; then
    log "Removing existing disk image: ${disk_path}"
    rm -f "${disk_path}"
  fi
}

main() {
  local -a package_targets=()
  local iso_path

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  require_cmd makepkg
  require_cmd virsh
  require_cmd find
  require_cmd sort
  require_cmd head
  require_cmd cut

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

  log "Rebuilding Veldmuis ISO (will purge cached local package artifacts first)"
  log "Rebuilding Veldmuis ISO"
  "${development_root}/build-archiso.sh"

  iso_path="$(find_latest_iso)"

  delete_existing_vm

  log "Creating fresh VM from ${iso_path}"
  "${development_root}/create-arch-test-vm.sh" "${iso_path}"

  log "Fresh VM ready: ${vm_name}"
}

main "$@"
