#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
container_workspace="/workspace/veldmuis"
container_runner_temp="/runner-temp"

common_packages=(
  archlinux-keyring
  base-devel
  boost
  boost-libs
  cmake
  extra-cmake-modules
  git
  gnupg
  hwinfo
  kcoreaddons
  kcrash
  kdbusaddons
  kglobalaccel
  kirigami
  kpmcore
  libpwquality
  pacman-contrib
  polkit-qt6
  python
  qt6-declarative
  qt6-svg
  qt6-tools
  qt6-translations
  yaml-cpp
)

iso_only_packages=(
  archiso
  rsync
  squashfs-tools
)

usage() {
  cat <<'EOF'
Usage:
  run-ci-arch-builder.sh packages
  run-ci-arch-builder.sh iso

Environment:
  BUILDER_USER
  BUILDER_HOME
  GNUPGHOME
  VELDMUIS_KEY_FPR_FILE
  VELDMUIS_GPG_PRIVATE_KEY
  VELDMUIS_GPG_FPR
  VELDMUIS_PACKAGER
  RUNNER_TEMP
EOF
}

die() {
  printf '[run-ci-arch-builder] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Missing required environment variable: ${name}"
}

validate_target() {
  case "$1" in
    packages|iso) ;;
    *)
      usage >&2
      die "Unsupported build target: $1"
      ;;
  esac
}

run_as_builder() {
  local command="$1"
  su "${BUILDER_USER}" -c "cd '${container_workspace}' && ${command}"
}

install_dependencies() {
  local target="$1"
  local packages=("${common_packages[@]}")

  if [[ "${target}" == "iso" ]]; then
    packages+=("${iso_only_packages[@]}")
  fi

  pacman -Syu --noconfirm --needed "${packages[@]}"
}

prepare_builder_user() {
  if ! id -u "${BUILDER_USER}" >/dev/null 2>&1; then
    useradd -m -u "${HOST_UID}" -s /bin/bash "${BUILDER_USER}"
  fi

  install -d -m 700 -o "${BUILDER_USER}" -g "${BUILDER_USER}" "${GNUPGHOME}"
}

import_signing_key() {
  local key_file="${container_runner_temp}/veldmuis-ci-signing-subkey.asc"

  printf '%s\n' "${VELDMUIS_GPG_PRIVATE_KEY}" > "${key_file}"
  chown "${BUILDER_USER}:${BUILDER_USER}" "${key_file}"
  su "${BUILDER_USER}" -c "GNUPGHOME='${GNUPGHOME}' gpg --batch --import '${key_file}'"

  printf '%s\n' "${VELDMUIS_GPG_FPR}" > "${VELDMUIS_KEY_FPR_FILE}"
  chown "${BUILDER_USER}:${BUILDER_USER}" "${VELDMUIS_KEY_FPR_FILE}"

  su "${BUILDER_USER}" -c "GNUPGHOME='${GNUPGHOME}' gpg --batch --list-secret-keys '${VELDMUIS_GPG_FPR}'"
  rm -f "${key_file}"
}

run_build_inside_container() {
  local target="$1"

  require_cmd pacman
  require_cmd su
  require_env BUILDER_USER
  require_env GNUPGHOME
  require_env VELDMUIS_KEY_FPR_FILE
  require_env VELDMUIS_GPG_PRIVATE_KEY
  require_env VELDMUIS_GPG_FPR
  require_env HOST_UID
  require_env HOST_GID

  install_dependencies "${target}"
  prepare_builder_user
  import_signing_key

  run_as_builder "PACKAGER='${VELDMUIS_PACKAGER:-Veldmuis Linux <veldmuis@veldmuislinux.org>}' GNUPGHOME='${GNUPGHOME}' ./development/build-all-packages.sh"
  run_as_builder "GNUPGHOME='${GNUPGHOME}' VELDMUIS_KEY_FPR_FILE='${VELDMUIS_KEY_FPR_FILE}' ./development/build-local-repo.sh"

  if [[ "${target}" == "iso" ]]; then
    cd "${container_workspace}"
    GNUPGHOME="${GNUPGHOME}" ./development/build-archiso.sh
    chown -R "${HOST_UID}:${HOST_GID}" /workspace/build "${container_workspace}/repos" "${container_workspace}/packages"
  else
    chown -R "${HOST_UID}:${HOST_GID}" "${container_workspace}/repos" "${container_workspace}/packages"
  fi
}

run_build_in_container() {
  local target="$1"
  local runner_temp="${RUNNER_TEMP:-}"
  local -a docker_args=(
    run
    --rm
    -i
    -e BUILDER_USER
    -e BUILDER_HOME
    -e GNUPGHOME
    -e VELDMUIS_KEY_FPR_FILE
    -e VELDMUIS_GPG_PRIVATE_KEY
    -e VELDMUIS_GPG_FPR
    -e VELDMUIS_PACKAGER
    -e HOST_UID="$(id -u)"
    -e HOST_GID="$(id -g)"
    -v "${repo_root}:${container_workspace}"
    -v "${runner_temp}:${container_runner_temp}"
    -w "${container_workspace}"
  )

  require_cmd docker
  require_env BUILDER_USER
  require_env BUILDER_HOME
  require_env GNUPGHOME
  require_env VELDMUIS_KEY_FPR_FILE
  require_env VELDMUIS_GPG_PRIVATE_KEY
  require_env VELDMUIS_GPG_FPR
  require_env RUNNER_TEMP

  if [[ "${target}" == "iso" ]]; then
    local host_build_root="${RUNNER_TEMP}/veldmuis-build"
    mkdir -p "${host_build_root}"
    docker_args+=(
      --privileged
      -v "${host_build_root}:/workspace/build"
    )
  fi

  docker_args+=(
    archlinux:base-devel
    bash
    "${container_workspace}/development/run-ci-arch-builder.sh"
    --in-container
    "${target}"
  )

  docker "${docker_args[@]}"
}

main() {
  local in_container=0
  local target="${1:-}"

  if [[ "${target}" == "--in-container" ]]; then
    in_container=1
    target="${2:-}"
  fi

  validate_target "${target}"

  if (( in_container )); then
    run_build_inside_container "${target}"
  else
    run_build_in_container "${target}"
  fi
}

main "$@"
