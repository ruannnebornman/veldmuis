#!/usr/bin/env bash

set -euo pipefail

if ! command -v aws >/dev/null 2>&1; then
  printf '[ensure-aws-cli] ERROR: AWS CLI is not installed. GitHub-hosted runners normally provide AWS CLI v2; install a pinned version instead of pulling from PyPI at release time.\n' >&2
  exit 1
fi

aws --version
