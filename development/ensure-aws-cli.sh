#!/usr/bin/env bash

set -euo pipefail

if ! command -v aws >/dev/null 2>&1; then
  python3 -m pip install --user awscli
  export PATH="${HOME}/.local/bin:${PATH}"

  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${HOME}/.local/bin" >> "${GITHUB_PATH}"
  fi
fi

aws --version
