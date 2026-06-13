# Native Differentiation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship platform-differentiating features — home screen widgets, offline caching, haptic feedback, shimmer loading, Siri Shortcuts, and Material You — that make Fire feel like a first-party native app on both iOS and Android.

**Architecture:** Rust owns the offline cache layer via `fire-store` SQLite tables with read-through semantics on network failure; platform stores consume cached payloads transparently. Widgets read from App Group shared containers (iOS) or native widget state mirrored by platform stores (Android), both populated from Rust-backed app loads through the UniFFI bridge. All UI components follow existing `FireTheme` / `FireColors` conventions and are added to the existing component libraries (`FireComponents.swift`, `FireColors.kt`).

**Tech Stack:** Rust + UniFFI + rusqlite / SwiftUI + WidgetKit + AppIntents / Android Views + AppWidgetProvider + RemoteViews + Material You / Kotlin Coroutines + Paging 3

## Feasibility Assessment

Fully feasible. The Rust `fire-store` crate already has a SQLite migration system with 3 migrations (`current_user_cache`, `topic_posts`, `topic_response_rows`, `cookie_replay_queue`) and supports `auth_scope_hash`-scoped reads/writes. The iOS app has a well-structured `FireTheme` enum with adaptive colors and corner-radius tokens. The Android app uses `FireColors.kt` backed by XML color resources with a clean resolver pattern. Both platforms already have PagingSource / Store patterns that can be augmented with offline fallback without architectural changes. No external dependencies are introduced that don't already exist in the respective ecosystems.

## Current Surface Inventory

- `rust/crates/fire-store/src/lib.rs` — `FireStore` struct with `open()`, `open_in_memory()`, cookie replay, user cache methods
- `rust/crates/fire-store/src/migrations.rs` — Schema migrations v1–v3
- `rust/crates/fire-core/src/core/topics.rs` — `FireCore::fetch_topic_list()` and topic detail source runtime
- `rust/crates/fire-core/src/core/notifications.rs` — Notification fetching and state management
- `native/ios-app/App/Core/FireTheme.swift` — `FireTheme` enum with adaptive colors, corner radius constants
- `native/ios-app/App/Core/FireComponents.swift` — 954-line reusable component library
- `native/ios-app/App/Stores/FireHomeFeedStore.swift` — Home feed state management with `topicLoadErrorMessage`
- `native/ios-app/App/Stores/FireNotificationStore.swift` — Notification state with error tracking
- `native/ios-app/App/ViewModels/FireAppViewModel.swift` — Central coordinator (2313 lines)
- `native/ios-app/App/Views/Home/FireHomeView.swift` — Home view with `.alert()` usage at line 156
- `native/android-app/src/main/java/com/fire/app/core/theme/FireColors.kt` — Color resolver with `resolveColor()`
- `native/android-app/src/main/java/com/fire/app/data/paging/TopicListPagingSource.kt` — Paging 3 source for topics
- `native/android-app/src/main/java/com/fire/app/data/paging/NotificationPagingSource.kt` — Paging 3 source for notifications
- `native/android-app/src/main/res/values/colors.xml` — Currently only launcher colors

## Design

### Key Design Decisions

1. **Offline cache lives in Rust `fire-store`, not in platform code.** Both platforms already depend on the UniFFI bridge for data. Adding cache tables to the same SQLite database that `fire-store` already manages keeps cache invalidation, scoping, and migration in one place. The alternative — platform-side Room / CoreData caches — would duplicate serialization logic and break the "Rust owns data" boundary.

2. **Widgets read from shared containers, not live FFI calls.** iOS WidgetKit extensions run in a separate process with strict memory limits. Writing topic summaries to an App Group `UserDefaults` from the main app process gives the widget a cheap synchronous read path. The alternative — calling UniFFI from the widget extension — would require bundling the Rust dylib into the extension and exceed memory budgets.

3. **Shimmer uses one shared platform path.** iOS keeps the existing `FireShimmerModifier` as the single SwiftUI animation implementation and applies it through shared skeleton row components; current first-page loading screens no longer fall back to blocking spinners where row-shaped skeletons are available. On Android, a custom `ShimmerLayout` wraps existing `RecyclerView` item layouts without changing their structure.

4. **Haptic feedback uses the existing `FireMotion` layer.** Remaining SwiftUI transitional surfaces use Fire's UIKit-backed haptic modifiers so the app stays iOS 16-compatible, while UIKit/Texture surfaces call the same small `FireMotionHaptics` bridge at confirmed interaction points. Decorative motion remains Reduce Motion-aware through `FireMotionTokens` and `fireRespectingReduceMotion`.

5. **Material You uses `DynamicColors` from the Material component library.** Android already depends on `com.google.android.material`. Dynamic Color support is a one-time theme configuration, not a new dependency. The `FireColors.kt` resolver pattern is extended with a `dynamicColorsEnabled` check that falls back to static colors on API < 31.

6. **Toast component replaces non-critical `.alert()` calls.** Notice-only iOS `.alert("提示", ...)` call sites are non-modal toasts. Critical confirmations, blocking load failures, and error-detail modals remain as alerts or inline error states.

### New Types

```rust
// fire-store: new cache tables (Migration 4)
pub struct TopicListCacheEntry {
    pub scope_key: String,        // "{kind}:{category_id}:{tag}"
    pub page: u32,
    pub payload_json: String,
    pub fetched_at_ms: i64,
}

pub struct NotificationListCacheEntry {
    pub scope_key: String,        // "recent" | "full:{offset}"
    pub payload_json: String,
    pub fetched_at_ms: i64,
}
```

```swift
// iOS: shared widget data
struct FireWidgetTopicEntry: Codable, Identifiable {
    var id: UInt64
    var title: String
    var categorySlug: String
    var categoryColor: String
    var replyCount: Int
    var lastPostedAt: Date
}

struct FireWidgetData: Codable {
    var unreadCount: Int
    var recentTopics: [FireWidgetTopicEntry]
    var updatedAt: Date
}
```

```swift
enum FireToastStyle {
    case success, error, info, warning
}

struct FireToast: Identifiable, Equatable {
    let id: UUID
    let message: String
    let style: FireToastStyle
}

struct FireToastView: View {
    let toast: FireToast
}
```

## Phased Implementation

### Task 1: Toast/Snackbar Component (iOS + Android)

**Files:**
- Modify: `native/ios-app/App/Core/FireComponents.swift`
- Create: `native/android-app/src/main/java/com/fire/app/core/ui/FireToast.kt`
- Modify: `native/ios-app/App/Views/Home/FireHomeView.swift`
- Modify: `native/ios-app/App/Views/Home/FireFilteredTopicListView.swift`
- Modify: `native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift`
- Modify: `native/ios-app/App/Views/Search/FireSearchView.swift`
- Modify: `native/ios-app/App/Views/Other/FireDraftsView.swift`
- Modify: `native/ios-app/App/Views/Other/FireReadHistoryView.swift`
- Modify: `native/ios-app/App/Views/Messages/FirePrivateMessagesView.swift`
- Modify: `native/ios-app/App/Views/Profile/FirePublicProfileView.swift`
- Modify: Android composer sheets and topic-detail interaction feedback surfaces

- [x] **Step 1: Add `FireToastStyle`, `FireToast`, `FireToastView`, and `fireToast(_:)` in `native/ios-app/App/Core/FireComponents.swift`**

  Implemented in the existing compiled component library instead of creating `FireToast.swift` to avoid unrelated `Fire.xcodeproj` metadata churn while the project file has local dirty changes. The modifier owns an identity-aware auto-dismiss task so an old timer cannot dismiss a newer toast.

- [x] **Step 2: Create `FireToast` Android component in `native/android-app/src/main/java/com/fire/app/core/ui/FireToast.kt`**

  Implemented as a Material `Snackbar` wrapper with `SUCCESS`, `ERROR`, `INFO`, and `WARNING` styles backed by the existing Fire color resources plus a string-resource overload.

- [x] **Step 3: Replace non-critical iOS notice alerts with `fireToast`**

  Converted notice-only `.alert("提示", ...)` feedback in Home, filtered topic lists, Bookmarks, Search, Drafts, Read History, Private Messages, and public-profile private-message submission. Critical confirmations and blocking error states remain modal or inline.

- [x] **Step 4: Add Android Snackbar calls in composer and topic-detail feedback flows**

  Converted composer sheet errors/draft restore/login/category warnings plus topic-detail action errors, bookmark save/delete, quote-empty, and reaction picker/user feedback at the UI boundary. ViewModels remain business-state owners and do not own Android views.

- [x] **Step 5: Verify**

  - `cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.ui.composer.MarkdownInsertionTest` — passed
  - `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3.1' -quiet` — passed; existing unrelated warnings remain

**Commit message:** `feat(toast): add FireToast component, replace non-critical alerts on iOS and Android`

---

### Task 2: iOS Widget — Data Sharing Layer

**Files:**
- Create: `native/ios-app/App/Shared/FireWidgetData.swift`
- Create: `native/ios-app/App/Shared/FireWidgetSnapshotWriter.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`
- Modify: `native/ios-app/App/Stores/FireHomeFeedStore.swift`
- Modify: `native/ios-app/App/Stores/FireNotificationStore.swift`
- Modify: `native/ios-app/Fire.entitlements`
- Create: `native/ios-app/FireWidget.entitlements`

- [x] **Step 1: Create shared widget snapshot types**

  `FireWidgetData` and `FireWidgetTopicEntry` live in `App/Shared/FireWidgetData.swift` and are compiled into both the app target and `FireWidgetExtension`. The snapshot is encoded to App Group `UserDefaults` under `group.com.fire.app` with key `fire_widget_data`.

- [x] **Step 2: Add App Group entitlement**

  Both `Fire.entitlements` and `FireWidget.entitlements` include `com.apple.security.application-groups = group.com.fire.app`.

- [x] **Step 3: Add `updateWidgetData()` through an app-only writer**

  `FireWidgetSnapshotWriter` stays in the app target only. It converts current Rust-backed `FireTopicRowPresentation` rows plus notification count into widget-safe snapshot data, limits topic entries to five, clears snapshots while unauthenticated, and calls `WidgetCenter.shared.reloadAllTimelines()`.

- [x] **Step 4: Refresh snapshots from authoritative stores**

  `FireHomeFeedStore` updates widget snapshots after topic-list state changes, including empty first pages. `FireNotificationStore` updates snapshots after notification state changes. Logout and unauthenticated session paths clear shared widget data through `FireAppViewModel.updateWidgetData()`.

- [x] **Step 5: Verify**

  - `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3' -derivedDataPath /tmp/fire-ios-widget-build2 CODE_SIGNING_ALLOWED=NO -quiet` — passed
  - `plutil -p /tmp/fire-ios-widget-build2/Build/Products/Debug-iphonesimulator/Fire.app/PlugIns/FireWidgetExtension.appex/Info.plist` — confirmed `NSExtensionPointIdentifier = com.apple.widgetkit-extension`

**Commit message:** `feat(widget-data): add shared App Group data layer for iOS home screen widgets`

---

### Task 3: iOS Widget — Small Widget

**Files:**
- Create: `native/ios-app/App/Widgets/FireWidgetEntry.swift`
- Create: `native/ios-app/App/Widgets/FireWidgetViews.swift`
- Create: `native/ios-app/App/Widgets/FireWidgetBundle.swift`
- Create: `native/ios-app/App/Widgets/FireSmallWidget.swift`
- Create: `native/ios-app/Configs/FireWidget-Info.plist`
- Modify: `native/ios-app/Fire.xcodeproj/project.pbxproj`
- Modify: `native/ios-app/project.yml`

- [x] **Step 1: Create `FireWidgetExtension` target**

  The Xcode project and `project.yml` define a `FireWidgetExtension` app-extension target with iOS 16 deployment, App Group entitlement, and an explicit `Configs/FireWidget-Info.plist` containing the WidgetKit `NSExtension` dictionary. The app target embeds the extension in `PlugIns`.

- [x] **Step 2: Create timeline entry/provider types**

  `FireWidgetEntry.swift` defines `FireWidgetEntry` and `FireWidgetProvider`. Timelines read only `FireWidgetData.load()` from the App Group shared container and refresh after 30 minutes; the extension never calls UniFFI or Rust.

- [x] **Step 3: Create small widget**

  `FireSmallWidget.swift` displays the Fire brand, unread count, and latest topic summary. It supports `.systemSmall` and deep-links to `fire://notifications`.

- [x] **Step 4: Add widget deep link handling in the app**

  `FireRouteParser`, `FireNavigationState`, `FireTabRoot`, and `FireHomeView` route `fire://notifications`, `fire://topic/<id>`, and related topic/profile routes through the existing native topic-detail and tab-navigation paths.

- [x] **Step 5: Verify**

  - `xcodebuild build -scheme Fire ... CODE_SIGNING_ALLOWED=NO -quiet` — passed
  - Built extension plist contains `NSExtensionPointIdentifier = com.apple.widgetkit-extension` and bundle ID `com.fire.app.ios.local.debug.widget`

**Commit message:** `feat(widget-small): add iOS small home screen widget with unread count and latest topic`

---

### Task 4: iOS Widget — Medium Widget

**Files:**
- Create: `native/ios-app/App/Widgets/FireMediumWidget.swift`
- Modify: `native/ios-app/App/Widgets/FireWidgetBundle.swift`
- Modify: `native/ios-app/App/Widgets/FireWidgetViews.swift`

- [x] **Step 1: Create `FireMediumWidget.swift`**

  `FireMediumWidget` supports `.systemMedium`, displays unread status and up to three topic rows, and links each row to `fire://topic/<id>`.

- [x] **Step 2: Add shared widget color/view helpers**

  `FireWidgetViews.swift` contains shared color parsing, category swatch rendering, empty-state rendering, and compact topic-row rendering used by all widget sizes.

- [x] **Step 3: Register `FireMediumWidget` in `FireWidgetBundle`**

  `FireWidgetBundle` registers `FireSmallWidget`, `FireMediumWidget`, and `FireLargeWidget`.

- [x] **Step 4: Verify**

  - `xcodebuild build -scheme Fire ... CODE_SIGNING_ALLOWED=NO -quiet` — passed

**Commit message:** `feat(widget-medium): add iOS medium home screen widget with trending topics`

---

### Task 5: iOS Widget — Large Widget

**Files:**
- Create: `native/ios-app/App/Widgets/FireLargeWidget.swift`
- Modify: `native/ios-app/App/Widgets/FireWidgetBundle.swift`

- [x] **Step 1: Create `FireLargeWidget.swift`**

  `FireLargeWidget` supports `.systemLarge`, renders unread summary plus up to five topic rows, and uses the same App Group snapshot as the small/medium widgets.

- [x] **Step 2: Register `FireLargeWidget` in `FireWidgetBundle`**

  `FireWidgetBundle` includes all three widgets in one WidgetKit extension entry point.

- [x] **Step 3: Verify**

  - `xcodebuild build -scheme Fire ... CODE_SIGNING_ALLOWED=NO -quiet` — passed

**Commit message:** `feat(widget-large): add iOS large home screen widget with timeline layout`

---

### Task 6: Android Widget — Native RemoteViews Implementation

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/widget/FireUnreadWidgetProvider.kt`
- Create: `native/android-app/src/main/java/com/fire/app/widget/FireTopicListWidgetProvider.kt`
- Create: `native/android-app/src/main/java/com/fire/app/widget/FireWidgetData.kt`
- Create: `native/android-app/src/main/res/drawable/bg_widget_panel.xml`
- Create: `native/android-app/src/main/res/layout/widget_unread.xml`
- Create: `native/android-app/src/main/res/layout/widget_topic_list.xml`
- Create: `native/android-app/src/main/res/xml/fire_unread_widget_info.xml`
- Create: `native/android-app/src/main/res/xml/fire_topic_list_widget_info.xml`
- Modify: `native/android-app/src/main/AndroidManifest.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/MainActivity.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/data/paging/TopicListPagingSource.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/home/HomeViewModel.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationsViewModel.kt`
- Modify: `native/android-app/src/main/res/values/strings.xml`

- [x] **Step 1: Use platform AppWidgetProvider/RemoteViews rather than adding Glance**

The Android host is View/XML-based and does not have a Compose compiler setup. The widget implementation therefore uses `AppWidgetProvider` plus `RemoteViews`, preserving the existing Android stack and avoiding a widget-only Compose/Glance dependency.

- [x] **Step 2: Create `FireWidgetData.kt` with shared state management**

`FireWidgetData` persists a compact snapshot in `SharedPreferences` under `fire_widget_prefs`: unread count, current username, up to five topic summaries, and the last update timestamp. Topic summaries are mirrored from `TopicRowState` values returned by Rust-backed paging loads; notification counters are mirrored from `NotificationCenterState`. Widgets never call UniFFI directly.

- [x] **Step 3: Create `FireUnreadWidgetProvider` small unread-count widget**

The small widget renders `widget_unread.xml`, pluralizes the unread notification count, shows an empty state when count is zero, and opens `fire://notifications` through `MainActivity`.

- [x] **Step 4: Create unread widget metadata and layout resources**

Added `widget_unread.xml`, `fire_unread_widget_info.xml`, shared `bg_widget_panel.xml`, and localized string/plural resources.

- [x] **Step 5: Create `FireTopicListWidgetProvider` medium topic-list widget**

The medium widget renders `widget_topic_list.xml`, shows the signed-in username or default title, displays up to three recent topic rows with category/reply/like/timestamp metadata, opens the app from the root, and deep-links rows into `TopicDetailActivity`.

- [x] **Step 6: Create topic-list widget metadata and layout resources**

Added `widget_topic_list.xml`, `fire_topic_list_widget_info.xml`, and topic metadata string resources.

- [x] **Step 7: Register widget providers and notification deep link in `AndroidManifest.xml`**

Registered `FireUnreadWidgetProvider` and `FireTopicListWidgetProvider` with `APPWIDGET_UPDATE` receivers. Added a `fire://notifications` `MainActivity` intent filter next to the existing profile deep link.

- [x] **Step 8: Update widget data from app state changes**

`TopicListPagingSource` now passes first-page topic rows to `HomeViewModel`, which mirrors them into `FireWidgetData` after every page-zero load, including an empty successful result. `NotificationsViewModel` mirrors unread counters after notification center refresh. Both paths use `FireApplication.getInstance()` to avoid introducing platform-side data ownership.

- [x] **Step 9: Verify Android build/test**

`cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.ui.composer.MarkdownInsertionTest` — passed.

**Commit message:** `feat(widget-android): add native app widgets`

---

### Task 7: Haptic Feedback Full Coverage (iOS)

**Files:**
- Modify: `native/ios-app/App/FireMotion/FireMotionEffects.swift`
- Modify: `native/ios-app/App/Views/Other/FireTabRoot.swift`
- Modify: `native/ios-app/App/ListKit/FireDiffableListController.swift`
- Modify: `native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift`
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift`
- Modify: `native/ios-app/App/Views/Composer/FirePostEditorView.swift`
- Modify: `native/ios-app/App/Views/Bookmarks/FireBookmarkEditorSheet.swift`

- [x] **Step 1: Extend the existing `FireMotion` haptic layer**

  Added declarative SwiftUI helpers for error, selection, and impact feedback, plus a small `FireMotionHaptics` UIKit bridge for Texture/UIKit event handlers. No separate `FireHaptics.swift` was introduced, preserving one authoritative motion/haptics path.

- [x] **Step 2: Add haptics to like toggle, reaction toggle, bookmark toggle**

  Topic-detail native cells now fire medium impact for heart/like, selection feedback for custom reactions, and light impact for bookmark actions from both action sheet and context menu paths. Existing SwiftUI like/bookmark/follow effects continue to use `FireMotion` modifiers.

- [x] **Step 3: Add haptics to pull-to-refresh completion**

  `FireDiffableListController` fires a light impact when the shared UIKit refresh control completes, covering Home and other collection-hosted refresh surfaces through the authoritative list controller.

- [x] **Step 4: Add haptics to send success/failure in composer**

  Existing composer, post editor, and bookmark editor success pulses remain on `fireSuccessFeedback`; validation and server failures now pulse `fireErrorFeedback`.

- [x] **Step 5: Add haptics to tab switch, context menu, and swipe reply**

  `FireTabRoot` emits selection feedback on tab changes, topic-detail menu presentation emits medium impact, and swipe-to-reply emits medium impact when the gesture crosses the reply threshold.

- [x] **Step 6: Verify**

  - `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3.1' -quiet` — passed; existing unrelated warnings remain

**Commit message:** `feat(haptics): add accessibility-gated haptic feedback to all interaction points`

---

### Task 8: Offline Cache Layer (Rust)

**Files:**
- Modify: `rust/crates/fire-store/src/migrations.rs` (add migration 4)
- Modify: `rust/crates/fire-store/src/lib.rs` (add cache read/write methods)
- Modify: `rust/crates/fire-models/src/topic.rs` and `rust/crates/fire-models/src/notification.rs` (surface cached response metadata)
- Modify: `rust/crates/fire-core/src/core/topics.rs` (add cache integration to fetch)
- Modify: `rust/crates/fire-core/src/core/notifications.rs` (add cache integration)
- Modify: `rust/crates/fire-core/src/core/session.rs` (clear scoped caches on logout)
- Modify: `rust/crates/fire-uniffi-types/src/records/topic_list.rs` and `rust/crates/fire-uniffi-notifications/src/records.rs` (carry cached metadata across UniFFI)

- [x] **Step 1: Add Migration 4 for topic list and notification cache tables in `migrations.rs`**

  Added `topic_list_cache` keyed by `(auth_scope_hash, scope_key, page)` and `notification_list_cache` keyed by `(auth_scope_hash, scope_key)`, with update-time indexes for future pruning.

- [x] **Step 2: Add `topic_list_cache_write` and `topic_list_cache_read` methods to `FireStore` in `lib.rs`**

  Added scoped topic-list write/read methods plus unit coverage for auth scope, scope key, and page isolation.

- [x] **Step 3: Add `notification_list_cache_write` and `notification_list_cache_read` methods to `FireStore`**

  Added notification list write/read methods and shared `clear_list_caches(auth_scope_hash)` for logout invalidation.

- [x] **Step 4: Add cache write after successful topic list fetch in `topics.rs`**

  `fetch_topic_list` serializes the parsed `TopicListResponse` after successful network parse and stores it under the current Rust-owned auth scope hash. Cache write failures are logged and non-fatal.

- [x] **Step 5: Add read-through cache fallback on network error in `topics.rs`**

  `fetch_topic_list` falls back only for `FireCoreError::Network`; HTTP, Cloudflare, login, stale-session, and parse errors stay authoritative. Cached responses return with `TopicListResponse.is_cached = true`, and UniFFI exposes `TopicListState.is_cached`.

- [x] **Step 6: Add same cache write/fallback for notifications in `notifications.rs`**

  Recent and full notification pages use scoped cache keys that include kind, limit, and offset. Cached responses set `NotificationListResponse.is_cached = true`, update the Rust notification runtime, and UniFFI exposes `NotificationListState.is_cached`, `NotificationCenterState.recent_is_cached`, and `NotificationCenterState.full_is_cached`.

- [x] **Step 7: Add cache invalidation on logout in `session.rs`**

  `logout_local()` clears topic and notification list caches for the current auth scope before mutating session cookies, then clears runtime notification/topic presence state as before.

- [x] **Step 8: Verify with `cargo test -p fire-store` and `cargo test -p fire-core`**

  - `cargo test -p fire-store` — passed
  - `cargo test -p fire-core fetch_topic_list_returns_cached_page_on_network_error` — passed
  - `cargo test -p fire-core fetch_recent_notifications_returns_cached_page_on_network_error` — passed
  - `cargo test -p fire-core` — passed
  - `cargo build -p fire-uniffi` — passed

**Commit message:** `feat(offline-cache): add Rust-side topic list and notification cache with read-through fallback`

---

### Task 9: Offline Cache Layer (iOS)

**Files:**
- Modify: `native/ios-app/App/Core/FireComponents.swift`
- Modify: `native/ios-app/App/Stores/FireHomeFeedStore.swift`
- Modify: `native/ios-app/App/Stores/FireNotificationStore.swift`
- Modify: `native/ios-app/App/Stores/FirePaginatedStore.swift`
- Modify: `native/ios-app/App/Views/Home/FireHomeView.swift`
- Modify: `native/ios-app/App/Views/Notifications/FireNotificationsView.swift`
- Modify: `native/ios-app/App/Views/Notifications/FireNotificationHistoryView.swift`

- [x] **Step 1: Add shared `FireOfflineBanner` to `FireComponents.swift`**

  Added a compact warning-colored banner using the existing `FireTheme` tokens and SF Symbol `wifi.slash`. The banner lives with the shared SwiftUI components instead of adding a one-off file.

- [x] **Step 2: Add `isOffline` state to `FireHomeFeedStore`**

  `FireHomeFeedStore` now updates `isOffline` from `TopicListState.isCached` and clears it on explicit feed scope changes. The platform store still uses the normal topic-list fetch path; Rust owns the read-through cache behavior.

- [x] **Step 3: Carry cached page metadata through `FirePaginatedStore`**

  `PageResult` now includes `isCached` with a default of `false`, so pagination stores can expose cache state without changing unrelated callers.

- [x] **Step 4: Add offline state to `FireNotificationStore`**

  Recent notifications use `NotificationListState.isCached` / `NotificationCenterState.recentIsCached`; full notification history uses the paginated store and `NotificationListState.isCached` / `NotificationCenterState.fullIsCached`.

- [x] **Step 5: Add banners to home and notification views**

  `FireHomeView`, `FireNotificationsView`, and `FireNotificationHistoryView` render `FireOfflineBanner` above their existing list content when the corresponding store state reports cached data.

- [x] **Step 6: Verify iOS build**

  - `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3.1' -quiet` — passed

**Commit message:** `feat(offline-ios): add offline banner and cache-aware state to iOS home and notification views`

---

### Task 10: Offline Cache Layer (Android)

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/data/paging/TopicListPagingSource.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/data/paging/NotificationPagingSource.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/home/HomeViewModel.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/home/HomeFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationsViewModel.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationsFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationHistoryFragment.kt`
- Create: `native/android-app/src/main/res/layout/view_offline_banner.xml`
- Create: `native/android-app/src/main/res/drawable/bg_offline_banner.xml`
- Create: `native/android-app/src/main/res/drawable/ic_wifi_off.xml`
- Modify: `native/android-app/src/main/res/layout/fragment_home.xml`
- Modify: `native/android-app/src/main/res/layout/fragment_notifications.xml`
- Modify: `native/android-app/src/main/res/layout/fragment_notification_history.xml`
- Modify: `native/android-app/src/main/res/values/strings.xml`

- [x] **Step 1: Keep Android on the normal Rust fetch path**

  No Android `fetchCachedTopicList()` or `fetchCachedNotifications()` path was added. `TopicListPagingSource` and `NotificationPagingSource` call the same repository methods as before; Rust decides whether a network failure can read through to cache.

- [x] **Step 2: Report cached page metadata from PagingSources**

  Both paging sources now accept an `onPageLoaded` callback and pass through `response.isCached`. Existing callers that do not show offline state use the default no-op callback.

- [x] **Step 3: Add offline state to Android view models**

  `HomeViewModel` exposes `isOffline` and resets it on feed/filter refresh. `NotificationsViewModel` exposes recent, full-history, and combined offline flows using `NotificationListState.isCached` and `NotificationCenterState.recentIsCached` / `fullIsCached`.

- [x] **Step 4: Add XML banner resources**

  Added `view_offline_banner.xml`, `bg_offline_banner.xml`, `ic_wifi_off.xml`, and `offline_cache_banner`. The banner uses existing `fire_warning` and `fire_chip_warning_background` colors.

- [x] **Step 5: Add banner visibility to home and notification fragments**

  `HomeFragment`, `NotificationsFragment`, and `NotificationHistoryFragment` include the shared banner layout and bind visibility to the view model flows. Explicit swipe/manual refresh clears the banner before requesting fresh data.

- [x] **Step 6: Verify Android build**

  - `cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.ui.composer.MarkdownInsertionTest` — passed

**Commit message:** `feat(offline-android): add cache-aware offline banners`

---

### Task 11: Shimmer Loading Animation (iOS)

**Files:**
- Modify: `native/ios-app/App/Core/FireShimmerModifier.swift`
- Modify: `native/ios-app/App/Core/FireComponents.swift`
- Modify: list views with first-page blocking loading states

- [x] **Step 1: Reuse the shared `FireShimmerModifier.swift` shimmer path**

  The branch already had a tracked `FireShimmerModifier` from the iOS native rebuild work. Task 11 keeps that as the single animation implementation instead of adding a parallel `FireShimmer.swift` path. The modifier overlays an animated sweep on existing skeleton shapes and respects `accessibilityReduceMotion`.

- [x] **Step 2: Find all `.redacted(reason: .placeholder)` usages**

  Verified with `rg "redacted\\(reason: \\.placeholder\\)" native/ios-app/App`: there are no current SwiftUI redacted placeholders. The earlier pseudo-code was stale relative to the native rebuild branch.

- [x] **Step 3: Keep home loading on the native ListKit skeleton path**

  Home is owned by `FireHomeCollectionView`, not redacted SwiftUI rows. Its existing `loadingRow` already uses `.fireShimmer()` and keeps topic rows on the native collection runtime path.

- [x] **Step 4: Replace blocking first-load spinners in notification, search, bookmarks, and secondary list views**

  Added shared `FireTopicSkeletonRow`, configurable `FireTopicSkeletonList`, `FireNotificationSkeletonRow`, and `FireNotificationSkeletonList` in `FireComponents.swift`. Recent notifications now reuse the notification skeleton list; full notification history, search execution, bookmarks, read history, drafts, and private messages use shimmer skeletons for initial page loading while keeping pagination footers as compact `ProgressView`s.

- [x] **Step 5: Verify iOS build**

  `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3.1' -quiet` passed. Existing unrelated warnings remain around deprecated text interactions, `await` without async operations, and Swift 6 capture diagnostics.

**Commit message:** `feat(shimmer-ios): replace redacted placeholders with animated shimmer loading views`

---

### Task 12: Shimmer Loading Animation (Android)

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/core/ui/ShimmerLayout.kt`
- Create: `native/android-app/src/main/res/layout/item_topic_shimmer.xml`
- Modify: `native/android-app/src/main/res/layout/fragment_home.xml`
- Modify: `native/android-app/src/main/res/values/fire_colors.xml`
- Modify: `native/android-app/src/main/res/values-night/fire_colors.xml`

- [x] **Step 1: Create `ShimmerLayout.kt`**

  Added a reusable `FrameLayout` overlay that draws an animated linear-gradient sweep in `dispatchDraw`, cancels on detach, and respects the system animator-disabled setting through `ValueAnimator.areAnimatorsEnabled()`.

- [x] **Step 2: Create `item_topic_shimmer.xml`**

  Added a wrapper layout around the existing `item_topic_row_skeleton`, preserving the current skeleton row shape while adding the shimmer treatment.

- [x] **Step 3: Add shimmer loading state to Home**

  `fragment_home.xml` now uses six `item_topic_shimmer` includes in the existing `loading_skeleton_view`. `HomeFragment` load-state ownership remains unchanged.

- [x] **Step 4: Verify**

  - `cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.ui.composer.MarkdownInsertionTest` — passed

**Commit message:** `feat(shimmer-android): add shimmer loading animation for RecyclerView items`

---

### Task 13: iOS Siri Shortcuts

**Files:**
- Create: `native/ios-app/App/Intents/FireShortcuts.swift`
- Create: `native/ios-app/App/Intents/FireViewUnreadIntent.swift`
- Create: `native/ios-app/App/Intents/FireSearchTopicsIntent.swift`
- Create: `native/ios-app/App/Intents/FireViewProfileIntent.swift`
- Modify: `native/ios-app/App/Navigation/FireNavigationState.swift`
- Modify: `native/ios-app/App/Routing/FireAppRoute.swift`
- Modify: `native/ios-app/App/Routing/FireRouteParser.swift`
- Modify: `native/ios-app/App/Views/Other/FireTabRoot.swift`
- Modify: `native/ios-app/App/Views/Home/FireHomeView.swift`

- [x] **Step 1: Create `FireViewUnreadIntent` using AppIntents framework**

  `FireViewUnreadIntent` uses `openAppWhenRun = true` and sets `FireNavigationState.shared.pendingRoute = .notifications` from `perform()`. It intentionally does not use `OpenURLIntent`, which is iOS 18-only while Fire targets iOS 16.

- [x] **Step 2: Create `FireSearchTopicsIntent`**

  `FireSearchTopicsIntent` defines an optional `@Parameter(title: "Search Query") var query: String?` without an unsupported inline default, then sets `.search(query:)` on `FireNavigationState.shared`.

- [x] **Step 3: Create `FireViewProfileIntent`**

  `FireViewProfileIntent` opens the app and sets `.profileTab` on `FireNavigationState.shared`.

- [x] **Step 4: Create `FireShortcuts` to group intents**

  `FireShortcuts` registers unread, search, and profile App Shortcuts with system images `bell.badge`, `magnifyingglass`, and `person.circle`.

- [x] **Step 5: Add deep link and shortcut route handling**

  `FireAppRoute` now models `.notifications`, `.profileTab`, and `.search(query:)`. `FireRouteParser` parses `fire://notifications`, `fire://profile`, and `fire://search?query=...`; `FireTabRoot` selects the notifications/profile tabs or forwards search to `FireHomeView`, and `FireSearchStore.prepareSearch(query:)` preloads the query.

- [x] **Step 6: Verify**

  - `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3' -derivedDataPath /tmp/fire-ios-widget-build2 CODE_SIGNING_ALLOWED=NO -quiet` — passed
  - `cd native/ios-app && xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3' -derivedDataPath /tmp/fire-ios-widget-build2 CODE_SIGNING_ALLOWED=NO -only-testing:FireTests/FireRouteParserTests -quiet` — passed, 23 route parser tests

**Commit message:** `feat(shortcuts): add Siri Shortcuts for unread, search, and profile navigation`

---

### Task 14: Android Material You

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/core/theme/FireColors.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/FireApplication.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/MainActivity.kt`
- Modify: `native/android-app/src/main/AndroidManifest.xml`
- Modify: `native/android-app/src/main/res/values/themes.xml`
- Create: `native/android-app/src/main/res/values-night/themes.xml`

- [x] **Step 1: Add Material You dynamic color support to `FireColors.kt`**

  `FireColors.accent()` and `accentSoft()` now resolve Material theme attributes when dynamic color is available on Android 12+ and fall back to the Fire palette otherwise. Other semantic/text/surface methods remain fixed Fire palette values so XML-heavy branded surfaces keep their existing contrast and identity.

- [x] **Step 2: Apply Dynamic Colors in `FireApplication.kt`**

  Startup applies `DynamicColors.applyToActivitiesIfAvailable(this)`, records whether dynamic colors are active, and exposes a wrapped themed context for app-context color resolution.

- [x] **Step 3: Enable edge-to-edge rendering in `MainActivity.kt`**

  `MainActivity` calls `enableEdgeToEdge()` before `super.onCreate`, while preserving the existing root inset listener that pads content around system bars.

- [x] **Step 4: Add Predictive Back Gesture support**

  `AndroidManifest.xml` sets `android:enableOnBackInvokedCallback="true"` on the application tag.

- [x] **Step 5: Add Material3 light/night theme attrs**

  `values/themes.xml` now declares Fire fallback Material3 color attributes and system-bar colors. `values-night/themes.xml` mirrors those attrs with dark-mode system-bar icon flags.

- [x] **Step 6: Verify**

  - `cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.ui.composer.MarkdownInsertionTest` — passed

**Commit message:** `feat(material-you): add Dynamic Color, edge-to-edge, and predictive back gesture`

---

### Task 15: Dark Mode Fine-tuning

**Files:**
- Modify: `native/ios-app/App/Core/FireTheme.swift`
- Modify: `native/ios-app/App/Views/Other/FireTabRoot.swift`
- Modify: `native/ios-app/App/Views/Profile/FireProfileView.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/core/theme/FireColors.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/FireApplication.kt`
- Modify: `native/android-app/src/main/res/values-night/fire_colors.xml`

- [x] **Step 1: Add OLED pure black option to `FireAppearancePreference`**

  `FireAppearancePreference` now includes `.oled`, displays `纯黑`, and resolves to `.dark` color scheme so the app stays in dark-mode system chrome while Fire surfaces can choose OLED overrides.

- [x] **Step 2: Keep OLED overrides in the authoritative `FireTheme.swift` path**

  The implementation avoids a separate Xcode project-file change by extending `FireTheme.adaptive()` with an optional `oled` color and a shared `appearancePreferenceStorageKey`. Canvas, surface, panel, chrome, and tab-bar colors now substitute pure-black / near-black OLED values when the stored preference is `oled`.

- [x] **Step 3: Make OLED surfaces recompute from the stored preference**

  OLED-sensitive colors are computed properties instead of static `let` constants, so switching between dark and pure black re-evaluates the current preference.

- [x] **Step 4: Add OLED toggle to profile settings**

  `FireProfileView` already renders `FireAppearancePreference.allCases` in the settings segmented picker, so adding the enum case surfaces the pure-black option automatically. `FireTabRoot` and settings now share `FireTheme.appearancePreferenceStorageKey`.

- [x] **Step 5: Add Android OLED mode hook in `FireColors.kt`**

  `FireColors` now loads a persisted `fire.appearance/oled_mode` flag at app startup and returns `#000000`, `#0A0A0B`, and `#111113` from `backgroundCanvas()`, `backgroundSurface()`, and `backgroundElevated()` when enabled. Android has no existing appearance settings UI, so this task keeps the mode hook centralized instead of adding a partial settings architecture.

- [x] **Step 6: Run contrast ratio checks**

  Contrast checks passed for representative iOS and Android dark/OLED text-on-surface pairs. Android night `fire_text_tertiary` was adjusted from `#6B7280` to `#7B8491` so tertiary text reaches 4.83:1 on dark canvas and 5.55:1 on OLED black.

- [x] **Step 7: Verify builds**

  - `cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.ui.composer.MarkdownInsertionTest` — passed
  - `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3.1' -quiet` — passed

**Commit message:** `feat(dark-mode): add OLED pure black option and contrast ratio validation`

## Architectural Notes

- **Rust ownership boundary:** Offline cache tables live in `fire-store` and are written/read only by `fire-core`. Platforms never touch SQLite directly — they receive cached or fresh data through the same UniFFI call path. This preserves the "Rust owns data" boundary.
- **No new external dependencies:** Android widgets use platform `AppWidgetProvider`/`RemoteViews`; Material Dynamic Colors are part of the Material library already used. WidgetKit and AppIntents are used through APIs compatible with Fire's iOS 16 deployment target. No third-party packages are added.
- **Backward compatibility:** Material You falls back to static Fire colors on API < 31. Siri Shortcuts remain on the iOS 16-compatible AppIntents path. Android widgets use the app's existing minSdk-compatible widget APIs, with newer launcher sizing hints ignored on older launchers.
- **Widget memory:** iOS widget timelines are capped at 30-minute refresh intervals and read from lightweight UserDefaults data — no Rust FFI calls in the widget extension process.
- **Motion accessibility:** Decorative motion is gated or degraded through `FireMotionTokens` / `fireRespectingReduceMotion`. Haptics use the small `FireMotionHaptics` UIKit bridge from both transitional SwiftUI surfaces and Texture/UIKit cells.
- **Cache staleness:** Cache entries have no TTL — they are invalidated on logout and overwritten on every successful fetch. This is intentional: stale data is better than no data for offline mode, and the next successful fetch always replaces it.
- **OLED mode scope:** OLED mode only affects dark-theme canvas/surface colors. Text, accent, and semantic colors remain unchanged to maintain contrast ratios.

## File Change Summary

- `native/ios-app/App/Core/FireComponents.swift` — Toast component, auto-dismiss modifier, and style variants
- `native/android-app/src/main/java/com/fire/app/core/ui/FireToast.kt` — Snackbar-based Android toast
- `native/ios-app/App/Views/Home/FireHomeView.swift` — Replace notice alert with toast
- `native/ios-app/App/Views/Home/FireFilteredTopicListView.swift` — Replace notice alert with toast
- `native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift` — Replace alert with toast
- `native/ios-app/App/Views/Search/FireSearchView.swift` — Replace notice alert with toast
- `native/ios-app/App/Views/Other/FireDraftsView.swift` — Replace alert with toast
- `native/ios-app/App/Views/Other/FireReadHistoryView.swift` — Replace notice alert with toast
- `native/ios-app/App/Views/Messages/FirePrivateMessagesView.swift` — Replace alert with toast
- `native/ios-app/App/Views/Profile/FirePublicProfileView.swift` — Replace composer notice alert with toast
- `native/ios-app/App/Shared/FireWidgetData.swift` — Shared data model for widget communication
- `native/ios-app/App/Shared/FireWidgetSnapshotWriter.swift` — App-only widget snapshot writer and timeline reload hook
- `native/ios-app/App/Widgets/FireWidgetEntry.swift` — Timeline entry and provider types
- `native/ios-app/App/Widgets/FireWidgetBundle.swift` — Widget extension entry point
- `native/ios-app/App/Widgets/FireWidgetViews.swift` — Shared WidgetKit view helpers
- `native/ios-app/App/Widgets/FireSmallWidget.swift` — Small unread count widget
- `native/ios-app/App/Widgets/FireMediumWidget.swift` — Medium trending topics widget
- `native/ios-app/App/Widgets/FireLargeWidget.swift` — Large timeline widget
- `native/ios-app/App/ViewModels/FireAppViewModel.swift` — Widget data update, deep link handler
- `native/android-app/src/main/java/com/fire/app/widget/FireWidgetData.kt` — Android widget shared state
- `native/android-app/src/main/java/com/fire/app/widget/FireUnreadWidgetProvider.kt` — Unread count `RemoteViews` widget
- `native/android-app/src/main/java/com/fire/app/widget/FireTopicListWidgetProvider.kt` — Topic list `RemoteViews` widget
- `native/android-app/src/main/res/layout/widget_unread.xml` — Unread-count widget layout
- `native/android-app/src/main/res/layout/widget_topic_list.xml` — Topic-list widget layout
- `native/android-app/src/main/res/drawable/bg_widget_panel.xml` — Shared widget panel background
- `native/android-app/src/main/res/xml/fire_unread_widget_info.xml` — Widget metadata
- `native/android-app/src/main/res/xml/fire_topic_list_widget_info.xml` — Widget metadata
- `native/android-app/src/main/AndroidManifest.xml` — Android widget receivers and notification deep link
- `native/android-app/src/main/java/com/fire/app/MainActivity.kt` — Widget notification deep-link handling
- `native/android-app/src/main/java/com/fire/app/data/paging/TopicListPagingSource.kt` — First-page topic rows for widget updates
- `native/android-app/src/main/java/com/fire/app/ui/home/HomeViewModel.kt` — Topic-list widget snapshot updates
- `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationsViewModel.kt` — Unread widget snapshot updates
- `native/ios-app/App/FireMotion/FireMotionEffects.swift` — Shared SwiftUI feedback modifiers and UIKit haptic bridge
- `native/ios-app/App/Views/Other/FireTabRoot.swift` — Add haptics to tab switch
- `native/ios-app/App/ListKit/FireDiffableListController.swift` — Add haptic to pull-to-refresh completion
- `native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift` — Add haptics to native Texture post interactions
- `rust/crates/fire-store/src/migrations.rs` — Migration 4 for topic/notification cache
- `rust/crates/fire-store/src/lib.rs` — Cache read/write methods
- `rust/crates/fire-core/src/core/topics.rs` — Read-through cache on fetch
- `rust/crates/fire-core/src/core/notifications.rs` — Read-through cache on fetch
- `native/ios-app/App/Core/FireOfflineBanner.swift` — Offline mode banner component
- `native/ios-app/App/Stores/FireHomeFeedStore.swift` — Offline state tracking
- `native/ios-app/App/Stores/FireNotificationStore.swift` — Offline state tracking
- `native/android-app/src/main/java/com/fire/app/data/paging/TopicListPagingSource.kt` — Cache fallback
- `native/android-app/src/main/java/com/fire/app/data/paging/NotificationPagingSource.kt` — Cache fallback
- `native/android-app/src/main/java/com/fire/app/core/ui/FireOfflineBanner.kt` — Offline banner view
- `native/android-app/src/main/java/com/fire/app/core/ui/ShimmerLayout.kt` — Shimmer animation layout
- `native/android-app/src/main/res/layout/item_topic_shimmer.xml` — Shimmer item layout
- `native/ios-app/App/Core/FireShimmerModifier.swift` — SwiftUI shimmer animation modifier
- `native/ios-app/App/Core/FireComponents.swift` — Shared SwiftUI skeleton row components
- `native/ios-app/App/Intents/FireShortcuts.swift` — App Shortcuts provider
- `native/ios-app/App/Intents/FireViewUnreadIntent.swift` — View unread intent
- `native/ios-app/App/Intents/FireSearchTopicsIntent.swift` — Search intent
- `native/ios-app/App/Intents/FireViewProfileIntent.swift` — View profile intent
- `native/android-app/src/main/java/com/fire/app/core/theme/FireColors.kt` — Dynamic Color accent resolution
- `native/android-app/src/main/java/com/fire/app/FireApplication.kt` — Dynamic Color initialization
- `native/android-app/src/main/java/com/fire/app/MainActivity.kt` — Edge-to-edge
- `native/ios-app/App/Core/FireOledTheme.swift` — OLED pure black color overrides
- `native/ios-app/App/Core/FireTheme.swift` — OLED mode integration
