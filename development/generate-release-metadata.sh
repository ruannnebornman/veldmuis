#!/usr/bin/env bash

set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
output_root="${VELDMUIS_RELEASE_OUTPUT_DIR:-}"
release_tag="${VELDMUIS_RELEASE_TAG:-}"
release_sha="${VELDMUIS_RELEASE_SHA:-}"
key_fpr_file="${VELDMUIS_KEY_FPR_FILE:-}"
builder_base_image="${VELDMUIS_BUILDER_BASE_IMAGE:-unknown}"
builder_base_digest="${VELDMUIS_BUILDER_BASE_DIGEST:-unknown}"
builder_image_id="${VELDMUIS_BUILDER_IMAGE_ID:-unknown}"
docker_version="${VELDMUIS_DOCKER_VERSION:-unknown}"
iso_mode="${VELDMUIS_ISO_MODE:-network}"
aur_manifest_source="${VELDMUIS_AUR_MANIFEST:-${repo_root}/artifacts/aur-packages/current/veldmuis-aur-packages.manifest.txt}"
offline_manifest_source="${repo_root}/repos/manifests/veldmuis-offline-packages.tsv"
offline_build_info_source="${repo_root}/repos/manifests/veldmuis-offline-build.txt"

# shellcheck source=development/package-manifest.sh
. "${script_dir}/package-manifest.sh"
# shellcheck source=packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
. "${repo_root}/packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh"

declare -A core_package_names=()
declare -A extra_package_names=()

die() {
  printf '[generate-release-metadata] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

validate_release_tag() {
  local tag="$1"
  local monthly_pattern='^[0-9]{4}\.(0[1-9]|1[0-2])$'
  local daily_pattern='^([0-9]{4})\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])(\.([2-9]|[1-9][0-9]+))?$'
  local date_part=""
  local normalized=""

  if [[ "${tag}" =~ ${monthly_pattern} ]]; then
    normalized="$(date -u -d "${tag//./-}-01" +%Y.%m 2>/dev/null)" || return 1
    [[ "${normalized}" == "${tag}" ]]
    return
  fi

  [[ "${tag}" =~ ${daily_pattern} ]] || return 1
  date_part="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  normalized="$(date -u -d "${date_part//./-}" +%Y.%m.%d 2>/dev/null)" || return 1
  [[ "${normalized}" == "${date_part}" ]]
}

sha256_file() {
  sha256sum "$1" | awk '{ print $1 }'
}

offline_build_value() {
  local key="$1"

  awk -F= -v wanted="${key}" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' \
    "${offline_build_info_source}"
}

spdx_id() {
  local package_name="$1"
  local normalized=""
  local suffix=""

  normalized="$(printf '%s' "${package_name}" | sed 's/[^A-Za-z0-9.-]/-/g')"
  suffix="$(printf '%s' "${package_name}" | sha256sum | awk '{ print substr($1, 1, 12) }')"
  printf '%s-%s' "${normalized}" "${suffix}"
}

source_repository_for() {
  local package_name="$1"

  if [[ -n "${core_package_names[${package_name}]:-}" ]]; then
    printf 'veldmuis-core\n'
  elif [[ -n "${extra_package_names[${package_name}]:-}" ]]; then
    printf 'veldmuis-extra\n'
  else
    printf 'arch\n'
  fi
}

write_package_inventory() {
  local package_list_member=""
  local package_name=""
  local package_version=""
  local source_repository=""
  local -a package_list_members=()
  declare -A seen_packages=()

  mapfile -t package_list_members < <(
    bsdtar -tf "${iso_path}" | \
      awk '/(^|\/)pkglist\.[A-Za-z0-9_+-]+\.txt$/ { print }'
  )
  ((${#package_list_members[@]} == 1)) || \
    die "Expected one package list in the ISO, found ${#package_list_members[@]}."
  package_list_member="${package_list_members[0]}"

  printf 'package\tversion\tsource_repository\n' > "${package_inventory_path}"
  while read -r package_name package_version _; do
    [[ -n "${package_name}" && -n "${package_version}" ]] || continue
    [[ "${package_name}" =~ ^[A-Za-z0-9@._+:-]+$ ]] || \
      die "Unsafe package name in ISO inventory: ${package_name}"
    [[ -z "${seen_packages[${package_name}]:-}" ]] || \
      die "Duplicate package in ISO inventory: ${package_name}"
    seen_packages["${package_name}"]=1
    source_repository="$(source_repository_for "${package_name}")"
    printf '%s\t%s\t%s\n' \
      "${package_name}" "${package_version}" "${source_repository}" \
      >> "${package_inventory_path}"
  done < <(bsdtar -xOf "${iso_path}" "${package_list_member}")

  ((${#seen_packages[@]} > 0)) || die "ISO package inventory is empty."
}

write_spdx_sbom() {
  local package_name=""
  local package_version=""
  local source_repository=""
  local package_spdx_id=""

  {
    printf 'SPDXVersion: SPDX-2.3\n'
    printf 'DataLicense: CC0-1.0\n'
    printf 'SPDXID: SPDXRef-DOCUMENT\n'
    printf 'DocumentName: Veldmuis-%s-x86_64\n' "${release_tag}"
    printf 'DocumentNamespace: https://veldmuislinux.org/spdx/releases/%s/%s\n' \
      "${release_tag}" "${release_sha}"
    printf 'Creator: Organization: Veldmuis Linux\n'
    printf 'Created: %s\n' "${built_at_utc}"

    while IFS=$'\t' read -r package_name package_version source_repository; do
      [[ "${package_name}" != "package" ]] || continue
      package_spdx_id="SPDXRef-Package-$(spdx_id "${package_name}")"
      printf '\nPackageName: %s\n' "${package_name}"
      printf 'SPDXID: %s\n' "${package_spdx_id}"
      printf 'PackageVersion: %s\n' "${package_version}"
      printf 'PackageDownloadLocation: NOASSERTION\n'
      printf 'FilesAnalyzed: false\n'
      printf 'PackageSupplier: NOASSERTION\n'
      printf 'PackageOriginator: NOASSERTION\n'
      printf 'PackageLicenseConcluded: NOASSERTION\n'
      printf 'PackageLicenseDeclared: NOASSERTION\n'
      printf 'PackageCopyrightText: NOASSERTION\n'
      printf 'PackageComment: Installed from %s\n' "${source_repository}"
      printf 'Relationship: SPDXRef-DOCUMENT DESCRIBES %s\n' "${package_spdx_id}"
    done < "${package_inventory_path}"
  } > "${sbom_path}"
}

write_build_inputs() {
  local package_name=""
  local package_version=""

  {
    printf 'release_tag=%s\n' "${release_tag}"
    printf 'release_sha=%s\n' "${release_sha}"
    printf 'installer=%s\n' "${iso_mode}"
    printf 'veldmuis_repository_source_sha=%s\n' "${release_sha}"
    printf 'builder_base_image=%s\n' "${builder_base_image}"
    printf 'builder_base_digest=%s\n' "${builder_base_digest}"
    printf 'builder_image_id=%s\n' "${builder_image_id}"
    printf 'docker_version=%s\n' "${docker_version}"
    printf 'aur_manifest=%s\n' "${aur_manifest_name}"
    printf 'aur_manifest_sha256=%s\n' "$(sha256_file "${aur_manifest_path}")"
    if [[ "${iso_mode}" == "offline" ]]; then
      printf 'arch_repository_snapshot=%s\n' "${arch_repository_snapshot}"
      printf 'offline_package_count=%s\n' "${offline_package_count}"
      printf 'offline_repo_bytes=%s\n' "${offline_repo_bytes}"
      printf 'offline_manifest=%s\n' "${offline_manifest_name}"
      printf 'offline_manifest_sha256=%s\n' "${offline_manifest_sha256}"
    fi
    printf 'package_inventory=%s\n' "${package_inventory_name}"
    printf 'package_inventory_sha256=%s\n' "$(sha256_file "${package_inventory_path}")"
    printf 'generated_at_utc=%s\n' "${built_at_utc}"
    printf '\n[build_tools]\n'
    for package_name in archiso gnupg pacman; do
      package_version="$(pacman -Q "${package_name}" 2>/dev/null | awk '{ print $2 }' || true)"
      [[ -n "${package_version}" ]] || package_version=unavailable
      printf '%s\t%s\n' "${package_name}" "${package_version}"
    done
    printf '\n[aur_inputs]\n'
    awk '
      /^\[package_bases\]$/ { in_section=1; next }
      /^\[/ { in_section=0 }
      in_section && NF { print }
    ' "${aur_manifest_path}"
    printf '\n[aur_source_inputs]\n'
    awk '
      /^\[source_inputs\]$/ { in_section=1; next }
      /^\[/ { in_section=0 }
      in_section && NF { print }
    ' "${aur_manifest_path}"
  } > "${build_inputs_path}"
}

write_signed_manifest() {
  local iso_sha256=""

  iso_sha256="$(sha256_file "${iso_path}")"
  printf '%s  %s\n' "${iso_sha256}" "${iso_name}" > "${checksum_path}"

  {
    printf 'release_tag=%s\n' "${release_tag}"
    printf 'release_sha=%s\n' "${release_sha}"
    printf 'installer=%s\n' "${iso_mode}"
    printf 'release_path=releases/%s\n' "${release_tag}"
    printf 'iso_name=%s\n' "${iso_name}"
    printf 'sha256=%s\n' "${iso_sha256}"
    printf 'iso_bytes=%s\n' "$(stat --format '%s' "${iso_path}")"
    printf 'checksum_name=%s\n' "${checksum_name}"
    printf 'package_inventory_name=%s\n' "${package_inventory_name}"
    printf 'package_inventory_sha256=%s\n' "$(sha256_file "${package_inventory_path}")"
    printf 'sbom_name=%s\n' "${sbom_name}"
    printf 'sbom_sha256=%s\n' "$(sha256_file "${sbom_path}")"
    printf 'build_inputs_name=%s\n' "${build_inputs_name}"
    printf 'build_inputs_sha256=%s\n' "$(sha256_file "${build_inputs_path}")"
    printf 'aur_manifest_name=%s\n' "${aur_manifest_name}"
    printf 'aur_manifest_sha256=%s\n' "$(sha256_file "${aur_manifest_path}")"
    if [[ "${iso_mode}" == "offline" ]]; then
      printf 'offline_manifest_name=%s\n' "${offline_manifest_name}"
      printf 'offline_manifest_sha256=%s\n' "${offline_manifest_sha256}"
      printf 'offline_repo_bytes=%s\n' "${offline_repo_bytes}"
      printf 'offline_package_count=%s\n' "${offline_package_count}"
      printf 'arch_repository_snapshot=%s\n' "${arch_repository_snapshot}"
    fi
    printf 'signing_fingerprint=%s\n' "${key_fingerprint}"
    printf 'builder_base_digest=%s\n' "${builder_base_digest}"
    printf 'built_at_utc=%s\n' "${built_at_utc}"
  } > "${manifest_path}"

  gpg --batch --yes --local-user "${key_fingerprint}" \
    --output "${signature_path}" --detach-sign "${manifest_path}"
  gpg --batch --verify "${signature_path}" "${manifest_path}" >/dev/null 2>&1 || \
    die "Release manifest signature verification failed."
}

main() {
  local expected_iso_name=""
  local file_name=""
  local package_name=""

  require_cmd awk
  require_cmd bsdtar
  require_cmd date
  require_cmd gpg
  require_cmd install
  require_cmd pacman
  require_cmd sed
  require_cmd sha256sum
  require_cmd stat
  require_cmd tr

  [[ -n "${output_root}" && -d "${output_root}" ]] || \
    die "VELDMUIS_RELEASE_OUTPUT_DIR must name the ISO output directory."
  validate_release_tag "${release_tag}" || die "Invalid release tag: ${release_tag}"
  [[ "${release_sha}" =~ ^[0-9a-f]{40}$ ]] || die "Invalid release commit: ${release_sha}"
  [[ -r "${key_fpr_file}" ]] || die "Signing fingerprint marker is missing: ${key_fpr_file}"
  [[ -r "${aur_manifest_source}" ]] || die "AUR input manifest is missing: ${aur_manifest_source}"
  [[ "${builder_base_digest}" == *@sha256:* ]] || \
    die "Builder base image digest is not immutable: ${builder_base_digest}"
  [[ "${builder_image_id}" == sha256:* ]] || \
    die "Builder image ID is invalid: ${builder_image_id}"
  case "${iso_mode}" in
    network|offline)
      ;;
    *)
      die "VELDMUIS_ISO_MODE must be network or offline, got: ${iso_mode}"
      ;;
  esac

  key_fingerprint="$(tr -d '[:space:]' < "${key_fpr_file}")"
  [[ "${key_fingerprint}" =~ ^[0-9A-Fa-f]{40}$ ]] || \
    die "Invalid signing fingerprint: ${key_fingerprint}"
  gpg --batch --list-secret-keys "${key_fingerprint}" >/dev/null 2>&1 || \
    die "Signing key is unavailable: ${key_fingerprint}"

  for package_name in "${veldmuis_core_package_order[@]}"; do
    core_package_names["${package_name}"]=1
  done
  for package_name in \
    "${veldmuis_extra_package_order[@]}" \
    "${veldmuis_nvidia_580xx_repository_packages[@]}"
  do
    extra_package_names["${package_name}"]=1
  done

  expected_iso_name="veldmuis-${release_tag}-${iso_mode}-x86_64.iso"
  iso_path="${output_root}/${expected_iso_name}"
  [[ -f "${iso_path}" ]] || die "Expected ISO is missing: ${iso_path}"
  iso_name="${expected_iso_name}"
  artifact_stem="${iso_name%.iso}"
  checksum_name="${iso_name}.sha256"
  checksum_path="${output_root}/${checksum_name}"
  manifest_name="${artifact_stem}.manifest.txt"
  manifest_path="${output_root}/${manifest_name}"
  signature_name="${manifest_name}.sig"
  signature_path="${output_root}/${signature_name}"
  package_inventory_name="${artifact_stem}.packages.tsv"
  package_inventory_path="${output_root}/${package_inventory_name}"
  sbom_name="${artifact_stem}.spdx"
  sbom_path="${output_root}/${sbom_name}"
  build_inputs_name="${artifact_stem}.build-inputs.txt"
  build_inputs_path="${output_root}/${build_inputs_name}"
  aur_manifest_name="${artifact_stem}.aur-packages.manifest.txt"
  aur_manifest_path="${output_root}/${aur_manifest_name}"
  built_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [[ "${iso_mode}" == "offline" ]]; then
    [[ -s "${offline_manifest_source}" && -s "${offline_build_info_source}" ]] || \
      die "Offline repository metadata is missing."
    arch_repository_snapshot="$(offline_build_value arch_repository_snapshot)"
    offline_package_count="$(offline_build_value offline_package_count)"
    offline_repo_bytes="$(offline_build_value offline_repo_bytes)"
    offline_manifest_sha256="$(offline_build_value offline_manifest_sha256)"
    [[ "${arch_repository_snapshot}" =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}$ ]] || \
      die "Offline repository snapshot is invalid."
    [[ "${offline_package_count}" =~ ^[1-9][0-9]*$ ]] || \
      die "Offline repository package count is invalid."
    [[ "${offline_repo_bytes}" =~ ^[1-9][0-9]*$ ]] || \
      die "Offline repository size is invalid."
    [[ "${offline_manifest_sha256}" =~ ^[0-9a-f]{64}$ && \
      "$(sha256_file "${offline_manifest_source}")" == "${offline_manifest_sha256}" ]] || \
      die "Offline repository manifest checksum is invalid."
    offline_manifest_name="${artifact_stem}.offline-packages.tsv"
    offline_manifest_path="${output_root}/${offline_manifest_name}"
    install -m600 "${offline_manifest_source}" "${offline_manifest_path}"
  fi

  install -m600 "${aur_manifest_source}" "${aur_manifest_path}"
  write_package_inventory
  write_spdx_sbom
  write_build_inputs
  write_signed_manifest

  for file_name in \
    "${checksum_path}" \
    "${manifest_path}" \
    "${signature_path}" \
    "${package_inventory_path}" \
    "${sbom_path}" \
    "${build_inputs_path}" \
    "${aur_manifest_path}"
  do
    [[ -s "${file_name}" ]] || die "Generated release metadata is empty: ${file_name}"
    chmod 644 "${file_name}"
  done

  if [[ "${iso_mode}" == "offline" ]]; then
    [[ -s "${offline_manifest_path}" ]] || die "Generated offline package manifest is empty."
    chmod 644 "${offline_manifest_path}"
  fi

  printf '[generate-release-metadata] Generated and verified release metadata.\n'
  printf '  ISO: %s\n' "${iso_path}"
  printf '  Manifest: %s\n' "${manifest_path}"
  printf '  Signature: %s\n' "${signature_path}"
  printf '  Package inventory: %s\n' "${package_inventory_path}"
  printf '  SPDX SBOM: %s\n' "${sbom_path}"
  printf '  Build inputs: %s\n' "${build_inputs_path}"
  if [[ "${iso_mode}" == "offline" ]]; then
    printf '  Offline packages: %s\n' "${offline_manifest_path}"
  fi
}

main "$@"
