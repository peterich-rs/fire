# Fire Privacy Policy Draft

Last updated: 2026-06-09

This draft must be reviewed before store submission. It reflects the current repository behavior as of June 9, 2026.

## Overview

Fire is an unofficial native client for the LinuxDo community. Fire does not operate a separate backend service. The app communicates with LinuxDo and LinuxDo-served assets to provide login, browsing, posting, notifications, search, profile, bookmark, draft, and read-history features.

## Data Fire Handles

| Data | Purpose | Storage |
| --- | --- | --- |
| LinuxDo session cookies and CSRF state | Keep the user authenticated with LinuxDo | Rust session state; iOS Keychain-backed cookie store; Android private storage with Android Keystore-encrypted saved login credentials |
| LinuxDo user profile data | Show the current user, profile screens, badges, stats, and author metadata | Rust session state and local app cache |
| Topics, posts, notifications, bookmarks, drafts, read history, search results, categories, and user data | Display LinuxDo community features and support offline reads of already loaded content | Rust-owned cache/session state and platform UI state |
| Search queries | Execute LinuxDo search requests | In-memory request/UI state; not intentionally persisted as a standalone history |
| iOS widget snapshot data | Render WidgetKit timelines without loading Rust inside the widget extension | App Group UserDefaults snapshot containing username, unread count, and recent topic summaries |
| Android widget snapshot data | Render RemoteViews widgets | Private Android preferences containing username, unread count, and recent topic summaries |
| APNs/FCM tokens | Local push registration diagnostics and local notification handling | Current code keeps token handling local; no LinuxDo backend token registration is available in the app |
| Local diagnostics and crash data | Developer diagnostics and local troubleshooting | Local APM/diagnostic files. They are not automatically uploaded by Fire |

## Data Fire Does Not Include

- Advertising SDKs
- Third-party analytics SDKs
- IDFA or Android Advertising ID collection
- Location tracking
- A Fire-operated backend database
- Automatic upload of crash reports or diagnostics from Fire

## Network Transmission

Fire sends authenticated requests to LinuxDo and LinuxDo asset/CDN hosts as required for app functionality. All app network traffic is expected to use HTTPS.

Fire may receive FCM payloads on Android when Firebase configuration is provided. The current Android implementation parses received payloads for local notification display and refreshes Rust notification state, but token registration to a LinuxDo backend is not implemented.

## Local Storage and Deletion

Users can remove local Fire data by logging out, clearing app data in system settings, or uninstalling the app. LinuxDo-hosted account data, posts, and notifications remain controlled by LinuxDo and the user's LinuxDo account.

## Platform Notes

### iOS

- WebView login, Cloudflare completion, cookie extraction, native UI, keychain storage, files, media, notifications, and widgets are platform-owned.
- WidgetKit reads an App Group snapshot only.
- PLCrashReporter and MetricKit diagnostics are local diagnostic artifacts unless the user intentionally exports diagnostics.
- The app and WidgetKit extension include privacy manifests that declare no tracking and required-reason API usage for local defaults, local diagnostic file metadata, and local stall timing. App Store Connect data-collection answers remain documented separately in `app-store-data-collection.md`.

### Android

- WebView login, Cloudflare completion, cookie extraction, native UI, keystore-backed credential storage, files, media, notifications, and widgets are platform-owned.
- Android backup is disabled with `android:allowBackup="false"` and all-exclude backup/data-extraction rules. Fire app data should not participate in Android cloud backup or device-transfer extraction.
- FCM token backend registration is not available in the current app.

## Important Release Blockers

- Complete legal/privacy review before using this draft as a public privacy policy.

## Contact

For privacy-related questions, contact the Fire project maintainers through the repository issue tracker.
