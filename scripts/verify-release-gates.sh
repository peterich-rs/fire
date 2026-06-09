#!/usr/bin/env bash
set -euo pipefail

evidence_file="${1:-docs/release/release-gate-evidence.md}"

if [[ ! -f "$evidence_file" ]]; then
  echo "release gate evidence file not found: $evidence_file" >&2
  exit 2
fi

awk '
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

function parse_markdown_row(line, fields, i, char, next_char, count, current) {
  for (i in fields) {
    delete fields[i]
  }
  count = 0
  current = ""
  for (i = 1; i <= length(line); i += 1) {
    char = substr(line, i, 1)
    next_char = substr(line, i + 1, 1)
    if (char == "\\" && next_char == "|") {
      current = current "|"
      i += 1
    } else if (char == "|") {
      fields[++count] = current
      current = ""
    } else {
      current = current char
    }
  }
  fields[++count] = current
  return count
}

function fail(gate, message) {
  failure_count += 1
  printf("FAIL: %s: %s\n", gate, message) > "/dev/stderr"
}

function is_leap_year(year) {
  return year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
}

function is_valid_date(value, year, month, day, max_day) {
  if (value !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
    return 0
  }
  year = substr(value, 1, 4) + 0
  month = substr(value, 6, 2) + 0
  day = substr(value, 9, 2) + 0
  if (month < 1 || month > 12 || day < 1) {
    return 0
  }
  max_day = 31
  if (month == 4 || month == 6 || month == 9 || month == 11) {
    max_day = 30
  } else if (month == 2) {
    max_day = is_leap_year(year) ? 29 : 28
  }
  return day <= max_day
}

function contains_fake_evidence_marker(value, normalized) {
  normalized = tolower(value)
  return normalized ~ /(^|[^[:alnum:]])(fake|mock|placeholder|dummy|synthetic)([^[:alnum:]]|$)/ ||
    normalized ~ /(^|[^[:alnum:]])(todo|tbd)([^[:alnum:]]|$)/ ||
    normalized ~ /example[.]com|not[- ]real/ ||
    normalized ~ /(^|\/)(localhost|127[.]0[.]0[.]1|0[.]0[.]0[.]0)([:\/]|$)/ ||
    normalized ~ /[.](local|test|invalid)([:\/]|$)/
}

function contains_accepted_waiver_metadata(value) {
  return (value ~ /[Aa]pprov(ed)?[[:space:]]+by[[:space:]]+[^;,.]+/ ||
      value ~ /[Aa]pprover[[:space:]]*:[[:space:]]*[^;,.]+/ ||
      value ~ /[Ww]aiv(ed)?[[:space:]]+by[[:space:]]+[^;,.]+/ ||
      value ~ /[Ww]aiver[[:space:]]*:[[:space:]]*[^;,.]+/ ||
      value ~ /[Aa]ccept(ed)?[[:space:]]+by[[:space:]]+[^;,.]+/) &&
    (value ~ /[Rr]eason[[:space:]]*:/ ||
      value ~ /[Bb]ecause/ ||
      value ~ /[Dd]ue to/ ||
      value ~ /[Rr]isk[[:space:]]*:/ ||
      value ~ /[Ee]xception[[:space:]]*:/ ||
      value ~ /[Nn]o-ship/)
}

function has_valid_http_host(value, host, label_count, labels, label_index) {
  host = value
  sub(/^https?:\/\//, "", host)
  sub(/[\/?#].*$/, "", host)
  sub(/:[0-9]+$/, "", host)
  if (host == "" || length(host) > 253 || host ~ /^[.]|[.]$/ || host ~ /[.][.]/) {
    return 0
  }
  label_count = split(host, labels, ".")
  for (label_index = 1; label_index <= label_count; label_index += 1) {
    if (labels[label_index] == "" || length(labels[label_index]) > 63 || labels[label_index] ~ /^-/ || labels[label_index] ~ /-$/) {
      return 0
    }
  }
  return 1
}

function is_http_url(value) {
  return value ~ /^https?:\/\/[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]+)?([\/?#][^[:space:]]*)?$/ &&
    has_valid_http_host(value)
}

function is_safe_repo_path(value) {
  return value ~ /^[A-Za-z0-9_.\/-]+$/ &&
    value !~ /^\// &&
    value !~ /^-/ &&
    value !~ /(^|\/)[.][.](\/|$)/ &&
    value !~ /\/$/
}

function repo_path_is_non_empty_file(value, command) {
  command = "test -f " value " && test -s " value
  return system(command) == 0
}

function validate_evidence_link(row_label, link) {
  if (link == "") {
    fail(row_label, "evidence link is required")
  } else if (!is_http_url(link)) {
    if (!is_safe_repo_path(link)) {
      fail(row_label, "evidence link must be an HTTP(S) URL or safe repo-relative file path")
    } else if (!repo_path_is_non_empty_file(link)) {
      fail(row_label, "evidence link path must exist and be a non-empty file")
    }
  }
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
  field_count = parse_markdown_row($0, field)
  if (field[2] ~ /^[[:space:]]*Gate[[:space:]]*$/ || field[2] ~ /^[[:space:]]*---[[:space:]]*$/) {
    next
  }

  gate = trim(field[2])
  row_label = gate
  owner = trim(field[4])
  status = trim(field[5])
  link = trim(field[6])
  date = trim(field[7])
  notes = trim(field[8])
  row_count += 1
  if (row_label == "") {
    row_label = "row " row_count
  }
  if (field_count < 9) {
    fail(row_label, "row is missing Markdown table columns; use the exact evidence table shape")
  } else if (field_count > 9) {
    fail(row_label, "row has extra Markdown table columns; escape pipe characters in cells")
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
  validate_evidence_link(row_label, link)
  if (!is_valid_date(date)) {
    fail(row_label, "date must be a valid YYYY-MM-DD calendar date")
  }
  if (status == "Accepted") {
    if (notes == "") {
      fail(row_label, "accepted waivers require notes")
    } else if (!contains_accepted_waiver_metadata(notes)) {
      fail(row_label, "accepted waivers require approver and reason in notes")
    }
  }
  if ((status in allowed) && contains_fake_evidence_marker(owner " " link " " notes)) {
    fail(row_label, "evidence metadata must not contain fake, mock, placeholder, dummy, synthetic, TODO, TBD, example.com, not-real, or not real markers")
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
