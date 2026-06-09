#!/usr/bin/env bash
set -euo pipefail

benchmark_file="${1:-docs/release/performance-benchmarks.md}"

if [[ ! -f "$benchmark_file" ]]; then
  echo "performance benchmark file not found: $benchmark_file" >&2
  exit 2
fi

awk '
BEGIN {
  required_metric["Cold start to home visible"] = 1
  required_metric["Home feed scroll fluency"] = 1
  required_metric["Topic detail first screen"] = 1
  required_metric["Home feed memory"] = 1
  required_metric["Topic detail memory after 100 posts"] = 1

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

function first_number(value) {
  if (match(value, /[0-9]+([.][0-9]+)?/)) {
    return substr(value, RSTART, RLENGTH) + 0
  }
  return -1
}

function parse_duration_seconds(value, lower, fragment, number) {
  lower = tolower(value)
  if (match(lower, /[0-9]+([.][0-9]+)?[[:space:]]*(ms|millisecond|milliseconds)/)) {
    fragment = substr(lower, RSTART, RLENGTH)
    number = first_number(fragment)
    return number / 1000.0
  }
  if (match(lower, /[0-9]+([.][0-9]+)?[[:space:]]*(s|sec|secs|second|seconds)([^[:alpha:]]|$)/)) {
    fragment = substr(lower, RSTART, RLENGTH)
    number = first_number(fragment)
    return number
  }
  return -1
}

function count_memory_values(value, lower, count) {
  lower = tolower(value)
  count = 0
  while (match(lower, /[0-9]+([.][0-9]+)?[[:space:]]*(mb|mib|gb|gib)/)) {
    count += 1
    lower = substr(lower, RSTART + RLENGTH)
  }
  return count
}

function memory_fragment_mb(fragment, number) {
  number = first_number(fragment)
  if (fragment ~ /gb|gib/) {
    return number * 1024.0
  }
  return number
}

function max_peak_memory_mb(value, lower, fragment, memory, max_memory) {
  lower = tolower(value)
  max_memory = -1
  while (match(lower, /peak[^0-9]*[0-9]+([.][0-9]+)?[[:space:]]*(mb|mib|gb|gib)/)) {
    fragment = substr(lower, RSTART, RLENGTH)
    memory = memory_fragment_mb(fragment)
    if (memory > max_memory) {
      max_memory = memory
    }
    lower = substr(lower, RSTART + RLENGTH)
  }

  lower = tolower(value)
  while (match(lower, /[0-9]+([.][0-9]+)?[[:space:]]*(mb|mib|gb|gib)[^0-9]*(peak)/)) {
    fragment = substr(lower, RSTART, RLENGTH)
    memory = memory_fragment_mb(fragment)
    if (memory > max_memory) {
      max_memory = memory
    }
    lower = substr(lower, RSTART + RLENGTH)
  }

  return max_memory
}

function parse_memory_mb(value, lower, peak_memory, fragment) {
  lower = tolower(value)
  peak_memory = max_peak_memory_mb(lower)
  if (peak_memory >= 0) {
    return peak_memory
  }
  if (count_memory_values(lower) > 1) {
    return -2
  }
  if (match(lower, /[0-9]+([.][0-9]+)?[[:space:]]*(mb|mib|gb|gib)/)) {
    fragment = substr(lower, RSTART, RLENGTH)
    return memory_fragment_mb(fragment)
  }
  return -1
}

function parse_fps(value, lower, fragment) {
  lower = tolower(value)
  if (match(lower, /[0-9]+([.][0-9]+)?[[:space:]]*(fps|frames per second)/)) {
    fragment = substr(lower, RSTART, RLENGTH)
    return first_number(fragment)
  }
  return -1
}

function parse_jank_percent(value, lower, fragment) {
  lower = tolower(value)
  if (match(lower, /[0-9]+([.][0-9]+)?[[:space:]]*%[^,;|]*(jank|janky)/)) {
    fragment = substr(lower, RSTART, RLENGTH)
    return first_number(fragment)
  }
  if (match(lower, /(jank|janky)[^0-9]*[0-9]+([.][0-9]+)?[[:space:]]*%/)) {
    fragment = substr(lower, RSTART, RLENGTH)
    return first_number(fragment)
  }
  return -1
}

function metric_target_passed(metric, result, duration, memory, fps, jank) {
  if (metric == "Cold start to home visible") {
    duration = parse_duration_seconds(result)
    if (duration < 0) {
      fail(metric, "result must include a numeric duration in seconds or milliseconds")
      return 0
    }
    return duration < 3.0
  }

  if (metric == "Topic detail first screen") {
    duration = parse_duration_seconds(result)
    if (duration < 0) {
      fail(metric, "result must include a numeric duration in seconds or milliseconds")
      return 0
    }
    return duration < 2.0
  }

  if (metric == "Home feed memory") {
    memory = parse_memory_mb(result)
    if (memory == -2) {
      fail(metric, "result with multiple memory values must label peak memory")
      return 0
    }
    if (memory < 0) {
      fail(metric, "result must include a numeric memory value in MB or GB")
      return 0
    }
    return memory < 200.0
  }

  if (metric == "Topic detail memory after 100 posts") {
    memory = parse_memory_mb(result)
    if (memory == -2) {
      fail(metric, "result with multiple memory values must label peak memory")
      return 0
    }
    if (memory < 0) {
      fail(metric, "result must include a numeric memory value in MB or GB")
      return 0
    }
    return memory < 350.0
  }

  if (metric == "Home feed scroll fluency") {
    fps = parse_fps(result)
    jank = parse_jank_percent(result)
    if (fps < 0 || jank < 0) {
      fail(metric, "result must include numeric fps and janky-frame percentage tied to jank")
      return 0
    }
    return fps >= 58.0 && jank <= 5.0
  }

  return 0
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

function is_template_row(date, commit, platform, device, build_type, metric, result, status, notes) {
  return date == "" && commit == "" && platform == "" && device == "" && build_type == "" && metric == "" && result == "" && status == "" && notes == ""
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
  field_count = parse_markdown_row($0, field)
  if (field[2] ~ /^[[:space:]]*Date[[:space:]]*$/ || field[2] ~ /^[[:space:]]*---[[:space:]]*$/) {
    next
  }

  date = trim(field[2])
  commit = trim(field[3])
  platform = normalize_platform(field[4])
  device = trim(field[5])
  build_type = trim(field[6])
  metric = trim(field[7])
  result = trim(field[8])
  status = normalize_status(field[9])
  notes = trim(field[10])
  row_label = platform " " metric

  if (is_template_row(date, commit, platform, device, build_type, metric, result, status, notes)) {
    next
  }

  row_count += 1
  if (field_count > 11) {
    fail(row_label, "row has extra Markdown table columns; escape pipe characters in cells")
  }

  if (!is_valid_date(date)) {
    fail(row_label, "date must be a valid YYYY-MM-DD calendar date")
  }

  if (commit !~ /^[0-9a-fA-F]{7,40}$/) {
    fail(row_label, "commit must be a 7-40 character git SHA")
  }

  if (!(platform in required_platform)) {
    fail(row_label, "platform must be iOS or Android")
  }

  if (device == "") {
    fail(row_label, "physical device name is required")
  }

  if (device ~ /[Ss]imulator|[Ee]mulator/) {
    fail(row_label, "release benchmark evidence must use a physical device")
  }

  if (tolower(build_type) !~ /^release/) {
    fail(row_label, "build type must be a release build")
  }

  if (!(metric in required_metric)) {
    fail(row_label, "metric must match one of the documented target names")
  }

  if (result == "") {
    fail(row_label, "result is required")
  }

  target_passed = 0
  if (metric in required_metric && result != "") {
    target_passed = metric_target_passed(metric, result)
  }

  if (status == "Fail") {
    fail(row_label, "failing threshold results must be fixed or explicitly Accepted")
  } else if (status != "Pass" && status != "Accepted") {
    fail(row_label, "status must be Pass or Accepted, found " status)
  }

  if (status == "Pass" && !target_passed) {
    fail(row_label, "Pass status requires a measured result inside the release target")
  }

  if (status == "Accepted") {
    if (notes == "") {
      fail(row_label, "accepted threshold waivers require notes")
    } else if (!contains_accepted_waiver_metadata(notes)) {
      fail(row_label, "accepted threshold waivers require approver and reason in notes")
    }
  }

  if ((status == "Pass" || status == "Accepted") && contains_fake_evidence_marker(device " " build_type " " result " " notes)) {
    fail(row_label, "benchmark metadata must not contain fake, mock, placeholder, dummy, synthetic, TODO, TBD, example.com, not-real, or not real markers, or placeholder URL hosts")
  }

  seen[platform SUBSEP metric] = 1
}

END {
  for (platform in required_platform) {
    for (metric in required_metric) {
      if (!(platform SUBSEP metric in seen)) {
        fail(platform " " metric, "missing release-build physical-device result")
      }
    }
  }

  if (row_count == 0) {
    fail("Results Log", "no performance benchmark result rows found")
  }

  if (failure_count > 0) {
    printf("Performance benchmark verification failed: %d row(s), %d failure(s)\n", row_count, failure_count) > "/dev/stderr"
    exit 1
  }

  printf("Performance benchmark verification passed: %d row(s)\n", row_count)
}
' "$benchmark_file"
