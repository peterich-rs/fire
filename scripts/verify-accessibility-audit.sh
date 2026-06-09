#!/usr/bin/env bash
set -euo pipefail

audit_file="${1:-docs/release/accessibility-audit-checklist.md}"

if [[ ! -f "$audit_file" ]]; then
  echo "accessibility audit file not found: $audit_file" >&2
  exit 2
fi

awk -F'|' '
BEGIN {
  required_screen["Login and Cloudflare flow"] = 1
  required_screen["Home feed"] = 1
  required_screen["Category-filtered feed"] = 1
  required_screen["Topic detail"] = 1
  required_screen["Notifications"] = 1
  required_screen["Search"] = 1
  required_screen["Profile"] = 1
  required_screen["Bookmarks"] = 1
  required_screen["Drafts and composer"] = 1
  required_screen["Widgets"] = 1
  required_screen["Developer diagnostics, if exposed in the build"] = 1

  required_audit["VoiceOver / TalkBack"] = 1
  required_audit["Dynamic Type / Font Scale"] = 1
  required_audit["Motion And Haptics"] = 1
  required_audit["Contrast And Color"] = 1
  required_audit["Keyboard And Switch Control"] = 1

  required_platform["iOS"] = 1
  required_platform["Android"] = 1

  row_count = 0
  failure_count = 0
  in_results_log = 0
}

function trim(value) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
  return value
}

function fail(row_label, message) {
  failure_count += 1
  printf("FAIL: %s: %s\n", row_label, message) > "/dev/stderr"
}

function contains_fake_evidence_marker(value, normalized) {
  normalized = tolower(value)
  return normalized ~ /(^|[^[:alnum:]])(fake|mock|placeholder|dummy|synthetic)([^[:alnum:]]|$)/ ||
    normalized ~ /(^|[^[:alnum:]])(todo|tbd)([^[:alnum:]]|$)/ ||
    normalized ~ /example[.]com|not[- ]real/
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

function normalize_result(value) {
  value = trim(value)
  if (tolower(value) == "pass") {
    return "Pass"
  }
  if (tolower(value) == "accepted") {
    return "Accepted"
  }
  if (tolower(value) == "fail") {
    return "Fail"
  }
  return value
}

function is_template_row(date, tester, platform, device, screen, result, notes) {
  return date == "" && tester == "" && platform == "" && device == "" && screen == "" && result == "" && notes == ""
}

/^## Results Log[[:space:]]*$/ {
  in_results_log = 1
  next
}

in_results_log && /^## / {
  in_results_log = 0
  next
}

in_results_log && /^\|/ {
  if ($2 ~ /^[[:space:]]*Date[[:space:]]*$/ || $2 ~ /^[[:space:]]*---[[:space:]]*$/) {
    next
  }

  date = trim($2)
  tester = trim($3)
  platform = normalize_platform($4)
  device = trim($5)
  screen = trim($6)
  result = normalize_result($7)
  notes = trim($8)
  row_label = platform " " screen

  if (is_template_row(date, tester, platform, device, screen, result, notes)) {
    next
  }

  row_count += 1

  if (date !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
    fail(row_label, "date must use YYYY-MM-DD")
  }

  if (tester == "") {
    fail(row_label, "tester is required")
  }

  if (!(platform in required_platform)) {
    fail(row_label, "platform must be iOS or Android")
  }

  if (device == "") {
    fail(row_label, "physical device name is required")
  }

  if (device ~ /[Ss]imulator|[Ee]mulator/) {
    fail(row_label, "release accessibility evidence must use a physical device")
  }

  if (!(screen in required_screen) && !(screen in required_audit)) {
    fail(row_label, "screen must match a checklist screen or audit category")
  }

  if (result == "Fail") {
    fail(row_label, "blocking accessibility failures must be fixed or explicitly Accepted")
  } else if (result != "Pass" && result != "Accepted") {
    fail(row_label, "result must be Pass or Accepted, found " result)
  }

  if (result == "Accepted") {
    if (notes == "") {
      fail(row_label, "accepted accessibility waivers require notes")
    } else if (!contains_accepted_waiver_metadata(notes)) {
      fail(row_label, "accepted accessibility waivers require approver and reason in notes")
    }
  }

  if ((result == "Pass" || result == "Accepted") && contains_fake_evidence_marker(notes)) {
    fail(row_label, "accessibility notes must not contain fake, mock, placeholder, dummy, synthetic, TODO, TBD, example.com, not-real, or not real markers")
  }

  if (screen in required_screen) {
    seen_screen[platform SUBSEP screen] = 1
  }
  if (screen in required_audit) {
    seen_audit[platform SUBSEP screen] = 1
  }
}

END {
  for (platform in required_platform) {
    for (screen in required_screen) {
      if (!(platform SUBSEP screen in seen_screen)) {
        fail(platform " " screen, "missing release-candidate accessibility screen result")
      }
    }
    for (audit in required_audit) {
      if (!(platform SUBSEP audit in seen_audit)) {
        fail(platform " " audit, "missing release-candidate accessibility audit result")
      }
    }
  }

  if (row_count == 0) {
    fail("Results Log", "no accessibility audit result rows found")
  }

  if (failure_count > 0) {
    printf("Accessibility audit verification failed: %d row(s), %d failure(s)\n", row_count, failure_count) > "/dev/stderr"
    exit 1
  }

  printf("Accessibility audit verification passed: %d row(s)\n", row_count)
}
' "$audit_file"
