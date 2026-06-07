# Topic Detail API Consolidation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Fire 贴文详情收口到“原始网络数据源分页”和“树状业务呈现”严格分离的 Rust 权威模型：底层分页必须按 `post_stream.stream` 的原始顺序和树化前的最后 `postId` 批量拉取，树状 thread 呈现作为上层业务处理保留并继续成为 Fire 双端特色。

**Architecture:** Rust Core 同时拥有两层职责，但必须显式分层。第一层是 raw source：负责 `/t/{id}.json`、`/t/{id}/posts.json?post_ids[]=...`、原始 `post_stream.stream`、source cursor、deep-link anchor 和批量拉取。第二层是 presentation：在已加载 raw posts 基础上生成树状 timeline rows、depth、parent、root grouping 和 UI 所需摘要。iOS / Android 只拥有路由、滚动、可见性上报、原生渲染、平台挑战 WebView 和少量 targeted hydration；平台不得以树状 row 或 root reply 反向驱动网络分页。

**Tech Stack:** Rust + openwire + UniFFI + tokio / Swift + UIKit + Texture / Kotlin + RecyclerView + androidx

**Design Inputs:**
- `docs/knowledge/api-overview.md`
- `docs/knowledge/api/03-topics.md`
- `docs/knowledge/api/10-presence-and-categories.md`
- `docs/knowledge/api/12-messagebus.md`
- `docs/architecture/fire-native-architecture.md`
- `rust/crates/fire-models/src/topic_detail.rs`
- `rust/crates/fire-core/src/core/topics.rs`
- `rust/crates/fire-core/src/core/topic_feed.rs`
- `rust/crates/fire-core/src/core/interactions.rs`
- `rust/crates/fire-core/src/core/presence.rs`
- `rust/crates/fire-uniffi-topics/src/lib.rs`
- `rust/crates/fire-uniffi-topics/src/records.rs`
- `native/ios-app/App/Stores/FireTopicDetailStore.swift`
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`
- `native/android-app/src/main/java/com/fire/app/data/repository/TopicRepository.kt`
- `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`
- `references/fluxdo/lib/services/discourse/_topics.dart`
- `references/fluxdo/lib/providers/topic_detail/_loading_methods.dart`
- `references/fluxdo/lib/providers/topic_detail/_filter_methods.dart`
- `references/fluxdo/lib/providers/topic_detail/_post_updates.dart`
- `references/fluxdo/lib/providers/message_bus/topic_channel_provider.dart`

---

## Audit Corrections (2026-06-06)

本计划基于当前 Fire 与 FluxDO 源码审查结果，以下事项为**强约束**：

- `docs/knowledge/api-overview.md` 仍把贴文详情概括成 `GET /t/{topicId}.json` + `GET /t/{topicId}/posts.json`，这只能表达底层端点，不再等于 Fire 当前权威读模型。
- Fire 当前双端主详情页的真实入口已经是 Rust `fetch_topic_screen()` + `fetch_topic_response_page()`，而不是平台直接拼 `/t/{id}/{postNumber}.json` 或 `getPostsByNumber(...)` 窗口。
- FluxDO 对 Fire 的参考价值主要是端点清单、筛选参数、MessageBus 事件类型、Presence/timings/AI summary 等侧边能力，不是其 host-managed 详情窗口架构本身。
- Fire 当前 Rust 主路径确实在用 top-level root id 驱动主分页：`fetch_topic_screen()` 先抽 `root_stream_ids`，后续 `load_root_branch_into_session(root_post_id, ...)` 再用 `fetch_post_reply_ids(root_post.id)` 和 descendant `post_ids[]` 拉数据。这条路径把业务树结构反向拿来驱动底层网络分页，不符合本计划目标。
- 正确的底层分页边界应该来自树化前的原始 `post_stream.stream`。无论最终 UI 是否展示为树状 thread，网络层都必须依据原始流中的最后已加载 `postId` / `stream offset` 继续批量拉取下一段 raw posts。
- 一次用户触发的“加载更多”不必严格等于一次网络批量请求。如果某一批 raw posts 只给现有 root 补充 descendants、没有给树状视图带来新的 root-level 可见进展，那么同一次用户动作内应自动继续拉下一批，直到出现新的 root post、source exhaust、达到自动批量上限或发生错误。
- `TopicDetailFeedSnapshot` / processed feed 路径在 Rust 仍存在，但 iOS/Android 主详情页都不依赖它；本计划要求删除这条并行读链路，而不是继续以 retained 或 inactive 名义保留。
- `fetch_topic_detail()` / `fetch_topic_detail_initial()` 仍通过 UniFFI 暴露，但当前 iOS/Android 主详情页没有依赖它们作为 authoritative surface；本计划要求把它们收口为内部底层接口或直接删除外部暴露，不允许继续维持“看起来也能当主接口”的兼容面。
- `forceLoad` 查询参数已经存在于 Fire 当前 `TopicDetailQuery` / `TopicScreenQuery` 实现中；如果它仍有运行时意义，就必须补文档并进入契约说明；如果没有意义，后续必须删除，而不是继续保持隐式行为。
- 回复上下文 API 与主阅读面 API 必须分层：`fetch_topic_posts`、`fetch_post_reply_ids`、`fetch_post_reply_history`、`fetch_post_replies` 只用于 targeted context，不参与主详情页分页。
- MessageBus 在 API 层的职责是 topic/reaction/poll/presence 事件和失效信号，不是让 host 回退到逐帖 `fetch post` patch 模式重新拼读模型。
- Presence、topic timings、AI summary 都是主详情页成功渲染之后的 sidecar capability，不应被塞进 `TopicScreen` 主载荷里。

## Target Contract

### Raw Source Contract

```text
TopicDetailSourceQuery {
  topic_id,
  target_post_number?,
  track_visit,
  force_load,
  initial_batch_size
}

  -> TopicDetailSourceSnapshot {
       header,
       body,
       raw_stream_ids,
       loaded_posts,
       source_cursor?,
       focused_post_number?
     }

TopicSourceCursor {
  topic_id,
  last_loaded_post_id,
  next_stream_offset,
  batch_size
}

LoadMoreTopicPostsQuery { cursor }
  -> TopicDetailSourceAppend {
       appended_posts,
       next_source_cursor?
     }
```

### Tree Presentation Contract

```text
fetch_topic_detail_page(TopicDetailSourceQuery)
  -> TopicDetailPage {
       source_snapshot,
       tree_presentation
     }

TopicTreePresentation {
  original_post_id,
  original_post_number,
  reply_rows,
  total_loaded_post_count,
  visible_root_post_numbers,
  gained_new_root_progress
}

TopicTreeRow {
  post_id,
  post_number,
  root_post_number,
  parent_post_number?,
  depth,
  sibling_index,
  is_last_sibling,
  descendant_count
}
```

树状 depth、parent、root grouping、thread 展示都属于这一层。它可以继续作为 Fire 双端特色存在，但不得反向决定下一次网络分页边界。完整 `TopicPost` 只通过 source snapshot 传输，tree presentation 只携带 post id / number 和展示元数据。

### Targeted Context Contract

这些 API 只允许服务局部上下文，不得再被提升为主详情页分页入口：

- `fetch_topic_posts(topic_id, post_ids[])`
- `fetch_post_by_number(topic_id, post_number)`
- `fetch_post_reply_ids(post_id)`
- `fetch_post_reply_history(post_id)`

### Sidecar Contract

- `report_topic_timings(input)`
- `bootstrap_topic_reply_presence(topic_id, owner_token)`
- `update_topic_reply_presence(topic_id, active)`
- `fetch_topic_ai_summary(topic_id, skip_age_check)`
- MessageBus `/topic/{topicId}`、`/topic/{topicId}/reactions`、poll channel、`/presence/discourse-presence/reply/{topicId}`

## Proposed Data Structures

### Rust Internal Runtime

这些结构只存在于 Rust Core 内部，不直接穿过 UniFFI：

```rust
struct TopicDetailSourceSession {
    topic_id: u64,
    session_id: u64,
    session_epoch: u64,
    header: TopicHeader,
    body_post_id: u64,
    body_post_number: u32,
    focused_post_number: Option<u32>,
    raw_stream_ids: Vec<u64>,
    posts_by_id: HashMap<u64, TopicPost>,
    post_id_by_number: HashMap<u32, u64>,
    loaded_ranges: Vec<TopicLoadedRange>,
    next_stream_offset: usize,
    last_loaded_post_id: Option<u64>,
    source_exhausted: bool,
}

struct TopicLoadedRange {
    start_offset: usize,
    end_offset_exclusive: usize,
    first_post_id: u64,
    last_post_id: u64,
}

struct TopicLoadMorePolicy {
    batch_size: u16,
    max_auto_batches_per_gesture: u8,
    max_auto_posts_per_gesture: u16,
    require_new_root_progress: bool,
}
```

字段约束：

- `raw_stream_ids` 是网络 source 真相，直接来自底层 detail `post_stream.stream`
- `posts_by_id` / `post_id_by_number` 只表示“已经拉到手的 raw posts”，不编码树结构
- `loaded_ranges` 反映 raw stream 哪些 offset 已被装载，便于去重和调试
- `next_stream_offset` / `last_loaded_post_id` 是唯一分页边界
- `source_exhausted` 只由 `next_stream_offset >= raw_stream_ids.len()` 得出
- 树状 root、depth、parent、descendant_count 不进入 source session

### UniFFI / Shared Records

这些结构是平台可见的稳定契约：

```rust
pub struct TopicDetailSourceQuery {
    pub topic_id: u64,
    pub target_post_number: Option<u32>,
    pub track_visit: bool,
    pub force_load: bool,
    pub initial_batch_size: u16,
    pub load_more_batch_size: u16,
    pub max_auto_batches_per_gesture: u8,
    pub max_auto_posts_per_gesture: u16,
}

pub struct TopicDetailSourceSnapshot {
    pub header: TopicHeader,
    pub body: TopicBody,
    pub raw_stream_ids: Vec<u64>,
    pub loaded_posts: Vec<TopicPost>,
    pub loaded_ranges: Vec<TopicLoadedRangeState>,
    pub source_cursor: Option<TopicSourceCursor>,
    pub source_exhausted: bool,
    pub focused_post_number: Option<u32>,
}

pub struct TopicSourceCursor {
    pub topic_id: u64,
    pub session_id: u64,
    pub next_stream_offset: u32,
    pub last_loaded_post_id: Option<u64>,
    pub batch_size: u16,
}

pub struct TopicDetailSourceAppend {
    pub appended_posts: Vec<TopicPost>,
    pub loaded_ranges: Vec<TopicLoadedRangeState>,
    pub source_cursor: Option<TopicSourceCursor>,
    pub source_exhausted: bool,
}

pub struct TopicTreePresentation {
    pub original_post_id: u64,
    pub original_post_number: u32,
    pub reply_rows: Vec<TopicTreeRow>,
    pub total_loaded_post_count: u32,
    pub visible_root_post_numbers: Vec<u32>,
    pub gained_new_root_progress: bool,
}

pub struct TopicTreeRow {
    pub post_id: u64,
    pub post_number: u32,
    pub root_post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u16,
    pub sibling_index: u16,
    pub is_last_sibling: bool,
    pub descendant_count: u32,
}

pub enum TopicLoadMoreStopReason {
    GainedVisibleRootProgress,
    SourceExhausted,
    MaxAutoBatchesReached,
    MaxAutoPostsReached,
    RequestFailed,
}

pub struct TopicLoadMoreOutcome {
    pub source_snapshot: TopicDetailSourceSnapshot,
    pub tree_presentation: TopicTreePresentation,
    pub chained_batches: u8,
    pub chained_posts: u16,
    pub stop_reason: TopicLoadMoreStopReason,
}
```

字段约束：

- `TopicDetailSourceSnapshot` 是 raw-source 状态快照，不包含预先树化的 rows
- `TopicTreePresentation` 是 source snapshot 的派生结果，可重复构建；跨 UniFFI 只返回 slim row 元数据，不重复携带 `TopicPost`
- `gained_new_root_progress` 只用于判定本次用户手势是否继续自动拉下一批，不代表 `hasMore`
- `TopicLoadMoreOutcome` 把“source 是否到底”和“本次是否带来新的 root 进展”显式分开

### Platform Page State

iOS store / Android ViewModel 应持有的状态建议统一为：

```text
TopicDetailPageState
  sourceSnapshot: TopicDetailSourceSnapshot
  treePresentation: TopicTreePresentation
  loadMoreState:
    isLoading
    stopReason?
    chainedBatches
    chainedPosts
  anchorState:
    targetPostNumber?
    pendingScrollPostNumber?
  sidecars:
    aiSummary?
    presenceUsers[]
    timingState
```

平台约束：

- 平台只缓存 `sourceSnapshot` 和 `treePresentation`
- 平台不持有独立的 root-page cursor、branch cursor、root reply ids 分页状态
- 平台可做 render diff、scroll anchor、visible-post timing，但不决定下一批网络拉什么
- iOS / Android 的树状显示差异只能体现在 presentation consume 层，不能倒灌 source 层

## Structure Migration Map

### Public Contract Mapping

| Current type / field | Current meaning | New home | Action |
|---|---|---|---|
| `TopicScreenQuery` | 主详情读取 + root-page 分页入口 | `TopicDetailSourceQuery` | Rename + semantic rewrite |
| `TopicScreen.header` | 主题元数据 | `TopicDetailSourceSnapshot.header` | Move |
| `TopicScreen.body` | 主贴 | `TopicDetailSourceSnapshot.body` | Move |
| `TopicScreen.response.rows` | 已树化的回复行 | `TopicTreePresentation.reply_rows` | Move to presentation layer |
| `TopicScreen.response.focused_post_number` | deep-link 命中信息 | `TopicDetailSourceSnapshot.focused_post_number` | Move |
| `TopicResponseCursor.next_root_offset` | root 分页偏移 | none | Delete |
| `TopicResponseCursor.next_branch_offset` | branch 分页偏移 | none | Delete |
| `TopicResponseCursor.page_size` | root page size | `TopicSourceCursor.batch_size` | Replace semantics |
| `TopicResponseCursor.row_page_size` | 行数预算 | none | Delete |
| `TopicResponsePageQuery` | 基于 root/branch 的下一页请求 | `LoadMoreTopicPostsQuery` | Replace |
| `TopicResponsePage.rows` | 本次树化行增量 | `TopicLoadMoreOutcome.tree_presentation.reply_rows` | Replace |
| `TopicResponsePage.next_cursor` | root/branch next cursor | `TopicDetailSourceAppend.source_cursor` | Replace |
| `TopicResponsePage.total_root_count` | root 总数 | none | Delete unless future diagnostics explicitly require |
| `TopicResponsePage.loaded_root_count` | 已加载 root 数 | none | Delete |
| `TopicResponsePage.total_response_count` | 回复总数 | `TopicDetailSourceSnapshot.raw_stream_ids.len() - 1` or `header.reply_count` | Derive, do not carry dedicated field |
| `TopicResponseRow.root_post_number` | 树展示根节点 | `TopicTreeRow.root_post_number` | Keep in presentation only |
| `TopicResponseRow.parent_post_number` | 树展示父节点 | `TopicTreeRow.parent_post_number` | Keep in presentation only |
| `TopicResponseRow.depth` | 树展示深度 | `TopicTreeRow.depth` | Keep in presentation only |
| `TopicResponseRow.descendant_count` | 树展示摘要 | `TopicTreeRow.descendant_count` | Keep in presentation only |

### Rust Internal Mapping

| Current runtime structure | Problem | New structure | Action |
|---|---|---|---|
| `FireTopicResponseRuntime` | 名称和职责绑定 root-response 分页 | `FireTopicDetailSourceRuntime` | Rename + rewrite |
| `TopicResponseSession` | 把 source、root、branch、presentation 混在一起 | `TopicDetailSourceSession` | Replace |
| `TopicBranchIndex` | 为 root-driven 分页服务 | none | Delete |
| `TopicResponseNode` | 为 branch tree index 服务 | none as stored runtime; compute transiently in presentation build | Delete persistent runtime form |
| `BranchLoadRequest` | root-level batch planning | none | Delete |
| `TopicResponsePageLoadRequest` | root/branch page load input | `TopicSourceBatchLoadRequest` if needed internally | Replace |
| `branch_reply_ids_by_root_id` | root->descendant source cache | none | Delete |
| `branch_by_root_id` | root->presentation cache | none persistent; recompute presentation from loaded raw posts | Delete |

### Platform State Mapping

| Current platform state | New state | Action |
|---|---|---|
| iOS `topicScreens[topicId]` | `sourceSnapshots[topicId]` + `treePresentations[topicId]` | Split |
| iOS `topicResponseRowsByTopic` | `treePresentations[topicId].replyRows` | Replace |
| iOS `topicResponseCursorsByTopic` | `sourceCursorsByTopic` | Replace |
| Android `screen` | `sourceSnapshot` + `treePresentation` | Split |
| Android `responseRows` | `treePresentation.replyRows` | Replace |
| Android `cursor` | `sourceCursor` | Replace |

## Explicit Cleanup / Delete List

以下内容不是“可以考虑清理”，而是本计划实现过程中要明确删除的对象。

### Rust Models / FFI

- `TopicScreenQuery`
- `TopicScreen`
- `TopicResponseCursor`
- `TopicResponsePageQuery`
- `TopicResponsePage`
- `TopicResponseRow`
- `TopicScreenQueryState`
- `TopicScreenState`
- `TopicResponseCursorState`
- `TopicResponsePageQueryState`
- `TopicResponsePageState`
- `TopicResponseRowState`
- `TopicDetailFeedQueryState`
- `TopicDetailFeedSnapshotState`
- `TopicDetailFeedItemState`
- `TopicDetailCursorState`
- `TopicDetailLoadedRangeState` 中仅为旧 feed cursor 服务的字段定义，如果与新 source range 设计不兼容则重做

### Rust Core Root-Driven Pagination Logic

- `TopicResponseSession`
- `TopicBranchIndex`
- `TopicResponseNode`
- `BranchLoadRequest`
- `TopicResponsePageLoadRequest`
- `roots_needed_for_response_page(...)`
- `assemble_topic_response_page(...)`
- `build_branch_index(...)`
- `append_children_preorder(...)`
- `root_stream_ids_from_top_level_posts(...)`
- `root_stream_ids_including_focus_root(...)`
- `initial_topic_response_page_size(...)`
- `load_root_branch_into_session(...)`
- `fetch_topic_response_page(...)` 现有 root/branch 语义实现
- 所有 `branch_reply_ids_by_root_id` / `branch_by_root_id` / `root_stream_ids` 持久状态

### Platform Convenience Surfaces

- iOS `FireSessionStore.fetchTopicDetail(query:)` 作为主详情入口的使用
- iOS `FireSessionStore.fetchTopicDetailInitial(query:)`
- iOS `FireSessionStore.fetchTopicDetail(topicID:trackVisit:)`
- iOS `FireSessionStore.loadTopicDetailFeed(...)`
- iOS `FireSessionStore.refreshTopicDetailFeed(...)`
- iOS `FireSessionStore.cachedTopicDetailFeed(...)`
- Android `FireSessionStore.fetchTopicDetail(...)`
- Android `FireSessionStore.fetchTopicDetailInitial(...)`
- Android / iOS 任何仍把 `TopicScreen` / `TopicResponsePage` 当主详情权威契约的 wrapper

### Platform State / Logic To Remove

- iOS `topicResponseRowsByTopic`
- iOS `topicResponseCursorsByTopic`
- iOS 任何以 response row / root row 判断下一次要拉哪批网络数据的逻辑
- Android `responseRows` 作为 source state 的职责
- Android `cursor` 中任何 root/branch 语义
- 双端任何基于 root-level row 可见性决定底层 source batch 边界的逻辑

### Optional Deletion If No Independent Product Need Remains

这些调用若只剩兼容用途，应在同一轮实现里删除，而不是继续以 fallback 名义保留：

- `fetch_post_replies(...)`
- reply-context 中任何 “reply-id tree 失败后退回 `/replies.json`” 的逻辑

### Explicit Non-Goals For This Rollout

- 不恢复 FluxDO 风格的 host-managed `getPostsByNumber(...)` 页面窗口逻辑。
- 不再让 root reply ids、tree rows、root page 概念驱动底层网络分页。
- 删除 processed feed snapshot 及其平台暴露，不保留 inactive / retained / migration 名义的并行读链路。
- 删除平台层 stringly `filter` / `username_filters` / `filter_top_level_replies` 详情页窗口逻辑，不保留兼容入口。
- 不为了筛选模式再引入一套与主详情不同的主读取模型；若未来需要筛选详情页，应新增 typed Rust `TopicScreenFilter` 合约。

---

### Task 1: Docs — Rewrite topic detail API docs to match the current runtime

**Files:**
- Modify: `docs/knowledge/api-overview.md`
- Modify: `docs/knowledge/api/03-topics.md`
- Modify: `docs/knowledge/api/10-presence-and-categories.md`
- Modify: `docs/knowledge/api/12-messagebus.md`
- Modify: `docs/architecture/fire-native-architecture.md`
- Modify: `native/ios-app/README.md`
- Modify: `native/android-app/README.md`

- [ ] **Step 1: 修正 topic detail 文档入口**

把 `api-overview` 中“话题详情”从旧摘要：

```text
GET /t/{topicId}.json
GET /t/{topicId}/posts.json
POST /topics/timings
GET /presence/get
POST /presence/update
```

改成分层描述：

```text
Primary source: raw stream + source cursor + batched post_ids loading
Presentation: tree rows built from loaded raw posts
Sidecar: timings / presence / AI summary / MessageBus
```

- [ ] **Step 2: 在 `03-topics.md` 明确 primary vs low-level**

保留底层端点章节，但新增一节 “Fire authoritative topic-detail contract”，明确：

- `GET /t/{id}.json` 只是底层原始 detail 端点
- `post_stream.stream` 是底层分页真相来源
- `GET /t/{topicId}/posts.json` 主路径只按 raw stream slice + `post_ids[]` 批量拉取
- 树状 rows 是对 loaded raw posts 的业务加工结果
- `post_number` 深链只影响初始 anchor，不再定义主分页模型

- [ ] **Step 3: 补齐 Fire-specific query knobs**

当前运行时存在但文档未写清的契约必须显式记录：

- `initial_batch_size`
- `last_loaded_post_id`
- `next_stream_offset`
- `target_post_number`
- `forceLoad` 的现状、适用场景和后续去留决策

- [ ] **Step 4: 把 Presence / timings / MessageBus 从“主详情载荷”中剥离**

在 `10-presence-and-categories.md` 和 `12-messagebus.md` 明确：

- Presence 是 sidecar，不参与主详情页首屏数据 shape
- timings 是后台静默写路径
- MessageBus topic/reaction/poll/presence 是失效与事件信号，不是主详情读模型

- [ ] **Step 5: 统一 README 描述**

iOS / Android README 都要保持同一结论：

- authoritative source path = initial detail + batched `post_ids[]` append
- authoritative presentation path = tree rows built from loaded raw posts
- targeted context path = reply ids/history/posts
- AI summary / presence / timings 为独立 sidecar

---

### Task 2: Rust + UniFFI — Replace root-based cursor pagination with raw source pagination

**Files:**
- Modify: `rust/crates/fire-models/src/topic_detail.rs`
- Modify: `rust/crates/fire-uniffi-topics/src/lib.rs`
- Modify: `rust/crates/fire-uniffi-topics/src/records.rs`
- Modify: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`

- [ ] **Step 1: 在 model / UniFFI 引入 source 与 presentation 的分层结构**

新增或重构为两层契约：

- `TopicDetailSourceQuery`
- `TopicDetailSourceSnapshot`
- `TopicLoadedRangeState`
- `TopicSourceCursor`
- `LoadMoreTopicPostsQuery`
- `TopicDetailSourceAppend`
- `TopicDetailPage`
- `TopicTreePresentation`
- `TopicTreeRow`
- `TopicLoadMoreStopReason`
- `TopicLoadMoreOutcome`

`TopicDetailQuery` 若继续存在，只允许作为底层 raw endpoint contract，不再承担主详情页分页语义。

- [ ] **Step 2: 删除平台 session store 上的误导性 convenience surface**

当前以下方法虽然存在，但并非主详情页真实入口：

- iOS `fetchTopicDetail(topicID:trackVisit:)`
- iOS `loadTopicDetailFeed(...)` / `refreshTopicDetailFeed(...)` / `cachedTopicDetailFeed(...)`
- Android `fetchTopicDetail(...)` / `fetchTopicDetailInitial(...)`

本阶段要求：
- 迁移任何剩余调用方后，直接移除平台侧 public wrapper
- 不允许通过重命名、注释或 legacy 标签继续把 dead surface 留在公开 API 上

- [ ] **Step 3: 删除 `TopicResponseCursor` / root-page 语义的 FFI 与平台暴露**

以下语义不再作为主详情公开契约存在：

- `next_root_offset`
- `next_branch_offset`
- `root_page_size`
- `row_page_size`
- 任何以 root page 为网络分页单位的 cursor

如果删除过程中发现隐藏 consumer：
- 先迁移 consumer 到 raw source cursor + tree presentation
- 同一任务内完成删除
- 不允许以 migration surface、internal fallback、retained path 的名义继续保留

- [ ] **Step 4: 对照 `Explicit Cleanup / Delete List` 勾销 public dead surface**

本步骤结束前必须明确核对：

- Rust Models / FFI 下的 dead types 是否已删
- Platform Convenience Surfaces 下的 wrappers 是否已删
- 旧 root-page cursor 语义是否已从 public API 消失

未删除项必须记录具体 blocker 和所属文件，不允许默认保留。

- [ ] **Step 5: 重新生成并校验绑定**

如果 FFI surface 发生变更：

Run: `native/ios-app/scripts/sync_uniffi_bindings.sh`

Expected: Swift/Kotlin 绑定与 Rust surface 一致

---

### Task 3: Rust — Separate raw-source batching from tree assembly

**Files:**
- Modify: `rust/crates/fire-core/src/core/topics.rs`
- Test: `rust/crates/fire-core/tests/network.rs`
- Test: `rust/crates/fire-core/src/core/topics.rs` unit tests

- [ ] **Step 1: 删除 root-driven 主分页**

当前以下主分页行为需要移除：

- 从 `filter_top_level_replies=true` 提取 `root_stream_ids`
- 用 `roots_needed_for_response_page(...)` 决定下一次网络拉取
- 对每个 root 调 `fetch_post_reply_ids(root_post.id)` 再按 branch 补 descendant ids

这些都属于“业务树结构反向驱动网络 source”的错误方向。

- [ ] **Step 2: 删除 root/branch runtime 持久状态**

本步骤要求一起删除：

- `root_stream_ids`
- `branch_reply_ids_by_root_id`
- `branch_by_root_id`
- `TopicBranchIndex`
- `TopicResponseNode`

若 presentation build 仍需要短暂树索引，只允许在单次构建过程中临时创建，不得常驻 source runtime。

- [ ] **Step 3: 以 raw stream 建立 source session**

新的 source session 至少要持有：

- `raw_stream_ids`，直接来自 detail `post_stream.stream`
- `loaded_posts_by_id`
- `loaded_stream_offsets` 或等价 loaded range
- `last_loaded_post_id`
- `next_stream_offset`
- deep-link anchor metadata

主分页必须只从 `raw_stream_ids` 的下一个 offset 继续切 batch，并通过 `fetch_topic_posts(post_ids[])` 拉取。

- [ ] **Step 4: 初始加载与 deep link 仍可保留 targeted anchor，但不改变主分页模型**

要求：

- 初始详情仍可通过 `/t/{id}.json` 或 `/t/{id}/{postNumber}.json` 获取 anchor 附近首包
- deep link 可额外确保目标 post 所在局部窗口被 hydration
- 但首包之后的继续加载，一律回到 `raw_stream_ids` 线性 batch append
- 不允许因为 deep link target 落在某个 root branch，就把后续分页切换成按 root 拉

- [ ] **Step 5: 将单次用户 load more 定义成“可见进展驱动”的自动批量循环**

对用户来说，一次上拉加载应该尽量带来可见进展。推荐规则：

```text
user load more
  -> load source batch #1
  -> rebuild tree presentation
  -> if no new visible root-level progress and source not exhausted:
       auto load source batch #2
  -> repeat until:
       new root-level progress
       or source exhausted
       or max_auto_batches reached
       or max_auto_posts reached
       or request fails
```

其中：

- `source exhausted` 只由 raw stream cursor 判定
- `new root-level progress` 只决定这次用户动作是否继续自动拉下一批，不决定底层 `hasMore`
- 自动批量循环属于 Rust source/presentation orchestration，不下放平台各自发明

- [ ] **Step 6: 将树状 thread 变成 source 之上的纯业务装配**

保留 Fire 的树状特色，但它只能消费 loaded raw posts：

- 根据 `reply_to_post_number` / post order 构建 tree rows
- 生成 `depth` / `parent_post_number` / root grouping
- 允许 partial-load 下存在未闭合 thread
- 不允许 tree row / root row 反向决定下一次 source batch

- [ ] **Step 7: 强化 tree assembly 健壮性**

补测试覆盖：

- duplicate post ids
- reply-to-self
- missing parent
- reply cycle
- orphan descendants
- partial descendant hydration

要求 tree assembly 在这些异常数据下仍能产出稳定 preorder rows，而不是把错误兜回平台。

- [ ] **Step 8: 锁定 source cursor 失效、自动批量和去重语义**

补测试覆盖：

- session epoch 改变后旧 cursor 失效
- topic id / session id 不匹配时返回 `InvalidTopicResponseCursor`
- source batch append 按 `raw_stream_ids` 顺序推进，不产生重复 raw posts
- tree rebuild 后不产生重复 rows
- `fetch_topic_posts` 写回 active source session cache 后，后续 targeted hydration 复用缓存而不重复请求
- 单次用户 load more 在第一批未产生新 root-level progress 时，会自动继续下一批
- 自动批量在出现新 root-level progress、source exhaust、达到批量/帖子预算或错误时停止

- [ ] **Step 9: 对照 `Explicit Cleanup / Delete List` 勾销 root-driven core logic**

本步骤结束前必须明确核对：

- Rust Core Root-Driven Pagination Logic 下的函数和结构是否已删
- old `fetch_topic_response_page(...)` implementation 是否已替换
- root-driven source cache 是否已消失

未删除项必须附带明确新职责说明，不能因为“可能还有用”保留。

- [ ] **Step 10: 补齐 source vs presentation 契约文档注释**

在 Rust 侧明确：

- `next_stream_offset` / `last_loaded_post_id` 属于底层 source cursor
- tree rows / depth / root grouping 属于 presentation 结果
- source batch size 控制本次拉取的 raw posts 数，不等于 UI row 数
- 单次用户 load more 可串联多个 source batches，以换取一次手势的可见树状进展

---

### Task 4: Platforms — Keep iOS / Android as pure consumers of screen + targeted context

**Files:**
- Modify: `native/ios-app/App/Stores/FireTopicDetailStore.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/data/repository/TopicRepository.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`
- Test: `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift`

- [ ] **Step 1: 固定主读取与刷新入口**

双端主详情页必须只通过以下路径读取与刷新：

- initial load -> detail source snapshot
- mutation refresh -> source snapshot refresh
- MessageBus refresh -> source snapshot refresh
- load more -> source cursor batch append
- render -> tree presentation rebuild
- one gesture may chain multiple source batches before completing

平台最终状态应明确拆成：

- source snapshot state
- tree presentation state
- load-more state
- anchor / scroll state
- sidecar state

- [ ] **Step 2: 禁止主详情页回退到 host-managed 窗口**

不得引入或恢复：

- `getPostsByNumber(...)` 风格的前后窗口分页
- 用 `TopicDetail.post_stream.stream` 在 host 侧自己切片当主分页
- 用 `GET /t/{id}/{postNumber}.json` 做主深链分页
- 用 tree row / root row 位置反向决定 source batch 边界
- 把“单批未出现新 root”错误地当成“已经到底”或“这次加载无效”

- [ ] **Step 3: targeted hydration 只服务上下文**

以下 API 只允许用于局部上下文：

- `fetchTopicPosts(post_ids)` -> anchor hydration / targeted merge
- `fetchPostReplyIds` + batched `fetchTopicPosts` -> reply context tree
- `fetchPostReplyHistory` -> parent chain context

不得把这些 targeted API 重新升格成主详情页读模型。`fetchPostReplies` 若仅剩 fallback 价值，应一并删除。

- [ ] **Step 4: 删除平台旧状态字段与旧依赖面**

本步骤要求明确替换或删除：

- iOS `topicResponseRowsByTopic`
- iOS `topicResponseCursorsByTopic`
- iOS 对 old `TopicScreen.response` 的 source-state 依赖
- Android `responseRows` 承担 source-state 的职责
- Android `cursor` 中 old root/branch 语义
- 双端任何用 root row / response row 反推 source batch 的逻辑

- [ ] **Step 5: 保持滚动期 MessageBus 刷新延后语义**

继续维持当前正确策略：

- 滚动期不立即 whole-screen apply
- 停止滚动后只应用最新一份 deferred screen
- identical refreshed screen / rows 直接丢弃

这条规则在 iOS / Android 两端都必须保留，避免实时刷新打断滚动路径。

---

### Task 5: Sidecars — Formalize AI summary, Presence, timings, and reply context as orthogonal capabilities

**Files:**
- Modify: `rust/crates/fire-core/src/core/interactions.rs`
- Modify: `rust/crates/fire-core/src/core/presence.rs`
- Modify: `native/ios-app/App/Stores/FireTopicDetailStore.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`
- Modify: `references/fluxdo/lib/services/discourse/_presence.dart` (reference-only audit notes if needed in docs)

- [ ] **Step 1: AI summary 保持非阻塞 sidecar**

规范双端行为：

- 仅在 header 暴露 `summarizable` / `hasCachedSummary` / `hasSummary` 时异步加载
- summary 失败不打断主详情页
- summary 重试只作用于 summary 卡片，不触发 whole-screen reload

- [ ] **Step 2: Presence 保持 bootstrap + heartbeat 模型**

规范 Rust / host 边界：

- bootstrap presence 从 Rust 发起 `GET /presence/get`
- update presence 从 Rust 发起 `/presence/update`
- topic detail 页面只消费 presence state，不自己组织 channel/body

- [ ] **Step 3: timings 维持后台静默写语义**

补充并验证以下契约：

- host 只上报可见 post timings
- Rust 负责 form body 组织和 `429` cooldown
- `429` 视为软失败，不影响主详情页会话状态

- [ ] **Step 4: reply context 收口到 reply-id tree 权威路径**

双端统一为：

```text
fetch_post_reply_ids
  -> batched fetch_topic_posts
  -> fetch_post_reply_history
```

不要让某一端回退到“先 `/replies.json` 再猜结构”的旧路径。若 `fetch_post_replies` 在当前产品面已无独立职责，应直接删除该调用链和 FFI 暴露。

---

### Task 6: Phase 2 follow-up — Add typed filtered topic-detail contract on top of the same raw source pipeline

**Files:**
- Future Modify: `rust/crates/fire-models/src/topic_detail.rs`
- Future Modify: `rust/crates/fire-core/src/core/topics.rs`
- Future Modify: `rust/crates/fire-uniffi-topics/src/records.rs`
- Future Modify: iOS / Android topic detail stores once product confirms filtered surface requirements

- [ ] **Step 1: 先冻结当前范围**

本期不把 FluxDO 的以下页面侧过滤逻辑直接搬到原生主详情页：

- `filter=summary`
- `username_filters=...`
- `filter_top_level_replies=true` + host 自补主贴

- [ ] **Step 2: 若未来需要筛选详情页，新增 typed Rust filter**

推荐新增：

```text
TopicScreenFilter {
  All,
  Summary,
  AuthorOnly { username },
  TopLevelOnly
}
```

由 Rust 统一决定底层调用 `/t/{id}.json` 的哪些 query params、如何生成 tree presentation、是否需要单独补主贴、以及如何在不破坏 raw source pipeline 的前提下投影出筛选后的视图。

- [ ] **Step 3: 平台不得直接消费 stringly raw filter contract**

未来即使要支持筛选，也只能消费 typed screen/filter contract，不能恢复：

- host 侧 string `filter`
- host 侧 string `username_filters`
- host 侧直接用 raw `TopicDetail.post_stream` 维护过滤窗口

---

### Task 7: Verification Matrix

- [ ] `docs/knowledge/api-overview.md` 不再把 topic detail 简化成旧 raw endpoint 流程，且相对链接路径正确。
- [ ] `docs/knowledge/api/03-topics.md` 明确 raw source contract 与 tree presentation contract 的边界。
- [ ] iOS 主详情页 initial load / refresh / load more 只走 raw source snapshot + source cursor batch append，再树状化渲染。
- [ ] Android 主详情页 initial load / refresh / load more 只走 raw source snapshot + source cursor batch append，再树状化渲染。
- [ ] deep link 到嵌套回复时，首包会正确包含目标 anchor，但后续 load more 仍回到原始 stream 批量拉取，而不是切成 root-driven 分页。
- [ ] source batch append 多页推进按 `post_stream.stream` 原始顺序工作，不依赖 top-level root ids。
- [ ] old source cursor 在 session epoch 改变后失效，不会污染新详情会话。
- [ ] 单次用户 load more 若首批仅补充现有 root 的子回复、未带来新的 root-level 可见进展，会自动继续下一批，而不是要求用户再次上拉。
- [ ] 单次用户 load more 在 source exhaust、出现新的 root-level 可见进展、达到自动批量预算或错误时结束。
- [ ] MessageBus 刷新在滚动中延后，停止滚动后只应用最新 screen，重复 payload 被丢弃。
- [ ] Presence bootstrap 与 update 不参与主详情页首屏载荷，且当前用户会被从可见 typing/presence 用户中过滤。
- [ ] `/topics/timings` 的 `429` 被视为软失败和 cooldown，不会触发登出或全页错误。
- [ ] AI summary 缺失或失败不会阻断主详情页，只影响 summary 自身 UI。
- [ ] reply context 统一走 `reply-ids + posts + reply-history`，不再保留 `/replies.json` fallback。
- [ ] tree presentation 在 source batch append 后仍能稳定保持 Fire 的嵌套 thread 特色，不退化成纯平铺列表。
- [ ] 平台层没有新的 `getPostsByNumber(...)` 风格主详情页分页逻辑进入代码库。
- [ ] Rust 主路径没有新的 root-driven source pagination 逻辑进入代码库。
- [ ] processed feed FFI、平台 convenience wrappers、以及仅为兼容存在的 topic-detail dead surface 已删除，不再以 retained / inactive / migration 名义存在。
- [ ] 在 typed filtered topic-detail contract 落地前，平台不会新增任何 stringly filter fallback surface。
