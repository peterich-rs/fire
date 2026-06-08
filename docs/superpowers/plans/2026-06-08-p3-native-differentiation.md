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

3. **Shimmer replaces `.redacted(reason: .placeholder)` everywhere.** The SwiftUI redaction API produces static gray blocks that look broken, not loading. A custom `FireShimmerView` with an animated gradient sweep matches the visual polish bar set by `FireTheme`. On Android, a custom `ShimmerLayout` wraps existing `RecyclerView` item layouts without changing their structure.

4. **Haptic feedback is gated behind `UIAccessibility.isReduceMotionEnabled`.** All haptic generators check this flag before firing. This is not optional polish — it is an accessibility requirement that Apple enforces during review.

5. **Material You uses `DynamicColors` from the Material component library.** Android already depends on `com.google.android.material`. Dynamic Color support is a one-time theme configuration, not a new dependency. The `FireColors.kt` resolver pattern is extended with a `dynamicColorsEnabled` check that falls back to static colors on API < 31.

6. **Toast component replaces non-critical `.alert()` calls.** Six `.alert()` call sites in the iOS app are used for non-critical feedback (e.g., "saved", "copied"). These should be non-modal toasts. Critical confirmations (logout, delete) remain as `.alert()`.

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
// iOS: toast component
struct FireToastView: View {
    let message: String
    let icon: String?
    let style: FireToastStyle
    @Binding var isPresented: Bool
}

enum FireToastStyle {
    case success, error, info, warning
}
```

## Phased Implementation

### Task 1: Toast/Snackbar Component (iOS + Android)

**Files:**
- Create: `native/ios-app/App/Core/FireToast.swift`
- Modify: `native/ios-app/App/Core/FireComponents.swift`
- Create: `native/android-app/src/main/java/com/fire/app/core/ui/FireToast.kt`
- Modify: `native/ios-app/App/Views/Home/FireHomeView.swift`
- Modify: `native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift`
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift`

- [ ] **Step 1: Create `FireToastStyle` enum and `FireToastView` in `native/ios-app/App/Core/FireToast.swift`**

```swift
import SwiftUI

enum FireToastStyle {
    case success, error, info, warning

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .success: return FireTheme.success
        case .error: return Color.red
        case .info: return FireTheme.accent
        case .warning: return FireTheme.warning
        }
    }
}

struct FireToastView: View {
    let message: String
    let style: FireToastStyle
    @Binding var isPresented: Bool
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: style.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(style.tintColor)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(FireTheme.ink)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FireTheme.chromeStrong)
        .clipShape(RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { opacity = 1 }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.25)) { opacity = 0 }
                try? await Task.sleep(for: .seconds(0.3))
                isPresented = false
            }
        }
    }
}

extension View {
    func fireToast(_ message: String, style: FireToastStyle = .info, isPresented: Binding<Bool>) -> some View {
        overlay(alignment: .top) {
            if isPresented.wrappedValue {
                FireToastView(message: message, style: style, isPresented: isPresented)
                    .padding(.top, 60)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: isPresented.wrappedValue)
    }
}
```

- [ ] **Step 2: Create `FireToast` Android component in `native/android-app/src/main/java/com/fire/app/core/ui/FireToast.kt`**

```kotlin
package com.fire.app.core.ui

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.google.android.material.snackbar.Snackbar

object FireToast {

    enum class Style { SUCCESS, ERROR, INFO, WARNING }

    fun show(anchor: View, message: String, style: Style = Style.INFO) {
        val snackbar = Snackbar.make(anchor, message, Snackbar.LENGTH_SHORT)
        val context = anchor.context
        snackbar.setBackgroundTint(resolveBackgroundColor(context, style))
        snackbar.setTextColor(resolveTextColor(context, style))
        snackbar.show()
    }

    private fun resolveBackgroundColor(context: Context, style: Style): Int {
        return when (style) {
            Style.SUCCESS -> com.fire.app.R.color.fire_success
            Style.ERROR -> com.fire.app.R.color.fire_error
            Style.INFO -> com.fire.app.R.color.fire_accent
            Style.WARNING -> com.fire.app.R.color.fire_warning
        }.let { context.getColor(it) }
    }

    private fun resolveTextColor(context: Context, style: Style): Int {
        return context.getColor(android.R.color.white)
    }
}
```

- [ ] **Step 3: Replace non-critical `.alert()` in `FireHomeView.swift` (line 156) with `fireToast` modifier**

Find the `.alert("提示", isPresented: ...)` at line 156 and replace with a toast binding. This alert is for non-critical feedback (e.g., topic action result).

- [ ] **Step 4: Replace non-critical `.alert()` in `FireDraftsView.swift` (line 211) and `FirePrivateMessagesView.swift` (line 354)**

Same pattern — these are informational "提示" alerts that should be non-modal.

- [ ] **Step 5: Add `showToast` calls in Android composer/bookmark/reaction flows**

In `ComposerViewModel.kt` and `BookmarksViewModel.kt`, replace any Toast.makeText() calls with `FireToast.show()`.

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
- Create: `native/ios-app/App/Core/FireHaptics.swift`
- Modify: interaction points across iOS views (see specific files below)

- [ ] **Step 1: Create `FireHaptics.swift` with accessibility-gated haptic wrappers**

```swift
import UIKit

enum FireHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func selection() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    static func success() { notification(.success) }
    static func error() { notification(.error) }
    static func warning() { notification(.warning) }
}
```

- [ ] **Step 2: Add haptics to like toggle, reaction toggle, bookmark toggle**

In the interaction handler for each toggle (likely in `FireTopicDetailModalViews.swift`, `FireTopicRow.swift`, and `FireBookmarksView.swift`):

```swift
// Like toggle:
FireHaptics.impact(.medium)
// Reaction toggle:
FireHaptics.selection()
// Bookmark toggle:
FireHaptics.impact(.light)
```

- [ ] **Step 3: Add haptics to pull-to-refresh completion in `FireHomeView.swift`**

```swift
// After refresh completes:
FireHaptics.impact()
```

- [ ] **Step 4: Add haptics to send success/failure in composer**

In `FireComposerView.swift` or `FirePostEditorView.swift`:

```swift
// On send success:
FireHaptics.success()
// On send failure:
FireHaptics.error()
```

- [ ] **Step 5: Add haptics to tab switch, context menu, long press**

```swift
// Tab switch in FireTabRoot:
FireHaptics.selection()
// Context menu presentation:
FireHaptics.impact(.medium)
// Long press on topic row:
FireHaptics.impact(.medium)
```

**Commit message:** `feat(haptics): add accessibility-gated haptic feedback to all interaction points`

---

### Task 8: Offline Cache Layer (Rust)

**Files:**
- Modify: `rust/crates/fire-store/src/migrations.rs` (add migration 4)
- Modify: `rust/crates/fire-store/src/lib.rs` (add cache read/write methods)
- Modify: `rust/crates/fire-core/src/core/topics.rs` (add cache integration to fetch)
- Modify: `rust/crates/fire-core/src/core/notifications.rs` (add cache integration)
- Modify: `rust/crates/fire-uniffi/src/lib.rs` (expose cache methods if needed)

- [ ] **Step 1: Add Migration 4 for topic list and notification cache tables in `migrations.rs`**

```rust
const MIGRATION_4: &str = r#"
CREATE TABLE IF NOT EXISTS topic_list_cache (
    auth_scope_hash TEXT NOT NULL,
    scope_key TEXT NOT NULL,
    page INTEGER NOT NULL,
    payload_json TEXT NOT NULL,
    fetched_at_ms INTEGER NOT NULL,
    PRIMARY KEY (auth_scope_hash, scope_key, page)
);

CREATE TABLE IF NOT EXISTS notification_list_cache (
    auth_scope_hash TEXT NOT NULL,
    scope_key TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    fetched_at_ms INTEGER NOT NULL,
    PRIMARY KEY (auth_scope_hash, scope_key)
);
"#;
```

Add the migration runner:

```rust
if current_version < 4 {
    connection.execute_batch(MIGRATION_4)?;
    connection.execute(
        "INSERT OR IGNORE INTO schema_migrations (version, applied_at_ms) VALUES (4, ?1)",
        [now_ms()],
    )?;
}
```

- [ ] **Step 2: Add `topic_list_cache_write` and `topic_list_cache_read` methods to `FireStore` in `lib.rs`**

```rust
pub fn topic_list_cache_write(
    &self,
    auth_scope_hash: &str,
    scope_key: &str,
    page: u32,
    payload_json: &str,
) -> Result<(), FireStoreError> {
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    self.connection.execute(
        "INSERT OR REPLACE INTO topic_list_cache (auth_scope_hash, scope_key, page, payload_json, fetched_at_ms) VALUES (?1, ?2, ?3, ?4, ?5)",
        rusqlite::params![auth_scope_hash, scope_key, page, payload_json, now_ms],
    )?;
    Ok(())
}

pub fn topic_list_cache_read(
    &self,
    auth_scope_hash: &str,
    scope_key: &str,
    page: u32,
) -> Result<Option<String>, FireStoreError> {
    let mut stmt = self.connection.prepare(
        "SELECT payload_json FROM topic_list_cache WHERE auth_scope_hash = ?1 AND scope_key = ?2 AND page = ?3 ORDER BY fetched_at_ms DESC LIMIT 1"
    )?;
    let mut rows = stmt.query(rusqlite::params![auth_scope_hash, scope_key, page])?;
    match rows.next()? {
        Some(row) => Ok(Some(row.get(0)?)),
        None => Ok(None),
    }
}
```

- [ ] **Step 3: Add `notification_list_cache_write` and `notification_list_cache_read` methods to `FireStore`**

Same pattern as topic list, but with `notification_list_cache` table and `scope_key` only (no page).

- [ ] **Step 4: Add cache write after successful topic list fetch in `topics.rs`**

In the `fetch_topic_list` method (or equivalent in `FireCore`), after a successful API response, serialize the response and call `store.topic_list_cache_write()` with the scope key derived from `kind:category_id:tag`.

- [ ] **Step 5: Add read-through cache fallback on network error in `topics.rs`**

When `fetch_topic_list` encounters a network error, attempt `store.topic_list_cache_read()`. If a cache hit exists, return the cached payload. If no cache exists, propagate the original error.

- [ ] **Step 6: Add same cache write/fallback for notifications in `notifications.rs`**

- [ ] **Step 7: Add cache invalidation on logout in `session.rs`**

```rust
// In logout_local() or equivalent:
store.connection.execute("DELETE FROM topic_list_cache WHERE auth_scope_hash = ?1", [auth_scope_hash])?;
store.connection.execute("DELETE FROM notification_list_cache WHERE auth_scope_hash = ?1", [auth_scope_hash])?;
```

- [ ] **Step 8: Verify with `cargo test -p fire-store` and `cargo test -p fire-core`**

```bash
cargo test -p fire-store
cargo test -p fire-core
cargo build -p fire-uniffi
```

**Commit message:** `feat(offline-cache): add Rust-side topic list and notification cache with read-through fallback`

---

### Task 9: Offline Cache Layer (iOS)

**Files:**
- Create: `native/ios-app/App/Core/FireOfflineBanner.swift`
- Modify: `native/ios-app/App/Stores/FireHomeFeedStore.swift`
- Modify: `native/ios-app/App/Stores/FireNotificationStore.swift`
- Modify: `native/ios-app/App/Views/Home/FireHomeView.swift`

- [ ] **Step 1: Create `FireOfflineBanner.swift`**

```swift
import SwiftUI

struct FireOfflineBanner: View {
    let message: String
    @Binding var isDismissed: Bool

    var body: some View {
        if !isDismissed {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(FireTheme.warning)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(FireTheme.subtleInk)
                Spacer()
                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FireTheme.tertiaryInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(FireTheme.warning.opacity(0.10))
        }
    }
}
```

- [ ] **Step 2: Add `isOffline` published property to `FireHomeFeedStore`**

```swift
@Published private(set) var isOffline = false
@Published private(set) var showOfflineBanner = false
```

- [ ] **Step 3: Set `isOffline = true` when Rust core returns cached data (read-through path)**

The Rust FFI layer should expose whether the response came from cache. Add a flag or check `topicLoadErrorMessage` for network-related errors with existing data.

- [ ] **Step 4: Add `isOffline` tracking to `FireNotificationStore`**

Same pattern as `FireHomeFeedStore`.

- [ ] **Step 5: Add `FireOfflineBanner` to `FireHomeView`**

```swift
VStack(spacing: 0) {
    FireOfflineBanner(
        message: "离线模式 — 显示缓存内容",
        isDismissed: $offlineBannerDismissed
    )
    // ... existing content
}
```

**Commit message:** `feat(offline-ios): add offline banner and cache-aware state to iOS home and notification views`

---

### Task 10: Offline Cache Layer (Android)

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/data/paging/TopicListPagingSource.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/data/paging/NotificationPagingSource.kt`
- Create: `native/android-app/src/main/java/com/fire/app/core/ui/FireOfflineBanner.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/home/HomeFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationsFragment.kt`

- [ ] **Step 1: Modify `TopicListPagingSource` to return cached data on error**

```kotlin
override suspend fun load(params: LoadParams<UInt>): LoadResult<UInt, TopicRowState> {
    val page = params.key ?: 0u
    return try {
        val response = repository.fetchTopicList(
            kind = kind,
            page = params.key,
            categorySlug = categorySlug,
            categoryId = categoryId,
            parentCategorySlug = parentCategorySlug,
            tag = tag,
            additionalTags = additionalTags,
            matchAllTags = matchAllTags,
        )
        LoadResult.Page(
            data = response.rows,
            prevKey = if (page == 0u) null else page - 1u,
            nextKey = response.nextPage,
        )
    } catch (e: Exception) {
        val cached = repository.fetchCachedTopicList(kind, page)
        if (cached != null) {
            LoadResult.Page(
                data = cached.rows,
                prevKey = if (page == 0u) null else page - 1u,
                nextKey = cached.nextPage,
            )
        } else {
            LoadResult.Error(e)
        }
    }
}
```

- [ ] **Step 2: Add `fetchCachedTopicList()` to `TopicRepository`**

```kotlin
suspend fun fetchCachedTopicList(kind: TopicListKindState, page: UInt): TopicListState? =
    withContext(Dispatchers.Default) {
        sessionStore.fetchCachedTopicList(kind, page)
    }
```

- [ ] **Step 3: Apply same pattern to `NotificationPagingSource` and `NotificationRepository`**

- [ ] **Step 4: Create `FireOfflineBanner.kt`**

```kotlin
package com.fire.app.core.ui

import android.content.Context
import android.util.AttributeSet
import android.widget.LinearLayout
import android.widget.TextView
import com.fire.app.R

class FireOfflineBanner @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : LinearLayout(context, attrs, defStyle) {

    init {
        orientation = HORIZONTAL
        inflate(context, R.layout.view_offline_banner, this)
    }

    fun setMessage(message: String) {
        findViewById<TextView>(R.id.offline_message).text = message
    }
}
```

- [ ] **Step 5: Add banner layout `view_offline_banner.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:paddingHorizontal="16dp"
    android:paddingVertical="10dp"
    android:background="#1AFF9800">
    <TextView
        android:id="@+id/offline_message"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:textColor="@color/fire_text_secondary"
        android:textSize="14sp" />
</LinearLayout>
```

- [ ] **Step 6: Add offline banner visibility to `HomeFragment` and `NotificationsFragment`**

Show the banner above the `RecyclerView` when the PagingSource returns cached data. Track this with a LiveData or state flow flag.

**Commit message:** `feat(offline-android): add cache-aware PagingSource fallback and offline banner`

---

### Task 11: Shimmer Loading Animation (iOS)

**Files:**
- Create: `native/ios-app/App/Core/FireShimmer.swift`
- Modify: all list views that currently use `.redacted(reason: .placeholder)`

- [ ] **Step 1: Create `FireShimmer.swift`**

```swift
import SwiftUI

struct FireShimmerView: View {
    @State private var phase: CGFloat = 0
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = FireTheme.smallCornerRadius) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: FireTheme.softSurface, location: 0),
                            .init(color: FireTheme.track, location: max(0, phase - 0.2)),
                            .init(color: FireTheme.softSurface, location: min(1, phase + 0.05)),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct FireShimmerRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                FireShimmerView(cornerRadius: 20)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 6) {
                    FireShimmerView(cornerRadius: 6).frame(height: 14)
                    FireShimmerView(cornerRadius: 6).frame(width: 120, height: 12)
                }
            }
            FireShimmerView(cornerRadius: 8)
                .frame(height: 16)
                .padding(.trailing, 40)
            HStack {
                FireShimmerView(cornerRadius: FireTheme.chipCornerRadius)
                    .frame(width: 60, height: 24)
                Spacer()
                FireShimmerView(cornerRadius: 6).frame(width: 80, height: 12)
            }
        }
        .padding(16)
        .background(FireTheme.canvasMid)
    }
}
```

- [ ] **Step 2: Find all `.redacted(reason: .placeholder)` usages**

Search across all views in `native/ios-app/App/Views/` for `.redacted(reason: .placeholder)` and replace with `FireShimmerRow`.

- [ ] **Step 3: Replace redacted placeholders in `FireHomeView.swift`**

Where the loading state shows redacted rows, replace with:

```swift
ForEach(0..<5, id: \.self) { _ in
    FireShimmerRow()
}
```

- [ ] **Step 4: Replace redacted placeholders in `FireNotificationsView.swift`, `FireSearchView.swift`, `FireBookmarksView.swift`**

Same pattern. Use `FireShimmerRow` or a simplified variant appropriate for the row shape.

**Commit message:** `feat(shimmer-ios): replace redacted placeholders with animated shimmer loading views`

---

### Task 12: Shimmer Loading Animation (Android)

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/core/ui/ShimmerLayout.kt`
- Create: `native/android-app/src/main/res/layout/item_topic_shimmer.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/home/HomeFragment.kt`

- [ ] **Step 1: Create `ShimmerLayout.kt`**

```kotlin
package com.fire.app.core.ui

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import android.widget.FrameLayout
import com.fire.app.R

class ShimmerLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : FrameLayout(context, attrs, defStyle) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var shimmerTranslate = 0f
    private var animator: ValueAnimator? = null

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val gradientWidth = w * 0.4f
        paint.shader = LinearGradient(
            -gradientWidth, 0f, gradientWidth, 0f,
            intArrayOf(0x0DFFFFFF, 0x1AFFFFFF, 0x0DFFFFFF),
            null,
            Shader.TileMode.CLAMP
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(shimmerTranslate, 0f, width.toFloat(), height.toFloat(), paint)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        animator = ValueAnimator.ofFloat(0f, (width + paint.shader).toFloat().coerceAtLeast(width.toFloat() * 2)).apply {
            duration = 1200
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                shimmerTranslate = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    override fun onDetachedFromWindow() {
        animator?.cancel()
        animator = null
        super.onDetachedFromWindow()
    }
}
```

- [ ] **Step 2: Create `item_topic_shimmer.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="16dp"
    android:background="@color/fire_background_canvas">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical">

        <View
            android:layout_width="36dp"
            android:layout_height="36dp"
            android:background="@color/fire_background_elevated" />

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginStart="10dp"
            android:orientation="vertical">

            <View
                android:layout_width="200dp"
                android:layout_height="14dp"
                android:background="@color/fire_background_elevated" />

            <View
                android:layout_width="120dp"
                android:layout_height="12dp"
                android:layout_marginTop="6dp"
                android:background="@color/fire_background_elevated" />
        </LinearLayout>
    </LinearLayout>

    <View
        android:layout_width="match_parent"
        android:layout_height="16dp"
        android:layout_marginTop="10dp"
        android:background="@color/fire_background_elevated" />

    <View
        android:layout_width="80dp"
        android:layout_height="12dp"
        android:layout_marginTop="8dp"
        android:background="@color/fire_background_elevated" />

</LinearLayout>
```

- [ ] **Step 3: Add shimmer loading state to `HomeFragment`**

Show 5 shimmer items in the `RecyclerView` when `HomeViewModel` is in initial loading state (before first page arrives).

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
- Modify: `native/android-app/src/main/res/values/colors.xml`
- Create: `native/android-app/src/main/res/values-night/colors.xml` (if not exists)
- Modify: `native/android-app/src/main/java/com/fire/app/MainActivity.kt`
- Modify: `native/android-app/src/main/res/values/styles.xml`

- [ ] **Step 1: Add Material You dynamic color support to `FireColors.kt`**

```kotlin
object FireColors {
    private var dynamicColorsEnabled = false

    fun setDynamicColorsEnabled(enabled: Boolean) {
        dynamicColorsEnabled = enabled
    }

    @ColorInt fun accent(): Int {
        if (dynamicColorsEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return resolveDynamicColor(android.R.attr.colorPrimary)
        }
        return resolveColor(R.color.fire_accent)
    }

    @ColorInt fun accentSoft(): Int {
        if (dynamicColorsEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return resolveDynamicColor(com.google.android.material.R.attr.colorPrimaryVariant)
        }
        return resolveColor(R.color.fire_accent_soft)
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun resolveDynamicColor(@AttrRes attr: Int): Int {
        val context = FireApplication.getInstance()
        val typedValue = android.util.TypedValue()
        context.theme.resolveAttribute(attr, typedValue, true)
        return typedValue.data
    }

    // ... existing methods unchanged
}
```

- [ ] **Step 2: Apply Dynamic Colors in `FireApplication.kt`**

```kotlin
import com.google.android.material.color.DynamicColors

class FireApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (DynamicColors.isDynamicColorAvailable()) {
            DynamicColors.applyToActivitiesIfAvailable(this)
            FireColors.setDynamicColorsEnabled(true)
        }
    }
}
```

- [ ] **Step 3: Enable edge-to-edge rendering in `MainActivity.kt`**

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    // ...
}
```

Requires `import androidx.activity.enableEdgeToEdge`.

- [ ] **Step 4: Add Predictive Back Gesture support**

In `AndroidManifest.xml`, ensure `android:enableOnBackInvokedCallback="true"` is set on the `<application>` tag. This enables the Android 14+ predictive back animation.

- [ ] **Step 5: Add night-mode color resources**

Create `native/android-app/src/main/res/values-night/colors.xml` with dark-mode color overrides that match the `FireTheme` dark values from iOS.

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
- **Haptic accessibility:** Every haptic call is gated behind `UIAccessibility.isReduceMotionEnabled`. Skipping this will trigger App Store review rejection.
- **Cache staleness:** Cache entries have no TTL — they are invalidated on logout and overwritten on every successful fetch. This is intentional: stale data is better than no data for offline mode, and the next successful fetch always replaces it.
- **OLED mode scope:** OLED mode only affects dark-theme canvas/surface colors. Text, accent, and semantic colors remain unchanged to maintain contrast ratios.

## File Change Summary

- `native/ios-app/App/Core/FireToast.swift` — Toast component with auto-dismiss and style variants
- `native/ios-app/App/Core/FireComponents.swift` — Reference toast modifier additions
- `native/android-app/src/main/java/com/fire/app/core/ui/FireToast.kt` — Snackbar-based Android toast
- `native/ios-app/App/Views/Home/FireHomeView.swift` — Replace alert with toast, add offline banner
- `native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift` — Replace alert with toast
- `native/ios-app/App/Views/Composer/FireComposerView.swift` — Replace alert with toast
- `native/ios-app/App/Views/Other/FireDraftsView.swift` — Replace alert with toast
- `native/ios-app/App/Views/Messages/FirePrivateMessagesView.swift` — Replace alert with toast
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
- `native/ios-app/App/Core/FireHaptics.swift` — Accessibility-gated haptic feedback wrapper
- `native/ios-app/App/Views/Home/FireTopicRow.swift` — Add haptics to like/bookmark/long-press
- `native/ios-app/App/Views/Other/FireTabRoot.swift` — Add haptics to tab switch
- `native/ios-app/App/TopicDetail/Support/FireTopicDetailModalViews.swift` — Add haptics to interactions
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
- `native/ios-app/App/Core/FireShimmer.swift` — SwiftUI shimmer animation component
- `native/ios-app/App/Intents/FireShortcuts.swift` — App Shortcuts provider
- `native/ios-app/App/Intents/FireViewUnreadIntent.swift` — View unread intent
- `native/ios-app/App/Intents/FireSearchTopicsIntent.swift` — Search intent
- `native/ios-app/App/Intents/FireViewProfileIntent.swift` — View profile intent
- `native/android-app/src/main/java/com/fire/app/core/theme/FireColors.kt` — Dynamic Color + OLED mode
- `native/android-app/src/main/java/com/fire/app/FireApplication.kt` — Dynamic Color initialization
- `native/android-app/src/main/java/com/fire/app/MainActivity.kt` — Edge-to-edge
- `native/ios-app/App/Core/FireOledTheme.swift` — OLED pure black color overrides
- `native/ios-app/App/Core/FireTheme.swift` — OLED mode integration
