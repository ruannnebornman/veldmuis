#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages_root="${repo_root}/packages"

package_order=(
  "calamares"
  "veldmuis-keyring"
  "veldmuis-mirrorlist"
  "veldmuis-release"
  "veldmuis-base"
  "veldmuis-common"
  "veldmuis-boot"
  "veldmuis-displaymanager"
  "veldmuis-desktop-kde"
  "veldmuis-multimedia"
  "veldmuis-branding"
  "veldmuis-desktop"
  "veldmuis-devel"
  "veldmuis-calamares-config"
)

log() {
  printf '[build-all-packages] %s\n' "$*"
}

die() {
  printf '[build-all-packages] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage:
  build-all-packages.sh
  build-all-packages.sh veldmuis-branding veldmuis-release

Behavior:
  - builds the full Veldmuis package set in deterministic order by default
  - if package names are passed, builds only that subset
  - uses `makepkg --nodeps -f` because CI runners should be provisioned with
    the required host build dependencies ahead of time
EOF
}

build_package() {
  local package_name="$1"
  local package_dir="${packages_root}/${package_name}"

  [[ -d "${package_dir}" ]] || die "Package directory not found: ${package_dir}"

  log "Building package: ${package_name}"
  (
    cd "${package_dir}"
    makepkg --nodeps -f
  )
}

main() {
  local -a package_targets=()

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  require_cmd makepkg

  if (($# > 0)); then
    package_targets=("$@")
  else
    package_targets=("${package_order[@]}")
  fi

  for package_name in "${package_targets[@]}"; do
    build_package "${package_name}"
  done
}

main "$@"
