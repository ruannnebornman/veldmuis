#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
lock_file="${VELDMUIS_AUR_LOCK_FILE:-${script_dir}/aur-packages.lock}"
work_root="${VELDMUIS_AUR_WORK_ROOT:-${repo_root}/artifacts/aur-packages/work}"
package_dir="${VELDMUIS_AUR_PACKAGE_DIR:-${repo_root}/artifacts/aur-packages/current}"
manifest_path="${VELDMUIS_AUR_MANIFEST:-${package_dir}/veldmuis-aur-packages.manifest.txt}"
ref_mode="${VELDMUIS_AUR_REF_MODE:-locked}"

package_bases=(
  "nvidia-580xx-utils"
  "lib32-nvidia-580xx-utils"
  "nvidia-580xx-settings"
)

declare -A resolved_refs=()

log() {
  printf '[build-aur-packages] %s\n' "$*"
}

die() {
  printf '[build-aur-packages] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  build-aur-packages.sh
  build-aur-packages.sh --resolve-only

Environment:
  VELDMUIS_AUR_REF_MODE=locked|latest
  VELDMUIS_AUR_LOCK_FILE=/path/to/aur-packages.lock
  VELDMUIS_AUR_WORK_ROOT=/path/to/work
  VELDMUIS_AUR_PACKAGE_DIR=/path/to/package-output
  VELDMUIS_AUR_MANIFEST=/path/to/manifest.txt
  VELDMUIS_AUR_REF_<PACKAGE_BASE>=commit-or-ref

Examples:
  VELDMUIS_AUR_REF_MODE=latest ./development/build-aur-packages.sh
  VELDMUIS_AUR_REF_NVIDIA_580XX_UTILS=master ./development/build-aur-packages.sh
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

aur_url() {
  local package_base="$1"
  printf 'https://aur.archlinux.org/%s.git' "${package_base}"
}

env_ref_name() {
  local package_base="$1"
  local suffix

  suffix="$(printf '%s' "${package_base}" | tr '[:lower:]-' '[:upper:]_')"
  printf 'VELDMUIS_AUR_REF_%s' "${suffix}"
}

locked_ref() {
  local package_base="$1"

  [[ -r "${lock_file}" ]] || die "AUR lock file not readable: ${lock_file}"

  awk -v package_base="${package_base}" '
    $1 == package_base && $1 !~ /^#/ {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "${lock_file}" || die "No locked ref found for ${package_base}"
}

latest_ref() {
  local package_base="$1"
  local ref

  ref="$(git ls-remote "$(aur_url "${package_base}")" HEAD | awk 'NR == 1 {print $1; exit}')"
  [[ -n "${ref}" ]] || die "Unable to resolve latest AUR ref for ${package_base}"
  printf '%s' "${ref}"
}

resolve_ref() {
  local package_base="$1"
  local ref_env_name ref_env_value

  ref_env_name="$(env_ref_name "${package_base}")"
  ref_env_value="${!ref_env_name:-}"

  if [[ -n "${ref_env_value}" ]]; then
    printf '%s' "${ref_env_value}"
    return
  fi

  case "${ref_mode}" in
    locked)
      locked_ref "${package_base}"
      ;;
    latest)
      latest_ref "${package_base}"
      ;;
    *)
      die "VELDMUIS_AUR_REF_MODE must be locked or latest, got: ${ref_mode}"
      ;;
  esac
}

resolve_all_refs() {
  local package_base

  for package_base in "${package_bases[@]}"; do
    resolved_refs["${package_base}"]="$(resolve_ref "${package_base}")"
  done
}

print_resolved_refs() {
  local package_base

  for package_base in "${package_bases[@]}"; do
    printf '%s %s\n' "${package_base}" "${resolved_refs[${package_base}]}"
  done
}

prepare_output_dirs() {
  rm -rf "${work_root}" "${package_dir}"
  mkdir -p "${work_root}" "${package_dir}"
}

copy_package_outputs() {
  local package_base="$1"
  local build_dir="$2"
  local -a package_paths=()
  local package_path

  mapfile -t package_paths < <(
    find "${build_dir}" -maxdepth 1 -type f \
      -name '*.pkg.tar.zst' \
      ! -name '*-debug-*.pkg.tar.zst' \
      | sort -V
  )

  ((${#package_paths[@]} > 0)) || die "No package artifacts produced for ${package_base}"

  for package_path in "${package_paths[@]}"; do
    cp -f "${package_path}" "${package_dir}/"
  done
}

latest_built_package() {
  local build_dir="$1"
  local package_name="$2"
  local package_path

  package_path="$(find "${build_dir}" -maxdepth 1 -type f \
    -name "${package_name}-*.pkg.tar.zst" \
    ! -name '*-debug-*.pkg.tar.zst' \
    | sort -V \
    | tail -n 1)"

  [[ -n "${package_path}" ]] || die "Built package not found: ${package_name}"
  printf '%s' "${package_path}"
}

install_built_dependencies() {
  local package_base="$1"
  local build_dir="$2"
  local package_path

  case "${package_base}" in
    nvidia-580xx-utils)
      package_path="$(latest_built_package "${build_dir}" "nvidia-580xx-utils")"
      log "Installing build dependency from local artifact: $(basename "${package_path}")"
      sudo pacman -U --noconfirm --needed "${package_path}"
      ;;
  esac
}

package_info_value() {
  local package_path="$1"
  local key="$2"

  bsdtar -xOf "${package_path}" .PKGINFO \
    | awk -F ' = ' -v key="${key}" '$1 == key {print $2; exit}'
}

package_info_has_value() {
  local package_path="$1"
  local key="$2"
  local expected="$3"

  bsdtar -xOf "${package_path}" .PKGINFO \
    | awk -F ' = ' -v key="${key}" -v expected="${expected}" '
      $1 == key && $2 == expected {
        found = 1
        exit
      }
      END {
        exit !found
      }
    '
}

package_has_license_file() {
  local package_path="$1"

  bsdtar -tf "${package_path}" \
    | awk '
      /^usr\/share\/licenses\// {
        found = 1
        exit
      }
      END {
        exit !found
      }
    '
}

expected_license() {
  local package_name="$1"

  case "${package_name}" in
    nvidia-580xx-utils|opencl-nvidia-580xx|nvidia-580xx-dkms)
      printf 'custom'
      ;;
    lib32-nvidia-580xx-utils|lib32-opencl-nvidia-580xx)
      printf 'custom'
      ;;
    nvidia-580xx-settings|libxnvctrl-580xx)
      printf 'GPL-2.0-only'
      ;;
    *)
      die "Unexpected AUR package artifact: ${package_name}"
      ;;
  esac
}

validate_package_artifact() {
  local package_path="$1"
  local package_name expected

  package_name="$(package_info_value "${package_path}" "pkgname")"
  [[ -n "${package_name}" ]] || die "Unable to read package name from: ${package_path}"

  expected="$(expected_license "${package_name}")"
  package_info_has_value "${package_path}" "license" "${expected}" \
    || die "Package ${package_name} does not declare expected license: ${expected}"

  if [[ "${expected}" == "custom" ]]; then
    package_has_license_file "${package_path}" \
      || die "Package ${package_name} does not include a license path under /usr/share/licenses"
  fi
}

validate_package_artifacts() {
  local package_path

  while IFS= read -r package_path; do
    validate_package_artifact "${package_path}"
  done < <(
    find "${package_dir}" -maxdepth 1 -type f \
      -name '*.pkg.tar.zst' \
      | sort -V
  )
}

build_package_base() {
  local package_base="$1"
  local ref="$2"
  local build_dir="${work_root}/${package_base}"

  log "Cloning ${package_base} at ${ref}"
  git clone --quiet "$(aur_url "${package_base}")" "${build_dir}"
  git -C "${build_dir}" checkout --quiet --detach "${ref}"

  log "Building ${package_base}"
  (
    cd "${build_dir}"
    makepkg --syncdeps --noconfirm --cleanbuild --force
  )

  copy_package_outputs "${package_base}" "${build_dir}"
  install_built_dependencies "${package_base}" "${build_dir}"
}

write_manifest() {
  local manifest_tmp="${manifest_path}.tmp"
  local package_base package_path

  {
    printf 'built_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'source=aur\n'
    printf 'fallback_used=false\n'
    printf 'ref_mode=%s\n' "${ref_mode}"
    printf 'lock_file=%s\n' "${lock_file}"
    printf 'package_dir=%s\n' "${package_dir}"
    printf '\n[package_bases]\n'
    for package_base in "${package_bases[@]}"; do
      printf '%s\t%s\t%s\n' \
        "${package_base}" \
        "${resolved_refs[${package_base}]}" \
        "$(aur_url "${package_base}")"
    done

    printf '\n[package_files]\n'
    while IFS= read -r package_path; do
      sha256sum "${package_path}" | awk -v file_name="${package_path##*/}" '{print $1 "\t" file_name}'
    done < <(
      find "${package_dir}" -maxdepth 1 -type f \
        -name '*.pkg.tar.zst' \
        | sort -V
    )
  } > "${manifest_tmp}"

  mv -f "${manifest_tmp}" "${manifest_path}"
}

main() {
  local resolve_only=0
  local package_base

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --resolve-only)
      resolve_only=1
      ;;
    "")
      ;;
    *)
      usage >&2
      die "Unsupported argument: $1"
      ;;
  esac

  require_cmd awk
  require_cmd git
  require_cmd tr

  resolve_all_refs

  if (( resolve_only )); then
    print_resolved_refs
    exit 0
  fi

  require_cmd cp
  require_cmd bsdtar
  require_cmd date
  require_cmd find
  require_cmd makepkg
  require_cmd sha256sum
  require_cmd sort
  require_cmd sudo
  require_cmd tail

  prepare_output_dirs

  for package_base in "${package_bases[@]}"; do
    build_package_base "${package_base}" "${resolved_refs[${package_base}]}"
  done

  validate_package_artifacts
  write_manifest
  log "Built AUR package artifacts under: ${package_dir}"
  log "Wrote manifest: ${manifest_path}"
}

main "$@"
