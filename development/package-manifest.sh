#!/usr/bin/env bash

veldmuis_core_package_order=(
  "calamares"
  "veldmuis-calamares-config"
  "veldmuis-keyring"
  "veldmuis-mirrorlist"
  "veldmuis-release"
  "veldmuis-base"
  "veldmuis-common"
  "veldmuis-boot"
  "veldmuis-displaymanager"
  "veldmuis-desktop-kde"
  "veldmuis-gaming"
  "veldmuis-multimedia"
  "veldmuis-branding"
  "veldmuis-desktop"
)

veldmuis_extra_package_order=(
  "veldmuis-nvidia-legacy"
)

veldmuis_package_order=(
  "${veldmuis_core_package_order[@]}"
  "${veldmuis_extra_package_order[@]}"
)
