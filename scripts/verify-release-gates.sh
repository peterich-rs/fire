#!/usr/bin/env bash
set -euo pipefail

evidence_file="${1:-docs/release/release-gate-evidence.md}"

if [[ ! -f "$evidence_file" ]]; then
  echo "release gate evidence file not found: $evidence_file" >&2
  exit 2
fi

awk -F'|' '
BEGIN {
  add_required("App Store screenshots")
  add_required("App Preview video")
  add_required("Play Store screenshots")
  add_required("Play Store feature graphic")
  add_required("Maintainer/legal privacy review")
  add_required("App Store Connect record")
  add_required("Play Console record")
  add_required("Internal testing builds")
  add_required("Tester invites and feedback")
  add_required("iOS release benchmarks")
  add_required("Android release benchmarks")
  add_required("Benchmark failure disposition")
  add_required("VoiceOver audit")
  add_required("TalkBack audit")
  add_required("Dynamic Type / font-scale audit")
  add_required("Reduce Motion / haptic audit")
  add_required("High contrast / color-blindness audit")
  add_required("Accessibility failure disposition")

  allowed["Complete"] = 1
  allowed["Accepted"] = 1
  row_count = 0
  failure_count = 0
  in_required_evidence = 0
}

function add_required(gate) {
  required[gate] = 1
  required_names[++required_count] = gate
}

function trim(value) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
  return value
}

function fail(gate, message) {
  failure_count += 1
  printf("FAIL: %s: %s\n", gate, message) > "/dev/stderr"
}

/^## Required Evidence[[:space:]]*$/ {
  in_required_evidence = 1
  next
}

in_required_evidence && /^## / {
  in_required_evidence = 0
  next
}

in_required_evidence && /^\|/ {
  if ($2 ~ /^[[:space:]]*Gate[[:space:]]*$/ || $2 ~ /^[[:space:]]*---[[:space:]]*$/) {
    next
  }

  gate = trim($2)
  row_label = gate
  owner = trim($4)
  status = trim($5)
  link = trim($6)
  date = trim($7)
  notes = trim($8)
  row_count += 1
  if (row_label == "") {
    row_label = "row " row_count
  }

  if (seen_all[gate] > 0) {
    fail(row_label, "duplicate release gate evidence row")
  }
  seen_all[gate] += 1

  if (!(gate in required)) {
    fail(row_label, "unknown release gate; use the exact required gate name")
  } else {
    seen[gate] = 1
  }

  if (!(status in allowed)) {
    fail(row_label, "status must be Complete or Accepted, found " status)
  }
  if (owner == "") {
    fail(row_label, "owner is required")
  }
  if (link == "") {
    fail(row_label, "evidence link is required")
  }
  if (date !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
    fail(row_label, "date must use YYYY-MM-DD")
  }
  if (status == "Accepted" && notes == "") {
    fail(row_label, "accepted waivers require notes")
  }
}

END {
  for (required_index = 1; required_index <= required_count; required_index += 1) {
    gate = required_names[required_index]
    if (!(gate in seen)) {
      fail(gate, "missing required release gate evidence row")
    }
  }

  if (row_count == 0) {
    print "FAIL: no release gate evidence rows found" > "/dev/stderr"
    exit 1
  }
  if (failure_count > 0) {
    printf("Release gate verification failed: %d row(s), %d failure(s)\n", row_count, failure_count) > "/dev/stderr"
    exit 1
  }
  printf("Release gate verification passed: %d row(s)\n", row_count)
}
' "$evidence_file"
