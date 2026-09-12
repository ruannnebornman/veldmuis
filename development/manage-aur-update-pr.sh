#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
lock_file="${VELDMUIS_AUR_LOCK_FILE:-${repo_root}/development/aur-packages.lock}"
candidate_lock="${VELDMUIS_AUR_CANDIDATE_LOCK:-}"
report_file="${VELDMUIS_AUR_UPDATE_REPORT:-}"
review_base_sha="${VELDMUIS_AUR_REVIEW_BASE_SHA:-}"
risk="${VELDMUIS_AUR_UPDATE_RISK:-high}"
group_name="${VELDMUIS_AUR_UPDATE_GROUP:-nvidia-580xx}"
branch_name="${VELDMUIS_AUR_UPDATE_BRANCH:-automation/aur-update/${group_name}}"
pr_title="${VELDMUIS_AUR_UPDATE_TITLE:-Update ${group_name} AUR inputs}"
labels="${VELDMUIS_AUR_UPDATE_LABELS:-}"
assignees="${VELDMUIS_AUR_UPDATE_ASSIGNEES:-}"

die() {
  printf '[manage-aur-update-pr] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  manage-aur-update-pr.sh

Environment:
  VELDMUIS_AUR_CANDIDATE_LOCK  Candidate lock file to publish in the PR branch.
  VELDMUIS_AUR_UPDATE_REPORT   Candidate evidence report.
  VELDMUIS_AUR_UPDATE_RISK     low or high.
  VELDMUIS_AUR_UPDATE_LABELS   Optional comma-separated labels for high-risk PRs.
  VELDMUIS_AUR_UPDATE_ASSIGNEES
                               Optional comma-separated assignees for high-risk PRs.
                               Labels and assignees are only applied to high-risk
                               PRs; low-risk sync PRs stay quiet.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

write_output() {
  local name="$1"
  local value="$2"

  [[ -n "${GITHUB_OUTPUT:-}" ]] || return 0
  printf '%s=%s\n' "${name}" "${value}" >>"${GITHUB_OUTPUT}"
}

remote_branch_exists() {
  git ls-remote --exit-code --heads origin "${branch_name}" >/dev/null 2>&1
}

find_open_pr() {
  gh pr list \
    --state open \
    --base main \
    --head "${branch_name}" \
    --json number \
    --jq '.[0].number // empty'
}

prepare_branch() {
  git fetch --quiet origin refs/heads/main:refs/remotes/origin/main
  if remote_branch_exists; then
    git fetch --quiet origin "refs/heads/${branch_name}:refs/remotes/origin/${branch_name}"
    git checkout --quiet -B "${branch_name}" "origin/${branch_name}"
    git merge --no-edit --quiet origin/main
  else
    git checkout --quiet -B "${branch_name}" origin/main
  fi
}

write_pr_body() {
  local body_file="$1"

  {
    cat "${report_file}"
    printf '\n## Review Gate\n\n'
    if [[ "${risk}" == high ]]; then
      printf 'This candidate is high risk. Do not merge until the AUR diff, package scan, and build evidence have been reviewed.\n'
      printf '\nNo routine package refresh will publish these refs until this PR reaches main.\n'
    else
      printf 'Routine low-risk sync. The scheduled package refresh publishes these refs without waiting for this PR; merging aligns the lock baseline with the published manifest.\n'
    fi
  } >"${body_file}"
}

apply_pr_attention() {
  local pr_number="$1"
  local label trimmed_labels trimmed_assignees
  local -a label_list=()

  # Quiet by design for low-risk sync PRs. High-risk PRs get labels and
  # assignees so the maintainer is notified through normal hosting alerts.
  # Reviewer requests and ready-state changes are intentionally left to the
  # maintainer through the hosting interface.
  [[ "${risk}" == high ]] || return 0

  trimmed_labels="$(printf '%s' "${labels}" | tr -d '[:space:]')"
  if [[ -n "${trimmed_labels}" ]]; then
    IFS=',' read -r -a label_list <<< "${trimmed_labels}"
    for label in "${label_list[@]}"; do
      [[ -n "${label}" ]] || continue
      if ! gh pr edit "${pr_number}" --add-label "${label}" >/dev/null; then
        printf '[manage-aur-update-pr] WARNING: Unable to apply label %s to #%s\n' "${label}" "${pr_number}" >&2
      fi
    done
  fi

  trimmed_assignees="$(printf '%s' "${assignees}" | tr -d '[:space:]')"
  if [[ -n "${trimmed_assignees}" ]]; then
    if ! gh pr edit "${pr_number}" --add-assignee "${trimmed_assignees}" >/dev/null; then
      printf '[manage-aur-update-pr] WARNING: Unable to assign #%s to %s\n' "${pr_number}" "${trimmed_assignees}" >&2
    fi
  fi
}

main() {
  local pr_number=""
  local body_file=""
  local lock_relative=""
  local unexpected_files=""
  local current_main_sha=""
  local is_draft=""

  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
  esac

  require_cmd gh
  require_cmd git
  [[ -n "${candidate_lock}" && -r "${candidate_lock}" ]] || \
    die "Candidate lock file is required"
  [[ -n "${report_file}" && -r "${report_file}" ]] || \
    die "Candidate report is required"
  [[ -z "${review_base_sha}" || "${review_base_sha}" =~ ^[0-9a-f]{40}$ ]] || \
    die "Review base SHA must be a 40-character commit SHA"
  [[ "${risk}" == low || "${risk}" == high ]] || die "Unsupported risk: ${risk}"

  gh auth setup-git
  pr_number="$(find_open_pr)"
  prepare_branch
  if [[ -n "${review_base_sha}" ]]; then
    current_main_sha="$(git rev-parse refs/remotes/origin/main)"
    [[ "${current_main_sha}" == "${review_base_sha}" ]] || \
      die "main changed during AUR review; candidate evidence is stale"
  fi
  lock_relative="${lock_file#"${repo_root}"/}"
  unexpected_files="$(git diff --name-only origin/main...HEAD | awk -v lock_file="${lock_relative}" '$0 != lock_file')"
  [[ -z "${unexpected_files}" ]] || \
    die "Update branch contains unexpected files: ${unexpected_files}"
  install -m644 "${candidate_lock}" "${lock_file}"

  if git diff --quiet -- "${lock_file}"; then
    printf '[manage-aur-update-pr] Candidate lock is already represented by the update branch.\n'
  else
    git config user.name 'Veldmuis update process'
    git config user.email 'veldmuis@veldmuislinux.org'
    git add -- "${lock_file}"
    git commit -m 'Update AUR input refs'
    git push --set-upstream origin "${branch_name}"
  fi

  body_file="$(mktemp)"
  trap 'rm -f -- "${body_file}"' EXIT
  write_pr_body "${body_file}"

  if [[ -n "${pr_number}" ]]; then
    gh pr comment "${pr_number}" --body-file "${report_file}" >/dev/null
    gh pr edit "${pr_number}" --title "${pr_title}" --body-file "${body_file}" >/dev/null
    apply_pr_attention "${pr_number}"
    if [[ "${risk}" == high ]]; then
      is_draft="$(gh pr view "${pr_number}" --json isDraft --jq '.isDraft')"
      if [[ "${is_draft}" != true ]]; then
        gh pr ready "${pr_number}" --undo >/dev/null
      fi
    fi
  else
    local pr_url=""
    local -a create_args=(
      --base main
      --head "${branch_name}"
      --title "${pr_title}"
      --body-file "${body_file}"
    )
    if [[ "${risk}" == high ]]; then
      create_args+=(--draft)
    fi
    pr_url="$(gh pr create "${create_args[@]}")"
    pr_number="$(gh pr view "${pr_url}" --json number --jq '.number')"
    apply_pr_attention "${pr_number}"
  fi

  gh workflow run repository-checks.yml \
    --ref "${branch_name}" \
    --field "ref=${branch_name}" \
    >/dev/null

  if [[ "${risk}" == high ]]; then
    printf '::warning::High-risk AUR update requires review: #%s\n' "${pr_number}"
    printf '[manage-aur-update-pr] High-risk PR requires review: #%s\n' "${pr_number}"
  else
    printf '[manage-aur-update-pr] Low-risk lock sync PR is ready: #%s\n' "${pr_number}"
  fi

  write_output pr_number "${pr_number}"
  write_output branch_name "${branch_name}"
  write_output risk "${risk}"
}

main "$@"
