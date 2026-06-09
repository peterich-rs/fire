# Native Differentiation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship platform-differentiating features — home screen widgets, offline caching, haptic feedback, shimmer loading, Siri Shortcuts, and Material You — that make Fire feel like a first-party native app on both iOS and Android.

**Architecture:** Rust owns the offline cache layer via `fire-store` SQLite tables with read-through semantics on network failure; platform stores consume cached payloads transparently. Widgets read from App Group shared containers (iOS) or Glance state (Android), both populated by the Rust core through the UniFFI bridge. All UI components follow existing `FireTheme` / `FireColors` conventions and are added to the existing component libraries (`FireComponents.swift`, `FireColors.kt`).

**Tech Stack:** Rust + UniFFI + rusqlite / SwiftUI + WidgetKit + AppIntents / Android Views + Glance + Material You / Kotlin Coroutines + Paging 3

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

4. **Haptic feedback uses the existing `FireMotion` layer.** SwiftUI surfaces prefer declarative `sensoryFeedback` modifiers, while UIKit/Texture surfaces call a small `FireMotionHaptics` bridge at confirmed interaction points. Decorative motion remains Reduce Motion-aware through `FireMotionTokens` and `fireRespectingReduceMotion`.

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
- Create: `native/ios-app/App/Widget/FireWidgetData.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift` (add widget data write after refresh)
- Modify: Xcode project: add App Group entitlement to main target

- [ ] **Step 1: Create shared data types in `native/ios-app/App/Widget/FireWidgetData.swift`**

```swift
import Foundation

struct FireWidgetTopicEntry: Codable, Identifiable, Hashable {
    var id: UInt64
    var title: String
    var categorySlug: String
    var categoryColorHex: String
    var replyCount: Int
    var likeCount: Int
    var lastPostedAt: TimeInterval
    var posterAvatarUrl: String?
}

struct FireWidgetData: Codable {
    var unreadNotificationCount: Int
    var recentTopics: [FireWidgetTopicEntry]
    var username: String
    var updatedAt: TimeInterval

    static let appGroupName = "group.com.fire.app"
    static let sharedDefaultsSuite = "group.com.fire.app.defaults"
    static let widgetDataKey = "fire_widget_data"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: sharedDefaultsSuite)
    }

    static func load() -> FireWidgetData? {
        guard let data = sharedDefaults?.data(forKey: widgetDataKey) else { return nil }
        return try? JSONDecoder().decode(FireWidgetData.self, from: data)
    }

    func save() {
        guard let defaults = FireWidgetData.sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: FireWidgetData.widgetDataKey)
        }
    }
}
```

- [ ] **Step 2: Add App Group entitlement**

In the Xcode project editor, add the App Groups capability to both the main app target and the widget extension target (created later). The group identifier is `group.com.fire.app`. This creates an entitlements file at `native/ios-app/App/AppName.entitlements`.

- [ ] **Step 3: Add `updateWidgetData()` method to `FireAppViewModel`**

```swift
// In FireAppViewModel, add after state refresh:
func updateWidgetData() {
    let snapshot = self.snapshot()
    let rows = self.homeFeedStore.topicRows.prefix(5).map { row in
        FireWidgetTopicEntry(
            id: row.id,
            title: row.title,
            categorySlug: row.categorySlug,
            categoryColorHex: row.categoryColorHex,
            replyCount: row.replyCount,
            likeCount: row.likeCount,
            lastPostedAt: row.lastPostedAt.timeIntervalSince1970,
            posterAvatarUrl: row.posterAvatarUrl
        )
    }
    let data = FireWidgetData(
        unreadNotificationCount: self.notificationStore.unreadCount,
        recentTopics: Array(rows),
        username: snapshot.currentUser?.username ?? "",
        updatedAt: Date().timeIntervalSince1970
    )
    data.save()
}
```

- [ ] **Step 4: Call `updateWidgetData()` after topic list refresh and notification state refresh in `FireHomeFeedStore` and `FireNotificationStore`**

After a successful `topicListRefresh` cycle completes, call `appViewModel.updateWidgetData()`. Same for notification state changes.

- [ ] **Step 5: Call `WidgetCenter.shared.reloadAllTimelines()` after `updateWidgetData()`**

```swift
import WidgetKit
// After data.save():
WidgetCenter.shared.reloadAllTimelines()
```

**Commit message:** `feat(widget-data): add shared App Group data layer for iOS home screen widgets`

---

### Task 3: iOS Widget — Small Widget

**Files:**
- Create: `native/ios-app/App/Widget/FireWidgetBundle.swift`
- Create: `native/ios-app/App/Widget/FireSmallWidget.swift`
- Create: `native/ios-app/App/Widget/FireWidgetEntry.swift`
- Modify: Xcode project: add WidgetExtension target

- [ ] **Step 1: Create WidgetExtension target in Xcode**

Add a new Widget Extension target named `FireWidget` to the Xcode project. Set deployment target to iOS 17+. Link against the main app's App Group.

- [ ] **Step 2: Create `FireWidgetEntry.swift` with timeline provider types**

```swift
import WidgetKit

struct FireWidgetEntry: TimelineEntry {
    let date: Date
    let data: FireWidgetData?

    static var placeholder: FireWidgetEntry {
        FireWidgetEntry(
            date: Date(),
            data: FireWidgetData(
                unreadNotificationCount: 3,
                recentTopics: [
                    FireWidgetTopicEntry(
                        id: 1, title: "示例话题标题", categorySlug: "general",
                        categoryColorHex: "#E8663C", replyCount: 12, likeCount: 5,
                        lastPostedAt: Date().timeIntervalSince1970, posterAvatarUrl: nil
                    )
                ],
                username: "Fire",
                updatedAt: Date().timeIntervalSince1970
            )
        )
    }

    static var snapshot: FireWidgetEntry { placeholder }
}
```

- [ ] **Step 3: Create `FireSmallWidget.swift`**

```swift
import WidgetKit
import SwiftUI

struct FireSmallWidget: Widget {
    let kind: String = "FireSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireWidgetProvider()) { entry in
            FireSmallWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.08, green: 0.09, blue: 0.10)
                }
        }
        .configurationDisplayName("Fire 未读")
        .description("查看未读通知数量和最新话题")
        .supportedFamilies([.systemSmall])
    }
}

struct FireSmallWidgetView: View {
    let entry: FireWidgetEntry

    var body: some View {
        if let data = entry.data {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fire")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                    Spacer()
                    if data.unreadNotificationCount > 0 {
                        Text("\(data.unreadNotificationCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.91, green: 0.39, blue: 0.18))
                            .clipShape(Capsule())
                    }
                }
                if let topic = data.recentTopics.first {
                    Text(topic.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.93))
                        .lineLimit(2)
                    Text(topic.categorySlug)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.62, green: 0.63, blue: 0.67))
                }
                Spacer()
                Link(destination: URL(string: "fire://notifications")!) {
                    Text("查看全部")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                }
            }
            .padding(12)
        } else {
            VStack {
                Text("Fire")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                Text("打开应用以加载数据")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.62, green: 0.63, blue: 0.67))
            }
        }
    }
}
```

- [ ] **Step 4: Create `FireWidgetProvider` with timeline logic**

```swift
struct FireWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FireWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (FireWidgetEntry) -> Void) {
        completion(.snapshot)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FireWidgetEntry>) -> Void) {
        let data = FireWidgetData.load()
        let entry = FireWidgetEntry(date: Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}
```

- [ ] **Step 5: Create `FireWidgetBundle.swift`**

```swift
import WidgetKit
import SwiftUI

@main
struct FireWidgetBundle: WidgetBundle {
    var body: some Widget {
        FireSmallWidget()
    }
}
```

- [ ] **Step 6: Add widget deep link handler in main app**

In `FireAppViewModel` or the app's `onOpenURL` handler, add:

```swift
.onOpenURL { url in
    guard url.scheme == "fire" else { return }
    switch url.host {
    case "notifications":
        // Navigate to notifications tab
        selectedTab = .notifications
    case "topic":
        if let topicId = url.queryParameters["id"].flatMap(UInt64.init) {
            navigateToTopic(id: topicId)
        }
    default: break
    }
}
```

**Commit message:** `feat(widget-small): add iOS small home screen widget with unread count and latest topic`

---

### Task 4: iOS Widget — Medium Widget

**Files:**
- Create: `native/ios-app/App/Widget/FireMediumWidget.swift`
- Modify: `native/ios-app/App/Widget/FireWidgetBundle.swift`

- [ ] **Step 1: Create `FireMediumWidget.swift`**

```swift
import WidgetKit
import SwiftUI

struct FireMediumWidget: Widget {
    let kind: String = "FireMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireWidgetProvider()) { entry in
            FireMediumWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.08, green: 0.09, blue: 0.10)
                }
        }
        .configurationDisplayName("Fire 热门")
        .description("查看热门话题")
        .supportedFamilies([.systemMedium])
    }
}

struct FireMediumWidgetView: View {
    let entry: FireWidgetEntry

    var body: some View {
        if let data = entry.data, !data.recentTopics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Fire 热门话题")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                    Spacer()
                    Text(data.username)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.62, green: 0.63, blue: 0.67))
                }
                Divider().overlay(Color(white: 1, opacity: 0.08))
                ForEach(Array(data.recentTopics.prefix(3))) { topic in
                    Link(destination: URL(string: "fire://topic?id=\(topic.id)")!) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: topic.categoryColorHex).opacity(0.6))
                                .frame(width: 4, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.93))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(topic.categorySlug)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(red: 0.62, green: 0.63, blue: 0.67))
                                    if topic.replyCount > 0 {
                                        Image(systemName: "bubble.right")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color(red: 0.52, green: 0.52, blue: 0.55))
                                        Text("\(topic.replyCount)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color(red: 0.52, green: 0.52, blue: 0.55))
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        } else {
            Text("打开 Fire 加载数据")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.62, green: 0.63, blue: 0.67))
        }
    }
}
```

- [ ] **Step 2: Add `Color(hex:)` convenience init if not already present**

```swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
```

- [ ] **Step 3: Register `FireMediumWidget` in `FireWidgetBundle`**

```swift
@main
struct FireWidgetBundle: WidgetBundle {
    var body: some Widget {
        FireSmallWidget()
        FireMediumWidget()
    }
}
```

**Commit message:** `feat(widget-medium): add iOS medium home screen widget with trending topics`

---

### Task 5: iOS Widget — Large Widget

**Files:**
- Create: `native/ios-app/App/Widget/FireLargeWidget.swift`
- Modify: `native/ios-app/App/Widget/FireWidgetBundle.swift`

- [ ] **Step 1: Create `FireLargeWidget.swift`**

```swift
import WidgetKit
import SwiftUI

struct FireLargeWidget: Widget {
    let kind: String = "FireLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireWidgetProvider()) { entry in
            FireLargeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.08, green: 0.09, blue: 0.10)
                }
        }
        .configurationDisplayName("Fire 时间线")
        .description("查看话题时间线和通知摘要")
        .supportedFamilies([.systemLarge])
    }
}

struct FireLargeWidgetView: View {
    let entry: FireWidgetEntry

    var body: some View {
        if let data = entry.data {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Fire")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                    Spacer()
                    if data.unreadNotificationCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 10))
                            Text("\(data.unreadNotificationCount) 条未读")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.22))
                    }
                }
                Divider().overlay(Color(white: 1, opacity: 0.08))
                ForEach(Array(data.recentTopics.prefix(5))) { topic in
                    Link(destination: URL(string: "fire://topic?id=\(topic.id)")!) {
                        HStack(spacing: 10) {
                            VStack(alignment: .center, spacing: 2) {
                                Circle()
                                    .fill(Color(hex: topic.categoryColorHex).opacity(0.5))
                                    .frame(width: 8, height: 8)
                                Rectangle()
                                    .fill(Color(white: 1, opacity: 0.06))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.93))
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text(topic.categorySlug)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(red: 0.62, green: 0.63, blue: 0.67))
                                    Label("\(topic.replyCount)", systemImage: "bubble.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(red: 0.52, green: 0.52, blue: 0.55))
                                    Label("\(topic.likeCount)", systemImage: "heart")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(red: 0.52, green: 0.52, blue: 0.55))
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        } else {
            Text("打开 Fire 加载数据")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.62, green: 0.63, blue: 0.67))
        }
    }
}
```

- [ ] **Step 2: Register `FireLargeWidget` in `FireWidgetBundle`**

```swift
@main
struct FireWidgetBundle: WidgetBundle {
    var body: some Widget {
        FireSmallWidget()
        FireMediumWidget()
        FireLargeWidget()
    }
}
```

**Commit message:** `feat(widget-large): add iOS large home screen widget with timeline layout`

---

### Task 6: Android Widget — Glance Implementation

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/widget/FireUnreadWidget.kt`
- Create: `native/android-app/src/main/java/com/fire/app/widget/FireTopicListWidget.kt`
- Create: `native/android-app/src/main/java/com/fire/app/widget/FireWidgetData.kt`
- Create: `native/android-app/src/main/java/com/fire/app/widget/FireWidgetReceiver.kt`
- Create: `native/android-app/src/main/res/xml/fire_unread_widget_info.xml`
- Create: `native/android-app/src/main/res/xml/fire_topic_list_widget_info.xml`
- Create: `native/android-app/src/main/res/layout/widget_unread.xml`
- Create: `native/android-app/src/main/res/layout/widget_topic_list.xml`
- Modify: `native/android-app/build.gradle.kts` (add Glance dependency)

- [ ] **Step 1: Add Glance dependency to `build.gradle.kts`**

```kotlin
implementation("androidx.glance:glance-appwidget:1.1.0")
implementation("androidx.glance:glance-material3:1.1.0")
```

- [ ] **Step 2: Create `FireWidgetData.kt` with shared state management**

```kotlin
package com.fire.app.widget

import android.content.Context
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.state.GlanceStateDefinition
import java.io.File

object FireWidgetData {
    val UNREAD_COUNT = intPreferencesKey("unread_count")
    val TOPIC_TITLES = stringPreferencesKey("topic_titles")
    val USERNAME = stringPreferencesKey("username")

    fun updateWidgetData(context: Context, unreadCount: Int, topicTitlesJson: String, username: String) {
        // Write to DataStore / SharedPreferences for Glance to read
        val prefs = context.getSharedPreferences("fire_widget_prefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putInt(UNREAD_COUNT.name, unreadCount)
            .putString(TOPIC_TITLES.name, topicTitlesJson)
            .putString(USERNAME.name, username)
            .apply()
    }
}
```

- [ ] **Step 3: Create `FireUnreadWidget.kt` — small unread count widget**

```kotlin
package com.fire.app.widget

import android.content.Context
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.layout.*
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider

class FireUnreadWidget : GlanceAppWidget() {
    @Composable
    override fun Content() {
        val prefs = currentState preferences
        val unread = prefs[FireWidgetData.UNREAD_COUNT] ?: 0
        val username = prefs[FireWidgetData.USERNAME] ?: ""

        Box(modifier = GlanceModifier.fillMaxSize().background(GlanceModifier.background(android.graphics.Color.parseColor("#141517")))) {
            Column(modifier = GlanceModifier.fillMaxSize().padding(12.dp)) {
                Text("Fire", style = TextStyle(color = ColorProvider(android.graphics.Color.parseColor("#F57338")), fontSize = 14.sp))
                Spacer(modifier = GlanceModifier.height(8.dp))
                if (unread > 0) {
                    Text("$unread", style = TextStyle(color = ColorProvider(android.graphics.Color.White), fontSize = 28.sp))
                    Text("条未读通知", style = TextStyle(color = ColorProvider(android.graphics.Color.parseColor("#9EA0AB")), fontSize = 12.sp))
                } else {
                    Text("没有未读", style = TextStyle(color = ColorProvider(android.graphics.Color.parseColor("#9EA0AB")), fontSize = 16.sp))
                }
            }
        }
    }
}

class FireUnreadWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = FireUnreadWidget()
}
```

- [ ] **Step 4: Create `fire_unread_widget_info.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="40dp"
    android:minHeight="40dp"
    android:targetCellWidth="2"
    android:targetCellHeight="2"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:initialLayout="@layout/widget_unread"
    android:description="@string/widget_unread_description"
    android:previewLayout="@layout/widget_unread" />
```

- [ ] **Step 5: Create `FireTopicListWidget.kt` — medium topic list widget**

```kotlin
package com.fire.app.widget

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.layout.*
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import org.json.JSONArray

class FireTopicListWidget : GlanceAppWidget() {
    @Composable
    override fun Content() {
        val prefs = currentState preferences
        val titlesJson = prefs[FireWidgetData.TOPIC_TITLES] ?: "[]"
        val titles = try {
            JSONArray(titlesJson).let { arr -> (0 until arr.length()).map { arr.getString(it) } }
        } catch (_: Exception) { emptyList() }

        Column(modifier = GlanceModifier.fillMaxSize().padding(12.dp)) {
            Text("Fire 热门", style = TextStyle(color = ColorProvider(android.graphics.Color.parseColor("#F57338")), fontSize = 13.sp))
            Spacer(modifier = GlanceModifier.height(4.dp))
            titles.take(3).forEach { title ->
                Text(title, style = TextStyle(color = ColorProvider(android.graphics.Color.parseColor("#F6F2EC")), fontSize = 12.sp), maxLines = 1)
                Spacer(modifier = GlanceModifier.height(4.dp))
            }
        }
    }
}

class FireTopicListWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = FireTopicListWidget()
}
```

- [ ] **Step 6: Create `fire_topic_list_widget_info.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp"
    android:minHeight="40dp"
    android:targetCellWidth="4"
    android:targetCellHeight="2"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:initialLayout="@layout/widget_topic_list"
    android:description="@string/widget_topic_list_description"
    android:previewLayout="@layout/widget_topic_list" />
```

- [ ] **Step 7: Register receivers in `AndroidManifest.xml`**

```xml
<receiver android:name=".widget.FireUnreadWidgetReceiver" android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data android:name="android.appwidget.provider"
        android:resource="@xml/fire_unread_widget_info" />
</receiver>
<receiver android:name=".widget.FireTopicListWidgetReceiver" android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data android:name="android.appwidget.provider"
        android:resource="@xml/fire_topic_list_widget_info" />
</receiver>
```

- [ ] **Step 8: Update widget data from `HomeViewModel` after topic list refresh**

```kotlin
// In HomeViewModel after successful topic load:
FireWidgetData.updateWidgetData(
    context = getApplication(),
    unreadCount = notificationCount,
    topicTitlesJson = JSONArray(currentTopics.map { it.title }).toString(),
    username = currentUser?.username ?: ""
)
```

**Commit message:** `feat(widget-android): add Glance-based unread and topic list widgets`

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

- [ ] **Step 1: Create `FireViewUnreadIntent` using AppIntents framework**

```swift
import AppIntents

struct FireViewUnreadIntent: AppIntent {
    static var title: LocalizedStringResource = "查看未读通知"
    static var description = IntentDescription("打开 Fire 的未读通知列表")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Navigate to notifications tab via shared URL scheme
        await UIApplication.shared.open(URL(string: "fire://notifications")!)
        return .result()
    }
}
```

- [ ] **Step 2: Create `FireSearchTopicsIntent`**

```swift
import AppIntents

struct FireSearchTopicsIntent: AppIntent {
    static var title: LocalizedStringResource = "搜索话题"
    static var description = IntentDescription("在 Fire 中搜索话题")
    static var openAppWhenRun = true

    @Parameter(title: "搜索关键词")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let url = URL(string: "fire://search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)")!
        await UIApplication.shared.open(url)
        return .result()
    }
}
```

- [ ] **Step 3: Create `FireViewProfileIntent`**

```swift
import AppIntents

struct FireViewProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "查看个人资料"
    static var description = IntentDescription("打开 Fire 个人资料页")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "fire://profile")!)
        return .result()
    }
}
```

- [ ] **Step 4: Create `FireShortcuts` to group intents**

```swift
import AppIntents

struct FireShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FireViewUnreadIntent(),
            phrases: [
                "查看 \(.applicationName) 未读",
                "打开 \(.applicationName) 通知",
                "View unread in \(.applicationName)"
            ],
            shortTitle: "查看未读",
            systemImageName: "bell.badge"
        )
        AppShortcut(
            intent: FireSearchTopicsIntent(),
            phrases: [
                "在 \(.applicationName) 搜索",
                "Search in \(.applicationName)"
            ],
            shortTitle: "搜索话题",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: FireViewProfileIntent(),
            phrases: [
                "打开 \(.applicationName) 个人资料",
                "View profile in \(.applicationName)"
            ],
            shortTitle: "查看资料",
            systemImageName: "person.circle"
        )
    }
}
```

- [ ] **Step 5: Add deep link handler for `fire://search` and `fire://profile` in main app**

Extend the `onOpenURL` handler from Task 3 to handle these schemes.

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
- Modify: `native/android-app/src/main/java/com/fire/app/core/theme/FireColors.kt`
- Create: `native/ios-app/App/Core/FireOledTheme.swift`

- [ ] **Step 1: Add OLED pure black option to `FireAppearancePreference`**

```swift
enum FireAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case oled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        case .oled: return "纯黑"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .oled: return .dark
        }
    }
}
```

- [ ] **Step 2: Create `FireOledTheme.swift` with pure black overrides**

```swift
extension FireTheme {
    static var isOledMode: Bool {
        // Check stored appearance preference
        UserDefaults.standard.string(forKey: "appearance_preference") == "oled"
    }

    static var oledCanvasTop: Color { Color(red: 0, green: 0, blue: 0) }
    static var oledCanvasMid: Color { Color(red: 0.02, green: 0.02, blue: 0.03) }
    static var oledCanvasBottom: Color { Color(red: 0.04, green: 0.04, blue: 0.05) }
    static var oledPanel: Color { Color(red: 0.06, green: 0.06, blue: 0.07) }
}
```

- [ ] **Step 3: Modify adaptive color resolution to use OLED values when `isOledMode` is true**

Update the `adaptive()` helper in `FireTheme` to check OLED mode and substitute pure black for canvas/surface colors.

- [ ] **Step 4: Add OLED toggle to profile settings**

In `FireProfileView.swift`, add the `oled` option to the appearance picker.

- [ ] **Step 5: Add OLED mode to Android via `FireColors.kt`**

```kotlin
object FireColors {
    var oledMode: Boolean = false

    @ColorInt fun backgroundCanvas(): Int {
        if (oledMode) return Color.BLACK
        return resolveColor(R.color.fire_background_canvas)
    }

    @ColorInt fun backgroundSurface(): Int {
        if (oledMode) return Color.parseColor("#0A0A0B")
        return resolveColor(R.color.fire_background_surface)
    }

    @ColorInt fun backgroundElevated(): Int {
        if (oledMode) return Color.parseColor("#111113")
        return resolveColor(R.color.fire_background_elevated)
    }
}
```

- [ ] **Step 6: Run contrast ratio checks**

Verify all text-on-background combinations pass WCAG AA (4.5:1 for normal text, 3:1 for large text) in both dark and OLED modes. Document any failures and adjust.

**Commit message:** `feat(dark-mode): add OLED pure black option and contrast ratio validation`

## Architectural Notes

- **Rust ownership boundary:** Offline cache tables live in `fire-store` and are written/read only by `fire-core`. Platforms never touch SQLite directly — they receive cached or fresh data through the same UniFFI call path. This preserves the "Rust owns data" boundary.
- **No new external dependencies:** Glance and Material Dynamic Colors are part of the standard AndroidX/Material libraries already used. WidgetKit and AppIntents ship with iOS 17+ SDK. No third-party packages are added.
- **Backward compatibility:** Material You falls back to static Fire colors on API < 31. Siri Shortcuts require iOS 17+ but do not break iOS 16 builds. Glance widgets require API 31+ but gracefully degrade.
- **Widget memory:** iOS widget timelines are capped at 30-minute refresh intervals and read from lightweight UserDefaults data — no Rust FFI calls in the widget extension process.
- **Motion accessibility:** Decorative motion is gated or degraded through `FireMotionTokens` / `fireRespectingReduceMotion`. Haptics use SwiftUI `sensoryFeedback` where available and the small `FireMotionHaptics` UIKit bridge for Texture cells.
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
- `native/ios-app/App/Widget/FireWidgetData.swift` — Shared data model for widget communication
- `native/ios-app/App/Widget/FireWidgetEntry.swift` — Timeline entry and provider types
- `native/ios-app/App/Widget/FireWidgetBundle.swift` — Widget extension entry point
- `native/ios-app/App/Widget/FireSmallWidget.swift` — Small unread count widget
- `native/ios-app/App/Widget/FireMediumWidget.swift` — Medium trending topics widget
- `native/ios-app/App/Widget/FireLargeWidget.swift` — Large timeline widget
- `native/ios-app/App/ViewModels/FireAppViewModel.swift` — Widget data update, deep link handler
- `native/android-app/src/main/java/com/fire/app/widget/FireWidgetData.kt` — Android widget shared state
- `native/android-app/src/main/java/com/fire/app/widget/FireUnreadWidget.kt` — Unread count Glance widget
- `native/android-app/src/main/java/com/fire/app/widget/FireTopicListWidget.kt` — Topic list Glance widget
- `native/android-app/src/main/res/xml/fire_unread_widget_info.xml` — Widget metadata
- `native/android-app/src/main/res/xml/fire_topic_list_widget_info.xml` — Widget metadata
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
