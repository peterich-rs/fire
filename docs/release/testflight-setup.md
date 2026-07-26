# TestFlight Setup Guide

## Public / External Testing Readiness

TestFlight has three distribution levels. iOS 16 support alone is **not** enough
for a public link.

| Level | Apple requirements | Fire status |
| --- | --- | --- |
| Internal testing | App Store Connect users only; no Beta App Review | Engineering upload path exists (`scripts/ios/archive_release.sh`); store record / invite evidence still empty |
| External testing | Beta App Review + privacy policy URL + compliance answers | **Not ready** — policy still draft, ASC metadata/evidence incomplete |
| Public link | External group approved first, then public link enabled | **Not ready** — blocked by external testing |

### Binary / repo checklist (engineering)

- [x] Minimum OS iOS 16 (`native/ios-app/project.yml`)
- [x] App + widget Privacy Manifests (`Configs/PrivacyInfo.xcprivacy`, widget copy)
- [x] App icons present; marketing 1024px must be **non-transparent / no alpha**
- [x] `ITSAppUsesNonExemptEncryption = false` in `Configs/Fire-Info.plist` (HTTPS-only exemption)
- [x] Photo save purpose string (`NSPhotoLibraryAddUsageDescription`)
- [x] Push entitlement declared (`aps-environment` in `Fire.entitlements`); enable Push + App Group on the App ID
- [x] Archive/upload script (`scripts/ios/archive_release.sh`)
- [ ] Production bundle ID + team chosen and used for the upload (not `.dev` / `.local.release` unless that is the intentional ASC record)
- [ ] Apple Developer identifiers created: app, widget, App Group `group.com.fire.app`, associated domain `applinks:linux.do`
- [ ] `linux.do` hosts a valid Apple App Site Association file if universal links are advertised

### App Store Connect / human checklist (public testing blockers)

- [ ] App record exists with the production bundle ID
- [ ] Privacy policy published at a **stable public HTTPS URL** (repo `docs/release/privacy-policy.md` is still a draft and is not a public URL)
- [ ] Maintainer/legal sign-off recorded in `privacy-review-evidence.md`
- [ ] App Privacy answers entered from `app-store-data-collection.md`
- [ ] Export compliance answered (Info.plist key should auto-satisfy the missing-compliance prompt)
- [ ] Beta App description + review notes, including a **demo LinuxDo account** (login/CF required)
- [ ] Contact email for Beta App Review
- [ ] Release build uploaded; build processing finished
- [ ] External group created, build assigned, Beta App Review submitted and **Approved**
- [ ] Only then: enable Public Link on the external group
- [ ] Record ASC/build/invite/feedback rows in `internal-testing-evidence.md`

### Recommended product cleanups before public testers

- Gate or hide **开发者工具** on release builds (currently reachable from Settings and onboarding) so public betas do not look like an unfinished internal build.
- Decide messaging for incomplete push backend (tokens are local-only today).
- Capture real RC screenshots under `native/ios-app/marketing/screenshots/` before full App Store submission (not strictly required for TestFlight itself).
- Bump `FIRE_MARKETING_VERSION` / `FIRE_BUILD_NUMBER` to the values you want testers to see (shared defaults are still `0.1.x`).

## Prerequisites

- Apple Developer Program access
- App Store Connect access for the Fire app record
- Xcode and iOS SDK versions that pass `scripts/ios/verify_xcode26_toolchain.sh`
- Valid distribution certificate, provisioning profiles, bundle IDs, and App Group configuration for the app and widget extension
- App Store listing and privacy drafts reviewed, privacy policy hosted publicly for external/public testing

## Relation to GitHub Releases

Tagging `v*` runs `.github/workflows/github-release.yml` and attaches iOS
xcarchive/dSYMs + Android APK to the GitHub Release page. That workflow does
**not** upload to TestFlight. Use this guide / the `iOS TestFlight` workflow for
App Store Connect internal or external testing.

## Build And Upload

Prefer the repository release script:

```bash
scripts/ios/verify_xcode26_toolchain.sh

TESTFLIGHT_UPLOAD=YES \
APP_STORE_CONNECT_API_KEY_PATH=/path/to/AuthKey.p8 \
APP_STORE_CONNECT_API_KEY_ID=<key-id> \
APP_STORE_CONNECT_API_KEY_ISSUER_ID=<issuer-id> \
FIRE_DEVELOPMENT_TEAM=<team-id> \
FIRE_PRODUCT_BUNDLE_IDENTIFIER=<bundle-id> \
FIRE_MARKETING_VERSION=2.0.0 \
FIRE_BUILD_NUMBER=<build-number> \
scripts/ios/archive_release.sh
```

The script prepares UniFFI artifacts, regenerates the Xcode project from `native/ios-app/project.yml`, archives `Fire`, exports/upload when configured, and writes build metadata under `artifacts/ios-release/`.

## App Store Connect Setup

1. Create or open the Fire iOS app record.
2. Confirm the main app bundle ID and widget extension bundle ID.
3. Confirm App Group `group.com.fire.app` is enabled for both targets.
4. Fill listing copy from `docs/release/app-store-description.md`.
5. Fill privacy answers from `docs/release/app-store-data-collection.md`.
6. Upload screenshots and any preview video from `native/ios-app/marketing/` after real capture and `scripts/verify-marketing-assets.sh` validation.
7. Submit a TestFlight build for review.
8. Record the App Store Connect record, uploaded build, tester invite, and feedback triage rows in `docs/release/internal-testing-evidence.md`.

## Test Groups

| Group | Audience | Goal |
| --- | --- | --- |
| Internal Team | Maintainers and developers | Smoke test every uploaded build |
| Alpha | Trusted community testers | Validate core flows and release blockers |
| Beta | Wider community testers | Find device, account, and scale issues |

## What To Test

- WebView login and Cloudflare completion
- Home feed, category filters, topic detail, reply navigation
- Notifications, search, profile, bookmarks, drafts, and read history
- Offline cache behavior after loading content
- WidgetKit small/medium/large widgets
- Siri Shortcuts: unread, search, profile
- Dark/OLED themes, haptics, accessibility, and diagnostics export

## Manual Requirements

Creating app records, inviting testers, reviewing TestFlight compliance prompts, and approving external testing require a human with App Store Connect permissions.
