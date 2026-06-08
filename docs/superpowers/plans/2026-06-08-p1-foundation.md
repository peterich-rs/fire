# P1 基础夯实 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除视觉不一致、补齐 Accessibility、统一架构模式、Android 核心页面补全

**Architecture:** iOS 侧聚焦 FireTheme Token 统一、通用分页 Store 提取、FireAppViewModel 拆分；Android 侧补全草稿列表、推送通知、阅读历史等缺失页面。两端共享上下文菜单、空状态组件、Shimmer 动画等模式。

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
| Modify | `App/ViewModels/FireAppViewModel.swift` | 拆分服务层 |
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

- [ ] **Step 1: 新增 corner radius Token 和 surface Token**

在 `FireTheme` extension constants 中替换现有 Token 并新增：

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

- [ ] **Step 2: 全局搜索并替换硬编码圆角值**

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

- [ ] **Step 3: 替换背景色硬编码**

| 搜索模式 | 替换为 |
|----------|--------|
| `Color(.systemGroupedBackground)` | `FireTheme.canvasMid` |
| `Color(.secondarySystemBackground)` | `FireTheme.surface` |
| `Color.black.opacity(0.06)` | `FireTheme.divider` |
| `Color.black.opacity(0.` 任何描边 | `FireTheme.divider` |

- [ ] **Step 4: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Core/FireTheme.swift native/ios-app/App/Core/FireComponents.swift native/ios-app/App/Views/
git commit -m "refactor(ios): unify corner radius and background tokens across FireTheme"
```

---

## Task 2: iOS Feed Kind Selector 统一

**Files:**
- Modify: `native/ios-app/App/Views/FireFilteredTopicListView.swift`
- Reference: `native/ios-app/App/Core/FireComponents.swift` (contains `FireFeedKindSelector`)

- [ ] **Step 1: 定位 FireFilteredTopicListView 中的简易筛选器**

读取 `FireFilteredTopicListView.swift`，找到使用 `Capsule().fill()` 的筛选器代码段。

- [ ] **Step 2: 替换为 FireFeedKindSelector**

将内联的 Capsule 筛选器替换为 `FireFeedKindSelector`（使用 `matchedGeometryEffect` 的版本），确保与首页视觉完全一致。

需要传递的参数：
- `kinds: [TopicListKindState]`
- `selectedKind: Binding<TopicListKindState>`
- `onSelect: (TopicListKindState) -> Void`

- [ ] **Step 3: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

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

- [ ] **Step 1: FireTopicRow Accessibility**

为 `FireTopicRow` 添加 accessibility 标注：

```swift
.accessibilityElement(children: .combine)
.accessibilityLabel("\(topic.title), \(topic.categoryName ?? ""), \(topic.replyCount) 回复, \(topic.views) 浏览")
.accessibilityHint("双击查看话题详情")
```

- [ ] **Step 2: FireHomeView 按钮标注**

为图标按钮添加 `accessibilityLabel`：

```swift
// 搜索按钮
.accessibilityLabel("搜索")

// 创建话题按钮
.accessibilityLabel("创建新话题")
```

- [ ] **Step 3: Skeleton 视图隐藏**

所有骨架屏视图添加 `.accessibilityHidden(true)`。

- [ ] **Step 4: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Views/FireTopicRow.swift native/ios-app/App/Views/FireHomeView.swift
git commit -m "a11y(ios): add accessibility labels to topic rows and home buttons"
```

---

## Task 5: iOS Accessibility 标注 — 编辑器、搜索、通知、其他

**Files:**
- Modify: `native/ios-app/App/Views/FireComposerView.swift`
- Modify: `native/ios-app/App/Views/FireSearchView.swift`
- Modify: `native/ios-app/App/Views/FireNotificationsView.swift`
- Modify: `native/ios-app/App/Views/FireBookmarksView.swift`
- Modify: `native/ios-app/App/Views/FireDraftsView.swift`
- Modify: `native/ios-app/App/Views/FireOnboardingView.swift`
- Modify: `native/ios-app/App/Views/FireProfileView.swift`

- [ ] **Step 1: FireComposerView 工具栏按钮标注**

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

- [ ] **Step 2: FireSearchView 标注**

```swift
// 搜索结果行
.accessibilityElement(children: .combine)
.accessibilityLabel("搜索结果: \(result.title)")
// 筛选器按钮
.accessibilityLabel("筛选: \(scope.title)")
```

- [ ] **Step 3: FireNotificationsView 标注**

```swift
// 通知行
.accessibilityElement(children: .combine)
.accessibilityLabel("\(notification.description), \(timeAgo)")
// 标记已读按钮
.accessibilityLabel("标记为已读")
```

- [ ] **Step 4: 其余视图批量标注**

对 `FireBookmarksView`, `FireDraftsView`, `FireOnboardingView`, `FireProfileView` 的交互元素添加 `.accessibilityLabel()`。

- [ ] **Step 5: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add native/ios-app/App/Views/
git commit -m "a11y(ios): add accessibility labels to composer, search, notifications, and remaining views"
```

---

## Task 6: iOS 暗黑模式修复

**Files:**
- Modify: `native/ios-app/App/Views/FireComposerView.swift`

- [ ] **Step 1: 修复 Composer 中的硬编码黑色**

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

- [ ] **Step 2: 全项目扫描其他 Color.black/Color.white 硬编码**

Run: `rg "Color\.black\.opacity|Color\.white\.opacity" native/ios-app/App/Views/ native/ios-app/App/Core/`
逐一评估并替换为 FireTheme 语义色。

- [ ] **Step 3: 暗黑模式视觉验证**

在 iOS Simulator 中切换到暗黑模式，检查 Composer 页面边框和分割线可见性。

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/Views/FireComposerView.swift
git commit -m "fix(ios): replace hardcoded Color.black.opacity with FireTheme tokens for dark mode"
```

---

## Task 7: iOS 通用分页 Store 提取

**Files:**
- Create: `native/ios-app/App/Stores/FirePaginatedStore.swift`
- Modify: `native/ios-app/App/Stores/FireSearchStore.swift`
- Modify: `native/ios-app/App/Stores/FireNotificationStore.swift`

- [ ] **Step 1: 创建 FirePaginatedStore 协议**

```swift
import Foundation

@MainActor
class FirePaginatedStore<Item>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasLoadedOnce: Bool = false
    @Published private(set) var blockingError: String?
    @Published private(set) var nonBlockingError: String?

    private var nextOffset: UInt32?
    private var loadTask: Task<Void, Never>?

    var hasMore: Bool { nextOffset != nil }

    func load(forceRefresh: Bool = false) {
        guard forceRefresh || !hasLoadedOnce else { return }
        loadTask?.cancel()
        loadTask = Task {
            guard !isLoading else { return }
            isLoading = true
            blockingError = nil
            do {
                let result = try await fetchPage(offset: nil)
                items = result.items
                nextOffset = result.nextOffset
                hasLoadedOnce = true
            } catch {
                blockingError = error.localizedDescription
            }
            isLoading = false
        }
    }

    func loadMore() {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let offset = nextOffset
        loadTask = Task {
            isLoadingMore = true
            nonBlockingError = nil
            do {
                let result = try await fetchPage(offset: offset)
                items.append(contentsOf: result.items)
                nextOffset = result.nextOffset
            } catch {
                nonBlockingError = error.localizedDescription
            }
            isLoadingMore = false
        }
    }

    func reset() {
        loadTask?.cancel()
        items = []
        nextOffset = nil
        hasLoadedOnce = false
        blockingError = nil
        nonBlockingError = nil
        isLoading = false
        isLoadingMore = false
    }

    func clearErrors() {
        blockingError = nil
        nonBlockingError = nil
    }

    func recordFailure(_ message: String, isBlocking: Bool = true) {
        if isBlocking {
            blockingError = message
        } else {
            nonBlockingError = message
        }
    }

    struct PageResult {
        let items: [Item]
        let nextOffset: UInt32?
    }

    func fetchPage(offset: UInt32?) async throws -> PageResult {
        fatalError("Subclass must override fetchPage(offset:)")
    }
}
```

- [ ] **Step 2: FireSearchStore 继承 FirePaginatedStore**

重构 `FireSearchStore` 继承 `FirePaginatedStore<SearchResultItem>`，删除重复的 `isLoading`, `isAppending`, `errorMessage` 属性，override `fetchPage(offset:)`。

- [ ] **Step 3: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 运行搜索相关测试**

Run: `cd native/ios-app && xcodebuild test -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FireAppTests/FireSearchStoreTests 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Stores/FirePaginatedStore.swift native/ios-app/App/Stores/FireSearchStore.swift
git commit -m "refactor(ios): extract generic FirePaginatedStore base class"
```

---

## Task 8: iOS 空状态组件复用 + Shimmer 动画

**Files:**
- Modify: `native/ios-app/App/Core/FireComponents.swift`
- Create: `native/ios-app/App/Core/FireShimmerModifier.swift`

- [ ] **Step 1: 创建 Shimmer 修饰器**

```swift
import SwiftUI

struct FireShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    let duration: Double = 1.5

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        FireTheme.softSurface.opacity(0),
                        FireTheme.softSurface.opacity(0.4),
                        FireTheme.softSurface.opacity(0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 400)
            )
            .clipped()
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func fireShimmer() -> some View {
        modifier(FireShimmerModifier())
    }
}
```

- [ ] **Step 2: 确认 FireEmptyFeedState 已存在**

读取 `FireComponents.swift` 中的 `FireEmptyFeedState`。确保它支持 3 种状态：
- 空数据（图标 + "暂无内容"）
- 加载失败（图标 + 错误信息 + 重试按钮）
- 无搜索结果（图标 + "未找到相关内容"）

如果不完整，补充缺失的状态。

- [ ] **Step 3: 在视图列表中应用 Shimmer 和空状态**

逐个检查以下视图，替换 `.redacted(reason: .placeholder)` 为 `.fireShimmer()`，并确保使用 `FireEmptyFeedState`：

- `FireHomeView` (home skeleton)
- `FireNotificationsView` (notification skeleton)
- `FireSearchView` (search result skeleton)
- `FireBookmarksView` (bookmark skeleton)
- `FireDraftsView` (draft skeleton)
- `FirePrivateMessagesView` (PM skeleton)
- `FireReadHistoryView` (history skeleton)

- [ ] **Step 4: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Core/FireShimmerModifier.swift native/ios-app/App/Core/FireComponents.swift native/ios-app/App/Views/
git commit -m "feat(ios): add shimmer animation and unify empty state component usage"
```

---

## Task 9: iOS 上下文菜单

**Files:**
- Create: `native/ios-app/App/Core/FireContextMenus.swift`
- Modify: `native/ios-app/App/Views/FireTopicRow.swift`
- Modify: `native/ios-app/App/Views/FireNotificationsView.swift`

- [ ] **Step 1: 创建上下文菜单构建器**

```swift
import SwiftUI

struct FireTopicContextMenu: View {
    let isBookmarked: Bool
    let onBookmark: () -> Void
    let onShare: () -> Void
    let onMute: () -> Void

    var body: some View {
        Button {
            onBookmark()
        } label: {
            Label(isBookmarked ? "取消收藏" : "收藏", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
        }
        Button {
            onShare()
        } label: {
            Label("分享", systemImage: "square.and.arrow.up")
        }
        Button {
            onMute()
        } label: {
            Label("静音", systemImage: "bell.slash")
        }
    }
}
```

- [ ] **Step 2: 话题行添加上下文菜单**

在 `FireTopicRow` 上添加 `.contextMenu`：

```swift
.contextMenu {
    FireTopicContextMenu(
        isBookmarked: topic.isBookmarked,
        onBookmark: { /* toggle bookmark */ },
        onShare: { /* share URL */ },
        onMute: { /* set notification level to muted */ }
    )
}
```

- [ ] **Step 3: 通知行添加上下文菜单**

```swift
.contextMenu {
    Button("标记为已读") { /* mark read */ }
    Button("跳转到话题") { /* navigate */ }
}
```

- [ ] **Step 4: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Core/FireContextMenus.swift native/ios-app/App/Views/FireTopicRow.swift native/ios-app/App/Views/FireNotificationsView.swift
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

## Task 13: Android — 草稿列表页

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsFragment.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsViewModel.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/drafts/DraftsAdapter.kt`
- Create: `native/android-app/src/main/res/layout/fragment_drafts.xml`
- Create: `native/android-app/src/main/res/layout/item_draft.xml`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt`

- [ ] **Step 1: 创建 DraftsViewModel**

```kotlin
package com.fire.app.ui.drafts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class DraftPresentation(
    val id: String,
    val title: String,
    val category: String?,
    val createdAt: String?,
    val excerpt: String?,
)

class DraftsViewModel(private val sessionStore: FireSessionStore) : ViewModel() {

    private val _drafts = MutableStateFlow<List<DraftPresentation>>(emptyList())
    val drafts = _drafts.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    private var currentOffset: UInt? = null
    private var hasMore = true

    fun loadDrafts(forceRefresh: Boolean = false) {
        if (!forceRefresh && _drafts.value.isNotEmpty()) return
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val result = sessionStore.fetchDrafts(offset = null, limit = 30)
                val presentations = result.drafts.map { draft ->
                    DraftPresentation(
                        id = draft.key,
                        title = draft.data?.title ?: "无标题草稿",
                        category = draft.data?.category,
                        createdAt = draft.data?.createdAt,
                        excerpt = draft.data?.reply?.take(100),
                    )
                }
                _drafts.value = presentations
                currentOffset = if (result.drafts.size >= 30) UInt(result.drafts.size) else null
                hasMore = currentOffset != null
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage ?: "加载草稿失败"
            }
            _isLoading.value = false
        }
    }

    fun loadMore() {
        if (!hasMore || _isLoading.value) return
        val offset = currentOffset ?: return
        viewModelScope.launch {
            try {
                val result = sessionStore.fetchDrafts(offset = offset, limit = 30)
                val presentations = result.drafts.map { draft ->
                    DraftPresentation(
                        id = draft.key,
                        title = draft.data?.title ?: "无标题草稿",
                        category = draft.data?.category,
                        createdAt = draft.data?.createdAt,
                        excerpt = draft.data?.reply?.take(100),
                    )
                }
                _drafts.value = _drafts.value + presentations
                currentOffset = if (result.drafts.size >= 30) UInt(_drafts.value.size) else null
                hasMore = currentOffset != null
            } catch (_: Exception) { }
        }
    }

    fun deleteDraft(draftKey: String) {
        viewModelScope.launch {
            try {
                sessionStore.deleteDraft(draftKey)
                _drafts.value = _drafts.value.filter { it.id != draftKey }
            } catch (_: Exception) { }
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): DraftsViewModel {
            return DraftsViewModel(sessionStore)
        }
    }
}
```

- [ ] **Step 2: 创建 DraftsAdapter**

```kotlin
package com.fire.app.ui.drafts

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.fire.app.R

class DraftsAdapter(
    private val onDraftClick: (DraftPresentation) -> Unit,
    private val onDraftDelete: (DraftPresentation) -> Unit,
) : RecyclerView.Adapter<DraftsAdapter.ViewHolder>() {

    private val items = mutableListOf<DraftPresentation>()

    fun submitList(newItems: List<DraftPresentation>) {
        items.clear()
        items.addAll(newItems)
        notifyDataSetChanged()
    }

    override fun getItemCount() = items.size

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_draft, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(items[position])
    }

    inner class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val titleView: TextView = view.findViewById(R.id.draft_title)
        private val excerptView: TextView = view.findViewById(R.id.draft_excerpt)
        private val metaView: TextView = view.findViewById(R.id.draft_meta)

        fun bind(draft: DraftPresentation) {
            titleView.text = draft.title
            excerptView.text = draft.excerpt ?: ""
            metaView.text = listOfNotNull(draft.category, draft.createdAt)
                .joinToString(" · ")
            itemView.setOnClickListener { onDraftClick(draft) }
        }
    }
}
```

- [ ] **Step 3: 创建布局文件**

`fragment_drafts.xml`：SwipeRefreshLayout + RecyclerView + 空状态 TextView + 加载骨架屏。
`item_draft.xml`：标题、摘要、分类/日期元数据行。

- [ ] **Step 4: 创建 DraftsFragment**

```kotlin
package com.fire.app.ui.drafts

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.Lifecycle
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.LinearLayoutManager
import com.fire.app.R
import com.fire.app.session.FireSessionStore
import com.fire.app.session.FireSessionStoreRepository
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class DraftsFragment : Fragment() {

    private var viewModel: DraftsViewModel? = null
    private lateinit var adapter: DraftsAdapter

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View = inflater.inflate(R.layout.fragment_drafts, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val recyclerView = view.findViewById<androidx.recyclerview.widget.RecyclerView>(R.id.draft_list)
        val emptyView = view.findViewById<android.widget.TextView>(R.id.empty_view)

        lifecycleScope.launch {
            val sessionStore = FireSessionStoreRepository.get(requireContext())
            viewModel = DraftsViewModel.create(sessionStore)

            adapter = DraftsAdapter(
                onDraftClick = { draft -> /* navigate to resume draft */ },
                onDraftDelete = { draft -> viewModel?.deleteDraft(draft.id) },
            )
            recyclerView.layoutManager = LinearLayoutManager(requireContext())
            recyclerView.adapter = adapter

            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viewModel?.drafts?.collectLatest { drafts ->
                        adapter.submitList(drafts)
                        emptyView.visibility = if (drafts.isEmpty()) View.VISIBLE else View.GONE
                    }
                }
            }

            viewModel?.loadDrafts()
        }
    }
}
```

- [ ] **Step 5: 添加导航目标**

在 `fire_nav_graph.xml` 中添加：

```xml
<fragment
    android:id="@+id/draftsFragment"
    android:name="com.fire.app.ui.drafts.DraftsFragment"
    android:label="@string/feed_drafts" />
```

在 `ProfileFragment` 中添加导航入口（草稿按钮 → `R.id.draftsFragment`）。

- [ ] **Step 6: 构建验证**

Run: `cd native/android-app && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 7: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/drafts/ native/android-app/src/main/res/layout/fragment_drafts.xml native/android-app/src/main/res/layout/item_draft.xml native/android-app/src/main/res/navigation/fire_nav_graph.xml native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt
git commit -m "feat(android): add drafts list screen with paging and swipe-to-delete"
```

---

## Task 14: Android — 推送通知（FCM）

**Files:**
- Modify: `native/android-app/build.gradle.kts`
- Create: `native/android-app/src/main/java/com/fire/app/push/FireFirebaseMessagingService.kt`
- Modify: `native/android-app/src/main/AndroidManifest.xml`
- Create: `native/android-app/google-services.json` (project config)

- [ ] **Step 1: 添加 Firebase 依赖**

在 `build.gradle.kts` 的 `dependencies` 中添加：

```kotlin
implementation(platform("com.google.firebase:firebase-bom:33.15.0"))
implementation("com.google.firebase:firebase-messaging-ktx")
```

在项目级 `build.gradle.kts`（如果存在）添加：
```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

在 app 级 `plugins` 中添加：
```kotlin
id("com.google.gms.google-services")
```

- [ ] **Step 2: 创建 FCM Service**

```kotlin
package com.fire.app.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class FireFirebaseMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // 将 token 发送给 Rust core 或后端注册
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data = message.data
        // 根据通知类型显示本地通知
        // 或刷新 FireNotificationStore
    }
}
```

- [ ] **Step 3: 注册 Service 和通知 Channel**

在 `AndroidManifest.xml` 中添加：

```xml
<service
    android:name=".push.FireFirebaseMessagingService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

在 `FireApplication.onCreate()` 中创建通知 Channel：

```kotlin
import android.app.NotificationChannel
import android.app.NotificationManager

private fun createNotificationChannels() {
    val channel = NotificationChannel(
        "fire_notifications",
        "Fire 通知",
        NotificationManager.IMPORTANCE_HIGH,
    )
    val manager = getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(channel)
}
```

- [ ] **Step 4: 构建验证**

Run: `cd native/android-app && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 5: Commit**

```bash
git add native/android-app/build.gradle.kts native/android-app/src/main/java/com/fire/app/push/ native/android-app/src/main/AndroidManifest.xml native/android-app/src/main/java/com/fire/app/FireApplication.kt
git commit -m "feat(android): add Firebase Cloud Messaging push notification support"
```

---

## Task 15: Android — 阅读历史页

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/readhistory/ReadHistoryFragment.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/readhistory/ReadHistoryViewModel.kt`
- Create: `native/android-app/src/main/res/layout/fragment_read_history.xml`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt`

- [ ] **Step 1: 创建 ReadHistoryViewModel**

```kotlin
package com.fire.app.ui.readhistory

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.fire_uniffi_types.TopicRowState

class ReadHistoryViewModel(private val sessionStore: FireSessionStore) : ViewModel() {

    private val _topics = MutableStateFlow<List<TopicRowState>>(emptyList())
    val topics = _topics.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    private var currentPage: UInt = 0u
    private var hasMore = true

    fun loadHistory(forceRefresh: Boolean = false) {
        if (!forceRefresh && _topics.value.isNotEmpty()) return
        currentPage = 0u
        hasMore = true
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val result = sessionStore.fetchReadHistory(page = 0u)
                _topics.value = result.topics
                hasMore = result.moreTopicsUrl != null
                currentPage = 1u
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage ?: "加载阅读历史失败"
            }
            _isLoading.value = false
        }
    }

    fun loadMore() {
        if (!hasMore || _isLoading.value) return
        viewModelScope.launch {
            try {
                val result = sessionStore.fetchReadHistory(page = currentPage)
                _topics.value = _topics.value + result.topics
                hasMore = result.moreTopicsUrl != null
                currentPage++
            } catch (_: Exception) { }
        }
    }

    companion object {
        fun create(sessionStore: FireSessionStore): ReadHistoryViewModel {
            return ReadHistoryViewModel(sessionStore)
        }
    }
}
```

- [ ] **Step 2: 创建布局和 Fragment**

`fragment_read_history.xml`：SwipeRefreshLayout + RecyclerView + 空状态。
`ReadHistoryFragment`：复用 `TopicListAdapter` 模式，点击跳转到 `TopicDetailActivity`。

- [ ] **Step 3: 添加导航和入口**

在 `fire_nav_graph.xml` 中添加 `readHistoryFragment`。
在 `ProfileFragment` 中添加「阅读历史」入口按钮。

- [ ] **Step 4: 构建验证**

Run: `cd native/android-app && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 5: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/readhistory/ native/android-app/src/main/res/layout/fragment_read_history.xml native/android-app/src/main/res/navigation/fire_nav_graph.xml
git commit -m "feat(android): add read history screen with pagination"
```

---

## Task 16: Android — 通知历史全屏页

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationHistoryFragment.kt`
- Create: `native/android-app/src/main/res/layout/fragment_notification_history.xml`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`

- [ ] **Step 1: 创建 NotificationHistoryFragment**

复用 `NotificationPagingSource`，独立全屏页面展示所有通知历史，支持分组显示（今天/昨天/更早）。

```kotlin
package com.fire.app.ui.notifications

// 分页通知列表，与 NotificationsFragment 共享 PagingSource
// 区别：全屏显示、分组 section headers
```

- [ ] **Step 2: 布局和导航**

`fragment_notification_history.xml`：SwipeRefreshLayout + RecyclerView。
在 `fire_nav_graph.xml` 中添加 `notificationHistoryFragment`。
在 `NotificationsFragment` 中添加「查看全部」按钮导航。

- [ ] **Step 3: 构建验证**

Run: `cd native/android-app && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationHistoryFragment.kt native/android-app/src/main/res/layout/fragment_notification_history.xml native/android-app/src/main/res/navigation/fire_nav_graph.xml
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
