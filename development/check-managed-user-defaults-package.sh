#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
package_dir="${repo_root}/packages/veldmuis-desktop-kde"
temp_root="$(mktemp -d -t veldmuis-managed-defaults-package.XXXXXX)"
pkgdir="${temp_root}/pkg"
history_rel="packages/veldmuis-desktop-kde/user-defaults-history.tsv"

cleanup() {
  rm -rf -- "${temp_root}"
}
trap cleanup EXIT

expected_fish_hash="$(sha256sum "${package_dir}/config.fish")"
expected_fish_hash=${expected_fish_hash%% *}
expected_wezterm_hash="$(sha256sum "${package_dir}/wezterm.lua")"
expected_wezterm_hash=${expected_wezterm_hash%% *}

(
  cd "${package_dir}"
  # shellcheck source=packages/veldmuis-desktop-kde/PKGBUILD
  source ./PKGBUILD
  srcdir="${package_dir}" package
)

defaults_root="${pkgdir}/usr/share/veldmuis/user-defaults/v1"
manifest_path="${defaults_root}/manifest.tsv"
state_path="${pkgdir}/etc/skel/.local/state/veldmuis/user-defaults/state.ini"

test -x "${pkgdir}/usr/lib/veldmuis/veldmuis-user-defaults-update"
test "$(stat -c '%a' "${pkgdir}/usr/lib/veldmuis/veldmuis-user-defaults-update")" = 755
test "$(stat -c '%a' "${pkgdir}/etc/xdg/autostart/veldmuis-user-defaults-update.desktop")" = 644
test "$(stat -c '%a' "${state_path}")" = 600

grep -Fqx "fish/config.fish$(printf '\t')templates/fish/config.fish$(printf '\t')${expected_fish_hash}$(printf '\t')1" \
  "${manifest_path}"
grep -Fqx "wezterm/wezterm.lua$(printf '\t')templates/wezterm/wezterm.lua$(printf '\t')${expected_wezterm_hash}$(printf '\t')1" \
  "${manifest_path}"
grep -Fqx "applied_hash=${expected_fish_hash}" "${state_path}"
grep -Fqx "applied_hash=${expected_wezterm_hash}" "${state_path}"
grep -Fqx "candidate_hash=${expected_fish_hash}" "${state_path}"
grep -Fqx "candidate_hash=${expected_wezterm_hash}" "${state_path}"
grep -Fqx 'Exec=/usr/lib/veldmuis/veldmuis-user-defaults-update' \
  "${pkgdir}/etc/xdg/autostart/veldmuis-user-defaults-update.desktop"

mkdir -p "${temp_root}/home/.config/fish" "${temp_root}/home/.config/wezterm"
mkdir -p "${temp_root}/state/veldmuis/user-defaults"
cp -- "${pkgdir}/etc/skel/.config/fish/config.fish" \
  "${temp_root}/home/.config/fish/config.fish"
cp -- "${pkgdir}/etc/skel/.config/wezterm/wezterm.lua" \
  "${temp_root}/home/.config/wezterm/wezterm.lua"
cp -- "${state_path}" "${temp_root}/state/veldmuis/user-defaults/state.ini"
fish_inode_before="$(stat -c '%i' "${temp_root}/home/.config/fish/config.fish")"
wezterm_inode_before="$(stat -c '%i' "${temp_root}/home/.config/wezterm/wezterm.lua")"

HOME="${temp_root}/home" \
XDG_STATE_HOME="${temp_root}/state" \
  bash -c 'source "$1"; veldmuis_user_defaults_test_run "$2"' _ \
  "${pkgdir}/usr/lib/veldmuis/veldmuis-user-defaults-update" \
  "${defaults_root}"

test "$(stat -c '%i' "${temp_root}/home/.config/fish/config.fish")" = "${fish_inode_before}"
test "$(stat -c '%i' "${temp_root}/home/.config/wezterm/wezterm.lua")" = "${wezterm_inode_before}"

base_ref="${GITHUB_BASE_REF:-main}"
previous_history="${temp_root}/previous-history.tsv"
history_header=$'config_path\tsha256\trevision'
if git -C "${repo_root}" show "origin/${base_ref}:${history_rel}" > "${previous_history}" 2>/dev/null || \
   git -C "${repo_root}" show "${base_ref}:${history_rel}" > "${previous_history}" 2>/dev/null; then
  while IFS= read -r history_line || [[ -n "${history_line}" ]]; do
    [[ -n "${history_line}" && "${history_line}" != "${history_header}" ]] || continue
    grep -Fqx "${history_line}" "${package_dir}/user-defaults-history.tsv" || {
      printf '[check-managed-user-defaults-package] History row was removed: %s\n' "${history_line}" >&2
      exit 1
    }
  done < "${previous_history}"
fi

printf '[check-managed-user-defaults-package] Package payload and seeded no-op passed.\n'
