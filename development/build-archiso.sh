#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
workspace_root="$(cd "${repo_root}/.." && pwd)"
profile_source="${repo_root}/archiso/veldmuis"
build_root="${workspace_root}/build/archiso"
build_id="$(date +%Y%m%d-%H%M%S)"
profile_work="${build_root}/profile-${build_id}"
work_dir="${build_root}/work-${build_id}"
out_dir="${build_root}/out"
repo_file_root="${repo_root}/repos"
pacman_gpgdir="${build_root}/pacman-gnupg-${build_id}"
veldmuis_keyring_root="${repo_root}/packages/veldmuis-keyring"
pacman_cache_dir="/var/cache/pacman/pkg"
archiso_keep_builds="${ARCHISO_KEEP_BUILDS:-3}"
archiso_keep_isos="${ARCHISO_KEEP_ISOS:-3}"
owner_uid="${SUDO_UID:-}"
owner_gid="${SUDO_GID:-}"
release_tag="${VELDMUIS_RELEASE_TAG:-$(date -u +%Y.%m.%d)}"
iso_mode="${VELDMUIS_ISO_MODE:-network}"
offline_manifest="${repo_file_root}/manifests/veldmuis-offline-packages.tsv"
offline_build_info="${repo_file_root}/manifests/veldmuis-offline-build.txt"
sudo_cmd=(sudo)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

pacman_keyring_has_secret() {
  [[ -d "${pacman_gpgdir}/private-keys-v1.d" ]] || return 1
  find "${pacman_gpgdir}/private-keys-v1.d" -mindepth 1 -type f -print -quit | grep -q .
}

setup_askpass_support() {
  local askpass_path=""

  if [[ -z "${SUDO_ASKPASS:-}" ]]; then
    if command -v ksshaskpass >/dev/null 2>&1; then
      askpass_path="$(command -v ksshaskpass)"
    elif command -v ssh-askpass >/dev/null 2>&1; then
      askpass_path="$(command -v ssh-askpass)"
    fi

    if [[ -n "${askpass_path}" ]]; then
      export SUDO_ASKPASS="${askpass_path}"
    fi
  fi

  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo_cmd=(sudo -A -p "Password: ")
  fi
}

require_non_negative_integer() {
  local name="$1"
  local value="$2"

  [[ "${value}" =~ ^[0-9]+$ ]] || {
    echo "${name} must be a non-negative integer, got: ${value}" >&2
    exit 1
  }
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

offline_build_value() {
  local key="$1"

  awk -F= -v wanted="${key}" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' \
    "${offline_build_info}"
}

validate_offline_repository() {
  local offline_dir="${repo_file_root}/veldmuis-offline/os/x86_64"
  local offline_db="${offline_dir}/veldmuis-offline.db.tar.gz"
  local expected_hash=""
  local expected_count=""
  local expected_bytes=""
  local actual_hash=""
  local actual_count=""
  local actual_bytes=""

  [[ -s "${offline_db}" && -s "${offline_db}.sig" ]] || {
    echo "Signed offline repository database not found under: ${offline_dir}" >&2
    exit 1
  }
  [[ -s "${offline_manifest}" && -s "${offline_build_info}" ]] || {
    echo "Offline repository manifest or build record is missing." >&2
    exit 1
  }

  gpgv --keyring "${veldmuis_keyring_root}/veldmuis.gpg" \
    "${offline_db}.sig" "${offline_db}" >/dev/null 2>&1 || {
    echo "Offline repository database signature is invalid." >&2
    exit 1
  }

  expected_hash="$(offline_build_value offline_manifest_sha256)"
  expected_count="$(offline_build_value offline_package_count)"
  expected_bytes="$(offline_build_value offline_repo_bytes)"
  actual_hash="$(sha256sum "${offline_manifest}" | awk '{ print $1 }')"
  actual_count="$(
    awk -f "${repo_root}/development/count-offline-manifest-packages.awk" \
      "${offline_manifest}"
  )"
  actual_bytes="$(du --bytes --summarize "${offline_dir}" | awk '{ print $1 }')"

  [[ "${expected_hash}" =~ ^[0-9a-f]{64}$ && "${actual_hash}" == "${expected_hash}" ]] || {
    echo "Offline repository manifest checksum is invalid." >&2
    exit 1
  }
  [[ "${expected_count}" =~ ^[1-9][0-9]*$ && "${actual_count}" == "${expected_count}" ]] || {
    echo "Offline repository package count is invalid." >&2
    exit 1
  }
  [[ "${expected_bytes}" =~ ^[1-9][0-9]*$ && "${actual_bytes}" == "${expected_bytes}" ]] || {
    echo "Offline repository byte count is invalid." >&2
    exit 1
  }
}

cleanup_mounts_under() {
  local mount_root="$1"
  local -a mountpoints=()
  local mountpoint

  [[ -d "${mount_root}" ]] || return 0

  mapfile -t mountpoints < <(findmnt -Rrn -o TARGET --target "${mount_root}" 2>/dev/null | sort -r)
  for mountpoint in "${mountpoints[@]}"; do
    [[ "${mountpoint}" == "${mount_root}"* ]] || continue
    umount -lf "${mountpoint}" >/dev/null 2>&1 || true
  done
}

restore_build_ownership() {
  cleanup_mounts_under "${build_root}"
  if [[ -n "${owner_uid}" && -n "${owner_gid}" && -d "${build_root}" ]]; then
    chown -R "${owner_uid}:${owner_gid}" "${build_root}"
  fi
}

prune_old_dirs() {
  local pattern="$1"
  local keep_count="$2"
  local -a entries=()
  local entry
  local idx

  mapfile -t entries < <(
    find "${build_root}" -maxdepth 1 -mindepth 1 -type d -name "${pattern}" \
      -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-
  )

  for ((idx = keep_count; idx < ${#entries[@]}; idx++)); do
    entry="${entries[idx]}"
    cleanup_mounts_under "${entry}"
    rm -rf "${entry}"
  done
}

prune_old_files() {
  local search_root="$1"
  local pattern="$2"
  local keep_count="$3"
  local -a entries=()
  local idx

  mapfile -t entries < <(
    find "${search_root}" -maxdepth 1 -mindepth 1 -type f -name "${pattern}" \
      -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-
  )

  for ((idx = keep_count; idx < ${#entries[@]}; idx++)); do
    rm -f "${entries[idx]}"
  done
}

prune_archiso_history() {
  local keep_existing_builds="${archiso_keep_builds}"
  local keep_existing_isos="${archiso_keep_isos}"

  if (( keep_existing_builds > 0 )); then
    keep_existing_builds=$((keep_existing_builds - 1))
  fi

  if (( keep_existing_isos > 0 )); then
    keep_existing_isos=$((keep_existing_isos - 1))
  fi

  prune_old_dirs 'profile-*' "${keep_existing_builds}"
  prune_old_dirs 'work-*' "${keep_existing_builds}"
  prune_old_dirs 'pacman-gnupg-*' "${keep_existing_builds}"
  prune_old_files "${out_dir}" 'veldmuis-*.iso' "${keep_existing_isos}"
}

finalize_archiso_history() {
  prune_old_dirs 'profile-*' "${archiso_keep_builds}"
  prune_old_dirs 'work-*' "${archiso_keep_builds}"
  prune_old_dirs 'pacman-gnupg-*' "${archiso_keep_builds}"
  prune_old_files "${out_dir}" 'veldmuis-*.iso' "${archiso_keep_isos}"
}

purge_cached_local_packages() {
  local local_repo repo_package package_name

  [[ -d "${pacman_cache_dir}" ]] || return 0

  for local_repo in veldmuis-core veldmuis-extra; do
    while IFS= read -r repo_package; do
      package_name="$(basename "${repo_package}")"
      rm -f "${pacman_cache_dir}/${package_name}" \
        "${pacman_cache_dir}/${package_name}.sig"
    done < <(
      find "${repo_file_root}/${local_repo}" -type f -name '*.pkg.tar.zst' | sort -u
    )
  done
}

setup_askpass_support

if (( EUID != 0 )); then
  exec "${sudo_cmd[@]}" env \
    VELDMUIS_RELEASE_TAG="${release_tag}" \
    VELDMUIS_ISO_MODE="${iso_mode}" \
    "$0" "$@"
fi

require_cmd mkarchiso
require_cmd sed
require_cmd pacman-key
require_cmd chown
require_cmd find
require_cmd findmnt
require_cmd umount
require_cmd gpg
require_cmd date
require_cmd awk
require_cmd du
require_cmd sha256sum
require_cmd stat
case "${iso_mode}" in
  network|offline)
    ;;
  *)
    echo "VELDMUIS_ISO_MODE must be network or offline, got: ${iso_mode}" >&2
    exit 1
    ;;
esac
require_non_negative_integer "ARCHISO_KEEP_BUILDS" "${archiso_keep_builds}"
require_non_negative_integer "ARCHISO_KEEP_ISOS" "${archiso_keep_isos}"
validate_release_tag "${release_tag}" || {
  echo "Invalid Veldmuis release tag: ${release_tag}" >&2
  exit 1
}

if [[ ! -d "${profile_source}" ]]; then
  echo "Archiso profile not found: ${profile_source}" >&2
  exit 1
fi

for repo_name in veldmuis-core veldmuis-extra; do
  if [[ ! -s "${repo_file_root}/${repo_name}/os/x86_64/${repo_name}.db.tar.gz" ]]; then
    echo "Local Veldmuis repository database not found: ${repo_name}" >&2
    echo "Rebuild the local package repositories first." >&2
    exit 1
  fi
done

for keyring_file in veldmuis.gpg veldmuis-trusted veldmuis-revoked; do
  if [[ ! -f "${veldmuis_keyring_root}/${keyring_file}" ]]; then
    echo "Missing Veldmuis keyring file: ${veldmuis_keyring_root}/${keyring_file}" >&2
    exit 1
  fi
done

if [[ "${iso_mode}" == "offline" ]]; then
  require_cmd gpgv
  validate_offline_repository
fi

mkdir -p "${build_root}" "${out_dir}"

cleanup_mounts_under "${build_root}"
prune_archiso_history

cp -a "${profile_source}" "${profile_work}"
sed -i "s|@VELDMUIS_ISO_VERSION@|${release_tag}|g" "${profile_work}/profiledef.sh"

if [[ "${iso_mode}" == "offline" ]]; then
  install -Dm644 /dev/null "${profile_work}/airootfs/etc/veldmuis/offline-install"
fi

trap restore_build_ownership EXIT

# Stage only the repositories used by the selected installer mode. This keeps
# stale offline artifacts out of network ISOs and prevents unrelated files
# under repos/ from entering either image.
embedded_repo_root="${profile_work}/airootfs/opt/veldmuis/repo"
rm -rf "${embedded_repo_root}"
install -d -m0755 "${embedded_repo_root}"
for repo_name in veldmuis-core veldmuis-extra; do
  cp -a "${repo_file_root}/${repo_name}" "${embedded_repo_root}/${repo_name}"
done
if [[ "${iso_mode}" == "offline" ]]; then
  cp -a "${repo_file_root}/veldmuis-offline" \
    "${embedded_repo_root}/veldmuis-offline"
  install -d -m0755 "${embedded_repo_root}/manifests"
  install -m0644 "${offline_manifest}" "${offline_build_info}" \
    "${embedded_repo_root}/manifests/"
fi

rm -rf "${pacman_gpgdir}"
mkdir -p "${pacman_gpgdir}"
if [[ -d /etc/pacman.d/gnupg ]]; then
  cp -a /etc/pacman.d/gnupg/. "${pacman_gpgdir}/"
fi
chmod 700 "${pacman_gpgdir}"

# Fresh CI containers can have a pacman GPG directory without an initialized
# secret key. In that case, pacman-key needs a local trust root before it can
# populate the Arch and Veldmuis keyrings for mkarchiso.
if ! pacman_keyring_has_secret; then
  pacman-key --gpgdir "${pacman_gpgdir}" --init >/dev/null
  pacman-key --gpgdir "${pacman_gpgdir}" --populate archlinux >/dev/null
fi

pacman-key --gpgdir "${pacman_gpgdir}" \
  --populate-from "${veldmuis_keyring_root}" \
  --populate veldmuis >/dev/null
pacman-key --gpgdir "${pacman_gpgdir}" --updatedb >/dev/null

# Local Veldmuis packages are rebuilt in-place during development, so purge any
# cached copies before mkarchiso installs from the embedded repo. Otherwise
# pacman can reuse an older package file with a newer detached signature.
purge_cached_local_packages

repo_file_root_escaped="$(printf '%s' "${repo_file_root}" | sed 's/[&|]/\\&/g')"
pacman_gpgdir_escaped="$(printf '%s' "${pacman_gpgdir}" | sed 's/[&|]/\\&/g')"
sed -e "s|@VELDMUIS_REPO_ROOT@|${repo_file_root_escaped}|g" \
  -e "s|@VELDMUIS_PACMAN_GPGDIR@|${pacman_gpgdir_escaped}|g" \
  "${profile_source}/pacman.conf.template" > "${profile_work}/pacman.conf"

echo "Building Veldmuis ISO with profile: ${profile_work}"
echo "Release tag: ${release_tag}"
echo "ISO mode: ${iso_mode}"
echo "Output directory: ${out_dir}"

mkarchiso -v \
  -C "${profile_work}/pacman.conf" \
  -w "${work_dir}" \
  -o "${out_dir}" \
  "${profile_work}"

if [[ "${iso_mode}" == "offline" ]]; then
  iso_path="${out_dir}/veldmuis-${release_tag}-x86_64.iso"
  summary_path="${out_dir}/veldmuis-${release_tag}-x86_64.offline-repo.txt"
  [[ -s "${iso_path}" ]] || {
    echo "Expected offline ISO output is missing: ${iso_path}" >&2
    exit 1
  }
  {
    cat "${offline_build_info}"
    printf 'iso_bytes=%s\n' "$(stat --format '%s' "${iso_path}")"
  } >"${summary_path}"
  chmod 644 "${summary_path}"
  echo "Offline ISO size record: ${summary_path}"
fi

finalize_archiso_history
