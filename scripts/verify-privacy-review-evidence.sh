#!/usr/bin/env bash
set -euo pipefail

evidence_file="${1:-docs/release/privacy-review-evidence.md}"

if [[ ! -f "$evidence_file" ]]; then
  echo "privacy review evidence file not found: $evidence_file" >&2
  exit 2
fi

awk -F'|' '
BEGIN {
  required["Privacy policy"] = 1
  required["App Store privacy questionnaire"] = 1
  required["Play Store Data Safety"] = 1
  required["Android backup behavior"] = 1
  required["Diagnostic export redaction"] = 1
  required["iOS privacy manifests"] = 1
  required["Third-party licenses"] = 1
  required["Final publication approval"] = 1

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

function is_template_row(date, area, reviewer, status, link, notes) {
  return date == "" && area == "" && reviewer == "" && status == "" && link == "" && notes == ""
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
  area = trim($3)
  reviewer = trim($4)
  status = normalize_status($5)
  link = trim($6)
  notes = trim($7)
  row_label = area

  if (is_template_row(date, area, reviewer, status, link, notes)) {
    next
  }

  row_count += 1

  if (!is_valid_date(date)) {
    fail(row_label, "date must be a valid YYYY-MM-DD calendar date")
  }

  if (!(area in required)) {
    fail(row_label, "review area is not one of the required rows")
  } else {
    if (seen[area] > 0) {
      fail(row_label, "duplicate privacy review evidence row")
    }
    seen[area] += 1
  }

  if (reviewer == "") {
    fail(row_label, "reviewer is required")
  }

  if (!(status in allowed_status)) {
    fail(row_label, "status must be Complete or Accepted, found " status)
  }

  validate_evidence_link(row_label, link)

  if (notes == "") {
    fail(row_label, "notes are required")
  }

  if ((status in allowed_status) && contains_fake_evidence_marker(reviewer " " link " " notes)) {
    fail(row_label, "evidence metadata must not contain fake, mock, placeholder, dummy, synthetic, TODO, TBD, example.com, not-real, or not real markers")
  }

  if (status == "Accepted" && !contains_accepted_waiver_metadata(notes)) {
    fail(row_label, "accepted rows require approver and waiver reason in notes")
  }

  if (area == "Final publication approval" && (notes !~ /[Aa]pprov/ || notes !~ /[Pp]ublish|[Rr]elease|[Ss]ubmi/)) {
    fail(row_label, "final publication approval notes must mention approval to publish, release, or submit")
  }

}

END {
  for (area in required) {
    if (!(area in seen)) {
      fail(area, "missing required privacy review evidence row")
    }
  }

  if (row_count == 0) {
    fail("Required Evidence", "no privacy review evidence rows found")
  }

  if (failure_count > 0) {
    printf("Privacy review evidence verification failed: %d row(s), %d failure(s)\n", row_count, failure_count) > "/dev/stderr"
    exit 1
  }

  printf("Privacy review evidence verification passed: %d row(s)\n", row_count)
}
' "$evidence_file"
