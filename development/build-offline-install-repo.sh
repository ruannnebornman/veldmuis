#!/usr/bin/env bash

set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
repos_root="${repo_root}/repos"
arch="${VELDMUIS_ARCH:-x86_64}"
snapshot="${VELDMUIS_ARCH_SNAPSHOT:-}"
snapshot_base=""
offline_repo_name="veldmuis-offline"
offline_dir="${repos_root}/${offline_repo_name}/os/${arch}"
manifests_dir="${repos_root}/manifests"
manifest_path="${manifests_dir}/veldmuis-offline-packages.tsv"
build_info_path="${manifests_dir}/veldmuis-offline-build.txt"
key_fpr_file="${VELDMUIS_KEY_FPR_FILE:-}"
package_sets="${repo_root}/packages/veldmuis-calamares-config/installer-package-sets.sh"
keyring_root="${repo_root}/packages/veldmuis-keyring"
temp_root=""
pacman_root=""
pacman_db=""
pacman_gpgdir=""
pacman_conf=""
resolution_path=""

die() {
  printf '[build-offline-install-repo] ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '[build-offline-install-repo] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  [[ -z "${temp_root}" || ! -d "${temp_root}" ]] || rm -rf "${temp_root}"
}

validate_snapshot() {
  local normalized=""

  [[ "${snapshot}" =~ ^([0-9]{4})/(0[1-9]|1[0-2])/(0[1-9]|[12][0-9]|3[01])$ ]] || \
    die "VELDMUIS_ARCH_SNAPSHOT must use YYYY/MM/DD, got: ${snapshot:-empty}"
  normalized="$(date -u -d "${snapshot//\//-}" +%Y/%m/%d 2>/dev/null)" || \
    die "Invalid Arch snapshot date: ${snapshot}"
  [[ "${normalized}" == "${snapshot}" ]] || die "Invalid Arch snapshot date: ${snapshot}"
}

setup_keyring() {
  local keyring_file=""

  for keyring_file in veldmuis.gpg veldmuis-trusted veldmuis-revoked; do
    [[ -r "${keyring_root}/${keyring_file}" ]] || \
      die "Missing Veldmuis keyring file: ${keyring_root}/${keyring_file}"
  done

  install -d -m700 "${pacman_gpgdir}"
  pacman-key --gpgdir "${pacman_gpgdir}" --init >/dev/null
  pacman-key --gpgdir "${pacman_gpgdir}" --populate archlinux >/dev/null
  pacman-key --gpgdir "${pacman_gpgdir}" \
    --populate-from "${keyring_root}" --populate veldmuis >/dev/null
  pacman-key --gpgdir "${pacman_gpgdir}" --updatedb >/dev/null
}

write_pacman_conf() {
  cat >"${pacman_conf}" <<EOF
[options]
Architecture = ${arch}
RootDir = ${pacman_root}
DBPath = ${pacman_db}
CacheDir = ${offline_dir}
GPGDir = ${pacman_gpgdir}
LogFile = ${temp_root}/pacman.log
CheckSpace
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Required
ParallelDownloads = 5
DisableDownloadTimeout

[core]
Server = ${snapshot_base}/\$repo/os/\$arch

[extra]
Server = ${snapshot_base}/\$repo/os/\$arch

[multilib]
Server = ${snapshot_base}/\$repo/os/\$arch

[veldmuis-core]
SigLevel = Required DatabaseRequired
Server = file://${repos_root}/veldmuis-core/os/\$arch

[veldmuis-extra]
SigLevel = Required DatabaseRequired
Server = file://${repos_root}/veldmuis-extra/os/\$arch
EOF
}

resolve_closure() {
  local record=""
  local package_name=""
  local package_version=""
  local package_arch=""
  local source_repo=""
  local package_filename=""
  local database_size=""
  local database_sha256=""
  local package_url=""
  declare -A seen_packages=()

  pacman --config "${pacman_conf}" -Sy --noconfirm
  pacman --config "${pacman_conf}" -S \
    --noconfirm \
    --print-format '%n|%v|%a|%r|%f|%s|%h|%l' \
    "${veldmuis_offline_seed_packages[@]}" >"${resolution_path}"

  [[ -s "${resolution_path}" ]] || die "The offline dependency closure is empty."

  while IFS= read -r record; do
    IFS='|' read -r \
      package_name package_version package_arch source_repo package_filename \
      database_size database_sha256 package_url <<<"${record}"

    [[ -n "${package_name}" && -n "${package_version}" && -n "${source_repo}" ]] || \
      die "Malformed pacman resolution record: ${record}"
    [[ -z "${seen_packages[${package_name}]:-}" ]] || \
      die "Duplicate package in dependency closure: ${package_name}"
    seen_packages["${package_name}"]=1

    case "${source_repo}" in
      core|extra|multilib|veldmuis-core|veldmuis-extra)
        ;;
      *)
        die "Package ${package_name} resolved from unexpected repository: ${source_repo}"
        ;;
    esac

    [[ -n "${package_filename}" && -n "${package_url}" ]] || \
      die "Package ${package_name} has no filename or source URL."
  done <"${resolution_path}"

  log "Resolved ${#seen_packages[@]} total packages from the frozen repository state"
}

download_and_verify_closure() {
  # Pacman verifies both Arch and Veldmuis package signatures while acquiring
  # the complete transaction. Only unchanged official Arch packages are kept
  # in the third repository below.
  pacman --config "${pacman_conf}" -Sw --noconfirm --needed \
    "${veldmuis_offline_seed_packages[@]}"
}

stage_official_packages() {
  local package_name=""
  local package_version=""
  local package_arch=""
  local source_repo=""
  local package_filename=""
  local database_size=""
  local database_sha256=""
  local package_url=""
  local package_path=""
  local signature_path=""
  local actual_sha256=""
  local actual_size=""
  local cache_file=""
  local -a official_records=()
  declare -A keep_files=()

  while IFS='|' read -r \
    package_name package_version package_arch source_repo package_filename \
    database_size database_sha256 package_url
  do
    case "${source_repo}" in
      core|extra|multilib)
        ;;
      veldmuis-core|veldmuis-extra)
        continue
        ;;
      *)
        die "Unexpected repository in resolved closure: ${source_repo}"
        ;;
    esac

    [[ "${package_filename}" =~ ^[A-Za-z0-9@._+:-]+\.pkg\.tar\.[A-Za-z0-9.]+$ ]] || \
      die "Unsafe package filename in dependency closure: ${package_filename}"
    package_path="${offline_dir}/${package_filename}"
    signature_path="${package_path}.sig"
    [[ -s "${package_path}" ]] || die "Downloaded package is missing: ${package_path}"

    if [[ ! -s "${signature_path}" ]]; then
      curl --fail --location --silent --show-error \
        --output "${signature_path}" "${package_url}.sig"
    fi
    pacman-key --gpgdir "${pacman_gpgdir}" --verify \
      "${signature_path}" "${package_path}" >/dev/null

    actual_sha256="$(sha256sum "${package_path}" | awk '{ print $1 }')"
    if [[ -n "${database_sha256}" && "${database_sha256}" != "${actual_sha256}" ]]; then
      die "Repository database checksum mismatch for ${package_filename}"
    fi
    actual_size="$(stat --format '%s' "${package_path}")"

    keep_files["${package_filename}"]=1
    keep_files["${package_filename}.sig"]=1
    official_records+=(
      "${package_name}"$'\t'"${package_version}"$'\t'"${package_arch}"$'\t'"${source_repo}"$'\t'"${actual_size}"$'\t'"${actual_sha256}"$'\t'"${package_filename}"
    )
  done <"${resolution_path}"

  ((${#official_records[@]} > 0)) || die "No official Arch packages were resolved."

  while IFS= read -r cache_file; do
    [[ -n "${keep_files[$(basename "${cache_file}")]:-}" ]] || rm -f "${cache_file}"
  done < <(
    find "${offline_dir}" -maxdepth 1 -type f \
      \( -name '*.pkg.tar.*' -o -name '*.pkg.tar.*.sig' \) -print
  )

  {
    printf 'package\tversion\tarchitecture\toriginal_repository\tfile_size\tsha256\tfilename\n'
    printf '%s\n' "${official_records[@]}" | LC_ALL=C sort -t $'\t' -k1,1
  } >"${manifest_path}"
}

build_signed_repository() {
  local key_fingerprint=""
  local db_path="${offline_dir}/${offline_repo_name}.db.tar.gz"
  local manifest_sha256=""
  local package_count=""
  local repo_bytes=""
  local -a package_paths=()

  [[ -r "${key_fpr_file}" ]] || die "Signing fingerprint marker is missing: ${key_fpr_file}"
  key_fingerprint="$(tr -d '[:space:]' <"${key_fpr_file}")"
  [[ "${key_fingerprint}" =~ ^[0-9A-Fa-f]{40}$ ]] || \
    die "Invalid signing fingerprint: ${key_fingerprint}"
  gpg --batch --list-secret-keys "${key_fingerprint}" >/dev/null 2>&1 || \
    die "Signing key is unavailable: ${key_fingerprint}"

  mapfile -t package_paths < <(
    awk -F $'\t' 'NR > 1 { print $7 }' "${manifest_path}" | \
      while IFS= read -r package_filename; do
        printf '%s/%s\n' "${offline_dir}" "${package_filename}"
      done
  )
  ((${#package_paths[@]} > 0)) || die "Offline package manifest has no packages."

  repo-add --sign --key "${key_fingerprint}" --include-sigs \
    "${db_path}" "${package_paths[@]}"
  [[ -s "${db_path}" && -s "${db_path}.sig" ]] || \
    die "Signed offline repository database was not created."
  gpg --batch --verify "${db_path}.sig" "${db_path}" >/dev/null 2>&1 || \
    die "Offline repository database signature verification failed."

  manifest_sha256="$(sha256sum "${manifest_path}" | awk '{ print $1 }')"
  package_count="$(awk 'END { print NR > 0 ? NR - 1 : 0 }' "${manifest_path}")"
  repo_bytes="$(du --bytes --summarize "${offline_dir}" | awk '{ print $1 }')"

  {
    printf 'arch_repository_snapshot=%s\n' "${snapshot}"
    printf 'offline_repository=%s\n' "${offline_repo_name}"
    printf 'offline_package_count=%s\n' "${package_count}"
    printf 'offline_repo_bytes=%s\n' "${repo_bytes}"
    printf 'offline_manifest_name=%s\n' "$(basename "${manifest_path}")"
    printf 'offline_manifest_sha256=%s\n' "${manifest_sha256}"
  } >"${build_info_path}"

  chmod 644 "${manifest_path}" "${build_info_path}"
  log "Built signed offline repository with ${package_count} official packages"
  log "Arch repository snapshot: ${snapshot}"
  log "Offline repository bytes: ${repo_bytes}"
}

main() {
  local action="${1:-all}"
  local repo_name=""

  case "${action}" in
    download|sign|all)
      ;;
    *)
      die "Usage: build-offline-install-repo.sh [download|sign|all]"
      ;;
  esac

  for command_name in awk date du find install sha256sum sort stat; do
    require_cmd "${command_name}"
  done
  [[ -r "${package_sets}" ]] || die "Installer package-set definition is missing: ${package_sets}"
  validate_snapshot
  snapshot_base="https://archive.archlinux.org/repos/${snapshot}"

  for repo_name in veldmuis-core veldmuis-extra; do
    [[ -s "${repos_root}/${repo_name}/os/${arch}/${repo_name}.db.tar.gz" ]] || \
      die "Required signed repository is missing: ${repo_name}"
    [[ -s "${repos_root}/${repo_name}/os/${arch}/${repo_name}.db.tar.gz.sig" ]] || \
      die "Required repository signature is missing: ${repo_name}"
  done

  # shellcheck source=packages/veldmuis-calamares-config/installer-package-sets.sh
  . "${package_sets}"
  ((${#veldmuis_offline_seed_packages[@]} > 0)) || die "Offline package seed is empty."

  if [[ "${action}" == "download" || "${action}" == "all" ]]; then
    require_cmd curl
    require_cmd pacman
    require_cmd pacman-key
    temp_root="$(mktemp -d -t veldmuis-offline-repo.XXXXXX)"
    trap cleanup EXIT
    pacman_root="${temp_root}/root"
    pacman_db="${temp_root}/db"
    pacman_gpgdir="${temp_root}/gnupg"
    pacman_conf="${temp_root}/pacman.conf"
    resolution_path="${temp_root}/resolved-packages.txt"

    rm -rf "${offline_dir}"
    install -d -m755 "${offline_dir}" "${manifests_dir}" "${pacman_root}" "${pacman_db}"
    rm -f "${manifest_path}" "${build_info_path}"
    setup_keyring
    write_pacman_conf
    resolve_closure
    download_and_verify_closure
    stage_official_packages
  fi

  if [[ "${action}" == "sign" || "${action}" == "all" ]]; then
    require_cmd gpg
    require_cmd repo-add
    [[ -n "${key_fpr_file}" ]] || die "VELDMUIS_KEY_FPR_FILE is required."
    [[ -s "${manifest_path}" ]] || die "Offline package manifest is missing; run the download phase first."
    build_signed_repository
  fi
}

main "$@"
