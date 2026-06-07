# Fire Native Architecture

## 1. Architecture Overview

### 1.1 Core Principle

**Rust is the sole logic engine. iOS and Android are pure data-consumption and presentation layers.** Platform code performs no business logic — it does not parse JSON, construct URLs, manage session state, decide cache policy, or handle retries. The platform answers exactly one question: **what does the user see, and what did the user tap?**

### 1.2 Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Platform Layer                          │
│  iOS (Swift / UIKit / Texture)  │  Android (Kotlin / androidx)│
│  UI rendering, user interaction,│  UI rendering, user interaction,
│  platform bridging              │  platform bridging           │
├─────────────────────────────────────────────────────────────┤
│                    UniFFI Boundary                            │
│  Type-safe Rust↔Platform data flow, zero business logic      │
├─────────────────────────────────────────────────────────────┤
│                      Rust Core                                │
│  Networking │ Database │ Rich Text │ Image │ Cache │ Session │
│  File I/O   │ Threading│ Timers   │ Log   │ Diag  │ Search  │
│  MessageBus │ Interactions (like/reply/vote/bookmark/flag)   │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 Responsibility Shift from Current Architecture

| Responsibility | Current State | Target State |
|---|---|---|
| Rich text parsing | Rust parses AST, each platform builds render semantics independently | Rust outputs unified `RenderDocument` semantic blocks, platforms only map shared blocks to native text/image nodes |
| Image processing | Platforms handle everything via Nuke/Coil independently | Rust decodes/scales/converts, platforms receive pixel buffers |
| Session state | iOS Store holds extensive `@Published` state | Rust remains the source of truth for session snapshots; platforms consume pushed snapshot copies plus explicit command results |
| Pagination / cache policy | iOS Store orchestrates logic | Rust fully orchestrates, platforms receive paginated results |
| Error handling | Platforms classify errors and decide retries | Rust classifies and auto-retries, platforms only receive final outcomes |
| State updates | Platforms pull after refresh/message events | `FireAppCore` pushes immutable snapshots on the current stable boundaries (`session`, `topic_list`, `topic_detail_feed`, `notification_center`) while explicit pagination and screen commands remain platform-owned |

---

## 2. Rust Core Architecture

### 2.1 Crate Structure

```
rust/
  crates/
    fire-models/            # Pure data models, zero dependencies
    fire-store/             # SQLite persistence
    fire-image/             # Image decode / scale / format convert / cache  (NEW)
    fire-rich-text/         # Rich text AST → render instruction tree        (NEW, extracted from fire-core)
    fire-core/              # Core engine: orchestrates all subsystems
    fire-uniffi-types/      # UniFFI shared types / runtime
    fire-uniffi-session/    # Session FFI handle
    fire-uniffi-topics/     # Topics FFI handle
    fire-uniffi-user/       # User FFI handle
    fire-uniffi-search/     # Search FFI handle
    fire-uniffi-messagebus/ # MessageBus FFI handle
    fire-uniffi-notifications/ # Notifications FFI handle
    fire-uniffi-image/      # Image FFI handle                             (NEW)
    fire-uniffi-diagnostics/ # Diagnostics FFI handle
    fire-uniffi/            # Top-level FFI aggregation
```

### 2.2 Dependency Graph

```
fire-models              (zero deps)
fire-store           ──> fire-models
fire-image           ──> fire-models
fire-rich-text       ──> fire-models
fire-core            ──> fire-models, fire-store, fire-image, fire-rich-text
fire-uniffi-types    ──> fire-core, fire-models
fire-uniffi-*        ──> fire-core, fire-models, fire-uniffi-types
fire-uniffi          ──> all fire-uniffi-*
```

### 2.3 Crate Responsibilities

#### fire-models

Pure data structures shared across all crates. No internal dependencies.

- Session models: `CookieSnapshot`, `BootstrapArtifacts`, `SessionSnapshot`, `LoginPhase`
- Topic models: `TopicSummary`, `TopicDetail`, `TopicPost`, `TopicReaction`, `Poll`
- User models: `UserProfile`, `UserSummary`, `Badge`
- Search / Notification / MessageBus models
- Image models: `ImageRequest`, `ImageMetadata`, `DecodedImage` — **NEW**
- Render instruction models: `RenderBlock`, `RenderBlockKind`, `TextStyle` — **NEW**

#### fire-store

SQLite persistence via `rusqlite` (bundled).

- Topic detail snapshot read/write
- Post and render block caching
- Session persistence
- Image disk cache index — **NEW**

#### fire-image — NEW

Full-pipeline image processing.

- URL parsing and transformation (Discourse `{size}` template, protocol-relative URLs)
- Format detection: JPEG, PNG, WebP, GIF, AVIF
- Decoding via `image` crate or `libwebp` direct decode
- Scaling: Lanczos3 downsample to target dimensions
- Format conversion: transcode to platform-optimal format (BGRA for iOS, ARGB_8888 for Android)
- Memory cache: LRU cache of decoded pixel buffers
- Disk cache: dual cache for raw bytes and decoded bytes
- Prefetch strategy: viewport-predictive loading

#### fire-rich-text — NEW (extracted from fire-core)

Rich text render instruction generation.

- HTML → AST parsing (`scraper` + `html5ever`)
- AST → platform-neutral `RenderBlock` tree
- Render instruction types: text, paragraph, heading, bold, italic, link, image, code block, blockquote, list, table, emoji, mention, hashtag, spoiler, details, onebox, iframe, attachment, unknown
- Each `RenderBlock` carries complete layout information — platforms never need secondary computation

#### fire-core

Core orchestration engine. Owns session state, networking, API orchestration, and delegates to subsystems.

- **Networking**: openwire client + transparent gzip/zlib/brotli/zstd response compression + request epoch guard + CSRF retry + auth signal/probe policy + Cloudflare challenge handler retry + logging
- **Session management**: Cookie sync, Bootstrap parsing, login state machine
- **API orchestration**: topic list, topic detail, post CRUD, user, search, notifications
- **MessageBus**: long-polling, subscription management, channel routing
- **Topic detail orchestration**: raw-source session (`post_stream.stream`, source cursor, batched `post_ids[]` append) plus tree-presentation rebuild
- **Image request orchestration**: delegates to `fire-image`
- **Rich text request orchestration**: delegates to `fire-rich-text`
- **Logging**: mars-xlog integration
- **Diagnostics**: network trace, support bundle export

#### fire-uniffi-\*

FFI boundary layer (maintaining existing pattern).

- Each domain handle exposes Rust API to platforms
- Panic-safe dispatch
- Type mapping: Rust types ↔ FFI record types

### 2.4 State Management Model

Rust now exposes a single top-level `StateObserver` registration point on `FireAppCore`.
The pushed boundaries are intentionally explicit and finite:

- `SessionState`
- `TopicListState`
- `NotificationCenterState`

```
Rust Core                              Platform
  │                                        │
  ├── Immutable snapshot ────────────────>  StateObserver callback
  │   session / topic list / notifications ├── Snapshot diff → UI update
  │                                        │
  ├── Event / command trigger ───────────>  Explicit refresh / page / mutation command
  │                                        │
  └── Command (Platform → Rust)  <───────  User action
      Contains: like, reply, page,         │
      scroll target...                     │
```

**Key constraints:**

- Platforms never decide topic-detail source pagination. They only hold snapshot copies produced by Rust and host-local UI state.
- Snapshots are immutable; platforms can safely hold and diff on the main thread
- State changes can only be sent back to Rust via Command; Rust computes a new snapshot and pushes it

### 2.5 Error Handling Model

Rust automatically handles retries, backoff, and session refresh. Platforms only receive final success or unrecoverable errors.

```
Rust FireCoreError              →  FireUniFfiError           →  Platform behavior
───────────────────────────────────────────────────────────────────────────────────
Network                         →  Network                   →  Show network error
LoginRequired                   →  LoginRequired             →  Surface request failure; no automatic logout/reset
StaleSessionResponse            →  StaleSessionResponse      →  Rust auto-retry, platform unaware
CloudflareChallenge             →  CloudflareChallenge       →  Foreground-capable hosts may complete a platform-owned challenge WebView and let Rust retry once; otherwise surface the request failure
HttpStatus(429)                 →  HttpStatus                →  Rust auto-backoff-retry
Storage                         →  Storage                   →  Degrade to no-cache mode
Other                           →  Runtime                   →  Generic error toast
```

---

## 3. iOS Platform Architecture

### 3.1 Tech Stack

| Item | Choice |
|---|---|
| Language | Swift 5.10+ |
| Minimum version | iOS 16 |
| UI framework | UIKit + Texture (AsyncDisplayKit) |
| Architecture | MVVM |
| Image loading | **Nuke** (upper-layer scheduling + transitions + prefetch), **Rust** (lower-layer decode + cache) |
| Build | XcodeGen |
| FFI | UniFFI static library + generated Swift code |

### 3.2 SwiftUI Migration Strategy

Existing SwiftUI screens will migrate progressively to UIKit + Texture. SwiftUI will ultimately be reduced to a minimal shell for `@main` and the tab container.

| Phase | Scope | Target |
|---|---|---|
| 1 | Topic detail | Already Texture-based |
| 2 | Home feed, notifications, search | Texture `ASCollectionNode` |
| 3 | Profile, bookmarks, messages | UIKit `UICollectionView` |
| 4 | Composer, onboarding/login | UIKit |
| Final | App entry + tab container | Minimal SwiftUI shell only |

### 3.3 Directory Structure

```
native/ios-app/
  App/
    FireApp.swift                        # @main entry, minimal SwiftUI shell
    AppDelegate.swift                    # Lifecycle, push registration

    Core/
      Theme/
        FireDesignTokens.swift           # Cross-platform design constants
      Motion/                            # Animation system
      Extensions/                        # UIKit / Texture extensions

    Session/
      FireSessionStore.swift             # Actor wrapping FireAppCore, sole Rust bridge
      FireAuthCookieKeychainStore.swift
      FireWebViewLoginCoordinator.swift

    Navigation/
      FireNavigationController.swift     # UINavigationController container
      FireRouteRegistry.swift            # Route definitions
      FireRouteControllerFactory.swift

    Stores/                              # Pure observers, zero business logic
      FireHomeFeedStore.swift
      FireTopicDetailStore.swift
      FireNotificationStore.swift
      FireSearchStore.swift

    ViewModels/                          # Pure UI state coordination
      FireAppViewModel.swift
      FireProfileViewModel.swift

  Screens/                               # One directory per screen
    Home/
      FireHomeViewController.swift       # UIViewController + ASCollectionNode
      FireHomeFeedNode.swift             # Topic row ASCellNode
      FireHomeFeedLayout.swift

    TopicDetail/
      FireTopicDetailViewController.swift
      FireTopicDetailFeedController.swift
      FirePostCellNode.swift
      FirePostCellLayout.swift

    Notifications/
      FireNotificationsViewController.swift
      FireNotificationCellNode.swift

    Search/
      FireSearchViewController.swift
      FireSearchResultCellNode.swift

    Profile/
      FireProfileViewController.swift
      FireProfileCellNode.swift

    Composer/
      FireComposerViewController.swift   # UIKit native editor

    Auth/
      FireOnboardingViewController.swift
      FireLoginWebViewController.swift

  Shared/                                # Cross-screen shared components
    Render/
      FireRenderBlockNodeBuilder.swift   # RenderBlock → ASDisplayNode tree
      FireRenderTextNode.swift
      FireRenderImageNode.swift
      FireRenderCodeBlockNode.swift
    Image/
      FireImageBridge.swift              # Rust decoded pixels → CGImage → Texture / Nuke
    RichText/
      FireRichTextRenderer.swift         # RenderBlock nodes → NSAttributedString
    Widgets/
      FireAvatarView.swift
      FireActionButton.swift
      FireBadgeView.swift

  Generated/                             # UniFFI generated code (do not edit)
  Configs/
  Tests/
```

### 3.4 MVVM Data Flow

```
User action
  │
  ▼
ViewController ──Command──> ViewModel/Store ──FFI──> Rust Core
                                                    │
                                                    ▼
                                              Compute new snapshot
                                                    │
ViewController <──Diff── ViewModel/Store <──Snapshot── Rust Core
  │
  ▼
ASCollectionNode.performBatchUpdates
```

**Key constraints:**

- **Store / ViewModel performs zero business logic**: no parsing, no computation, no caching, no retry
- **Store does exactly two things**: (1) forward user actions to Rust (2) diff Rust-pushed snapshots and trigger UI refresh
- **ViewController does exactly two things**: (1) convert user events to Commands (2) map snapshots to cell nodes

### 3.5 Image Pipeline

```
Rust fire-image                      iOS Platform
  │                                    │
  ├─ Decode (JPEG/PNG/WebP/AVIF)       │
  ├─ Scale to target dimensions        │
  ├─ Convert → BGRA pixel buffer       │
  ├─ Memory LRU cache                  │
  ├─ Disk cache                        │
  │                                    │
  └─ Return RawPixelBuffer ──────────> Nuke (retained)
                                       │
                                       ├─ Phase 1: Nuke full pipeline (current)
                                       │   Nuke scheduling + Nuke decoding + Nuke caching
                                       │
                                       ├─ Phase 2: Nuke scheduling + Rust decoding (hybrid)
                                       │   Custom ImageDecoder delegates to Rust
                                       │   Nuke manages request queue, priority, prefetch
                                       │
                                       └─ Phase 3: Rust full pipeline (ultimate)
                                           Rust scheduling + Rust decoding + Rust caching
                                           Nuke degrades to UIImageView placeholder / transition animation
```

**Reasons to retain Nuke:**

- Request scheduling: priority queue, cancellation, deduplication, concurrency control
- Progressive JPEG: Nuke built-in support, high cost to self-build
- Transition animations: crossfade, placeholder→main image switching
- Prefetch strategy: viewport-predictive loading
- Smooth migration: custom `ImageDecoding` protocol delegates decode to Rust, rest of pipeline unchanged

### 3.6 Rich Text Rendering Pipeline

```
Rust fire-rich-text                   iOS Platform
  │                                    │
  ├─ HTML → AST                        │
  ├─ AST → RenderDocument              │
  │   flat semantic blocks +           │
  │   normalized image attachments     │
  │                                    │
  └─ Return RenderDocumentState ─────> FireRenderBlockNodeBuilder
                                       │
                                       ├─ shared blocks → FireRichTextNode
                                       ├─ FireRichTextAttributedStringBuilder
                                       ├─ ASTextNode / native image nodes
                                       └─ no platform-owned cooked fallback
```

### 3.7 Design Tokens

Cross-platform shared design constants. Defined in `Core/Theme/FireDesignTokens.swift` with a 1:1 counterpart in Android.

```swift
enum FireDesignTokens {
    // Spacing
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24

    // Font size
    static let fontTitle: CGFloat = 17
    static let fontBody: CGFloat = 15
    static let fontCaption: CGFloat = 13
    static let fontMicro: CGFloat = 11

    // Corner radius
    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 14
    static let radiusFull: CGFloat = .greatestFiniteMagnitude

    // Colors (1:1 with Android FireDesignTokens)
    static var colorPrimary: UIColor { /* ... */ }
    static var colorBackground: UIColor { /* ... */ }
    static var colorTextPrimary: UIColor { /* ... */ }
    // ... full palette per Section 5.2
}
```

---

## 4. Android Platform Architecture

### 4.1 Tech Stack

| Item | Choice |
|---|---|
| Language | Kotlin 2.2+ |
| Minimum version | API 26 (Android 8.0) |
| Target version | API 35 |
| UI framework | androidx + RecyclerView ecosystem, **no Compose** |
| Architecture | MVVM |
| Image loading | **Coil** (upper-layer scheduling + transitions + prefetch), **Rust** (lower-layer decode + cache) |
| Build | Gradle Kotlin DSL |
| FFI | UniFFI + JNA |

### 4.2 Directory Structure

```
native/android-app/
  src/main/
    java/com/fire/app/

      core/
        theme/
          FireDesignTokens.kt           # 1:1 with iOS design constants
          FireColors.kt                 # Color palette
          FireTypography.kt             # Font size / weight
        image/
          FireImageBridge.kt            # Rust decoded pixels → Bitmap → ImageView
        render/
          FireRenderBlockBuilder.kt     # RenderBlock → View tree
          FireRenderTextView.kt
          FireRenderImageView.kt
          FireRenderCodeBlockView.kt
        ext/
          ViewExt.kt
          ContextExt.kt
          RecyclerViewExt.kt

      session/
        FireSessionStore.kt             # Sole Rust bridge, actor-ized
        FireWebViewLoginCoordinator.kt

      navigation/
        FireRouteRegistry.kt            # Route definitions
        FireNavigationController.kt     # Navigation container

      viewmodel/                        # Pure UI state coordination, zero business logic
        FireHomeViewModel.kt
        FireTopicDetailViewModel.kt
        FireNotificationsViewModel.kt
        FireSearchViewModel.kt
        FireProfileViewModel.kt
        FireComposerViewModel.kt

      ui/                               # One directory per screen
        home/
          FireHomeFragment.kt
          FireHomeAdapter.kt            # RecyclerView.Adapter
          FireTopicRowViewHolder.kt
          FireTopicRowView.kt           # Custom view (not XML layout)

        topicdetail/
          FireTopicDetailActivity.kt
          FirePostListAdapter.kt
          FirePostViewHolder.kt
          FirePostItemView.kt           # Custom view

        notifications/
          FireNotificationsFragment.kt
          FireNotificationAdapter.kt
          FireNotificationItemView.kt

        search/
          FireSearchFragment.kt
          FireSearchAdapter.kt
          FireSearchResultItemView.kt

        profile/
          FireProfileFragment.kt
          FireProfileAdapter.kt
          FireProfileItemView.kt

        composer/
          FireComposerBottomSheet.kt     # Bottom sheet editor

        auth/
          FireOnboardingFragment.kt
          FireLoginWebViewFragment.kt

      messagebus/
        FireMessageBusCoordinator.kt     # Event bridge to Flow

    res/
      values/
        colors.xml
        dimens.xml
      drawable/
      navigation/
        fire_nav_graph.xml
```

### 4.3 MVVM Data Flow

```
User action
  │
  ▼
Fragment/Activity ──Command──> ViewModel ──FFI──> Rust Core
                                                  │
                                                  ▼
                                            Compute new snapshot
                                                  │
Fragment/Activity <──Diff── ViewModel <──Snapshot── Rust Core
  │
  ▼
RecyclerView.Adapter.submitList / notifyItemRangeChanged
```

**Key constraints (identical to iOS):**

- **ViewModel performs zero business logic**: no parsing, no computation, no caching, no retry
- **ViewModel does exactly two things**: (1) forward user actions to Rust (2) diff Rust-pushed snapshots and trigger UI refresh
- **Fragment / Activity does exactly two things**: (1) convert user events to Commands (2) map snapshots to Views

### 4.4 RecyclerView Component Selection

| Component | Choice | Rationale |
|---|---|---|
| List foundation | RecyclerView 1.4+ | Stable, high performance, no Compose dependency |
| Pagination | Paging 3 | Interfaces with Rust pagination snapshots, built-in DiffUtil |
| List diffing | AsyncListDiffer | Auto diff, main-thread safe |
| Multi-type | ConcatAdapter | Topic detail: header + posts + footer |
| Pull-to-refresh | SwipeRefreshLayout | Simple, reliable |
| Animation | DefaultItemAnimator | Adequate, not over-customized |
| ViewHolder | Custom View preferred | Less XML inflate, better performance |

### 4.5 Image Pipeline

```
Rust fire-image                      Android Platform
  │                                    │
  ├─ Decode (JPEG/PNG/WebP/AVIF)       │
  ├─ Scale to target dimensions        │
  ├─ Convert → ARGB_8888 pixel buffer  │
  ├─ Memory LRU cache                  │
  ├─ Disk cache                        │
  │                                    │
  └─ Return RawPixelBuffer ──────────> Coil (retained)
                                       │
                                       ├─ Phase 1: Coil full pipeline (current)
                                       │   Coil scheduling + Coil decoding + Coil caching
                                       │
                                       ├─ Phase 2: Coil scheduling + Rust decoding (hybrid)
                                       │   Custom Interceptor delegates to Rust
                                       │   Coil manages request queue, priority, prefetch
                                       │
                                       └─ Phase 3: Rust full pipeline (ultimate)
                                           Rust scheduling + Rust decoding + Rust caching
                                           Coil degrades to ImageView placeholder / transition
```

**Reasons to retain Coil (symmetric with Nuke on iOS):**

- Request scheduling: priority, cancellation, deduplication
- Transition animations: crossfade, placeholder switching
- Prefetch: viewport-predictive loading
- Smooth migration: custom `Interceptor` delegates decode to Rust

### 4.6 Rich Text Rendering Pipeline

```
Rust fire-rich-text                   Android Platform
  │                                    │
  ├─ HTML → AST                        │
  ├─ AST → RenderDocument              │
  │                                    │
  └─ Return RenderDocumentState ─────> FireRenderBlockBuilder
                                       │
                                       ├─ shared blocks → FireRichTextNode
                                       ├─ FireSpannableBuilder
                                       ├─ FireRichTextView / ImageView
                                       └─ no platform-owned cooked fallback
```

### 4.7 Design Tokens

1:1 counterpart to iOS `FireDesignTokens`:

```kotlin
object FireDesignTokens {
    // Spacing
    const val SPACING_XS = 4.dp
    const val SPACING_SM = 8.dp
    const val SPACING_MD = 12.dp
    const val SPACING_LG = 16.dp
    const val SPACING_XL = 24.dp

    // Font size
    const val FONT_TITLE = 17.sp
    const val FONT_BODY = 15.sp
    const val FONT_CAPTION = 13.sp
    const val FONT_MICRO = 11.sp

    // Corner radius
    const val RADIUS_SM = 6.dp
    const val RADIUS_MD = 10.dp
    const val RADIUS_LG = 14.dp

    // Colors (1:1 with iOS FireDesignTokens)
    val colorPrimary: Int get() = /* ... */
    val colorBackground: Int get() = /* ... */
    val colorTextPrimary: Int get() = /* ... */
    // ... full palette per Section 5.2
}
```

### 4.8 iOS vs Android Component Mapping

| Function | iOS | Android |
|---|---|---|
| List container | ASCollectionNode (Texture) | RecyclerView |
| List cell | ASCellNode | ViewHolder + Custom View |
| Diff update | performBatchUpdates | AsyncListDiffer |
| Pagination | Custom PaginationCoordinator | Paging 3 |
| Image display | ASNetworkImageNode / UIImageView | ImageView + Coil Target |
| Rich text rendering | ASTextNode tree | TextView + Spannable |
| Code block | ASImageNode (snapshot render) | HorizontalScrollView + TextView |
| Navigation | UINavigationController | Navigation Component |
| Pull-to-refresh | UIRefreshControl | SwipeRefreshLayout |
| Bottom sheet | UIViewController (modal) | BottomSheetDialogFragment |
| Design tokens | FireDesignTokens (Swift) | FireDesignTokens (Kotlin) |
| Rust bridge | FireSessionStore (Actor) | FireSessionStore (Actor-ized) |
| Event bus | Combine | Kotlin Flow |

---

## 5. Cross-Platform Contracts

### 5.1 Design System

Cross-platform UI consistency is guaranteed through **design tokens + component contracts**, not shared UI code.

#### Three-Layer Contract

```
Layer 1: Design Tokens (numeric-level consistency)
  Spacing, font size, corner radius, color, animation curve, shadow parameters
  iOS: FireDesignTokens.swift
  Android: FireDesignTokens.kt

Layer 2: Component Contract (component-level consistency)
  Each component defines: input data, visual specification, interaction behavior
  Each platform implements natively, but external interface and visual output are strictly aligned

Layer 3: Screen Contract (screen-level consistency)
  Each screen defines: component composition, layout structure, navigation flow
  Both platforms mirror screen structure; users have muscle-memory across platforms
```

#### Component Contract Examples

| Component | Contract Definition | iOS Implementation | Android Implementation |
|---|---|---|---|
| TopicRow | Avatar(32pt) + Title(17sp/bold) + Excerpt(13sp/2-line ellipsis) + Tag flow + Metadata row | ASCellNode | Custom View + ViewHolder |
| PostCell | User info row + RenderBlock content + Action bar (like/reply/share) | ASCellNode (Texture) | Custom View + ViewHolder |
| AvatarView | Circle / rounded-square, monogram fallback | ASDisplayNode | Custom View |
| RichTextBlock | Text/link/image/code/quote nesting | ASTextNode tree | TextView + Spannable |
| ReactionChip | Emoji + count, selected state highlight | ASDisplayNode | Chip / Custom View |
| Composer | Bottom sheet, toolbar + edit area + send button | UIViewController modal | BottomSheetDialogFragment |

### 5.2 Color Palette Contract

```
Semantic Name             Light          Dark           iOS UIColor              Android Int
───────────────────────────────────────────────────────────────────────────────────────────────
backgroundPrimary        #FFFFFF        #1C1C1E        colorBackgroundPrimary   colorBackgroundPrimary
backgroundSecondary      #F2F2F7        #2C2C2E        colorBackgroundSecondary colorBackgroundSecondary
textPrimary              #000000        #FFFFFF        colorTextPrimary         colorTextPrimary
textSecondary            #8E8E93        #8E8E93        colorTextSecondary       colorTextSecondary
accentPrimary            #007AFF        #007AFF        colorAccentPrimary       colorAccentPrimary
accentDestructive        #FF3B30        #FF3B30        colorAccentDestructive   colorAccentDestructive
divider                  #C6C6C8        #38383A        colorDivider             colorDivider
reactionActive           #007AFF        #0A84FF        colorReactionActive      colorReactionActive
linkColor                #007AFF        #0A84FF        colorLink                colorLink
codeBackground           #F0F0F0        #2A2A2A        colorCodeBackground      colorCodeBackground
quoteBorder              #007AFF        #0A84FF        colorQuoteBorder         colorQuoteBorder
spoilerOverlay           #E0E0E0        #3A3A3A        colorSpoilerOverlay      colorSpoilerOverlay
```

Light/dark mode driven by platform system settings. Semantic color names are strictly aligned across platforms.

### 5.3 Animation Contract

| Interaction | Curve | Duration | iOS | Android |
|---|---|---|---|---|
| Page push | ease-in-out | 350ms | UIView.animate | Fragment transition |
| Page pop | ease-out | 300ms | UIView.animate | Fragment transition |
| Like animation | spring(damping:0.6) | 400ms | CASpringAnimation | SpringAnimation |
| List refresh | ease-out | 250ms | performBatchUpdates | DefaultItemAnimator |
| Bottom sheet | spring(damping:0.8) | 350ms | UIViewControllerTransitioningDelegate | BottomSheetBehavior |
| Image viewer | crossfade | 200ms | Nuke transition | Coil transition |

---

## 6. Rust ↔ Platform Responsibility Boundary

### 6.1 Rust Exclusive (Platform Must Not Touch)

| Responsibility | Description |
|---|---|
| Networking | All HTTP calls via openwire; zero platform networking code |
| Session management | Cookie / Bootstrap / CSRF state machine entirely in Rust |
| Database | SQLite read/write entirely in Rust; platforms do not access directly |
| Rich text parsing | HTML → AST → RenderBlock entirely in Rust |
| Image decoding | Download / decode / scale / format conversion entirely in Rust |
| Cache policy | Memory / disk cache logic entirely in Rust |
| Pagination logic | When to load more, how to merge data — Rust decides |
| Retry / backoff | Network retry, session recovery, rate-limit backoff entirely in Rust |
| MessageBus | Long-polling, subscription management, channel routing entirely in Rust |
| Logging | mars-xlog integration entirely in Rust |
| Search | Query construction, result parsing entirely in Rust |
| Write operations | Post / reply / like / vote / bookmark / flag entirely in Rust |

### 6.2 Platform Exclusive (Rust Must Not Touch)

| Responsibility | Description |
|---|---|
| WebView login | WKWebView / WebView renders login page |
| Interactive auth browser | Platform can render explicit login/manual remediation pages, but request-failure recovery does not auto-launch them |
| Cookie extraction | Extract from platform WebView CookieStore, pass into Rust |
| UI rendering | All pixel drawing, layout computation |
| User interaction | Tap / swipe / long-press / input events |
| Push notifications | APNs / FCM registration and reception |
| Keychain / Keystore | Platform secure storage |
| File system paths | Provide workspace path to Rust |
| Photo library / camera | Image selection, then pass to Rust for upload |

### 6.3 Shared Boundary (Data Flows Through, Logic Does Not Share)

| Data | Direction | Description |
|---|---|---|
| RawPixelBuffer | Rust → Platform | Decoded image result; platform converts to CGImage / Bitmap |
| RenderBlock tree | Rust → Platform | Rich text render instructions; platform converts to View / Node tree |
| StateSnapshot | Rust → Platform | Immutable state snapshot; platform diffs and updates UI |
| Command | Platform → Rust | User action (like, reply, page turn, etc.) |
| PlatformCookie | Platform → Rust | Cookie extracted from WebView |
| Event | Rust → Platform | MessageBus event, state change notification |

---

## 7. UniFFI Boundary Layer

### 7.1 Design Principles

The UniFFI layer is a **pure pipe**. It does exactly three things:

1. **Type mapping**: Rust types ↔ Platform types, zero business logic
2. **Panic safety**: `catch_unwind`, poison flag, error mapping
3. **Async dispatch**: Rust tokio ↔ Platform main-thread callback

### 7.2 Handle Structure

```
FireAppCore
  ├── .session()       → FireSessionHandle
  ├── .topics()        → FireTopicsHandle
  ├── .user()          → FireUserHandle
  ├── .search()        → FireSearchHandle
  ├── .messagebus()    → FireMessageBusHandle
  ├── .notifications() → FireNotificationsHandle
  ├── .image()         → FireImageHandle              ← NEW
  └── .diagnostics()   → FireDiagnosticsHandle
```

### 7.3 FireImageHandle API (NEW)

```rust
impl FireImageHandle {
    fn request_image(
        &self,
        url: String,
        target_width: u32,
        target_height: u32,
        cache_policy: ImageCachePolicy,
    ) -> Result<DecodedImageState>;

    fn prefetch_images(&self, urls: Vec<String>);

    fn clear_memory_cache(&self);

    fn image_metadata(&self, url: String) -> Result<ImageMetadataState>;
}

struct DecodedImageState {
    width: u32,
    height: u32,
    pixel_buffer: Vec<u8>,
    stride: u32,
    format: ImagePixelFormatState,
}

struct ImageMetadataState {
    width: u32,
    height: u32,
    format: String,
    file_size: u64,
    is_animated: bool,
}

enum ImagePixelFormatState { Bgra, Argb8888 }

enum ImageCachePolicyState { MemoryOnly, DiskFirst, NetworkFirst }
```

Platforms request their preferred pixel format via `ImagePixelFormatState`:
- iOS: `Bgra` (native CGImage pixel format)
- Android: `Argb8888` (native Bitmap.Config.ARGB_8888)

The Rust `fire-image` crate transcodes to the requested format during decode so platforms can copy pixels directly without format conversion.

### 7.4 RenderBlock FFI Types (NEW)

```rust
enum RenderBlockKindState {
    Document,
    Paragraph,
    Heading { level: u8 },
    Text { content: String, style: TextStyleState },
    Image { url: String, alt: String, width: u32, height: u32 },
    CodeBlock { language: String, code: String },
    InlineCode { code: String },
    Blockquote,
    OrderedList { start: u32 },
    UnorderedList,
    ListItem { index: u32 },
    Link { url: String, title: String },
    Bold,
    Italic,
    Strikethrough,
    Spoiler,
    Details { summary: String },
    Divider,
    Table { column_count: u32 },
    TableRow,
    TableCell { alignment: CellAlignmentState },
    Emoji { name: String, url: String },
    Mention { username: String, url: String },
    Hashtag { tag: String, url: String },
    Onebox { url: String, title: String, description: String, image_url: String },
    Iframe { url: String, title: String },
    Attachment { url: String, filename: String, file_size: u64 },
    Unknown,
}

struct RenderBlockState {
    kind: RenderBlockKindState,
    children: Vec<RenderBlockState>,
    metadata: HashMap<String, String>,
}

struct TextStyleState {
    bold: bool,
    italic: bool,
    strikethrough: bool,
    code: bool,
    link_url: Option<String>,
    font_size: u8,
    color: Option<String>,
}

enum CellAlignmentState { Left, Center, Right }
```

### 7.5 Enhanced Rich Text FFI API

```rust
impl fire_uniffi {
    // Parser / AST inspection entry only; native topic body rendering consumes
    // TopicPostState.render_document and must not synthesize a RenderDocument
    // from cooked HTML on the platform side.
    fn parse_cooked_html(html: String) -> CookedHtmlDocumentState;
    fn render_cooked_html(html: String, base_url: String) -> RenderDocumentState;
    fn collect_images_from_render_document(document: RenderDocumentState) -> Vec<RenderImageAttachmentState>;
    fn plain_text_from_render_document(document: RenderDocumentState) -> String;
}
```

### 7.6 StateObserver Callback Interface (NEW)

```rust
trait StateObserver: Send + Sync {
    fn on_session_snapshot(&self, snapshot: SessionSnapshotState);
    fn on_topic_list_snapshot(&self, snapshot: TopicListState);
    fn on_notification_center_snapshot(&self, snapshot: NotificationCenterState);
}
```

Platform implements `StateObserver`. Rust proactively pushes snapshots on the implemented snapshot boundaries; explicit page/load/mutation commands remain unchanged. The registry debounces same-domain updates and isolates callback failures so one platform-side observer error does not cascade across domains.

### 7.7 Data Flow Comparison

```
Current (platform polling):
  Platform Timer/Combine ──> Store.buildSnapshot() ──> Rust FFI (sync fetch) ──> diff ──> UI

Target (Rust push):
  Rust state change ──> StateObserver.on_*_snapshot() ──> Platform diff ──> UI
```

Advantages:
- Eliminates platform-side polling overhead
- Rust precisely controls push frequency (debounce / throttle)
- Platform code is simpler: only implement callback + diff

---

## 8. Migration Phases

### Phase 0: Infrastructure (1-2 weeks)

- Create `fire-image` crate skeleton
- Create `fire-rich-text` crate skeleton (extracted from fire-core)
- Define `RenderBlock` FFI types in `fire-models`
- Define `StateObserver` callback interface in `fire-uniffi-types`

### Phase 1: Unified Rich Text (2-3 weeks)

- `fire-rich-text`: implement AST → RenderBlock conversion
- iOS: `FireRenderBlockNodeBuilder` maps RenderBlock to Texture nodes
- Android: `FireRenderBlockBuilder` maps RenderBlock to View tree
- Both platforms validate visual consistency side-by-side

### Phase 2: Image Pipeline (3-4 weeks)

- `fire-image`: implement URL parsing / download / decode / scale / cache
- iOS: custom Nuke `ImageDecoder` delegates to Rust
- Android: custom Coil `Interceptor` delegates to Rust
- Progressive migration: avatars first, then post images

### Phase 3: State Push (2-3 weeks)

- Implement `StateObserver` callback
- Rust-side debounce / throttle for push
- iOS Store switches from polling to receiving pushes
- Android ViewModel switches from polling to receiving pushes

### Phase 4: SwiftUI Elimination (4-6 weeks)

- Home topic list → Texture `ASCollectionNode`
- Notifications / Search → Texture `ASCollectionNode`
- Profile / Bookmarks / Messages → UIKit
- Composer → UIKit
- SwiftUI only retains `@main` shell

### Phase 5: Android Alignment (3-4 weeks)

- Custom Views replace XML layouts
- Paging 3 interfaces with Rust pagination snapshots
- Design tokens fully implemented
- Side-by-side visual consistency validation with iOS
