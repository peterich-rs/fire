#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
required_submodules=(
  "third_party/openwire"
  "third_party/xlog-rs"
)

for path in "${required_submodules[@]}"; do
  full_path="${repo_root}/${path}"
  if ! git -C "${full_path}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "required submodule is not initialized: ${path}" >&2
    echo "run: git submodule update --init --recursive ${path}" >&2
    exit 1
  fi

  if [[ -n "$(git -C "${full_path}" status --short --untracked-files=no)" ]]; then
    echo "required submodule has local modifications: ${path}" >&2
    git -C "${full_path}" status --short --untracked-files=no >&2
    exit 1
  fi
done

if [[ -n "$(git -C "${repo_root}" status --short --ignore-submodules=all -- third_party/openwire third_party/xlog-rs)" ]]; then
  echo "superproject has uncommitted submodule pointer changes" >&2
  git -C "${repo_root}" status --short --ignore-submodules=all -- third_party/openwire third_party/xlog-rs >&2
  exit 1
fi
