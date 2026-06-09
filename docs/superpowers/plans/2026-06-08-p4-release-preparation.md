# Prepare Fire Release Materials

> **For agentic workers:** Use this plan as the P4 release-preparation source of truth. Checkbox state tracks repository artifacts only; store-console actions, real screenshots/videos, legal review, device benchmarks, and accessibility audits remain manual gates.

## Feasibility Assessment

P4 is process-heavy and does not require changes to the Rust/native architecture. The repository can hold listing drafts, privacy/data-safety drafts, benchmark scripts, accessibility checklists, license inventories, and marketing asset folders now. Final App Store / Play Store readiness still requires human store access and real-device validation. Feasible with caveats: repository scaffolding is complete, but release acceptance remains blocked on manual evidence.

## Current Surface Inventory

- `docs/release/` -- release copy, compliance drafts, testing guides, benchmark definitions, accessibility checklist, release-gate evidence register, and license inventory.
- `native/ios-app/marketing/` -- App Store screenshot and preview-video folder structure.
- `native/android-app/marketing/` -- Play Store screenshot and feature-graphic folder structure.
- `scripts/ios/archive_release.sh` -- existing iOS archive/upload path used by the TestFlight guide.
- `scripts/ios/verify_xcode26_toolchain.sh` -- existing App Store Connect toolchain guard used before iOS uploads.
- `scripts/collect-licenses.sh` -- generated third-party dependency inventory.
- `scripts/verify-marketing-assets.sh` -- store marketing asset verifier for final screenshots, optional App Preview file placement, and Play feature-graphic dimensions.
- `scripts/verify-performance-benchmarks.sh` -- release benchmark evidence verifier for physical-device iOS and Android result rows.
- `scripts/verify-accessibility-audit.sh` -- release accessibility evidence verifier for physical-device iOS and Android screen/audit rows.
- `scripts/verify-internal-testing-evidence.sh` -- internal testing evidence verifier for store records, uploaded builds, tester invites, and feedback triage.
- `scripts/verify-privacy-review-evidence.sh` -- maintainer/legal privacy review evidence verifier.
- `scripts/verify-p4-release-evidence-suite.sh` -- shared non-recursive P4 evidence verifier for store media, performance, accessibility, internal testing, privacy review, and release-gate evidence.
- `scripts/verify-release-readiness.sh` -- composite P4 release-readiness verifier that runs the shared P4 evidence suite and roadmap guards.
- `scripts/verify-release-gates.sh` -- release-gate evidence verifier for the exact required manual gate set.
- `scripts/verify-roadmap-plan-contract.sh` -- roadmap document contract verifier for the one-spec/four-plan task counts.
- `scripts/verify-roadmap-architecture-constraints.sh` -- roadmap architecture/platform-boundary verifier for minimum APIs, native runtime paths, and reference boundaries.
- `scripts/verify-roadmap-implementation-evidence.sh` -- checked P1-P3 roadmap implementation evidence verifier.
- `scripts/verify-roadmap-p4-acceptance.sh` -- roadmap P4 acceptance verifier that keeps checked boxes tied to the shared P4 evidence suite.
- `scripts/test-release-verifiers.sh` -- temporary-fixture regression tests for release-readiness wrapper wiring, release evidence parsers, fake-evidence markers, marketing asset validation, and checked P4 acceptance guards.
- `scripts/benchmark-*.sh` -- benchmark workflows for cold start, scroll fluency, topic load, and memory.
- `native/android-app/src/main/AndroidManifest.xml` -- Android backup is release-disabled with `allowBackup="false"`.
- `native/android-app/src/main/res/xml/backup_rules.xml` -- all-exclude Android Auto Backup rules.
- `native/android-app/src/main/res/xml/data_extraction_rules.xml` -- all-exclude Android cloud-backup and device-transfer rules.
- `native/ios-app/Configs/PrivacyInfo.xcprivacy` -- app privacy manifest with required-reason API declarations.
- `native/ios-app/Configs/FireWidget/PrivacyInfo.xcprivacy` -- widget extension privacy manifest with required-reason API declarations.
- `native/ios-app/Sources/FireAppSession/APM/FireAPMManager.swift` -- local PLCrashReporter / MetricKit diagnostic behavior.
- `native/ios-app/App/DeveloperTools/FirePushDiagnosticsView.swift` -- APNs token is local-only at this stage.
- `native/android-app/src/main/java/com/fire/app/push/FireFirebaseMessagingService.kt` -- FCM token registration API is not available; payloads are local notification input.
- `rust/crates/fire-core/tests/session_flow.rs` -- verifies that redacted session export strips auth cookies while preserving bootstrap context.

## Design

### Key Design Decisions

1. **Version release source material, not fake final media.** The repo now includes marketing directories and `.gitkeep` placeholders, but no fabricated screenshots, preview videos, or feature graphics. Real assets must come from release-candidate builds.
2. **Keep privacy drafts conservative.** Privacy documents state local diagnostics, widget snapshots, offline cache, local push token handling, Android backup exclusion, privacy-manifest coverage, and redacted-export behavior without overclaiming legal review.
3. **Make benchmark scripts honest about prerequisites.** Android scripts use `adb` when available; iOS scripts print required Instruments/xctrace workflows because reliable iOS FPS/memory/topic measurements require device tooling.
4. **Generate license inventory from current declarations.** `scripts/collect-licenses.sh` uses `cargo metadata --locked` for Rust crate license fields and resolves Android `releaseRuntimeClasspath` with Gradle before reading Maven POM license metadata. Full legal review and Swift package license-text review remain required.
5. **Separate repository completion from release acceptance.** P4 acceptance boxes in the roadmap remain unchecked until real store/test/performance/accessibility evidence exists.
6. **Keep manual gate evidence centralized.** `docs/release/release-gate-evidence.md` is the register for screenshots, store records, legal signoff, release-build benchmarks, accessibility audit runs, and any accepted waivers. It does not satisfy those gates by itself.
7. **Make the final release gate fail closed.** `scripts/verify-release-gates.sh` checks the evidence register and fails until the exact required gate rows are present once, with no unknown rows, and every row has an accepted/completed status, owner, evidence link, and real calendar date. `Accepted` release-gate waivers must include explicit approval/waiver context plus a reason in notes, such as `Approved by ...; reason: ...`. Evidence links must be well-formed HTTP(S) URLs with valid hostnames or safe repo-relative paths to non-empty local files, not directories, and malformed URLs, malformed URL hosts, or placeholder URL hosts are rejected. Manual evidence verifiers reject completed or accepted rows that still contain fake/mock/placeholder-style markers in completion metadata such as owner, reviewer, tester, device, result, evidence link, or notes, and reject missing or extra Markdown table columns; literal pipe characters must be escaped in cells. Current failure is expected because manual gates are still open.
8. **Make store-media structure checkable before evidence closure.** `scripts/verify-marketing-assets.sh` validates that required screenshot buckets contain real PNG/JPEG files with readable dimensions, final asset filenames do not carry fake/mock/placeholder-style markers, screenshots are at least 320px on each side, PNG screenshots are not single-color placeholders, screenshot buckets do not contain nested directories or alternate asset paths, the optional App Preview path is unambiguous and contains MP4 `ftyp` content when present, and the Play feature graphic is PNG content with exact `1024x500` dimensions and non-flat pixels. The script is expected to fail until final release-candidate media exists.
9. **Make benchmark evidence complete by metric and platform.** `scripts/verify-performance-benchmarks.sh` checks `performance-benchmarks.md` for exactly one iOS row and exactly one Android release-build physical-device row for every target metric, requires metric-bound numeric result units, rejects ambiguous multi-value memory results unless the peak value is labeled, treats the highest labeled peak memory value as authoritative, and fails until threshold failures are fixed or explicitly accepted with approval/waiver context plus a reason in notes.
10. **Make accessibility evidence complete by screen and audit area.** `scripts/verify-accessibility-audit.sh` checks `accessibility-audit-checklist.md` for exactly one iOS row and exactly one Android physical-device row covering every listed screen and audit category, and fails until blocking failures are fixed or explicitly accepted with explicit approval/waiver context plus a reason in notes.
11. **Make testing-track evidence explicit.** `docs/release/internal-testing-evidence.md` records App Store Connect / Play Console records, release-candidate uploads, tester invites, and feedback triage. `scripts/verify-internal-testing-evidence.sh` fails until all required platform rows are complete and non-duplicated, requires evidence links to be URLs or existing local files, requires build numbers, commit SHAs, invite dates, and numeric blocker counts, and requires accepted rows to include explicit approval/waiver context plus a reason in notes.
12. **Make privacy review evidence explicit.** `docs/release/privacy-review-evidence.md` records maintainer/legal review of the privacy policy, store answers, backup behavior, diagnostic redaction, privacy manifests, license inventory, and final publication approval. `scripts/verify-privacy-review-evidence.sh` fails until all required review rows are complete and non-duplicated, requires evidence links to be URLs or existing local files, requires final publication approval wording, and requires accepted rows to include explicit approval/waiver context plus a reason in notes.
13. **Make final readiness one command.** `scripts/verify-release-readiness.sh` runs the shared P4 release evidence suite, roadmap plan contract, roadmap architecture constraints, roadmap implementation evidence, and roadmap P4 acceptance verifiers together. It does not replace any underlying gate; it fails until every lower-level verifier passes.
14. **Keep the roadmap document contract checkable.** `scripts/verify-roadmap-plan-contract.sh` verifies the one design spec and four implementation plans stay present with P1/P2/P3/P4 top-level task counts of 17/14/15/6.
15. **Keep architecture constraints evidence-bound.** `scripts/verify-roadmap-architecture-constraints.sh` checks the platform/Rust ownership split, minimum API targets, iOS topic-detail native runtime path, and reference/infrastructure repository boundaries.
16. **Keep checked implementation acceptance evidence-bound.** `scripts/verify-roadmap-implementation-evidence.sh` checks concrete code files, symbols, scoped cleanup patterns, and size limits that support the checked P1-P3 acceptance rows.
17. **Keep roadmap P4 acceptance evidence-bound.** `scripts/verify-roadmap-p4-acceptance.sh` checks the exact P4 acceptance rows in the design document and fails if any box is checked before the shared P4 evidence suite passes.

## Phased Implementation

### Task 1: Store Listing Drafts And Marketing Structure

**Files:**
- `docs/release/app-store-description.md`
- `docs/release/play-store-description.md`
- `native/ios-app/marketing/README.md`
- `native/ios-app/marketing/screenshots/iPhone6.5/.gitkeep`
- `native/ios-app/marketing/screenshots/iPhone5.5/.gitkeep`
- `native/ios-app/marketing/screenshots/iPad12.9/.gitkeep`
- `native/ios-app/marketing/screenshots/iPad11/.gitkeep`
- `native/ios-app/marketing/preview-video/.gitkeep`
- `native/android-app/marketing/README.md`
- `native/android-app/marketing/screenshots/phone/.gitkeep`
- `native/android-app/marketing/screenshots/tablet7/.gitkeep`
- `native/android-app/marketing/screenshots/tablet10/.gitkeep`
- `scripts/verify-marketing-assets.sh`

- [x] Create App Store and Play Store listing drafts.
- [x] Create iOS and Android marketing asset folder structures.
- [x] Document that real release-candidate media is still required.
- [x] Add a store marketing asset verifier that fails until final assets exist.
- [ ] Capture and validate final App Store screenshots.
- [ ] Capture or decide not to ship an App Preview video.
- [ ] Capture and validate final Play Store screenshots.
- [ ] Create and approve the Play Store 1024x500 feature graphic.

### Task 2: Privacy, Data Safety, And Licenses

**Files:**
- `docs/release/privacy-policy.md`
- `docs/release/app-store-data-collection.md`
- `docs/release/play-store-data-safety.md`
- `docs/release/third-party-licenses.md`
- `docs/release/privacy-review-evidence.md`
- `scripts/collect-licenses.sh`
- `scripts/verify-privacy-review-evidence.sh`
- `native/android-app/src/main/AndroidManifest.xml`
- `native/android-app/src/main/res/xml/backup_rules.xml`
- `native/android-app/src/main/res/xml/data_extraction_rules.xml`
- `native/ios-app/Configs/PrivacyInfo.xcprivacy`
- `native/ios-app/Configs/FireWidget/PrivacyInfo.xcprivacy`
- `native/ios-app/project.yml`
- `rust/crates/fire-core/src/core/persistence.rs`
- `rust/crates/fire-core/src/session_store.rs`
- `rust/crates/fire-core/tests/session_flow.rs`

- [x] Create privacy policy draft aligned with current code facts.
- [x] Create App Store privacy questionnaire draft.
- [x] Create Play Store Data Safety draft.
- [x] Add license collection script.
- [x] Generate current third-party dependency inventory.
- [x] Generate Rust crate license names from `cargo metadata --locked`.
- [x] Verify Android transitive license metadata with Gradle tooling.
- [x] Add a maintainer/legal privacy review evidence log and verifier.
- [ ] Complete maintainer/legal privacy review.
- [x] Decide Android `allowBackup` release behavior and update docs/store answers.
- [x] Add iOS app and widget privacy manifests with required-reason API declarations.
- [x] Fix redacted session export before any public diagnostic workflow claims redaction.

### Task 3: Internal Testing Guides And Readiness Guards

**Files:**
- `docs/release/testflight-setup.md`
- `docs/release/play-store-testing-setup.md`
- `docs/release/internal-testing-evidence.md`
- `docs/release/test-feedback-template.md`
- `docs/release/release-gate-evidence.md`
- `scripts/verify-internal-testing-evidence.sh`
- `scripts/verify-release-gates.sh`
- `scripts/verify-release-readiness.sh`
- `scripts/verify-p4-release-evidence-suite.sh`
- `scripts/verify-roadmap-plan-contract.sh`
- `scripts/verify-roadmap-architecture-constraints.sh`
- `scripts/verify-roadmap-implementation-evidence.sh`
- `scripts/verify-roadmap-p4-acceptance.sh`
- `scripts/test-release-verifiers.sh`

- [x] Document TestFlight build/upload flow using existing iOS release scripts.
- [x] Document Play Store internal/closed/open testing setup.
- [x] Add a tester feedback template.
- [x] Add a release-gate evidence register for manual P4 gates.
- [x] Add a verifier that fails until manual gate evidence is complete.
- [x] Add an internal testing evidence log and verifier for store/test-track gates.
- [x] Add a composite release-readiness verifier that runs every P4 guard.
- [x] Add a roadmap plan contract verifier for the one-spec/four-plan task counts.
- [x] Add a roadmap architecture constraints verifier for platform/Rust ownership, minimum APIs, topic-detail native runtime paths, and reference boundaries.
- [x] Add a roadmap implementation evidence verifier for checked P1-P3 acceptance rows.
- [x] Add a roadmap P4 acceptance verifier that blocks premature checkbox closure.
- [ ] Create App Store Connect app record.
- [ ] Create Play Console app record.
- [ ] Upload release-candidate builds to internal testing tracks.
- [ ] Invite testers and collect feedback.

### Task 4: Performance Regression Gates

**Files:**
- `docs/release/performance-benchmarks.md`
- `scripts/benchmark-cold-start.sh`
- `scripts/benchmark-scroll-fps.sh`
- `scripts/benchmark-topic-load.sh`
- `scripts/benchmark-memory-peak.sh`
- `scripts/verify-performance-benchmarks.sh`

- [x] Define release benchmark targets and failure thresholds.
- [x] Add Android `adb` benchmark workflows.
- [x] Add iOS measurement workflows for Instruments/xctrace.
- [x] Add a performance benchmark evidence verifier that fails until final physical-device results exist.
- [ ] Record release-build iOS measurements on a physical device.
- [ ] Record release-build Android measurements on a physical device.
- [ ] Resolve or explicitly accept any threshold failures.

### Task 5: Accessibility Audit

**Files:**
- `docs/release/accessibility-audit-checklist.md`
- `scripts/verify-accessibility-audit.sh`

- [x] Add a cross-platform accessibility audit checklist.
- [x] Add an accessibility audit evidence verifier that fails until final physical-device results exist.
- [ ] Run VoiceOver full-flow audit.
- [ ] Run TalkBack full-flow audit.
- [ ] Run Dynamic Type / font-scale audit.
- [ ] Run Reduce Motion and haptic audit.
- [ ] Run high-contrast and color-blindness checks.
- [ ] Record results and fix blocking failures.

### Task 6: Final P4 Evidence Closure

**Files:**
- `docs/release/release-gate-evidence.md`
- `docs/superpowers/specs/2026-06-08-fire-v2-roadmap-design.md`
- `scripts/verify-release-readiness.sh`

- [ ] Populate every manual release-gate evidence row with owner, evidence link, date, and `Complete` or accepted-waiver status.
- [ ] Run `scripts/verify-release-readiness.sh` and confirm all lower-level release guards pass.
- [ ] Check the P4 roadmap acceptance boxes only after release readiness passes.

## Architectural Notes

- No Rust/native architecture changes are part of P4 release-prep scaffolding.
- The platform/Rust ownership split remains unchanged.
- `references/fluxdo/` and `third_party/` are not edited by this plan.
- Generated release media is intentionally absent until captured from real release-candidate builds.
- Privacy and data-safety drafts are conservative working documents, not final legal text.
- `docs/release/release-gate-evidence.md` tracks manual gate proof, but rows start as `Not started` and must be updated by the humans or release engineers who perform those actions.
- `scripts/verify-marketing-assets.sh` is expected to fail while marketing folders contain only `.gitkeep` placeholders, while PNG assets are flat single-color placeholders, while final asset filenames still contain fake/mock/placeholder-style markers, while screenshot folders contain nested directories or alternate asset paths, or while screenshot/feature-graphic dimensions do not match the release constraints; it is a precondition for store-media evidence closure, not a replacement for human asset review.
- `scripts/verify-performance-benchmarks.sh` is expected to fail while benchmark results are absent; it is a precondition for performance evidence closure, not a substitute for release-build physical-device measurement.
- `scripts/verify-accessibility-audit.sh` is expected to fail while accessibility results are absent; it is a precondition for accessibility evidence closure, not a substitute for a release-candidate assistive-technology audit.
- `scripts/verify-internal-testing-evidence.sh` is expected to fail while store records, uploaded builds, tester invites, or feedback triage rows are absent; it is a precondition for internal-testing evidence closure, not a substitute for store-console access.
- `scripts/verify-privacy-review-evidence.sh` is expected to fail while maintainer/legal review evidence is absent; it is a precondition for privacy evidence closure, not a substitute for legal approval.
- `scripts/verify-release-readiness.sh` is expected to fail while any lower-level P4 verifier fails; it is the final repo-owned readiness command before changing roadmap P4 acceptance.
- `scripts/verify-p4-release-evidence-suite.sh` is expected to fail while any store-media, performance, accessibility, internal-testing, privacy-review, or release-gate evidence verifier fails; it is shared by release readiness and checked roadmap P4 acceptance.
- `scripts/verify-release-gates.sh` is expected to fail until the manual P4 evidence rows are populated, and it also fails if required gate rows are renamed, duplicated, missing, or unknown; this is a release guard, not a development-test failure.
- Manual evidence verifiers are expected to fail if completed or accepted evidence rows still contain fake, mock, placeholder, dummy, synthetic, TODO/TBD, `example.com`, `not-real`, or `not real` markers in owner, reviewer, tester, device, result, evidence-link, or notes metadata, if evidence links are dead local paths, local directories, malformed URLs, malformed URL hosts, or placeholder URL hosts, if dates are impossible calendar dates, if rows have missing or extra Markdown table columns, if required manual evidence rows, platform/metric benchmark rows, or platform/screen accessibility rows are duplicated, if performance results lack metric-bound numeric units, leave multi-value memory results ambiguous, or hide a threshold miss behind a lower non-peak memory value, or if accepted waiver notes lack explicit approval/waiver context plus a reason, risk, exception, or no-ship decision.
- `scripts/verify-roadmap-plan-contract.sh` is expected to pass while the roadmap document set keeps one spec, four implementation plans, and the agreed 17/14/15/6 top-level task split.
- `scripts/verify-roadmap-architecture-constraints.sh` is expected to pass while the platform/Rust ownership split, minimum API targets, iOS topic-detail native runtime path, and reference/infrastructure boundaries stay intact.
- `scripts/verify-roadmap-implementation-evidence.sh` is expected to pass while checked P1-P3 acceptance code paths remain present; it does not prove P4 release readiness.
- `scripts/verify-roadmap-p4-acceptance.sh` is expected to pass while P4 roadmap acceptance remains unchecked, and to fail if any acceptance box is checked before the shared P4 evidence suite passes.
- `scripts/test-release-verifiers.sh` is expected to pass without real manual evidence because it uses isolated temporary fixtures to regression-test the release verifiers themselves, including release-readiness wrapper wiring, fake-evidence marker rejection, malformed store-media failures, flat PNG placeholder rejection, non-measurement performance results, target misses marked `Pass`, ambiguous or misleading multi-value memory results, duplicate manual evidence rows, duplicate performance/accessibility coverage rows, invalid calendar dates, placeholder metadata fields, dead local evidence paths, malformed evidence URLs, malformed URL hosts, placeholder URL hosts, extra Markdown table columns, missing Markdown table boundaries, weak accepted-waiver notes, and weak internal-testing/privacy metadata.
- Roadmap P4 acceptance remains unchecked until manual evidence exists.

## File Change Summary

- `docs/release/README.md` -- release materials index and manual-gate note.
- `docs/release/accessibility-audit-checklist.md` -- cross-platform accessibility release checklist.
- `docs/release/app-store-data-collection.md` -- App Store privacy questionnaire draft.
- `docs/release/app-store-description.md` -- App Store listing draft.
- `docs/release/internal-testing-evidence.md` -- store records, release-candidate uploads, tester invites, and feedback-triage evidence log.
- `docs/release/performance-benchmarks.md` -- benchmark targets and results log.
- `docs/release/play-store-data-safety.md` -- Play Store data-safety draft.
- `docs/release/play-store-description.md` -- Play Store listing draft.
- `docs/release/play-store-testing-setup.md` -- Play Store testing guide.
- `docs/release/privacy-policy.md` -- privacy policy draft aligned to current code.
- `docs/release/privacy-review-evidence.md` -- maintainer/legal privacy review evidence log.
- `docs/release/release-gate-evidence.md` -- manual P4 gate evidence register.
- `docs/release/test-feedback-template.md` -- beta feedback template.
- `docs/release/testflight-setup.md` -- TestFlight setup guide.
- `docs/release/third-party-licenses.md` -- generated dependency inventory.
- `native/android-app/marketing/README.md` -- Play Store asset requirements.
- `native/android-app/marketing/screenshots/phone/.gitkeep` -- phone screenshot folder placeholder.
- `native/android-app/marketing/screenshots/tablet7/.gitkeep` -- 7" tablet screenshot folder placeholder.
- `native/android-app/marketing/screenshots/tablet10/.gitkeep` -- 10" tablet screenshot folder placeholder.
- `native/android-app/src/main/AndroidManifest.xml` -- disables Android backup for release.
- `native/android-app/src/main/res/xml/backup_rules.xml` -- excludes all app data from legacy Auto Backup.
- `native/android-app/src/main/res/xml/data_extraction_rules.xml` -- excludes all app data from Android cloud backup and device transfer.
- `native/ios-app/Configs/FireWidget/PrivacyInfo.xcprivacy` -- widget privacy manifest with UserDefaults required-reason declarations.
- `native/ios-app/Configs/PrivacyInfo.xcprivacy` -- app privacy manifest with required-reason declarations.
- `native/ios-app/project.yml` -- wires privacy manifests into the app and widget resource phases.
- `native/ios-app/marketing/README.md` -- App Store asset requirements.
- `native/ios-app/marketing/preview-video/.gitkeep` -- App Preview folder placeholder.
- `native/ios-app/marketing/screenshots/iPad11/.gitkeep` -- iPad 11" screenshot folder placeholder.
- `native/ios-app/marketing/screenshots/iPad12.9/.gitkeep` -- iPad 12.9" screenshot folder placeholder.
- `native/ios-app/marketing/screenshots/iPhone5.5/.gitkeep` -- iPhone 5.5" screenshot folder placeholder.
- `native/ios-app/marketing/screenshots/iPhone6.5/.gitkeep` -- iPhone 6.5" screenshot folder placeholder.
- `scripts/benchmark-cold-start.sh` -- cold-start benchmark workflow.
- `scripts/benchmark-memory-peak.sh` -- memory benchmark workflow.
- `scripts/benchmark-scroll-fps.sh` -- scroll fluency benchmark workflow.
- `scripts/benchmark-topic-load.sh` -- topic detail load benchmark workflow.
- `scripts/collect-licenses.sh` -- dependency license inventory generator.
- `scripts/verify-accessibility-audit.sh` -- verifies release accessibility result rows across iOS and Android screens and audit categories.
- `scripts/verify-internal-testing-evidence.sh` -- verifies internal testing evidence rows across iOS and Android store/test-track gates.
- `scripts/verify-marketing-assets.sh` -- validates final store screenshot files, optional App Preview placement, and Play feature-graphic dimensions.
- `scripts/verify-performance-benchmarks.sh` -- verifies release benchmark result rows across iOS and Android target metrics.
- `scripts/verify-privacy-review-evidence.sh` -- verifies maintainer/legal privacy review evidence rows.
- `scripts/verify-release-readiness.sh` -- runs all P4 release-readiness verifiers as one final command.
- `scripts/verify-p4-release-evidence-suite.sh` -- runs the non-recursive lower-level P4 evidence suite used by readiness and checked acceptance guards.
- `scripts/verify-release-gates.sh` -- verifies exact manual P4 gate rows and required completion metadata.
- `scripts/verify-roadmap-plan-contract.sh` -- verifies the roadmap spec/plan set and expected top-level task counts.
- `scripts/verify-roadmap-architecture-constraints.sh` -- verifies minimum API targets, platform/Rust ownership boundaries, the iOS topic-detail native runtime path, and reference/infrastructure repository boundaries.
- `scripts/verify-roadmap-implementation-evidence.sh` -- verifies checked P1-P3 acceptance code evidence remains present.
- `scripts/verify-roadmap-p4-acceptance.sh` -- verifies exact roadmap P4 acceptance rows and requires the shared P4 evidence suite before checked acceptance.
- `scripts/test-release-verifiers.sh` -- regression-tests release verifier failure modes with temporary fixtures, including release-readiness wrapper wiring, fake evidence, and malformed store-media cases.
- `rust/crates/fire-core/src/core/persistence.rs` -- writes redacted session exports through the redacted envelope.
- `rust/crates/fire-core/src/session_store.rs` -- creates versioned redacted envelopes with auth cookies stripped.
- `rust/crates/fire-core/tests/session_flow.rs` -- covers redacted JSON and file persistence restore behavior.
