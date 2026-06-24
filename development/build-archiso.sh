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
  local repo_package package_name

  [[ -d "${pacman_cache_dir}" ]] || return 0

  while IFS= read -r repo_package; do
    package_name="$(basename "${repo_package}")"
    rm -f "${pacman_cache_dir}/${package_name}" \
      "${pacman_cache_dir}/${package_name}.sig"
  done < <(find "${repo_file_root}" -type f -name '*.pkg.tar.zst' | sort -u)
}

setup_askpass_support

if (( EUID != 0 )); then
  exec "${sudo_cmd[@]}" env VELDMUIS_RELEASE_TAG="${release_tag}" "$0" "$@"
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

if [[ ! -f "${repo_file_root}/veldmuis-core/os/x86_64/veldmuis-core.db.tar.gz" ]]; then
  echo "Local Veldmuis repo database not found under: ${repo_file_root}" >&2
  echo "Rebuild the local package repo first." >&2
  exit 1
fi

for keyring_file in veldmuis.gpg veldmuis-trusted veldmuis-revoked; do
  if [[ ! -f "${veldmuis_keyring_root}/${keyring_file}" ]]; then
    echo "Missing Veldmuis keyring file: ${veldmuis_keyring_root}/${keyring_file}" >&2
    exit 1
  fi
done

mkdir -p "${build_root}" "${out_dir}"

cleanup_mounts_under "${build_root}"
prune_archiso_history

cp -a "${profile_source}" "${profile_work}"
sed -i "s|@VELDMUIS_ISO_VERSION@|${release_tag}|g" "${profile_work}/profiledef.sh"

trap restore_build_ownership EXIT

# Embed the current local Veldmuis repo into the live image so the installer
# can bootstrap the installed target without requiring hosted mirrors yet.
install -d -m 0755 "${profile_work}/airootfs/opt/veldmuis"
rm -rf "${profile_work}/airootfs/opt/veldmuis/repo"
cp -a "${repo_file_root}" "${profile_work}/airootfs/opt/veldmuis/repo"

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
echo "Output directory: ${out_dir}"

mkarchiso -v \
  -C "${profile_work}/pacman.conf" \
  -w "${work_dir}" \
  -o "${out_dir}" \
  "${profile_work}"

finalize_archiso_history
