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

def write_marketing(root: Path, include_feature_graphic=True, mutation="valid"):
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

    if mutation == "fake-filename":
        png_file(root, "native/android-app/marketing/screenshots/phone/not-real-phone.png", 320, 320)
    elif mutation == "tiny-screenshot":
        png_file(root, "native/android-app/marketing/screenshots/phone/final-phone.png", 319, 319)
    elif mutation == "malformed-png":
        target = root / "native/android-app/marketing/screenshots/phone/final-phone.png"
        target.write_bytes(
            b"\x89PNG\r\n\x1a\n"
            + struct.pack(">I", 13)
            + b"IHDR"
            + struct.pack(">II", 320, 320)
            + b"\x08\x02\x00\x00\x00"
            + b"\x00\x00\x00\x00"
        )
    elif mutation == "invalid-mp4":
        preview.write_bytes(b"not an mp4")

def write_release_gate(
    path: Path,
    marker="",
    accepted_note=None,
    missing_local_link=False,
    placeholder_url=False,
):
    lines = [
        "# Release Gate Evidence",
        "",
        "## Required Evidence",
        "",
        "| Gate | Evidence Required | Owner | Status | Evidence Link | Date | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, gate in enumerate(release_gates):
        note = "Completed release evidence"
        status = "Complete"
        if index == 0 and accepted_note:
            note = accepted_note
            status = "Accepted"
        if index == 0 and marker:
            note += f" {marker}"
        link = (
            "docs/release/missing-evidence.md"
            if missing_local_link and index == 0
            else "https://evidence.local/release-0"
            if placeholder_url and index == 0
            else f"https://github.com/peterich-rs/fire/issues/{1000 + index}"
        )
        lines.append(
            f"| {gate} | Required evidence | Release owner | {status} | "
            f"{link} | 2026-06-09 | {note} |"
        )
    path.write_text("\n".join(lines) + "\n")

def write_internal(
    path: Path,
    marker="",
    accepted_note=None,
    weak_build_note=False,
    weak_invite_note=False,
    weak_feedback_note=False,
    missing_local_link=False,
    placeholder_url=False,
):
    lines = [
        "# Internal Testing Evidence",
        "",
        "## Required Evidence",
        "",
        "| Date | Platform | Gate | Owner | Status | Evidence Link | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, (platform, gate, note) in enumerate(internal_rows):
        status = "Complete"
        if index == 0 and accepted_note:
            note = accepted_note
            status = "Accepted"
        if platform == "iOS" and gate == "Internal testing build" and weak_build_note:
            note = "Build pending commit unknown"
        if platform == "iOS" and gate == "Tester invites" and weak_invite_note:
            note = "Group Core invite pending"
        if platform == "iOS" and gate == "Feedback triage" and weak_feedback_note:
            note = "Blockers reviewed; accepted risks follow-up"
        if index == 0 and marker:
            note += f" {marker}"
        link = (
            "docs/release/missing-internal-evidence.md"
            if missing_local_link and index == 0
            else "https://localhost/internal-0"
            if placeholder_url and index == 0
            else f"https://github.com/peterich-rs/fire/issues/{2000 + index}"
        )
        lines.append(
            f"| 2026-06-09 | {platform} | {gate} | Release owner | {status} | "
            f"{link} | {note} |"
        )
    path.write_text("\n".join(lines) + "\n")

def write_privacy(
    path: Path,
    marker="",
    accepted_note=None,
    final_note=None,
    missing_local_link=False,
    placeholder_url=False,
):
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
        status = "Complete"
        if index == 0 and accepted_note:
            note = accepted_note
            status = "Accepted"
        if area == "Final publication approval" and final_note:
            note = final_note
        if index == 0 and marker:
            note += f" {marker}"
        link = (
            "docs/release/missing-privacy-evidence.md"
            if missing_local_link and index == 0
            else "https://review.invalid/privacy-0"
            if placeholder_url and index == 0
            else f"https://github.com/peterich-rs/fire/issues/{3000 + index}"
        )
        lines.append(
            f"| 2026-06-09 | {area} | Reviewer | {status} | "
            f"{link} | {note} |"
        )
    path.write_text("\n".join(lines) + "\n")

def performance_result(metric: str) -> str:
    return {
        "Cold start to home visible": "2.4s",
        "Home feed scroll fluency": "59 fps, 1% janky frames",
        "Topic detail first screen": "1.6s",
        "Home feed memory": "180 MB",
        "Topic detail memory after 100 posts": "320 MB",
    }[metric]

def write_performance(
    path: Path,
    omit_last=False,
    marker="",
    accepted_note=None,
    invalid_result=False,
    target_miss=False,
):
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
    for index, (platform, device, metric) in enumerate(entries):
        note = "Measured on release candidate"
        status = "Pass"
        result = "OK" if invalid_result and index == 0 else performance_result(metric)
        if target_miss and index == 0:
            result = "3.5s"
        if index == 0 and accepted_note:
            note = accepted_note
            status = "Accepted"
            result = "5.2s"
        if index == 0 and marker:
            note += f" {marker}"
        lines.append(
            f"| 2026-06-09 | abc1234 | {platform} | {device} | Release archive | "
            f"{metric} | {result} | {status} | {note} |"
        )
    path.write_text("\n".join(lines) + "\n")

def write_accessibility(path: Path, marker="", accepted_note=None):
    lines = [
        "# Fire Accessibility Audit Checklist",
        "",
        "## Results Log",
        "",
        "| Date | Tester | Platform | Device | Screen | Result | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    row_index = 0
    for platform in ("iOS", "Android"):
        device = "iPhone 15 Pro" if platform == "iOS" else "Pixel 8 Pro"
        for screen in screens + audits:
            note = "Audited on release candidate"
            result = "Pass"
            if row_index == 0 and accepted_note:
                note = accepted_note
                result = "Accepted"
            if row_index == 0 and marker:
                note += f" {marker}"
            lines.append(
                f"| 2026-06-09 | Tester | {platform} | {device} | {screen} | "
                f"{result} | {note} |"
            )
            row_index += 1
    path.write_text("\n".join(lines) + "\n")

fixture = tmp / "fixture"
write_marketing(fixture / "marketing")
write_marketing(fixture / "marketing-missing-feature", include_feature_graphic=False)
write_marketing(fixture / "marketing-fake-filename", mutation="fake-filename")
write_marketing(fixture / "marketing-tiny-screenshot", mutation="tiny-screenshot")
write_marketing(fixture / "marketing-malformed-png", mutation="malformed-png")
write_marketing(fixture / "marketing-invalid-mp4", mutation="invalid-mp4")
write_performance(fixture / "performance.md")
write_performance(
    fixture / "performance-accepted-valid.md",
    accepted_note="Approved by performance owner; reason: no-ship decision documented for threshold risk.",
)
write_performance(
    fixture / "performance-accepted-weak.md",
    accepted_note="Accepted risk.",
)
write_performance(fixture / "performance-missing.md", omit_last=True)
write_performance(fixture / "performance-invalid-result.md", invalid_result=True)
write_performance(fixture / "performance-target-miss-pass.md", target_miss=True)
write_performance(fixture / "performance-not-real.md", marker="not-real")
write_performance(fixture / "performance-not-real-space.md", marker="not real")
write_accessibility(fixture / "accessibility.md")
write_accessibility(
    fixture / "accessibility-accepted-valid.md",
    accepted_note="Approved by accessibility owner; reason: exception accepted with tracked follow-up risk.",
)
write_accessibility(
    fixture / "accessibility-accepted-weak.md",
    accepted_note="Accepted risk.",
)
write_accessibility(fixture / "accessibility-not-real.md", marker="not-real")
write_accessibility(fixture / "accessibility-not-real-space.md", marker="not real")
write_internal(fixture / "internal.md")
write_internal(
    fixture / "internal-accepted-valid.md",
    accepted_note="Approved by release owner; reason: store-record exception accepted before final rollout.",
)
write_internal(
    fixture / "internal-accepted-weak.md",
    accepted_note="Accepted risk.",
)
write_internal(fixture / "internal-weak-build.md", weak_build_note=True)
write_internal(fixture / "internal-weak-invite.md", weak_invite_note=True)
write_internal(fixture / "internal-weak-feedback.md", weak_feedback_note=True)
write_internal(fixture / "internal-missing-link.md", missing_local_link=True)
write_internal(fixture / "internal-placeholder-url.md", placeholder_url=True)
write_internal(fixture / "internal-not-real.md", marker="not-real")
write_internal(fixture / "internal-not-real-space.md", marker="not real")
write_privacy(fixture / "privacy.md")
write_privacy(
    fixture / "privacy-accepted-valid.md",
    accepted_note="Approved by privacy reviewer; reason: waiver accepted with documented exception.",
)
write_privacy(
    fixture / "privacy-accepted-weak.md",
    accepted_note="Accepted risk.",
)
write_privacy(
    fixture / "privacy-final-approval-weak.md",
    final_note="Release notes prepared.",
)
write_privacy(fixture / "privacy-missing-link.md", missing_local_link=True)
write_privacy(fixture / "privacy-placeholder-url.md", placeholder_url=True)
write_privacy(fixture / "privacy-not-real.md", marker="not-real")
write_privacy(fixture / "privacy-not-real-space.md", marker="not real")
write_release_gate(fixture / "release-gates.md")
write_release_gate(
    fixture / "release-gates-accepted-valid.md",
    accepted_note="Approved by release owner; reason: no-ship decision for optional app preview.",
)
write_release_gate(
    fixture / "release-gates-accepted-weak.md",
    accepted_note="Accepted risk.",
)
write_release_gate(fixture / "release-gates-missing-link.md", missing_local_link=True)
write_release_gate(fixture / "release-gates-placeholder-url.md", placeholder_url=True)
write_release_gate(fixture / "release-gates-not-real.md", marker="not-real")
write_release_gate(fixture / "release-gates-not-real-space.md", marker="not real")

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

expect_pass "release readiness accepts complete fixture evidence" \
  "${suite_env[@]}" scripts/verify-release-readiness.sh

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

expect_fail_contains "release readiness rejects missing lower-level fixture evidence" \
  "Release readiness verification failed" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing-missing-feature" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md" \
  scripts/verify-release-readiness.sh

expect_fail_contains "P4 release evidence suite rejects fake marketing filename" \
  "asset filename must not contain" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing-fake-filename" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md" \
  scripts/verify-p4-release-evidence-suite.sh

expect_fail_contains "P4 release evidence suite rejects tiny screenshots" \
  "expected dimensions of at least 320px on each side" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing-tiny-screenshot" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md" \
  scripts/verify-p4-release-evidence-suite.sh

expect_fail_contains "P4 release evidence suite rejects malformed PNGs" \
  "could not read PNG or JPEG dimensions" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing-malformed-png" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md" \
  scripts/verify-p4-release-evidence-suite.sh

expect_fail_contains "P4 release evidence suite rejects invalid MP4 previews" \
  "MP4 file must contain an ftyp box" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing-invalid-mp4" \
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

expect_fail_contains "P4 release evidence suite rejects non-measurement performance result" \
  "result must include a numeric duration" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance-invalid-result.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md" \
  scripts/verify-p4-release-evidence-suite.sh

expect_fail_contains "P4 release evidence suite rejects target miss marked pass" \
  "Pass status requires a measured result inside the release target" \
  env \
  "FIRE_MARKETING_ASSETS_ROOT=$fixture/marketing" \
  "FIRE_PERFORMANCE_BENCHMARK_FILE=$fixture/performance-target-miss-pass.md" \
  "FIRE_ACCESSIBILITY_AUDIT_FILE=$fixture/accessibility.md" \
  "FIRE_INTERNAL_TESTING_EVIDENCE_FILE=$fixture/internal.md" \
  "FIRE_PRIVACY_REVIEW_EVIDENCE_FILE=$fixture/privacy.md" \
  "FIRE_RELEASE_GATE_EVIDENCE_FILE=$fixture/release-gates.md" \
  scripts/verify-p4-release-evidence-suite.sh

marker_failure="not-real, or not real markers"

expect_pass "release gates accept explicit waiver metadata" \
  scripts/verify-release-gates.sh "$fixture/release-gates-accepted-valid.md"

expect_fail_contains "release gates reject weak accepted waiver notes" \
  "accepted waivers require approver and reason in notes" \
  scripts/verify-release-gates.sh "$fixture/release-gates-accepted-weak.md"
expect_fail_contains "release gates reject missing local evidence path" \
  "evidence link path must exist and be non-empty" \
  scripts/verify-release-gates.sh "$fixture/release-gates-missing-link.md"
expect_fail_contains "release gates reject placeholder evidence URL host" "$marker_failure" \
  scripts/verify-release-gates.sh "$fixture/release-gates-placeholder-url.md"

expect_fail_contains "release gates reject not-real marker" "$marker_failure" \
  scripts/verify-release-gates.sh "$fixture/release-gates-not-real.md"
expect_fail_contains "release gates reject not real marker" "$marker_failure" \
  scripts/verify-release-gates.sh "$fixture/release-gates-not-real-space.md"

expect_fail_contains "internal testing rejects not-real marker" "$marker_failure" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-not-real.md"
expect_fail_contains "internal testing rejects not real marker" "$marker_failure" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-not-real-space.md"

expect_pass "internal testing accepts explicit waiver metadata" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-accepted-valid.md"
expect_fail_contains "internal testing rejects weak accepted waiver notes" \
  "accepted rows require approver and reason in notes" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-accepted-weak.md"
expect_fail_contains "internal testing rejects weak build metadata" \
  "internal testing build notes must include build number" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-weak-build.md"
expect_fail_contains "internal testing rejects missing invite date" \
  "tester invite notes must include invite date" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-weak-invite.md"
expect_fail_contains "internal testing rejects weak feedback triage" \
  "feedback triage notes must summarize blocker count" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-weak-feedback.md"
expect_fail_contains "internal testing rejects missing local evidence path" \
  "evidence link path must exist and be non-empty" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-missing-link.md"
expect_fail_contains "internal testing rejects placeholder evidence URL host" "$marker_failure" \
  scripts/verify-internal-testing-evidence.sh "$fixture/internal-placeholder-url.md"

expect_fail_contains "privacy review rejects not-real marker" "$marker_failure" \
  scripts/verify-privacy-review-evidence.sh "$fixture/privacy-not-real.md"
expect_fail_contains "privacy review rejects not real marker" "$marker_failure" \
  scripts/verify-privacy-review-evidence.sh "$fixture/privacy-not-real-space.md"

expect_pass "privacy review accepts explicit waiver metadata" \
  scripts/verify-privacy-review-evidence.sh "$fixture/privacy-accepted-valid.md"
expect_fail_contains "privacy review rejects weak accepted waiver notes" \
  "accepted rows require approver and waiver reason in notes" \
  scripts/verify-privacy-review-evidence.sh "$fixture/privacy-accepted-weak.md"
expect_fail_contains "privacy review rejects weak final publication approval notes" \
  "final publication approval notes must mention approval to publish, release, or submit" \
  scripts/verify-privacy-review-evidence.sh "$fixture/privacy-final-approval-weak.md"
expect_fail_contains "privacy review rejects missing local evidence path" \
  "evidence link path must exist and be non-empty" \
  scripts/verify-privacy-review-evidence.sh "$fixture/privacy-missing-link.md"
expect_fail_contains "privacy review rejects placeholder evidence URL host" "$marker_failure" \
  scripts/verify-privacy-review-evidence.sh "$fixture/privacy-placeholder-url.md"

expect_fail_contains "performance rejects not-real marker" "$marker_failure" \
  scripts/verify-performance-benchmarks.sh "$fixture/performance-not-real.md"
expect_fail_contains "performance rejects not real marker" "$marker_failure" \
  scripts/verify-performance-benchmarks.sh "$fixture/performance-not-real-space.md"

expect_pass "performance accepts explicit waiver metadata" \
  scripts/verify-performance-benchmarks.sh "$fixture/performance-accepted-valid.md"
expect_fail_contains "performance rejects weak accepted waiver notes" \
  "accepted threshold waivers require approver and reason in notes" \
  scripts/verify-performance-benchmarks.sh "$fixture/performance-accepted-weak.md"

expect_fail_contains "accessibility rejects not-real marker" "$marker_failure" \
  scripts/verify-accessibility-audit.sh "$fixture/accessibility-not-real.md"
expect_fail_contains "accessibility rejects not real marker" "$marker_failure" \
  scripts/verify-accessibility-audit.sh "$fixture/accessibility-not-real-space.md"

expect_pass "accessibility accepts explicit waiver metadata" \
  scripts/verify-accessibility-audit.sh "$fixture/accessibility-accepted-valid.md"
expect_fail_contains "accessibility rejects weak accepted waiver notes" \
  "accepted accessibility waivers require approver and reason in notes" \
  scripts/verify-accessibility-audit.sh "$fixture/accessibility-accepted-weak.md"

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
