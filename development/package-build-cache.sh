#!/usr/bin/env bash

set -euo pipefail

# Shared helpers for the CI package build cache. The cache lets a package
# refresh reuse a previously built package when none of its recipe inputs
# changed, so only changed packages are rebuilt. Cache entries are keyed by a
# content hash of the package directory; signing, repo assembly, and
# publication are unaffected because a restored artifact is placed back into
# the package directory exactly like a freshly built one.

cache_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache_repo_root="${CI_REPO_ROOT:-$(cd "${cache_script_dir}/.." && pwd)}"
cache_packages_root="${cache_repo_root}/packages"
cache_root="${VELDMUIS_PACKAGE_BUILD_CACHE:-${cache_repo_root}/artifacts/package-build-cache}"
cache_schema="${VELDMUIS_PACKAGE_BUILD_CACHE_SCHEMA:-1}"

# shellcheck source=development/package-manifest.sh
. "${cache_script_dir}/package-manifest.sh"

package_build_cache_hash() {
  local package_name="$1"
  local package_dir="${cache_packages_root}/${package_name}"

  [[ -d "${package_dir}" ]] || {
    printf '[package-build-cache] ERROR: package directory not found: %s\n' \
      "${package_dir}" >&2
    return 1
  }

  (
    cd "${package_dir}"
    {
      printf 'veldmuis-package-build-cache schema=%s\n' "${cache_schema}"
      find . -type f \
        -not -path './pkg/*' \
        -not -path './src/*' \
        -not -name '*.pkg.tar.*' \
        -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 -r sha256sum --
    } | sha256sum | awk '{ print $1 }'
  )
}

package_build_cache_aggregate_key() {
  local package_name

  {
    for package_name in "${veldmuis_package_order[@]}"; do
      printf '%s %s\n' "${package_name}" "$(package_build_cache_hash "${package_name}")"
    done
  } | sha256sum | awk '{ print $1 }'
}

package_build_cache_entry_dir() {
  local package_name="$1"
  local package_hash="$2"

  printf '%s/%s/%s\n' "${cache_root}" "${package_name}" "${package_hash}"
}

package_build_cache_has_entry() {
  local package_name="$1"
  local package_hash="$2"
  local entry_dir
  local -a matches=()

  entry_dir="$(package_build_cache_entry_dir "${package_name}" "${package_hash}")"
  mapfile -t matches < <(
    find "${entry_dir}" -maxdepth 1 -type f \
      -name "${package_name}-*.pkg.tar.zst" \
      ! -name "${package_name}-debug-*.pkg.tar.zst" \
      -print 2>/dev/null
  )
  ((${#matches[@]} > 0))
}

package_build_cache_restore() {
  local package_name="$1"
  local package_hash="$2"
  local package_dir="${cache_packages_root}/${package_name}"
  local entry_dir
  local -a matches=()

  package_build_cache_has_entry "${package_name}" "${package_hash}" || return 1
  entry_dir="$(package_build_cache_entry_dir "${package_name}" "${package_hash}")"

  rm -f "${package_dir}/${package_name}-"*.pkg.tar.zst \
    "${package_dir}/${package_name}-"*.pkg.tar.zst.sig
  mapfile -t matches < <(
    find "${entry_dir}" -maxdepth 1 -type f \
      -name "${package_name}-*.pkg.tar.zst" \
      ! -name "${package_name}-debug-*.pkg.tar.zst" \
      -print
  )
  cp -f "${matches[@]}" "${package_dir}/"
}

package_build_cache_store() {
  local package_name="$1"
  local package_hash="$2"
  local package_dir="${cache_packages_root}/${package_name}"
  local entry_dir
  local package_cache_dir
  local -a matches=()

  mapfile -t matches < <(
    find "${package_dir}" -maxdepth 1 -type f \
      -name "${package_name}-*.pkg.tar.zst" \
      ! -name "${package_name}-debug-*.pkg.tar.zst" \
      -print
  )
  ((${#matches[@]} > 0)) || {
    printf '[package-build-cache] ERROR: no built package to cache for %s\n' \
      "${package_name}" >&2
    return 1
  }

  entry_dir="$(package_build_cache_entry_dir "${package_name}" "${package_hash}")"
  package_cache_dir="${cache_root}/${package_name}"
  mkdir -p "${entry_dir}"

  # Keep only the current input hash per package so the cache does not grow
  # without bound across recipe revisions.
  find "${package_cache_dir}" -mindepth 1 -maxdepth 1 -type d \
    ! -name "${package_hash}" -exec rm -rf {} +

  cp -f "${matches[@]}" "${entry_dir}/"
}

usage() {
  cat <<'EOF'
Usage:
  package-build-cache.sh hash PACKAGE
  package-build-cache.sh aggregate
  package-build-cache.sh dir PACKAGE HASH

Prints a deterministic content hash or the aggregate cache key. Sourced by
development/build-all-packages.sh, where it also provides restore/store
helpers.
EOF
}

main() {
  case "${1:-}" in
    hash)
      (($# == 2)) || { usage >&2; exit 2; }
      package_build_cache_hash "$2"
      ;;
    aggregate)
      package_build_cache_aggregate_key
      ;;
    dir)
      (($# == 3)) || { usage >&2; exit 2; }
      package_build_cache_entry_dir "$2" "$3"
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
