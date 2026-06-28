#!/usr/bin/env bash
# shellcheck disable=SC2034

# Sourced by package build and repo publication helpers.

veldmuis_core_package_order=(
  "calamares"
  "veldmuis-calamares-config"
  "veldmuis-keyring"
  "veldmuis-mirrorlist"
  "veldmuis-lsb-release"
  "veldmuis-release"
  "veldmuis-base"
  "veldmuis-common"
  "veldmuis-boot"
  "veldmuis-displaymanager"
  "veldmuis-desktop-kde"
  "veldmuis-development"
  "veldmuis-gaming"
  "veldmuis-downloads"
  "veldmuis-sync"
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
