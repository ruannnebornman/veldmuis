#!/usr/bin/env bash

set -euo pipefail

target_root="${1:-}"
graphics_choice="${2:-all-open-source}"
live_repo_root="/opt/veldmuis/repo"
tmp_pacman_conf=""
log_file="/tmp/veldmuis-calamares-bootstrap.log"
aur_builder_user="veldmuisaur"

log() {
  printf '[veldmuis-calamares-bootstrap] %s\n' "$*"
}

die() {
  printf '[veldmuis-calamares-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  [[ -n "${tmp_pacman_conf}" ]] && rm -f "${tmp_pacman_conf}"

  if [[ -n "${target_root}" && -d "${target_root}" ]]; then
    arch-chroot "${target_root}" /usr/bin/bash -lc "
      rm -f '/etc/sudoers.d/${aur_builder_user}'
      userdel -r '${aur_builder_user}' >/dev/null 2>&1 || true
    " >/dev/null 2>&1 || true
  fi
}

normalize_graphics_choice() {
  case "${graphics_choice}" in
    all-open-source|default-open-source|amd-open-source|intel-open-source|nvidia-open-source|nvidia-580xx-dkms)
      ;;
    "")
      graphics_choice="all-open-source"
      ;;
    *)
      log "Unknown graphics choice '${graphics_choice}', defaulting to all-open-source"
      graphics_choice="all-open-source"
      ;;
  esac
}

has_non_loopback_nameserver() {
  local resolver_path="$1"

  awk '
    $1 == "nameserver" && $2 !~ /^(127\.|::1$|0\.0\.0\.0$)/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "${resolver_path}"
}

pick_resolver_source() {
  local candidate

  for candidate in \
    /run/systemd/resolve/resolv.conf \
    /run/NetworkManager/no-stub-resolv.conf \
    /run/NetworkManager/resolv.conf \
    /etc/resolv.conf
  do
    [[ -f "${candidate}" ]] || continue
    if has_non_loopback_nameserver "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

write_pacman_conf() {
  tmp_pacman_conf="$(mktemp -t veldmuis-calamares-pacman.XXXXXX)"
  cp /etc/pacman.conf "${tmp_pacman_conf}"

  # The installer should favor reliability over throughput on weak Wi-Fi.
  # Multiple concurrent downloads and pacman's low-speed timeout have caused
  # large desktop installs to fail on bare metal.
  if grep -q '^ParallelDownloads' "${tmp_pacman_conf}"; then
    sed -i 's/^ParallelDownloads.*/ParallelDownloads = 1/' "${tmp_pacman_conf}"
  else
    sed -i '/^\[options\]/a ParallelDownloads = 1' "${tmp_pacman_conf}"
  fi

  if ! grep -q '^DisableDownloadTimeout$' "${tmp_pacman_conf}"; then
    sed -i '/^\[options\]/a DisableDownloadTimeout' "${tmp_pacman_conf}"
  fi

  cat >>"${tmp_pacman_conf}" <<EOF

[veldmuis-core]
SigLevel = Required DatabaseOptional
Server = file://${live_repo_root}/veldmuis-core/os/\$arch

[veldmuis-extra]
SigLevel = Required DatabaseOptional
Server = file://${live_repo_root}/veldmuis-extra/os/\$arch
EOF
}

has_secret_key() {
  local gpgdir="$1"

  gpg --homedir "${gpgdir}" --batch --with-colons -K 2>/dev/null | grep -q '^sec:'
}

target_has_secret_key() {
  arch-chroot "${target_root}" /usr/bin/bash -lc \
    "gpg --homedir /etc/pacman.d/gnupg --batch --with-colons -K 2>/dev/null | grep -q '^sec:'"
}

release_key_id_from_dir() {
  local keyring_dir="$1"
  local trusted_file="${keyring_dir}/veldmuis-trusted"

  [[ -f "${trusted_file}" ]] || return 0

  awk -F: '
    NF && $1 !~ /^#/ {
      print $1
      exit
    }
  ' "${trusted_file}"
}

ensure_keyring_populated() {
  local gpgdir="$1"
  local keyring_dir="$2"
  local label="$3"
  local release_key_id=""

  install -d -m700 "${gpgdir}"

  if ! has_secret_key "${gpgdir}"; then
    log "Initializing ${label} pacman keyring"
    pacman-key --gpgdir "${gpgdir}" --init
  fi

  log "Populating ${label} pacman keyring with Arch and Veldmuis signing keys"
  pacman-key --gpgdir "${gpgdir}" --populate-from "${keyring_dir}" --populate archlinux veldmuis
  log "Updating ${label} pacman trust database"
  pacman-key --gpgdir "${gpgdir}" --updatedb

  release_key_id="$(release_key_id_from_dir "${keyring_dir}")"
  if [[ -n "${release_key_id}" ]]; then
    log "Locally signing the Veldmuis release key in the ${label} keyring"
    pacman-key --gpgdir "${gpgdir}" --lsign-key "${release_key_id}"
  fi
}

ensure_target_keyring_populated() {
  local release_key_id="$1"

  if ! target_has_secret_key; then
    log "Initializing target pacman keyring"
    arch-chroot "${target_root}" pacman-key --init
  fi

  log "Populating target pacman keyring with Arch and Veldmuis signing keys"
  arch-chroot "${target_root}" pacman-key --populate archlinux veldmuis
  log "Updating target pacman trust database"
  arch-chroot "${target_root}" pacman-key --updatedb

  if [[ -n "${release_key_id}" ]]; then
    log "Locally signing the Veldmuis release key in the target keyring"
    arch-chroot "${target_root}" pacman-key --lsign-key "${release_key_id}"
  fi
}

prepare_target_root() {
  local resolver_source=""

  install -d -m755 "${target_root}/etc"
  install -Dm644 /dev/null "${target_root}/etc/vconsole.conf"

  if resolver_source="$(pick_resolver_source)"; then
    log "Copying resolver config from ${resolver_source} into ${target_root}"
    install -Dm644 "${resolver_source}" "${target_root}/etc/resolv.conf"
  else
    die "Could not find a non-loopback resolver config in the live environment."
  fi
}

normalize_keyring_permissions() {
  local gpgdir="$1"

  [[ -d "${gpgdir}" ]] || return 0

  chmod 755 "${gpgdir}"

  for dir_name in crls.d openpgp-revocs.d private-keys-v1.d; do
    [[ -d "${gpgdir}/${dir_name}" ]] || continue
    chmod 700 "${gpgdir}/${dir_name}"
  done

  for file_name in pubring.gpg trustdb.gpg gpg.conf gpg-agent.conf tofu.db; do
    [[ -f "${gpgdir}/${file_name}" ]] || continue
    chmod 644 "${gpgdir}/${file_name}"
  done

  [[ -f "${gpgdir}/secring.gpg" ]] && chmod 600 "${gpgdir}/secring.gpg"
}

install_target_packages() {
  (($# > 0)) || return 0

  log "Installing target packages: $*"
  arch-chroot "${target_root}" pacman -S --noconfirm --needed "$@"
}

install_selected_graphics_stack() {
  local -a packages=()

  case "${graphics_choice}" in
    default-open-source)
      ;;
    all-open-source)
      packages=(
        mesa
        xf86-video-amdgpu
        xf86-video-ati
        xf86-video-nouveau
        libva-intel-driver
        intel-media-driver
        vulkan-radeon
        vulkan-intel
        vulkan-nouveau
        xorg-server
        xorg-xinit
      )
      ;;
    amd-open-source)
      packages=(
        mesa
        xf86-video-amdgpu
        xf86-video-ati
        vulkan-radeon
        xorg-server
        xorg-xinit
      )
      ;;
    intel-open-source)
      packages=(
        mesa
        libva-intel-driver
        intel-media-driver
        vulkan-intel
        xorg-server
        xorg-xinit
      )
      ;;
    nvidia-open-source)
      packages=(
        mesa
        xf86-video-nouveau
        vulkan-nouveau
        xorg-server
        xorg-xinit
      )
      ;;
    nvidia-580xx-dkms)
      packages=(
        base-devel
        dkms
        linux-headers
        xorg-server
        xorg-xinit
      )
      ;;
  esac

  install_target_packages "${packages[@]}"
}

ensure_target_aur_builder() {
  log "Preparing temporary AUR build user in the target system"
  arch-chroot "${target_root}" /usr/bin/bash -lc "
    if ! id -u '${aur_builder_user}' >/dev/null 2>&1; then
      useradd -m -U -s /bin/bash '${aur_builder_user}'
    fi
    install -d -m 700 -o '${aur_builder_user}' -g '${aur_builder_user}' '/home/${aur_builder_user}/aurbuild'
    printf '%s\n' \
      '${aur_builder_user} ALL=(ALL) NOPASSWD: /usr/bin/pacman' \
      'Defaults:${aur_builder_user} !requiretty' \
      > '/etc/sudoers.d/${aur_builder_user}'
    chmod 440 '/etc/sudoers.d/${aur_builder_user}'
  "
}

cleanup_target_aur_builder() {
  log "Cleaning up temporary AUR build user in the target system"
  arch-chroot "${target_root}" /usr/bin/bash -lc "
    rm -f '/etc/sudoers.d/${aur_builder_user}'
    userdel -r '${aur_builder_user}' >/dev/null 2>&1 || true
  "
}

remove_conflicting_nvidia_packages() {
  local candidate
  local -a installed_packages=()

  # The default desktop install brings in Steam, which in turn pulls the
  # default vulkan-driver providers on Nvidia hardware. Those official packages
  # conflict with the 580xx AUR stack we install immediately afterward.
  for candidate in \
    nvidia-utils \
    lib32-nvidia-utils \
    opencl-nvidia \
    lib32-opencl-nvidia \
    nvidia \
    nvidia-dkms \
    nvidia-open \
    nvidia-open-dkms
  do
    if arch-chroot "${target_root}" pacman -Q "${candidate}" >/dev/null 2>&1; then
      installed_packages+=("${candidate}")
    fi
  done

  if ((${#installed_packages[@]} == 0)); then
    return 0
  fi

  log "Removing conflicting Nvidia packages before installing the 580xx AUR stack: ${installed_packages[*]}"
  arch-chroot "${target_root}" pacman -Rdd --noconfirm "${installed_packages[@]}"
}

install_aur_package_base() {
  local package_base="$1"

  log "Installing AUR package base ${package_base} into the target system"
  arch-chroot "${target_root}" \
    /usr/bin/runuser -u "${aur_builder_user}" -- \
    /usr/bin/env HOME="/home/${aur_builder_user}" \
    /usr/bin/bash -lc "
      set -euo pipefail
      build_root=\"\$HOME/aurbuild\"
      package_dir=\"\${build_root}/${package_base}\"
      rm -rf \"\${package_dir}\"
      mkdir -p \"\${build_root}\"
      git clone --depth 1 'https://aur.archlinux.org/${package_base}.git' \"\${package_dir}\"
      cd \"\${package_dir}\"
      makepkg -si --noconfirm
    "
}

install_nvidia_580xx_stack() {
  remove_conflicting_nvidia_packages
  ensure_target_aur_builder

  # The nvidia-580xx-utils AUR base produces and installs both the userspace
  # package and the matching dkms package as split packages.
  install_aur_package_base "nvidia-580xx-utils"
  install_aur_package_base "lib32-nvidia-580xx-utils"

  cleanup_target_aur_builder
}

main() {
  require_cmd pacstrap
  require_cmd pacman-key
  require_cmd gpg
  require_cmd arch-chroot
  local release_key_id=""

  exec > >(tee "${log_file}") 2>&1

  [[ -n "${target_root}" ]] || die "Missing target root argument."
  [[ -d "${target_root}" ]] || die "Target root does not exist: ${target_root}"
  [[ -d "${live_repo_root}/veldmuis-core/os/x86_64" ]] || \
    die "Embedded Veldmuis repo not found at ${live_repo_root}"
  [[ -f /usr/share/pacman/keyrings/veldmuis.gpg ]] || \
    die "Veldmuis keyring is missing from the live environment."

  trap cleanup EXIT
  normalize_graphics_choice
  write_pacman_conf
  prepare_target_root

  ensure_keyring_populated /etc/pacman.d/gnupg /usr/share/pacman/keyrings live
  release_key_id="$(release_key_id_from_dir /usr/share/pacman/keyrings)"

  log "Installing Veldmuis package stack into ${target_root}"
  pacstrap -C "${tmp_pacman_conf}" "${target_root}" veldmuis-desktop

  ensure_target_keyring_populated "${release_key_id}"
  normalize_keyring_permissions "${target_root}/etc/pacman.d/gnupg"

  if [[ -f /etc/pacman.d/mirrorlist ]]; then
    install -Dm644 /etc/pacman.d/mirrorlist "${target_root}/etc/pacman.d/mirrorlist"
  fi

  if ! grep -qxF 'Include = /etc/pacman.conf.d/veldmuis.conf' "${target_root}/etc/pacman.conf"; then
    printf '\nInclude = /etc/pacman.conf.d/veldmuis.conf\n' >> "${target_root}/etc/pacman.conf"
  fi

  log "Selected graphics choice: ${graphics_choice}"
  install_selected_graphics_stack

  if [[ "${graphics_choice}" == "nvidia-580xx-dkms" ]]; then
    install_nvidia_580xx_stack
  fi

  if [[ -x "${target_root}/usr/bin/flatpak" && \
        -f "${target_root}/usr/share/flatpak/remotes.d/flathub.flatpakrepo" ]]; then
    log "Configuring Flathub in the target system"
    arch-chroot "${target_root}" \
      /usr/bin/flatpak remote-add --if-not-exists --system --from \
      flathub /usr/share/flatpak/remotes.d/flathub.flatpakrepo
  fi

  log "Bootstrap complete"
}

main "$@"
