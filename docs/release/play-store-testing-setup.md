# Play Store Testing Setup Guide

## Prerequisites

- Google Play Developer account
- Play Console access for the Fire app
- Release signing configured outside the repository
- `native/android-app/google-services.json` present if FCM testing is required
- Play Store listing and data-safety drafts reviewed

## Build A Release Bundle

```bash
cd native/android-app
./gradlew bundleRelease
```

Expected output:

```text
native/android-app/build/outputs/bundle/release/app-release.aab
```

## Play Console Setup

1. Create or open the Fire app record.
2. Confirm package name `com.fire.app`.
3. Fill listing copy from `docs/release/play-store-description.md`.
4. Fill data-safety answers from `docs/release/play-store-data-safety.md`.
5. Upload real screenshots and feature graphic from `native/android-app/marketing/` after `scripts/verify-marketing-assets.sh` validation.
6. Upload the signed AAB to Internal testing.
7. Complete content rating, target audience, data safety, and app access declarations.

## Test Tracks

| Track | Audience | Goal |
| --- | --- | --- |
| Internal testing | Maintainers and developers | Build install and smoke validation |
| Closed testing | Trusted community testers | Core feature and release-candidate validation |
| Open testing | Wider community testers | Device diversity and feedback volume |

## What To Test

- WebView login and Cloudflare completion
- Home feed, category filters, topic detail, and deep links
- Notifications, search, profile, bookmarks, drafts, and read history
- Offline cache behavior after loading content
- RemoteViews unread and topic-list widgets
- Dark/OLED themes, predictive back, and accessibility
- FCM local notification display when Firebase is configured

## Manual Requirements

Creating Play Console app records, uploading signed releases, approving declarations, inviting testers, and starting rollouts require a human with Play Console permissions.
