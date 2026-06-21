#!/usr/bin/env bash

veldmuis_nvidia_580xx_aur_package_bases=(
  "nvidia-580xx-utils"
  "lib32-nvidia-580xx-utils"
  "nvidia-580xx-settings"
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
