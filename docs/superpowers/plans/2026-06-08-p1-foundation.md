# P1 基础夯实 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除视觉不一致、补齐 Accessibility、统一架构模式、Android 核心页面补全

**Architecture:** iOS 侧已聚焦 FireTheme Token 统一、通用分页 Store 提取、FireAppViewModel 拆分；Android 侧已补全草稿列表、FCM 本地通知接入、阅读历史、通知历史和话题阅读计时。两端共享上下文菜单、空状态组件、Shimmer 动画等模式。

**Tech Stack:** SwiftUI / UIKit (iOS), Kotlin + ViewBinding + Paging 3 (Android), Rust UniFFI (shared core)

---

## File Structure

### iOS Changes

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `App/Core/FireTheme.swift` | 新增 corner radius / surface token |
| Modify | `App/Core/FireComponents.swift` | 统一空状态、新增 Shimmer |
| Create | `App/Core/FireShimmerModifier.swift` | Shimmer 动画修饰器 |
| Create | `App/Core/FireContextMenus.swift` | 可复用上下文菜单构建器 |
| Create | `App/Stores/FirePaginatedStore.swift` | 通用分页 Store 基类 |
| Modify | `App/Stores/FireHomeFeedStore.swift` | 适配新 Token |
| Modify | `App/Stores/FireNotificationStore.swift` | 提取通用模式 |
| Modify | `App/Stores/FireSearchStore.swift` | 继承 FirePaginatedStore |
| Modify | `App/ViewModels/FireAppViewModel.swift` | 拆分服务层和门面扩展 |
| Create | `App/ViewModels/FireAppViewModelSupport.swift` | 支撑类型、错误、状态观察协调器、搜索 scope |
| Create | `App/ViewModels/FireAppViewModel+Diagnostics.swift` | 诊断、日志、网络 trace、APM facade |
| Create | `App/ViewModels/FireAppViewModel+Profile.swift` | 个人资料、关注、邀请、徽章、LDC/CDK facade |
| Create | `App/ViewModels/FireAppViewModel+RecoveryURLs.swift` | Cloudflare 恢复 URL 构建 |
| Create | `App/Services/FireTopicInteractionService.swift` | 话题交互服务 |
| Create | `App/Services/FireNotificationService.swift` | 通知服务 |
| Create | `App/Services/FireSearchService.swift` | 搜索服务 |
| Modify | `App/Views/*.swift` | Token 替换、Accessibility 标注、上下文菜单 |

### Android Changes

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ui/drafts/DraftsFragment.kt` | 草稿列表页 |
| Create | `ui/drafts/DraftsViewModel.kt` | 草稿 ViewModel |
| Create | `ui/drafts/DraftsAdapter.kt` | 草稿列表适配器 |
| Create | `ui/readhistory/ReadHistoryFragment.kt` | 阅读历史页 |
| Create | `ui/readhistory/ReadHistoryViewModel.kt` | 阅读历史 ViewModel |
| Create | `ui/notifications/NotificationHistoryFragment.kt` | 通知历史全屏页 |
| Create | `push/FireFirebaseMessagingService.kt` | FCM 推送服务 |
| Create | `core/theme/FireShimmerLayout.kt` | Shimmer 动画布局 |
| Modify | `build.gradle.kts` | 添加 Firebase 依赖 |
| Modify | `res/navigation/fire_nav_graph.xml` | 新增导航目标 |

---

## Task 1: iOS FireTheme Token 统一

**Files:**
- Modify: `native/ios-app/App/Core/FireTheme.swift`
- Modify: `native/ios-app/App/Core/FireComponents.swift`
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift`
- Modify: `native/ios-app/App/Views/Other/FireOnboardingView.swift`
- Modify: `native/ios-app/App/Views/Search/FireSearchView.swift`

- [x] **Step 1: 新增 corner radius Token 和 surface Token**

`FireTheme` now defines:

```swift
extension FireTheme {
    static let cornerRadius: CGFloat = 20
    static let mediumCornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 10
    static let chipCornerRadius: CGFloat = 100
    static let panelShadowRadius: CGFloat = 16
    static let panelShadowY: CGFloat = 8
}
```

It also exposes semantic `canvas`, `surface`, and `surfaceSecondary` colors for SwiftUI surfaces.

- [x] **Step 2: 全局搜索并替换硬编码圆角值**

搜索模式及替换目标：

| 搜索 | 替换为 |
|------|--------|
| `cornerRadius: 16` (非 FireTheme 引用) | `cornerRadius: FireTheme.cornerRadius` |
| `cornerRadius: 18` | `cornerRadius: FireTheme.cornerRadius` |
| `cornerRadius: 12` | `cornerRadius: FireTheme.mediumCornerRadius` |
| `cornerRadius: 10` | `cornerRadius: FireTheme.smallCornerRadius` |

涉及文件（需逐一检查确认）：
- `App/Core/FireComponents.swift`
- `App/Views/FireComposerView.swift`
- `App/Views/FireOnboardingView.swift`
- `App/Views/FireSearchView.swift`
- `App/Views/FireTopicRow.swift`

Verified scoped search over `FireTheme.swift`, `FireComponents.swift`, `FireComposerView.swift`, `FireOnboardingView.swift`, `FireSearchView.swift`, and `FireTopicRow.swift` no longer finds the listed hardcoded radius patterns.

- [x] **Step 3: 替换背景色硬编码**

| 搜索模式 | 替换为 |
|----------|--------|
| `Color(.systemGroupedBackground)` | `FireTheme.canvasMid` |
| `Color(.secondarySystemBackground)` | `FireTheme.surface` |
| `Color.black.opacity(0.06)` | `FireTheme.divider` |
| `Color.black.opacity(0.` 任何描边 | `FireTheme.divider` |

`FireComposerView` now uses `FireTheme.canvas` for the page background and `FireTheme.surface` for composer panels. The scoped search no longer finds `Color(.systemGroupedBackground)` or `Color(.secondarySystemBackground)` in the planned files.

- [x] **Step 4: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

Result: build succeeded. Existing warnings remain from `UITextItemInteraction`, no-op `await`, Swift 6 capture diagnostics, and related pre-existing code.

- [x] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md \
  native/ios-app/App/Core/FireTheme.swift \
  native/ios-app/App/Core/FireComponents.swift \
  native/ios-app/App/Views/Composer/FireComposerView.swift \
  native/ios-app/App/Views/Other/FireOnboardingView.swift \
  native/ios-app/App/Views/Search/FireSearchView.swift
git commit -m "refactor(ios): unify corner radius and background tokens across FireTheme"
```

---

## Task 2: iOS Feed Kind Selector 统一

**Files:**
- Modify: `native/ios-app/App/Views/FireFilteredTopicListView.swift`
- Reference: `native/ios-app/App/Core/FireComponents.swift` (contains `FireFeedKindSelector`)

- [x] **Step 1: 定位 FireFilteredTopicListView 中的简易筛选器**

读取 `FireFilteredTopicListView.swift`，找到使用 `Capsule().fill()` 的筛选器代码段。

- [x] **Step 2: 替换为 FireFeedKindSelector**

将内联的 Capsule 筛选器替换为 `FireFeedKindSelector`（使用 `matchedGeometryEffect` 的版本），确保与首页视觉完全一致。

实际集成参数：
- `selectedKind: TopicListKindState`
- `namespace: Namespace.ID`
- `onSelect: (TopicListKindState) -> Void`

- [x] **Step 3: 构建验证**

Verified:
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

- [x] **Step 4: Commit**

```bash
git add native/ios-app/App/Views/FireFilteredTopicListView.swift
git commit -m "refactor(ios): unify feed kind selector between home and filtered views"
```

---

## Task 3: iOS Feed Kind 标题语言统一

**Files:**
- Modify: `native/ios-app/App/Core/SessionState+Helpers.swift`（或 TopicListKindState extension 所在文件）

- [x] **Step 1: 定位 TopicListKindState.title 定义**

搜索 `TopicListKindState` 的 `title` computed property。当前返回英文如 "Latest", "New"。

- [x] **Step 2: 统一为中文标题**

```swift
var title: String {
    switch self {
    case .latest: return "最新"
    case .new: return "最新发布"
    case .unread: return "未读"
    case .unseen: return "未看"
    case .hot: return "热门"
    case .top: return "精华"
    case .privateMessagesInbox: return "收件箱"
    case .privateMessagesSent: return "已发送"
    }
}
```

- [x] **Step 3: 构建验证**

Verified:
- `cd native/ios-app && xcodebuild test -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -only-testing:FireTests/FireEntityStateTests`
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

- [x] **Step 4: Commit**

```bash
git add -u
git commit -m "fix(ios): unify feed kind titles to Chinese"
```

---

## Task 4: iOS Accessibility 标注 — 话题行和首页

**Files:**
- Modify: `native/ios-app/App/Views/FireTopicRow.swift`
- Modify: `native/ios-app/App/Views/FireHomeView.swift`

- [x] **Step 1: FireTopicRow Accessibility**

为 `FireTopicRow` 添加 accessibility 标注：

```swift
.accessibilityElement(children: .combine)
.accessibilityLabel("\(topic.title), \(topic.categoryName ?? ""), \(topic.replyCount) 回复, \(topic.views) 浏览")
.accessibilityHint("双击查看话题详情")
```

- [x] **Step 2: FireHomeView 按钮标注**

为图标按钮添加 `accessibilityLabel`：

```swift
// 搜索按钮
.accessibilityLabel("搜索")

// 创建话题按钮
.accessibilityLabel("创建新话题")
```

- [x] **Step 3: Skeleton 视图隐藏**

所有骨架屏视图添加 `.accessibilityHidden(true)`。

- [x] **Step 4: 构建验证**

Verified:
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

- [x] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md native/ios-app/App/Core/FireComponents.swift native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift native/ios-app/App/Views/Home/FireTopicRow.swift native/ios-app/App/Views/Home/FireHomeView.swift
git commit -m "a11y(ios): add accessibility labels to topic rows and home buttons"
```

---

## Task 5: iOS Accessibility 标注 — 编辑器、搜索、通知、其他

**Files:**
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift`
- Modify: `native/ios-app/App/Views/Messages/FireRecipientTokenField.swift`
- Modify: `native/ios-app/App/Views/Search/FireSearchView.swift`
- Modify: `native/ios-app/App/Views/Notifications/FireNotificationsView.swift`
- Modify: `native/ios-app/App/Views/Notifications/FireNotificationHistoryView.swift`
- Modify: `native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift`
- Modify: `native/ios-app/App/Views/Other/FireDraftsView.swift`
- Modify: `native/ios-app/App/Views/Other/FireOnboardingView.swift`
- Modify: `native/ios-app/App/Views/Profile/FireProfileView.swift`
- Modify: `native/ios-app/App/Views/Profile/FireProfileActivityRow.swift`
- Modify: `native/ios-app/App/Views/Profile/FireProfileHeaderComponents.swift`

- [x] **Step 1: FireComposerView 工具栏按钮标注**

为编辑器工具栏按钮添加 accessibility 标注：

```swift
// 上传图片按钮
.accessibilityLabel("上传图片")
// 预览按钮
.accessibilityLabel("切换预览")
// 发送按钮
.accessibilityLabel("发送")
// 草稿保存状态
.accessibilityLabel("草稿已自动保存")
```

- [x] **Step 2: FireSearchView 标注**

```swift
// 搜索结果行
.accessibilityElement(children: .combine)
.accessibilityLabel("搜索结果: \(result.title)")
// 筛选器按钮
.accessibilityLabel("筛选: \(scope.title)")
```

- [x] **Step 3: FireNotificationsView 标注**

```swift
// 通知行
.accessibilityElement(children: .combine)
.accessibilityLabel("\(notification.description), \(timeAgo)")
// 标记已读按钮
.accessibilityLabel("标记为已读")
```

- [x] **Step 4: 其余视图批量标注**

对 `FireBookmarksView`, `FireDraftsView`, `FireOnboardingView`, `FireProfileView` 的交互元素添加 `.accessibilityLabel()`。

- [x] **Step 5: 构建验证**

Verified:
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

- [x] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md native/ios-app/App/Views/Composer/FireComposerView.swift native/ios-app/App/Views/Messages/FireRecipientTokenField.swift native/ios-app/App/Views/Search/FireSearchView.swift native/ios-app/App/Views/Notifications/FireNotificationsView.swift native/ios-app/App/Views/Notifications/FireNotificationHistoryView.swift native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift native/ios-app/App/Views/Other/FireDraftsView.swift native/ios-app/App/Views/Other/FireOnboardingView.swift native/ios-app/App/Views/Profile/FireProfileView.swift native/ios-app/App/Views/Profile/FireProfileActivityRow.swift native/ios-app/App/Views/Profile/FireProfileHeaderComponents.swift
git commit -m "a11y(ios): label composer search notifications and profile views"
```

---

## Task 6: iOS 暗黑模式修复

**Files:**
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift`
- Modify: `native/ios-app/App/Core/FireTheme.swift`
- Modify: `native/ios-app/App/Core/FireComponents.swift`

- [x] **Step 1: 修复 Composer 中的硬编码黑色**

搜索 `Color.black.opacity(` 并替换：

```swift
// 替换前:
Color.black.opacity(0.06)

// 替换后:
FireTheme.divider
```

```swift
// 替换前（描边）:
.stroke(Color.black.opacity(0.08), lineWidth: 1)

// 替换后:
.stroke(FireTheme.divider, lineWidth: 1)
```

- [x] **Step 2: 全项目扫描其他 Color.black/Color.white 硬编码**

Run: `rg "Color\.black\.opacity|Color\.white\.opacity" native/ios-app/App/Views/ native/ios-app/App/Core/`
逐一评估并替换为 FireTheme 语义色。

Result:
- Composer editor border now uses `FireTheme.divider`.
- `FireCard` shadows now use adaptive `FireTheme.panelShadow` / `FireTheme.contrastPanelShadow`.
- Remaining scan hits are profile avatar white rings in `FireProfileView` and `FirePublicProfileView`; these are intentional image-overlay highlights, not semantic dividers/backgrounds.

- [x] **Step 3: 暗黑模式验证**

Verified:
- `rg "Color\.black\.opacity|Color\.white\.opacity" native/ios-app/App/Views/ native/ios-app/App/Core/`
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

- [x] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md native/ios-app/App/Views/Composer/FireComposerView.swift native/ios-app/App/Core/FireTheme.swift native/ios-app/App/Core/FireComponents.swift
git commit -m "fix(ios): replace hardcoded composer colors with theme tokens"
```

---

## Task 7: iOS 通用分页 Store 提取

**Files:**
- Create: `native/ios-app/App/Stores/FirePaginatedStore.swift`
- Modify: `native/ios-app/App/Stores/FireSearchStore.swift`
- Modify: `native/ios-app/App/Stores/FireNotificationStore.swift`
- Modify: `native/ios-app/Fire.xcodeproj/project.pbxproj`
- Modify: `native/ios-app/README.md`

- [x] **Step 1: 创建 FirePaginatedStore 基类**

`FirePaginatedStore<Item>` now owns shared paginated list state:
- `items`, `isLoading`, `isLoadingMore`, `hasLoadedOnce`
- blocking/non-blocking errors
- next cursor tracking
- cancellable fire-and-forget `load` / `loadMore`
- awaited `loadAsync` / `loadMoreAsync`
- overridable `fetchPage`, `mergeItems`, and recoverable-error hook

- [x] **Step 2: 迁移 FireSearchStore**

`FireSearchStore` now inherits `FirePaginatedStore<SearchResultState>` while preserving its existing public API (`result`, `currentPage`, `isSearching`, `isAppending`, `errorMessage`, `submit(reset:)`). Search keeps the aggregate `SearchResultState` model and uses page numbers as the base cursor instead of introducing a fake item wrapper.

- [x] **Step 3: 迁移 FireNotificationStore 全量通知分页**

`FireNotificationStore` now delegates full-history pagination to a private `FirePaginatedStore<NotificationItemState>` subclass and bridges `objectWillChange` back to the outer store. Recent notifications, unread count, read mutations, and MessageBus refresh remain explicit in `FireNotificationStore`.

- [x] **Step 4: 构建验证**

Verified:
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

- [x] **Step 5: 运行搜索相关测试**

Verified:
- `cd native/ios-app && xcodebuild test -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -only-testing:FireTests/FireSearchStoreTests`

- [x] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md native/ios-app/README.md native/ios-app/App/Stores/FirePaginatedStore.swift native/ios-app/App/Stores/FireSearchStore.swift native/ios-app/App/Stores/FireNotificationStore.swift native/ios-app/Fire.xcodeproj/project.pbxproj
git commit -m "refactor(ios): extract generic FirePaginatedStore base class"
```

---

## Task 8: iOS 空状态组件复用 + Shimmer 动画

**Files:**
- Modify: `native/ios-app/App/Core/FireComponents.swift`
- Create: `native/ios-app/App/Core/FireShimmerModifier.swift`
- Modify: `native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift`
- Modify: `native/ios-app/App/Views/Home/FireFilteredTopicListView.swift`
- Modify: `native/ios-app/App/Views/Notifications/FireNotificationsView.swift`
- Modify: `native/ios-app/App/Views/Notifications/FireNotificationHistoryView.swift`
- Modify: `native/ios-app/Fire.xcodeproj/project.pbxproj`

- [x] **Step 1: 创建 Shimmer 修饰器**

`FireShimmerModifier` now provides `View.fireShimmer()` with FireTheme colors, geometry-relative animation, hit-testing disabled, clipping, and reduce-motion support.

- [x] **Step 2: 确认 FireEmptyFeedState 已存在**

`FireEmptyFeedState` now supports reusable icon, optional title, message, and optional action button parameters while preserving the existing message/action initializer shape.

- [x] **Step 3: 在视图列表中应用 Shimmer 和空状态**

Applied `.fireShimmer()` to the existing SwiftUI skeletons:
- `FireTopicSkeletonList`
- `FireHomeCollectionView.loadingRow`
- `FireFilteredTopicListView.loadingSection`
- `FireNotificationsView.loadingSkeleton`

Reused `FireEmptyFeedState` in:
- `FireFilteredTopicListView.emptySection`
- `FireNotificationsView.emptyState`
- `FireNotificationHistoryView.emptyState`

Checked search, bookmarks, drafts, private messages, and read history; they did not have `.redacted(reason: .placeholder)` skeletons to replace.

- [x] **Step 4: 构建验证**

Verified:
- `rg -n "redacted\\(reason: \\.placeholder\\)|fireShimmer\\(|FireEmptyFeedState\\(" native/ios-app/App -g '*.swift'`
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

- [x] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md native/ios-app/App/Core/FireShimmerModifier.swift native/ios-app/App/Core/FireComponents.swift native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift native/ios-app/App/Views/Home/FireFilteredTopicListView.swift native/ios-app/App/Views/Notifications/FireNotificationsView.swift native/ios-app/App/Views/Notifications/FireNotificationHistoryView.swift native/ios-app/Fire.xcodeproj/project.pbxproj
git commit -m "feat(ios): add shimmer animation and reuse empty states"
```

---

## Task 9: iOS 上下文菜单

**Files:**
- Create: `native/ios-app/App/Core/FireContextMenus.swift`
- Modify: `native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift`
- Modify: `native/ios-app/App/Views/Home/FireHomeView.swift`
- Modify: `native/ios-app/App/Views/Home/FireFilteredTopicListView.swift`
- Modify: `native/ios-app/App/Views/Search/FireSearchView.swift`
- Modify: `native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift`
- Modify: `native/ios-app/App/Views/Other/FireReadHistoryView.swift`
- Modify: `native/ios-app/App/Views/FireNotificationsView.swift`
- Modify: `native/ios-app/App/Views/Notifications/FireNotificationHistoryView.swift`
- Modify: `native/ios-app/Fire.xcodeproj/project.pbxproj`

- [x] **Step 1: 创建上下文菜单构建器**

`FireContextMenus.swift` now provides:
- `FireTopicContextMenu` for open, bookmark editor, share, copy link, and mute actions.
- `FireNotificationContextMenu` for open, mark-read, copy content, share link, and copy link actions.
- small URL/context helpers for topic share URLs, notification share URLs, and bookmark editor contexts.

- [x] **Step 2: 话题行添加上下文菜单**

`FireTopicRow` remains presentation-only. Owning views attach menus with local closures so routing, bookmark sheets, mutation services, and refresh behavior stay with the surface that owns them:
- Home collection rows
- Filtered category/tag topic lists
- Search topic results
- Bookmarks
- Read history

Bookmark actions reuse `FireBookmarkEditorSheet`; muting uses `FireTopicInteractionService.setTopicNotificationLevel(.muted)`. There is no topic-list mark-read API, so no synthetic fallback action was added.

- [x] **Step 3: 通知行添加上下文菜单**

Recent and full notification history now share `FireNotificationRow`, which wraps `FireNotificationRowContent` with tap handling, accessibility labels, and context-menu actions. Mark-read uses `FireNotificationStore.markRead(id:)`; open uses the existing route presentation path.

- [x] **Step 4: 构建验证**

Verified:
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF' -quiet`

- [x] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md native/ios-app/App/Core/FireContextMenus.swift native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift native/ios-app/App/Views/Home/FireHomeView.swift native/ios-app/App/Views/Home/FireFilteredTopicListView.swift native/ios-app/App/Views/Search/FireSearchView.swift native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift native/ios-app/App/Views/Other/FireReadHistoryView.swift native/ios-app/App/Views/Notifications/FireNotificationsView.swift native/ios-app/App/Views/Notifications/FireNotificationHistoryView.swift native/ios-app/Fire.xcodeproj/project.pbxproj
git commit -m "feat(ios): add context menus to topic rows and notifications"
```

---

## Task 10: iOS FireAppViewModel 拆分 — 话题交互服务

**Files:**
- Create: `native/ios-app/App/Services/FireTopicInteractionService.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`

- [x] **Step 1: 创建 FireTopicInteractionService**

从 `FireAppViewModel` 中提取以下方法到 `FireTopicInteractionService`：

```swift
import Foundation

@MainActor
final class FireTopicInteractionService {
    private let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    // 从 FireAppViewModel 搬入:
    // - toggleLike(postId:)
    // - toggleReaction(postId:reaction:)
    // - createBookmark(postId:name:reminderAt:)
    // - deleteBookmark(bookmarkId:)
    // - toggleTopicVote(topicId:)
    // - votePoll(pollName:optionId:postId:)
    // - unvotePoll(pollName:optionId:postId:)
    // - flagPost(postId:reasonId:)
    // - reportPostTimings(topicId:timings:)
}
```

- [x] **Step 2: FireAppViewModel 持有 service 实例**

在 `FireAppViewModel` 中添加：

```swift
let topicInteraction: FireTopicInteractionService
```

在 `init` 中初始化。所有调用 `toggleLike` 等方法的视图改为通过 `appViewModel.topicInteraction.toggleLike(...)`。

- [x] **Step 3: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: 运行相关测试**

Run: `cd native/ios-app && xcodebuild test -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E '(Test Suite|Executed|FAILED)'`
Expected: All tests pass, 0 failures

- [x] **Step 5: Commit**

```bash
git add native/ios-app/App/Services/FireTopicInteractionService.swift native/ios-app/App/ViewModels/FireAppViewModel.swift
git commit -m "refactor(ios): extract FireTopicInteractionService from FireAppViewModel"
```

---

## Task 11: iOS FireAppViewModel 拆分 — 通知服务

**Files:**
- Create: `native/ios-app/App/Services/FireNotificationService.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`

- [x] **Step 1: 创建 FireNotificationService**

从 `FireAppViewModel` 中提取：

```swift
@MainActor
final class FireNotificationService {
    private let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    // 从 FireAppViewModel 搬入:
    // - fetchRecentNotifications()
    // - fetchFullNotifications(offset:)
    // - markNotificationRead(notificationId:)
    // - markAllNotificationsRead()
}
```

- [x] **Step 2: FireAppViewModel 持有 service 实例**

```swift
let notificationService: FireNotificationService
```

- [x] **Step 3: 构建并测试**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: Commit**

```bash
git add native/ios-app/App/Services/FireNotificationService.swift native/ios-app/App/ViewModels/FireAppViewModel.swift
git commit -m "refactor(ios): extract FireNotificationService from FireAppViewModel"
```

---

## Task 12: iOS FireAppViewModel 拆分 — 搜索服务

**Files:**
- Create: `native/ios-app/App/Services/FireSearchService.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`

- [x] **Step 1: 创建 FireSearchService**

```swift
@MainActor
final class FireSearchService {
    private let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    // 从 FireAppViewModel 搬入:
    // - search(query:scope:page:)
    // - searchTags(query:)
    // - searchUsers(query:)
}
```

- [x] **Step 2: FireAppViewModel 持有 service 实例**

```swift
let searchService: FireSearchService
```

- [x] **Step 3: 构建并测试**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: Commit**

```bash
git add native/ios-app/App/Services/FireSearchService.swift native/ios-app/App/ViewModels/FireAppViewModel.swift
git commit -m "refactor(ios): extract FireSearchService from FireAppViewModel"
```

---

### Follow-up: iOS FireAppViewModel 拆分 — 门面扩展收敛

**Files:**
- Create: `native/ios-app/App/ViewModels/FireAppViewModelSupport.swift`
- Create: `native/ios-app/App/ViewModels/FireAppViewModel+Diagnostics.swift`
- Create: `native/ios-app/App/ViewModels/FireAppViewModel+Profile.swift`
- Create: `native/ios-app/App/ViewModels/FireAppViewModel+RecoveryURLs.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`
- Modify: `native/ios-app/Fire.xcodeproj/project.pbxproj`

- [x] **Step 1: Move support types out of the main view model file**

`FireAppViewModelSupport.swift` now owns login/diagnostics error types, auth presentation state, Cloudflare cookie snapshot diagnostics, app-state/state-observer coordinators, topic-detail request/window structs, and search scope helpers.

- [x] **Step 2: Move diagnostics facade methods**

`FireAppViewModel+Diagnostics.swift` owns log listing/reading, network trace access, diagnostic session ID, support bundle export, APM summary/export, log flushing, and diagnostics scene-phase handling.

- [x] **Step 3: Move profile and LDC/CDK facade methods**

`FireAppViewModel+Profile.swift` owns user profile/summary/actions/bookmarks/follows/invites/badges and LDC/CDK authorization, approval, callback, user-info, and logout pass-through methods.

- [x] **Step 4: Move Cloudflare recovery URL builders**

`FireAppViewModel+RecoveryURLs.swift` owns site-root, topic-list, topic-detail, filter, tag, and query-item URL normalization helpers used by the platform WebView recovery path.

- [x] **Step 5: Build and line-count verification**

Verified:
- `wc -l native/ios-app/App/ViewModels/FireAppViewModel.swift` -> `1431`
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,id=D733CCB1-7B2A-49B5-B3F8-36CB6D0CB2BF,OS=18.3' -derivedDataPath /tmp/fire-ios-vm-split-build CODE_SIGNING_ALLOWED=NO -quiet` passed

The split is behavior-preserving: stateful login/session/message-bus orchestration remains in `FireAppViewModel.swift`; native topic-detail rows remain on the UIKit/Texture runtime cell path.

---

## Task 13: Android — 草稿列表页

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`
- Create: `native/android-app/src/main/java/com/fire/app/data/paging/DraftsPagingSource.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsFragment.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsViewModel.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsAdapter.kt`
- Create: `native/android-app/src/main/res/layout/fragment_drafts.xml`
- Create: `native/android-app/src/main/res/layout/item_draft.xml`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt`
- Modify: `native/android-app/src/main/res/layout/fragment_profile.xml`
- Modify: `native/android-app/src/main/res/values/strings.xml`

- [x] **Step 1: Expose draft listing in Android session store**

`FireSessionStore.fetchDrafts(offset, limit)` now wraps `core.notifications().fetchDrafts(...)` on `Dispatchers.IO`, matching the existing `fetchDraft`, `saveDraft`, and `deleteDraft` UniFFI boundary.

- [x] **Step 2: Add Paging-backed draft data flow**

`DraftsPagingSource` requests drafts by offset and limit, returns `DraftState` rows directly from UniFFI, and advances `nextKey` only when `DraftListResponseState.hasMore` is true. `DraftsViewModel` owns the `Pager`, caches it in `viewModelScope`, and reports delete errors through `FireErrorReporter`.

- [x] **Step 3: Add drafts list UI**

`DraftsFragment` follows the existing Android list-page shape: `SwipeRefreshLayout`, `RecyclerView`, initial loading indicator, empty/error text, and lifecycle-aware Paging collection. `DraftsAdapter` renders title, excerpt, type/date/user metadata, and a delete button for each draft.

- [x] **Step 4: Resume and delete behavior**

Draft taps use the authoritative composer paths:
- `new_topic` opens `TopicComposerSheet`, which restores the fixed `new_topic` draft key.
- `new_private_message` opens `PrivateMessageComposerSheet`, which restores the fixed `new_private_message` draft key.
- Reply drafts open `ReplyComposerSheet` with the parsed `topic_<id>` or `topic_<id>_post_<post>` target, preferring explicit `replyToPostNumber` payload data when present.
- Unknown draft keys show `feed_drafts_resume_unavailable` instead of adding a fallback editor path.

Delete confirms with an `AlertDialog`, calls `sessionStore.deleteDraft(draft.draftKey, draft.sequence)`, then refreshes the Paging adapter.

- [x] **Step 5: Add profile navigation entry**

`fire_nav_graph.xml` now includes `draftsFragment` and `ProfileFragment` navigates through generated Safe Args. The profile action row was updated to three equal actions: Bookmarks, Drafts, and Private Messages.

- [x] **Step 6: Build verification**

Run: `cd native/android-app && ./gradlew assembleDebug`

Result: `BUILD SUCCESSFUL`

- [x] **Step 7: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md \
  native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt \
  native/android-app/src/main/java/com/fire/app/data/paging/DraftsPagingSource.kt \
  native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsViewModel.kt \
  native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsAdapter.kt \
  native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsFragment.kt \
  native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt \
  native/android-app/src/main/res/layout/fragment_drafts.xml \
  native/android-app/src/main/res/layout/item_draft.xml \
  native/android-app/src/main/res/layout/fragment_profile.xml \
  native/android-app/src/main/res/navigation/fire_nav_graph.xml \
  native/android-app/src/main/res/values/strings.xml
git commit -m "feat(android): add drafts list screen"
```

---

## Task 14: Android — 推送通知（FCM）

**Files:**
- Modify: `native/android-app/build.gradle.kts`
- Create: `native/android-app/src/main/java/com/fire/app/push/FireFirebaseMessagingService.kt`
- Create: `native/android-app/src/main/java/com/fire/app/push/FirePushNotification.kt`
- Create: `native/android-app/src/main/java/com/fire/app/push/FirePushNotificationDispatcher.kt`
- Modify: `native/android-app/src/main/AndroidManifest.xml`
- Local/CI config: `native/android-app/google-services.json` (ignored production project config)

- [x] **Step 1: 添加 Firebase 依赖**

`build.gradle.kts` now declares the Google Services plugin and Firebase
Messaging dependencies:

```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false

implementation(platform("com.google.firebase:firebase-bom:33.15.0"))
implementation("com.google.firebase:firebase-messaging-ktx")
```

The Google Services plugin is applied only when a real
`native/android-app/google-services.json` exists, so source builds remain
repeatable without checking private Firebase project configuration into git.
`native/android-app/.gitignore` excludes that file.

- [x] **Step 2: 创建 FCM Service**

`FireFirebaseMessagingService` receives token refreshes and FCM messages. Token
refreshes are logged to Rust diagnostics, but not registered directly from
Android because there is no shared Rust/core token-registration API yet. Message
handling parses common Discourse/LinuxDo payload fields through
`FirePushPayloadParser`, displays a local notification through
`FirePushNotificationDispatcher`, and refreshes Rust notification state
opportunistically without making notification display depend on network success.

- [x] **Step 3: 注册 Service 和通知 Channel**

`AndroidManifest.xml` registers the non-exported Firebase messaging service:

```xml
<service
    android:name=".push.FireFirebaseMessagingService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

`FireApplication.onCreate()` creates the `fire_notifications` channel through
`FirePushNotificationDispatcher`, separate from the existing bookmark reminder
channel.

- [x] **Step 4: 构建验证**

Run:
- `cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.push.FirePushPayloadParserTest`
- `cd native/android-app && ./gradlew assembleDebug`

Result: passed.

- [x] **Step 5: Commit**

Included in this commit.

```bash
git add native/android-app/.gitignore native/android-app/build.gradle.kts native/android-app/src/main/java/com/fire/app/push/ native/android-app/src/test/java/com/fire/app/push/ native/android-app/src/main/AndroidManifest.xml native/android-app/src/main/java/com/fire/app/FireApplication.kt native/android-app/src/main/res/values/strings.xml native/android-app/README.md docs/superpowers/plans/2026-06-08-p1-foundation.md
git commit -m "feat(android): add Firebase Cloud Messaging push notification support"
```

---

## Task 15: Android — 阅读历史页

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/data/paging/ReadHistoryPagingSource.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/readhistory/ReadHistoryFragment.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/readhistory/ReadHistoryViewModel.kt`
- Create: `native/android-app/src/main/res/layout/fragment_read_history.xml`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt`
- Modify: `native/android-app/src/main/res/layout/fragment_profile.xml`
- Modify: `native/android-app/src/main/res/values/strings.xml`

- [x] **Step 1: Add Paging-backed read history data flow**

`ReadHistoryPagingSource` calls `FireSessionStore.fetchReadHistory(page)` and returns `TopicRowState` rows directly from `TopicListState`, using `nextPage` as the authoritative continuation. `ReadHistoryViewModel` owns the `Pager` and caches it in `viewModelScope`.

- [x] **Step 2: Add read history screen**

`ReadHistoryFragment` reuses `TopicListAdapter`, `TopicDetailActivity`, `SwipeRefreshLayout`, and the existing loading/empty/error list-state pattern. Topic taps open the topic detail at `lastReadPostNumber` when available.

- [x] **Step 3: Add profile navigation entry**

`fire_nav_graph.xml` now includes `readHistoryFragment` and the generated `actionProfileToReadHistory()` Safe Args action. The own-profile action row now exposes Bookmarks, Drafts, Messages, and History.

- [x] **Step 4: Build verification**

Run: `cd native/android-app && ./gradlew assembleDebug`

Result: `BUILD SUCCESSFUL`

- [x] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md \
  native/android-app/src/main/java/com/fire/app/data/paging/ReadHistoryPagingSource.kt \
  native/android-app/src/main/java/com/fire/app/ui/readhistory/ReadHistoryViewModel.kt \
  native/android-app/src/main/java/com/fire/app/ui/readhistory/ReadHistoryFragment.kt \
  native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt \
  native/android-app/src/main/res/layout/fragment_read_history.xml \
  native/android-app/src/main/res/layout/fragment_profile.xml \
  native/android-app/src/main/res/navigation/fire_nav_graph.xml \
  native/android-app/src/main/res/values/strings.xml
git commit -m "feat(android): add read history screen with pagination"
```

---

## Task 16: Android — 通知历史全屏页

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationListAdapter.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationHistoryAdapter.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationHistoryFragment.kt`
- Create: `native/android-app/src/main/res/layout/fragment_notification_history.xml`
- Create: `native/android-app/src/main/res/layout/item_notification_history_header.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationsFragment.kt`
- Modify: `native/android-app/src/main/res/layout/fragment_notifications.xml`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`
- Modify: `native/android-app/src/main/res/values/strings.xml`

- [x] **Step 1: Create grouped notification history screen**

`NotificationHistoryFragment` reuses `NotificationsViewModel` and the existing `NotificationPagingSource` through `notificationPagingFlow()`. It maps notification rows into a history row model and uses Paging `insertSeparators` for Today / Yesterday / Earlier section headers.

- [x] **Step 2: Reuse notification row rendering**

`NotificationListAdapter` now exposes a reusable `NotificationViewHolder`, and `NotificationHistoryAdapter` wraps it for notification rows while rendering section headers from `item_notification_history_header.xml`.

- [x] **Step 3: Add layout and navigation**

`fragment_notification_history.xml` provides a full-screen `SwipeRefreshLayout` + `RecyclerView` list with loading and empty/error states. `NotificationsFragment` now has a `View All` text button that navigates to `notificationHistoryFragment`; the history screen can still navigate profile-targeted notifications to `profileFragment`.

- [x] **Step 4: Build verification**

Run: `cd native/android-app && ./gradlew assembleDebug`

Result: `BUILD SUCCESSFUL`

- [x] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p1-foundation.md \
  native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationListAdapter.kt \
  native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationHistoryAdapter.kt \
  native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationHistoryFragment.kt \
  native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationsFragment.kt \
  native/android-app/src/main/res/layout/fragment_notifications.xml \
  native/android-app/src/main/res/layout/fragment_notification_history.xml \
  native/android-app/src/main/res/layout/item_notification_history_header.xml \
  native/android-app/src/main/res/navigation/fire_nav_graph.xml \
  native/android-app/src/main/res/values/strings.xml
git commit -m "feat(android): add full-page notification history with grouped sections"
```

---

## Task 17: Android — 话题阅读计时

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicTimingTracker.kt`
- Create: `native/android-app/src/test/java/com/fire/app/ui/topicdetail/TopicTimingTrackerTest.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/FireApplication.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`

- [x] **Step 1: 创建 TopicTimingTracker**

Implemented `TopicTimingTracker` with one-second ticks, 60-second flushes, idle pause handling, per-post timing caps, rejected-report backoff, scene active/inactive control, and deterministic clock/dispatcher injection for JVM tests.

- [x] **Step 2: 集成到 TopicDetailActivity / FireSessionStore**

`TopicDetailActivity` now owns native visible-row collection from the `RecyclerView` lifecycle and reports through `FireSessionStore.reportTopicTimings(...)` into the Rust UniFFI `/topics/timings` API. `TopicDetailViewModel` is now provider-backed so its existing `onCleared()` cleanup reliably releases topic MessageBus subscriptions.

- [x] **Step 3: 构建验证**

Verified:
- `cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.ui.topicdetail.TopicTimingTrackerTest`
- `cd native/android-app && ./gradlew assembleDebug`

- [x] **Step 4: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/FireApplication.kt native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicTimingTracker.kt native/android-app/src/test/java/com/fire/app/ui/topicdetail/TopicTimingTrackerTest.kt docs/superpowers/plans/2026-06-08-p1-foundation.md
git commit -m "feat(android): add topic timing tracker for read time reporting"
```
