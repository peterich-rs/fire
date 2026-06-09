#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

tmp_dir="$(mktemp -d)"
failure_count=0

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  failure_count=$((failure_count + 1))
  printf 'FAIL: %s\n' "$1" >&2
  if [[ "${2:-}" != "" ]]; then
    printf '%s\n' "$2" >&2
  fi
}

expect_pass() {
  local label="$1"
  shift
  local output

  if output="$("$@" 2>&1)"; then
    pass "$label"
  else
    fail "$label" "$output"
  fi
}

expect_fail_contains() {
  local label="$1"
  local expected="$2"
  shift 2
  local output

  if output="$("$@" 2>&1)"; then
    fail "$label" "command unexpectedly passed"
    return
  fi

  if [[ "$output" == *"$expected"* ]]; then
    pass "$label"
  else
    fail "$label" "expected output to contain: $expected"$'\n'"actual output:"$'\n'"$output"
  fi
}

python3 - "$tmp_dir" <<'PY'
from pathlib import Path
import struct
import sys
import zlib

tmp = Path(sys.argv[1])

release_gates = [
    "App Store screenshots",
    "App Preview video",
    "Play Store screenshots",
    "Play Store feature graphic",
    "Maintainer/legal privacy review",
    "App Store Connect record",
    "Play Console record",
    "Internal testing builds",
    "Tester invites and feedback",
    "iOS release benchmarks",
    "Android release benchmarks",
    "Benchmark failure disposition",
    "VoiceOver audit",
    "TalkBack audit",
    "Dynamic Type / font-scale audit",
    "Reduce Motion / haptic audit",
    "High contrast / color-blindness audit",
    "Accessibility failure disposition",
]

internal_rows = [
    ("iOS", "App Store Connect record", "Store record entered"),
    ("Android", "Play Console record", "Store record entered"),
    ("iOS", "Internal testing build", "Build 42 commit abc1234 uploaded"),
    ("Android", "Internal testing build", "Build 42 commit abc1234 uploaded"),
    ("iOS", "Tester invites", "Group Core invited 2026-06-09"),
    ("Android", "Tester invites", "Group Core invited 2026-06-09"),
    ("iOS", "Feedback triage", "Blocker count 0; accepted risks none"),
    ("Android", "Feedback triage", "Blocker count 0; accepted risks none"),
]

privacy_areas = [
    "Privacy policy",
    "App Store privacy questionnaire",
    "Play Store Data Safety",
    "Android backup behavior",
    "Diagnostic export redaction",
    "iOS privacy manifests",
    "Third-party licenses",
    "Final publication approval",
]

metrics = [
    "Cold start to home visible",
    "Home feed scroll fluency",
    "Topic detail first screen",
    "Home feed memory",
    "Topic detail memory after 100 posts",
]

screens = [
    "Login and Cloudflare flow",
    "Home feed",
    "Category-filtered feed",
    "Topic detail",
    "Notifications",
    "Search",
    "Profile",
    "Bookmarks",
    "Drafts and composer",
    "Widgets",
    "Developer diagnostics, if exposed in the build",
]

audits = [
    "VoiceOver / TalkBack",
    "Dynamic Type / Font Scale",
    "Motion And Haptics",
    "Contrast And Color",
    "Keyboard And Switch Control",
]

def png_file(root: Path, path: str, width: int, height: int):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    raw = b"".join(b"\x00" + (b"\x00\x00\x00" * width) for _ in range(height))

    def chunk(kind: bytes, data: bytes):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    target.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )

def write_marketing(root: Path, include_feature_graphic=True):
    screenshots = [
        "native/ios-app/marketing/screenshots/iPhone6.5/final-phone.png",
        "native/ios-app/marketing/screenshots/iPhone5.5/final-phone.png",
        "native/ios-app/marketing/screenshots/iPad12.9/final-tablet.png",
        "native/ios-app/marketing/screenshots/iPad11/final-tablet.png",
        "native/android-app/marketing/screenshots/phone/final-phone.png",
        "native/android-app/marketing/screenshots/tablet7/final-tablet.png",
        "native/android-app/marketing/screenshots/tablet10/final-tablet.png",
    ]
    for screenshot in screenshots:
        png_file(root, screenshot, 320, 320)
    if include_feature_graphic:
        png_file(root, "native/android-app/marketing/feature-graphic.png", 1024, 500)
    preview = root / "native/ios-app/marketing/preview-video/app-preview.mp4"
    preview.parent.mkdir(parents=True, exist_ok=True)
    preview.write_bytes(b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42")

def write_release_gate(path: Path):
    lines = [
        "# Release Gate Evidence",
        "",
        "## Required Evidence",
        "",
        "| Gate | Evidence Required | Owner | Status | Evidence Link | Date | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, gate in enumerate(release_gates):
        lines.append(
            f"| {gate} | Required evidence | Release owner | Complete | "
            f"docs/release/evidence-{index}.md | 2026-06-09 | Completed release evidence |"
        )
    path.write_text("\n".join(lines) + "\n")

def write_internal(path: Path):
    lines = [
        "# Internal Testing Evidence",
        "",
        "## Required Evidence",
        "",
        "| Date | Platform | Gate | Owner | Status | Evidence Link | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, (platform, gate, note) in enumerate(internal_rows):
        lines.append(
            f"| 2026-06-09 | {platform} | {gate} | Release owner | Complete | "
            f"docs/release/internal-{index}.md | {note} |"
        )
    path.write_text("\n".join(lines) + "\n")

def write_privacy(path: Path):
    lines = [
        "# Privacy Review Evidence",
        "",
        "## Required Evidence",
        "",
        "| Date | Review Area | Reviewer | Status | Evidence Link | Notes |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for index, area in enumerate(privacy_areas):
        note = "Release publication approval complete" if area == "Final publication approval" else "Review complete"
        lines.append(
            f"| 2026-06-09 | {area} | Reviewer | Complete | "
            f"docs/release/privacy-{index}.md | {note} |"
        )
    path.write_text("\n".join(lines) + "\n")

def write_performance(path: Path, omit_last=False):
    lines = [
        "# Fire Performance Benchmarks",
        "",
        "## Results Log",
        "",
        "| Date | Commit | Platform | Device | Build Type | Metric | Result | Pass/Fail | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    entries = []
    for platform in ("iOS", "Android"):
        device = "iPhone 15 Pro" if platform == "iOS" else "Pixel 8 Pro"
        for metric in metrics:
            entries.append((platform, device, metric))
    if omit_last:
        entries.pop()
    for platform, device, metric in entries:
        lines.append(
            f"| 2026-06-09 | abc1234 | {platform} | {device} | Release archive | "
            f"{metric} | OK | Pass | Measured on release candidate |"
        )
    path.write_text("\n".join(lines) + "\n")

def write_accessibility(path: Path):
    lines = [
        "# Fire Accessibility Audit Checklist",
        "",
        "## Results Log",
        "",
        "| Date | Tester | Platform | Device | Screen | Result | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for platform in ("iOS", "Android"):
        device = "iPhone 15 Pro" if platform == "iOS" else "Pixel 8 Pro"
        for screen in screens + audits:
            lines.append(
                f"| 2026-06-09 | Tester | {platform} | {device} | {screen} | "
                f"Pass | Audited on release candidate |"
            )
    path.write_text("\n".join(lines) + "\n")

fixture = tmp / "fixture"
write_marketing(fixture / "marketing")
write_marketing(fixture / "marketing-missing-feature", include_feature_graphic=False)
write_performance(fixture / "performance.md")
write_performance(fixture / "performance-missing.md", omit_last=True)
write_accessibility(fixture / "accessibility.md")
write_internal(fixture / "internal.md")
write_privacy(fixture / "privacy.md")
write_release_gate(fixture / "release-gates.md")

roadmap = fixture / "checked-roadmap.md"
text = Path("docs/superpowers/specs/2026-06-08-fire-v2-roadmap-design.md").read_text()
text = text.replace("- [ ] App Store / Play Store 素材齐全", "- [x] App Store / Play Store 素材齐全", 1)
roadmap.write_text(text)
PY

fixture="$tmp_dir/fixture"
suite_env=(
  env
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing"
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance.md"
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md"
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md"
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md"
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md"
)

expect_pass "P4 release evidence suite accepts complete fixtures" \
  "${suite_env[@]}" scripts/verify-p4-release-evidence-suite.sh

expect_fail_contains "P4 release evidence suite rejects missing marketing asset" \
  "Play Store feature graphic" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing-missing-feature" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md" \
  scripts/verify-p4-release-evidence-suite.sh

expect_fail_contains "P4 release evidence suite rejects missing performance row" \
  "missing release-build physical-device result" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance-missing.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md" \
  scripts/verify-p4-release-evidence-suite.sh

expect_pass "roadmap P4 acceptance allows checked roadmap with complete fixture evidence" \
  "${suite_env[@]}" \
  scripts/verify-roadmap-p4-acceptance.sh \
  "$fixture/checked-roadmap.md" \
  "$fixture/release-gates.md"

expect_fail_contains "roadmap P4 acceptance rejects checked roadmap with missing lower-level evidence" \
  "P4 release evidence suite is incomplete" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance-missing.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  scripts/verify-roadmap-p4-acceptance.sh \
  "$fixture/checked-roadmap.md" \
  "$fixture/release-gates.md"

expect_pass "roadmap P4 acceptance allows unchecked production roadmap" \
  scripts/verify-roadmap-p4-acceptance.sh

if [[ "$failure_count" -gt 0 ]]; then
  printf 'Release verifier regression tests failed: %d failure(s)\n' "$failure_count" >&2
  exit 1
fi

printf 'Release verifier regression tests passed.\n'
