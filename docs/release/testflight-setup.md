# TestFlight Setup Guide

## Prerequisites

- Apple Developer Program access
- App Store Connect access for the Fire app record
- Xcode and iOS SDK versions that pass `scripts/ios/verify_xcode26_toolchain.sh`
- Valid distribution certificate, provisioning profiles, bundle IDs, and App Group configuration for the app and widget extension
- App Store listing and privacy drafts reviewed

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
