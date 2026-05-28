# Android Native App: iOS Feature Alignment Implementation Plan

## 1. Overview

将 Android 应用从当前的原始 Activity/Button 原型全面重建为与 iOS 对齐的原生应用。技术方案：传统 Android View 系统 + RecyclerView 生态 + MVVM 架构 + Navigation Fragment，富文本走 Rust 底层解析。

### 核心约束

- **UI 框架**：Android 原生 View 系统，不使用 Jetpack Compose
- **列表系统**：RecyclerView + ListAdapter + DiffUtil + Paging 3
- **架构模式**：MVVM（ViewModel + Repository + Flow/LiveData）
- **导航**：Jetpack Navigation Fragment + Safe Args
- **富文本**：Rust `parseCookedHtml` → AST → SpannableString（与 iOS `FireRichTextAttributedStringBuilder` 对等）
- **Rust 边界**：保持 AGENTS.md 中定义的 platform/Rust ownership split

### 与 iOS 的对应关系

| iOS | Android |
|-----|---------|
| SwiftUI View | Fragment + XML Layout / ViewBinding |
| @Published / ObservableObject | StateFlow / SharedFlow + ViewModel |
| UICollectionView + DiffableDataSource | RecyclerView + ListAdapter + DiffUtil |
| UICollectionLayoutSection | ConcatAdapter / multiple ViewType |
| NSAttributedString | SpannableString |
| NSTextAttachment (emoji) | ImageSpan + async image loading |
| NavigationStack / NavigationLink | Navigation Fragment + Safe Args |
| @AppStorage | DataStore / SharedPreferences |
| WKWebView | WebView (android.webkit) |
| Keychain | EncryptedSharedPreferences / Keystore |
| NSCache | LruCache |

## 2. Architecture Decision Record

### ADR-1: 传统 View 系统 + RecyclerView（不使用 Compose）

**决策**：采用传统 Android View 系统，RecyclerView 及其生态组件作为列表基础设施。

**理由**：
- RecyclerView 生态成熟稳定，Paging 3 / DiffUtil / ItemDecoration / ConcatAdapter 完整覆盖列表场景
- 与 iOS `ListKit`（UICollectionView + DiffableDataSource）对等映射
- 传统 View 系统对 SpannableString 富文本渲染有完整原生支持
- 避免 Compose 与 View 系统互操作带来的架构复杂度

**影响**：
- XML layout + ViewBinding 作为视图层
- 需要手写 ViewHolder / Adapter，但可通过基类模板减少重复

### ADR-2: MVVM + Navigation Fragment

**决策**：ViewModel + Repository + Flow 作为架构模式，Navigation Fragment 作为导航框架。

**理由**：
- 与 iOS `FireAppViewModel` / `FireHomeFeedStore` 等 ObservableObject 对应
- ViewModel 生命周期与 Navigation Fragment 天然对齐
- Flow 对应 iOS 的 async/await + @Published 组合
- Safe Args 提供类型安全导航，对应 iOS `FireAppRoute`

### ADR-3: Rust AST → SpannableString 富文本渲染

**决策**：消费 Rust `parseCookedHtml` 产出的 AST，在 Android 侧生成 SpannableString。

**理由**：
- 与 iOS `FireRichTextAttributedStringBuilder` 完全对等
- 单个 TextView 渲染整个 post body，适合 RecyclerView 复用
- 替代当前 `FireCookedHtmlRenderer` 的 LinearLayout 嵌套方案（性能差且无法在 RecyclerView 中复用）
- SpannableString 是 Android 原生富文本格式，支持 ClickableSpan / ImageSpan / StyleSpan 等

### ADR-4: Paging 3 作为分页基础设施

**决策**：使用 AndroidX Paging 3 库统一所有列表分页逻辑。

**理由**：
- 与 iOS `FireDiffableListController` + 手动分页逻辑对等
- Paging 3 内置预取（prefetch）对应 iOS 的 `paginationPrefetchDistance`
- 与 RecyclerView 无缝集成
- 统一 home feed / notifications / search / topic detail posts 的分页模式

## 3. Package Structure

```
com.fire.app/
├── FireApplication.kt                    // Application subclass
├── MainActivity.kt                       // 单 Activity，承载 NavHostFragment
│
├── core/
│   ├── ext/                              // Kotlin 扩展函数
│   ├── util/                             // 通用工具类
│   ├── image/                            // 图片加载管线 (FireImageLoader)
│   └── theme/                            // 主题 / 颜色 / 字体 (对应 iOS FireTheme)
│
├── data/
│   ├── repository/
│   │   ├── SessionRepository.kt          // 对应 iOS FireAppViewModel session 部分
│   │   ├── TopicRepository.kt            // 对应 iOS FireHomeFeedStore / FireTopicDetailStore
│   │   ├── NotificationRepository.kt     // 对应 iOS FireNotificationStore
│   │   ├── SearchRepository.kt           // 对应 iOS FireSearchStore
│   │   ├── UserRepository.kt             // 对应 iOS FireProfileViewModel
│   │   └── MessageBusRepository.kt       // 对应 iOS FireMessageBusCoordinator
│   ├── paging/
│   │   ├── TopicListPagingSource.kt      // Home feed 分页
│   │   ├── NotificationPagingSource.kt   // 通知分页
│   │   ├── SearchPagingSource.kt         // 搜索分页
│   │   └── TopicPostPagingSource.kt      // 话题帖子分页
│   └── local/
│       ├── SessionLocalDataSource.kt     // Session 持久化 (DataStore / EncryptedSP)
│       └── PreferenceDataSource.kt       // 用户偏好 (对应 @AppStorage)
│
├── ui/
│   ├── common/
│   │   ├── widget/                       // 通用自定义 View
│   │   │   ├── FireRecyclerView.kt       // 封装 RecyclerView 通用配置
│   │   │   ├── FireSwipeRefreshLayout.kt // 下拉刷新封装
│   │   │   ├── FireEmptyStateView.kt     // 空状态视图
│   │   │   ├── FireLoadingStateView.kt   // 加载状态视图
│   │   │   └── FireChipGroup.kt          // 标签 chip 组
│   │   └── adapter/
│   │       ├── FireListAdapter.kt        // ListAdapter 基类
│   │       ├── FirePagingAdapter.kt      // PagingDataAdapter 基类
│   │       └── FireConcatAdapterBuilder.kt // ConcatAdapter 构建器
│   │
│   ├── home/
│   │   ├── HomeFragment.kt              // 对应 iOS FireHomeView
│   │   ├── HomeViewModel.kt             // 对应 iOS FireHomeFeedStore
│   │   ├── TopicListAdapter.kt          // 话题列表 Adapter
│   │   └── TopicRowViewHolder.kt        // 对应 iOS FireTopicRow
│   │
│   ├── topicdetail/
│   │   ├── TopicDetailFragment.kt       // 对应 iOS FireTopicDetailView
│   │   ├── TopicDetailViewModel.kt      // 对应 iOS FireTopicDetailStore
│   │   ├── PostListAdapter.kt           // 帖子列表 Adapter
│   │   ├── PostViewHolder.kt            // 帖子 ViewHolder
│   │   └── PostHeaderViewHolder.kt      // 话题头 ViewHolder
│   │
│   ├── notifications/
│   │   ├── NotificationsFragment.kt     // 对应 iOS FireNotificationsView
│   │   ├── NotificationsViewModel.kt    // 对应 iOS FireNotificationStore
│   │   └── NotificationListAdapter.kt
│   │
│   ├── search/
│   │   ├── SearchFragment.kt            // 对应 iOS FireSearchView
│   │   ├── SearchViewModel.kt           // 对应 iOS FireSearchStore
│   │   └── SearchResultsAdapter.kt
│   │
│   ├── profile/
│   │   ├── ProfileFragment.kt           // 对应 iOS FireProfileView
│   │   ├── ProfileViewModel.kt          // 对应 iOS FireProfileViewModel
│   │   └── ProfileAdapter.kt
│   │
│   ├── composer/
│   │   ├── ReplyComposerSheet.kt        // 对应 iOS FireComposerView
│   │   ├── TopicComposerSheet.kt        // 对应 iOS FireTopicEditorView
│   │   └── ComposerViewModel.kt
│   │
│   ├── auth/
│   │   ├── OnboardingFragment.kt        // 对应 iOS FireOnboardingView
│   │   ├── LoginWebViewFragment.kt      // 对应 iOS FireLoginWebView / FireAuthScreen
│   │   ├── CloudflareRecoverySheet.kt   // 对应 iOS FireCloudflareRecoverySheet
│   │   └── AuthViewModel.kt
│   │
│   ├── bookmarks/
│   │   ├── BookmarksFragment.kt         // 对应 iOS FireBookmarksView
│   │   └── BookmarksViewModel.kt
│   │
│   └── privatemessages/
│       ├── PrivateMessagesFragment.kt   // 对应 iOS FirePrivateMessagesView
│       └── PrivateMessagesViewModel.kt
│
├── richtext/
│   ├── FireRichTextParser.kt            // Rust AST → FireRichTextNode 映射
│   ├── FireRichTextNode.kt              // 对应 iOS FireRichTextNode enum
│   ├── FireRichTextContent.kt           // 对应 iOS FireRichTextContent
│   ├── FireSpannableBuilder.kt          // 对应 iOS FireRichTextAttributedStringBuilder
│   ├── FireRichTextView.kt              // 对应 iOS FireRichTextView (UIViewRepresentable)
│   ├── FireEmojiImageSpan.kt            // 对应 iOS FireRichTextEmojiAttachment
│   └── span/                            // 自定义 Span
│       ├── FireQuoteSpan.kt             // 引用块装饰
│       ├── FireSpoilerSpan.kt           // 剧透遮罩
│       └── FireCodeBlockSpan.kt         // 代码块背景
│
├── navigation/
│   ├── FireNavGraph.kt                  // Navigation graph 定义
│   ├── FireRoute.kt                     // 对应 iOS FireAppRoute
│   ├── FireRouteParser.kt               // 对应 iOS FireRouteParser (deep link)
│   └── FireNavArgs.kt                   // Safe Args 定义
│
├── session/
│   ├── FireSessionStore.kt              // 已有，逐步重构
│   ├── FireSessionStoreRepository.kt    // 已有，逐步重构
│   ├── FireWebViewLoginCoordinator.kt   // 已有，逐步重构
│   └── FireCfClearanceService.kt        // 对应 iOS FireCfClearanceRefreshService
│
└── messagebus/
    └── FireMessageBusCoordinator.kt     // 对应 iOS FireMessageBusCoordinator
```

## 4. Rich Text Engine Design

这是 Android 实现中最关键的技术组件，直接对应 iOS 的 `FireRichTextRenderer.swift`。

### 4.1 数据流

```
Discourse cooked HTML (String)
    ↓  Rust parseCookedHtml()
CookedHtmlDocumentState (UniFFI AST)
    ↓  FireRichTextParser.parse()
FireRichTextContent (platform nodes + plainText + imageAttachments)
    ↓  FireSpannableBuilder.build()
SpannableString (Android native rich text)
    ↓  FireRichTextView
Single TextView per post body
```

### 4.2 FireRichTextNode（Kotlin enum）

与 iOS `FireRichTextNode` 一一对应：

```kotlin
sealed class FireRichTextNode {
    data class Text(val value: String) : FireRichTextNode()
    data class Bold(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Italic(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Strikethrough(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Code(val value: String) : FireRichTextNode()
    data class CodeBlock(val language: String?, val code: String) : FireRichTextNode()
    data class Link(val url: String, val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Mention(val username: String) : FireRichTextNode()
    data class MentionGroup(val name: String, val url: String) : FireRichTextNode()
    data class Hashtag(val text: String, val url: String, val kind: String?) : FireRichTextNode()
    data class Emoji(val url: String, val fallbackText: String, val onlyEmoji: Boolean) : FireRichTextNode()
    data class Heading(val level: Int, val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Blockquote(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Quote(val author: String?, val postNumber: UInt?, val topicId: ULong?, val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Onebox(val url: String?, val title: String?, val description: String?) : FireRichTextNode()
    data class List(val ordered: Boolean, val items: List<List<FireRichTextNode>>) : FireRichTextNode()
    data class ListItem(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Spoiler(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Details(val summary: List<FireRichTextNode>, val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Table(val text: String) : FireRichTextNode()
    data class Video(val url: String, val title: String?) : FireRichTextNode()
    data object Divider : FireRichTextNode()
    data object LineBreak : FireRichTextNode()
    data class Paragraph(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Image(val src: String, val alt: String?, val width: Float?, val height: Float?) : FireRichTextNode()
}
```

### 4.3 FireSpannableBuilder

对应 iOS `FireRichTextAttributedStringBuilder`，核心逻辑：

1. 递归遍历 `FireRichTextNode` 树
2. 为每种 node 类型应用对应 Span：
   - `Bold` → `StyleSpan(Typeface.BOLD)`
   - `Italic` → `StyleSpan(Typeface.ITALIC)`
   - `Strikethrough` → `StrikethroughSpan`
   - `Code` → `TypefaceSpan("monospace")` + `BackgroundColorSpan`
   - `Link` / `Mention` / `Hashtag` → `FireLinkSpan` (ClickableSpan) + `ForegroundColorSpan`
   - `Emoji` → `FireEmojiImageSpan` (ImageSpan) + 异步图片加载
   - `Heading` → `RelativeSizeSpan` + `StyleSpan(BOLD)`
   - `Blockquote` / `Quote` → `FireQuoteSpan` (自定义 QuoteSpan) + `LeadingMarginSpan`
   - `CodeBlock` → `TypefaceSpan("monospace")` + `BackgroundColorSpan` + `LeadingMarginSpan`
   - `Spoiler` → `FireSpoilerSpan` (点击揭示)
   - `List` → 前缀 "• " / "1. " + `LeadingMarginSpan`
   - `Table` → `TypefaceSpan("monospace")` + `BackgroundColorSpan`

3. 渲染上下文（RenderContext）携带基础字号、文字颜色、accent 颜色、代码背景色，与 iOS `RenderContext` 对应

### 4.4 FireRichTextView

对应 iOS `FireRichTextView`（UIViewRepresentable），核心特性：

- 继承 `AppCompatTextView`
- `isScrollEnabled = false`（自适应高度，在 RecyclerView 中使用）
- `LinkMovementMethod` 处理链接点击
- 异步 emoji 图片加载（通过 `FireEmojiImageSpan` 占位 + 回填）
- 固有高度缓存（`intrinsicContentHeight`），对应 iOS 的 `intrinsicHeightCache`

### 4.5 Emoji 图片加载

对应 iOS `FireRichTextEmojiAttachment` + `FireRemoteImagePipeline`：

1. 解析时插入 `FireEmojiImageSpan` 占位（透明 1x1 drawable）
2. 记录 span 的 URL 和占位区域
3. 异步加载图片（Coil / Glide）
4. 加载完成后替换 drawable，调用 `invalidateDrawable` 触发重绘
5. `onlyEmoji` 模式：图片尺寸为 `1.9x baseFont`；行内模式：`1.15x baseFont`

### 4.6 与当前 FireCookedHtmlRenderer 的关系

当前 `FireCookedHtmlRenderer` 产出 `LinearLayout` 嵌套 View 树，将在新方案中完全替换。新方案的 `FireSpannableBuilder` 产出 `SpannableString`，配合 `FireRichTextView` 实现单 TextView 渲染，性能和复用性大幅提升。

## 5. List System Design

对应 iOS `ListKit/` 模块。

### 5.1 RecyclerView + ListAdapter + DiffUtil

iOS 的 `FireDiffableListController` 基于 `UICollectionView.DiffableDataSource`。Android 对等方案：

- `ListAdapter<T, VH>` — 内置 DiffUtil 异步 diff
- `DiffUtil.ItemCallback<T>` — 对应 iOS 的 content version diff
- `RecyclerView.ItemDecoration` — 对应 iOS 的 section spacing / divider
- `ConcatAdapter` — 对应 iOS 多 section（header + items + footer）

### 5.2 Paging 3

iOS 的手动分页逻辑（`paginationPrefetchDistance` + `loadMoreFeed`）在 Android 上用 Paging 3 统一：

```
PagingSource<Key, Value>
    ↓ RemoteMediator (可选，用于本地缓存)
Flow<PagingData<Value>>
    ↓ PagingDataAdapter (或 FlowAdapter + ListAdapter)
RecyclerView
```

具体分页源：
- `TopicListPagingSource` — 首页话题列表，对应 iOS `FireHomeFeedStore.loadTopics`
- `TopicPostPagingSource` — 话题详情帖子列表，对应 iOS `FireTopicDetailStore.loadNextTopicResponsePage`
- `NotificationPagingSource` — 通知列表，对应 iOS `FireNotificationStore.loadFullPage`
- `SearchPagingSource` — 搜索结果，对应 iOS `FireSearchStore`

### 5.3 预取与滚动监控

对应 iOS `FireCollectionScrollMetrics` + `paginationPrefetchDistance`：

- RecyclerView 的 `RecyclerView.RecycledViewPool` + `PrefetchLayoutManager`（LinearLayoutManager 已内置 prefetch）
- `RecyclerView.OnScrollListener` 监控滚动距离，用于：
  - 触发预加载
  - 记录阅读进度（对应 iOS `FireTopicTimingTracker`）

### 5.4 列表项类型

| iOS Section | Android ViewType | ViewHolder |
|-------------|-----------------|------------|
| TopicRow | TYPE_TOPIC | TopicRowViewHolder |
| TopicHeader | TYPE_TOPIC_HEADER | PostHeaderViewHolder |
| PostRow | TYPE_POST | PostViewHolder |
| NotificationRow | TYPE_NOTIFICATION | NotificationViewHolder |
| SearchResultRow | TYPE_SEARCH_RESULT | SearchResultViewHolder |
| LoadingFooter | TYPE_LOADING | LoadingViewHolder |
| EmptyState | TYPE_EMPTY | EmptyStateViewHolder |

## 6. Navigation & Routing

对应 iOS `Routing/` 模块。

### 6.1 Navigation Graph

```xml
<!-- res/navigation/fire_nav_graph.xml -->
<nav_graph>
    <fragment id="@+id/onboarding" destination="@id/onboardingFragment"/>
    <fragment id="@+id/home" destination="@id/homeFragment">
        <action destination="@id/topicDetailFragment"/>
        <action destination="@id/searchFragment"/>
        <action destination="@id/composerSheet"/>
    </fragment>
    <fragment id="@+id/notifications" destination="@id/notificationsFragment">
        <action destination="@id/topicDetailFragment"/>
        <action destination="@id/profileFragment"/>
    </fragment>
    <fragment id="@+id/profile" destination="@id/profileFragment">
        <action destination="@id/bookmarksFragment"/>
        <action destination="@id/privateMessagesFragment"/>
        <action destination="@id/settingsFragment"/>
    </fragment>
    <fragment id="@+id/topicDetail" destination="@id/topicDetailFragment">
        <argument name="topicId" type="long"/>
        <argument name="topicSlug" type="string" nullable="true"/>
        <argument name="targetPostNumber" type="integer" nullable="true"/>
        <action destination="@id/profileFragment"/>
        <action destination="@id/replyComposerSheet"/>
    </fragment>
    <fragment id="@+id/search" destination="@id/searchFragment"/>
    <dialog id="@+id/replyComposer" destination="@id/replyComposerSheet"/>
    <dialog id="@+id/cloudflareRecovery" destination="@id/cloudflareRecoverySheet"/>
</nav_graph>
```

### 6.2 Deep Link

对应 iOS `FireRouteParser`，支持 `fire://` scheme：

- `fire://topic/{topicId}` → TopicDetailFragment
- `fire://topic/{topicId}/{postNumber}` → TopicDetailFragment with scroll target
- `fire://profile/{username}` → ProfileFragment
- `fire://badge/{id}/{slug}` → BadgeDetailFragment

通过 Navigation 的 `deepLink` 属性定义，与 iOS `FireNavigationState.handleIncomingURL` 对等。

### 6.3 Bottom Navigation

对应 iOS `TabView`：

```xml
<!-- res/menu/bottom_nav_menu.xml -->
<menu>
    <item id="@+id/home" icon="@drawable/ic_home" title="首页"/>
    <item id="@+id/notifications" icon="@drawable/ic_notifications" title="通知"/>
    <item id="@+id/profile" icon="@drawable/ic_profile" title="我的"/>
</menu>
```

`BottomNavigationView` + `NavigationUI.setupWithNavController()`。

## 7. Session & Auth

对应 iOS `FireAppViewModel` 的 session/auth 部分 + `FireLoginWebView` + Cloudflare recovery。

### 7.1 Session Lifecycle

与 iOS 对齐：

1. Cold start → `restorePersistedSessionIfAvailable`
2. CSRF refresh → `refreshCsrfTokenIfNeeded`
3. Bootstrap refresh → `refreshBootstrapIfNeeded`
4. Ready → `canReadAuthenticatedApi` / `canWriteAuthenticatedApi`
5. Cloudflare challenge → interactive recovery (WebView)
6. Logout → `logout_remote` / `logout_local`

### 7.2 Cloudflare Recovery

对应 iOS Cloudflare recovery 流程（含未落地的 browser-alignment-plan 改进）：

- `CloudflareRecoverySheet` 作为 BottomSheetDialogFragment
- 加载浏览器 HTML URL（非 `/login`，非 JSON endpoint）
- Topic-detail 触发的 recovery 使用 topic HTML page
- 通用 recovery 使用 site root
- Recovery 完成后自动同步 cookie → 重试被阻塞操作
- 冷却期抑制：成功 recovery 后 10 秒内不再弹出

### 7.3 WebView Login

保留现有 `LoginActivity` + `FireWebViewLoginCoordinator` 的核心逻辑，迁移为 Fragment：

- `LoginWebViewFragment` 替代 `LoginActivity`
- WebView 配置对齐 iOS `FireWebViewBox` / `FireLoginWebView`
- Cookie 提取 → `sync_login_context` → session persistence

## 8. Feature Alignment Matrix

### 8.1 Home Feed

| iOS 功能 | Android 对应 | 状态 |
|---------|-------------|------|
| Topic list (latest/new/unread/unseen/hot/top) | Paging 3 + TopicListPagingSource | 需重建 |
| Category filter | CategoryChipGroup + FilterBar | 需重建 |
| Tag filter | TagChipGroup + TagPickerSheet | 需重建 |
| Pull to refresh | SwipeRefreshLayout | 需重建 |
| Pagination prefetch | Paging 3 prefetch | 需重建 |
| Topic row card | TopicRowViewHolder (item_topic_row.xml) | 需重建 |
| Category/tag/status chips | Material Chip / custom view | 需重建 |
| Private message inbox/sent | TopicListPagingSource (PM variant) | 需重建 |
| Bookmarks list | BookmarksFragment + Paging | 需重建 |
| Read history | HistoryFragment + Paging | 需重建 |
| Create topic composer | TopicComposerSheet (BottomSheet) | 需重建 |

### 8.2 Topic Detail

| iOS 功能 | Android 对应 | 状态 |
|---------|-------------|------|
| Post list with rich text | PostListAdapter + FireRichTextView | 需重建 |
| Topic header (title, tags, category) | PostHeaderViewHolder | 需重建 |
| Post author avatar + username | AuthorView (custom view) | 需重建 |
| Post reactions (heart + custom) | ReactionBarView (custom view) | 需重建 |
| Reply composer | ReplyComposerSheet (BottomSheet) | 需重建 |
| Post actions (like/reply/bookmark/flag) | PostActionBottomSheet | 需重建 |
| Quote post navigation | Deep link navigation | 需重建 |
| Mention/hashtag click | FireLinkSpan → Navigation | 需重建 |
| Post timing tracker | TopicTimingTracker (onScrollListener) | 需新增 |
| AI summary | AISummaryViewHolder | 需新增 |
| Poll voting | PollCardView (custom view) | 需新增 |
| Topic/bookmark edit | EditSheet (BottomSheet) | 需新增 |
| Post delete/recover/report | PostActionBottomSheet | 需新增 |
| Scroll to post number | RecyclerView scroll to position | 需重建 |
| Reply pagination | Paging 3 + TopicPostPagingSource | 需重建 |

### 8.3 Notifications

| iOS 功能 | Android 对应 | 状态 |
|---------|-------------|------|
| Notification list | NotificationListAdapter + Paging | 需重建 |
| Unread badge | BottomNavigationView badge | 需新增 |
| Mark read (single/all) | NotificationViewModel actions | 需重建 |
| Notification → topic/profile navigation | Safe Args navigation | 需重建 |

### 8.4 Search

| iOS 功能 | Android 对应 | 状态 |
|---------|-------------|------|
| Search input + suggestions | SearchView + SearchViewModel | 需重建 |
| Category/tag filters | FilterChipGroup | 需重建 |
| Result list + navigation | SearchResultsAdapter + Paging | 需重建 |

### 8.5 Profile

| iOS 功能 | Android 对等 | 状态 |
|---------|------------|------|
| User info header | ProfileHeaderViewHolder | 需重建 |
| Badge display | BadgeChipView | 需重建 |
| Activity timeline | ProfileAdapter (concat) | 需新增 |
| Follow/unfollow | ProfileViewModel actions | 需重建 |
| Private message compose | PMComposerSheet | 需新增 |
| User notification level | ProfileViewModel actions | 需新增 |

### 8.6 Rich Text Rendering

| iOS 功能 | Android 对应 | 状态 |
|---------|-------------|------|
| Rust AST mapping | FireRichTextParser | 需重写 |
| SpannableString builder | FireSpannableBuilder | 需新增 |
| Emoji async loading | FireEmojiImageSpan + Coil | 需新增 |
| Quote block rendering | FireQuoteSpan | 需新增 |
| Code block rendering | FireCodeBlockSpan | 需新增 |
| Spoiler reveal | FireSpoilerSpan | 需新增 |
| Link click routing | FireLinkSpan → Navigation | 需新增 |
| Image attachments | ImageSpan + click → fullscreen | 需新增 |
| Intrinsic height cache | FireRichTextView.heightCache | 需新增 |

## 9. Dependency List

### AndroidX 核心

```kotlin
// Navigation
implementation("androidx.navigation:navigation-fragment-ktx:2.8.9")
implementation("androidx.navigation:navigation-ui-ktx:2.8.9")

// Lifecycle & ViewModel
implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.8.7")
implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")

// RecyclerView
implementation("androidx.recyclerview:recyclerview:1.4.0")

// Paging 3
implementation("androidx.paging:paging-runtime-ktx:3.3.6")

// SwipeRefreshLayout
implementation("androidx.swiperefreshlayout:swiperefreshlayout:1.1.0")

// WebView
implementation("androidx.webkit:webkit:1.13.0")

// DataStore (preferences)
implementation("androidx.datastore:datastore-preferences:1.1.4")

// Material Design
implementation("com.google.android.material:material:1.12.0")

// Activity & Fragment
implementation("androidx.activity:activity-ktx:1.10.1")
implementation("androidx.fragment:fragment-ktx:1.8.6")

// Core
implementation("androidx.core:core-ktx:1.15.0")
implementation("androidx.appcompat:appcompat:1.7.1")
implementation("androidx.constraintlayout:constraintlayout:2.2.1")

// Coroutines
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

// UniFFI / JNA
implementation("net.java.dev.jna:jna:5.16.0@aar")
```

### 图片加载

```kotlin
// Coil (轻量 Kotlin-first 图片加载库)
implementation("io.coil-kt:coil:2.7.0")
```

选择 Coil 而非 Glide 的理由：
- Kotlin-first API，与 Coroutines 天然集成
- 轻量（~1.5MB vs Glide ~5MB）
- 支持 SVG / GIF / WebP
- 与 RecyclerView + ViewHolder 生命周期集成良好

## 10. Phased Implementation Plan

### Phase 0: Infrastructure Foundation

**目标**：建立 MVVM 骨架，迁移到单 Activity + Navigation Fragment。

**文件变更**：

1. 新建 `FireApplication.kt` — Application subclass，初始化全局依赖
2. 重构 `MainActivity.kt` — 改为单 Activity 承载 `NavHostFragment` + `BottomNavigationView`
3. 新建 `res/navigation/fire_nav_graph.xml` — 导航图
4. 新建 `res/menu/bottom_nav_menu.xml` — 底部导航菜单
5. 新建 `core/theme/` — 颜色/字体/主题定义，对应 iOS `FireTheme`
6. 新建 `core/ext/` — Kotlin 扩展函数
7. 重构 `build.gradle.kts` — 添加 Navigation / Paging / Lifecycle 依赖，启用 ViewBinding
8. 新建 `data/repository/SessionRepository.kt` — 封装现有 `FireSessionStore`

**验证**：单 Activity 启动，底部导航切换空 Fragment。

### Phase 1: Rich Text Engine

**目标**：实现 Rust AST → SpannableString 富文本渲染管线，替代 `FireCookedHtmlRenderer`。

**文件变更**：

1. 新建 `richtext/FireRichTextNode.kt` — platform node 模型
2. 新建 `richtext/FireRichTextParser.kt` — UniFFI AST → FireRichTextNode 映射
3. 新建 `richtext/FireRichTextContent.kt` — 解析结果容器
4. 新建 `richtext/FireSpannableBuilder.kt` — 核心 SpannableString 构建
5. 新建 `richtext/span/FireQuoteSpan.kt` — 引用块装饰 Span
6. 新建 `richtext/span/FireSpoilerSpan.kt` — 剧透遮罩 Span
7. 新建 `richtext/span/FireCodeBlockSpan.kt` — 代码块背景 Span
8. 新建 `richtext/FireEmojiImageSpan.kt` — Emoji 异步图片 Span
9. 新建 `richtext/FireRichTextView.kt` — 自适应高度 TextView
10. 新建 `core/image/FireImageLoader.kt` — 图片加载管线（基于 Coil）
11. 删除/弃用 `FireCookedHtmlRenderer.kt`

**验证**：单元测试覆盖所有 node 类型 → SpannableString 映射；手动验证典型 Discourse cooked HTML 渲染。

### Phase 2: Home Feed

**目标**：实现首页话题列表，对齐 iOS `FireHomeView` + `FireHomeCollectionView`。

**文件变更**：

1. 新建 `data/paging/TopicListPagingSource.kt` — 话题列表分页源
2. 新建 `ui/home/HomeFragment.kt` — 首页 Fragment
3. 新建 `ui/home/HomeViewModel.kt` — 首页 ViewModel
4. 新建 `ui/home/TopicListAdapter.kt` — 话题列表 Adapter
5. 新建 `ui/home/TopicRowViewHolder.kt` — 话题行 ViewHolder
6. 新建 `res/layout/fragment_home.xml` — 首页布局
7. 新建 `res/layout/item_topic_row.xml` — 话题行布局
8. 新建 `ui/common/widget/FireSwipeRefreshLayout.kt` — 下拉刷新封装
9. 新建 `ui/common/widget/FireEmptyStateView.kt` — 空状态
10. 新建 `ui/common/adapter/FirePagingAdapter.kt` — Paging Adapter 基类

**功能对齐**：
- Latest / New / Unread / Unseen / Hot / Top 分类切换
- Pull to refresh
- 分页预取加载
- Category / Tag 筛选
- Topic 行点击 → 导航到 TopicDetail

**验证**：冷启动 → 登录 → 首页列表加载 → 下拉刷新 → 滚动分页 → 切换分类。

### Phase 3: Topic Detail

**目标**：实现话题详情页，对齐 iOS `FireTopicDetailView`。

**文件变更**：

1. 新建 `data/paging/TopicPostPagingSource.kt` — 帖子分页源
2. 新建 `ui/topicdetail/TopicDetailFragment.kt` — 详情 Fragment
3. 新建 `ui/topicdetail/TopicDetailViewModel.kt` — 详情 ViewModel
4. 新建 `ui/topicdetail/PostListAdapter.kt` — 帖子列表 Adapter
5. 新建 `ui/topicdetail/PostViewHolder.kt` — 帖子 ViewHolder
6. 新建 `ui/topicdetail/PostHeaderViewHolder.kt` — 话题头 ViewHolder
7. 新建 `res/layout/fragment_topic_detail.xml` — 详情布局
8. 新建 `res/layout/item_post.xml` — 帖子布局
9. 新建 `res/layout/item_topic_header.xml` — 话题头布局

**功能对齐**：
- 话题标题 / 标签 / 分类头
- Post 富文本渲染（FireRichTextView）
- 作者头像 + 用户名
- 滚动到目标楼层
- 帖子分页加载
- Reaction 显示（heart + custom）
- Reply composer (BottomSheet)
- Post actions（like / reply / bookmark / share）
- Mention / hashtag / quote 链接点击导航
- Topic timing tracker

**验证**：话题列表 → 点击进入详情 → 富文本渲染 → 滚动 → 分页 → 回复 → 反应。

### Phase 4: Auth & Session

**目标**：实现完整的登录 / Cloudflare 恢复流程，对齐 iOS `FireOnboardingView` + `FireAuthScreen` + Cloudflare recovery。

**文件变更**：

1. 重构 `session/FireWebViewLoginCoordinator.kt` — 迁移为 Fragment 兼容
2. 新建 `ui/auth/OnboardingFragment.kt` — 登录引导页
3. 新建 `ui/auth/LoginWebViewFragment.kt` — WebView 登录
4. 新建 `ui/auth/CloudflareRecoverySheet.kt` — Cloudflare 恢复 BottomSheet
5. 新建 `ui/auth/AuthViewModel.kt` — Auth 状态管理
6. 新建 `res/layout/fragment_onboarding.xml`
7. 新建 `res/layout/fragment_login_webview.xml`
8. 新建 `res/layout/sheet_cloudflare_recovery.xml`
9. 新建 `session/FireCfClearanceService.kt` — CF clearance 刷新服务

**功能对齐**：
- 冷启动 session 恢复
- WebView 登录流程（cookie 提取 → sync_login_context）
- Cloudflare challenge 检测 → 恢复 sheet
- Recovery URL routing（topic HTML / site root）
- 冷却期抑制
- 登出（remote + local）

**验证**：冷启动 → 未登录 → 登录 → session 恢复 → Cloudflare 挑战 → 恢复 → 重试。

### Phase 5: Notifications

**目标**：实现通知中心，对齐 iOS `FireNotificationsView`。

**文件变更**：

1. 新建 `data/paging/NotificationPagingSource.kt`
2. 新建 `ui/notifications/NotificationsFragment.kt`
3. 新建 `ui/notifications/NotificationsViewModel.kt`
4. 新建 `ui/notifications/NotificationListAdapter.kt`
5. 新建 `res/layout/fragment_notifications.xml`
6. 新建 `res/layout/item_notification.xml`
7. 新建 `messagebus/FireMessageBusCoordinator.kt` — MessageBus 协调

**功能对齐**：
- 通知列表 + 分页
- 未读计数 badge
- 标记已读（单条 / 全部）
- MessageBus 实时推送更新
- 通知点击 → topic / profile 导航

**验证**：通知列表加载 → MessageBus 实时更新 → 点击导航 → 标记已读。

### Phase 6: Search

**目标**：实现搜索功能，对齐 iOS `FireSearchView`。

**文件变更**：

1. 新建 `data/paging/SearchPagingSource.kt`
2. 新建 `ui/search/SearchFragment.kt`
3. 新建 `ui/search/SearchViewModel.kt`
4. 新建 `ui/search/SearchResultsAdapter.kt`
5. 新建 `res/layout/fragment_search.xml`
6. 新建 `res/layout/item_search_result.xml`

**功能对齐**：
- 搜索输入 + 建议去抖
- Category / tag / 日期筛选
- 结果列表 + 分页
- 结果点击 → topic / profile 导航

**验证**：搜索 → 筛选 → 结果导航。

### Phase 7: Profile & Settings

**目标**：实现个人中心，对齐 iOS `FireProfileView`。

**文件变更**：

1. 新建 `ui/profile/ProfileFragment.kt`
2. 新建 `ui/profile/ProfileViewModel.kt`
3. 新建 `ui/profile/ProfileAdapter.kt` — ConcatAdapter（header + activity）
4. 新建 `ui/bookmarks/BookmarksFragment.kt`
5. 新建 `ui/bookmarks/BookmarksViewModel.kt`
6. 新建 `ui/privatemessages/PrivateMessagesFragment.kt`
7. 新建 `ui/privatemessages/PrivateMessagesViewModel.kt`
8. 新建 `res/layout/fragment_profile.xml`
9. 新建 `res/layout/fragment_bookmarks.xml`
10. 新建 `res/layout/fragment_private_messages.xml`

**功能对齐**：
- 用户信息头（头像、用户名、信任等级）
- 徽章展示
- 活动时间线
- 关注 / 取关
- 私信发起
- 书签列表
- 私信列表
- 外观偏好设置（对应 iOS `FireAppearancePreference`）

**验证**：个人中心 → 徽章 → 活动时间线 → 关注操作 → 书签 → 私信。

### Phase 8: Composers & Advanced Interactions

**目标**：实现各类编辑器和高级交互，对齐 iOS Composer / Editor / Poll / Bookmark 等。

**文件变更**：

1. 新建 `ui/composer/ReplyComposerSheet.kt` — BottomSheet 回复编辑器
2. 新建 `ui/composer/TopicComposerSheet.kt` — BottomSheet 发帖编辑器
3. 新建 `ui/composer/ComposerViewModel.kt`
4. 新建 `res/layout/sheet_reply_composer.xml`
5. 新建 `res/layout/sheet_topic_composer.xml`
6. 新建 Topic detail 内的 Poll / Bookmark / Edit / Delete / Report 组件

**功能对齐**：
- 回复编辑器（话题回复 + 楼层回复）
- 发帖编辑器（标题 + 分类 + 标签 + 正文 + 校验）
- 投票卡片
- 书签创建/更新/删除
- 帖子编辑
- 话题元数据编辑
- 帖子删除/恢复/举报
- Reaction picker（自定义反应选择器）

**验证**：发帖 → 回复 → 编辑 → 书签 → 投票 → 反应 → 举报。

### Phase 9: Polish & Optimization

**目标**：性能优化、主题完善、辅助功能。

**文件变更**：

1. 完善 `core/theme/` — dark mode / 动态颜色
2. RecyclerView 性能优化 — RecycledViewPool / setHasFixedSize / setItemViewCacheSize
3. 图片加载优化 — 内存缓存策略 / 列表滑动暂停加载
4. 内存泄漏检查 — LeakCanary 集成
5. 辅助功能 — contentDescription / talkback
6. Deep link 完善 — `fire://` scheme 注册
7. 启动优化 — 初始化延迟 / splash screen
8. 文档同步 — `docs/architecture/fire-native-workspace.md` 更新 Android 部分

**验证**：内存分析 → 滑动流畅度 → dark mode 切换 → deep link → 启动时间。

## 11. Architectural Notes

- **Semver impact**：无。这是 Android 原型到生产级应用的完整重建。
- **Ownership split**：保持 AGENTS.md 定义不变。Rust 仍然拥有 session state、challenge classification、API orchestration、MessageBus、shared models；Android 仍然拥有 WebView login、cookie extraction、native UI、notifications presentation。
- **Dependency impact**：新增 Navigation / Paging / Coil 等依赖，移除不需要的旧依赖。
- **UniFFI 边界**：`FireAppCore` 及其 handles（session / topics / notifications / search / user / diagnostics / messagebus）保持不变。Android Repository 层封装这些 handles 的 async 调用，转换为 Flow。
- **现有代码迁移**：`FireSessionStore` / `FireSessionStoreRepository` / `FireWebViewLoginCoordinator` 保留并逐步重构，不一次性重写。

## 12. File Change Summary

### 新增文件（~70 个）

- `core/` — 8 个文件（ext / util / image / theme）
- `data/` — 10 个文件（repository / paging / local）
- `ui/` — 30+ 个文件（Fragment / ViewModel / Adapter / ViewHolder / layout XML）
- `richtext/` — 11 个文件（parser / builder / span / view）
- `navigation/` — 4 个文件（graph / route / parser / args）
- `session/` — 1 个文件（CfClearanceService）
- `messagebus/` — 1 个文件（MessageBusCoordinator）
- `FireApplication.kt` — 1 个文件
- 资源文件 — 15+ 个（navigation XML / menu XML / layout XML / drawable）

### 重构文件

- `MainActivity.kt` — 单 Activity 改造
- `build.gradle.kts` — 依赖升级 / ViewBinding 启用
- `FireSessionStore.kt` — Repository 层封装
- `FireSessionStoreRepository.kt` — Repository 层封装
- `FireWebViewLoginCoordinator.kt` — Fragment 兼容迁移

### 删除文件

- `FireCookedHtmlRenderer.kt` — 被 richtext 模块完全替代
- `LoginActivity.kt` — 被 LoginWebViewFragment 替代
- `NotificationsActivity.kt` — 被 NotificationsFragment 替代
- `SearchActivity.kt` — 被 SearchFragment 替代
- `TopicDetailActivity.kt` — 被 TopicDetailFragment 替代
- `ProfileActivity.kt` — 被 ProfileFragment 替代
- `DiagnosticsActivity.kt` — 被内部 Fragment 替代
- `LogViewerActivity.kt` — 被内部 Fragment 替代
- `RequestTraceDetailActivity.kt` — 被内部 Fragment 替代
- 所有 Activity 对应的 layout XML — 被 Fragment layout 替代
