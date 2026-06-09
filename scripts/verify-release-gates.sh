#!/usr/bin/env bash
set -euo pipefail

evidence_file="${1:-docs/release/release-gate-evidence.md}"

if [[ ! -f "$evidence_file" ]]; then
  echo "release gate evidence file not found: $evidence_file" >&2
  exit 2
fi

awk -F'|' '
BEGIN {
  allowed["Complete"] = 1
  allowed["Accepted"] = 1
  row_count = 0
  failure_count = 0
}

function trim(value) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
  return value
}

function fail(gate, message) {
  failure_count += 1
  printf("FAIL: %s: %s\n", gate, message) > "/dev/stderr"
}

/^\|/ {
  if ($2 ~ /^[[:space:]]*Gate[[:space:]]*$/ || $2 ~ /^[[:space:]]*---[[:space:]]*$/) {
    next
  }

  gate = trim($2)
  owner = trim($4)
  status = trim($5)
  link = trim($6)
  date = trim($7)
  notes = trim($8)
  row_count += 1

  if (!(status in allowed)) {
    fail(gate, "status must be Complete or Accepted, found " status)
  }
  if (owner == "") {
    fail(gate, "owner is required")
  }
  if (link == "") {
    fail(gate, "evidence link is required")
  }
  if (date !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
    fail(gate, "date must use YYYY-MM-DD")
  }
  if (status == "Accepted" && notes == "") {
    fail(gate, "accepted waivers require notes")
  }
}

END {
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
