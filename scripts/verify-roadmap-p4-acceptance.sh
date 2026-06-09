#!/usr/bin/env bash
set -euo pipefail

roadmap_file="${1:-docs/superpowers/specs/2026-06-08-fire-v2-roadmap-design.md}"
release_gate_file="${2:-docs/release/release-gate-evidence.md}"
p4_release_evidence_suite="scripts/verify-p4-release-evidence-suite.sh"

if [[ ! -f "$roadmap_file" ]]; then
  echo "roadmap design file not found: $roadmap_file" >&2
  exit 2
fi

if [[ ! -f "$release_gate_file" ]]; then
  echo "release gate evidence file not found: $release_gate_file" >&2
  exit 2
fi

parse_output="$(
  awk '
  BEGIN {
    add_required("App Store / Play Store 素材齐全")
    add_required("TestFlight / 内部测试轨道可分发")
    add_required("首页滚动 60fps 无掉帧")
    add_required("话题详情首屏 < 2s")
    add_required("VoiceOver / TalkBack 全流程可操作")

    row_count = 0
    checked_count = 0
    failure_count = 0
    in_p4_acceptance = 0
  }

  function add_required(item) {
    required[item] = 1
    required_names[++required_count] = item
  }

  function trim(value) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    return value
  }

  function fail(item, message) {
    failure_count += 1
    printf("FAIL: %s: %s\n", item, message) > "/dev/stderr"
  }

  /^### P4 验收[[:space:]]*$/ {
    in_p4_acceptance = 1
    next
  }

  in_p4_acceptance && /^### / {
    in_p4_acceptance = 0
    next
  }

  in_p4_acceptance && /^- \[[ xX]\][[:space:]]+/ {
    item = $0
    is_checked = item ~ /^- \[[xX]\][[:space:]]+/
    sub(/^- \[[ xX]\][[:space:]]+/, "", item)
    item = trim(item)

    row_count += 1

    if (seen_all[item] > 0) {
      fail(item, "duplicate P4 acceptance row")
    }
    seen_all[item] += 1

    if (!(item in required)) {
      fail(item, "unknown P4 acceptance row; use the exact required roadmap wording")
    } else {
      seen[item] = 1
    }

    if (is_checked) {
      checked_count += 1
    }
  }

  END {
    for (required_index = 1; required_index <= required_count; required_index += 1) {
      item = required_names[required_index]
      if (!(item in seen)) {
        fail(item, "missing required P4 acceptance row")
      }
    }

    if (row_count == 0) {
      fail("P4 验收", "no P4 acceptance rows found")
    }

    if (failure_count > 0) {
      printf("Roadmap P4 acceptance verification failed: %d row(s), %d failure(s)\n", row_count, failure_count) > "/dev/stderr"
      exit 1
    }

    printf("row_count=%d\n", row_count)
    printf("checked_count=%d\n", checked_count)
  }
  ' "$roadmap_file"
)"

row_count="$(printf '%s\n' "$parse_output" | awk -F= '/^row_count=/ { print $2; exit }')"
checked_count="$(printf '%s\n' "$parse_output" | awk -F= '/^checked_count=/ { print $2; exit }')"

if [[ -z "$row_count" || -z "$checked_count" ]]; then
  echo "roadmap P4 acceptance parser did not report row counts" >&2
  exit 1
fi

if [[ "$checked_count" -gt 0 ]]; then
  if [[ ! -x "$p4_release_evidence_suite" ]]; then
    printf 'FAIL: P4 release evidence suite is missing or not executable: %s\n' "$p4_release_evidence_suite" >&2
    exit 2
  fi

  if ! suite_output="$(
    FIRE_RELEASE_GATE_EVIDENCE_FILE="$release_gate_file" \
      "$p4_release_evidence_suite" 2>&1
  )"; then
    printf '%s\n' "$suite_output" >&2
    printf 'FAIL: roadmap P4 acceptance has %d checked item(s), but P4 release evidence suite is incomplete.\n' "$checked_count" >&2
    exit 1
  fi
fi

printf 'Roadmap P4 acceptance verification passed: %d row(s), %d checked.\n' "$row_count" "$checked_count"
