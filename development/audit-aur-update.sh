#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
lock_file="${VELDMUIS_AUR_LOCK_FILE:-${script_dir}/aur-packages.lock}"
resolved_file="${VELDMUIS_AUR_RESOLVED_REFS_FILE:-}"
report_file="${VELDMUIS_AUR_UPDATE_REPORT:-}"
work_root="${VELDMUIS_AUR_AUDIT_ROOT:-${RUNNER_TEMP:-/tmp}/veldmuis-aur-audit}"
aur_repo_root="${VELDMUIS_AUR_REPO_ROOT:-}"

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
recipe or privileged-package changes as high risk. NVIDIA candidates receive a
low classification only for an allowlisted metadata-only PKGBUILD diff.
EOF
}

write_output() {
  local name="$1"
  local value="$2"

  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf '%s=%s\n' "${name}" "${value}" >> "${GITHUB_OUTPUT}"
}

set_highest_risk() {
  if [[ "$1" == high ]]; then
    highest_risk=high
  fi
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
  if [[ -n "${aur_repo_root}" ]]; then
    printf '%s/%s' "${aur_repo_root%/}" "$1"
  else
    printf 'https://aur.archlinux.org/%s.git' "$1"
  fi
}

is_nvidia_package_base() {
  [[ "${1,,}" == *nvidia* ]]
}

is_safe_metadata_assignment() {
  local line="$1"
  local command_substitution=$'\x24('
  local backtick=$'\x60'

  [[ "${line}" =~ ^[[:space:]]*(pkgver|pkgrel|epoch|source|sha256sums|b2sums|md5sums|validpgpkeys)(\[[^]]+\])?[[:space:]]*= ]] || return 1
  case "${line}" in
    *"${command_substitution}"*|*"${backtick}"*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*)
      return 1
      ;;
  esac
}

is_safe_metadata_continuation() {
  local line="$1"
  local command_substitution=$'\x24('
  local backtick=$'\x60'

  case "${line}" in
    *"${command_substitution}"*|*"${backtick}"*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*)
      return 1
      ;;
  esac

  [[ "${line}" =~ ^[[:space:]]*\" ]] ||
    [[ "${line}" =~ ^[[:space:]]*\' ]] ||
    [[ "${line}" =~ ^[[:space:]]*\)[[:space:]]*$ ]] ||
    [[ "${line}" =~ ^[[:space:]]*\\[[:space:]]*$ ]]
}

metadata_context_after_line() {
  local line="$1"
  local context="$2"

  if [[ "${line}" =~ ^[[:space:]]*(source|sha256sums|b2sums|md5sums|validpgpkeys)(\[[^]]+\])?[[:space:]]*=.*\([[:space:]]*$ ]]; then
    printf 'array'
    return 0
  fi

  if [[ "${line}" =~ ^[[:space:]]*[[:alpha:]_][[:alnum:]_]*= ]]; then
    printf '%s' ''
    return 0
  fi

  if [[ -n "${context}" && "${line}" =~ ^[[:space:]]*\)[[:space:]]*$ ]]; then
    printf '%s' ''
    return 0
  fi

  printf '%s' "${context}"
}

nvidia_metadata_diff_is_safe() {
  local repo_path="$1"
  local old_ref="$2"
  local new_ref="$3"
  local line content old_context new_context
  local -a diff_lines=()

  mapfile -t diff_lines < <(
    git -C "${repo_path}" diff --no-ext-diff --no-renames --unified=3 \
      "${old_ref}" "${new_ref}" -- PKGBUILD
  )
  ((${#diff_lines[@]} > 0)) || return 1

  old_context=''
  new_context=''
  for line in "${diff_lines[@]}"; do
    case "${line}" in
      'diff --git '*|'index '*|'+++ '*|'--- '*|'@@ '*)
        old_context=''
        new_context=''
        continue
        ;;
      +*)
        content="${line:1}"
        if ! is_safe_metadata_assignment "${content}" &&
          { [[ -z "${new_context}" ]] || ! is_safe_metadata_continuation "${content}"; }; then
          return 1
        fi
        new_context="$(metadata_context_after_line "${content}" "${new_context}")"
        ;;
      -*)
        content="${line:1}"
        if ! is_safe_metadata_assignment "${content}" &&
          { [[ -z "${old_context}" ]] || ! is_safe_metadata_continuation "${content}"; }; then
          return 1
        fi
        old_context="$(metadata_context_after_line "${content}" "${old_context}")"
        ;;
      ' '*|\\\ No\ newline\ at\ end\ of\ file)
        content="${line:1}"
        old_context="$(metadata_context_after_line "${content}" "${old_context}")"
        new_context="$(metadata_context_after_line "${content}" "${new_context}")"
        ;;
      *)
        return 1
        ;;
    esac
  done
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
  local nvidia_package=0
  local routine_metadata_change=0

  mapfile -t changed_paths < <(
    git -C "${repo_path}" diff --name-only "${old_ref}" "${new_ref}"
  )

  if ((${#changed_paths[@]} > 0)); then
    updates_available=true
  fi

  if is_nvidia_package_base "${package_base}"; then
    nvidia_package=1
    if nvidia_metadata_diff_is_safe "${repo_path}" "${old_ref}" "${new_ref}"; then
      routine_metadata_change=1
    else
      package_risk=high
      risk_reasons+=("NVIDIA update changes more than approved metadata")
    fi
  fi

  for path in "${changed_paths[@]}"; do
    case "${path}" in
      PKGBUILD)
        if ((nvidia_package == 0 || routine_metadata_change == 0)); then
          package_risk=high
          risk_reasons+=("build recipe changed outside the approved metadata-only policy")
        fi
        ;;
      *.install|*.hook|*.service|*systemd*|*pacman*|*.patch|*.run)
        package_risk=high
        risk_reasons+=("privileged or executable build input changed: ${path}")
        ;;
      *)
        if ((nvidia_package == 1)); then
          package_risk=high
          risk_reasons+=("NVIDIA update changed an unapproved input: ${path}")
        fi
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
    if ((routine_metadata_change)) && [[ "${package_risk}" == low ]]; then
      printf 'Classification: automated metadata-only NVIDIA policy\n'
    fi
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
    printf '\nCandidate recipe diff:\n'
    git -C "${repo_path}" diff --no-ext-diff --unified=3 \
      "${old_ref}" "${new_ref}" -- "${changed_paths[@]}"
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
    printf 'Risk policy: routine NVIDIA metadata-only changes may pass automated checks; recipe, executable, privileged, and other unapproved changes require review.\n'
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

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
