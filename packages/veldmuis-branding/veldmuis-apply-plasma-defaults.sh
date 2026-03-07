#!/usr/bin/env bash

set -euo pipefail

config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
marker="${config_home}/veldmuis/first-login-pending"
stamp="${config_home}/veldmuis/defaults-applied"
log_dir="${state_home}/veldmuis"
log_file="${log_dir}/first-login-defaults.log"

case ":${XDG_CURRENT_DESKTOP:-}:" in
  *:KDE:*|*:PLASMA:*) ;;
  *)
    exit 0
    ;;
esac

[[ -f "${marker}" ]] || exit 0
command -v plasma-apply-lookandfeel >/dev/null 2>&1 || exit 0
command -v kwriteconfig6 >/dev/null 2>&1 || exit 0

mkdir -p "${config_home}/veldmuis" "${log_dir}"

{
  printf '[%s] applying Veldmuis Plasma defaults\n' "$(date --iso-8601=seconds)"
  plasma-apply-lookandfeel --resetLayout --apply org.veldmuis.desktop
  kwriteconfig6 --file "${config_home}/kdeglobals" --group KDE --key LookAndFeelPackage org.veldmuis.desktop
  kwriteconfig6 --file "${config_home}/kdeglobals" --group KDE --key DefaultDarkLookAndFeel org.veldmuis.desktop
  rm -f "${marker}"
  : > "${stamp}"
  printf '[%s] defaults applied successfully\n' "$(date --iso-8601=seconds)"
} >>"${log_file}" 2>&1
