#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C

# Compares the vendored NVIDIA 580xx recipes under packages/nvidia-580xx-src
# against the upstream AUR package repositories. It only reports drift; it never
# changes the vendored files. The scheduled watcher workflow turns a drift
# report into an issue.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
source_dir="${VELDMUIS_AUR_SOURCE_DIR:-${repo_root}/packages/nvidia-580xx-src}"
aur_root="${VELDMUIS_AUR_UPSTREAM_ROOT:-https://aur.archlinux.org}"
upstream_refs="${VELDMUIS_AUR_UPSTREAM_REFS:-${source_dir}/upstream-refs.txt}"
report_file="${VELDMUIS_RECIPE_DRIFT_REPORT:-}"
nvidia_package_set="${VELDMUIS_NVIDIA_580XX_PACKAGE_SET:-${repo_root}/packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh}"

die() {
  printf '[check-nvidia-recipe-drift] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[check-nvidia-recipe-drift] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

write_output() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT}"
}

usage() {
  cat <<'EOF'
Usage:
  check-nvidia-recipe-drift.sh --report PATH

Environment:
  VELDMUIS_AUR_SOURCE_DIR=/path/to/vendored-recipes
  VELDMUIS_AUR_UPSTREAM_ROOT=https://aur.archlinux.org
  VELDMUIS_RECIPE_DRIFT_REPORT=/path/to/report.md

Writes a Markdown report and sets drift=true|false in GITHUB_OUTPUT.
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

read_synced_refs() {
  [[ -r "${upstream_refs}" ]] || return 0

  local base ref extra
  while read -r base ref extra; do
    [[ -z "${base}" ]] && continue
    [[ "${base}" != \#* ]] || continue
    [[ -z "${extra:-}" && "${ref}" =~ ^[0-9a-f]{40}$ ]] || continue
    printf '%s %s\n' "${base}" "${ref}"
  done < "${upstream_refs}"
}

compare_recipe() {
  local base="$1"
  local upstream_dir="$2"
  local local_dir="${source_dir}/${base}"
  local status="current"
  local entry upstream_hash local_hash
  local -a upstream_files=() local_files=() notes=()

  [[ -d "${local_dir}" ]] || die "Vendored recipe directory is missing: ${local_dir}"

  mapfile -t upstream_files < <(
    cd "${upstream_dir}" && find . -type f -not -path './.git/*' | LC_ALL=C sort
  )
  mapfile -t local_files < <(
    cd "${local_dir}" && find . -type f -not -path './.git/*' | LC_ALL=C sort
  )

  while IFS= read -r entry; do
    [[ -n "${entry}" ]] || continue
    status="drift"
    notes+=("added upstream: ${entry#./}")
  done < <(comm -13 <(printf '%s\n' "${local_files[@]}") <(printf '%s\n' "${upstream_files[@]}"))

  while IFS= read -r entry; do
    [[ -n "${entry}" ]] || continue
    status="drift"
    notes+=("removed upstream: ${entry#./}")
  done < <(comm -23 <(printf '%s\n' "${local_files[@]}") <(printf '%s\n' "${upstream_files[@]}"))

  for entry in "${upstream_files[@]}"; do
    [[ -f "${local_dir}/${entry}" ]] || continue
    upstream_hash="$(sha256sum "${upstream_dir}/${entry}" | awk '{print $1}')"
    local_hash="$(sha256sum "${local_dir}/${entry}" | awk '{print $1}')"
    if [[ "${upstream_hash}" != "${local_hash}" ]]; then
      status="drift"
      notes+=("modified upstream: ${entry#./}")
    fi
  done

  printf 'Status: %s\n' "${status}"
  printf 'Vendored: %s\n' "${local_dir#"${repo_root}"/}"
  if ((${#notes[@]} > 0)); then
    printf 'Changed files:\n'
    printf -- '- %s\n' "${notes[@]}"
  fi
  printf '\n'

  [[ "${status}" == "drift" ]]
}

main() {
  local -a package_bases=()
  local -A synced_refs=()
  local base upstream_dir upstream_ref
  local drift=0
  local work_root

  while (($# > 0)); do
    case "$1" in
      --report)
        shift
        (($# > 0)) || die "--report requires a path"
        report_file="$1"
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage >&2
        die "Unsupported argument: $1"
        ;;
    esac
    shift
  done

  [[ -n "${report_file}" ]] || die "A report path is required"
  [[ -r "${nvidia_package_set}" ]] || die "NVIDIA package set not readable: ${nvidia_package_set}"

  require_cmd git
  require_cmd find
  require_cmd sha256sum
  require_cmd comm
  require_cmd sort
  require_cmd awk
  require_cmd date

  # shellcheck source=packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
  . "${nvidia_package_set}"
  package_bases=("${veldmuis_nvidia_580xx_aur_package_bases[@]}")

  while read -r base upstream_ref; do
    synced_refs["${base}"]="${upstream_ref}"
  done < <(read_synced_refs)

  work_root="$(mktemp -d)"
  trap '[[ -n "${work_root:-}" ]] && rm -rf -- "${work_root}"' EXIT

  {
    printf '# NVIDIA 580xx recipe drift\n\n'
    printf 'Generated at: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'The vendored recipes under packages/nvidia-580xx-src differ from the upstream AUR package repositories.\n'
    printf 'Sync them (and packages/nvidia-580xx-src/upstream-refs.txt) when you are ready to rebuild.\n\n'
  } > "${report_file}"

  for base in "${package_bases[@]}"; do
    upstream_dir="${work_root}/${base}"
    clone_upstream "${aur_root%/}/${base}.git" "${upstream_dir}"
    upstream_ref="$(git -C "${upstream_dir}" rev-parse HEAD)"

    {
      printf '## %s\n' "${base}"
      printf 'Upstream HEAD: %s\n' "${upstream_ref}"
      printf 'Last synced: %s\n\n' "${synced_refs[${base}]:-unknown}"
    } >> "${report_file}"

    if compare_recipe "${base}" "${upstream_dir}" >> "${report_file}"; then
      drift=1
    fi
  done

  if ((drift == 1)); then
    printf 'Result: drift detected.\n' >> "${report_file}"
    write_output drift "true"
    log "Upstream NVIDIA recipe drift detected; report: ${report_file}"
  else
    printf 'Result: recipes are current.\n' >> "${report_file}"
    write_output drift "false"
    log "Vendored NVIDIA recipes are current."
  fi
}

main "$@"
