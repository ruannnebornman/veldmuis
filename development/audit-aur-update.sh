#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
lock_file="${VELDMUIS_AUR_LOCK_FILE:-${script_dir}/aur-packages.lock}"
resolved_file="${VELDMUIS_AUR_RESOLVED_REFS_FILE:-}"
report_file="${VELDMUIS_AUR_UPDATE_REPORT:-}"
work_root="${VELDMUIS_AUR_AUDIT_ROOT:-${RUNNER_TEMP:-/tmp}/veldmuis-aur-audit}"

declare -A accepted_refs=()
declare -A candidate_refs=()
declare -a package_bases=()
highest_risk=low
updates_available=false

die() {
  printf '[audit-aur-update] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  audit-aur-update.sh --resolved-refs PATH --report PATH [--work-root PATH]

The report compares resolved AUR commits with the accepted lock and classifies
recipe or privileged-package changes as high risk.
EOF
}

write_output() {
  local name="$1"
  local value="$2"

  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf '%s=%s\n' "${name}" "${value}" >> "${GITHUB_OUTPUT}"
}

set_highest_risk() {
  [[ "$1" == high ]] && highest_risk=high
}

read_refs() {
  local file="$1"
  local target="$2"
  local package_base ref extra

  while read -r package_base ref extra; do
    [[ -z "${package_base}" ]] && continue
    [[ "${package_base}" != \#* ]] || continue
    [[ -z "${extra:-}" && "${ref}" =~ ^[0-9a-f]{40}$ ]] || \
      die "Invalid AUR ref entry in ${file}: ${package_base} ${ref} ${extra:-}"
    if [[ "${target}" == accepted ]]; then
      [[ -z "${accepted_refs[${package_base}]:-}" ]] || die "Duplicate accepted AUR ref: ${package_base}"
      accepted_refs["${package_base}"]="${ref}"
      package_bases+=("${package_base}")
    else
      [[ -z "${candidate_refs[${package_base}]:-}" ]] || die "Duplicate candidate AUR ref: ${package_base}"
      candidate_refs["${package_base}"]="${ref}"
    fi
  done <"${file}"
}

aur_url() {
  printf 'https://aur.archlinux.org/%s.git' "$1"
}

classify_change() {
  local package_base="$1"
  local repo_path="$2"
  local old_ref="$3"
  local new_ref="$4"
  local path
  local package_risk=low
  local reason
  local -a changed_paths=()
  local -a risk_reasons=()

  mapfile -t changed_paths < <(
    git -C "${repo_path}" diff --name-only "${old_ref}" "${new_ref}"
  )

  if ((${#changed_paths[@]} > 0)); then
    updates_available=true
  fi

  if [[ "${package_base}" == *nvidia* ]]; then
    package_risk=high
    risk_reasons+=("proprietary NVIDIA package input requires review")
  fi

  for path in "${changed_paths[@]}"; do
    case "${path}" in
      PKGBUILD|*.install|*.hook|*.service|*systemd*|*pacman*|*.patch|*.run)
        package_risk=high
        risk_reasons+=("privileged or executable build input changed: ${path}")
        ;;
      *)
        ;;
    esac
  done

  if ! git -C "${repo_path}" merge-base --is-ancestor "${old_ref}" "${new_ref}"; then
    package_risk=high
    risk_reasons+=("candidate history is not a descendant of the accepted ref")
  fi

  set_highest_risk "${package_risk}"
  {
    printf '\n### %s\n' "${package_base}"
    printf 'Accepted ref: %s\n' "${old_ref}"
    printf 'Candidate ref: %s\n' "${new_ref}"
    printf 'Risk: %s\n' "${package_risk}"
    if ((${#risk_reasons[@]} > 0)); then
      printf 'Risk reasons:\n'
      for reason in "${risk_reasons[@]}"; do
        printf -- '- %s\n' "${reason}"
      done
    fi
    printf 'Changed paths:\n'
    if ((${#changed_paths[@]} == 0)); then
      printf '%s\n' '(none)'
    else
      printf -- '- %s\n' "${changed_paths[@]}"
    fi
    printf '\nPKGBUILD diff:\n'
    git -C "${repo_path}" diff --no-ext-diff --unified=3 \
      "${old_ref}" "${new_ref}" -- PKGBUILD | awk 'NR <= 500'
  } >>"${report_file}"
}

main() {
  local package_base old_ref new_ref repo_path

  while (($# > 0)); do
    case "$1" in
      --resolved-refs)
        shift
        (($# > 0)) || die "--resolved-refs requires a path"
        resolved_file="$1"
        ;;
      --report)
        shift
        (($# > 0)) || die "--report requires a path"
        report_file="$1"
        ;;
      --work-root)
        shift
        (($# > 0)) || die "--work-root requires a path"
        work_root="$1"
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

  [[ -n "${resolved_file}" && -r "${resolved_file}" ]] || die "Resolved refs are required"
  [[ -n "${report_file}" ]] || die "A report path is required"
  [[ -r "${lock_file}" ]] || die "Accepted lock file is not readable: ${lock_file}"

  mkdir -p "${work_root}"
  : >"${report_file}"
  read_refs "${lock_file}" accepted
  read_refs "${resolved_file}" candidate
  ((${#package_bases[@]} > 0)) || die "Accepted lock file contains no package bases"

  {
    printf '# AUR Update Candidate\n\n'
    printf 'Generated at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Accepted lock: %s\n' "${lock_file#"${repo_root}"/}"
    printf 'Risk policy: recipe, executable, privileged, and proprietary NVIDIA changes require review.\n'
  } >"${report_file}"

  for package_base in "${package_bases[@]}"; do
    old_ref="${accepted_refs[${package_base}]}"
    new_ref="${candidate_refs[${package_base}]:-}"
    [[ -n "${new_ref}" ]] || die "Candidate refs are missing package base: ${package_base}"
    [[ "${new_ref}" != "${old_ref}" ]] || continue
    updates_available=true

    repo_path="${work_root}/${package_base}"
    rm -rf -- "${repo_path}"
    git clone --quiet "$(aur_url "${package_base}")" "${repo_path}"
    git -C "${repo_path}" fetch --quiet origin "${old_ref}" "${new_ref}"
    classify_change "${package_base}" "${repo_path}" "${old_ref}" "${new_ref}"
  done

  printf '\nOverall risk: %s\n' "${highest_risk}" >>"${report_file}"
  write_output updates_available "${updates_available}"
  write_output risk "${highest_risk}"
  write_output report_file "${report_file}"

  if [[ "${updates_available}" == true ]]; then
    printf '[audit-aur-update] Candidate updates require %s risk handling.\n' "${highest_risk}"
  else
    printf '[audit-aur-update] No AUR updates are available.\n'
  fi
}

main "$@"
