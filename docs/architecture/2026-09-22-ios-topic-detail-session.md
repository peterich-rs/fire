# iOS 话题详情：Rust 会话唯一控制面

| 项 | 值 |
| --- | --- |
| 日期 | 2026-09-22 |
| 状态 | 已落地（Rust 会话 + iOS/Android 单源；旧分页 RPC 已删） |
| 范围 | 话题详情模块。Home / 搜索 / 通知 / 聊天不改架构 |
| 通道 | 只动 `fire-uniffi-topics` + `fire-core` 话题模块。不合并 session / chat / search / notification |
| 参考 | KycNative 模块内对象生命周期与 ABI 投影。不把 Fire 收成一个 `FaceVerifySession` 式应用对象 |

## Feasibility Assessment

可行，且应做。源游标、树、未读根自动延伸已经在 Rust：

- `FireTopicDetailSourceRuntime` / 私有 `TopicDetailSourceSession`：`rust/crates/fire-core/src/core/topics.rs`
- `FireCore::fetch_topic_detail_source_snapshot`、`fetch_topic_detail_page`、`append_topic_detail_source`、`load_more_topic_posts`、`extend_topic_source_to_unread_root_if_needed`
- 模型 `TopicDetailPage { source_snapshot, tree_presentation }`：`rust/crates/fire-models/src/topic_detail.rs`
- FFI 仍是 RPC 目录：`FireTopicsHandle::{fetch_topic_detail_page, load_more_topic_posts, like_post, create_reply, ...}`（`rust/crates/fire-uniffi-topics/src/lib.rs`）

缺口是 iOS 第二控制面，不是缺协议。`FireTopicDetailStore` 持有 `topicDetails`、`topicSourceSnapshots`、`topicTreePresentations`、`topicPostLookups`、`topicSourceCursorsByTopic`、窗口 / 区间 / hydration task，并自己决定重试、预取、乐观回滚、MessageBus 刷新。这违反 `docs/architecture/fire-native-architecture.md` §1.1 与 §2.4。

不需要新网络栈。CF 挑战与 cookie self-healing 已在 `FireNetworkLayer`（`cloudflare_challenge_handler`、`cookie_self_healing_handler`，注册入口在 `FireSessionHandle`）。话题详情不再在 Swift 里解析 `FireUniFfiError` 决定重试。

Android 早期阶段不改调用点。`TopicRepository.fetchTopicDetailPage` / `loadMoreTopicPosts` 与 `FireSessionStore.fetchTopicDetailPage` 继续打旧 RPC。旧 RPC 只转发 `load_topic_detail_*`，不 `open` 会话，直到两端都迁完再删。

主要风险：iOS 消费面一次切走 `TopicDetailState` / `TopicPostState` / `postLookup`；LoginRequired 的 headless 重登今天只从话题 store 和首页 store 进入。见 Architectural Notes。

## Current Surface Inventory (method-level)

### Rust 已有，会话应吃掉而不是重写

| 位置 | 符号 | 归宿 |
| --- | --- | --- |
| `topics.rs` | `TopicDetailSourceSession` 及 `source_snapshot` / `merge_posts` / `recompute_loaded_state` | 留在会话私有状态。不导出 |
| `topics.rs` | `fetch_topic_detail_source_snapshot` | 会话 `open` / `reload` 的内部步骤 |
| `topics.rs` | `fetch_topic_detail_page` | 同上，含 `extend_topic_source_to_unread_root_if_needed` |
| `topics.rs` | `load_more_topic_posts` / `append_topic_detail_source` | 会话 `load_more` 与可见区预取 |
| `topics.rs` | `build_topic_tree_presentation` | 私有。树不进 UI 快照的源字段 |
| `topics.rs` | `fetch_topic_posts` / `fetch_topic_ai_summary` | 会话内部补洞与摘要 |
| `interactions.rs` | `like_post` / `unlike_post` -> `Option<PostReactionUpdate>`；`toggle_post_reaction`；`create_reply`；`create_boost`；`vote_poll` | 会话命令调用。返回值不穿过 FFI 给 Swift 改帖 |
| `messagebus.rs` | `subscribe_message_bus_channel` / `unsubscribe_message_bus_channel` | 会话在 open/close 自己订阅 |
| `presence.rs` | `bootstrap_topic_reply_presence` / `update_topic_reply_presence` / `topic_reply_presence_state` | 会话内部 |
| `state_observer.rs` | `notify_session` / `notify_topic_list` / `notify_notification_center` | 不扩展。话题详情用会话级 observer |
| `network.rs` | `StaleSessionResponse`（epoch 前进后丢弃响应）；CF `retry_after_cloudflare_challenge` | 会话内重试一次 `force_load`。Swift 不再看见这个错误 |

`TopicDetailSourceQuery` 仍带 `initial_batch_size`、`load_more_batch_size`、`max_auto_batches_per_gesture`、`max_auto_posts_per_gesture`。生产路径改为常量。`tests/network.rs` 用 1/3/10 等非生产批量，见测试节。

常量今天分裂两处，数值已经一致，收到会话旁边：

| 策略 | Swift 现状 | Rust 现状 |
| --- | --- | --- |
| 首批 / 续批 | `topicDetailInitialBatchSize = 40`，`topicDetailLoadMoreBatchSize = 40` | `DEFAULT_TOPIC_INITIAL_BATCH_SIZE` / `DEFAULT_TOPIC_LOAD_MORE_BATCH_SIZE` |
| 自动连批 | Swift 写死 `maxAutoBatchesPerGesture: 3`，`maxAutoPostsPerGesture: 120` | 同名 default |
| 流内预取 | `topicPostPrefetchThreshold = 10`，`topicPostForwardExpansionSize = 60`，`topicPostPageSize = 30`，`topicPostHydrationIterationLimit = 8`，debounce 120ms | 无。在 Swift `handleVisiblePostNumbersChanged` / `expandRequestedRangeIfNeeded` |
| 列表尾预取 | `fireTopicDetailShouldLoadMore` 默认 `trailingThreshold = 5` | 无 |
| 回复上下文 | `replyContextPostBatchSize = 20` | 无 |
| MessageBus 刷新 | `scheduleTopicDetailRefresh` 睡 1.5s；滚动中延期 | 无 |
| presence 心跳 | 30s | `update_topic_reply_presence` 另有服务端节流 |

### FFI 现状

`FireTopicsHandle` 是无生命周期的 RPC。话题详情相关：`fetch_topic_detail_source_snapshot`、`fetch_topic_detail_page`、`load_more_topic_posts`、`fetch_topic_posts`、`fetch_topic_ai_summary`、`create_reply`、`create_boost`、`delete_boost`、`fetch_post`、`fetch_post_replies`、`fetch_post_reply_ids`、`fetch_post_reply_history`、`update_post`、`delete_post`、`recover_post`、`flag_post`、`fetch_post_action_types`、`update_topic`、`report_topic_timings`、`like_post`、`unlike_post`、`toggle_post_reaction`、`fetch_reaction_users`、`accept_solution`、`unaccept_solution`、`vote_poll`、`unvote_poll`、`vote_topic`、`unvote_topic`、`fetch_topic_voters`。

记录在 `fire-uniffi-topics/src/records.rs`。`TopicPostState.presentation` 已是 `Option<Arc<RenderDocumentHandle>>`（`fire-uniffi-types/src/handle.rs`，`checksum()` / `plain_text()` / `segment(i)`）。单元格不得再拿 cooked HTML。

全局 `StateObserver`（`fire-uniffi/src/lib.rs`）只有 `on_session_snapshot`、`on_topic_list_snapshot`、`on_notification_center_snapshot`。`fetch_topic_list` 注释写明分页结果不能广播成权威全表。话题详情禁止塞进这个 observer。

### iOS store：逐方法归类

归类：`删` = 逻辑进 Rust，方法删除。`转` = 保留，函数体变成一行命令转发。`留` = 纯 UI，不进 Rust。store 最终只留「转」和快照持有。

`FireTopicDetailStore.swift`

| 方法 | 类 |
| --- | --- |
| `checksum` | 删。服务端字段的 `layout_checksum` / `interaction_checksum` 由 Rust 算。Swift builder 仍把本地 chrome 折进 layout / in-place token，不把 token 设成 Rust checksum 本身 |
| `bumpTopicCollectionRevision` / `Chrome` / `Sidecar` / `Interaction` | 删。快照带单调 revision |
| `setLoadingTopic` / `setLoadingMoreTopicPosts` / `setLoadMoreTopicPostsError` / `setLoadingTopicAiSummary` | 删 |
| `setMutatingPost` / `setSubmittingReply` / `setLoadingPostReplyContext` / `setPostReplyContextError` | 删。进快照行标志或 composer 段 |
| `setTopicPresenceUsers` / `setPendingScrollTarget` / `updateTopicErrorMessage` / `updateTopicDetailNotice` | 删 |
| `applySession` | 转。只转发两种 readiness，见「三种会话过渡」。`canReadAuthenticatedApi == true` 时直接 return，epoch 变化不在这里清快照。完整登出才 `release` 全部 owner 并清空快照。短暂未登录只取消在途 HTTP |
| `cancelInFlightFetches` | 删。`close` 取消 actor 任务 |
| `handleMessageBusStopped` | 删。bus runtime 通知内部 listener |
| `reset` | 转。`registry.close_all()` |
| `clearTopicDetailAnchor` / `clearTransientAnchor` | 转。`clear_scroll_target` |
| `markScrollTargetSatisfied` | 转。`acknowledge_scroll_target` |
| `pendingScrollTarget` / `isScrollTargetExhausted` / `topicDetail` / `topicRenderState` / `topicPostLookup` / presence 与 AI summary / notice / revision / loading / `hasMoreTopicPosts` / `isSubmittingReply` / `isMutatingPost` 全部 getter | 删。VC 读 `snapshot(for:)` |
| `canStartNextTopicSourcePageLoad` | 删 |
| `mergeReplyContextTreeRows` | 删 |
| `formattedTopicIDs` | 删 |
| `renderStateCoversRowInputs` | 删 |
| `elapsedMilliseconds` | 留在 VC 诊断，从 store 挪走 |
| `snapshotByAppending` / `cookedByteCount` / `hydrateRequestedRange` | 删 |
| `nextDirectionalSearchRange` / `previousDirectionalSearchRange` / `nextForwardSearchRange` | 删。这是滚动锚点找流位置，不是正文搜索。调用点在 `+Load.swift` `nextRequestedRangeForUnresolvedTarget` |
| `performWithTimeout` 及文件末尾 request gate（`start` / `cancel` / `setWorkTask` / `setTimeoutTask` / `finish`） | 删。超时是会话常量 |

`FireTopicDetailStore+Load.swift`

| 方法 | 类 |
| --- | --- |
| `loadTopicDetail` | 转。`open` 或已打开时 `reload` |
| `fetchTopicDetailPagePayload` | 删。含 `performWithCloudflareRecovery`、`StaleSessionResponse` 循环、`attemptReadPathLoginRecovery`、批量参数 |
| `detailContainsPostNumber` | 删 |
| `rememberTopicRecoverySlug` / `bestKnownTopicRecoverySlug` / `topicCloudflareRecoveryURL` | 删。slug 作为 `open` 入参，供首包前的 CF URL；header 到达后以 header.slug 为准。URL 由网络层按现有 foreground 请求构造 |
| `synthesizedTopicDetail` / `prepareTopicDetailPagePayload` | 删。禁止再把 source+tree 合成 `TopicDetailState` |
| `applyTopicDetailPagePayload` | 删。今天第 318 行 `appViewModel.patchHomeTopicCounts(from:)` 改由快照上的窄 patch 触发 |
| `loadNextTopicSourcePage` / `enqueueNextTopicSourcePageLoad` | 删 |
| `loadMoreTopicPostsIfNeeded` | 转。只服务用户点「加载更多」/ 失败 footer 重试。阈值预取删除 |
| `handleVisiblePostNumbersChanged` | 转。`note_visible_posts` |
| `needsAnchoredReload` / `prepareTopicDetail` / `cacheTopicDetail` / `setTopicDetail` / `rebuildTopicDetail` | 删 |
| `buildTopicDetailRenderUpdate` / `applyTopicDetailRenderUpdate` / `scheduleTopicRenderCacheUpdate` / `applyTopicRenderCache` / `applyTopicDetail` | 删。渲染缓存改读 `RenderDocumentHandle` |
| `reloadTopicAiSummary` | 转。`reload_ai_summary` |
| `loadTopicAiSummaryIfNeeded` | 删。`summarizable` 后会话自己拉 |
| `prehydrateAnchoredContextBeforeDisplayIfNeeded` / `expandRequestedRangeIfNeeded` / `hydrateTopicPostsToTargetIfNeeded` / `advanceRequestedRangeTowardPendingScrollTargetIfNeeded` / `loadedPostNumbers` / `applyHydratedTopicPostsIfNeeded` / `hasMissingPostsInRequestedRange` / `refreshTopicWindowState` / `resolvedTopicWindowState` / `resolveRequestedRange` / `clampedRequestedRange` / `streamIndex` / `scrollTargetIsExhausted` / `nextRequestedRangeForUnresolvedTarget` / `initialRequestedRange` / `expandedRequestedRange` / `boundedRequestedRange` | 删 |

`FireTopicDetailStore+Mutations.swift`

| 方法 | 类 |
| --- | --- |
| `submitReply` / `createBoost` / `updatePost` / `deletePost` / `recoverPost` / `flagPost` / `votePoll` / `unvotePoll` | 转。不返回 `TopicPostState` 给调用方改树。`updatePost` 今天返回帖，改为 `async throws`，编辑器预填走 `prepare_edit` |
| `loadPostActionTypesIfNeeded` | 转。`ensure_flag_types`。目录进快照 `flag_types`，store 不再缓存 |
| `loadPostReplyContextIfNeeded` | 转。`load_reply_context` |
| `applyReplyContextRowsIfPossible` / `fetchReplyContextReplies` / `orderedUniquePostIDs` | 删 |
| `performPostManagementMutation` / `refreshTopicDetailAfterMutation` / `refreshTopicDetailPageFromNetwork` | 删 |
| `applyCreatedBoost` / `applyCreatedReply` | 删 |

`FireTopicDetailStore+Presence.swift`

| 方法 | 类 |
| --- | --- |
| `beginTopicDetailLifecycle` | 转。并入 `open` 的 owner token |
| `endTopicDetailLifecycle` | 转。`close`。不再因首页行可见而保留详情（见 Key Decisions） |
| `pruneInactiveTopicDetailState`（两个）/ `retainedTopicDetailIDs` / `evictTopicDetailState` | 删。refcount 替代 |
| `maintainTopicDetailSubscription` | 删。订阅频道与今天 iOS 一致：`/topic/{id}`、`/topic/{id}/reactions`、`/polls/{id}`、`/presence/discourse-presence/reply/{id}`（`FireSessionStore.subscribeTopic*`） |
| `handleMessageBusEvent` | 删。`FireAppViewModel.handleMessageBusEvent` 不再把 `.topicDetail` / `.topicReaction` / `.presence` 转给 topic store。聊天分支不动 |
| `setTopicDetailScrollInteractionActive` | 转。`note_scroll_interaction` |
| `beginTopicReplyPresence` / `endTopicReplyPresence` | 转。`begin_reply_typing` / `end_reply_typing` |
| `scheduleTopicDetailRefresh` / `refreshTopicDetailFromMessageBus` / `refreshTopicPresenceState` / `applyTopicPresenceState` / `activeAnchorPostNumber` | 删 |

`FireTopicDetailStore+Reactions.swift`

| 方法 | 类 |
| --- | --- |
| `setPostLiked` / `togglePostReaction` | 转 |
| `captureReactionSnapshot` / `restoreReactionSnapshot` / `applyOptimisticReactionChange` / `adjustCount` / `applyPostReactionUpdate` | 删 |

### 留在 VC / cell 的 UI 状态（不进 store，不进 Rust）

`expandedPostTextIDs`、`expandedReplyRootPostIDs`、`expandedReactionPickerPostIDs`、composer draft / `composerContext` / `quickReplyError`、`isTopicAiSummaryExpanded`、键盘、搜索高亮、滚动偏移、cell 本地 overflow（`docs/architecture/2026-09-19-ios-topic-detail-local-updates.md`）。三档 Texture 管道留在 Swift。Rust checksum 只覆盖服务端字段。builder 仍把展开、搜索高亮等本地 chrome 折进 layout / in-place token。

### UI 消费点（本设计要改输入，不改管道语义）

| 文件 | 今天读什么 | 之后 |
| --- | --- | --- |
| `FireTopicDetailViewController` `buildCurrentFeedState` / `Chrome` / `Composer` / `Sidecar` / `Interaction` / `PageState` / `buildRuntimeConfiguration` | `TopicDetailState`、`postLookup`、store revision | 快照段 + VC 本地 chrome |
| `FireTopicDetailPageState.swift` | 同上 | 重写成快照视图，不再嵌 `TopicDetailState` |
| `FireTopicDetailFeedModels.swift` | `FireTopicDetailRuntimePostContext.post: TopicPostState` | 行 DTO |
| `FireTopicDetailRuntimeSnapshotBuilder` | detail + renderState + lookup | 快照行 + 本地展开集合 |
| `FireTopicDetailFeedUpdatePipeline` | `invalidationToken` / `postLayoutContentToken` / `postContentToken` | 三档规则不变。Rust checksum 只是 builder 的输入之一。禁止 `contentToken = layout_checksum` |
| `FireTopicDetailPaginationCoordinator` | `fireTopicDetailShouldLoadMore` 用过滤后的 item 下标，默认尾阈值 5 | 协调器只上报 `note_filtered_feed_tail(itemCount, visibleMaxItem)`。比较进 Rust。footer 重试仍 `load_more`。删掉 Swift 里的第二份阈值 |
| `FireTopicDetailVisibilityCoordinator` | 240ms 合并可见楼层号 | 留。只调 `note_visible_posts`。120ms 产品 debounce 进 Rust，240ms 仍是 UI 合并 |
| `Controller/` 下 toolbar / interaction / search / modal | 读 store 帖 | 读快照行。搜索只扫已加载行的 `plain_text()` |
| `FireTopicInteractionService` | 赞/表情/投票走 store；`voteTopic`、书签、通知级别、timings 直接打 session store 再 `refreshTopicDetailAfterMutation` | 话题详情屏幕上的写操作全部走 store 转发。`fetchReactionUsers` / `fetchTopicVoters` 仍是一次性拉取，不进帖树 |
| `FireAppViewModel.submitReply` / `updatePost` | 已转发 store | 保持转发，签名去掉返回帖 |
| `FireRootCoordinator` | 拥有唯一生产 store（约第 95 行） | 仍是唯一 store |

额外 `FireTopicDetailStore(appViewModel:)` 构造（必须改成拿 root store，否则会再开一套会话）：

- `FireAppRouteDestinationView.swift`
- `FirePublicProfileView.swift`
- `FireFollowListViewController.swift`
- `FireProfileActivityTimelineView.swift`
- `FireProfileView.swift`
- 单测里的临时 store 改为注入 snapshot fixture，不拉网

### 首页行补丁（唯一允许碰首页的点）

调用链今天是：

1. `FireTopicDetailStore.applyTopicDetailPagePayload` 与 `+Mutations` 刷新成功后调 `FireAppViewModel.patchHomeTopicCounts(from: TopicDetailState)`（`FireAppViewModel.swift` 约 791 行）
2. `FireHomeFeedStore.patchTopicCounts` -> `patchedTopicRow(_:from:)`（`FireHomeFeedStore.swift` 98–209 行）

公式：帖数 / 回复数 / 浏览 / `lastRead` / `highest` 覆盖；`lastRead == nil` 时保留原 `hasUnreadPosts`；`lastRead >= highest` 时未读与新帖数清零；否则保留原 `unreadPosts` / `newPosts` 且 `hasUnreadPosts = true`。没有从 stream 重算未读。

Rust 没有对应方法。`notify_topic_list` 推的是整表 `TopicListResponse`，不能用于单行。设计只加窄 patch，不改首页分页。

### Android（本阶段只保证能编过）

`TopicDetailViewModel.loadTopicDetail` -> `fetchTopicDetailPagePayload` -> `TopicRepository.fetchTopicDetailPage` -> `FireSessionStore.fetchTopicDetailPage` -> `core.topics().fetchTopicDetailPage`。`loadMorePosts` 同理走 `loadMoreTopicPosts(cursor)`。这些签名在删除 PR 之前保持。

## Design

### 决策

1. 一个话题一个 `TopicDetailSession`。`open` / 命令 / `close`。不是 `FireTopicsHandle` 上再堆 HTTP。
2. Registry 挂在 `FireCore`，key = topic id。`open` 按 owner token 引用计数，同一 token 再 open 是替换 observer。`release(topic_id, owner_token)` 只卸该 owner。最后一人离开才拆会话。
3. 命令进，不可变 `TopicDetailUiSnapshot` 出。后台刷新推同一类型。Swift 不保留第二份 source / tree / post 字典。
4. UniFFI 只做 `into_core` / `from_core`、错误映射、panic 边界。业务分支不进 `fire-uniffi-topics`。
5. 不新增「请宿主决定下一步」回调。平台能力继续用 session 通道已有的 CF / cookie hook。
6. 不复制 Kyc：无逐帧同步 tick、无专用会话线程、不在 UI 线程等 HTTP。Kyc 的 `cfg(target_os)` 主要是 JNI、日志和 vendor 绑定，不是产品语义开关。话题详情不按 `target_os` 分产品行为。
7. Actor 跑在现有 tokio（`run_on_ffi_runtime` 那套），每会话一个 task + `mpsc`。HTTP 在 actor 内 await。observer 在放下锁之后调用，`catch_unwind`，不 debounce 点赞。
8. 新会话 API 不收批量参数。actor 用常量组 query。旧 RPC 在删除前仍把宿主 query 的批量原样交给同一个 `load_topic_detail_page`。
9. 旧 RPC 在删除前只转发 `load_topic_detail_page` / `load_topic_detail_source_snapshot` / `load_more_topic_detail_posts`，不进 `Registry.open`。无 observer、无 MessageBus 订阅、无预取、无 owner。Android 行为不变。
10. 首页只收窄计数 patch。不调用 `notify_topic_list`。

### 不复制的 Kyc 形状

要的：`FaceVerifySession` 的生命周期对象；`Ffi*::into_core` / `from_core`；`docs/ARCHITECTURE.md`「接口层只做 ABI」；壳（`FacePipelineController` / `FaceSessionHost`）投影 tick、不拥有 login/compare。话题详情里壳只投影快照、上报可见楼层与生命周期。

不要的：`process_frame` -> `FrameTick` 同步回路；`facelight-session` 专用线程；把平台绑定用的 `cfg(target_os)` 拿来切产品语义。Fire 这边不新增这种分叉。

### 模块

```text
fire-models/src/topic_detail_ui.rs     UI 投影，无逻辑
fire-core/src/core/topic_detail_session.rs
fire-core/src/core/topic_detail_project.rs
fire-uniffi-topics/src/session.rs      Handle + observer 适配
fire-uniffi-topics/src/records.rs      from_core 记录
```

`topics.rs` 里的 source session 原样搬进会话文件（或留在 `topics.rs` 作为 `pub(crate)`）。`FireCore.topic_detail_source` 从 `core/mod.rs` 移除，改成：

```rust
topic_detail_sessions: Arc<TopicDetailSessionRegistry>,
```

`FireCore::fetch_topic_detail_page` 等公开方法保留为兼容包装，内部调用 `load_topic_detail_page` / `load_more_topic_detail_posts`。不另写一套。

### 生命周期与调用

```text
VC appear
  |
  v
Store.open(id, owner, slug, target, bypass)  1 line
  |
  v
FireTopicsHandle.open_topic_detail
  |
  v
Registry.open(topic_id, owner, observer)
  |
  +-- same owner token --> replace that observer
  |
  +-- other owners exist --> fan-out current snapshot
  |
  +-- new session --> spawn actor on shared tokio
        |
        v
      same path as fetch_topic_detail_page
      source session + tree + unread-root seek
        |
        v
      project TopicDetailUiSnapshot
        |
        v
      observer.on_snapshot          not on UI thread
        |
        v
      Store.snapshots[id] = snap
        |
        v
      VC: rows + local chrome
      Texture 3-tier pipeline
```

`open` 立即返回 handle。第一帧可以是 `phase = loading`。缓存短路只属于 `open`，而且只在调用方没要求绕过缓存、并且已有 source 已经包含目标楼时：重推快照，不打网。这对应今天 `loadTopicDetail` 里 `!force` 且 source 已覆盖目标就 return（`+Load.swift` 33–41 行）。`bypass_cache == false` 才走这条。`force_load` 是另一位，只进服务端 query，不决定要不要打网。

```text
VC tap like / reply / load-more
  |
  v
Store command                         1 line, no post merge
  |
  v
session mpsc
  |
  +-- optimistic write posts_by_id
  +-- push snapshot (interaction or collection rev)
  +-- HTTP via existing FireCore methods
  |     ok  -> reconcile, push
  |     err -> rollback, push, surface error
  v
observer
  |
  v
pipeline reads checksums, does not patch posts
```

```text
MessageBus poll loop, each message
  |
  +-- read live listener list   not the list at start
  |
  +-- host UnboundedSender      home / chat / notif
  |
  v
TopicDetailSession
  TopicDetail | TopicReaction:
    scrolling -> defer
    else sleep 1.5s, reload track_visit=false
  TopicDetail + detail_event_type polls:
    same refresh path, no new kind
  Presence:
    typing users onto snapshot
```

`FireMessageBusRuntime` 只有一个在 `start_message_bus` 时放进 `MessageBusPollContext` 的 `event_sender`。内部 listener 必须在每条消息上从 runtime 现读，不能在 start 时拷走。`add_internal_listener` / `remove_internal_listener` 不替换 host sender。`stop_message_bus` 通知 listener；会话若仍有 owner，bus 再次 start 后重订阅。频道与 last id 保持 `FireSessionStore.subscribeTopicDetailChannel`：detail 用 header `message_bus_last_id`，reactions 为 nil，polls 为 0，scope transient。

没有 `MessageBusEventKind::Polls`。`/polls/{id}` 在 `messagebus.rs` 里是 `TopicDetail` 且 `detail_event_type == "polls"`。监听这个组合，或频道前缀 `/polls/`，不要新枚举。

```text
header counts changed
  |
  v
FireCore::patch_cached_home_topic_counts
  read cached row if present
  do not call notify_topic_list
  |
  v
snapshot.home_row_patch: Option<...>
  |
  v
FireHomeFeedStore.applyHomeRowCountPatch
  assign fields only
```

未读决策在 Rust，照抄 `patchedTopicRow`，不从 stream 重算：

```rust
pub enum TopicHomeUnreadDecision {
    /// last_read is None. Do not compare post numbers in Swift.
    /// If row.hasUnreadPosts: keep unreadPosts and newPosts.
    /// If !row.hasUnreadPosts: zero both. Leave the flag as it is.
    WhenLastReadMissing,
    /// last_read >= highest. Zero both counts. hasUnreadPosts = false.
    CaughtUp,
    /// last_read < highest. Keep both counts. hasUnreadPosts = true.
    StillUnread,
}
```

这是 `patchedTopicRow`（`FireHomeFeedStore.swift` 105–109 行）的原公式。`lastRead == nil` 时用行上已有的 `hasUnreadPosts`，为 false 则清零，不是「两个计数字段都不动」。`lastRead < highest` 的比较只在 Rust。patch 结构体没有 `like_count`：`patchedTopicRow` 不写 `likeCount`。

只在 header 的 `posts_count` / `reply_count` / `views` / `last_read_post_number` / `highest_post_number` 或上述未读结果会改变该行时设置 `home_row_patch`。只改赞的 generation 为 `None`，不写磁盘。

内存行：`FireHomeFeedStore.applyHomeRowCountPatch` 按三态赋值。话题不在 `topicEntities` 则 no-op。

磁盘（今天的 `patchTopicCounts` 不写磁盘，这是新增，范围写死）：`FireCore::patch_cached_home_topic_counts` 的键是 `current_auth_scope_hash()` 加上 `topic_list_cache_scope_key(&self.current_home_topic_list_query())`。`HomeTopicListScope` 不是这个字符串。`FireStore` 增加 `topic_list_cache_list_pages(auth_scope_hash, scope_key) -> Vec<(u32, String)>`，只列这一对键下的页。命中后同时改两处，禁止调用 `topic_row_from_topic`（它把 `has_unread_posts` 写成 `unread_posts > 0`，和 `patchedTopicRow` 不一致）：

- `topics[]` 里匹配的 `TopicSummary`：`posts_count`、`reply_count`、`views`、`last_read_post_number`、`highest_post_number`、`unread_posts`、`new_posts`。`TopicSummary` 没有 `has_unread_posts`。
- `rows[]` 里匹配的 `TopicRow`：嵌套 `topic` 的同一组计数字段，加上行自己的 `has_unread_posts`。`WhenLastReadMissing` 读的是这个 `TopicRow.has_unread_posts`，不是 summary。

写回用 `topic_list_cache_write`，键不变。不调用 `notify_topic_list`。不扫其它 scope。

PR-B 删除 `patchedTopicRow` 和 `patchTopicCounts`。`FireTopicListMessageBusRefreshTests` 改断言 `applyHomeRowCountPatch`。未读三态的单元测试放在 Rust，Swift 不再留第二份公式。

### Core 类型

```rust
// fire-core/src/core/topic_detail_session.rs

pub const TOPIC_DETAIL_INITIAL_BATCH: u16 = 40;
pub const TOPIC_DETAIL_LOAD_MORE_BATCH: u16 = 40;
pub const TOPIC_DETAIL_MAX_AUTO_BATCHES: u8 = 3;
pub const TOPIC_DETAIL_MAX_AUTO_POSTS: u16 = 120;
pub const TOPIC_DETAIL_PREFETCH_THRESHOLD: u32 = 10;
pub const TOPIC_DETAIL_FORWARD_EXPANSION: u32 = 60;
pub const TOPIC_DETAIL_HYDRATION_PAGE: usize = 30;
pub const TOPIC_DETAIL_HYDRATION_ITERS: u8 = 8;
pub const TOPIC_DETAIL_VISIBLE_DEBOUNCE: Duration = Duration::from_millis(120);
pub const TOPIC_DETAIL_LIST_TAIL_THRESHOLD: u32 = 5;
pub const TOPIC_DETAIL_REPLY_CONTEXT_BATCH: usize = 20;
pub const TOPIC_DETAIL_REFRESH_DEBOUNCE: Duration = Duration::from_millis(1500);
pub const TOPIC_DETAIL_PRESENCE_HEARTBEAT: Duration = Duration::from_secs(30);
pub const TOPIC_DETAIL_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

pub struct TopicDetailOpenRequest {
    pub topic_id: u64,
    pub owner_token: String,
    pub slug_hint: Option<String>,
    pub target_post_number: Option<u32>,
    /// Local cache bypass for `open` only. Not the server query bit.
    pub bypass_cache: bool,
    /// `TopicDetailSourceQuery.force_load`. Does not decide whether to skip HTTP.
    pub force_load: bool,
    pub track_visit: bool,
    pub allow_suggested_unread_root: bool,
}

pub trait TopicDetailObserver: Send + Sync {
    fn on_snapshot(&self, snapshot: TopicDetailUiSnapshot);
}

impl TopicDetailSessionRegistry {
    pub fn open(
        &self,
        request: TopicDetailOpenRequest,
        observer: Arc<dyn TopicDetailObserver>,
    ) -> Arc<TopicDetailSession>;
    /// Drops only this owner and its observer. Last owner unsubscribes,
    /// cancels tasks, and removes the session. Same token re-open replaces
    /// the observer; it does not append a second one.
    pub fn release(&self, topic_id: u64, owner_token: &str);
    pub fn close_all(&self);
    /// Transient unauth. Cancels actor HTTP. Keeps owners and the last Ready snapshot.
    pub fn cancel_inflight_http(&self);
}

impl TopicDetailSession {
    pub fn release_owner(&self, owner_token: &str);
    /// Always HTTP. No cache short-circuit. `force_load` is only the server query bit.
    pub fn reload(
        &self,
        target_post_number: Option<u32>,
        force_load: bool,
        track_visit: bool,
        allow_suggested_unread_root: bool,
    );
    pub fn load_more(&self);
    pub fn note_visible_posts(&self, post_numbers: Vec<u32>);
    pub fn note_filtered_feed_tail(&self, item_count: u32, visible_max_item: Option<u32>);
    pub fn note_scroll_interaction(&self, active: bool);
    pub fn acknowledge_scroll_target(&self, post_number: u32);
    pub fn clear_scroll_target(&self);
    pub fn begin_reply_typing(&self);
    pub fn end_reply_typing(&self);
    pub fn reload_ai_summary(&self, skip_age_check: bool);
    pub fn load_reply_context(&self, post_id: u64);
    pub async fn prepare_edit(&self, post_id: u64) -> Result<String, FireCoreError>;
    pub async fn ensure_flag_types(&self) -> Result<(), FireCoreError>;
    pub async fn submit_reply(
        &self,
        raw: String,
        reply_to_post_number: Option<u32>,
        scroll_to_created: bool,
    ) -> Result<(), FireCoreError>;
    pub async fn create_boost(&self, post_id: u64, raw: String) -> Result<(), FireCoreError>;
    pub async fn delete_boost(&self, post_id: u64, boost_id: u64) -> Result<(), FireCoreError>;
    pub async fn update_post(
        &self,
        post_id: u64,
        raw: String,
        edit_reason: Option<String>,
    ) -> Result<(), FireCoreError>;
    pub async fn delete_post(&self, post_id: u64) -> Result<(), FireCoreError>;
    pub async fn recover_post(&self, post_id: u64) -> Result<(), FireCoreError>;
    pub async fn flag_post(
        &self,
        post_id: u64,
        flag_type_id: u32,
        message: Option<String>,
    ) -> Result<(), FireCoreError>;
    pub async fn set_liked(&self, post_id: u64, liked: bool) -> Result<(), FireCoreError>;
    pub async fn toggle_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<(), FireCoreError>;
    pub async fn vote_poll(
        &self,
        post_id: u64,
        poll_name: String,
        options: Vec<String>,
    ) -> Result<(), FireCoreError>;
    pub async fn unvote_poll(
        &self,
        post_id: u64,
        poll_name: String,
    ) -> Result<(), FireCoreError>;
    pub async fn vote_topic(&self, voted: bool) -> Result<(), FireCoreError>;
    pub async fn accept_solution(&self, post_id: u64, accepted: bool) -> Result<(), FireCoreError>;
    pub async fn create_bookmark(
        &self,
        bookmarkable_id: u64,
        bookmarkable_type: String,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireCoreError>;
    pub async fn update_bookmark(
        &self,
        bookmark_id: u64,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireCoreError>;
    pub async fn delete_bookmark(&self, bookmark_id: u64) -> Result<(), FireCoreError>;
    pub async fn set_notification_level(&self, level: i32) -> Result<(), FireCoreError>;
    pub async fn update_topic(
        &self,
        title: String,
        category_id: u64,
        tags: Vec<String>,
    ) -> Result<(), FireCoreError>;
    pub async fn report_timings(&self, topic_time_ms: u32, timings: Vec<TopicTimingEntry>) -> Result<bool, FireCoreError>;
}

```

唯一的拉页实现（不是 `cfg(test)`，actor、兼容 RPC、测试共用）：

```rust
pub(crate) async fn load_topic_detail_source_snapshot(
    core: &FireCore,
    query: TopicDetailSourceQuery,
) -> Result<TopicDetailSourceSnapshot, FireCoreError>;

pub(crate) async fn load_topic_detail_page(
    core: &FireCore,
    query: TopicDetailSourceQuery,
) -> Result<TopicDetailPage, FireCoreError>;

pub(crate) async fn load_more_topic_detail_posts(
    core: &FireCore,
    query: LoadMoreTopicPostsQuery,
) -> Result<TopicLoadMoreOutcome, FireCoreError>;
```

`FireCore::fetch_topic_detail_source_snapshot` / `fetch_topic_detail_page` / `load_more_topic_posts` 只转发这三个函数。兼容路径无 observer、无 MessageBus 订阅、无预取任务、无 owner。它写入的 `TopicDetailSourceSession` 就是 `load_more` 用 `(topic_id, session_id)` 查找的那张表（今天的 `FireTopicDetailSourceRuntime.sessions_by_topic_id`）。query 上的 `initial_batch_size`、`load_more_batch_size`、`max_auto_*`、`force_load`、`track_visit`、`allow_suggested_unread_root`、`target_post_number` 原样生效。Android `TopicRepository` 仍传 40/40/3/120，运行时行为不变。actor 自己组 query：批量用会话常量，访问与未读根用 open/reload 契约，不读 Swift 传来的批量。

`prepare_edit` 是唯一允许的拉取：编辑器要预填 raw，raw 不是 cell 的 cooked HTML。读会话里已有 `TopicPost.raw`，没有再走现有 `fetch_post`。Swift 把字符串放进编辑草稿（本地 chrome），不写回行字典。

空正文拒绝在 Rust 再做一次（`FireCoreError`），Swift composer 仍可在点击前本地拦住。这是守卫，不是两套分页策略。

写命令 `async` 只为让 composer 拿到 `quickReplyError`。成功路径不返回帖。点赞在 HTTP 前推乐观快照。回复和 boost 不插占位行，见「回复插入与 boost」。`like` 无 body 时与今天一样：有 `PostReactionUpdate` 就覆盖，没有就在会话内再拉一页（`track_visit = false`），Swift 不参与。

`create_bookmark` 包装 `FireCore::create_bookmark`（`interactions.rs`），`bookmarkable_type` 为 `"Topic"` 或 `"Post"`，保留 `auto_delete_preference`。成功后把返回的 bookmark id 写到 header（话题）或行（帖）。话题书签抬 `chrome_revision`。帖书签改行上的 bookmark 字段，从而改变 `interaction_checksum`（`postContentToken` 收录 bookmark，`postLayoutContentToken` 不收录）。`update_bookmark` / `delete_bookmark` 同样包装现有函数。没有 `TopicBookmarkTarget`，也没有单独的 `clear_bookmark`。

`update_topic` 成功后更新 chrome 的 title / category / tags 并抬 `chrome_revision`。计数 patch 不带标题、分类、标签、摘要。Swift `FireAppViewModel.updateTopic` 在命令返回后仍调用现有 `refreshHomeFeedIfPossible(force: true)`。excerpt 在这次首页刷新返回前保持旧值，这是有意的。`delete_post` / `recover_post` / `flag_post` / `update_post` 的 Swift 转发在成功后仍调用现有 `refreshHomeFeedIfPossible(force: false)`，对齐 `performPostManagementMutation`。会话同时在 header 计数变化时发 home patch。

`bypass_cache` 与 `force_load` 分开，不从其中一个推断另一个。缓存短路只在 `open`，而且只在 `bypass_cache == false` 且已有 source 已包含目标楼时：重推快照，不打网。`reload` 永远打 HTTP。对账、MessageBus、书签、通知级别、帖子编辑器、改话题用的 reload 固定 `force_load = false`，`track_visit = false`，`allow_suggested_unread_root = false`。`reload_ai_summary` 不走这次 reload。Android 兼容 RPC 把 query 的 `force_load`、`track_visit`、`allow_suggested_unread_root` 原样传入 `load_topic_detail_page`，没有 `open` 的缓存短路。

调用点不再写 `loadTopicDetail(force:)`。三位是：

| 调用 | bypass_cache | force_load | track_visit |
| --- | --- | --- | --- |
| 首次 `open`，调用方 force == false（`viewDidAppear` 那条 `loadTopicDetail`） | false | false（仅当这次真的打网） | true |
| 下拉刷新 `performRefresh` | true | true | true |
| 信息流错误重试 `onLoadTopicDetail`（`FireTopicDetailFeedCellFactory` 的重试按钮） | true | true | true |
| Android `TopicDetailViewModel.loadTopicDetail` → `open` | true | true | true |

`allow_suggested_unread_root` 不在这张表里单独发明：iOS 仍是「无目标且没有 Ready 快照」。Android 保持今天的 `targetPostNumber == null && _detail.value == null`，不改。下拉刷新和错误重试的 `track_visit = true` 是有意的，和删掉的编辑器保存不同。这两处用同一个 owner 再 `open`，不是 `reload`，这样 `bypass_cache` 才存在。

`openAdvancedComposer` 与 `openQuoteComposer` 的 `onReplySubmitted` 不再 `loadTopicDetail`。`submit_reply` 已经用 `force_load = false`、`track_visit = false` 对账。引用回复传 `scroll_to_created = true`：会话把 `create_reply` 返回帖的 `post_number` 写成 `scroll_target`。这替换今天 `openQuoteComposer` 里跳到被引用帖 `post.postNumber` 的行为。高级回复传 `scroll_to_created = false`。

`report_timings` 不改变快照结构。失败吞掉并返回 `false`，对齐 `FireTopicInteractionService.reportTopicTimings`。

### 快照（UI 投影）

`fire-models` 新文件。不含 `raw_stream_ids`、`TopicSourceCursor`、`loaded_ranges`、cooked `String`。

```rust
pub struct TopicDetailUiSnapshot {
    pub topic_id: u64,
    pub generation: u64,
    pub phase: TopicDetailPhase, // Loading | Ready | Failed
    pub load_error: Option<TopicDetailLoadError>,
    pub notice: Option<TopicDetailNotice>,
    pub has_more: bool,
    pub is_loading_more: bool,
    pub load_more_error: Option<String>,
    pub scroll_target_post_number: Option<u32>,
    pub collection_revision: u64,
    pub chrome_revision: u64,
    pub sidecar_revision: u64,
    pub interaction_revision: u64,
    pub chrome: TopicDetailChrome,
    pub composer: TopicDetailComposerModel,
    pub sidecar: TopicDetailSidecarModel,
    pub rows: Vec<TopicDetailUiRow>,
    pub focused_reply_context: Option<TopicDetailReplyContext>,
    pub flag_types: Vec<PostActionType>,
    pub home_row_patch: Option<TopicHomeRowCountPatch>,
}

pub struct TopicDetailUiRow {
    pub post_id: u64,
    pub post_number: u32,
    pub root_post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u16,
    pub has_children: bool,
    pub is_last_sibling: bool,
    pub descendant_count: u32,
    pub author: TopicDetailAuthorDisplay,
    pub presentation: AttachedPresentation, // FFI 层换成 RenderDocumentHandle
    pub layout_checksum: u64,
    pub interaction_checksum: u64,
    pub created_at: Option<String>,
    pub reply_count: u32,
    pub reply_to_username: Option<String>,
    pub like_count: u32,
    pub reactions: Vec<TopicDetailReactionChip>,
    pub current_reaction_id: Option<String>,
    pub polls: Vec<TopicDetailPollDisplay>,
    pub boosts: Vec<TopicDetailBoostDisplay>,
    pub accepted_answer: bool,
    pub can_accept_answer: bool,
    pub can_unaccept_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub can_boost: bool,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub hidden: bool,
    pub is_mutating: bool,
    pub is_loading_reply_context: bool,
    pub is_original_post: bool,
}

pub struct TopicDetailReactionChip {
    pub id: String,
    pub count: u32,
    pub selected: bool,
}

pub struct TopicHomeRowCountPatch {
    pub topic_id: u64,
    pub posts_count: u32,
    pub reply_count: u32,
    pub views: u32,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
    pub unread: TopicHomeUnreadDecision,
}
```

没有 `like_count`。`patchedTopicRow` 不拷贝它。

### 嵌套显示结构

字段来自 `TopicPost`、`TopicPostAuthorMetadata`、`TopicPostBoost`、`Poll`、`TopicHeader`。boost 与正文用 `RenderDocumentHandle`，cooked 字符串不出 FFI。

`TopicDetailAuthorDisplay`：`username`，`name`，`avatar_template`，`user_id`，`user_title`，`primary_group_name`，`flair_url`，`flair_name`，`flair_bg_color`，`flair_color`，`flair_group_id`，`moderator`，`admin`，`group_moderator`，`user_status_emoji`，`user_status_description`。

`TopicDetailPollDisplay`：`id`，`name`，`kind`，`status`，`results`，`voters`，`user_votes`。选项：`id`，`html`，`plain_text`，`votes`。选项 html 是投票控件要画的，不是帖子 cooked。

`TopicDetailBoostDisplay`：`id`，`display_text`，`user`（`id`，`username`，`name`，`avatar_template`），`can_delete`，`can_flag`，`user_flag_status`，`available_flags`，`presentation: RenderDocumentHandle`。没有 `cooked`。

`TopicDetailChrome`：`title`，`slug`，`archetype`，`bookmarked`，`bookmark_id`，`bookmark_name`，`bookmark_reminder_at`，`notification_level`，`can_edit`，`category_id`，`tags`（`TopicTag` 的 name），`views`，`posts_count`，`reply_count`，`like_count`（话题赞，给统计行，不进首页 patch），`vote_count`，`user_voted`，`can_vote`，`has_accepted_answer`，`created_at`，`highest_post_number`，`last_read_post_number`。参与者：`user_id`，`username`，`name`。

`TopicDetailComposerModel`：`typing_users`（`id`，`username`，`avatar_template`），`is_submitting`。没有草稿、没有最短回复长度、没有 `canWrite`。

`TopicDetailSidecarModel`：`summarized_text`，`algorithm`，`outdated`，`can_regenerate`，`new_posts_since_summary`，`updated_at`，`is_loading`，`error`。没有 `isTopicAiSummaryExpanded`。

`TopicDetailReplyContext`：`root_post_id`，已并入主行的 `appended_post_ids`，`history_rows: Vec<TopicDetailUiRow>`。

行上另外要有：`updated_at`，`post_type`，`reply_to_user`（`username`，`name`，`avatar_template`），`bookmark_name`，`bookmark_reminder_at`。`can_boost` 已在行上。

VC 继续从 `SessionState` 读，不拷进话题快照，也不要在改 builder 时删掉：

- `canWriteInteractions` = `FireAppViewModel.canStartAuthenticatedMutation`
- `baseURLString` = `session.bootstrap.baseUrl`，空则 `https://linux.do`
- `minimumReplyLength` = `FireTopicPresentation.minimumReplyLength`，私信用 `minPersonalMessagePostLength`，否则 `minPostLength`
- 是否私信线程用 chrome 的 `archetype`，经现有 `FireTopicPresentation.isPrivateMessageArchetype`

### Checksum

Rust 只哈希服务端字段。Swift builder 把本地 chrome 折进去。验收标准是今天的 `postLayoutContentToken`（`FireTopicDetailRuntimeSnapshotBuilder.swift` 418–430 行），字段为：

- `post.id`
- `FirePostAuthorMetadataDisplay.contentToken`
- `renderContent?.signature.token ?? "pending"`
- `pollsContentToken`
- `FirePostBoostDisplay.contentToken`（id、用户、displayText、presentation plain text、canDelete、canFlag，不是条数）
- `String(!post.reactions.isEmpty)`（空与非空，不是完整反应列表）
- `String(replyShortcutCount != nil)`
- `String(isReplyThreadExpanded)`
- `String(isReactionPickerExpanded)`
- `String(textExpansionState.isExpanded)`
- `String(textExpansionState.isCollapsible)`

`layout_checksum` 只覆盖其中的服务端部分：post id、作者 metadata、presentation checksum、poll token、boost token、`reactions.is_empty()`。回复快捷方式是否为 nil、回复树展开、表情条展开、正文展开，留在 Swift。

`interaction_checksum` 覆盖 `postContentToken` 里的服务端部分：楼层号、用户名、头像、created/updated、like count、reply count、完整反应列表（id、kind、count、can_undo）、current reaction id、accepted / can_edit / can_delete / can_recover / hidden、bookmark 三字段加 bookmarked、`is_mutating`、`is_loading_reply_context`。搜索高亮、`canWriteInteractions`、正文展开、表情条展开留在 Swift。

builder 组 token，而不是赋值：

- layout token = `layout_checksum` + 上面四项本地 chrome（shortcut、回复树、表情条、正文展开）
- in-place token = `interaction_checksum` + layout token 里 Swift 已折入的本地项 + `isSearchHighlighted` + `canWriteInteractions`
- 摘要卡再把 `isTopicAiSummaryExpanded` 折进该卡的 layout token

禁止 `contentToken = layout_checksum` 或 `inPlaceUpdateToken = interaction_checksum`。首枚反应让 `reactions.is_empty()` 翻转，layout token 变，走可见行 relayout。之后的续赞只变 `interaction_checksum`，走 in-place。正文展开不进 `FireTopicDetailFeedInvalidationToken`（今天也没有 `expandedPostTextIDs`），靠 `applyLocalInteractionSnapshot` 里 layout token 变化 relayout。搜索高亮留在 in-place token；`activeSearchPostID` 仍在 invalidation token 上。

`collection_revision`：插删行、分页、首屏替换、加载/错误/has_more 变化。`interaction_revision`：只改表情或 mutating，且 layout checksum 不变。`chrome_revision`：标题、话题书签、通知级别、投票数。`sidecar_revision`：AI 摘要与 notice。展开回复树不在 Rust revision 里，VC 把 `expandedReplyRootPostIDs` 放进自己的 invalidation token，继续走 collection diff。

行集合是已加载树的前序，含楼主。二级楼默认隐藏仍由 Swift `makeReplyDisplayPlan` 用 `expandedReplyRootPostIDs` 过滤。Rust 不接收展开集合。

`focused_reply_context` 在 `load_reply_context` 后填充：已并入主行的子楼 id，加历史行（今天的 `postReplyHistoryByPostID`）。`applyReplyContextRowsIfPossible` 的并树进会话，用现有 `TopicTreeRow` 规则，不在 Swift 改 parent/depth。

`load_error` 枚举：`Network`、`LoginRequired`、`Unrecoverable { message }`。VC 只展示，不 `switch` 后重试。

### 会话私有状态

```rust
struct SessionInner {
    source: TopicDetailSourceSession, // 现有私有结构
    tree: TopicTreePresentation,
    generation: u64,
    scroll_target: Option<u32>,
    scroll_target_exhausted: bool,
    window: TopicWindow,              // 现 FireTopicDetailWindowState 的语义
    scroll_active: bool,
    deferred_refresh: DeferredRefresh, // None | Pending | Ready(snapshot)
    owners: HashMap<String, Arc<dyn TopicDetailObserver>>,
    optimistic: HashMap<u64, TopicPost>, // 回滚用，不对 Swift 暴露
}
```

`note_visible_posts` 在 120ms debounce 后，坐标是楼层号，不是列表下标：

- 可见楼层距已加载窗口边 ≤ `PREFETCH_THRESHOLD`（10）时，按 `FORWARD_EXPANSION`（60）与 `HYDRATION_PAGE`（30）补 `fetch_topic_posts`，最多 `HYDRATION_ITERS`（8）。等价 `expandRequestedRangeIfNeeded` + `hydrateTopicPostsToTargetIfNeeded`。
- 有未完成 `scroll_target` 时沿用 `nextRequestedRangeForUnresolvedTarget` 的跳转，直到命中或 `scrollTargetIsExhausted`。窗口上限仍是今天的 `FireTopicDetailWindowState.maxWindowSize`（200），私有，不进 FFI。命中前快照带 `scroll_target_post_number`。VC `acknowledge_scroll_target` 后清空。

`note_filtered_feed_tail` 的坐标是 `makeReplyDisplayPlan` 隐藏二级回复之后的列表下标，不是快照全序行。谓词与 `fireTopicDetailShouldLoadMore` 相同：`item_count > 0`，`visible_max_item` 为 Some，且 `item_count - visible_max_item <= 5`，并且 `has_more`。满足则跑与 `load_more_topic_posts` 相同的连批停止条件。Swift 删掉 `fireTopicDetailShouldLoadMore`，避免两份阈值。协调器只上报两个整数。

`load_more` 是用户点 footer 的一拍，同一停止条件，不看尾阈值。

### 回复插入与 boost

`submit_reply` 不在 HTTP 前插占位行。`create_reply` 返回 `TopicPost` 之后，按 `applyCreatedReply`（`+Mutations.swift` 537–581 行）：

- id 不在 `raw_stream_ids` 则 append
- 合并进 `posts_by_id`
- `posts_count = max(old + 1, stream_len)`，`reply_count = max(old + 1, posts_count.saturating_sub(1))`
- `highest_post_number = max(highest, post_number)`，`last_read = max(last_read.unwrap_or(0), post_number)`
- 若窗口 `requested_range.upper_bound >= 插入前的 stream_len`，把上界伸到新的 stream 末尾
- 重建树，推快照。header 计数变了才带 `home_row_patch`
- 再 `reload(target: None, force_load: false, track_visit: false, allow_suggested_unread_root: false)` 对账。这一步必须打网，不能因为帖已经在 source 里就短路。

`create_boost` 成功后：该 id 不在列表则 append，`can_boost = false`。boost token 变，`layout_checksum` 变，抬 `collection_revision`（高度变，不是 in-place）。然后同一套 `track_visit = false` 的 reload。

### 恢复

- CF：请求继续走 foreground profile，现有 `retry_after_cloudflare_challenge`。会话不调用 Swift。
- cookie：现有 `cookie_self_healing_handler`。
- `StaleSessionResponse`：再打一次 HTTP，`force_load = true`，`track_visit` 保持这次加载的原值。这是服务端 query 位，不是缓存短路。仍失败才 `load_error`。
- `LoginRequired`：不写 `FireAuthRecoveryHint`，不发明轮换原因。`FireAuthRecoveryHintReason` 仍只有 `TOnlyRotation` 与 `ForumSessionOnlyRotation`。`runAuthenticatedWritePreflight` 的 hint epoch 判断不动。

唤醒字段不进持久化信封。权威副本在 `FireSessionRuntimeState`，和 `auth_recovery_hint` 一样。`SessionSnapshot` 若为了 `SessionState::from_snapshot` 带上它，必须 `#[serde(skip)]`，而且 `update_session_persistence_revisions` 比较时忽略这一字段，不能单凭它增加 `snapshot_revision`。`export_session_json` / `PersistedSessionEnvelope` 因此写不进去。`restore_session_json` 在清 `auth_recovery_hint` 的同一处把 runtime 上的请求清掉（`persistence.rs` 第 39 行旁边）。

```rust
pub struct ReadPathLoginRequest {
    pub generation: u64,
    pub operation: String,
}

// FireSessionRuntimeState
pub(crate) read_path_login_request: Option<ReadPathLoginRequest>,

// SessionSnapshot，只出现在 notify 推出去的副本上
#[serde(skip)]
pub read_path_login_request: Option<ReadPathLoginRequest>,
```

`request_read_path_login(operation) -> u64` 写 runtime 字段。已有未完成的 generation 时，后来的 LoginRequired 加入这一代，不换号。`notify_session` 把该字段拷到推送副本上。`DebouncedEmitter` 仍是 100ms 取最新快照，未完成的请求留在 runtime 上，所以窗口里后到的快照仍带着它。不增加 epoch。

`applySession` 看到新 generation 时，不调用 `runReadPathLoginRecovery`。那只是 cookie 重放，没有 single-flight，也没有 headless。要跑的是 `attemptReadPathLoginRecovery` 去掉 `LoginRequired` 类型守卫之后的函数体，operation 用 `ReadPathLoginRequest.operation`：

1. `attemptHostCookieResyncRecovery(operation:)`。同一 epoch 已有任务则 join。
2. 只有它返回 false，才 `attemptMidSessionHeadlessReauth(operation:)`。

首页 store 继续自己调用带守卫的 `attemptReadPathLoginRecovery`，不改。

返回后 `applySession` 调 `FireSessionHandle::complete_read_path_login(generation, succeeded)`。实现在 `FireCore` 里走 registry，叫醒这一代的全部 waiter。不新增话题 observer。`succeeded == true` 时每个 waiter `reload(force_load: true, track_visit: 这次加载的原值, allow_suggested_unread_root: false)` 一次。`reload` 必打网。`succeeded == false` 时这些快照停在 `LoginRequired`，不第二次。无关 epoch 变化不触发。

### 三种会话过渡

`FireTopicDetailStore.applySession` 保留，只转发 readiness。`FireAppViewModel.applySession` 继续调用它。

| 过渡 | 条件 | 行为 |
| --- | --- | --- |
| 完整登出 | `!hasLoginCookie && !hasCurrentUser` | 每个 handle `close`（只释放自己的 owner）。registry 无 owner 后拆会话。Swift 清空 `snapshots` |
| 短暂不可读 | `!canReadAuthenticatedApi` 且不是完整登出 | `cancel_inflight_http`。保留 owner 和最后一帧 Ready 快照。不推空快照 |
| 读路径恢复成功 | `complete_read_path_login(succeeded: true)` | `reload(force_load: true)`，`track_visit` 不变，必打网。先不推空快照。失败则停在 `LoginRequired` |

`canReadAuthenticatedApi == true` 时 `applySession` 立即 return。cookie / CSRF 造成的 epoch 增加不走登出分支。

乐观更新：`set_liked` / `toggle_reaction` 在 actor 里克隆帖、改 count 与 current reaction、推 interaction 快照、置 `is_mutating`。失败恢复克隆。成功用 `PostReactionUpdate` 覆盖。与 `applyOptimisticReactionChange` 同一规则（heart id `"heart"`，再点同一 reaction 即取消）。

MessageBus：`TopicDetail` 与 `TopicReaction` 走 1.5s debounce 后 `reload(target: None, force_load: false, track_visit: false, allow_suggested_unread_root: false)`，必打网。`detail_event_type == "polls"` 走同一条，不新增 kind。滚动中：请求还没结束记 `Pending`；请求已结束则把快照放进 `Ready`，对齐 `deferredTopicDetailRefreshPayloads`。`note_scroll_interaction(false)` 若是 `Ready`，直接推这帧，不再请求；若是 `Pending`，再 reload。`presence` 读 `topic_reply_presence_state`，滤掉当前用户，写入 composer。Swift 不再滤。

AI 摘要：首包后若 `summarizable` 且无摘要，会话调用现有 `fetch_topic_ai_summary`。loading 不抬 `collection_revision`（今天 `setLoadingTopicAiSummary` 的注释：避免空 chrome 抖动）。失败只抬 sidecar。

### FFI

```rust
// fire-uniffi-topics/src/session.rs

#[uniffi::export(with_foreign)]
pub trait TopicDetailObserver: Send + Sync {
    fn on_snapshot(&self, snapshot: TopicDetailUiSnapshotState);
}

#[derive(uniffi::Object)]
pub struct TopicDetailSessionHandle {
    inner: Arc<fire_core::TopicDetailSession>,
    topic_id: u64,
    owner_token: String,
}

#[uniffi::export]
impl FireTopicsHandle {
    pub fn open_topic_detail(
        &self,
        request: TopicDetailOpenRequestState,
        observer: Arc<dyn TopicDetailObserver>,
    ) -> Result<Arc<TopicDetailSessionHandle>, FireUniFfiError>;
}

#[uniffi::export]
impl TopicDetailSessionHandle {
    /// Handle stores the owner token from open. `release` calls
    /// registry.release(topic_id, owner_token) for that owner only.
    /// Named `release` (not `close`) so Kotlin UniFFI does not collide with `AutoCloseable.close`.
    pub fn release(&self);
    /// Always HTTP. `force_load` is `TopicDetailSourceQuery.force_load`, not a cache bypass.
    pub fn reload(
        &self,
        target_post_number: Option<u32>,
        force_load: bool,
        track_visit: bool,
        allow_suggested_unread_root: bool,
    );
    pub fn load_more(&self);
    pub fn note_visible_posts(&self, post_numbers: Vec<u32>);
    pub fn note_filtered_feed_tail(&self, item_count: u32, visible_max_item: Option<u32>);
    pub fn note_scroll_interaction(&self, active: bool);
    pub fn acknowledge_scroll_target(&self, post_number: u32);
    pub fn clear_scroll_target(&self);
    pub fn begin_reply_typing(&self);
    pub fn end_reply_typing(&self);
    pub fn reload_ai_summary(&self, skip_age_check: bool);
    pub fn load_reply_context(&self, post_id: u64);
    pub async fn prepare_edit(&self, post_id: u64) -> Result<String, FireUniFfiError>;
    pub async fn submit_reply(&self, raw: String, reply_to_post_number: Option<u32>, scroll_to_created: bool) -> Result<(), FireUniFfiError>;
    pub async fn create_boost(&self, post_id: u64, raw: String) -> Result<(), FireUniFfiError>;
    pub async fn delete_boost(&self, post_id: u64, boost_id: u64) -> Result<(), FireUniFfiError>;
    pub async fn update_post(&self, post_id: u64, raw: String, edit_reason: Option<String>) -> Result<(), FireUniFfiError>;
    pub async fn delete_post(&self, post_id: u64) -> Result<(), FireUniFfiError>;
    pub async fn recover_post(&self, post_id: u64) -> Result<(), FireUniFfiError>;
    pub async fn flag_post(&self, post_id: u64, flag_type_id: u32, message: Option<String>) -> Result<(), FireUniFfiError>;
    pub async fn ensure_flag_types(&self) -> Result<(), FireUniFfiError>;
    pub async fn set_liked(&self, post_id: u64, liked: bool) -> Result<(), FireUniFfiError>;
    pub async fn toggle_reaction(&self, post_id: u64, reaction_id: String) -> Result<(), FireUniFfiError>;
    pub async fn vote_poll(&self, post_id: u64, poll_name: String, options: Vec<String>) -> Result<(), FireUniFfiError>;
    pub async fn unvote_poll(&self, post_id: u64, poll_name: String) -> Result<(), FireUniFfiError>;
    pub async fn vote_topic(&self, voted: bool) -> Result<(), FireUniFfiError>;
    pub async fn accept_solution(&self, post_id: u64, accepted: bool) -> Result<(), FireUniFfiError>;
    pub async fn create_bookmark(&self, bookmarkable_id: u64, bookmarkable_type: String, name: Option<String>, reminder_at: Option<String>, auto_delete_preference: Option<i32>) -> Result<(), FireUniFfiError>;
    pub async fn update_bookmark(&self, bookmark_id: u64, name: Option<String>, reminder_at: Option<String>, auto_delete_preference: Option<i32>) -> Result<(), FireUniFfiError>;
    pub async fn delete_bookmark(&self, bookmark_id: u64) -> Result<(), FireUniFfiError>;
    pub async fn set_notification_level(&self, level: i32) -> Result<(), FireUniFfiError>;
    pub async fn update_topic(&self, title: String, category_id: u64, tags: Vec<String>) -> Result<(), FireUniFfiError>;
    pub async fn report_timings(&self, topic_time_ms: u32, timings: Vec<TopicTimingEntryState>) -> Result<bool, FireUniFfiError>;
}
```

适配器：

```rust
struct FfiTopicDetailObserver {
    inner: Arc<dyn TopicDetailObserver>,
}

impl fire_core::TopicDetailObserver for FfiTopicDetailObserver {
    fn on_snapshot(&self, snapshot: fire_core::TopicDetailUiSnapshot) {
        self.inner.on_snapshot(TopicDetailUiSnapshotState::from_core(snapshot));
    }
}
```

`from_core` 只做字段拷贝，并把 `AttachedPresentation` 交给已有 `intern_presented_handle`。禁止在这里决定预取、重试、未读。

兼容包装（删之前）：

```rust
impl FireTopicsHandle {
    pub async fn fetch_topic_detail_page(...) -> Result<TopicDetailPageState, FireUniFfiError> {
        // load_topic_detail_page(query.into())。batch、force、track_visit、
        // allow_suggested_unread_root 都保留。无 observer、无订阅、无预取、无 owner。
    }
    pub async fn fetch_topic_detail_source_snapshot(...) -> Result<TopicDetailSourceSnapshotState, FireUniFfiError> {
        // load_topic_detail_source_snapshot。同一张 session 表。
    }
    pub async fn load_more_topic_posts(...) -> Result<TopicLoadMoreOutcomeState, FireUniFfiError> {
        // load_more_topic_detail_posts。cursor.session_id 必须命中刚才写入的 source session。
    }
}
```

`fetch_topic_posts`、`like_post` 等非详情屏幕也会用的 RPC 保持原样，直到 Android 详情不再通过它们改本地帖。详情屏幕的 iOS 路径停止调用 `fetchTopicDetailPage` / `loadMoreTopicPosts`。

晚到快照：`generation` 单调。Swift 丢弃更旧的 generation。

### Swift 之后的 store 与 VC

```swift
@MainActor
final class FireTopicDetailStore: ObservableObject {
    @Published private(set) var snapshots: [UInt64: TopicDetailUiSnapshot] = [:]

    func open(topicId: UInt64, ownerToken: String, slug: String?, targetPostNumber: UInt32?, bypassCache: Bool, forceLoad: Bool, trackVisit: Bool, allowSuggestedUnreadRoot: Bool)
    func close(topicId: UInt64, ownerToken: String)
    func reload(topicId: UInt64, targetPostNumber: UInt32?, forceLoad: Bool, trackVisit: Bool, allowSuggestedUnreadRoot: Bool)
    func loadMore(topicId: UInt64)
    func noteVisiblePosts(topicId: UInt64, postNumbers: Set<UInt32>)
    func noteFilteredFeedTail(topicId: UInt64, itemCount: Int, visibleMaxItem: Int?)
    func applySession(_ session: SessionState)
    func noteScrollInteraction(topicId: UInt64, active: Bool)
    func acknowledgeScrollTarget(topicId: UInt64, postNumber: UInt32)
    func clearScrollTarget(topicId: UInt64)
    func beginReplyTyping(topicId: UInt64)
    func endReplyTyping(topicId: UInt64) async
    func reloadAiSummary(topicId: UInt64, skipAgeCheck: Bool)
    func loadReplyContext(topicId: UInt64, postId: UInt64)
    func prepareEdit(topicId: UInt64, postId: UInt64) async throws -> String
    func submitReply(topicId: UInt64, raw: String, replyToPostNumber: UInt32?, scrollToCreated: Bool) async throws
    func setPostLiked(topicId: UInt64, postId: UInt64, liked: Bool) async throws
    func togglePostReaction(topicId: UInt64, postId: UInt64, reactionId: String) async throws
    func votePoll(topicId: UInt64, postId: UInt64, pollName: String, options: [String]) async throws
    func unvotePoll(topicId: UInt64, postId: UInt64, pollName: String) async throws
    func voteTopic(topicId: UInt64, voted: Bool) async throws
    func updatePost(topicId: UInt64, postId: UInt64, raw: String, editReason: String?) async throws
    func deletePost(topicId: UInt64, postId: UInt64) async throws
    func recoverPost(topicId: UInt64, postId: UInt64) async throws
    func flagPost(topicId: UInt64, postId: UInt64, flagTypeId: UInt32, message: String?) async throws
    func ensureFlagTypes(topicId: UInt64) async throws
    func createBookmark(topicId: UInt64, bookmarkableId: UInt64, bookmarkableType: String, name: String?, reminderAt: String?, autoDeletePreference: Int32?) async throws
    func updateBookmark(topicId: UInt64, bookmarkId: UInt64, name: String?, reminderAt: String?, autoDeletePreference: Int32?) async throws
    func deleteBookmark(topicId: UInt64, bookmarkId: UInt64) async throws
    func setNotificationLevel(topicId: UInt64, level: Int32) async throws
    func updateTopic(topicId: UInt64, title: String, categoryId: UInt64, tags: [String]) async throws
    func acceptSolution(topicId: UInt64, postId: UInt64, accepted: Bool) async throws
    func reportTimings(topicId: UInt64, topicTimeMs: UInt32, timings: [UInt32: UInt32]) async -> Bool
    func reset()

    func snapshot(for topicId: UInt64) -> TopicDetailUiSnapshot? { snapshots[topicId] }
}

final class FireTopicDetailSnapshotSink: TopicDetailObserver, @unchecked Sendable {
    func onSnapshot(snapshot: TopicDetailUiSnapshot) {
        Task { @MainActor in store.apply(snapshot) }
    }
}
```

`apply`：若 `generation` 不旧于已应用值，替换 `snapshots[id]`；若 `homeRowPatch != nil`，调 `FireAppViewModel.applyHomeRowCountPatch`。不合并行。

`FireSessionStore.openTopicDetail` / `cancelTopicDetailHttp` / `closeAllTopicDetailSessions` 标为 `nonisolated`：只碰 `core` UniFFI，供 `@MainActor` 的 `FireTopicDetailStore` 同步拿到 handle，不进 session actor 队列。

`FireHomeFeedStore.applyHomeRowCountPatch` 替换 `patchTopicCounts`。同一 PR 删除 `patchedTopicRow` 与 `patchTopicCounts`。`FireTopicDetailModalRouter.presentBookmarkEditor` 的话题详情 `onReload` 不再调用 `loadTopicDetail`；保存和删除改走 store 的 create / update / delete bookmark。`presentTopicBookmarkEditor` / `presentPostBookmarkEditor` 同样改。

VC `buildCurrentFeedState` 改为读 `snapshot.rows`、`phase`、`hasMore`、`collectionRevision`、`scrollTarget`。`buildCurrentInteractionState` 只保留三个 expanded 集合。`mutating` / reply-context loading 来自行字段。`canWriteInteractions`、`baseURLString`、`minimumReplyLength` 仍从 session / bootstrap 读。Combine 从多个 revision 字典改成 `$snapshots`，用 `FireTopicDetailRevisionFingerprint`（`Equatable`）按 `collection` / `chrome` / `sidecar` / `interaction` 去重。本地展开仍走 `applyLocalInteractionSnapshot`，主线程，不经 Rust。

`FireTopicDetailRuntimeConfiguration` 丢掉 `detail: TopicDetailState?` 与 `postLookup`。builder 用行 DTO，再把本地 chrome 折进 token。禁止把 `contentToken` 或 `inPlaceUpdateToken` 设成裸的 Rust checksum。管道 `apply` 的三档判断不改。

分页协调器：`fireTopicDetailShouldLoadMore` 删除。过滤后的 `itemCount` / `visibleMaxItem` 经 `noteFilteredFeedTail` 上报。footer 仍 `loadMore`。可见楼层号仍由 `FireTopicDetailVisibilityCoordinator.publishIfChanged` 上报。

### 错误与线程

| 错误 | 会话行为 | Swift 话题详情 |
| --- | --- | --- |
| Network | 快照 `Failed` + 文案 | 展示 |
| CF challenge | 网络层已弹 WebView 并重试 | 无感知 |
| cookie healing | 网络层已重试 | 无感知 |
| StaleSessionResponse | 内部 force 再读一次 | 无感知 |
| LoginRequired | 同一代请求。成功则 `force_load` reload 一次，`track_visit` 不变 | 只展示。`applySession` 先 `attemptHostCookieResyncRecovery`，失败再 `attemptMidSessionHeadlessReauth`。不调用 `runReadPathLoginRecovery` |
| Http 429 | 网络层已退避 | 最终失败才展示 |
| 写失败 | 回滚乐观快照，`Err` 给 composer | `quickReplyError` 本地 |

禁止在主线程 `wait` UniFFI。`open` / `note_*` / `load_more` 是同步入队。写命令的 `async` 只 await 已在 runtime 上的 actor，Swift 侧在 `Task` 里调用。

## Phased Implementation

每阶段结束工作区可编译。阶段内不要长期双源。iOS 在 Android ViewModel 迁移之前达到「store 只有快照 + VC 只有本地 chrome」。

### Phase 1 — Rust 会话 + 兼容投影

新文件：

- `rust/crates/fire-models/src/topic_detail_ui.rs`
- `rust/crates/fire-core/src/core/topic_detail_session.rs`
- `rust/crates/fire-core/src/core/topic_detail_project.rs`
- `rust/crates/fire-uniffi-topics/src/session.rs`

改：

- `fire-models/src/lib.rs` 导出新类型
- `fire-core/src/core/mod.rs`：`topic_detail_source` 换成 `topic_detail_sessions`
- `fire-core/src/core/topics.rs`：`fetch_topic_detail_page` / `load_more_topic_posts` / `fetch_topic_detail_source_snapshot` 只转发 `load_topic_detail_*`，不调用 `Registry.open`。无 observer、无 MessageBus 订阅、无预取、无 owner
- `fire-core/src/core/messagebus.rs`：内部 listener 列表，poll 分发处（现有 host sender 旁边）再送一份
- `FireSessionRuntimeState` 持有 `ReadPathLoginRequest`。推送用的 `SessionSnapshot` 字段 `#[serde(skip)]`，不进 `snapshot_revision`。`restore_session_json` 清掉它。`SessionState::from_snapshot` 能看见推送副本。`FireSessionHandle::complete_read_path_login` 走 registry 叫醒 waiter
- `fire-core/src/core/mod.rs`：`request_read_path_login` / `complete_read_path_login`。不碰 `FireAuthRecoveryHint`
- `fire-store`：`topic_list_cache_list_pages`
- `fire-uniffi-topics/src/lib.rs`：`open_topic_detail`。旧 `fetch_topic_detail_source_snapshot` / `fetch_topic_detail_page` / `load_more_topic_posts` 把 query 原样委托给 `load_topic_detail_*`。不忽略 batch
- `fire-uniffi-topics/src/records.rs`：`TopicDetailUiSnapshotState::from_core` 与行记录。不写分支

iOS / Android 调用点不动。旧 RPC 仍返回原来的记录，并且仍遵守 query 的 batch、`force_load`、`track_visit`、`allow_suggested_unread_root`。

测试：

- `topics.rs` 现有树 / 游标单测保持，改 `super` 路径即可
- `tests/network.rs` 的自定义 batch（`initial_batch_size` 10、3、1，以及 cursor `batch_size == 10`）继续打 `FireCore::fetch_topic_detail_page` / `fetch_topic_detail_source_snapshot`，因为这两个方法就是 `load_topic_detail_*`。断言不变，包括 `fetch_topic_detail_page_auto_extends_to_first_unread_root`、`skips_unread_root_auto_extend_when_not_allowed`、全部 `fetch_topic_detail_source_snapshot_*`
- 新测：同一 owner 再 open 是替换不是第二个 observer；最后 `release` 取消订阅；`note_visible_posts` 在阈值内才 append；`note_filtered_feed_tail` 用过滤后的下标；`StaleSessionResponse` 只 force 一次且 `track_visit` 不变；乐观 like 失败回滚；滚动中已完成的 reload 在松手时直接推、不再请求；`WhenLastReadMissing` 在 `has_unread == false` 时清零；compat 调用不注册 observer、不订阅 MessageBus

`cargo test -p fire-core -p fire-uniffi-topics` 与 Android 现有编译是本阶段门槛。

### Phase 2 — iOS 改吃快照（一个 PR，结束时编译）

这是行为切换。不要先留 `topicDetails` 再合成快照。

顺序（同一 PR）：

1. 生成 UniFFI（现有 `native/ios-app/scripts/sync_uniffi_bindings.sh`）
2. 改 `FireTopicDetailStore` 为上一节签名。删除 `+Load` 里的合并 / 窗口 / 重试。`+Mutations` / `+Reactions` / `+Presence` 只留转发
3. `FireTopicDetailSnapshotSink` 放在 store 文件
4. 改 `FireTopicDetailPageState`、`FeedModels`、`RuntimeSnapshotBuilder`、`SnapshotAssembler`、`ViewController` 的 `buildCurrent*` 与 revision sink
5. `PaginationCoordinator` 改为 `noteFilteredFeedTail`；`VisibilityCoordinator` 回调改 `noteVisiblePosts`。删除 `fireTopicDetailShouldLoadMore`
6. `FireTopicInteractionService` 的话题写操作改 store 转发。`voteTopic` 不再 `refreshTopicDetailAfterMutation`
7. `FireAppViewModel.submitReply` / `updatePost` 去掉返回帖。`updateTopic` 改为会话命令，成功后仍 `refreshHomeFeedIfPossible(force: true)`，不再 `refreshTopicDetailAfterMutation`。`patchHomeTopicCounts` 改为 `applyHomeRowCountPatch`，并删除 `patchedTopicRow`。`handleMessageBusEvent` 去掉话题分支。`applySession` 看到新 generation 时先 `attemptHostCookieResyncRecovery(operation:)`，返回 false 再 `attemptMidSessionHeadlessReauth(operation:)`，然后 `complete_read_path_login`。不调用 `runReadPathLoginRecovery`。话题 store 的 `applySession` 只转发登出 / 短暂不可读
8. `presentBookmarkEditor`、`presentTopicBookmarkEditor`、`presentPostBookmarkEditor` 的 `onReload` 不再 `loadTopicDetail`。改调 create / update / delete bookmark。`presentPostEditor` 的 `onSaved`、`presentTopicEditor` 的 `onSaved`、`updateTopicNotificationLevel` 同样禁止 `loadTopicDetail(force: true)`，改为对应会话命令。对账是命令内部的 `reload(force_load: false, track_visit: false)`，必打网。去掉今天这第二发 `trackVisit: true` 是有意的。`recoveryOriginURL` 用 `open` 已经传入的 slug，不调用删掉的 `topicCloudflareRecoveryURL`
9. `performRefresh` 与 `onLoadTopicDetail`（`FireTopicDetailFeedCellFactory` 重试）改为 `open(bypass_cache: true, force_load: true, track_visit: true)`。这次记访问是有意的。`openAdvancedComposer` / `openQuoteComposer` 的 `onReplySubmitted` 不再 `loadTopicDetail`。引用回复 `submitReply(..., scrollToCreated: true)`，由会话把新帖楼层写成 `scroll_target`
10. 六个额外 store 构造改为使用 root store。含 `FireAppRoutePresentationTests` 里的临时 store
11. 详情路径停止调用 `FireSessionStore.fetchTopicDetailPage` / `loadMoreTopicPosts`

门槛：见 PR-B 审查清单。话题 store 不再以 `TopicDetailState` 为成员。

### Phase 3 — Android ViewModel（独立 PR，方法级）

`TopicDetailViewModel.kt`：

| 方法 | 动作 |
| --- | --- |
| `prepareForTopicLoad` | 换 topic id 时 `close` 上一个 owner，再 `open` 下一个。清本地展开与渲染缓存 |
| `loadTopicDetail` | `open(bypass_cache: true, force_load: true, track_visit: true)`。`allow_suggested_unread_root` 仍是 `targetPostNumber == null && _detail.value == null`。不要把 `bypass_cache` 留成 false，否则第二次打开会跳过今天这发 HTTP |
| `fetchTopicDetailPagePayload` / `applyFetchedPayload` / `mergeLoadMore` / `applyReactionUpdate` / `applyPollUpdate` | 删 |
| `refreshCurrentTopic` | 删。通知级别、改话题、书签、删帖、恢复改走会话命令。命令内部 `track_visit = false`、`force = false` 对账。禁止留下对 `fetchTopicDetailPage` 的调用 |
| `replacePost` | 删。乐观写入在 actor 内 |
| `maintainTopicDetailMessageBus` / `scheduleTopicDetailRefresh` / `refreshTopicDetailFromMessageBus` / `releaseTopicDetailMessageBus` / `drainDeferredMessageBusRefreshIfNeeded` | 删 |
| `loadMorePosts` / `loadMorePostsPage` | `load_more` |
| `scrollToPostWhenLoaded` / `hasLoadedPostNumber` | 删。滚动目标交给会话的窗口算法（`maxWindowSize = 200`，`nextRequestedRangeForUnresolvedTarget`）。不要在 Kotlin 再写 20 页循环（`TARGET_HYDRATION_PAGE_LIMIT`） |
| `setTopicDetailScrollInteractionActive` | `note_scroll_interaction` |
| `reloadTopicAiSummary` / `loadTopicAiSummaryIfNeeded` | 命令 / 删 |
| `toggleHeart` / `toggleReaction` / `votePoll` / `unvotePoll` / `toggleTopicVote` / `deletePost` / `recoverPost` / `updatePost` / 书签 / `setTopicNotificationLevel` / `updateTopic` | 会话命令 |
| `expandReplyThread` | 留本地 |
| `projectRows` / `postRow` / `searchMatches` / `usesBoostBarrage` | 输入改快照行。`uniqueTreeRows`、`postsById`、`postsForDetail`、`initialScrollTargetPostNumber` 删 |
| `getRenderContent` / `preloadRenderContent` | 改 `RenderDocumentHandle` |
| `onCleared` | `close`（只释放本屏 owner） |

`TopicRepository.fetchTopicDetailPage` / `loadMoreTopicPosts` 此 PR 不再被 ViewModel 调用，方法先留着，避免别的调用点断编译。`FireSessionStore.fetchTopicDetailPage` 同理。

### Phase 4 — 删除旧 RPC

两端都不再调用之后：

- 删 `FireTopicsHandle::fetch_topic_detail_source_snapshot`、`fetch_topic_detail_page`、`load_more_topic_posts`
- 删 FFI `TopicDetailSourceQueryState` 的 batch 字段，或整个 query 记录若无引用
- 删 Android `TopicRepository.fetchTopicDetailPage`、`loadMoreTopicPosts`、`fetchTopicDetailSourceSnapshot`
- 删 Android `FireSessionStore.fetchTopicDetailPage`、`loadMoreTopicPosts`、`fetchTopicDetailSourceSnapshot`
- 删 iOS `FireSessionStore.fetchTopicDetailPage`、`loadMoreTopicPosts`、`fetchTopicDetailSourceSnapshot`
- 删 `FireCore` 上这三个公开包装。`load_topic_detail_page` 仍是 `pub(crate)`，给测试和 actor 用，不是第二套逻辑
- 详情屏幕不再使用的 `TopicDetailState` 合成路径删除。其它屏幕若仍要单帖，继续用 `fetch_post`

## Architectural Notes

与 `fire-native-architecture.md` 的偏差要在实现时改文档，而不是改代码去迎合过期句子：

- §1.3 把 `topic_detail_feed` 写成 `FireAppCore` 全局推送边界。落地是每会话 observer。不要给 `StateObserver` 加第四个方法。
- §2.4 当前稳定边界仍是 session / topic list / notification center。本设计不改变这三条。
- §2.5 `StaleSessionResponse`「平台无感知」今天并未做到：`FireTopicDetailStore.loadTopicDetail` 仍 `case StaleSessionResponse` 后 `force` 重试。会话补上这一跳。
- §2.5 LoginRequired 写的是「展示失败，不自动 logout」。Headless 重登今天从话题 store 解析 `FireUniFfiError.LoginRequired` 进入。改成 `SessionSnapshot.read_path_login_request` 唤醒 `applySession`，话题详情不再解析错误。失败则快照停在 `LoginRequired`，不自动 logout。

三档更新必须保住（`2026-09-19-ios-topic-detail-local-updates.md`）。比较的是 Swift 组出来的 token，不是裸 Rust checksum：

1. layout token 不变且 in-place token 变：复用 + `applyVisibleNodeUpdates`。续赞停在这档（`reactions.is_empty()` 仍为 true 方向上的非空，like 只进 `interaction_checksum`）。
2. layout token 变且行可见：relayout。首枚反应翻转 `reactions.is_empty()`。正文展开、表情条、回复树展开、摘要展开由 Swift 折进 layout token，不要求 Rust checksum 变化。
3. 行身份集合变化（分页、展开回复树）：collection diff。展开回复树的身份变化来自 Swift 过滤，不是 Rust revision。`FireTopicDetailFeedInvalidationToken` 仍不含 `expandedPostTextIDs`。

`is_mutating` 只进表情 alpha，不禁用回复 / boost / overflow / 投票。chip 签名不含 mutating，避免打断 bounce。overflow 仍是 cell 本地，relayout 不得写回 `false`。

`FireTopicDetailWindowState`（`FireAppViewModelSupport.swift`）随窗口逻辑删除。`maxWindowSize = 200` 进会话私有窗口，不进 FFI。

Kyc `FaceSessionHost` 持有会话并在 `releaseSession` 拆掉。Fire 的对应物是 store 的 `close(ownerToken:)`，不是一个全局 `FireAppCore` 替身。`FireTopicsHandle` 继续从 `FireAppCore.topics()` 拿。

风险：

- 离开详情即丢会话。今天 `endTopicDetailLifecycle` 在首页仍可见时保留详情。按屏幕 refcount 后，返回同一话题会重新 `open`。只有 `bypass_cache == false` 且 source 已含目标楼才不打网。最后 owner 的 `close` 会拆掉会话。这是有意行为变化，避免首页可见集变成第二套保留策略。
- 多 store 若漏改，会各开一个 owner。`close` 只释放该 handle 记住的 owner，最后一个才拆会话。同一 token 再 open 是替换。Phase 2 仍把 `FireTopicDetailStore` 的公开 init 收成内部，只允许 root 构造。
- 兼容 RPC 若忽略 batch，`tests/network.rs` 里 batch 为 1/3/10 的 source snapshot 用例会按 40 失败，Android 若将来传入非 40 也会变。所以 compat 保留 query 批量。actor 自己的打开路径才用常量。
- 乐观表情与 MessageBus 刷新并发：actor 单写。刷新开始时若该帖 `is_mutating`，跳过覆盖该帖，等命令结束再对齐。
- observer 若在 Swift 主线程同步做全量快照构建会死锁或卡滚动。sink 只赋值 `snapshots`，重的 `buildSnapshot` 仍走现有 `Task.detached`。
- 首页 patch 在话题不在 `topicEntities` 时无效果。与今天相同。不要为此去拉首页。

## File Change Summary

| 文件 | 阶段 | 动作 |
| --- | --- | --- |
| `rust/crates/fire-models/src/topic_detail_ui.rs` | 1 | 新增快照与 home patch |
| `rust/crates/fire-models/src/lib.rs` | 1 | 导出 |
| `rust/crates/fire-core/src/core/topic_detail_session.rs` | 1 | 会话、registry、常量、命令 |
| `rust/crates/fire-core/src/core/topic_detail_project.rs` | 1 | 私有 source+tree -> 快照；compat -> `TopicDetailPage` |
| `rust/crates/fire-core/src/core/topics.rs` | 1 | source session 留私有；公开 fetch 变包装 |
| `FireSessionRuntimeState`、`SessionSnapshot`（`#[serde(skip)]`）、`SessionState` | 1 | `ReadPathLoginRequest` 不进信封、不抬 `snapshot_revision`。restore 时清掉。不改 `FireAuthRecoveryHint` |
| `rust/crates/fire-core/src/core/mod.rs` | 1 | registry；`request_read_path_login` / `complete_read_path_login` |
| `rust/crates/fire-store/src/lib.rs` | 1 | `topic_list_cache_list_pages` |
| `rust/crates/fire-core/src/core/messagebus.rs` | 1 | 内部 listener |
| `rust/crates/fire-uniffi-topics/src/session.rs` | 1 | Handle、observer 适配 |
| `rust/crates/fire-uniffi-topics/src/lib.rs` | 1 | `open_topic_detail`。旧 RPC 只转发 `load_topic_detail_*`，不 `Registry.open` |
| `rust/crates/fire-uniffi-topics/src/records.rs` | 1 | `from_core` 记录 |
| `rust/crates/fire-core/tests/network.rs` | 1 | 仍走公开 `fetch_*`，确认委托后断言不变 |
| `native/ios-app/App/ViewModels/FireAppViewModel.swift` | 2 | 去掉话题错误重试。`applySession` 走 cookie resync，失败再 headless。`updateTopic` 仍刷新首页 |
| `native/ios-app/App/Stores/FireTopicDetailStore*.swift` | 2 | 快照持有 + 转发 |
| `native/ios-app/App/TopicDetail/**` | 2 | 消费快照；管道留 |
| `native/ios-app/App/Services/FireTopicInteractionService.swift` | 2 | 写操作转发 |
| `native/ios-app/App/Stores/FireHomeFeedStore.swift` | 2 | `applyHomeRowCountPatch`。删除 `patchedTopicRow` / `patchTopicCounts` |
| `native/ios-app/App/Core/FireRootCoordinator.swift` | 2 | 仍拥有唯一 store |
| 六个额外 store 构造点 | 2 | 改用 root store |
| `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift` | 2 | 窗口断言删除或改读 Rust；UI 无关用例保留 |
| `native/ios-app/Tests/Unit/FireTopicDetailRuntimeTests.swift` | 2 | fixture 改快照行 |
| `docs/architecture/fire-native-architecture.md` §1.3 §2.4 §2.5 | 2 | 写成每会话 observer |
| `docs/architecture/2026-09-19-ios-topic-detail-local-updates.md` | 2 | 写明 Rust checksum 与 Swift 折入的本地 chrome |
| `TopicRepository.kt`、两端 `FireSessionStore` | 4 | 删除 `fetchTopicDetailPage`、`loadMoreTopicPosts`、`fetchTopicDetailSourceSnapshot` |
| `native/android-app/.../TopicDetailViewModel.kt` | 3 | 方法表 |
| `FireTopicsHandle` 三个分页方法 | 4 | 删除。含 `fetch_topic_detail_source_snapshot` |

## Key Decisions

- 话题详情是 `fire-uniffi-topics` 上的一个对象，不是新的 UniFFI crate，也不是全应用一个 session。
- 全局 `StateObserver` 不增加话题详情。
- Swift store 不做页合并、不算区间、不解析 `FireUniFfiError` 重试。
- 新会话的批量是常量 40/40/3/120。预取 10、前向 60、hydration 页 30、迭代 8、过滤后列表尾 5、回复上下文 20、可见 debounce 120ms、刷新 1.5s、presence 30s、请求超时 30s、窗口 200。旧 RPC 在 Phase 4 前仍尊重宿主 query 的批量。
- 用户「加载更多」是 `load_more`。楼层预取是 `note_visible_posts`。列表尾预取是 `note_filtered_feed_tail`，用过滤后的 item 下标。
- 点赞在 HTTP 前乐观更新。回复在 `create_reply` 返回后按 `applyCreatedReply` 插入并伸窗口，不插占位行。Swift 不改帖。
- 展开、草稿、键盘、搜索高亮、滚动偏移、overflow 留在 VC / cell，并折进 Swift token。
- 首页补丁是 `TopicHomeRowCountPatch`，无 `like_count`。未读三态对齐 `patchedTopicRow`，含 `lastRead == nil` 且 `hasUnreadPosts == false` 时清零。只在计数会变时发出。不广播 topic list。标题 / 分类 / 标签仍靠现有 `refreshHomeFeedIfPossible`。
- 旧 RPC 只转发 `load_topic_detail_*`，不进 `Registry.open`。无 observer、无订阅、无预取、无 owner。Android 早期运行时行为不变。
- `open` 的缓存短路和 query 的 `force_load` 是两位。`reload` 永远打网。对账用 `force_load = false`、`track_visit = false`。
- `close` / `release(topic_id, owner_token)` 只释放该 owner。
- 书签是 `create_bookmark` / `update_bookmark` / `delete_bookmark` 的薄包装，带 `bookmarkable_type` 与 `auto_delete_preference`。
- 详情状态只由屏幕 owner 保持。首页可见不再充当隐式 owner。
- 编辑 raw 用 `prepare_edit` 单次读取，不把 raw 放进每一行。

## Alternatives Considered

- 继续在 `FireTopicsHandle` 上加参数，让 Swift 少传 batch。拒绝。控制流仍在 Swift，违反 §1.1。
- 把话题快照塞进 `StateObserver`。拒绝。多话题会把全局 observer 变成第二总线，且与「分页不要广播全表」同一类问题。
- 一个进程级 `TopicDetailController` 仿 `FaceVerifySession` 包掉整个 App。拒绝。用户约束：只学模块内 API，Fire 多通道保持。
- 专用 `topic-detail` OS 线程 + 同步 `call`。拒绝。会把 UI 挂在 HTTP 上。Kyc 的帧回路不适用于帖子流。
- Swift 暂留 `TopicDetailState` 由快照反推。拒绝。那是第二真相源。
- 首页未读改由话题 stream 重算 `unreadPosts`。拒绝。今天的公式是清零或保留，重算会改产品语义，也超出首页范围。
- `notify_topic_list` 推一页被改过的列表。拒绝。`fetch_topic_list` 已写明宿主自己应用分页，广播会把一页当成全表。
- 展开回复树改成 Rust 命令。拒绝。该状态是本地 chrome，文档要求留在 Swift。
- Phase 2 双写 `topicDetails` 与快照直到 Android 完成。拒绝。iOS 必须先到达单源，双写会把合并逻辑留下。

## PR Plan

1. **PR-A Rust 会话与兼容 RPC。** Phase 1。iOS/Android 行为不变。审查点：actor 不阻塞；observer 不进 `StateObserver`；compat 无订阅、无预取、无 owner，且保留 batch / `force_load` / `track_visit` / `allow_suggested_unread_root`；`tests/network.rs` 自定义 batch 断言仍绿；`release` 只拆一个 owner。
2. **PR-B iOS 单源。** Phase 2。一个 PR，中间可以不编译，不拆双源的中间步。审查不通过，如果下面任一条成立：
   - `TopicDetailState` 仍是 store 成员
   - 详情路径仍 `switch` `FireUniFfiError` 来决定重试
   - `contentToken` 或 `inPlaceUpdateToken` 被赋成裸的 Rust checksum
   - `FireAppViewModel.updateTopic` 仍调用 `refreshTopicDetailAfterMutation`，或丢掉 `refreshHomeFeedIfPossible(force: true)`
   - `presentBookmarkEditor` / `presentTopicBookmarkEditor` / `presentPostBookmarkEditor` 的 `onReload`，或 `presentPostEditor` / `presentTopicEditor` 的 `onSaved`，或 `updateTopicNotificationLevel` 仍调用 `loadTopicDetail`
   - `performRefresh`、`onLoadTopicDetail`、`openAdvancedComposer.onReplySubmitted`、`openQuoteComposer.onReplySubmitted` 仍调用 `loadTopicDetail(force:)`。前两个必须是 `bypass_cache = true`、`force_load = true`、`track_visit = true`。后两个不得再拉页；引用回复必须 `scroll_to_created`
   - Android `open` 不是 `bypass_cache = true`、`force_load = true`、`track_visit = true`（`allow_suggested_unread_root` 除外，那条保持原公式）。这条在 PR-C 落地，PR-B 审查时对照契约表，避免 iOS 表和 Android 行各写一套
   - `patchedTopicRow` 还在
   - 详情路径仍调用 `fetchTopicDetailPage` / `loadMoreTopicPosts`
3. **PR-C Android ViewModel。** Phase 3。方法表含 `prepareForTopicLoad`、`scrollToPostWhenLoaded`、`refreshCurrentTopic`、`replacePost`。Repository 方法先留。PR 结束后 ViewModel 不得再调用 `fetchTopicDetailPage`。
4. **PR-D 删除旧 RPC。** Phase 4。删三个分页 FFI，以及两端 `FireSessionStore` 和 `TopicRepository` 上的 `fetchTopicDetailPage`、`loadMoreTopicPosts`、`fetchTopicDetailSourceSnapshot`。单独审查，便于回滚。

文档更新放在 PR-B（iOS 行为已变）和 PR-D（RPC 消失）。不要在 PR-A 把架构文档改成「Swift 已不再合并」——那时 Swift 还在合并。

## Open Questions

- `fetchReactionUsers` / `fetchTopicVoters` 是 sheet 列表，不是帖树。保持一次性 RPC。若产品要它们也进快照，另开任务。
- 被动掉登录时 `applySession` 里已有的 `scheduleMidSessionReauthAfterPassiveDeauth` 保持原样。它看的是 readiness 从已登录变成未登录，和 `ReadPathLoginRequest` 不是一条路径。不要把二者合成一个 hint。

## Goals & Non-Goals

目标：

- Rust 是话题详情唯一数据源和唯一逻辑处理器。
- Swift 只渲染 UI 快照，外加纯本地 chrome。
- 一个会话对象，命令进、快照出，含后台刷新。
- 源游标、stream、批量、未读自动延伸、乐观对账、预取、MessageBus 刷新策略全部私有。
- iOS 先于 Android 到达该形状。每阶段可编译。旧 RPC 最后删除。
- 三档就地更新行为保持。
- 首页行计数仍然正确，且首页 store 不再做未读比较。

非目标：

- 合并 UniFFI 通道，或做全应用单一 session。
- 改首页、搜索、通知、聊天的架构。
- 重做 Texture 管道、动画、overflow 的 cell 本地状态。
- 把展开正文 / 回复树 / 表情条 / 草稿 / 键盘 / 搜索高亮放进 Rust。
- 在话题详情增加新的平台决策回调。
- 用 `FrameTick`、专用线程或同步 HTTP 阻塞 UI。
- 从 stream 重算首页未读条数。
- Phase 1–2 修改 Android ViewModel 行为。
