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
checks GitHub releases, attached manifests, and detached signatures.
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

select_release_signature_url() {
  local asset_urls="$1"

  awk '/\.manifest\.txt\.sig$/ { print; exit }' <<<"${asset_urls}"
}

select_release_manifest_url() {
  local asset_urls="$1"
  local signature_url="$2"
  local manifest_url=""

  if [[ -n "${signature_url}" ]]; then
    manifest_url="${signature_url%.sig}"
    awk -v wanted="${manifest_url}" '$0 == wanted { found=1 } END { exit !found }' \
      <<<"${asset_urls}" || return 1
    printf '%s\n' "${manifest_url}"
    return 0
  fi

  awk '/\.manifest\.txt$/ && !/\.aur-packages\.manifest\.txt$/ { print; exit }' \
    <<<"${asset_urls}"
}

check_release_asset_selection() {
  local release_base="https://downloads.example.test/releases/2099.12"
  local manifest_url="${release_base}/veldmuis-2099.12-network-x86_64.manifest.txt"
  local signature_url="${manifest_url}.sig"
  local asset_urls=""
  local selected_manifest=""
  local selected_signature=""

  asset_urls="$(printf '%s\n' \
    "${release_base}/veldmuis-2099.12-network-x86_64.aur-packages.manifest.txt" \
    "${manifest_url}" \
    "${signature_url}")"
  selected_signature="$(select_release_signature_url "${asset_urls}")"
  selected_manifest="$(select_release_manifest_url "${asset_urls}" "${selected_signature}")"

  [[ "${selected_signature}" == "${signature_url}" ]] || \
    die "Release asset selection did not select the manifest signature."
  [[ "${selected_manifest}" == "${manifest_url}" ]] || \
    die "Release asset selection did not pair the signature with its exact manifest."

  log "Release signature selection pairs the exact manifest asset"
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
  local cleanup_line=""
  local publish_line=""
  local tag_line=""

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

  if grep -qF 'configure-r2-release-cors.sh' "${workflow}"; then
    die "Release workflow attempts to modify bucket-level CORS configuration."
  fi

  grep -q 'YYYY.MM.DD.N' "${workflow}" || \
    die "Release workflow does not document sequenced same-day tags."
  grep -q 'already exists and cannot be reused' "${workflow}" || \
    die "Release workflow does not reject tag or release reuse."
  grep -q 'VELDMUIS_RELEASE_TAG' "${workflow}" || \
    die "Release workflow does not pass the release tag into the ISO build."
  grep -q 'persist-credentials: false' "${workflow}" || \
    die "Release workflow leaves checkout credentials persisted."
  grep -q 'refs/heads/main' "${workflow}" || \
    die "Release workflow does not restrict source checkout to main."
  grep -q 'publish-r2-release.sh' "${workflow}" || \
    die "Release workflow does not use immutable release publication."
  grep -q 'prune-release-storage.sh' "${workflow}" || \
    die "Release workflow does not prune previous installer releases."
  tag_line="$(grep -nF -- '- name: Create immutable release tag' "${workflow}" | cut -d: -f1)"
  cleanup_line="$(grep -nF -- './development/prune-release-storage.sh' "${workflow}" | cut -d: -f1)"
  publish_line="$(grep -nF -- './development/publish-r2-release.sh' "${workflow}" | head -n 1 | cut -d: -f1)"
  [[ "${tag_line}" =~ ^[0-9]+$ && "${cleanup_line}" =~ ^[0-9]+$ && "${publish_line}" =~ ^[0-9]+$ ]] || \
    die "Release workflow publication ordering could not be resolved."
  ((tag_line < cleanup_line && cleanup_line < publish_line)) || \
    die "Release workflow must tag, prune older releases, and then publish in that order."
  grep -q 'channels/network.manifest.txt.sig' "${workflow}" || \
    die "Network release workflow does not publish a channel-manifest signature."
  grep -q 'gpgv --keyring ./packages/veldmuis-keyring/veldmuis.gpg' "${workflow}" || \
    die "Release workflow does not verify generated metadata with the packaged keyring."
  if grep -qF "if: github.event_name == 'schedule'" "${workflow}"; then
    die "Network release workflow still restricts offline builds to scheduled releases."
  fi
  grep -qF 'uses: ./.github/workflows/offline-iso-size.yml' "${workflow}" || \
    die "Network release workflow does not call the offline installer workflow."
  grep -qF "arch_snapshot: \${{ needs.validate-release.outputs.arch_snapshot }}" "${workflow}" || \
    die "Network release workflow does not pass its frozen Arch snapshot to the offline build."

  log "Release workflow source follows the one-shot release policy"
}

check_workflow_action_pins() {
  local workflow=""
  local line=""
  local action=""

  while IFS= read -r workflow; do
    while IFS= read -r line; do
      action="$(sed -E 's/^[[:space:]]*-[[:space:]]+uses:[[:space:]]+([^[:space:]#]+).*/\1/' <<<"${line}")"
      [[ "${action}" == ./* ]] && continue
      [[ "${action}" =~ @([0-9a-f]{40})$ ]] || \
        die "Workflow action is not pinned to a full commit SHA: ${workflow#"${repo_root}"/}: ${action}"
    done < <(grep -E '^[[:space:]]*-[[:space:]]+uses:' "${workflow}" || true)
  done < <(find "${repo_root}/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print)

  log "Workflow actions are pinned to immutable commit SHAs"
}

check_offline_release_workflow_source() {
  local workflow="${repo_root}/.github/workflows/offline-iso-size.yml"

  [[ -f "${workflow}" ]] || die "Offline ISO size workflow not found: ${workflow}"
  if grep -qF 'workflow_dispatch:' "${workflow}"; then
    die "Offline release workflow remains independently dispatchable."
  fi
  grep -qF "if: github.ref == 'refs/heads/main'" "${workflow}" || \
    die "Offline ISO size workflow is not restricted to main."
  grep -qF 'ref: refs/heads/main' "${workflow}" || \
    die "Offline ISO size workflow does not explicitly check out main."
  grep -qF 'workflow_call:' "${workflow}" || \
    die "Offline release workflow is not reusable by the scheduled release."
  grep -qF "ref: \${{ steps.candidate.outputs.release_sha }}" "${workflow}" || \
    die "Offline release workflow does not check out the resolved release commit."
  grep -qF "Release tag \${release_tag} does not resolve to \${release_sha}" "${workflow}" || \
    die "Offline release workflow does not verify the called release tag and commit."
  grep -qF './development/run-ci-arch-builder.sh offline-iso' "${workflow}" || \
    die "Offline ISO size workflow does not use the offline ISO build target."
  grep -qF './development/publish-r2-release.sh' "${workflow}" || \
    die "Offline release workflow does not publish immutable artifacts."
  grep -qF 'VELDMUIS_ISO_MODE: offline' "${workflow}" || \
    die "Offline release workflow does not select the offline release channel."
  if grep -qF 'configure-r2-release-cors.sh' "${workflow}"; then
    die "Offline release workflow attempts to modify bucket-level CORS configuration."
  fi
  if grep -Eq 'gh[[:space:]]+release|git/tags|git/refs' "${workflow}"; then
    die "Offline release workflow must not mutate the network release tag history."
  fi

  log "Offline release workflow is main-only and publishes the offline channel"
}

check_repository_signature_policy() {
  local file=""
  local section=""
  local policy=""
  local -a files=(
    "${repo_root}/archiso/veldmuis/pacman.conf.template"
    "${repo_root}/packages/veldmuis-release/veldmuis.conf"
  )

  for file in "${files[@]}"; do
    for section in veldmuis-core veldmuis-extra; do
      policy="$(
        awk -v wanted="${section}" '
          /^\[/ { in_section = ($0 == "[" wanted "]") }
          in_section && /^[[:space:]]*SigLevel[[:space:]]*=/ { print; exit }
        ' "${file}"
      )"
      [[ "${policy}" == "SigLevel = Required DatabaseRequired" ]] || \
        die "${file#"${repo_root}"/} does not require ${section} database signatures."
    done
  done

  file="${repo_root}/packages/veldmuis-calamares-config/veldmuis-calamares-bootstrap.sh"
  for section in veldmuis-core veldmuis-extra veldmuis-offline; do
    awk -v wanted="${section}" '
      /^\[/ { in_section = ($0 == "[" wanted "]") }
      in_section && $0 == "SigLevel = Required DatabaseRequired" { found=1 }
      END { exit found ? 0 : 1 }
    ' "${file}" || \
      die "Calamares bootstrap does not require the ${section} database signature."
  done

  log "All installer and Veldmuis pacman configurations require repository database signatures"
}

check_release_metadata_source() {
  local generator="${repo_root}/development/generate-release-metadata.sh"
  local publisher="${repo_root}/development/publish-r2-release.sh"
  local pruner="${repo_root}/development/prune-release-storage.sh"

  [[ -x "${generator}" ]] || die "Release metadata generator is missing or not executable."
  [[ -x "${publisher}" ]] || die "Release publisher is missing or not executable."
  [[ -x "${pruner}" ]] || die "Release-storage pruner is missing or not executable."
  grep -q -- '--detach-sign' "${generator}" || \
    die "Release metadata generator does not create a detached signature."
  grep -q 'SPDXVersion: SPDX-2.3' "${generator}" || \
    die "Release metadata generator does not create the SPDX inventory."
  grep -q 'releases/%s/%s' "${publisher}" || \
    die "Release publisher does not use release-specific object paths."
  grep -q 'channels/%s.%s' "${publisher}" || \
    die "Release publisher does not use installer-specific channel documents."
  grep -q 'Immutable release object already exists and will not be overwritten' "${publisher}" || \
    die "Release publisher does not reject existing immutable objects."
  if grep -Eq 'aws[[:space:]]+s3[[:space:]]+rm' "${publisher}"; then
    die "Release publisher contains a destructive prefix-removal path."
  fi
  grep -qF "s3 rm \"s3://\${bucket}/\${release_root}/\"" "${pruner}" || \
    die "Release-storage pruner does not target the release root."
  grep -qF -- "--exclude \"\${release_tag}/*\"" "${pruner}" || \
    die "Release-storage pruner does not protect the current release tag."
  grep -qF 'verify_previous_releases_removed' "${pruner}" || \
    die "Release-storage pruner does not verify cleanup."

  log "Release metadata is signed, previous releases are pruned, and the current tag remains immutable"
}

check_private_reporting_source() {
  local security_policy="${repo_root}/SECURITY.md"

  grep -qF 'https://github.com/ruannnebornman/veldmuis/security/advisories/new' \
    "${security_policy}" || \
    die "Security policy does not provide the private vulnerability-reporting form."
  if grep -q 'minimal issue asking for a private contact' "${security_policy}"; then
    die "Security policy still requires a public issue before private disclosure."
  fi

  log "Security policy provides a concrete private-reporting path"
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
  local release_asset_urls
  local manifest_url
  local signature_url
  local temp_root
  local manifest_path
  local signature_path
  local manifest_tag
  local manifest_sha
  local bad_body_tags
  local retired_body_tags
  local network_channel_url="${VELDMUIS_NETWORK_CHANNEL_URL:-}"
  local network_manifest_url="${VELDMUIS_NETWORK_MANIFEST_URL:-}"
  local network_signature_url="${VELDMUIS_NETWORK_MANIFEST_SIGNATURE_URL:-}"
  local channel_body=""
  local release_keyring="${VELDMUIS_RELEASE_KEYRING:-${repo_root}/packages/veldmuis-keyring/veldmuis.gpg}"
  local required_signed_tag="${VELDMUIS_REQUIRED_SIGNED_RELEASE_TAG:-}"
  local required_signed_tag_seen=0

  command -v gh >/dev/null 2>&1 || die "gh is required for --remote"
  command -v curl >/dev/null 2>&1 || die "curl is required for --remote"
  command -v gpgv >/dev/null 2>&1 || die "gpgv is required for --remote"
  [[ -r "${release_keyring}" ]] || die "Release keyring is unavailable: ${release_keyring}"

  temp_root="$(mktemp -d -t veldmuis-release-policy.XXXXXX)"
  trap 'rm -rf "${temp_root}"' EXIT

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
    if [[ -n "${required_signed_tag}" && "${release_tag}" == "${required_signed_tag}" ]]; then
      required_signed_tag_seen=1
    fi
    is_valid_release_tag "${release_tag}" || die "Unsupported GitHub release tag: ${release_tag}"
    git -C "${repo_root}" rev-parse --verify "refs/tags/${release_tag}" >/dev/null 2>&1 || \
      die "GitHub release has no matching local tag: ${release_tag}"

    tag_sha="$(git -C "${repo_root}" rev-list -n 1 "${release_tag}")"
    release_asset_urls="$(gh release view "${release_tag}" --json assets --jq '.assets[].url')"
    signature_url="$(select_release_signature_url "${release_asset_urls}")"
    manifest_url="$(
      select_release_manifest_url "${release_asset_urls}" "${signature_url}"
    )" || die "GitHub release signature has no matching manifest asset: ${release_tag}"
    [[ -n "${manifest_url}" ]] || die "GitHub release has no manifest asset: ${release_tag}"

    manifest_path="${temp_root}/${release_tag}.manifest.txt"
    curl -fsSL -o "${manifest_path}" "${manifest_url}"
    if [[ -n "${signature_url}" ]]; then
      signature_path="${manifest_path}.sig"
      curl -fsSL -o "${signature_path}" "${signature_url}"
      gpgv --keyring "${release_keyring}" "${signature_path}" "${manifest_path}" >/dev/null 2>&1 || \
        die "Manifest signature is invalid for ${release_tag}."
    elif [[ -n "${required_signed_tag}" && "${release_tag}" == "${required_signed_tag}" ]]; then
      die "GitHub release has no required manifest signature asset: ${release_tag}"
    fi
    manifest_tag="$(awk -F= '$1 == "release_tag" { print $2; exit }' "${manifest_path}")"
    manifest_sha="$(awk -F= '$1 == "release_sha" { print $2; exit }' "${manifest_path}")"
    [[ "${manifest_tag}" == "${release_tag}" ]] || \
      die "Manifest tag mismatch for ${release_tag}: ${manifest_tag}"
    [[ "${manifest_sha}" == "${tag_sha}" ]] || \
      die "Manifest commit mismatch for ${release_tag}: ${manifest_sha}"
  done < <(gh release list --limit 100 --json tagName --jq '.[].tagName')

  if [[ -n "${required_signed_tag}" && "${required_signed_tag_seen}" -ne 1 ]]; then
    die "Required signed release was not returned by the release listing: ${required_signed_tag}"
  fi

  if [[ -n "${network_channel_url}" ]]; then
    [[ "${network_channel_url}" =~ ^https:// ]] || \
      die "VELDMUIS_NETWORK_CHANNEL_URL must use HTTPS: ${network_channel_url}"
    channel_body="$(curl -fsSL "${network_channel_url}")" || \
      die "Network release channel is not reachable: ${network_channel_url}"
    grep -qF '"installer": "network"' <<<"${channel_body}" || \
      die "Network release channel does not identify the network installer."
    if [[ -n "${required_signed_tag}" ]]; then
      grep -qF "\"release_tag\": \"${required_signed_tag}\"" <<<"${channel_body}" || \
        die "Network release channel does not point to ${required_signed_tag}."
    fi
  fi

  if [[ -n "${network_manifest_url}" || -n "${network_signature_url}" ]]; then
    [[ "${network_manifest_url}" =~ ^https:// ]] || \
      die "VELDMUIS_NETWORK_MANIFEST_URL must use HTTPS."
    [[ "${network_signature_url}" =~ ^https:// ]] || \
      die "VELDMUIS_NETWORK_MANIFEST_SIGNATURE_URL must use HTTPS."
    manifest_path="${temp_root}/network.manifest.txt"
    signature_path="${manifest_path}.sig"
    curl -fsSL -o "${manifest_path}" "${network_manifest_url}"
    curl -fsSL -o "${signature_path}" "${network_signature_url}"
    gpgv --keyring "${release_keyring}" "${signature_path}" "${manifest_path}" >/dev/null 2>&1 || \
      die "Network channel manifest signature is invalid."
  fi

  log "GitHub releases and manifests follow the release policy"
  rm -rf "${temp_root}"
  trap - EXIT
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
  check_release_asset_selection
  check_workflow_source
  check_workflow_action_pins
  check_offline_release_workflow_source
  check_repository_signature_policy
  check_release_metadata_source
  check_private_reporting_source
  check_branding_source
  check_package_suffix_source

  if ((check_remote)); then
    check_remote_releases
  fi
}

main "$@"
