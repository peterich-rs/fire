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
| Maintainer/legal privacy review | Signed review of privacy policy, App Store privacy answers, Play Data Safety answers, backup behavior, diagnostic export redaction, and license inventory. | | Not started | | | Draft docs are not legal approval. |
| App Store Connect record | App record exists with bundle ID, pricing, category, privacy, and listing metadata entered. | | Not started | | | Link to App Store Connect record or checklist export. |
| Play Console record | App record exists with package name, data safety, content rating, store listing, and testing setup entered. | | Not started | | | Link to Play Console record or checklist export. |
| Internal testing builds | Release-candidate iOS and Android builds uploaded to TestFlight / Play internal testing tracks. | | Not started | | | Include build numbers and commit SHA. |
| Tester invites and feedback | Tester groups invited and feedback reviewed. | | Not started | | | Link to collected feedback or triage summary. |
| iOS release benchmarks | Physical-device release-build measurements recorded in `performance-benchmarks.md`. | | Not started | | | Include device, OS, build type, and commit SHA. |
| Android release benchmarks | Physical-device release-build measurements recorded in `performance-benchmarks.md`. | | Not started | | | Include device, OS, build type, and commit SHA. |
| Benchmark failure disposition | Every threshold failure has a fixed, accepted, or no-ship decision. | | Not started | | | Required only if benchmark failures exist. |
| VoiceOver audit | Full iOS release-candidate flow audited and results recorded in `accessibility-audit-checklist.md`. | | Not started | | | Include blocking issue links. |
| TalkBack audit | Full Android release-candidate flow audited and results recorded in `accessibility-audit-checklist.md`. | | Not started | | | Include blocking issue links. |
| Dynamic Type / font-scale audit | iOS Dynamic Type and Android font scale results recorded. | | Not started | | | Include largest supported accessibility sizes. |
| Reduce Motion / haptic audit | Motion and haptic behavior audited with accessibility settings enabled. | | Not started | | | Include any expected platform differences. |
| High contrast / color-blindness audit | Light, dark, OLED, high-contrast, and color-state checks recorded. | | Not started | | | Include contrast failures and remediation. |
| Accessibility failure disposition | Every blocking accessibility failure has a fixed, accepted, or no-ship decision. | | Not started | | | Required after the full accessibility audit pass. |

## Evidence Rules

- Evidence links may point to files in this repository, store-console exports,
  issue trackers, test-run artifacts, or signed review notes.
- Record only release-candidate evidence. Simulator and emulator smoke runs may
  be linked as supporting context, but they do not satisfy physical-device gates.
- If a gate is intentionally waived, set `Status` to `Accepted`, link the
  decision, and include the approver and reason in `Notes`.
- Do not replace this register with prose-only status updates. The table is the
  source of truth for manual P4 gate closure.
