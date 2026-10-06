#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
packages_root="${repo_root}/packages"
cache_active=0

# shellcheck source=development/package-manifest.sh
. "${script_dir}/package-manifest.sh"
# shellcheck source=development/package-build-cache.sh
. "${script_dir}/package-build-cache.sh"

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

is_true() {
  [[ "${1:-}" == "1" || "${1:-}" == "true" ]]
}

usage() {
  cat <<'EOF'
Usage:
  build-all-packages.sh [--no-cache] [PACKAGE ...]

Behavior:
  - builds the full Veldmuis package set in deterministic order by default
  - if package names are passed, builds only that subset
  - uses makepkg --nodeps -f because CI builders are expected to provide the
    required host build dependencies ahead of time
  - when VELDMUIS_PACKAGE_BUILD_CACHE_ENABLE is set, reuses artifact-cached
    packages whose recipe inputs are unchanged instead of rebuilding them
EOF
}

build_package() {
  local package_name="$1"
  local package_dir="${packages_root}/${package_name}"
  local package_hash=""

  [[ -d "${package_dir}" ]] || die "Package directory not found: ${package_dir}"

  if (( cache_active )); then
    package_hash="$(package_build_cache_hash "${package_name}")"

    if package_build_cache_restore "${package_name}" "${package_hash}"; then
      log "Reusing cached package: ${package_name} (${package_hash:0:12})"
      return 0
    fi

    log "Building package: ${package_name} (cache miss ${package_hash:0:12})"
    (
      cd "${package_dir}"
      makepkg --nodeps -f
    )
    package_build_cache_store "${package_name}" "${package_hash}"
    return 0
  fi

  log "Building package: ${package_name}"
  (
    cd "${package_dir}"
    makepkg --nodeps -f
  )
}

main() {
  local -a package_targets=()
  local no_cache=0

  while (($# > 0)); do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --no-cache)
        no_cache=1
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage >&2
        die "Unsupported option: $1"
        ;;
      *)
        break
        ;;
    esac
  done

  if (($# > 0)); then
    package_targets=("$@")
  else
    package_targets=("${veldmuis_package_order[@]}")
  fi

  require_cmd makepkg

  if is_true "${VELDMUIS_PACKAGE_BUILD_CACHE_ENABLE:-0}" \
    && ! is_true "${VELDMUIS_PACKAGE_BUILD_CACHE_DISABLE:-0}"; then
    cache_active=1
    log "Package build cache enabled: ${cache_root}"
  fi
  if (( no_cache )); then
    cache_active=0
  fi

  for package_name in "${package_targets[@]}"; do
    build_package "${package_name}"
  done
}

main "$@"
