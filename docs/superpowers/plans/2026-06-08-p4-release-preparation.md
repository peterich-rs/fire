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
- `scripts/verify-release-gates.sh` -- release-gate evidence verifier.
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
7. **Make the final release gate fail closed.** `scripts/verify-release-gates.sh` checks the evidence register and fails until every row has an accepted/completed status, owner, evidence link, and date. Current failure is expected because manual gates are still open.

## Phased Implementation

### Phase 1: Store Listing And Marketing Structure

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

- [x] Create App Store and Play Store listing drafts.
- [x] Create iOS and Android marketing asset folder structures.
- [x] Document that real release-candidate media is still required.
- [ ] Capture and validate final App Store screenshots.
- [ ] Capture or decide not to ship an App Preview video.
- [ ] Capture and validate final Play Store screenshots.
- [ ] Create and approve the Play Store 1024x500 feature graphic.

### Phase 2: Privacy, Data Safety, And Licenses

**Files:**
- `docs/release/privacy-policy.md`
- `docs/release/app-store-data-collection.md`
- `docs/release/play-store-data-safety.md`
- `docs/release/third-party-licenses.md`
- `scripts/collect-licenses.sh`
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
- [ ] Complete maintainer/legal privacy review.
- [x] Decide Android `allowBackup` release behavior and update docs/store answers.
- [x] Add iOS app and widget privacy manifests with required-reason API declarations.
- [x] Fix redacted session export before any public diagnostic workflow claims redaction.

### Phase 3: Internal Testing Guides

**Files:**
- `docs/release/testflight-setup.md`
- `docs/release/play-store-testing-setup.md`
- `docs/release/test-feedback-template.md`
- `docs/release/release-gate-evidence.md`
- `scripts/verify-release-gates.sh`

- [x] Document TestFlight build/upload flow using existing iOS release scripts.
- [x] Document Play Store internal/closed/open testing setup.
- [x] Add a tester feedback template.
- [x] Add a release-gate evidence register for manual P4 gates.
- [x] Add a verifier that fails until manual gate evidence is complete.
- [ ] Create App Store Connect app record.
- [ ] Create Play Console app record.
- [ ] Upload release-candidate builds to internal testing tracks.
- [ ] Invite testers and collect feedback.

### Phase 4: Performance Regression Gates

**Files:**
- `docs/release/performance-benchmarks.md`
- `scripts/benchmark-cold-start.sh`
- `scripts/benchmark-scroll-fps.sh`
- `scripts/benchmark-topic-load.sh`
- `scripts/benchmark-memory-peak.sh`

- [x] Define release benchmark targets and failure thresholds.
- [x] Add Android `adb` benchmark workflows.
- [x] Add iOS measurement workflows for Instruments/xctrace.
- [ ] Record release-build iOS measurements on a physical device.
- [ ] Record release-build Android measurements on a physical device.
- [ ] Resolve or explicitly accept any threshold failures.

### Phase 5: Accessibility Audit

**Files:**
- `docs/release/accessibility-audit-checklist.md`

- [x] Add a cross-platform accessibility audit checklist.
- [ ] Run VoiceOver full-flow audit.
- [ ] Run TalkBack full-flow audit.
- [ ] Run Dynamic Type / font-scale audit.
- [ ] Run Reduce Motion and haptic audit.
- [ ] Run high-contrast and color-blindness checks.
- [ ] Record results and fix blocking failures.

## Architectural Notes

- No Rust/native architecture changes are part of P4 release-prep scaffolding.
- The platform/Rust ownership split remains unchanged.
- `references/fluxdo/` and `third_party/` are not edited by this plan.
- Generated release media is intentionally absent until captured from real release-candidate builds.
- Privacy and data-safety drafts are conservative working documents, not final legal text.
- `docs/release/release-gate-evidence.md` tracks manual gate proof, but rows start as `Not started` and must be updated by the humans or release engineers who perform those actions.
- `scripts/verify-release-gates.sh` is expected to fail until the manual P4 evidence rows are populated; this is a release guard, not a development-test failure.
- Roadmap P4 acceptance remains unchecked until manual evidence exists.

## File Change Summary

- `docs/release/README.md` -- release materials index and manual-gate note.
- `docs/release/accessibility-audit-checklist.md` -- cross-platform accessibility release checklist.
- `docs/release/app-store-data-collection.md` -- App Store privacy questionnaire draft.
- `docs/release/app-store-description.md` -- App Store listing draft.
- `docs/release/performance-benchmarks.md` -- benchmark targets and results log.
- `docs/release/play-store-data-safety.md` -- Play Store data-safety draft.
- `docs/release/play-store-description.md` -- Play Store listing draft.
- `docs/release/play-store-testing-setup.md` -- Play Store testing guide.
- `docs/release/privacy-policy.md` -- privacy policy draft aligned to current code.
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
- `scripts/verify-release-gates.sh` -- release-gate evidence verifier.
- `rust/crates/fire-core/src/core/persistence.rs` -- writes redacted session exports through the redacted envelope.
- `rust/crates/fire-core/src/session_store.rs` -- creates versioned redacted envelopes with auth cookies stripped.
- `rust/crates/fire-core/tests/session_flow.rs` -- covers redacted JSON and file persistence restore behavior.
