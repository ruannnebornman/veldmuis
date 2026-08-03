#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
ref_mode="${VELDMUIS_AUR_REF_MODE:-locked}"
force_refresh="${VELDMUIS_PACKAGE_REFRESH_FORCE:-0}"
package_base="${PACKAGE_BASE_URL:-https://packages.veldmuislinux.org}"
package_manifest_url="${PUBLISHED_PACKAGE_MANIFEST_URL:-}"
aur_manifest_url="${PUBLISHED_AUR_MANIFEST_URL:-}"
work_root="${RUNNER_TEMP:-/tmp}/veldmuis-package-refresh"
resolved_refs_file="${VELDMUIS_AUR_RESOLVED_REFS_FILE:-${work_root}/resolved-aur-refs.txt}"
published_package_manifest="${work_root}/published-package-manifest.txt"
published_aur_manifest="${work_root}/published-aur-manifest.txt"
published_refs_file="${work_root}/published-aur-refs.txt"
current_source_commit=""
published_source_commit=""

log() {
  printf '[check-package-repo-refresh] %s\n' "$*"
}

die() {
  printf '[check-package-repo-refresh] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_force_refresh() {
  [[ "${force_refresh}" == "1" || "${force_refresh}" == "true" ]]
}

write_output() {
  local name="$1"
  local value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "${name}" "${value}" >> "${GITHUB_OUTPUT}"
  fi
}

write_summary() {
  local refresh_needed="$1"
  local reason="$2"

  if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    return 0
  fi

  {
    echo "## Package Repo Refresh"
    echo
    echo "- Refresh needed: \`${refresh_needed}\`"
    echo "- Reason: ${reason}"
    echo "- Current source commit: \`${current_source_commit}\`"
    echo "- Published source commit: \`${published_source_commit:-unavailable}\`"
    echo "- AUR ref mode: \`${ref_mode}\`"
    echo "- Published package manifest: ${package_manifest_url}"
    echo "- Published AUR manifest: ${aur_manifest_url}"
    if [[ -s "${resolved_refs_file}" ]]; then
      echo
      echo "### Resolved AUR Refs"
      echo
      echo '```text'
      cat "${resolved_refs_file}"
      echo '```'
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
}

finish() {
  local refresh_needed="$1"
  local reason="$2"

  log "${reason}"
  write_output "refresh_needed" "${refresh_needed}"
  write_output "reason" "${reason}"
  write_output "ref_mode" "${ref_mode}"
  write_output "current_source_commit" "${current_source_commit}"
  write_output "published_source_commit" "${published_source_commit}"
  write_output "package_manifest_url" "${package_manifest_url}"
  write_output "aur_manifest_url" "${aur_manifest_url}"
  write_output "resolved_refs_file" "${resolved_refs_file}"
  write_summary "${refresh_needed}" "${reason}"
}

parse_manifest_refs() {
  local manifest_path="$1"

  awk '
    /^\[package_bases\]$/ {
      in_package_bases = 1
      next
    }
    /^\[/ {
      in_package_bases = 0
      next
    }
    in_package_bases && NF >= 2 && $1 !~ /^#/ {
      print $1 " " $2
    }
  ' "${manifest_path}" | sort
}

main() {
  require_cmd awk
  require_cmd curl
  require_cmd git
  require_cmd sort

  mkdir -p "${work_root}"
  : > "${resolved_refs_file}"
  current_source_commit="$(git -C "${repo_root}" rev-parse HEAD)"

  package_base="${package_base%/}"
  [[ -n "${package_base}" ]] || die "PACKAGE_BASE_URL resolves to an empty value"
  package_manifest_url="${package_manifest_url:-${package_base}/veldmuis-package-repo.manifest.txt}"
  aur_manifest_url="${aur_manifest_url:-${package_base}/veldmuis-aur-packages.manifest.txt}"

  if is_force_refresh; then
    finish "true" "Manual force refresh requested."
    return 0
  fi

  if ! curl --fail --silent --show-error --location "${package_manifest_url}" \
    --output "${published_package_manifest}"
  then
    finish "true" "Published package repository manifest is missing or unavailable."
    return 0
  fi

  published_source_commit="$(
    awk -F= '$1 == "source_commit" { print $2; found = 1; exit } END { exit !found }' \
      "${published_package_manifest}" 2>/dev/null || true
  )"

  if [[ -z "${published_source_commit}" ]]; then
    finish "true" "Published package repository manifest has no source commit."
    return 0
  fi

  if [[ "${published_source_commit}" != "${current_source_commit}" ]]; then
    finish "true" "Repository source commit differs from the published package repository."
    return 0
  fi

  log "Resolving AUR refs with VELDMUIS_AUR_REF_MODE=${ref_mode}"
  VELDMUIS_AUR_REF_MODE="${ref_mode}" \
    "${repo_root}/development/build-aur-packages.sh" --resolve-only \
    | sort > "${resolved_refs_file}"

  if ! curl --fail --silent --show-error --location "${aur_manifest_url}" \
    --output "${published_aur_manifest}"
  then
    finish "true" "Published AUR manifest is missing or unavailable."
    return 0
  fi

  parse_manifest_refs "${published_aur_manifest}" > "${published_refs_file}"

  if [[ ! -s "${published_refs_file}" ]]; then
    finish "true" "Published AUR manifest did not contain package base refs."
    return 0
  fi

  if cmp -s "${resolved_refs_file}" "${published_refs_file}"; then
    finish "false" "Published source commit and AUR refs are current."
  else
    finish "true" "Resolved AUR refs differ from published refs."
  fi
}

main "$@"
