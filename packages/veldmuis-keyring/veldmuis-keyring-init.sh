#!/usr/bin/env bash

set -euo pipefail

release_key_id() {
  awk -F: '
    NF && $1 !~ /^#/ {
      print $1
      exit
    }
  ' /usr/share/pacman/keyrings/veldmuis-trusted 2>/dev/null
}

main() {
  local key_id=""
  local state_dir="/var/lib/veldmuis"
  local marker=""

  key_id="$(release_key_id)"
  marker="${state_dir}/keyring-initialized${key_id:+-${key_id}}"

  install -d -m755 "${state_dir}"
  [[ ! -e "${marker}" ]] || exit 0

  pacman-key --init
  pacman-key --populate archlinux veldmuis
  pacman-key --updatedb

  if [[ -n "${key_id}" ]]; then
    pacman-key --lsign-key "${key_id}"
  fi

  rm -f \
    /var/lib/pacman/sync/veldmuis-core.db \
    /var/lib/pacman/sync/veldmuis-core.db.sig \
    /var/lib/pacman/sync/veldmuis-extra.db \
    /var/lib/pacman/sync/veldmuis-extra.db.sig

  touch "${marker}"
}

main "$@"
