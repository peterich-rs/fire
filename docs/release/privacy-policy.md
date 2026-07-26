# Fire Privacy Policy

**Last updated:** 2026-07-26

**Public URL (use this in App Store Connect / TestFlight):**  
https://github.com/peterich-rs/fire/blob/main/docs/release/privacy-policy.md

**Plain-text mirror:**  
https://raw.githubusercontent.com/peterich-rs/fire/main/docs/release/privacy-policy.md

This policy describes how the Fire native client handles information. Fire does
not operate a separate application backend. The live copy of this document is
the `main` branch file in the public Fire repository linked above.

## Overview

Fire is an unofficial native client for the LinuxDo community. The app
communicates with LinuxDo and LinuxDo-served assets to provide login, browsing,
posting, notifications, search, profile, bookmark, draft, and read-history
features.

## Information Fire Handles

| Data | Purpose | Storage |
| --- | --- | --- |
| LinuxDo session cookies and CSRF state | Keep you authenticated with LinuxDo | Rust session state; iOS Keychain-backed cookie store; Android private storage with Android Keystore-encrypted saved login credentials |
| LinuxDo user profile data | Show the current user, profile screens, badges, stats, and author metadata | Rust session state and local app cache |
| Topics, posts, notifications, bookmarks, drafts, read history, search results, categories, and user data | Display LinuxDo community features and support offline reads of already loaded content | Rust-owned cache/session state and platform UI state |
| Search queries | Execute LinuxDo search requests | In-memory request/UI state; not intentionally persisted as a standalone history |
| iOS widget snapshot data | Render WidgetKit timelines without loading Rust inside the widget extension | App Group UserDefaults snapshot containing username, unread count, and recent topic summaries |
| Android widget snapshot data | Render RemoteViews widgets | Private Android preferences containing username, unread count, and recent topic summaries |
| APNs/FCM device tokens | Local push registration diagnostics and local notification handling | Current builds keep token handling local; Fire does not register push tokens with a Fire-operated backend |
| Local diagnostics and crash data | Developer diagnostics and local troubleshooting | Local APM/diagnostic files. Fire does not automatically upload them |

## Information Fire Does Not Collect for Advertising

Fire does not include:

- Advertising SDKs
- Third-party analytics SDKs
- IDFA or Android Advertising ID collection
- Location tracking
- A Fire-operated backend user database
- Automatic upload of crash reports or diagnostics from Fire to a Fire service

## Network Transmission

Fire sends authenticated requests to LinuxDo and LinuxDo asset/CDN hosts as
required for app functionality. App network traffic is expected to use HTTPS.

On Android, Fire may receive FCM payloads when Firebase configuration is
provided. Received payloads may be used to show local notifications and refresh
notification state. Token registration to a LinuxDo push backend is not
implemented in the current app.

## Local Storage and Deletion

You can remove local Fire data by logging out, clearing app data in system
settings, or uninstalling the app. LinuxDo-hosted account data, posts, and
notifications remain controlled by LinuxDo and your LinuxDo account.

## Platform Notes

### iOS

- WebView login, Cloudflare completion, cookie extraction, native UI, keychain
  storage, files, media, notifications, and widgets are handled on device.
- WidgetKit reads an App Group snapshot only.
- PLCrashReporter and MetricKit diagnostics remain local unless you intentionally
  export diagnostics.
- The app and WidgetKit extension ship privacy manifests that declare no tracking
  and required-reason API usage for local defaults, local diagnostic file
  metadata, and local stall timing.

### Android

- WebView login, Cloudflare completion, cookie extraction, native UI,
  keystore-backed credential storage, files, media, notifications, and widgets
  are handled on device.
- Android backup is disabled (`android:allowBackup="false"` with exclude rules).
  Fire app data should not participate in Android cloud backup or device-transfer
  extraction.
- FCM token backend registration is not available in the current app.

## Children

Fire is intended for users of the LinuxDo community and is not directed at
children. Do not use Fire if you are not permitted to use LinuxDo under
applicable terms and law.

## Changes

When this policy changes, the `main` branch file and “Last updated” date above
are updated. The public GitHub URL remains the canonical location unless a later
release announces a different host.

## Contact

Privacy questions about Fire can be filed through the project issue tracker:

https://github.com/peterich-rs/fire/issues
