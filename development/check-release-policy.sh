#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
check_remote=0

log() {
  printf '[check-release-policy] %s\n' "$*"
}

die() {
  printf '[check-release-policy] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  check-release-policy.sh
  check-release-policy.sh --remote

The default mode checks repository source and local tags. Remote mode also
checks GitHub releases and their attached manifests.
EOF
}

is_valid_monthly_tag() {
  local tag="$1"
  local pattern='^[0-9]{4}\.(0[1-9]|1[0-2])$'
  local normalized=""

  [[ "${tag}" =~ ${pattern} ]] || return 1
  normalized="$(date -u -d "${tag//./-}-01" +%Y.%m 2>/dev/null)" || return 1
  [[ "${normalized}" == "${tag}" ]]
}

is_valid_daily_tag() {
  local tag="$1"
  local pattern='^([0-9]{4})\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])(\.([2-9]|[1-9][0-9]+))?$'
  local date_part=""
  local normalized=""

  [[ "${tag}" =~ ${pattern} ]] || return 1
  date_part="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  normalized="$(date -u -d "${date_part//./-}" +%Y.%m.%d 2>/dev/null)" || return 1
  [[ "${normalized}" == "${date_part}" ]]
}

is_valid_release_tag() {
  is_valid_monthly_tag "$1" || is_valid_daily_tag "$1"
}

check_local_tags() {
  local tag

  while IFS= read -r tag; do
    [[ -n "${tag}" ]] || continue
    is_valid_release_tag "${tag}" || die "Unsupported or invalid local tag: ${tag}"
  done < <(git -C "${repo_root}" tag)

  log "Local tags follow the date-based release policy"
}

check_local_tag_sequences() {
  local tag
  local base
  local sequence
  local expected
  local max
  local key
  local daily_pattern='^([0-9]{4}\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01]))(\.([2-9]|[1-9][0-9]+))?$'
  declare -A seen=()
  declare -A maxima=()

  while IFS= read -r tag; do
    [[ "${tag}" =~ ${daily_pattern} ]] || continue
    base="${BASH_REMATCH[1]}"
    sequence="${BASH_REMATCH[5]:-1}"
    seen["${base}:${sequence}"]=1
    max="${maxima[${base}]:-0}"
    ((sequence > max)) && maxima["${base}"]="${sequence}"
  done < <(git -C "${repo_root}" tag)

  for base in "${!maxima[@]}"; do
    max="${maxima[${base}]}"
    for ((expected = 1; expected <= max; expected++)); do
      key="${base}:${expected}"
      [[ -n "${seen[${key}]:-}" ]] || \
        die "Release tag sequence has a gap: missing ${base}$([[ ${expected} -gt 1 ]] && printf '.%s' "${expected}")"
    done
  done

  log "Same-day release tag sequences are contiguous"
}

check_tag_examples() {
  local tag
  local -a valid_tags=(
    "2026.04"
    "2026.04.22"
    "2026.04.22.2"
    "2026.04.22.10"
  )
  local -a invalid_tags=(
    "v1.0.0"
    "2026.13"
    "2026.02.30"
    "2026.04.22.0"
    "2026.04.22.1"
    "2026.04.22.02"
  )

  for tag in "${valid_tags[@]}"; do
    is_valid_release_tag "${tag}" || die "Valid release-tag example was rejected: ${tag}"
  done
  for tag in "${invalid_tags[@]}"; do
    if is_valid_release_tag "${tag}"; then
      die "Invalid release-tag example was accepted: ${tag}"
    fi
  done

  log "Release-tag validation accepts only supported examples"
}

check_workflow_source() {
  local workflow="${repo_root}/.github/workflows/release.yml"

  [[ -f "${workflow}" ]] || die "Release workflow not found: ${workflow}"

  if grep -Eq 'release_version|RELEASE_VERSION|VELDMUIS_DOWNLOAD_URL' "${workflow}"; then
    die "Release workflow contains obsolete release-version or download-link variables."
  fi

  if grep -Eq 'gh release edit|--clobber' "${workflow}"; then
    die "Release workflow contains a release replacement path."
  fi

  if grep -Eq 'ISO download:|Direct HTTPS ISO:|Direct HTTPS checksum:' "${workflow}"; then
    die "Release workflow writes mutable ISO links into historical release notes."
  fi

  grep -q 'YYYY.MM.DD.N' "${workflow}" || \
    die "Release workflow does not document sequenced same-day tags."
  grep -q 'already exists and cannot be reused' "${workflow}" || \
    die "Release workflow does not reject tag or release reuse."
  grep -q 'VELDMUIS_RELEASE_TAG' "${workflow}" || \
    die "Release workflow does not pass the release tag into the ISO build."

  log "Release workflow source follows the one-shot release policy"
}

check_branding_source() {
  local branding="${repo_root}/packages/veldmuis-calamares-config/branding/veldmuis/branding.desc"

  [[ -f "${branding}" ]] || die "Calamares branding not found: ${branding}"
  if grep -qi 'preview' "${branding}"; then
    die "Calamares production branding still contains Preview."
  fi

  log "Calamares production branding is not marked Preview"
}

check_package_suffix_source() {
  local repo_builder="${repo_root}/development/build-local-repo.sh"

  [[ -f "${repo_builder}" ]] || die "Package repository builder not found: ${repo_builder}"
  if grep -Eq 'repo_package_suffix=.*:-v' "${repo_builder}"; then
    die "Package repository cache suffix still resembles a v-prefixed release tag."
  fi
  grep -q 'repo_package_suffix=.*build' "${repo_builder}" || \
    die "Package repository cache suffix is not explicitly build-labelled."

  log "Package repository cache suffix is clearly build-labelled"
}

check_remote_releases() {
  local release_tag
  local tag_sha
  local manifest_url
  local manifest
  local manifest_tag
  local manifest_sha
  local bad_body_tags
  local retired_body_tags
  local latest_iso_url="${VELDMUIS_LATEST_ISO_URL:-}"

  command -v gh >/dev/null 2>&1 || die "gh is required for --remote"
  command -v curl >/dev/null 2>&1 || die "curl is required for --remote"

  bad_body_tags="$(
    gh api --paginate 'repos/{owner}/{repo}/releases' \
      --jq '.[] | select((.body // "") | test("latest\\.iso|ISO download:|Direct HTTPS ISO:|Direct HTTPS checksum:"; "i")) | .tag_name'
  )"
  [[ -z "${bad_body_tags}" ]] || {
    printf '%s\n' "${bad_body_tags}" >&2
    die "GitHub release bodies contain mutable ISO links."
  }

  retired_body_tags="$(
    gh api --paginate 'repos/{owner}/{repo}/releases' \
      --jq '.[] | select((.body // "") | test("v1\\.|v2026|vYYYY|YYYY\\.MM\\.N|semver|alpha release|beta release"; "i")) | .tag_name'
  )"
  [[ -z "${retired_body_tags}" ]] || {
    printf '%s\n' "${retired_body_tags}" >&2
    die "GitHub release bodies contain retired release-version terminology."
  }

  while IFS= read -r release_tag; do
    [[ -n "${release_tag}" ]] || continue
    is_valid_release_tag "${release_tag}" || die "Unsupported GitHub release tag: ${release_tag}"
    git -C "${repo_root}" rev-parse --verify "refs/tags/${release_tag}" >/dev/null 2>&1 || \
      die "GitHub release has no matching local tag: ${release_tag}"

    tag_sha="$(git -C "${repo_root}" rev-list -n 1 "${release_tag}")"
    manifest_url="$(
      gh release view "${release_tag}" --json assets \
        --jq '.assets[] | select(.name | endswith(".manifest.txt")) | .url' \
        | head -n 1
    )"
    [[ -n "${manifest_url}" ]] || die "GitHub release has no manifest asset: ${release_tag}"

    manifest="$(curl -fsSL "${manifest_url}")"
    manifest_tag="$(awk -F= '$1 == "release_tag" { print $2; exit }' <<<"${manifest}")"
    manifest_sha="$(awk -F= '$1 == "release_sha" { print $2; exit }' <<<"${manifest}")"
    [[ "${manifest_tag}" == "${release_tag}" ]] || \
      die "Manifest tag mismatch for ${release_tag}: ${manifest_tag}"
    [[ "${manifest_sha}" == "${tag_sha}" ]] || \
      die "Manifest commit mismatch for ${release_tag}: ${manifest_sha}"
  done < <(gh release list --limit 100 --json tagName --jq '.[].tagName')

  if [[ -n "${latest_iso_url}" ]]; then
    [[ "${latest_iso_url}" =~ ^https:// ]] || \
      die "VELDMUIS_LATEST_ISO_URL must use HTTPS: ${latest_iso_url}"
    curl -fsSI "${latest_iso_url}" >/dev/null || \
      die "Latest ISO URL is not reachable: ${latest_iso_url}"
  fi

  log "GitHub releases and manifests follow the release policy"
}

main() {
  case "${1:-}" in
    "")
      ;;
    --remote)
      check_remote=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unsupported argument: $1"
      ;;
  esac

  check_local_tags
  check_local_tag_sequences
  check_tag_examples
  check_workflow_source
  check_branding_source
  check_package_suffix_source

  if ((check_remote)); then
    check_remote_releases
  fi
}

main "$@"
