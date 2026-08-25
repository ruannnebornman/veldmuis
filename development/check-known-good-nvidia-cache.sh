#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
temp_root="$(mktemp -d -t veldmuis-known-good-cache-check.XXXXXX)"

cleanup() {
  rm -rf -- "${temp_root}"
}
trap cleanup EXIT

for command_name in gpg gpgv sha256sum; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf '[check-known-good-nvidia-cache] ERROR: Missing required command: %s\n' \
      "${command_name}" >&2
    exit 1
  }
done

gnupg_home="${temp_root}/gnupg"
repos_root="${temp_root}/repos"
package_dir="${temp_root}/current"
signed_package_dir="${repos_root}/veldmuis-extra/os/x86_64"
stage_dir="${repos_root}/known-good-nvidia-580xx"
pristine_stage="${temp_root}/pristine-stage"
package_keyring="${temp_root}/veldmuis.gpg"
fingerprint_file="${temp_root}/current-signing-key.fpr"
fake_bin="${temp_root}/bin"
aws_log="${temp_root}/aws.log"
manifest_path="${package_dir}/veldmuis-aur-packages.manifest.txt"
restore_package_dir="${temp_root}/restored"
restore_work_root="${temp_root}/restore-work"
remote_source_dir="${temp_root}/remote-source"

mkdir -p "${gnupg_home}" "${package_dir}" "${signed_package_dir}" "${fake_bin}"
chmod 700 "${gnupg_home}"

printf '%s\n' \
  '%no-protection' \
  'Key-Type: RSA' \
  'Key-Length: 2048' \
  'Name-Real: Known-good cache test' \
  'Name-Email: known-good-cache-test@example.invalid' \
  'Expire-Date: 0' \
  '%commit' \
  > "${temp_root}/key-generation.conf"
GNUPGHOME="${gnupg_home}" gpg --batch --generate-key "${temp_root}/key-generation.conf" >/dev/null 2>&1
fingerprint="$(GNUPGHOME="${gnupg_home}" gpg --batch --with-colons --list-keys | \
  awk -F: '$1 == "fpr" {print $10; exit}')"
[[ "${fingerprint}" =~ ^[0-9A-Fa-f]{40}$ ]] || {
  printf '[check-known-good-nvidia-cache] ERROR: Failed to create an ephemeral key\n' >&2
  exit 1
}
GNUPGHOME="${gnupg_home}" gpg --batch --export "${fingerprint}" > "${package_keyring}"
printf '%s\n' "${fingerprint}" > "${fingerprint_file}"

cat > "${fake_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${AWS_LOG}"
EOF
chmod +x "${fake_bin}/aws"

cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

url=""
output=""
while (($# > 0)); do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

source_path="${FAKE_SOURCE_ROOT}/${url##*/}"
[[ -n "${output}" && -r "${source_path}" ]] || exit 1
cp -f "${source_path}" "${output}"
EOF
chmod +x "${fake_bin}/curl"

package_names=(
  nvidia-580xx-dkms
  nvidia-580xx-utils
  opencl-nvidia-580xx
  lib32-nvidia-580xx-utils
  lib32-opencl-nvidia-580xx
  nvidia-580xx-settings
  libxnvctrl-580xx
)

{
  printf 'built_at_utc=2026-01-01T00:00:00Z\n'
  printf 'fallback_used=false\n'
  printf '\n[package_bases]\n'
  printf 'nvidia-580xx-utils deadbeef\n'
  printf 'lib32-nvidia-580xx-utils deadbeef\n'
  printf 'nvidia-580xx-settings deadbeef\n'
  printf '\n[source_inputs]\n'
  printf 'nvidia-580xx-utils PKGBUILD deadbeef\n'
} > "${manifest_path}"

for package_name in "${package_names[@]}"; do
  package_path="${signed_package_dir}/${package_name}-1.0-1-x86_64.pkg.tar.zst"
  printf 'signed fixture for %s\n' "${package_name}" > "${package_path}"
  GNUPGHOME="${gnupg_home}" gpg --batch --yes --local-user "${fingerprint}" \
    --output "${package_path}.sig" --detach-sign "${package_path}"
done

publisher_env=(
  "REPOS_ROOT=${repos_root}"
  "VELDMUIS_AUR_PACKAGE_DIR=${package_dir}"
  "VELDMUIS_AUR_MANIFEST=${manifest_path}"
  "VELDMUIS_SIGNED_PACKAGE_DIR=${signed_package_dir}"
  "KNOWN_GOOD_STAGE_DIR=${stage_dir}"
  "VELDMUIS_PACKAGE_KEYRING=${package_keyring}"
  "VELDMUIS_KEY_FPR_FILE=${fingerprint_file}"
  "GNUPGHOME=${gnupg_home}"
)

run_prepare() {
  env "${publisher_env[@]}" \
    "${repo_root}/development/publish-known-good-nvidia-packages.sh" --prepare-only
}

run_publish() {
  env "${publisher_env[@]}" \
    "PATH=${fake_bin}:${PATH}" \
    "AWS_LOG=${aws_log}" \
    AWS_ACCESS_KEY_ID=fixture-access \
    AWS_SECRET_ACCESS_KEY=fixture-secret \
    CF_R2_PACKAGE_BUCKET=fixture-packages \
    CF_R2_ENDPOINT_URL=https://objects.example.invalid \
    "${repo_root}/development/publish-known-good-nvidia-packages.sh" --publish-only
}

run_restore() {
  env \
    "PATH=${fake_bin}:${PATH}" \
    "FAKE_SOURCE_ROOT=${stage_dir}" \
    "VELDMUIS_AUR_PACKAGE_DIR=${restore_package_dir}" \
    "VELDMUIS_AUR_MANIFEST=${restore_package_dir}/veldmuis-aur-packages.manifest.txt" \
    "VELDMUIS_KNOWN_GOOD_WORK_ROOT=${restore_work_root}" \
    VELDMUIS_KNOWN_GOOD_NVIDIA_URL=https://cache.example.invalid/_known-good/nvidia-580xx/current \
    "VELDMUIS_PACKAGE_KEYRING=${package_keyring}" \
    "${repo_root}/development/restore-known-good-nvidia-packages.sh"
}

expect_publish_failure() {
  local description="$1"
  shift
  local output

  if output=$("$@" 2>&1); then
    printf '[check-known-good-nvidia-cache] ERROR: %s was accepted\n' "${description}" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  fi
}

reset_stage() {
  rm -rf "${stage_dir}"
  cp -a "${pristine_stage}" "${stage_dir}"
}

run_prepare >/dev/null
cp -a "${stage_dir}" "${pristine_stage}"
known_good_manifest="${stage_dir}/veldmuis-known-good-nvidia-580xx.manifest.txt"
source_manifest_name="$(awk -F= '$1 == "source_aur_manifest" {print $2; exit}' "${known_good_manifest}")"
source_manifest_hash="$(awk -F= '$1 == "source_aur_manifest_sha256" {print $2; exit}' "${known_good_manifest}")"
known_good_manifest_hash="$(sha256sum "${known_good_manifest}" | awk '{print $1}')"
[[ "${source_manifest_name}" == "veldmuis-aur-packages-${source_manifest_hash}.manifest.txt" ]] || {
  printf '[check-known-good-nvidia-cache] ERROR: Source AUR manifest is not content-addressed\n' >&2
  exit 1
}
[[ "$(sha256sum "${stage_dir}/${source_manifest_name}" | awk '{print $1}')" == "${source_manifest_hash}" ]] || {
  printf '[check-known-good-nvidia-cache] ERROR: Source AUR manifest filename hash does not match content\n' >&2
  exit 1
}
mkdir -p "${remote_source_dir}"
cp -f "${stage_dir}/${source_manifest_name}" "${remote_source_dir}/${source_manifest_name}"
run_restore >/dev/null
restored_manifest="${restore_package_dir}/veldmuis-aur-packages.manifest.txt"
grep -q '^fallback_used=true$' "${restored_manifest}"
grep -q '^known_good_manifest_url=https://cache.example.invalid/_known-good/nvidia-580xx/current/veldmuis-known-good-nvidia-580xx.manifest.txt$' \
  "${restored_manifest}"
grep -q "^known_good_manifest_sha256=${known_good_manifest_hash}$" "${restored_manifest}"
run_publish >/dev/null

cp -f "${manifest_path}" "${temp_root}/non-fallback-aur-manifest.txt"
printf 'fallback_used=true\n' > "${manifest_path}"
rm -rf "${stage_dir}"
: > "${aws_log}"
run_publish >/dev/null
[[ ! -s "${aws_log}" ]] || {
  printf '[check-known-good-nvidia-cache] ERROR: Current fallback publish-only path invoked AWS\n' >&2
  exit 1
}
[[ ! -d "${stage_dir}" ]] || {
  printf '[check-known-good-nvidia-cache] ERROR: Current fallback publish-only path recreated the stage\n' >&2
  exit 1
}
cp -f "${temp_root}/non-fallback-aur-manifest.txt" "${manifest_path}"

reset_stage
source_manifest_path="${stage_dir}/${source_manifest_name}"
awk '$0 == "fallback_used=false" {$0 = "fallback_used=true"} {print}' \
  "${source_manifest_path}" > "${source_manifest_path}.tmp"
mv -f "${source_manifest_path}.tmp" "${source_manifest_path}"
: > "${aws_log}"
run_publish >/dev/null
[[ ! -s "${aws_log}" ]] || {
  printf '[check-known-good-nvidia-cache] ERROR: Prepared fallback publish-only path invoked AWS\n' >&2
  exit 1
}

reset_stage
printf 'modified\n' >> "${known_good_manifest}"
expect_publish_failure 'modified known-good manifest' run_publish

reset_stage
printf 'modified\n' >> "${stage_dir}/${source_manifest_name}"
expect_publish_failure 'modified source AUR manifest' run_publish

reset_stage
rm -f "${known_good_manifest}.sig"
expect_publish_failure 'missing known-good manifest signature' run_publish

reset_stage
mapfile -t package_paths < <(find "${stage_dir}" -maxdepth 1 -type f -name '*.pkg.tar.zst' | sort)
package_path="${package_paths[0]}"
package_file="${package_path##*/}"
printf 'modified payload\n' >> "${package_path}"
new_package_hash="$(sha256sum "${package_path}" | awk '{print $1}')"
manifest_file="${known_good_manifest}"
awk -v package_file="${package_file}" -v new_hash="${new_package_hash}" \
  '$2 == package_file {$1 = new_hash} {print}' "${manifest_file}" > "${manifest_file}.tmp"
mv -f "${manifest_file}.tmp" "${manifest_file}"
GNUPGHOME="${gnupg_home}" gpg --batch --yes --local-user "${fingerprint}" \
  --output "${manifest_file}.sig" --detach-sign "${manifest_file}"
payload_failure_output="$(run_publish 2>&1 || true)"
if [[ "${payload_failure_output}" != *"package signature is invalid"* ]]; then
  printf '[check-known-good-nvidia-cache] ERROR: Modified package payload did not fail package signature validation\n' >&2
  printf '%s\n' "${payload_failure_output}" >&2
  exit 1
fi

reset_stage
printf 'new source generation\n' >> "${manifest_path}"
run_prepare >/dev/null
new_known_good_manifest="${stage_dir}/veldmuis-known-good-nvidia-580xx.manifest.txt"
new_source_manifest_name="$(awk -F= '$1 == "source_aur_manifest" {print $2; exit}' "${new_known_good_manifest}")"
[[ "${new_source_manifest_name}" != "${source_manifest_name}" ]] || {
  printf '[check-known-good-nvidia-cache] ERROR: Source AUR manifest filename was reused across generations\n' >&2
  exit 1
}
cp -f "${stage_dir}/${new_source_manifest_name}" "${remote_source_dir}/${new_source_manifest_name}"
cmp -s "${pristine_stage}/${source_manifest_name}" "${remote_source_dir}/${source_manifest_name}" || {
  printf '[check-known-good-nvidia-cache] ERROR: Previous source AUR manifest was overwritten\n' >&2
  exit 1
}
: > "${aws_log}"
run_publish >/dev/null
if grep -q -- '--delete' "${aws_log}"; then
  printf '[check-known-good-nvidia-cache] ERROR: Cache publication still deletes obsolete objects\n' >&2
  exit 1
fi

printf '[check-known-good-nvidia-cache] Validated prepared cache, manifest signature, source binding, and package signatures.\n'
