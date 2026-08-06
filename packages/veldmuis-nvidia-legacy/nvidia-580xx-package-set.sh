#!/usr/bin/env bash
# shellcheck disable=SC2034

# Sourced by NVIDIA AUR build, publish, restore, and metapackage helpers.

veldmuis_nvidia_580xx_aur_package_bases=(
  "nvidia-580xx-utils"
  "lib32-nvidia-580xx-utils"
  "nvidia-580xx-settings"
)

# Audited direct official build-dependency roots for the locked AUR recipes
# above. Keep locally built nvidia-580xx packages out of this list.
veldmuis_nvidia_580xx_official_build_dependency_roots=(
  "dkms"
  "egl-gbm"
  "egl-wayland"
  "egl-x11"
  "gtk3"
  "jansson"
  "lib32-gcc-libs"
  "lib32-libglvnd"
  "lib32-zlib"
  "libglvnd"
  "libvdpau"
  "libxext"
  "libxv"
  "vulkan-headers"
  "zlib"
)

veldmuis_nvidia_580xx_repository_packages=(
  "nvidia-580xx-dkms"
  "nvidia-580xx-utils"
  "opencl-nvidia-580xx"
  "lib32-nvidia-580xx-utils"
  "lib32-opencl-nvidia-580xx"
  "nvidia-580xx-settings"
  "libxnvctrl-580xx"
)

veldmuis_nvidia_580xx_runtime_packages=(
  "nvidia-580xx-dkms"
  "nvidia-580xx-utils"
  "opencl-nvidia-580xx"
  "lib32-nvidia-580xx-utils"
  "lib32-opencl-nvidia-580xx"
  "nvidia-580xx-settings"
)

declare -A veldmuis_nvidia_580xx_expected_licenses=(
  ["nvidia-580xx-dkms"]="custom"
  ["nvidia-580xx-utils"]="custom"
  ["opencl-nvidia-580xx"]="custom"
  ["lib32-nvidia-580xx-utils"]="custom"
  ["lib32-opencl-nvidia-580xx"]="custom"
  ["nvidia-580xx-settings"]="GPL-2.0-only"
  ["libxnvctrl-580xx"]="GPL-2.0-only"
)
