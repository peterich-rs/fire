#!/usr/bin/env bash
set -euo pipefail

evidence_file="${1:-docs/release/internal-testing-evidence.md}"

if [[ ! -f "$evidence_file" ]]; then
  echo "internal testing evidence file not found: $evidence_file" >&2
  exit 2
fi

awk -F'|' '
BEGIN {
  required["iOS" SUBSEP "App Store Connect record"] = 1
  required["Android" SUBSEP "Play Console record"] = 1
  required["iOS" SUBSEP "Internal testing build"] = 1
  required["Android" SUBSEP "Internal testing build"] = 1
  required["iOS" SUBSEP "Tester invites"] = 1
  required["Android" SUBSEP "Tester invites"] = 1
  required["iOS" SUBSEP "Feedback triage"] = 1
  required["Android" SUBSEP "Feedback triage"] = 1

  allowed_status["Complete"] = 1
  allowed_status["Accepted"] = 1

  row_count = 0
  failure_count = 0
  in_required_evidence = 0
}

function trim(value) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
  return value
}

function normalize_platform(value) {
  value = trim(value)
  if (tolower(value) == "ios") {
    return "iOS"
  }
  if (tolower(value) == "android") {
    return "Android"
  }
  return value
}

function normalize_status(value) {
  value = trim(value)
  if (tolower(value) == "complete") {
    return "Complete"
  }
  if (tolower(value) == "accepted") {
    return "Accepted"
  }
  return value
}

function fail(row_label, message) {
  failure_count += 1
  printf("FAIL: %s: %s\n", row_label, message) > "/dev/stderr"
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

function is_http_url(value) {
  return value ~ /^https?:\/\//
}

function is_safe_repo_path(value) {
  return value ~ /^[A-Za-z0-9_.\/-]+$/ &&
    value !~ /^\// &&
    value !~ /^-/ &&
    value !~ /(^|\/)[.][.](\/|$)/ &&
    value !~ /\/$/
}

function repo_path_exists(value, command) {
  command = "test -s " value
  return system(command) == 0
}

function validate_evidence_link(row_label, link) {
  if (link == "") {
    fail(row_label, "evidence link is required")
  } else if (!is_http_url(link)) {
    if (!is_safe_repo_path(link)) {
      fail(row_label, "evidence link must be an HTTP(S) URL or safe repo-relative file path")
    } else if (!repo_path_exists(link)) {
      fail(row_label, "evidence link path must exist and be non-empty")
    }
  }
}

function is_template_row(date, platform, gate, owner, status, link, notes) {
  return date == "" && platform == "" && gate == "" && owner == "" && status == "" && link == "" && notes == ""
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
  if ($2 ~ /^[[:space:]]*Date[[:space:]]*$/ || $2 ~ /^[[:space:]]*---[[:space:]]*$/) {
    next
  }

  date = trim($2)
  platform = normalize_platform($3)
  gate = trim($4)
  owner = trim($5)
  status = normalize_status($6)
  link = trim($7)
  notes = trim($8)
  row_label = platform " " gate

  if (is_template_row(date, platform, gate, owner, status, link, notes)) {
    next
  }

  row_count += 1

  if (!is_valid_date(date)) {
    fail(row_label, "date must be a valid YYYY-MM-DD calendar date")
  }

  if (!(platform == "iOS" || platform == "Android")) {
    fail(row_label, "platform must be iOS or Android")
  }

  key = platform SUBSEP gate
  if (!(key in required)) {
    fail(row_label, "gate is not one of the required platform/gate pairs")
  } else {
    if (seen[key] > 0) {
      fail(row_label, "duplicate internal testing evidence row")
    }
    seen[key] += 1
  }

  if (owner == "") {
    fail(row_label, "owner is required")
  }

  if (!(status in allowed_status)) {
    fail(row_label, "status must be Complete or Accepted, found " status)
  }

  validate_evidence_link(row_label, link)

  if (notes == "") {
    fail(row_label, "notes are required")
  }

  if ((status in allowed_status) && contains_fake_evidence_marker(owner " " link " " notes)) {
    fail(row_label, "evidence metadata must not contain fake, mock, placeholder, dummy, synthetic, TODO, TBD, example.com, not-real, or not real markers")
  }

  if (status == "Accepted" && !contains_accepted_waiver_metadata(notes)) {
    fail(row_label, "accepted rows require approver and reason in notes")
  }

  if (gate == "Internal testing build") {
    if (notes !~ /[Bb]uild[[:space:]:#-]*[0-9][0-9A-Za-z._-]*/) {
      fail(row_label, "internal testing build notes must include build number")
    }
    if (notes !~ /([Cc]ommit|[Ss][Hh][Aa])[[:space:]:#-]*[0-9a-fA-F]{7,40}/) {
      fail(row_label, "internal testing build notes must include commit SHA")
    }
  }

  if (gate == "Tester invites") {
    if (notes !~ /[Gg]roup|[Ll]ist/) {
      fail(row_label, "tester invite notes must include group or list name")
    }
    if (notes !~ /[Ii]nvit/) {
      fail(row_label, "tester invite notes must include invite date/status")
    }
    if (notes !~ /[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
      fail(row_label, "tester invite notes must include invite date")
    }
  }

  if (gate == "Feedback triage") {
    if (notes !~ /[Bb]locker[^0-9]*[0-9]+/) {
      fail(row_label, "feedback triage notes must summarize blocker count")
    }
    if (notes !~ /[Rr]isk|[Aa]ccept/) {
      fail(row_label, "feedback triage notes must summarize accepted risks")
    }
    if (notes !~ /[Nn]one|https?:\/\/|#[0-9]+|[A-Z][A-Z0-9]+-[0-9]+/) {
      fail(row_label, "feedback triage notes must link release-blocking issues or state none")
    }
  }

}

END {
  for (key in required) {
    split(key, parts, SUBSEP)
    platform = parts[1]
    gate = parts[2]
    if (!(platform SUBSEP gate in seen)) {
      fail(platform " " gate, "missing required internal testing evidence row")
    }
  }

  if (row_count == 0) {
    fail("Required Evidence", "no internal testing evidence rows found")
  }

  if (failure_count > 0) {
    printf("Internal testing evidence verification failed: %d row(s), %d failure(s)\n", row_count, failure_count) > "/dev/stderr"
    exit 1
  }

  printf("Internal testing evidence verification passed: %d row(s)\n", row_count)
}
' "$evidence_file"
