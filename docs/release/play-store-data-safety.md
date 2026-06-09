# Play Store Data Safety Draft

Last reviewed against code: 2026-06-09

Use this as a working draft for Play Console. Final answers require maintainer and legal review.

## Collection And Sharing

Fire does not sell data and does not include advertising or analytics SDKs. Fire communicates with LinuxDo and LinuxDo asset/CDN hosts for app functionality. Firebase Cloud Messaging may deliver Android notification payloads when `google-services.json` is configured, but the current app does not register FCM tokens with a LinuxDo backend.

| Play Category | Collected | Shared | Purpose | Notes |
| --- | --- | --- | --- | --- |
| User IDs | Yes | No | App functionality | LinuxDo username/user ID and session identity. |
| User-generated content | Yes | No | App functionality | Topics, posts, drafts, messages, bookmarks, notifications, uploaded media, and related content are exchanged with LinuxDo. |
| App activity | Yes | No | App functionality | Locally cached read state, notification state, and offline cache data. |
| Search history | No | No | App functionality request only | Queries are sent to LinuxDo for the requested search but are not intentionally stored as history by Fire. |
| Diagnostics | Yes, local only | No | App functionality / diagnostics | Local crash/APM/MetricKit diagnostics exist; Fire does not automatically upload them. |
| Device or other IDs | No | No | Not applicable | Advertising IDs are not used. FCM token handling is local diagnostic behavior today; revisit if uploaded. |
| Location | No | No | Not applicable | No location feature is implemented. |
| Financial info | No | No | Not applicable | No purchase flow is implemented. |

## Security Practices

- Network communication uses HTTPS.
- iOS credentials/session cookies use platform keychain-backed storage where applicable.
- Android saved credentials are encrypted with an Android Keystore AES-GCM key and stored in private SharedPreferences.
- Android backup is disabled with `android:allowBackup="false"` and all-exclude backup/data-extraction rules, so Fire app data is excluded from Android backup and device-transfer extraction.
- Fire has no advertising SDK and no analytics SDK.

## Deletion

Users can delete local Fire data by logging out, clearing app storage, or uninstalling the app. LinuxDo-hosted account data remains controlled by LinuxDo.

## Release Blockers

- Revisit this document if FCM token backend registration, analytics, cloud diagnostics, or server-side Fire services are added.
