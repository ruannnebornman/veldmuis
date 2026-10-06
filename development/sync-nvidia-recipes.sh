#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C

# Mirrors the upstream AUR NVIDIA 580xx recipes into the vendored recipe tree
# under packages/nvidia-580xx-src and records the synced commits in
# packages/nvidia-580xx-src/upstream-refs.txt. It is used by the scheduled
# NVIDIA recipe watcher to prepare a review pull request when upstream drifts;
# it never commits, pushes, or merges anything itself.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
source_dir="${VELDMUIS_NVIDIA_SOURCE_DIR:-${repo_root}/packages/nvidia-580xx-src}"
upstream_root="${VELDMUIS_NVIDIA_UPSTREAM_ROOT:-https://aur.archlinux.org}"
upstream_refs="${VELDMUIS_NVIDIA_UPSTREAM_REFS:-${source_dir}/upstream-refs.txt}"
nvidia_package_set="${VELDMUIS_NVIDIA_580XX_PACKAGE_SET:-${repo_root}/packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh}"

die() {
  printf '[sync-nvidia-recipes] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[sync-nvidia-recipes] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage:
  sync-nvidia-recipes.sh

Mirrors the upstream AUR NVIDIA 580xx recipes into
packages/nvidia-580xx-src/<package_base> and rewrites
packages/nvidia-580xx-src/upstream-refs.txt with the synced commits.

Environment:
  VELDMUIS_NVIDIA_SOURCE_DIR=/path/to/vendored-recipes
  VELDMUIS_NVIDIA_UPSTREAM_ROOT=https://aur.archlinux.org
EOF
}

clone_upstream() {
  local repo_url="$1"
  local dest="$2"
  local attempt

  for attempt in 1 2 3; do
    if git clone --quiet --depth 1 "${repo_url}" "${dest}"; then
      return 0
    fi
    rm -rf "${dest}"
    log "Clone attempt ${attempt} failed for ${repo_url}; retrying"
    sleep $((attempt * 5))
  done

  die "Unable to clone upstream AUR repository: ${repo_url}"
}

sync_recipe() {
  local base="$1"
  local upstream_dir="$2"
  local local_dir="${source_dir}/${base}"

  [[ -d "${local_dir}" ]] || die "Vendored recipe directory is missing: ${local_dir}"

  # Mirror the upstream tree, including symlinks, and drop files that upstream
  # no longer ships. The vendored recipes are unmodified upstream copies, so a
  # mirror reproduces the recorded commit exactly.
  rsync -a --delete --exclude '.git/' "${upstream_dir}/" "${local_dir}/"
}

write_upstream_refs() {
  local base

  {
    printf '# Upstream AUR commits that the vendored recipes were copied from.\n'
    printf '# Update this file together with packages/nvidia-580xx-src/<base> when syncing.\n'
    for base in "${package_bases[@]}"; do
      printf '%s %s\n' "${base}" "${synced_refs[${base}]}"
    done
  } > "${upstream_refs}"

  log "Recorded synced commits in ${upstream_refs#"${repo_root}"/}"
}

main() {
  local -a package_bases=()
  local -A synced_refs=()
  local base upstream_dir upstream_ref
  local work_root

  while (($# > 0)); do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage >&2
        die "Unsupported argument: $1"
        ;;
    esac
  done

  [[ -r "${nvidia_package_set}" ]] || die "NVIDIA package set not readable: ${nvidia_package_set}"

  require_cmd git
  require_cmd rsync
  require_cmd mktemp

  # shellcheck source=packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
  . "${nvidia_package_set}"
  package_bases=("${veldmuis_nvidia_580xx_package_bases[@]}")
  ((${#package_bases[@]} > 0)) || die "No vendored NVIDIA package bases defined"

  mkdir -p "${source_dir}"

  work_root="$(mktemp -d)"
  trap '[[ -n "${work_root:-}" ]] && rm -rf -- "${work_root}"' EXIT

  for base in "${package_bases[@]}"; do
    upstream_dir="${work_root}/${base}"
    clone_upstream "${upstream_root%/}/${base}.git" "${upstream_dir}"
    upstream_ref="$(git -C "${upstream_dir}" rev-parse HEAD)"
    sync_recipe "${base}" "${upstream_dir}"
    synced_refs["${base}"]="${upstream_ref}"
    log "Synced ${base} at ${upstream_ref}"
  done

  write_upstream_refs
  log "Vendored NVIDIA recipes now match upstream."
}

main "$@"
