#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export FIRE_MARKETING_ASSETS_ROOT="${FIRE_MARKETING_ASSETS_ROOT:-$ROOT_DIR}"

performance_file="${FIRE_PERFORMANCE_BENCHMARK_FILE:-docs/release/performance-benchmarks.md}"
accessibility_file="${FIRE_ACCESSIBILITY_AUDIT_FILE:-docs/release/accessibility-audit-checklist.md}"
internal_testing_file="${FIRE_INTERNAL_TESTING_EVIDENCE_FILE:-docs/release/internal-testing-evidence.md}"
privacy_review_file="${FIRE_PRIVACY_REVIEW_EVIDENCE_FILE:-docs/release/privacy-review-evidence.md}"
release_gate_file="${FIRE_RELEASE_GATE_EVIDENCE_FILE:-docs/release/release-gate-evidence.md}"

checks=(
  "Store marketing assets|scripts/verify-marketing-assets.sh|"
  "Performance benchmarks|scripts/verify-performance-benchmarks.sh|$performance_file"
  "Accessibility audit|scripts/verify-accessibility-audit.sh|$accessibility_file"
  "Internal testing evidence|scripts/verify-internal-testing-evidence.sh|$internal_testing_file"
  "Privacy review evidence|scripts/verify-privacy-review-evidence.sh|$privacy_review_file"
  "Release gate evidence|scripts/verify-release-gates.sh|$release_gate_file"
)

failure_count=0

for entry in "${checks[@]}"; do
  IFS='|' read -r label command_path argument <<< "$entry"
  printf '==> %s\n' "$label"

  if [[ ! -x "$command_path" ]]; then
    printf 'FAIL: %s: verifier is missing or not executable: %s\n' "$label" "$command_path" >&2
    failure_count=$((failure_count + 1))
    printf '\n'
    continue
  fi

  if [[ -n "$argument" ]]; then
    if "$command_path" "$argument"; then
      printf 'PASS: %s\n' "$label"
    else
      status=$?
      printf 'FAIL: %s: %s exited with status %d\n' "$label" "$command_path" "$status" >&2
      failure_count=$((failure_count + 1))
    fi
  elif "$command_path"; then
    printf 'PASS: %s\n' "$label"
  else
    status=$?
    printf 'FAIL: %s: %s exited with status %d\n' "$label" "$command_path" "$status" >&2
    failure_count=$((failure_count + 1))
  fi
  printf '\n'
done

if [[ "$failure_count" -gt 0 ]]; then
  printf 'P4 release evidence suite verification failed: %d check(s) failed\n' "$failure_count" >&2
  exit 1
fi

printf 'P4 release evidence suite verification passed.\n'
