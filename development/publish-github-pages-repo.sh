#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
repos_root="${repo_root}/repos"
build_root="${PAGES_BUILD_ROOT:-$HOME/.cache/veldmuis/github-pages}"
worktree_dir="${build_root}/gh-pages"
branch="${PAGES_BRANCH:-gh-pages}"
remote="${PAGES_REMOTE:-origin}"
pages_base="${PAGES_BASE_URL:-https://packages.veldmuislinux.org}"
cname="${PAGES_CNAME:-packages.veldmuislinux.org}"
git_author_name="${PAGES_GIT_AUTHOR_NAME:-}"
git_author_email="${PAGES_GIT_AUTHOR_EMAIL:-}"

log() {
  printf '[publish-github-pages-repo] %s\n' "$*"
}

die() {
  printf '[publish-github-pages-repo] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  if [[ -d "${worktree_dir}" ]]; then
    git -C "${repo_root}" worktree remove --force "${worktree_dir}" >/dev/null 2>&1 || true
  fi
}

prepare_worktree() {
  rm -rf "${worktree_dir}"
  mkdir -p "${build_root}"

  git -C "${repo_root}" fetch "${remote}" >/dev/null 2>&1 || true

  if git -C "${repo_root}" ls-remote --exit-code --heads "${remote}" "${branch}" >/dev/null 2>&1; then
    git -C "${repo_root}" worktree add -B "${branch}" "${worktree_dir}" "${remote}/${branch}" >/dev/null
  elif git -C "${repo_root}" show-ref --verify --quiet "refs/heads/${branch}"; then
    git -C "${repo_root}" worktree add -B "${branch}" "${worktree_dir}" "${branch}" >/dev/null
  else
    git -C "${repo_root}" worktree add --detach "${worktree_dir}" >/dev/null
    (
      cd "${worktree_dir}"
      git checkout --orphan "${branch}" >/dev/null 2>&1
    )
  fi
}

render_index() {
  cat > "${worktree_dir}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Veldmuis Package Repository</title>
  <style>
    body {
      margin: 0;
      padding: 48px 24px;
      background: #18100e;
      color: #f4e8dd;
      font: 16px/1.5 system-ui, sans-serif;
    }
    main { max-width: 760px; margin: 0 auto; }
    a { color: #e59c3f; }
    code {
      display: inline-block;
      background: #251714;
      border: 1px solid rgba(229,156,63,0.25);
      border-radius: 6px;
      padding: 2px 6px;
      color: #f4e8dd;
    }
  </style>
</head>
<body>
  <main>
    <h1>Veldmuis Package Repository</h1>
    <p>This branch publishes the pacman repository for Veldmuis Linux.</p>
    <p>Base URL: <a href="${pages_base}">${pages_base}</a></p>
    <p>Repository layout:</p>
    <ul>
      <li><a href="./veldmuis-core/os/x86_64/">veldmuis-core/os/x86_64/</a></li>
      <li><a href="./veldmuis-extra/os/x86_64/">veldmuis-extra/os/x86_64/</a></li>
    </ul>
    <p>Mirrorlist example:</p>
    <p><code>Server = ${pages_base}/\$repo/os/\$arch</code></p>
  </main>
</body>
</html>
EOF
}

publish_tree() {
  find "${worktree_dir}" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

  cp -a "${repos_root}/veldmuis-core" "${worktree_dir}/veldmuis-core"
  cp -a "${repos_root}/veldmuis-extra" "${worktree_dir}/veldmuis-extra"
  render_index

  if [[ -n "${cname}" ]]; then
    printf '%s\n' "${cname}" > "${worktree_dir}/CNAME"
  fi
}

commit_and_push() {
  (
    cd "${worktree_dir}"
    if [[ -n "${git_author_name}" ]]; then
      git config user.name "${git_author_name}"
    elif ! git config user.name >/dev/null 2>&1; then
      git config user.name "Veldmuis Pages Bot"
    fi

    if [[ -n "${git_author_email}" ]]; then
      git config user.email "${git_author_email}"
    elif ! git config user.email >/dev/null 2>&1; then
      git config user.email "actions@veldmuislinux.org"
    fi

    git add -A
    if git diff --cached --quiet; then
      log "No GitHub Pages changes to publish."
      return 0
    fi
    git commit -m "Publish pacman repo $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
    git push "${remote}" "${branch}" >/dev/null
  )
}

main() {
  require_cmd git

  [[ -d "${repos_root}/veldmuis-core/os/x86_64" ]] || die "Missing built core repo under ${repos_root}"
  [[ -d "${repos_root}/veldmuis-extra/os/x86_64" ]] || die "Missing built extra repo under ${repos_root}"

  trap cleanup EXIT

  prepare_worktree
  publish_tree
  commit_and_push

  log "Published GitHub Pages branch '${branch}'."
  log "Expected base URL: ${pages_base}"
}

main "$@"
