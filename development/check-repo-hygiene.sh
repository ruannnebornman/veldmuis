#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

log() {
  printf '[check-repo-hygiene] %s\n' "$*"
}

die() {
  printf '[check-repo-hygiene] ERROR: %s\n' "$*" >&2
  exit 1
}

tracked_bash_scripts() {
  local file

  git -C "${repo_root}" ls-files -z | while IFS= read -r -d '' file; do
    [[ -f "${repo_root}/${file}" ]] || continue

    case "${file}" in
      *.sh|archiso/veldmuis/airootfs/usr/local/bin/*|packages/veldmuis-boot/veldmuis-kernel-install-sync)
        printf '%s\0' "${file}"
        continue
        ;;
    esac

    if head -n 1 "${repo_root}/${file}" | grep -Eq '^#! */(usr/bin/env +bash|bin/bash)'; then
      printf '%s\0' "${file}"
    fi
  done
}

check_shell_syntax() {
  local -a scripts=()
  local script

  mapfile -d '' -t scripts < <(tracked_bash_scripts)
  ((${#scripts[@]} > 0)) || die "No Bash scripts found to check."

  log "Checking Bash syntax for ${#scripts[@]} tracked scripts"
  for script in "${scripts[@]}"; do
    bash -n "${repo_root}/${script}"
  done

  if command -v shellcheck >/dev/null 2>&1; then
    log "Running shellcheck"
    (
      cd "${repo_root}"
      shellcheck -x "${scripts[@]}"
    )
  else
    log "shellcheck not installed; skipped optional shell lint"
  fi
}

check_tracked_artifacts() {
  local -a generated_artifacts=()

  mapfile -t generated_artifacts < <(
    git -C "${repo_root}" ls-files | grep -E \
      '^packages/[^/]+/(pkg|src)/|^artifacts/|^build/|\.pkg\.tar(\.[^.]+)?$|\.pkg\.tar\.[^.]+(\.sig)?$|\.iso$|\.iso\.sha256$' || true
  )

  ((${#generated_artifacts[@]} == 0)) || {
    printf '%s\n' "${generated_artifacts[@]}" >&2
    die "Generated package, ISO, or build artifacts are tracked."
  }

  log "No tracked package, ISO, or build artifacts found"
}

main() {
  check_shell_syntax
  check_tracked_artifacts
}

main "$@"
