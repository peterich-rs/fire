# App Store Privacy Questionnaire Draft

Last reviewed against code: 2026-06-09

Use this as a working draft for App Store Connect. Final answers require maintainer and legal review.

## Data Collection Summary

Fire handles data for app functionality. Fire does not use data for tracking and does not include advertising or analytics SDKs.

| App Store Category | Draft Answer | Notes |
| --- | --- | --- |
| Contact Info | No | Fire displays LinuxDo profile data but does not collect email/phone/name fields for Fire-operated services. |
| User Content | Yes | Topics, posts, drafts, messages, bookmarks, notifications, uploaded media, and related community content are fetched from or sent to LinuxDo for app functionality. |
| Search History | No | Search queries are sent to LinuxDo to execute searches, but Fire does not intentionally persist a search-history feature. Revisit if store policy treats submitted search terms as collected data. |
| Identifiers - User ID | Yes | LinuxDo username/user ID and session identity are used for app functionality and are linked to the user's LinuxDo account. |
| Identifiers - Device ID | No | Fire does not use IDFA or an Android Advertising ID. APNs device token is local-only today; if uploaded later, revisit this answer. |
| Usage Data | Yes | Locally cached read/browse state and notification state exist for app functionality and offline mode. No Fire analytics backend receives this data. |
| Diagnostics | Yes, local only | iOS PLCrashReporter/MetricKit and runtime diagnostics are stored locally and can be intentionally exported by a user/developer. They are not automatically uploaded by Fire. Confirm how App Store Connect classifies local-only diagnostics before submission. |
| Location | No | No location feature is implemented. |
| Purchases | No | No purchase flow is implemented. |
| Financial Info | No | No financial data flow is implemented. |
| Health and Fitness | No | Not applicable. |
| Sensitive Info | No | No dedicated sensitive-info feature is implemented. |

## Tracking

Draft answer: Fire does not track users across apps or websites owned by other companies.

## Linked to Identity

LinuxDo account identifiers, user content, and app activity needed for app functionality are linked to the user's LinuxDo session. Fire does not create a separate Fire account.

## Release Questions

- Decide final App Store classification for local-only diagnostics.
- Keep the app and widget privacy manifests aligned with required-reason API usage if diagnostics, widget storage, or linked SDK behavior changes.
- Revisit this document if APNs token backend registration, analytics, cloud diagnostics, or server-side Fire services are added.
