#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${CI_REPO_ROOT:-$(cd "${script_dir}/.." && pwd)}"
repos_root="${REPOS_ROOT:-${repo_root}/repos}"
package_dir="${VELDMUIS_AUR_PACKAGE_DIR:-${repo_root}/artifacts/aur-packages/current}"
aur_manifest_path="${VELDMUIS_AUR_MANIFEST:-${package_dir}/veldmuis-aur-packages.manifest.txt}"
manifest_name="${KNOWN_GOOD_NVIDIA_MANIFEST_NAME:-veldmuis-known-good-nvidia-580xx.manifest.txt}"
aur_manifest_name="${R2_AUR_MANIFEST_NAME:-veldmuis-aur-packages.manifest.txt}"
prefix="${KNOWN_GOOD_NVIDIA_PREFIX:-_known-good/nvidia-580xx/current}"
arch="${VELDMUIS_ARCH:-x86_64}"
extra_repo="${VELDMUIS_EXTRA_REPO:-veldmuis-extra}"
signed_package_dir="${VELDMUIS_SIGNED_PACKAGE_DIR:-${repos_root}/${extra_repo}/os/${arch}}"
bucket="${CF_R2_PACKAGE_BUCKET:-}"
account_id="${CF_R2_ACCOUNT_ID:-}"
endpoint="${CF_R2_ENDPOINT_URL:-}"
cache_control="${KNOWN_GOOD_CACHE_CONTROL:-no-store, max-age=0, must-revalidate}"
package_keyring="${VELDMUIS_PACKAGE_KEYRING:-${repo_root}/packages/veldmuis-keyring/veldmuis.gpg}"
key_fpr_file="${VELDMUIS_KEY_FPR_FILE:-${HOME}/.local/share/veldmuis/keyring-private/current-signing-key.fpr}"
nvidia_package_set="${VELDMUIS_NVIDIA_580XX_PACKAGE_SET:-${repo_root}/packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh}"

if [[ -n "${KNOWN_GOOD_STAGE_DIR:-}" ]]; then
  stage_dir="${KNOWN_GOOD_STAGE_DIR}"
elif [[ -n "${KNOWN_GOOD_BUILD_ROOT:-}" ]]; then
  # Keep the old override usable while making the repository cache layout the
  # default shared between the Arch builder and the host publisher.
  stage_dir="${KNOWN_GOOD_BUILD_ROOT}/stage"
else
  stage_dir="${repos_root}/known-good-nvidia-580xx"
fi

[[ -r "${nvidia_package_set}" ]] || {
  printf '[publish-known-good-nvidia-packages] ERROR: NVIDIA package set not readable: %s\n' "${nvidia_package_set}" >&2
  exit 1
}
# shellcheck source=packages/veldmuis-nvidia-legacy/nvidia-580xx-package-set.sh
. "${nvidia_package_set}"

expected_packages=("${veldmuis_nvidia_580xx_repository_packages[@]}")
operation="publish"
signing_fingerprint=""
fallback_skip=0
source_aur_manifest_name=""
source_aur_manifest_sha256=""

log() {
  printf '[publish-known-good-nvidia-packages] %s\n' "$*"
}

die() {
  printf '[publish-known-good-nvidia-packages] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage:
  publish-known-good-nvidia-packages.sh
  publish-known-good-nvidia-packages.sh --prepare-only
  publish-known-good-nvidia-packages.sh --publish-only

--prepare-only creates and validates the known-good stage without AWS access.
--publish-only validates an existing stage and uploads it without a private key.
EOF
}

parse_args() {
  local arg

  while (($# > 0)); do
    arg="$1"
    shift
    case "${arg}" in
      --prepare-only)
        [[ "${operation}" == publish ]] || die "Only one operation may be selected"
        operation="prepare"
        ;;
      --publish-only)
        [[ "${operation}" == publish ]] || die "Only one operation may be selected"
        operation="publish-only"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: ${arg}"
        ;;
    esac
  done
}

configure_credentials() {
  if [[ -z "${AWS_ACCESS_KEY_ID:-}" && -n "${CF_R2_PACKAGE_ACCESS_KEY_ID:-}" ]]; then
    export AWS_ACCESS_KEY_ID="${CF_R2_PACKAGE_ACCESS_KEY_ID}"
  fi

  if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" && -n "${CF_R2_PACKAGE_SECRET_ACCESS_KEY:-}" ]]; then
    export AWS_SECRET_ACCESS_KEY="${CF_R2_PACKAGE_SECRET_ACCESS_KEY}"
  fi

  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"

  [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || die "Missing AWS_ACCESS_KEY_ID or CF_R2_PACKAGE_ACCESS_KEY_ID"
  [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] || die "Missing AWS_SECRET_ACCESS_KEY or CF_R2_PACKAGE_SECRET_ACCESS_KEY"
}

configure_endpoint() {
  [[ -n "${bucket}" ]] || die "Missing CF_R2_PACKAGE_BUCKET"
  [[ "${bucket}" != "veldmuis-releases" ]] || die "Refusing to use ISO bucket ${bucket}"

  if [[ -z "${endpoint}" ]]; then
    [[ -n "${account_id}" ]] || die "Missing CF_R2_ACCOUNT_ID or CF_R2_ENDPOINT_URL"
    endpoint="https://${account_id}.r2.cloudflarestorage.com"
  fi

  prefix="${prefix#/}"
  prefix="${prefix%/}"
  [[ -n "${prefix}" ]] || die "Known-good prefix resolves to an empty path"
}

manifest_value() {
  local manifest_file="$1"
  local key="$2"

  awk -F '=' -v key="${key}" '$1 == key { print $2; found = 1; exit } END { exit !found }' \
    "${manifest_file}" 2>/dev/null || true
}

is_fallback_manifest() {
  local manifest_file="$1"

  [[ "$(manifest_value "${manifest_file}" fallback_used)" == "true" ]]
}

safe_file_name() {
  local file_name="$1"

  [[ -n "${file_name}" ]] || return 1
  [[ "${file_name}" != */* ]] || return 1
  [[ "${file_name}" != .* ]] || return 1
}

read_signing_fingerprint() {
  local fingerprint

  [[ -r "${key_fpr_file}" ]] || die "Signing fingerprint marker is missing: ${key_fpr_file}"
  fingerprint="$(tr -d '[:space:]' < "${key_fpr_file}")"
  [[ "${fingerprint}" =~ ^[0-9A-Fa-f]{40}$ ]] || \
    die "Invalid signing fingerprint: ${fingerprint}"
  gpg --batch --list-secret-keys "${fingerprint}" >/dev/null 2>&1 || \
    die "Signing key is unavailable: ${fingerprint}"
  signing_fingerprint="${fingerprint}"
}

find_package() {
  local package_name="$1"
  local -a matches=()

  mapfile -t matches < <(
    find "${signed_package_dir}" -maxdepth 1 -type f \
      -name "${package_name}-*.pkg.tar.zst" \
      ! -name '*-debug-*.pkg.tar.zst' \
      | sort -V
  )

  ((${#matches[@]} == 1)) || die "Expected exactly one artifact for ${package_name}, found ${#matches[@]}"
  printf '%s' "${matches[0]}"
}

copy_known_good_files() {
  local package_name package_path

  rm -rf "${stage_dir}"
  mkdir -p "${stage_dir}"

  [[ -r "${aur_manifest_path}" ]] || die "AUR manifest not readable: ${aur_manifest_path}"
  source_aur_manifest_sha256="$(sha256sum "${aur_manifest_path}" | awk '{print $1}')"
  source_aur_manifest_name="veldmuis-aur-packages-${source_aur_manifest_sha256}.manifest.txt"
  cp -f "${aur_manifest_path}" "${stage_dir}/${source_aur_manifest_name}"

  for package_name in "${expected_packages[@]}"; do
    package_path="$(find_package "${package_name}")"
    cp -f "${package_path}" "${stage_dir}/"
    [[ -f "${package_path}.sig" ]] || die "Missing package signature: ${package_path}.sig"
    cp -f "${package_path}.sig" "${stage_dir}/"
  done
}

render_manifest() {
  local source_commit="unknown"

  source_commit="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  [[ -n "${source_aur_manifest_name}" && -n "${source_aur_manifest_sha256}" ]] || \
    die "Source AUR manifest identity was not prepared"

  {
    printf 'schema_version=2\n'
    printf 'created_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'source_commit=%s\n' "${source_commit}"
    printf 'cache_prefix=%s\n' "${prefix}"
    printf 'source_aur_manifest=%s\n' "${source_aur_manifest_name}"
    printf 'source_aur_manifest_sha256=%s\n' "${source_aur_manifest_sha256}"
    printf 'signing_fingerprint=%s\n' "${signing_fingerprint}"
    printf 'fallback_used=false\n'
    printf '\n[package_bases]\n'
    awk '
      /^\[package_bases\]$/ {
        in_package_bases = 1
        next
      }
      /^\[/ {
        in_package_bases = 0
        next
      }
      in_package_bases && NF >= 2 && $1 !~ /^#/ {
        print
      }
    ' "${stage_dir}/${source_aur_manifest_name}"
    printf '\n[source_inputs]\n'
    awk '
      /^\[source_inputs\]$/ {
        in_source_inputs = 1
        next
      }
      /^\[/ {
        in_source_inputs = 0
        next
      }
      in_source_inputs && NF >= 2 && $1 !~ /^#/ {
        print
      }
    ' "${stage_dir}/${source_aur_manifest_name}"
    printf '\n[package_files]\n'
    find "${stage_dir}" -maxdepth 1 -type f \
      -name '*.pkg.tar.zst' \
      -printf '%f\n' \
      | sort -V \
      | while IFS= read -r file_name; do
          sha256sum "${stage_dir}/${file_name}" | awk -v file_name="${file_name}" '{print $1 "\t" file_name}'
        done
    printf '\n[signature_files]\n'
    find "${stage_dir}" -maxdepth 1 -type f \
      -name '*.pkg.tar.zst.sig' \
      -printf '%f\n' \
      | sort -V \
      | while IFS= read -r file_name; do
          sha256sum "${stage_dir}/${file_name}" | awk -v file_name="${file_name}" '{print $1 "\t" file_name}'
        done
  } > "${stage_dir}/${manifest_name}"
}

sign_manifest() {
  gpg --batch --yes --local-user "${signing_fingerprint}" \
    --output "${stage_dir}/${manifest_name}.sig" \
    --detach-sign "${stage_dir}/${manifest_name}"
}

parse_package_files() {
  local manifest_file="$1"

  awk '
    /^\[package_files\]$/ {
      in_package_files = 1
      next
    }
    /^\[/ {
      in_package_files = 0
      next
    }
    in_package_files && NF >= 2 && $1 !~ /^#/ {
      print $1 " " $2
    }
  ' "${manifest_file}"
}

parse_signature_files() {
  local manifest_file="$1"

  awk '
    /^\[signature_files\]$/ {
      in_signature_files = 1
      next
    }
    /^\[/ {
      in_signature_files = 0
      next
    }
    in_signature_files && NF >= 2 && $1 !~ /^#/ {
      print $1 " " $2
    }
  ' "${manifest_file}"
}

verify_package_entries() {
  local manifest_file="$1"
  local expected_hash file_name output_path actual_hash
  local package_count=0
  local signature_count=0
  local package_name found

  while read -r expected_hash file_name; do
    [[ "${expected_hash}" =~ ^[0-9a-fA-F]{64}$ ]] || die "Invalid package checksum in known-good manifest"
    safe_file_name "${file_name}" || die "Unsafe package file name in known-good manifest: ${file_name}"
    [[ "${file_name}" == *.pkg.tar.zst ]] || die "Invalid package file name in known-good manifest: ${file_name}"
    output_path="${stage_dir}/${file_name}"
    [[ -f "${output_path}" ]] || die "Known-good package is missing: ${file_name}"
    actual_hash="$(sha256sum "${output_path}" | awk '{print $1}')"
    [[ "${actual_hash}" == "${expected_hash}" ]] || \
      die "Checksum mismatch for ${file_name}: expected ${expected_hash}, got ${actual_hash}"
    package_count=$((package_count + 1))
  done < <(parse_package_files "${manifest_file}")

  while read -r expected_hash file_name; do
    [[ "${expected_hash}" =~ ^[0-9a-fA-F]{64}$ ]] || die "Invalid signature checksum in known-good manifest"
    safe_file_name "${file_name}" || die "Unsafe signature file name in known-good manifest: ${file_name}"
    [[ "${file_name}" == *.pkg.tar.zst.sig ]] || die "Invalid signature file name in known-good manifest: ${file_name}"
    output_path="${stage_dir}/${file_name}"
    [[ -f "${output_path}" ]] || die "Known-good package signature is missing: ${file_name}"
    actual_hash="$(sha256sum "${output_path}" | awk '{print $1}')"
    [[ "${actual_hash}" == "${expected_hash}" ]] || \
      die "Checksum mismatch for ${file_name}: expected ${expected_hash}, got ${actual_hash}"
    signature_count=$((signature_count + 1))
  done < <(parse_signature_files "${manifest_file}")

  ((package_count > 0)) || die "Known-good manifest has no package files"
  ((signature_count == package_count)) || die "Known-good manifest package/signature entries do not match"

  for package_name in "${expected_packages[@]}"; do
    found=0
    while read -r _ file_name; do
      if [[ "${file_name}" == "${package_name}-"*.pkg.tar.zst ]]; then
        found=1
        break
      fi
    done < <(parse_package_files "${manifest_file}")
    ((found == 1)) || die "Known-good manifest is missing package: ${package_name}"
  done
}

verify_package_signatures() {
  local expected_hash file_name package_path signature_path

  while read -r expected_hash file_name; do
    [[ -n "${expected_hash}" ]] || die "Known-good package checksum is missing"
    package_path="${stage_dir}/${file_name}"
    signature_path="${package_path}.sig"
    [[ -r "${signature_path}" ]] || die "Known-good package signature missing: ${signature_path}"
    gpgv --keyring "${package_keyring}" "${signature_path}" "${package_path}" >/dev/null 2>&1 || \
      die "Known-good package signature is invalid: ${file_name}"
  done < <(parse_package_files "${stage_dir}/${manifest_name}")
}

verify_local_stage() {
  local manifest_path="${stage_dir}/${manifest_name}"
  local signature_path="${manifest_path}.sig"
  local source_aur_manifest source_aur_manifest_path expected_source_hash actual_source_hash
  local stage_signing_fingerprint

  [[ -r "${manifest_path}" ]] || die "Known-good manifest is missing: ${manifest_path}"
  [[ -r "${signature_path}" ]] || die "Known-good manifest signature is missing: ${signature_path}"
  gpgv --keyring "${package_keyring}" "${signature_path}" "${manifest_path}" >/dev/null 2>&1 || \
    die "Known-good manifest signature is invalid"

  [[ "$(manifest_value "${manifest_path}" schema_version)" == "2" ]] || \
    die "Known-good manifest schema_version must be 2"

  source_aur_manifest="$(manifest_value "${manifest_path}" source_aur_manifest)"
  safe_file_name "${source_aur_manifest}" || die "Unsafe source_aur_manifest in known-good manifest: ${source_aur_manifest}"
  source_aur_manifest_path="${stage_dir}/${source_aur_manifest}"
  [[ -r "${source_aur_manifest_path}" ]] || die "Source AUR manifest is missing: ${source_aur_manifest}"

  expected_source_hash="$(manifest_value "${manifest_path}" source_aur_manifest_sha256)"
  [[ "${expected_source_hash}" =~ ^[0-9a-fA-F]{64}$ ]] || \
    die "Known-good manifest has an invalid source AUR manifest checksum"
  actual_source_hash="$(sha256sum "${source_aur_manifest_path}" | awk '{print $1}')"
  [[ "${actual_source_hash}" == "${expected_source_hash}" ]] || \
    die "Source AUR manifest checksum does not match known-good manifest"

  stage_signing_fingerprint="$(manifest_value "${manifest_path}" signing_fingerprint)"
  [[ "${stage_signing_fingerprint}" =~ ^[0-9A-Fa-f]{40}$ ]] || \
    die "Known-good manifest is missing signing_fingerprint"

  verify_package_entries "${manifest_path}"
  verify_package_signatures
}

upload_known_good() {
  local target="s3://${bucket}/${prefix}"

  log "Publishing known-good NVIDIA package set to ${target}"

  # Keep mutable metadata out of the bulk sync. Payloads and the source AUR
  # manifest become available first; the manifest and its signature are the
  # final two objects written so readers never trust an unverified manifest.
  aws s3 cp "${stage_dir}" "${target}" \
    --recursive \
    --exclude "${manifest_name}" \
    --exclude "${manifest_name}.sig" \
    --cache-control "${cache_control}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors
  aws s3 sync "${stage_dir}" "${target}" \
    --exclude "${manifest_name}" \
    --exclude "${manifest_name}.sig" \
    --cache-control "${cache_control}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors
  aws s3 cp "${stage_dir}/${manifest_name}" "${target}/${manifest_name}" \
    --cache-control "${cache_control}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors
  aws s3 cp "${stage_dir}/${manifest_name}.sig" "${target}/${manifest_name}.sig" \
    --cache-control "${cache_control}" \
    --endpoint-url "${endpoint}" \
    --only-show-errors
}

verify_known_good() {
  local file_name

  while IFS= read -r file_name; do
    log "Verifying known-good object: ${prefix}/${file_name}"
    aws s3api head-object \
      --bucket "${bucket}" \
      --key "${prefix}/${file_name}" \
      --endpoint-url "${endpoint}" \
      >/dev/null
  done < <(find "${stage_dir}" -maxdepth 1 -type f -printf '%f\n' | sort)
}

prepare_known_good() {
  [[ -d "${package_dir}" ]] || die "Package artifact directory not found: ${package_dir}"
  [[ -d "${signed_package_dir}" ]] || die "Signed package directory not found: ${signed_package_dir}"
  [[ -r "${aur_manifest_path}" ]] || die "AUR manifest not readable: ${aur_manifest_path}"

  if is_fallback_manifest "${aur_manifest_path}"; then
    log "Skipping known-good update because current package set came from fallback"
    fallback_skip=1
    return 0
  fi

  read_signing_fingerprint
  copy_known_good_files
  render_manifest
  sign_manifest
  verify_local_stage
}

publish_prepared_known_good() {
  local prepared_manifest="${stage_dir}/${manifest_name}"
  local stage_aur_manifest=""

  [[ -d "${stage_dir}" ]] || die "Known-good stage directory not found: ${stage_dir}"

  # Support the pre-content-addressed prepared-stage fallback marker as well
  # as the current manifest-driven source filename.
  if [[ -r "${stage_dir}/${aur_manifest_name}" ]] && \
    is_fallback_manifest "${stage_dir}/${aur_manifest_name}"; then
    log "Skipping known-good update because prepared package set came from fallback"
    fallback_skip=1
    return 0
  fi

  [[ -r "${prepared_manifest}" ]] || die "Prepared known-good manifest is missing: ${prepared_manifest}"
  stage_aur_manifest="$(manifest_value "${prepared_manifest}" source_aur_manifest)"
  safe_file_name "${stage_aur_manifest}" || \
    die "Unsafe source_aur_manifest in prepared known-good manifest: ${stage_aur_manifest}"
  stage_aur_manifest="${stage_dir}/${stage_aur_manifest}"
  [[ -r "${stage_aur_manifest}" ]] || die "Prepared source AUR manifest is missing: ${stage_aur_manifest}"

  if is_fallback_manifest "${stage_aur_manifest}"; then
    log "Skipping known-good update because prepared package set came from fallback"
    fallback_skip=1
    return 0
  fi

  require_cmd aws
  verify_local_stage
  configure_credentials
  configure_endpoint
  upload_known_good
  verify_known_good
}

main() {
  parse_args "$@"

  require_cmd awk
  require_cmd date
  require_cmd find
  require_cmd sha256sum
  require_cmd sort
  require_cmd tr
  require_cmd gpgv
  [[ -r "${package_keyring}" ]] || die "Package keyring not readable: ${package_keyring}"

  case "${operation}" in
    prepare)
      require_cmd gpg
      require_cmd git
      prepare_known_good
      if ((fallback_skip == 1)); then
        exit 0
      fi
      log "Prepared and validated known-good NVIDIA package stage: ${stage_dir}"
      ;;
    publish-only)
      if [[ -r "${aur_manifest_path}" ]] && is_fallback_manifest "${aur_manifest_path}"; then
        log "Skipping known-good update because current package set came from fallback"
        exit 0
      fi
      publish_prepared_known_good
      if ((fallback_skip == 1)); then
        exit 0
      fi
      log "Published known-good NVIDIA package set"
      ;;
    publish)
      require_cmd aws
      require_cmd gpg
      require_cmd git
      prepare_known_good
      if ((fallback_skip == 1)); then
        exit 0
      fi
      configure_credentials
      configure_endpoint
      upload_known_good
      verify_known_good
      log "Published known-good NVIDIA package set"
      ;;
  esac
}

main "$@"
