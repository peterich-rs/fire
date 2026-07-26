# TestFlight Setup Guide

## Public / External Testing Readiness

TestFlight has three distribution levels. iOS 16 support alone is **not** enough
for a public link.

| Level | Apple requirements | Fire status |
| --- | --- | --- |
| Internal testing | App Store Connect users only; no Beta App Review | Engineering upload path exists (`scripts/ios/archive_release.sh` + `iOS TestFlight` workflow) |
| External testing | Beta App Review + privacy policy URL + compliance answers | **Repo side ready for privacy URL** — paste links from `public-urls.md`; ASC human steps still required |
| Public link | External group approved first, then public link enabled | After external approval only |

### Public HTTPS links (no separate website)

Fire hosts store-facing legal/support pages on the **public** GitHub `main`
branch. Full table: [`public-urls.md`](./public-urls.md).

| ASC field | Paste this |
| --- | --- |
| Privacy Policy URL | https://github.com/peterich-rs/fire/blob/main/docs/release/privacy-policy.md |
| Support URL | https://github.com/peterich-rs/fire/issues |
| Marketing URL (optional) | https://github.com/peterich-rs/fire |

Fallback plain-text privacy policy:  
https://raw.githubusercontent.com/peterich-rs/fire/main/docs/release/privacy-policy.md

Merge any privacy-policy edits to `main` **before** submitting Beta App Review so
reviewers see the published file.

### Binary / repo checklist (engineering)

- [x] Minimum OS iOS 16 (`native/ios-app/project.yml`)
- [x] App + widget Privacy Manifests (`Configs/PrivacyInfo.xcprivacy`, widget copy)
- [x] App icons present; marketing 1024px non-transparent / no alpha
- [x] `ITSAppUsesNonExemptEncryption = false` in `Configs/Fire-Info.plist`
- [x] Photo save purpose string (`NSPhotoLibraryAddUsageDescription`)
- [x] Archive/upload script (`scripts/ios/archive_release.sh`)
- [x] Public privacy policy URL on GitHub `main` (`privacy-policy.md` + `public-urls.md`)
- [x] Signing baseline aligned with **v0.1.3**: main app entitlements are
  Associated Domains only; **Widget is not embedded** in the Fire archive until
  App Group + extension profiles exist. Push (`aps-environment`) and App Groups
  stay out of `Fire.entitlements` so the existing `Fire App Store` profile works.
- [ ] Production bundle ID + team used for the upload (not `.dev` / `.local.release` unless intentional)
- [ ] Apple Developer identifiers: app, widget, App Group `group.com.fire.app`, Push, associated domain `applinks:linux.do` if advertised
- [ ] `linux.do` AASA file if universal links are advertised

### App Store Connect / human checklist (public testing)

- [ ] App record exists with the production bundle ID
- [x] Privacy Policy URL ready — use the GitHub link in `public-urls.md`
- [ ] Paste Privacy Policy URL into App Privacy + TestFlight external testing
- [ ] App Privacy answers entered from `app-store-data-collection.md`
- [ ] Export compliance answered (Info.plist key should auto-satisfy)
- [ ] Beta App description + review notes (template below), including **demo LinuxDo account**
- [ ] Contact email for Beta App Review
- [ ] Release build uploaded; processing finished
- [ ] External group created, build assigned, Beta App Review **Approved**
- [ ] Enable Public Link on the external group
- [ ] Record ASC/build/invite/feedback rows in `internal-testing-evidence.md`

### Beta App Review notes template

Paste into TestFlight → Beta App Review → Review Notes (adjust account secrets):

```text
Fire is an unofficial native LinuxDo client. It has no separate Fire backend.

Login:
- Uses an in-app WKWebView so reviewers can complete LinuxDo login and any
  Cloudflare challenge in the system WebView surface.
- Demo account: <USERNAME>
- Demo password: <PASSWORD>

Privacy policy:
https://github.com/peterich-rs/fire/blob/main/docs/release/privacy-policy.md

Support:
https://github.com/peterich-rs/fire/issues

Notes:
- Push-token backend registration is not available; tokens stay local.
- Associated domain applinks:linux.do may be incomplete on the server side.
```

### Recommended product cleanups before wide public testers

- Gate or hide **开发者工具** on release builds (Settings / onboarding).
- Expect push delivery to be limited until a backend token path exists.
- Capture RC screenshots under `native/ios-app/marketing/screenshots/` before full App Store submission (not required for TestFlight itself).
- Set `FIRE_MARKETING_VERSION` / `FIRE_BUILD_NUMBER` for the uploaded build.

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
