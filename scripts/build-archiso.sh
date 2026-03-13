#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile_source="${repo_root}/archiso/veldmuis"
build_root="${repo_root}/build/archiso"
build_id="$(date +%Y%m%d-%H%M%S)"
profile_work="${build_root}/profile-${build_id}"
work_dir="${build_root}/work-${build_id}"
out_dir="${build_root}/out"
repo_file_root="${repo_root}/repos"
pacman_gpgdir="${build_root}/pacman-gnupg-${build_id}"
veldmuis_keyring_root="${repo_root}/packages/veldmuis-keyring"
pacman_cache_dir="/var/cache/pacman/pkg"
owner_uid="${SUDO_UID:-}"
owner_gid="${SUDO_GID:-}"

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

restore_build_ownership() {
  if [[ -n "${owner_uid}" && -n "${owner_gid}" && -d "${build_root}" ]]; then
    chown -R "${owner_uid}:${owner_gid}" "${build_root}"
  fi
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

if (( EUID != 0 )); then
  exec sudo "$0" "$@"
fi

require_cmd mkarchiso
require_cmd sed
require_cmd pacman-key
require_cmd chown
require_cmd find
require_cmd gpg

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
cp -a "${profile_source}" "${profile_work}"

trap restore_build_ownership EXIT

install -d -m 0755 "${profile_work}/airootfs/opt/veldmuis"
rm -rf "${profile_work}/airootfs/opt/veldmuis/repo"
cp -a "${repo_file_root}" "${profile_work}/airootfs/opt/veldmuis/repo"

rm -rf "${pacman_gpgdir}"
mkdir -p "${pacman_gpgdir}"
chmod 700 "${pacman_gpgdir}"

if [[ -d /etc/pacman.d/gnupg ]]; then
  cp -a /etc/pacman.d/gnupg/. "${pacman_gpgdir}/"
  chmod 700 "${pacman_gpgdir}"
fi

if ! pacman_keyring_has_secret; then
  pacman-key --gpgdir "${pacman_gpgdir}" --init >/dev/null
  pacman-key --gpgdir "${pacman_gpgdir}" --populate archlinux >/dev/null
fi

pacman-key --gpgdir "${pacman_gpgdir}" \
  --populate-from "${veldmuis_keyring_root}" \
  --populate veldmuis >/dev/null
pacman-key --gpgdir "${pacman_gpgdir}" --updatedb >/dev/null

purge_cached_local_packages

repo_file_root_escaped="$(printf '%s' "${repo_file_root}" | sed 's/[&|]/\\&/g')"
pacman_gpgdir_escaped="$(printf '%s' "${pacman_gpgdir}" | sed 's/[&|]/\\&/g')"
sed -e "s|@VELDMUIS_REPO_ROOT@|${repo_file_root_escaped}|g" \
  -e "s|@VELDMUIS_PACMAN_GPGDIR@|${pacman_gpgdir_escaped}|g" \
  "${profile_source}/pacman.conf.template" > "${profile_work}/pacman.conf"

echo "Building Veldmuis ISO with profile: ${profile_work}"
echo "Output directory: ${out_dir}"

mkarchiso -v \
  -C "${profile_work}/pacman.conf" \
  -w "${work_dir}" \
  -o "${out_dir}" \
  "${profile_work}"
