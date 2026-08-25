#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
lock_file="${VELDMUIS_AUR_LOCK_FILE:-${script_dir}/aur-packages.lock}"
resolved_file="${VELDMUIS_AUR_RESOLVED_REFS_FILE:-}"

die() {
  printf '[update-aur-lock] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  update-aur-lock.sh --resolved-refs PATH [--lock-file PATH]

The resolved-ref file must contain one package base and one 40-character git
commit SHA per line. The lock file is updated in place.
EOF
}

main() {
  local lock_tmp=""

  while (($# > 0)); do
    case "$1" in
      --resolved-refs)
        shift
        (($# > 0)) || die "--resolved-refs requires a path"
        resolved_file="$1"
        ;;
      --lock-file)
        shift
        (($# > 0)) || die "--lock-file requires a path"
        lock_file="$1"
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage >&2
        die "Unsupported argument: $1"
        ;;
    esac
    shift
  done

  [[ -n "${resolved_file}" ]] || die "A resolved-ref file is required"
  [[ -r "${resolved_file}" ]] || die "Resolved-ref file is not readable: ${resolved_file}"
  [[ -r "${lock_file}" ]] || die "AUR lock file is not readable: ${lock_file}"

  lock_tmp="$(mktemp "${lock_file}.tmp.XXXXXX")"
  trap '[[ -n "${lock_tmp:-}" ]] && rm -f -- "${lock_tmp}"' EXIT

  awk '
    NR == FNR {
      if (NF != 2 || $1 ~ /^#/ || $2 !~ /^[0-9a-f]{40}$/) {
        exit 2
      }
      if ($1 in refs) {
        exit 3
      }
      refs[$1] = $2
      next
    }
    $1 in refs && $1 !~ /^#/ {
      printf "%s %s\n", $1, refs[$1]
      updated[$1] = 1
      next
    }
    { print }
    END {
      for (package_base in refs) {
        if (!(package_base in updated)) {
          exit 4
        }
      }
    }
  ' "${resolved_file}" "${lock_file}" >"${lock_tmp}" || {
    status=$?
    case "${status}" in
      2) die "Resolved refs must contain package bases and 40-character commit SHAs" ;;
      3) die "Resolved refs contain a duplicate package base" ;;
      4) die "Resolved refs contain a package base missing from the lock file" ;;
      *) die "Unable to update AUR lock file" ;;
    esac
  }

  if cmp -s "${lock_tmp}" "${lock_file}"; then
    rm -f -- "${lock_tmp}"
    trap - EXIT
    printf '[update-aur-lock] Lock file is already current: %s\n' "${lock_file#"${repo_root}"/}"
    return 0
  fi

  mv -f -- "${lock_tmp}" "${lock_file}"
  trap - EXIT
  printf '[update-aur-lock] Updated lock file: %s\n' "${lock_file#"${repo_root}"/}"
}

main "$@"
