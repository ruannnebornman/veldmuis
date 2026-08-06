#!/usr/bin/env bash

set -euo pipefail
umask 077

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
support_root="$(cd "${script_dir}/.." && pwd)"
container_workspace="/workspace/veldmuis"
container_support_root="/workspace/ci-support"
builder_image=""
builder_base_image="${VELDMUIS_BUILDER_BASE_IMAGE:-archlinux:base-devel}"
builder_base_digest=""
builder_image_id=""
docker_version=""
trusted_support_root=""
nvidia_package_set="${VELDMUIS_NVIDIA_580XX_PACKAGE_SET:-${repo_root}/packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh}"

common_packages=(
  archlinux-keyring
  base-devel
  boost
  boost-libs
  cmake
  curl
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
  sudo
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
  run-ci-arch-builder.sh candidate
  run-ci-arch-builder.sh iso
  run-ci-arch-builder.sh offline-iso

Environment:
  BUILDER_USER
  BUILDER_HOME
  GNUPGHOME
  VELDMUIS_KEY_FPR_FILE
  VELDMUIS_GPG_PRIVATE_KEY
  VELDMUIS_GPG_FPR
  VELDMUIS_RELEASE_TAG
  VELDMUIS_RELEASE_SHA
  VELDMUIS_ARCH_SNAPSHOT
  VELDMUIS_PACKAGER
  VELDMUIS_AUR_REF_MODE
  VELDMUIS_AUR_ENABLE_FALLBACK
  VELDMUIS_SIMULATE_AUR_BUILD_FAILURE
  PACKAGE_BASE_URL
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

shell_quote() {
  printf '%q' "$1"
}

is_true() {
  [[ "${1:-}" == "1" || "${1:-}" == "true" ]]
}

validate_target() {
  case "$1" in
    packages|candidate|iso|offline-iso) ;;
    *)
      usage >&2
      die "Unsupported build target: $1"
      ;;
  esac
}

validate_stage() {
  case "$1" in
    packages|aur|sign|offline-download|offline-sign|offline-validate|iso|release-metadata) ;;
    *)
      usage >&2
      die "Unsupported container stage: $1"
      ;;
  esac
}

load_nvidia_package_set() {
  [[ -r "${nvidia_package_set}" ]] || \
    die "NVIDIA package set not readable: ${nvidia_package_set}"
  # shellcheck source=packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
  . "${nvidia_package_set}"

  declare -p veldmuis_nvidia_580xx_official_build_dependency_roots >/dev/null 2>&1 || \
    die "Approved NVIDIA build-dependency roots are unavailable"
  ((${#veldmuis_nvidia_580xx_official_build_dependency_roots[@]} > 0)) || \
    die "Approved NVIDIA build-dependency roots are empty"
}

load_nvidia_package_set

run_as_builder() {
  local command="$1"
  su "${BUILDER_USER}" -c "cd '${container_workspace}' && ${command}"
}

prepare_builder_user() {
  local allow_pacman="${1:-0}"

  if ! id -u "${BUILDER_USER}" >/dev/null 2>&1; then
    useradd -m -u "${HOST_UID}" -s /bin/bash "${BUILDER_USER}"
  fi

  install -d -m 700 -o "${BUILDER_USER}" -g "${BUILDER_USER}" "${GNUPGHOME}"

  if [[ "${allow_pacman}" == "1" ]]; then
    [[ -x "${container_support_root}/development/install-aur-build-dependency.sh" ]] || \
      die "Restricted AUR dependency installer is missing"
    require_cmd visudo
    install -d -m 0750 /etc/sudoers.d
    local sudoers_file="/etc/sudoers.d/veldmuis-builder-aur-dependency"
    printf '%s ALL=(root) NOPASSWD: %s\n' "${BUILDER_USER}" \
      "${container_support_root}/development/install-aur-build-dependency.sh \"\"" \
      > "${sudoers_file}"
    chmod 0440 "${sudoers_file}"
    visudo -cf "${sudoers_file}"
  fi
}

validate_aur_dependency_roots() {
  local dependency
  local -a missing_dependencies=()

  require_cmd pacman
  for dependency in "${veldmuis_nvidia_580xx_official_build_dependency_roots[@]}"; do
    if ! pacman -T "${dependency}" >/dev/null 2>&1; then
      missing_dependencies+=("${dependency}")
    fi
  done

  ((${#missing_dependencies[@]} == 0)) || \
    die "Approved NVIDIA build-dependency roots are missing: ${missing_dependencies[*]}"
}

import_signing_key() {
  local key_file=""

  key_file="$(mktemp -t veldmuis-ci-signing-subkey.XXXXXX)"

  printf '%s\n' "${VELDMUIS_GPG_PRIVATE_KEY}" > "${key_file}"
  chown "${BUILDER_USER}:${BUILDER_USER}" "${key_file}"
  su "${BUILDER_USER}" -c "GNUPGHOME='${GNUPGHOME}' gpg --batch --import '${key_file}'"

  printf '%s\n' "${VELDMUIS_GPG_FPR}" > "${VELDMUIS_KEY_FPR_FILE}"
  chown "${BUILDER_USER}:${BUILDER_USER}" "${VELDMUIS_KEY_FPR_FILE}"

  su "${BUILDER_USER}" -c "GNUPGHOME='${GNUPGHOME}' gpg --batch --list-secret-keys '${VELDMUIS_GPG_FPR}'"
  rm -f "${key_file}"
}

chown_output_paths() {
  local -a output_paths=()
  local path

  for path in "$@"; do
    [[ -e "${path}" ]] && output_paths+=("${path}")
  done

  ((${#output_paths[@]} == 0)) || chown -R "${HOST_UID}:${HOST_GID}" "${output_paths[@]}"
}

run_package_build_stage() {
  require_cmd su
  require_env BUILDER_USER
  require_env GNUPGHOME
  require_env HOST_UID
  require_env HOST_GID

  prepare_builder_user 1

  local packager="${VELDMUIS_PACKAGER:-Veldmuis Linux <veldmuis@veldmuislinux.org>}"

  run_as_builder "PACKAGER=$(shell_quote "${packager}") GNUPGHOME=$(shell_quote "${GNUPGHOME}") ${container_support_root}/development/build-all-packages.sh"
  chown_output_paths "${container_workspace}/packages"
}

run_aur_build_stage() {
  require_cmd su
  require_env BUILDER_USER
  require_env GNUPGHOME
  require_env HOST_UID
  require_env HOST_GID

  validate_aur_dependency_roots
  prepare_builder_user 1

  local packager="${VELDMUIS_PACKAGER:-Veldmuis Linux <veldmuis@veldmuislinux.org>}"
  local aur_ref_mode="${VELDMUIS_AUR_REF_MODE:-locked}"
  local aur_dependency_installer="${container_support_root}/development/install-aur-build-dependency.sh"
  local aur_build_status=0
  local build_aur_command
  local override_name

  build_aur_command="PACKAGER=$(shell_quote "${packager}") GNUPGHOME=$(shell_quote "${GNUPGHOME}") VELDMUIS_AUR_REF_MODE=$(shell_quote "${aur_ref_mode}") VELDMUIS_AUR_DEPENDENCY_INSTALLER=$(shell_quote "${aur_dependency_installer}")"
  for override_name in \
    VELDMUIS_AUR_REF_NVIDIA_580XX_UTILS \
    VELDMUIS_AUR_REF_LIB32_NVIDIA_580XX_UTILS \
    VELDMUIS_AUR_REF_NVIDIA_580XX_SETTINGS
  do
    if [[ -n "${!override_name:-}" ]]; then
      build_aur_command+=" ${override_name}=$(shell_quote "${!override_name}")"
    fi
  done

  if is_true "${VELDMUIS_SIMULATE_AUR_BUILD_FAILURE:-0}"; then
    echo "[run-ci-arch-builder] Simulating AUR package build failure"
    aur_build_status=1
  elif run_as_builder "${build_aur_command} ${container_support_root}/development/build-aur-packages.sh"; then
    aur_build_status=0
  else
    aur_build_status=$?
  fi

  if (( aur_build_status != 0 )); then
    if ! is_true "${VELDMUIS_AUR_ENABLE_FALLBACK:-0}"; then
      die "AUR package build failed and fallback is disabled"
    fi

    echo "[run-ci-arch-builder] AUR package build failed, restoring known-good NVIDIA package set"
    run_as_builder "PACKAGE_BASE_URL=$(shell_quote "${PACKAGE_BASE_URL:-}") VELDMUIS_AUR_REF_MODE=$(shell_quote "${aur_ref_mode}") ${container_support_root}/development/restore-known-good-nvidia-packages.sh"
  fi

  chown_output_paths "${container_workspace}/artifacts"
}

run_signing_stage() {
  require_cmd gpg
  require_cmd repo-add
  require_cmd su
  require_env BUILDER_USER
  require_env GNUPGHOME
  require_env VELDMUIS_KEY_FPR_FILE
  require_env VELDMUIS_GPG_PRIVATE_KEY
  require_env VELDMUIS_GPG_FPR
  require_env HOST_UID
  require_env HOST_GID

  prepare_builder_user
  run_as_builder "${container_support_root}/development/build-aur-packages.sh --validate-only"
  import_signing_key
  run_as_builder "GNUPGHOME=$(shell_quote "${GNUPGHOME}") VELDMUIS_KEY_FPR_FILE=$(shell_quote "${VELDMUIS_KEY_FPR_FILE}") ${container_support_root}/development/build-local-repo.sh"
  run_as_builder "GNUPGHOME=$(shell_quote "${GNUPGHOME}") VELDMUIS_KEY_FPR_FILE=$(shell_quote "${VELDMUIS_KEY_FPR_FILE}") ${container_support_root}/development/publish-known-good-nvidia-packages.sh --prepare-only"
  chown_output_paths "${container_workspace}/repos"
}

run_offline_download_stage() {
  require_env HOST_UID
  require_env HOST_GID
  require_env VELDMUIS_ARCH_SNAPSHOT

  cd "${container_workspace}"
  VELDMUIS_ARCH_SNAPSHOT="${VELDMUIS_ARCH_SNAPSHOT}" \
    "${container_support_root}/development/build-offline-install-repo.sh" download
  chown_output_paths "${container_workspace}/repos"
}

run_offline_signing_stage() {
  require_cmd gpg
  require_cmd repo-add
  require_cmd su
  require_env BUILDER_USER
  require_env GNUPGHOME
  require_env VELDMUIS_KEY_FPR_FILE
  require_env VELDMUIS_GPG_PRIVATE_KEY
  require_env VELDMUIS_GPG_FPR
  require_env VELDMUIS_ARCH_SNAPSHOT
  require_env HOST_UID
  require_env HOST_GID

  prepare_builder_user
  import_signing_key
  run_as_builder "GNUPGHOME=$(shell_quote "${GNUPGHOME}") VELDMUIS_KEY_FPR_FILE=$(shell_quote "${VELDMUIS_KEY_FPR_FILE}") VELDMUIS_ARCH_SNAPSHOT=$(shell_quote "${VELDMUIS_ARCH_SNAPSHOT}") ${container_support_root}/development/build-offline-install-repo.sh sign"
  chown_output_paths "${container_workspace}/repos"
}

run_offline_validation_stage() {
  cd "${container_workspace}"
  "${container_support_root}/development/check-offline-install-repo.sh"
}

run_iso_stage() {
  require_env HOST_UID
  require_env HOST_GID

  cd "${container_workspace}"
  "${container_support_root}/development/build-archiso.sh"
  chown_output_paths /workspace/build
}

run_release_metadata_stage() {
  require_cmd gpg
  require_cmd su
  require_env BUILDER_USER
  require_env GNUPGHOME
  require_env VELDMUIS_KEY_FPR_FILE
  require_env VELDMUIS_GPG_PRIVATE_KEY
  require_env VELDMUIS_GPG_FPR
  require_env VELDMUIS_RELEASE_TAG
  require_env VELDMUIS_RELEASE_SHA
  require_env VELDMUIS_BUILDER_BASE_IMAGE
  require_env VELDMUIS_BUILDER_BASE_DIGEST
  require_env VELDMUIS_BUILDER_IMAGE_ID
  require_env HOST_UID
  require_env HOST_GID

  prepare_builder_user
  import_signing_key
  run_as_builder "GNUPGHOME=$(shell_quote "${GNUPGHOME}") VELDMUIS_KEY_FPR_FILE=$(shell_quote "${VELDMUIS_KEY_FPR_FILE}") VELDMUIS_RELEASE_OUTPUT_DIR=/workspace/build/archiso/out VELDMUIS_RELEASE_TAG=$(shell_quote "${VELDMUIS_RELEASE_TAG}") VELDMUIS_RELEASE_SHA=$(shell_quote "${VELDMUIS_RELEASE_SHA}") VELDMUIS_BUILDER_BASE_IMAGE=$(shell_quote "${VELDMUIS_BUILDER_BASE_IMAGE}") VELDMUIS_BUILDER_BASE_DIGEST=$(shell_quote "${VELDMUIS_BUILDER_BASE_DIGEST}") VELDMUIS_BUILDER_IMAGE_ID=$(shell_quote "${VELDMUIS_BUILDER_IMAGE_ID}") VELDMUIS_DOCKER_VERSION=$(shell_quote "${VELDMUIS_DOCKER_VERSION:-unknown}") VELDMUIS_ISO_MODE=$(shell_quote "${VELDMUIS_ISO_MODE:-network}") ${container_support_root}/development/generate-release-metadata.sh"
  chown_output_paths /workspace/build
}

prepare_trusted_support() {
  trusted_support_root="${RUNNER_TEMP}/veldmuis-ci-support-${GITHUB_RUN_ID:-local}-$$"
  rm -rf "${trusted_support_root}"
  mkdir -p "${trusted_support_root}"
  cp -a "${support_root}/development" "${trusted_support_root}/development"
}

prepare_builder_image() {
  local target="$1"
  local -a packages=("${common_packages[@]}" "${veldmuis_nvidia_580xx_official_build_dependency_roots[@]}")
  local package_list=""

  if [[ "${target}" == "iso" || "${target}" == "offline-iso" ]]; then
    packages+=("${iso_only_packages[@]}")
  fi

  package_list="${packages[*]}"
  builder_image="veldmuis-builder-${GITHUB_RUN_ID:-local}-$$"
  builder_image="${builder_image//[^A-Za-z0-9_.-]/-}"

  docker pull "${builder_base_image}"
  builder_base_digest="$(
    docker image inspect --format '{{index .RepoDigests 0}}' "${builder_base_image}"
  )"
  [[ "${builder_base_digest}" == *@sha256:* ]] || \
    die "Unable to resolve immutable builder base image digest: ${builder_base_image}"

  printf '%s\n' \
    "FROM ${builder_base_digest}" \
    'RUN sed -i '\''/^\#\[multilib\]/{s/^#//; n; s/^#//;}'\'' /etc/pacman.conf' \
    "RUN pacman -Syu --noconfirm --needed ${package_list} && pacman -Scc --noconfirm" \
    | docker build --tag "${builder_image}" -

  builder_image_id="$(docker image inspect --format '{{.Id}}' "${builder_image}")"
  [[ "${builder_image_id}" == sha256:* ]] || \
    die "Unable to resolve builder image ID: ${builder_image}"
  docker_version="$(docker --version)"
}

cleanup_outer_resources() {
  if [[ -n "${builder_image}" ]]; then
    docker image rm --force "${builder_image}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${trusted_support_root}" ]]; then
    rm -rf "${trusted_support_root}"
  fi
}

run_container_stage() {
  local stage="$1"
  local target="$2"
  local image="${builder_image}"
  local mount_mode="rw"
  local -a docker_args=(
    run
    --rm
    -i
    -e BUILDER_USER
    -e BUILDER_HOME
    -e GNUPGHOME
    -e CI_REPO_ROOT="${container_workspace}"
    -e HOST_UID="$(id -u)"
    -e HOST_GID="$(id -g)"
  )

  if [[ "${stage}" == "packages" || "${stage}" == "aur" ]]; then
    docker_args+=(
      -e VELDMUIS_PACKAGER
    )
  fi

  if [[ "${stage}" == "aur" ]]; then
    mount_mode="ro"
    docker_args+=(
      -e VELDMUIS_AUR_REF_MODE="${VELDMUIS_AUR_REF_MODE:-}"
      -e VELDMUIS_AUR_REF_NVIDIA_580XX_UTILS="${VELDMUIS_AUR_REF_NVIDIA_580XX_UTILS:-}"
      -e VELDMUIS_AUR_REF_LIB32_NVIDIA_580XX_UTILS="${VELDMUIS_AUR_REF_LIB32_NVIDIA_580XX_UTILS:-}"
      -e VELDMUIS_AUR_REF_NVIDIA_580XX_SETTINGS="${VELDMUIS_AUR_REF_NVIDIA_580XX_SETTINGS:-}"
      -e VELDMUIS_AUR_ENABLE_FALLBACK="${VELDMUIS_AUR_ENABLE_FALLBACK:-}"
      -e VELDMUIS_SIMULATE_AUR_BUILD_FAILURE="${VELDMUIS_SIMULATE_AUR_BUILD_FAILURE:-}"
      -e PACKAGE_BASE_URL="${PACKAGE_BASE_URL:-}"
    )
  elif [[ "${stage}" == "sign" ]]; then
    mount_mode="ro"
    docker_args+=(
      --network none
      -e VELDMUIS_KEY_FPR_FILE
      -e VELDMUIS_GPG_PRIVATE_KEY
      -e VELDMUIS_GPG_FPR
    )
  elif [[ "${stage}" == "offline-download" ]]; then
    mount_mode="ro"
    docker_args+=(
      -e VELDMUIS_ARCH_SNAPSHOT="${VELDMUIS_ARCH_SNAPSHOT:-}"
    )
  elif [[ "${stage}" == "offline-sign" ]]; then
    mount_mode="ro"
    docker_args+=(
      --network none
      -e VELDMUIS_KEY_FPR_FILE
      -e VELDMUIS_GPG_PRIVATE_KEY
      -e VELDMUIS_GPG_FPR
      -e VELDMUIS_ARCH_SNAPSHOT="${VELDMUIS_ARCH_SNAPSHOT:-}"
    )
  elif [[ "${stage}" == "offline-validate" ]]; then
    mount_mode="ro"
    docker_args+=(
      --network none
    )
  elif [[ "${stage}" == "release-metadata" ]]; then
    mount_mode="ro"
    docker_args+=(
      --network none
      -e VELDMUIS_KEY_FPR_FILE
      -e VELDMUIS_GPG_PRIVATE_KEY
      -e VELDMUIS_GPG_FPR
      -e VELDMUIS_RELEASE_TAG="${VELDMUIS_RELEASE_TAG:-}"
      -e VELDMUIS_RELEASE_SHA="${VELDMUIS_RELEASE_SHA:-}"
      -e VELDMUIS_BUILDER_BASE_IMAGE="${builder_base_image}"
      -e VELDMUIS_BUILDER_BASE_DIGEST="${builder_base_digest}"
      -e VELDMUIS_BUILDER_IMAGE_ID="${builder_image_id}"
      -e VELDMUIS_DOCKER_VERSION="${docker_version}"
      -e VELDMUIS_ISO_MODE="$([[ "${target}" == "offline-iso" ]] && printf offline || printf network)"
    )
  elif [[ "${stage}" == "iso" ]]; then
    mount_mode="ro"
    docker_args+=(
      --privileged
      -e VELDMUIS_RELEASE_TAG="${VELDMUIS_RELEASE_TAG:-}"
      -e VELDMUIS_ISO_MODE="$([[ "${target}" == "offline-iso" ]] && printf offline || printf network)"
    )
  fi

  docker_args+=(
    -v "${repo_root}:${container_workspace}:${mount_mode}"
    -v "${trusted_support_root}:${container_support_root}:ro"
    -w "${container_workspace}"
  )

  if [[ "${stage}" == "aur" ]]; then
    mkdir -p "${repo_root}/artifacts"
    docker_args+=(-v "${repo_root}/artifacts:${container_workspace}/artifacts:rw")
  elif [[ "${stage}" == "sign" || "${stage}" == "offline-download" || "${stage}" == "offline-sign" ]]; then
    mkdir -p "${repo_root}/repos"
    docker_args+=(-v "${repo_root}/repos:${container_workspace}/repos:rw")
  elif [[ "${stage}" == "iso" || "${stage}" == "release-metadata" ]]; then
    local host_build_root="${RUNNER_TEMP}/veldmuis-build"
    mkdir -p "${host_build_root}"
    docker_args+=(-v "${host_build_root}:/workspace/build:rw")
  fi

  docker_args+=(
    "${image}"
    bash
    "${container_support_root}/development/run-ci-arch-builder.sh"
    --in-container
    "${stage}"
    "${target}"
  )

  docker "${docker_args[@]}"
}

run_build_in_containers() {
  local target="$1"

  require_cmd docker
  require_env BUILDER_USER
  require_env BUILDER_HOME
  require_env GNUPGHOME
  if [[ "${target}" != candidate ]]; then
    require_env VELDMUIS_KEY_FPR_FILE
    require_env VELDMUIS_GPG_PRIVATE_KEY
    require_env VELDMUIS_GPG_FPR
  fi
  require_env RUNNER_TEMP

  if [[ "${target}" == "iso" || "${target}" == "offline-iso" ]]; then
    require_env VELDMUIS_RELEASE_TAG
    require_env VELDMUIS_RELEASE_SHA
  fi
  if [[ "${target}" == "offline-iso" ]]; then
    require_env VELDMUIS_ARCH_SNAPSHOT
  fi

  prepare_trusted_support
  trap cleanup_outer_resources EXIT
  prepare_builder_image "${target}"
  run_container_stage packages "${target}"
  run_container_stage aur "${target}"
  if [[ "${target}" != candidate ]]; then
    run_container_stage sign "${target}"
  fi

  if [[ "${target}" == "offline-iso" ]]; then
    run_container_stage offline-download "${target}"
    run_container_stage offline-sign "${target}"
    run_container_stage offline-validate "${target}"
  fi

  if [[ "${target}" == "iso" || "${target}" == "offline-iso" ]]; then
    run_container_stage iso "${target}"
    run_container_stage release-metadata "${target}"
  fi

  cleanup_outer_resources
  trap - EXIT
}

main() {
  local in_container=0
  local stage=""
  local target="${1:-}"

  if [[ "${target}" == "--in-container" ]]; then
    in_container=1
    stage="${2:-}"
    target="${3:-}"
  fi

  validate_target "${target}"

  if (( in_container )); then
    validate_stage "${stage}"
    case "${stage}" in
      packages)
        run_package_build_stage
        ;;
      aur)
        run_aur_build_stage
        ;;
      sign)
        run_signing_stage
        ;;
      offline-download)
        run_offline_download_stage
        ;;
      offline-sign)
        run_offline_signing_stage
        ;;
      offline-validate)
        run_offline_validation_stage
        ;;
      iso)
        run_iso_stage
        ;;
      release-metadata)
        run_release_metadata_stage
        ;;
    esac
  else
    run_build_in_containers "${target}"
  fi
}

main "$@"
