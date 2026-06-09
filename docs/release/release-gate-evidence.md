# Release Gate Evidence

This file is the evidence register for manual P4 release gates. Keep roadmap P4
acceptance unchecked until every required row has a completed evidence link,
reviewer, and date.

## Required Evidence

| Gate | Required Evidence | Owner | Status | Evidence Link | Date | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| App Store screenshots | Final screenshots captured from a release-candidate iOS build for all required device classes. | | Not started | | | Do not use mock screenshots; run `scripts/verify-marketing-assets.sh` before completion. |
| App Preview video | Explicit ship/no-ship decision, and final video asset if shipping one. | | Not started | | | Record decision even if no video ships; verifier accepts either no file or `preview-video/app-preview.mp4`. |
| Play Store screenshots | Final screenshots captured from a release-candidate Android build for phone, 7 inch tablet, and 10 inch tablet classes. | | Not started | | | Do not use mock screenshots; run `scripts/verify-marketing-assets.sh` before completion. |
| Play Store feature graphic | Approved 1024x500 feature graphic. | | Not started | | | Store-ready bitmap required; verifier enforces exact `1024x500` dimensions. |
| Maintainer/legal privacy review | Signed review of privacy policy, App Store privacy answers, Play Data Safety answers, backup behavior, diagnostic export redaction, and license inventory. | | Not started | | | Draft docs are not legal approval; record rows in `privacy-review-evidence.md` and include `scripts/verify-privacy-review-evidence.sh` output. |
| App Store Connect record | App record exists with bundle ID, pricing, category, privacy, and listing metadata entered. | | Not started | | | Link to App Store Connect record or checklist export; record iOS row in `internal-testing-evidence.md`. |
| Play Console record | App record exists with package name, data safety, content rating, store listing, and testing setup entered. | | Not started | | | Link to Play Console record or checklist export; record Android row in `internal-testing-evidence.md`. |
| Internal testing builds | Release-candidate iOS and Android builds uploaded to TestFlight / Play internal testing tracks. | | Not started | | | Include build numbers, commit SHA, and `scripts/verify-internal-testing-evidence.sh` output. |
| Tester invites and feedback | Tester groups invited and feedback reviewed. | | Not started | | | Link to collected feedback or triage summary; verifier requires invite and feedback triage rows. |
| iOS release benchmarks | Physical-device release-build measurements recorded in `performance-benchmarks.md`. | | Not started | | | Include device, OS, build type, commit SHA, and `scripts/verify-performance-benchmarks.sh` output. |
| Android release benchmarks | Physical-device release-build measurements recorded in `performance-benchmarks.md`. | | Not started | | | Include device, OS, build type, commit SHA, and `scripts/verify-performance-benchmarks.sh` output. |
| Benchmark failure disposition | Every threshold failure has a fixed, accepted, or no-ship decision. | | Not started | | | Required only if benchmark failures exist; verifier accepts explicit `Accepted` rows with notes. |
| VoiceOver audit | Full iOS release-candidate flow audited and results recorded in `accessibility-audit-checklist.md`. | | Not started | | | Include blocking issue links and `scripts/verify-accessibility-audit.sh` output. |
| TalkBack audit | Full Android release-candidate flow audited and results recorded in `accessibility-audit-checklist.md`. | | Not started | | | Include blocking issue links and `scripts/verify-accessibility-audit.sh` output. |
| Dynamic Type / font-scale audit | iOS Dynamic Type and Android font scale results recorded. | | Not started | | | Include largest supported accessibility sizes; verifier requires both platforms. |
| Reduce Motion / haptic audit | Motion and haptic behavior audited with accessibility settings enabled. | | Not started | | | Include any expected platform differences; verifier requires both platforms. |
| High contrast / color-blindness audit | Light, dark, OLED, high-contrast, and color-state checks recorded. | | Not started | | | Include contrast failures and remediation; verifier requires both platforms. |
| Accessibility failure disposition | Every blocking accessibility failure has a fixed, accepted, or no-ship decision. | | Not started | | | Required after the full accessibility audit pass; verifier accepts explicit `Accepted` rows with notes. |

## Evidence Rules

- Evidence links may point to files in this repository, store-console exports,
  issue trackers, test-run artifacts, or signed review notes. Use a well-formed
  HTTP(S) URL with a hostname or a safe repo-relative path to a non-empty local
  file; placeholder hosts such as localhost, `.local`, `.test`, and `.invalid`
  are rejected.
- Owner, evidence-link, and notes metadata must identify real release evidence;
  fake, mock, placeholder, dummy, synthetic, TODO/TBD, `example.com`,
  `not-real`, or `not real` markers are rejected.
- Keep exactly one row for every required gate in the table above. Do not rename,
  add, or remove gate rows; `scripts/verify-release-gates.sh` treats the exact
  gate names as the release-readiness contract.
- `Date` must be a real calendar date in `YYYY-MM-DD` form.
- Rows with missing or extra Markdown table columns are rejected; keep the exact
  table shape and escape literal `|` characters in cell text.
- Record only release-candidate evidence. Simulator and emulator smoke runs may
  be linked as supporting context, but they do not satisfy physical-device gates.
- If a gate is intentionally waived, set `Status` to `Accepted`, link the
  decision, and include the approver and reason in `Notes`. The verifier rejects
  vague accepted-waiver notes that do not explicitly describe approval/waiver
  context and a reason, risk, exception, or no-ship decision. Use a clear shape
  such as `Approved by <owner>; reason: <decision>`.
- Do not replace this register with prose-only status updates. The table is the
  source of truth for manual P4 gate closure.
