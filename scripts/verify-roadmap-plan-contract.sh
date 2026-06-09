#!/usr/bin/env bash
set -euo pipefail

spec_file="docs/superpowers/specs/2026-06-08-fire-v2-roadmap-design.md"

plans=(
  "P1|docs/superpowers/plans/2026-06-08-p1-foundation.md|17"
  "P2|docs/superpowers/plans/2026-06-08-p2-feature-completion.md|14"
  "P3|docs/superpowers/plans/2026-06-08-p3-native-differentiation.md|15"
  "P4|docs/superpowers/plans/2026-06-08-p4-release-preparation.md|6"
)

failure_count=0
total_expected=0
total_actual=0

fail() {
  failure_count=$((failure_count + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

if [[ ! -f "$spec_file" ]]; then
  fail "roadmap design spec is missing: $spec_file"
else
  printf 'INFO: roadmap design spec found: %s\n' "$spec_file"
fi

for entry in "${plans[@]}"; do
  IFS='|' read -r label plan_file expected_count <<< "$entry"
  total_expected=$((total_expected + expected_count))

  if [[ ! -f "$plan_file" ]]; then
    fail "$label plan is missing: $plan_file"
    continue
  fi

  actual_count="$(awk '/^## Task [0-9]+:/ || /^### Task [0-9]+:/ { count += 1 } END { print count + 0 }' "$plan_file")"
  total_actual=$((total_actual + actual_count))

  while IFS= read -r malformed_heading; do
    fail "$label plan has non-contract task heading: $malformed_heading"
  done < <(awk '$0 ~ /^## Task / || $0 ~ /^### Task / { if ($0 !~ /^## Task [0-9]+:/ && $0 !~ /^### Task [0-9]+:/) print FNR ":" $0 }' "$plan_file")

  if [[ "$actual_count" -ne "$expected_count" ]]; then
    fail "$label plan expected $expected_count top-level task(s), found $actual_count in $plan_file"
  else
    printf 'INFO: %s plan task count OK: %d\n' "$label" "$actual_count"
  fi
done

if [[ "$total_actual" -ne "$total_expected" ]]; then
  fail "roadmap plan total expected $total_expected top-level task(s), found $total_actual"
else
  printf 'INFO: roadmap plan total OK: %d task(s)\n' "$total_actual"
fi

if [[ "$failure_count" -gt 0 ]]; then
  printf 'Roadmap plan contract verification failed: %d failure(s)\n' "$failure_count" >&2
  exit 1
fi

printf 'Roadmap plan contract verification passed: 1 spec, %d plan(s), %d task(s).\n' "${#plans[@]}" "$total_actual"
