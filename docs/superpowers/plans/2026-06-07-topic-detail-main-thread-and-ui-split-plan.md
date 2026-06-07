# Topic Detail Main-Thread and UI Split Optimization Plan

> 日期: 2026-06-07
> 状态: Plan
> 范围: iOS topic detail 主线程卡顿、poll option 同步解析、topic tree FFI 载荷瘦身、Android 冷启动 UI 线程初始化、详情页状态拆分

## Goal

解决 review 指出的四类性能风险，并把详情页从“单个大状态刷新整页”推进到“按职责拆分状态域、各自刷新”的结构：

- iOS 不在 `@MainActor` 上比较完整 `TopicDetailState`
- iOS cell / layout key 路径不再同步 HTML 解析 poll option 标题
- 双端 topic detail 不再把完整 post 在 FFI 边界来回传递多次
- Android 首次 `FireSessionStore` / `FireAppCore` 初始化不阻塞 UI 线程
- iOS 详情页拆成 feed、chrome、composer、sidecar、interaction 几个刷新域，避免输入框、toolbar、sidecar 状态触发整页 feed diff

核心原则：不是简单把所有逻辑塞进后台线程，而是先减少主路径要做的工作，再把仍然昂贵、纯计算的派生步骤放到后台。主线程只保留状态发布、UIKit / Texture apply、导航和用户交互收口。

## Direct Answers

### 主线程上的内容是否可以迁移到异步线程

可以，但要分层迁移：

- 必须留在主线程 / MainActor：
  - `@Published` 状态写入
  - UIKit / Texture node apply
  - navigation item、toolbar、quick reply bar 更新
  - visible cell in-place 更新
  - 生命周期和手势事件收口
- 应迁移到后台或 Rust：
  - `TopicDetailState` 变更判断与 signature 生成
  - tree presentation 构建与 row metadata 生成
  - rich text render cache / attributed string 预计算
  - poll option HTML -> plain text
  - snapshot item list 的纯数据构建
  - Android `FireSessionStore` / `FireAppCore` 首次构造

注意：单纯把 `topicDetails[topicId] != detail` 放到 `Task.detached` 不是最优解。它仍然需要复制完整 FFI 大对象，也会制造取消和乱序 apply 问题。更优方案是让 Rust 或后台构建阶段产出轻量 revision / signature，MainActor 只比较 token。

### UI 展示部分是否可以拆分

可以，而且当前代码已经有可利用的边界：

- `FireTopicDetailFeedController`
- `FireTopicDetailPaginationCoordinator`
- `FireTopicDetailVisibilityCoordinator`
- `FireTopicDetailToolbarCoordinator`
- `FireTopicQuickReplyBarNode`
- `FireTopicDetailModalRouter`

当前问题不是完全没有拆组件，而是状态刷新仍然集中在 `FireTopicDetailStore` 和 `FireTopicDetailViewController.buildAndApplySnapshot()`。下一步应拆状态域，而不是重写 UI 层：

- feed state: 原帖、回复、layout、render cache、pagination
- chrome state: toolbar、bookmark、notification、topic vote、share URL
- composer state: draft、target、validation、submitting
- sidecar state: AI summary、presence、timings
- interaction state: mutating post IDs、expanded text IDs、reply thread expansion

## Current Evidence

### iOS deep compare on MainActor

`native/ios-app/App/Stores/FireTopicDetailStore.swift` 是 `@MainActor` store。当前 `setTopicDetail` 用完整对象比较：

```swift
let changed = topicDetails[topicId] != detail
```

`TopicDetailState` 包含 `postStream.posts`，每个 `TopicPostState` 又包含 `cooked` 和 `renderDocument`。大帖刷新、MessageBus refresh、返回相同数据或差异靠后时，这个比较会在主线程走深比较。

### iOS render cache 已部分后台化，但 poll title 仍在 cell/layout 路径

`FireTopicDetailStore.scheduleTopicRenderCacheUpdate` / `buildTopicDetailRenderUpdate` 已用 `Task.detached` 构建 `FireTopicPresentation.detailRenderCache(...)`，这是正确方向。

但 `FirePostPollRenderModel.models(from:)` 仍会在 poll option cache miss 时调用：

```swift
FireRichTextParser.parse(html: html, baseURLString: "")
```

该 parser 会同步调用 `renderCookedHtml(...)` FFI。调用点包括：

- cell configure: `FirePostCellNode`
- layout precompute: `FireTopicDetailFeedController.prepareLayoutsIfNeeded`
- layout key: `FireTopicDetailFeedController.makeLayoutKey`

所以 poll-bearing posts 仍可能在滚动和 layout key 构建路径阻塞。

### FFI tree payload 当前重复带完整 post

当前 source snapshot:

```rust
TopicDetailSourceSnapshotState {
  body: TopicBodyState,
  loaded_posts: Vec<TopicPostState>,
  ...
}
```

当前 tree query 又把完整 post 传回 Rust：

```rust
TopicTreePresentationQueryState {
  body_post: TopicPostState,
  raw_stream_ids: Vec<u64>,
  loaded_posts: Vec<TopicPostState>,
  focused_post_number: Option<u32>,
}
```

当前 tree result 再把完整 post 带回平台：

```rust
TopicTreeRowState {
  post: TopicPostState,
  ...
}
```

因为 `TopicPostState` 包含 `cooked` 和 `render_document`，这会造成大帖 FFI 重复序列化和重复传输。

### Android first store creation is synchronous at the UI call site

`PreheatGateFragment.awaitPreloadedData()` 在启动页面先执行：

```kotlin
val store = FireSessionStoreRepository.get(requireContext())
```

随后才进入 coroutine。`FireSessionStoreRepository.get()` 会同步构造 `FireSessionStore`，而 `FireSessionStore.init` 里创建 `FireAppCore`、注册 observer、解析 session path。这些 IO / Rust 初始化工作应从 UI 线程移走。

### iOS page state already has coarse revision but not enough state-domain isolation

`FireTopicDetailViewController` 已订阅：

- `topicCollectionRevisions` -> `buildAndApplySnapshot()`
- `topicChromeRevisions` -> `buildAndApplyChromeState()`

但 controller-local 事件仍有过度刷新：

- quick reply draft 每次变化会调用 `buildAndApplySnapshot()`
- composer target / validation / submitting 和 feed snapshot 混在 `FireTopicDetailPageState`
- `FireTopicDetailSnapshotAssembler` 标注 `@MainActor`，纯 snapshot item list 构建无法后台化

## Non-Goals

- 不重引入 SwiftUI post row fallback。
- 不把 topic detail 主阅读面改成 host-managed window / `getPostsByNumber(...)`。
- 不增加 parallel rendering path。
- 不用 tree row / root row 反向决定网络分页边界。
- 不把 AI summary、presence、timings 塞进主详情载荷。

## Target Architecture

### Rust / UniFFI

新增或调整为一个 combined + slim contract：

```text
fetch_topic_detail_page(query)
  -> TopicDetailPageState {
       source_snapshot,
       tree_presentation
     }

load_more_topic_posts(cursor)
  -> TopicLoadMoreOutcomeState {
       source_snapshot,
       tree_presentation,
       chained_batches,
       chained_posts,
       stop_reason
     }

TopicTreePresentationState {
  original_post_id,
  reply_rows: Vec<TopicTreeRowMetaState>,
  total_loaded_post_count,
  visible_root_post_numbers,
  gained_new_root_progress
}

TopicTreeRowMetaState {
  post_id,
  post_number,
  root_post_number,
  parent_post_number,
  depth,
  preorder_index,
  has_children,
  descendant_count,
  sibling_index,
  is_last_sibling
}
```

Full post payload only appears in `source_snapshot.body.post` and `source_snapshot.loaded_posts`. Tree presentation references posts by id / post number only.

### iOS Store / Controller

Split state and refresh domains:

```text
FireTopicDetailStore
  source state:
    sourceSnapshots
    treePresentations
    postLookups
    detailTokens
  feed state:
    renderCaches
    renderStates
    windowStates
    collectionRevisions
  chrome state:
    toolbar / bookmark / notification revisions
  sidecar state:
    aiSummary
    presence
    timings
  interaction state:
    mutatingPostIDs
    loadingReplyContextIDs
```

Controller should apply:

- feed updates only when feed token changes
- chrome updates only when toolbar token changes
- quick reply bar updates only when composer token changes
- visible post node updates only when in-place interaction token changes

### Android Startup

Change first initialization to a suspend IO path:

```kotlin
suspend fun FireSessionStoreRepository.get(context): FireSessionStore =
    withContext(Dispatchers.IO) { getOrCreateBlocking(context.applicationContext) }
```

`PreheatGateFragment` should enter `lifecycleScope.launch` before calling `get(...)`. Other UI call sites should also use the suspend path or receive an already initialized store.

## Implementation Plan

### Phase 0: Baseline instrumentation

Files:

- Modify: `native/ios-app/App/Stores/FireTopicDetailStore.swift`
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/startup/PreheatGateFragment.kt`
- Optional Modify: `rust/crates/fire-core/src/core/topics.rs`

Steps:

- [ ] Add lightweight signposts / log fields for topic detail apply:
  - source fetch duration
  - tree presentation duration
  - render cache duration
  - MainActor apply duration
  - collection snapshot item count
  - loaded post count and cooked byte count
- [ ] Add startup timing around Android `FireSessionStoreRepository.get(...)`.
- [ ] Capture before numbers on:
  - large topic initial load
  - MessageBus refresh with identical payload
  - poll-bearing topic scroll
  - Android cold start / deep link first entry

Acceptance:

- Logs identify whether time is spent in fetch, FFI conversion, render cache, snapshot build, or UI apply.
- No behavior changes yet.

### Phase 1: Fix P1 iOS deep compare

Files:

- Modify: `native/ios-app/App/Stores/FireTopicDetailStore.swift`
- Modify: `native/ios-app/App/TopicDetail/Support/FireTopicPresentation.swift`
- Test: `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift`

Steps:

- [ ] Introduce `FireTopicDetailContentToken`.
- [ ] Token fields should cover visible detail semantics without embedding full cooked/render tree:
  - topic id
  - message bus last id
  - header counters and flags
  - bookmark / notification fields
  - `postStream.stream` checksum
  - per post id, post number, updated_at, like count, reaction signature, poll signature, cooked length + stable checksum
  - details permission / participant signature
- [ ] Keep `topicDetailContentTokensByTopicID`.
- [ ] Replace `topicDetails[topicId] != detail` with token comparison.
- [ ] Build token before `MainActor` apply where possible. If token must be computed in Swift, compute in the existing detached render-cache task or a dedicated detached task and apply only latest generation.
- [ ] Keep full `TopicDetailState` assignment only when token changed.
- [ ] Preserve `bumpRevision` behavior exactly.
- [ ] Add tests:
  - identical large detail does not publish / bump collection revision
  - changed late post does publish
  - changed bookmark / notification chrome field updates correct revision
  - token collision-sensitive fields are included

Acceptance:

- No full `TopicDetailState` equality check remains on `@MainActor`.
- Identical refresh does O(1) main-thread comparison.
- Store tests cover no-op and changed refresh.

### Phase 2: Collapse and slim topic tree FFI

Files:

- Modify: `rust/crates/fire-models/src/topic_detail.rs`
- Modify: `rust/crates/fire-core/src/core/topics.rs`
- Modify: `rust/crates/fire-uniffi-topics/src/lib.rs`
- Modify: `rust/crates/fire-uniffi-topics/src/records.rs`
- Modify: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`
- Modify: `native/ios-app/App/Stores/FireTopicDetailStore.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/data/repository/TopicRepository.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`
- Test: `rust/crates/fire-core/tests/network.rs`
- Test: `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift`
- Test: `native/android-app/src/test/.../TopicDetailPostRowsTest.kt` or equivalent

Steps:

- [ ] Add `TopicTreeRowMeta` / `TopicTreeRowMetaState` without full `TopicPost`.
- [ ] Add `TopicDetailPage` / `TopicDetailPageState` combined result:
  - `source_snapshot`
  - `tree_presentation`
- [ ] Add Rust core method that builds source snapshot and tree presentation in one call from the same internal source session.
- [ ] Keep `load_more_topic_posts` combined, but make returned `tree_presentation.reply_rows` slim.
- [ ] Remove platform path that sends `bodyPost` and `loadedPosts` back to Rust just to build the tree.
- [ ] iOS rebuild:
  - keep `sourceSnapshots[topicId]`
  - keep `treePresentations[topicId]`
  - derive `postLookup` from `sourceSnapshot.body.post + sourceSnapshot.loadedPosts`
  - synthesize `TopicDetailState` from source + slim tree metadata only when compatibility with existing UI code still needs it
- [ ] Android rebuild:
  - `PostRow` uses row metadata + post lookup
  - `_detail.postStream.posts` comes from source posts only
  - mutation patch updates source posts and post lookup, not duplicated tree row post copies
- [ ] Delete or deprecate old `buildTopicTreePresentation(query: TopicTreePresentationQueryState)` platform wrapper after all call sites move.

Acceptance:

- Main detail flow crosses FFI once for source + tree on initial refresh.
- Tree row FFI no longer carries `TopicPostState`.
- `TopicPostState.renderDocument` is serialized once per loaded post per response, not again through tree rows.
- Both platforms render the same row order/depth as before.

### Phase 3: Move poll option title parsing out of iOS cell/layout path

Files:

- Modify: `rust/crates/fire-models/src/topic_detail.rs`
- Modify: `rust/crates/fire-uniffi-topics/src/records.rs`
- Modify: `native/ios-app/App/ListKit/TopicDetail/FirePostPollRenderer.swift`
- Modify: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/PostViewHolder.kt` if Android consumes option title directly
- Test: `cargo test -p fire-models -p fire-uniffi-topics`
- Test: iOS unit test for poll model title

Steps:

- [ ] Add `plain_text` or `title` to `PollOption` / `PollOptionState`.
- [ ] Populate it in Rust using the existing shared plain-text rich text path.
- [ ] Update iOS `FirePostPollRenderModel.models(from:)` to use `option.plainText` and fallback to `option.id`.
- [ ] Remove `FirePostPollPlainTextCache` and `optionTitle(fromHTML:)` from the cell path.
- [ ] Ensure `FireTopicDetailFeedController.makeLayoutKey` uses already materialized poll signatures only.
- [ ] Audit all iOS references to `FireRichTextParser.parse(html:)` and confirm none are reachable from cell configure or layout key cache miss.

Acceptance:

- No `renderCookedHtml(...)` FFI can be triggered by poll model construction.
- Poll-bearing rows can configure and compute layout keys without synchronous HTML parsing.

### Phase 4: Move Android core initialization off UI thread

Files:

- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStoreRepository.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/startup/PreheatGateFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/MainActivity.kt`
- Modify: other `FireSessionStoreRepository.get(...)` UI call sites found by `rg`
- Test: Android unit tests if repository behavior is testable

Steps:

- [ ] Replace sync public `get(context)` with a suspend `get(context)` or add a clearly named `getOrCreate(context)` suspend method.
- [ ] Keep a private blocking `getOrCreateBlocking(applicationContext)` behind `withContext(Dispatchers.IO)`.
- [ ] Preserve singleton locking and Cloudflare challenge handler registration.
- [ ] Update `PreheatGateFragment.awaitPreloadedData()`:
  - enter `lifecycleScope.launch` first
  - call repository from IO
  - then call `prepareStartupSession`, `awaitPreloadedData`, and login probe
- [ ] Update other UI call sites so none construct `FireSessionStore` before entering a coroutine / IO context.
- [ ] Do not use `runBlocking` on UI thread.

Acceptance:

- First `FireAppCore` construction cannot happen on the Android main thread.
- Cold start / deep link first entry keeps the UI responsive while preheat runs.

### Phase 5: Split iOS topic detail state refresh domains

Files:

- Modify: `native/ios-app/App/TopicDetail/State/FireTopicDetailPageState.swift`
- Modify: `native/ios-app/App/TopicDetail/State/FireTopicDetailSnapshotAssembler.swift`
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`
- Modify: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedModels.swift`
- Modify: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedUpdatePipeline.swift`
- Modify: `native/ios-app/App/Stores/FireTopicDetailStore.swift`
- Test: `native/ios-app/Tests/Unit/FireTopicDetailRuntimeTests.swift`

Steps:

- [ ] Split `FireTopicDetailPageState` into:
  - `FireTopicDetailFeedState`
  - `FireTopicDetailChromeState`
  - `FireTopicDetailComposerState`
  - `FireTopicDetailSidecarState`
  - `FireTopicDetailInteractionState`
- [ ] Split invalidation tokens:
  - feed token: post/tree/render/layout/pagination only
  - chrome token: title/share/bookmark/notification/topic vote only
  - composer token: draft/target/validation/submitting only
  - sidecar token: AI summary/presence/timing display only
  - visible-node token: mutating/reaction/loading reply context/expanded text only
- [ ] Change quick reply draft updates to apply only composer state:
  - no feed snapshot rebuild on every keystroke
  - no collection diff on validation-only changes
- [ ] Change toolbar-only changes to call only `toolbarCoordinator.apply(...)`.
- [ ] Change AI summary reload failure/loading to update only the summary item if present, not rebuild unrelated post items.
- [ ] Extract a pure `FireTopicDetailSnapshotInput: Sendable` for feed item construction.
- [ ] Move pure feed item list construction off `@MainActor` when inputs are ready and attach action callbacks only at apply time.
- [ ] Keep Texture / collection update application on MainActor.
- [ ] Add tests asserting:
  - composer draft token change does not change feed invalidation token
  - chrome token change does not change feed items
  - expanded text affects only the relevant post item content token
  - mutation state can use visible in-place update path

Acceptance:

- Typing in quick reply does not call `feedUpdatePipeline.apply(...)`.
- Toolbar changes do not diff post rows.
- Feed snapshot build becomes pure and eligible for background execution.
- UI behavior remains unchanged.

### Phase 6: Verification and regression gates

Rust:

```bash
cargo fmt --all --check
cargo test -p fire-models -p fire-core -p fire-uniffi-topics --all-targets
```

iOS:

```bash
xcodegen generate --spec native/ios-app/project.yml
FIRE_SKIP_UNIFFI_BINDGEN=1 xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire-Local-Unit -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Android:

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
export ANDROID_HOME=/Users/zhangfan/Library/Android/sdk
export ANDROID_SDK_ROOT=/Users/zhangfan/Library/Android/sdk
cd native/android-app
./gradlew testDebugUnitTest assembleDebug
```

Runtime checks:

- iOS large topic initial load: no visible main-thread freeze during identical refresh.
- iOS poll-bearing topic scroll: no synchronous `renderCookedHtml` from cell/layout stack.
- iOS quick reply typing: no feed collection diff.
- iOS MessageBus identical refresh during/after scroll: no full detail deep compare.
- Android cold start: first `FireSessionStore` construction happens on IO dispatcher.

## Suggested Commit Split

1. `perf(ios): replace topic detail deep compare with content tokens`
2. `refactor(topics): slim topic tree presentation over uniffi`
3. `perf(ios): precompute poll option titles in rust payloads`
4. `perf(android): initialize fire session store off main thread`
5. `refactor(ios): split topic detail refresh domains`
6. `docs: document topic detail performance boundaries`

## Risk Notes

- Token comparison must include every visible field that can affect UI. Missing fields would create stale UI.
- Slim tree rows require careful post lookup rebuild on both platforms. Mutation updates must patch source posts, not stale row copies.
- Moving snapshot build off-main requires separating pure data from UIKit objects and callbacks.
- Android repository API changes may affect multiple call sites; update all `FireSessionStoreRepository.get(...)` consumers in one commit.
- UniFFI model changes require regenerating bindings and then regenerating the iOS Xcode project if source lists change.

## Documentation Follow-Up

After implementation, update:

- `docs/knowledge/api/03-topics.md`: source snapshot + slim tree presentation contract
- `docs/architecture/2026-06-05-rich-text-and-state-observer-design.md`: poll option plain text and topic detail observer boundary notes
- `docs/superpowers/plans/2026-06-06-topic-detail-api-consolidation.md`: mark combined/slim FFI decisions as the current direction or supersede stale sections

Documentation should be synchronized after code lands, not before, because code remains the source of truth.
