#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
package_dir="${VELDMUIS_AUR_PACKAGE_DIR:-${repo_root}/artifacts/aur-packages/current}"
source_root="${VELDMUIS_AUR_WORK_ROOT:-${repo_root}/artifacts/aur-packages/work}"
report_file="${VELDMUIS_AUR_SCAN_REPORT:-}"
nvidia_package_set="${VELDMUIS_NVIDIA_580XX_PACKAGE_SET:-${repo_root}/packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh}"

declare -a findings=()
scan_risk=low

die() {
  printf '[scan-aur-candidate] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scan-aur-candidate.sh --report PATH [--package-dir PATH]

The scanner reports package paths, executable content, privileged files, and
setuid entries. Findings require risk review; they are not proof of malware.
EOF
}

add_finding() {
  scan_risk=high
  findings+=("$1")
}

package_path_for() {
  local package_name="$1"
  local -a matches=()

  mapfile -t matches < <(
    find "${package_dir}" -maxdepth 1 -type f \
      -name "${package_name}-*.pkg.tar.zst" \
      ! -name '*-debug-*.pkg.tar.zst' \
      | sort -V
  )
  ((${#matches[@]} == 1)) || die "Expected one artifact for ${package_name}, found ${#matches[@]}"
  printf '%s\n' "${matches[0]}"
}

scan_package() {
  local package_name="$1"
  local package_path="$2"
  local entry
  local package_info_name
  local entries_file
  local privileged_entries
  local setuid_entries

  package_info_name="$(bsdtar -xOf "${package_path}" .PKGINFO | awk -F ' = ' '$1 == "pkgname" {print $2; exit}')"
  [[ "${package_info_name}" == "${package_name}" ]] || \
    die "Package metadata name mismatch: expected ${package_name}, got ${package_info_name}"

  entries_file="$(mktemp)"
  bsdtar -tf "${package_path}" >"${entries_file}"

  while IFS= read -r entry; do
    if [[ "${entry}" == /* || "${entry}" == ../* || "${entry}" == */../* ]]; then
      add_finding "${package_name}: unsafe archive path ${entry}"
    fi

    case "${entry}" in
      *.install|*.hook|*.service|*.sh)
        if bsdtar -xOf "${package_path}" "${entry}" 2>/dev/null \
          | LC_ALL=C grep -Eiq 'curl|wget|nc[[:space:]]|/dev/tcp|systemctl|pacman[[:space:]]|chmod[[:space:]].*\+s|setcap|mkfs|dd[[:space:]]+if='; then
          add_finding "${package_name}: suspicious command in ${entry}"
        fi
        ;;
    esac
  done <"${entries_file}"

  privileged_entries="$(awk '/^(etc\/(pacman\.d\/hooks|systemd)|usr\/(lib\/(systemd\/system|pacman\/hooks|modules-load\.d|modprobe\.d)|share\/libalpm\/hooks))\// {print}' "${entries_file}")"
  if [[ -n "${privileged_entries}" ]]; then
    add_finding "${package_name}: privileged integration paths present"
  fi

  setuid_entries="$(bsdtar -tvf "${package_path}" | awk '$1 ~ /s/ {print $NF}')"
  if [[ -n "${setuid_entries}" ]]; then
    add_finding "${package_name}: setuid or setgid entry present"
  fi

  rm -f -- "${entries_file}"
}

scan_source_checkout() {
  local package_base="$1"
  local checkout_path="${source_root}/${package_base}"
  local source_file

  [[ -d "${checkout_path}/.git" ]] || {
    add_finding "${package_base}: source checkout is unavailable for scanning"
    return
  }

  while IFS= read -r source_file; do
    case "${source_file}" in
      PKGBUILD|*.install|*.hook|*.service|*.sh)
        if grep -Eiq 'curl|wget|nc[[:space:]]|/dev/tcp|systemctl|pacman[[:space:]]|chmod[[:space:]].*\+s|setcap|mkfs|dd[[:space:]]+if=' \
          "${checkout_path}/${source_file}"; then
          add_finding "${package_base}: suspicious command in source file ${source_file}"
        fi
        ;;
    esac
  done < <(git -C "${checkout_path}" ls-files)
}

main() {
  local package_name package_path
  local -a package_names=()

  while (($# > 0)); do
    case "$1" in
      --report)
        shift
        (($# > 0)) || die "--report requires a path"
        report_file="$1"
        ;;
      --package-dir)
        shift
        (($# > 0)) || die "--package-dir requires a path"
        package_dir="$1"
        ;;
      --source-root)
        shift
        (($# > 0)) || die "--source-root requires a path"
        source_root="$1"
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
  [[ -d "${package_dir}" ]] || die "Candidate package directory is missing: ${package_dir}"
  [[ -r "${nvidia_package_set}" ]] || die "Package set is not readable: ${nvidia_package_set}"
  # shellcheck source=packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
  . "${nvidia_package_set}"
  package_names=("${veldmuis_nvidia_580xx_repository_packages[@]}")

  for package_name in "${package_names[@]}"; do
    package_path="$(package_path_for "${package_name}")"
    scan_package "${package_name}" "${package_path}"
  done
  for package_name in "${veldmuis_nvidia_580xx_aur_package_bases[@]}"; do
    scan_source_checkout "${package_name}"
  done

  {
    printf '# AUR Candidate Package Scan\n\n'
    printf 'Scanner version: 1\n'
    printf 'Package directory: %s\n' "${package_dir}"
    printf 'Source checkout root: %s\n' "${source_root}"
    printf 'Risk: %s\n' "${scan_risk}"
    printf '\nFindings:\n'
    if ((${#findings[@]} == 0)); then
      printf '%s\n' '(none)'
    else
      printf -- '- %s\n' "${findings[@]}"
    fi
    printf '\nThis scan detects review signals; it does not prove that third-party code is safe.\n'
  } >"${report_file}"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'risk=%s\n' "${scan_risk}" >>"${GITHUB_OUTPUT}"
    printf 'report_file=%s\n' "${report_file}" >>"${GITHUB_OUTPUT}"
  fi
  printf '[scan-aur-candidate] Candidate package scan completed with %s risk.\n' "${scan_risk}"
}

main "$@"
