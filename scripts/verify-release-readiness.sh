#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

checks=(
  "Store marketing assets|scripts/verify-marketing-assets.sh"
  "Performance benchmarks|scripts/verify-performance-benchmarks.sh"
  "Accessibility audit|scripts/verify-accessibility-audit.sh"
  "Release gate evidence|scripts/verify-release-gates.sh"
)

failure_count=0

for entry in "${checks[@]}"; do
  IFS='|' read -r label command_path <<< "$entry"
  printf '==> %s\n' "$label"

  if [[ ! -x "$command_path" ]]; then
    printf 'FAIL: %s: verifier is missing or not executable: %s\n' "$label" "$command_path" >&2
    failure_count=$((failure_count + 1))
    continue
  fi

  if "$command_path"; then
    printf 'PASS: %s\n' "$label"
  else
    status=$?
    printf 'FAIL: %s: %s exited with status %d\n' "$label" "$command_path" "$status" >&2
    failure_count=$((failure_count + 1))
  fi
  printf '\n'
done

if [[ "$failure_count" -gt 0 ]]; then
  printf 'Release readiness verification failed: %d check(s) failed\n' "$failure_count" >&2
  exit 1
fi

printf 'Release readiness verification passed.\n'
