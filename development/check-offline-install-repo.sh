#!/usr/bin/env bash

set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
repos_root="${repo_root}/repos"
arch="${VELDMUIS_ARCH:-x86_64}"
package_sets="${repo_root}/packages/veldmuis-calamares-config/installer-package-sets.sh"
keyring_root="${repo_root}/packages/veldmuis-keyring"
manifest_path="${repos_root}/manifests/veldmuis-offline-packages.tsv"
build_info_path="${repos_root}/manifests/veldmuis-offline-build.txt"
temp_root=""
pacman_conf=""
pacman_gpgdir=""

die() {
  printf '[check-offline-install-repo] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[check-offline-install-repo] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  [[ -z "${temp_root}" || ! -d "${temp_root}" ]] || rm -rf "${temp_root}"
}

build_info_value() {
  local key="$1"
  awk -F= -v wanted="${key}" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' \
    "${build_info_path}"
}

validate_manifest() {
  local expected_hash=""
  local actual_hash=""
  local expected_count=""
  local actual_count=""
  local package_name=""
  local package_version=""
  local package_arch=""
  local source_repo=""
  local file_size=""
  local expected_package_hash=""
  local package_filename=""
  local package_path=""
  declare -A seen_packages=()

  [[ -s "${manifest_path}" && -s "${build_info_path}" ]] || \
    die "Offline repository manifest or build record is missing."
  [[ "$(head -n 1 "${manifest_path}")" == $'package\tversion\tarchitecture\toriginal_repository\tfile_size\tsha256\tfilename' ]] || \
    die "Offline package manifest header is invalid."

  expected_hash="$(build_info_value offline_manifest_sha256)"
  actual_hash="$(sha256sum "${manifest_path}" | awk '{ print $1 }')"
  [[ "${expected_hash}" == "${actual_hash}" ]] || die "Offline package manifest checksum mismatch."
  expected_count="$(build_info_value offline_package_count)"
  actual_count="$(
    awk -f "${repo_root}/development/count-offline-manifest-packages.awk" \
      "${manifest_path}"
  )"
  [[ "${expected_count}" =~ ^[1-9][0-9]*$ && "${expected_count}" == "${actual_count}" ]] || \
    die "Offline package manifest count mismatch."

  while IFS=$'\t' read -r \
    package_name package_version package_arch source_repo file_size \
    expected_package_hash package_filename
  do
    [[ "${package_name}" != package ]] || continue
    [[ -n "${package_name}" && -n "${package_version}" && "${package_arch}" =~ ^(any|${arch})$ ]] || \
      die "Malformed offline package manifest entry for ${package_name:-unknown}."
    [[ "${source_repo}" =~ ^(core|extra|multilib)$ ]] || \
      die "Unexpected source repository in offline manifest: ${source_repo}"
    [[ "${file_size}" =~ ^[1-9][0-9]*$ && "${expected_package_hash}" =~ ^[0-9a-f]{64}$ ]] || \
      die "Invalid size or checksum in offline manifest for ${package_name}."
    [[ -z "${seen_packages[${package_name}]:-}" ]] || \
      die "Duplicate package in offline manifest: ${package_name}"
    seen_packages["${package_name}"]=1

    package_path="${repos_root}/veldmuis-offline/os/${arch}/${package_filename}"
    [[ -s "${package_path}" && -s "${package_path}.sig" ]] || \
      die "Offline package or signature is missing: ${package_filename}"
    [[ "$(stat --format '%s' "${package_path}")" == "${file_size}" ]] || \
      die "Offline package size mismatch: ${package_filename}"
    [[ "$(sha256sum "${package_path}" | awk '{ print $1 }')" == "${expected_package_hash}" ]] || \
      die "Offline package checksum mismatch: ${package_filename}"
  done <"${manifest_path}"
}

setup_pacman() {
  local keyring_file=""

  for keyring_file in veldmuis.gpg veldmuis-trusted veldmuis-revoked; do
    [[ -r "${keyring_root}/${keyring_file}" ]] || \
      die "Missing Veldmuis keyring file: ${keyring_root}/${keyring_file}"
  done

  install -d -m755 "${temp_root}/root" "${temp_root}/db" "${temp_root}/cache"
  install -d -m700 "${pacman_gpgdir}"
  pacman-key --gpgdir "${pacman_gpgdir}" --init >/dev/null
  pacman-key --gpgdir "${pacman_gpgdir}" --populate archlinux >/dev/null
  pacman-key --gpgdir "${pacman_gpgdir}" \
    --populate-from "${keyring_root}" --populate veldmuis >/dev/null
  pacman-key --gpgdir "${pacman_gpgdir}" --updatedb >/dev/null

  cat >"${pacman_conf}" <<EOF
[options]
Architecture = ${arch}
RootDir = ${temp_root}/root
DBPath = ${temp_root}/db
CacheDir = ${temp_root}/cache
GPGDir = ${pacman_gpgdir}
LogFile = ${temp_root}/pacman.log
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Required

[veldmuis-core]
SigLevel = Required DatabaseRequired
Server = file://${repos_root}/veldmuis-core/os/\$arch

[veldmuis-extra]
SigLevel = Required DatabaseRequired
Server = file://${repos_root}/veldmuis-extra/os/\$arch

[veldmuis-offline]
SigLevel = Required DatabaseRequired
Server = file://${repos_root}/veldmuis-offline/os/\$arch
EOF

  pacman --config "${pacman_conf}" -Sy --noconfirm
}

validate_scenario() {
  local scenario="$1"
  shift
  local resolution_path="${temp_root}/scenario-${scenario}.txt"
  local package_name=""
  local source_repo=""
  local package_url=""
  local package_path=""
  declare -A seen_packages=()

  (($# > 0)) || die "Scenario ${scenario} has no package seed."
  pacman --config "${pacman_conf}" -S \
    --noconfirm \
    --print-format '%n|%r|%l' "$@" >"${resolution_path}"
  [[ -s "${resolution_path}" ]] || die "Scenario ${scenario} resolved no packages."

  while IFS='|' read -r package_name source_repo package_url; do
    [[ -n "${package_name}" && "${source_repo}" =~ ^veldmuis-(core|extra|offline)$ ]] || \
      die "Scenario ${scenario} resolved an invalid package record."
    [[ "${package_url}" == file:///* ]] || \
      die "Scenario ${scenario} attempted a non-local package source: ${package_url}"
    [[ -z "${seen_packages[${package_name}]:-}" ]] || \
      die "Scenario ${scenario} resolved duplicate package: ${package_name}"
    seen_packages["${package_name}"]=1
    package_path="${package_url#file://}"
    [[ -s "${package_path}" && -s "${package_path}.sig" ]] || \
      die "Scenario ${scenario} references a missing package or signature: ${package_path}"
  done <"${resolution_path}"

  log "Validated ${scenario}: ${#seen_packages[@]} packages, local sources only"
}

verify_maximal_signatures() {
  local resolution_path="${temp_root}/scenario-maximal.txt"
  local package_name=""
  local source_repo=""
  local package_url=""
  local package_path=""
  local verified=0

  [[ -s "${resolution_path}" ]] || die "Maximal scenario resolution is missing."
  while IFS='|' read -r package_name source_repo package_url; do
    package_path="${package_url#file://}"
    pacman-key --gpgdir "${pacman_gpgdir}" --verify \
      "${package_path}.sig" "${package_path}" >/dev/null
    ((verified += 1))
  done <"${resolution_path}"

  ((verified > 0)) || die "No package signatures were verified."
  log "Verified ${verified} package signatures for the maximal selection"
}

main() {
  local command_name=""

  for command_name in awk head install pacman pacman-key sha256sum stat; do
    require_cmd "${command_name}"
  done
  [[ -r "${package_sets}" ]] || die "Installer package-set definition is missing: ${package_sets}"
  # shellcheck source=packages/veldmuis-calamares-config/installer-package-sets.sh
  . "${package_sets}"

  validate_manifest
  temp_root="$(mktemp -d -t veldmuis-offline-check.XXXXXX)"
  trap cleanup EXIT
  pacman_conf="${temp_root}/pacman.conf"
  pacman_gpgdir="${temp_root}/gnupg"
  setup_pacman

  validate_scenario default \
    "${veldmuis_installer_base_packages[@]}"
  validate_scenario amd-graphics \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_graphics_amd_open_source_packages[@]}"
  validate_scenario intel-graphics \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_graphics_intel_open_source_packages[@]}"
  validate_scenario nouveau-graphics \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_graphics_nvidia_open_source_packages[@]}"
  validate_scenario all-open-source-graphics \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_graphics_all_open_source_packages[@]}"
  validate_scenario nvidia-580xx \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_graphics_nvidia_580xx_packages[@]}"
  validate_scenario amd-microcode \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_cpu_amd_packages[@]}"
  validate_scenario intel-microcode \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_cpu_intel_packages[@]}"
  validate_scenario steam \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_steam_packages[@]}"
  validate_scenario lutris \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_lutris_packages[@]}"
  validate_scenario discord \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_discord_packages[@]}"
  validate_scenario gaming-group \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_gaming_packages[@]}"
  validate_scenario qbittorrent \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_downloads_packages[@]}"
  validate_scenario syncthing \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_sync_packages[@]}"
  validate_scenario development \
    "${veldmuis_installer_base_packages[@]}" \
    "${veldmuis_installer_development_packages[@]}"
  validate_scenario maximal "${veldmuis_offline_seed_packages[@]}"
  verify_maximal_signatures

  log "All offline installer package closures are complete and local-only"
}

main "$@"
