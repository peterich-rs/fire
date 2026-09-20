# RenderPresentation 后续阶段完整规划

日期：2026-09-19  
状态：已实施  
前置：`docs/architecture/2026-09-19-render-presentation.md`（终态摘要）  
范围：帖子 / Boost / 聊天 / 资料 bio 的展示数据所有权、UI plan 形状、UniFFI 出站、宿主消费、Handle

本文是 Stage 1–4 的唯一权威规格，现已落地。当前行为以代码与 `2026-09-19-render-presentation.md` 为准。不要另开平行方案，不要为旧 FFI 形状保留兼容出口。

---

## 0. 文档怎么用

读完应能回答五件事：

1. 值从哪里来、谁拥有、谁释放。
2. 哪些状态允许存在，哪些组合根本不该构造。
3. 哪一层稳定、哪一层只是内部实现。
4. 解析 / 展示计算 / FFI 拷贝 / 宿主排版分别发生在哪里。
5. 每个阶段做什么、不做什么、怎样才算完成。

设计判断遵循仓库内 `.agents/skills/rust-quality-coding`：先所有权和领域类型，再函数，最后才是 trait / Handle / 零拷贝。展示计算保持同步 CPU，放在 async fetch 之后的映射侧，不进网络 task。不为“将来可能替换 renderer”抽象 trait。

---

## 1. 已经完成的阶段（Stage 0–4）

Stage 1–4 已按本文落地。当前出站与宿主边界见 `docs/architecture/2026-09-19-render-presentation.md`。下面 Stage 0 段落保留为当时切点的记录。

2026-09-19 已落地的边界：

```text
cooked HTML
  → fire-core::parse_cooked_html          （内部 AST，不上 FFI）
  → fire-rich-text::render_document       （内部 IR）
  → fire-rich-text::PresentedDocument     （IR + UI plan 的名义所有者）
  → RenderPresentation                    （plain_text / image_attachments / segments）
  → RenderPresentationState               （UniFFI Record）
  → iOS / Android FireRenderPresentation  （宿主映射）
```

已做到：

- `TopicPostState` / `TopicPostBoostState` / `ChatMessageState` 不再带 `cooked` 或 `render_document`，只带 `presentation`。
- 宿主不再把文档回传 Rust 做第二次 `collect_images` / `plain_text` / segment 拆分。
- 聊天 REST 与 MessageBus 的消息/频道 envelope 由 Rust 解析并带上 presentation。
- 删除了会把 `cooked` 抹成空串的反向 `From<TopicPostState> for TopicPost`。
- `present_cooked_html` 只留给测试夹具。

未做到（本文要规划的）：

- segment 仍是迷你 `RenderDocument`，block 树仍过 FFI。
- 宿主仍重建 `FireRichTextNode`，并二次拆 onebox / 图文。
- `TopicPost` / `ChatMessage` 领域对象仍只持有 `cooked`；每次 FFI 映射都重新 html5ever。
- `PresentedDocument` 出站时 `into_presentation()`，IR 立刻丢掉，Handle 没有可包的运行时对象。
- checksum、raw、bio、bus 的 delete/reaction/tracking、双端渲染缓存键仍是宿主拼的。

Stage 0 修的是「往返」。后续修的是「同一份正文被复制成太多份 IR，而且每次出 FFI 都重算、整页重拷」。

---

## 2. 原则与硬约束

### 2.1 一条权威路径

每个功能只保留一条实现路径。缺口暴露为缺失，不从 `raw`、平台 HTML parser 或 SwiftUI/Compose 假正文补。iOS 帖子行继续走 native runtime cell，不重开 SwiftUI post-row fallback。

### 2.2 所有权先于拷贝

| 数据 | 最终所有者 | 谁只读 | 谁不得持有 |
|---|---|---|---|
| cooked HTML | 解析期 / 编辑期的领域记录 | 持久化层 | FFI 热路径、宿主 cell |
| `CookedHtmlDocument` | `parse_cooked_html` 栈上 | 单测 | FFI、宿主 |
| `RenderDocument` | `PresentedDocument` | 调试 / 将来按需派生 | `TopicPostState`、宿主 |
| UI plan | `PresentedDocument` | Handle 方法 | 不得再复制一份平行 plan |
| 原生节点 / Spannable / `NSAttributedString` | 宿主 | cell | Rust |

`Clone` 必须能说出新副本由谁使用。默认同页 load more、MessageBus 刷新、点赞回写不得再克隆整棵展示树。

### 2.3 UniFFI 0.32 能做什么、不能做什么

- Object 已经是 `u64` handle。这是 Stage 3 的唯一出站机制。
- Record / Enum / `String` / `Vec` 都走 `RustBuffer` 拷贝。
- `ForeignBytes` / `&[u8]` 只覆盖 **foreign → Rust、同步、顶层参数**。不能把展示树零拷贝送回 Swift/Kotlin。
- 禁止把 Handle 做成 `fn presentation(&self) -> RenderPresentationState` 然后继续在热路径调用。那只是换了个名字搬树。

### 2.4 稳定边界 vs 内部实现

稳定（跨 crate / 跨 FFI / 宿主必须遵守）：

- `PresentedDocument` 是唯一运行时所有者。
- 宿主只消费 UI plan 或 Handle 方法，不解析 cooked。
- `TopicTreeRow` 继续只描述树形，不夹带正文。

内部（可以改、宿主不得依赖）：

- `CookedHtmlDocument`、扁平 `RenderBlock` 树、`display_segments` 的现行拆法。
- `FireRenderBlockNodeBuilder` / `FireRenderBlockBuilder` / `FireRichTextBlockBuilder`（Stage 1 后退场）。

### 2.5 并发

HTML 解析和 UI plan 生成是同步 CPU。发生在：

1. 网络 JSON 收成领域对象之后；
2. 写入会话内存之前。

不要放进 `run_on_ffi_runtime` 的请求闭包里和 I/O 抢线程，也不要放到宿主主线程。同一 `cooked + base_url` 的结果用 `Arc` 共享，不在 FFI 线程重算。

---

## 3. 目标终态

```text
网络 JSON / MessageBus
  → fire-core 解析
  → TopicPostRecord / ChatMessageRecord     （可持久化：id、cooked、raw、元数据）
  → present_cooked → Arc<PresentedDocument> （只算一次）
  → TopicPostRuntime / ChatMessageRuntime   （记录 + Arc）
        │
        ├─ 会话内存、load more、点赞回写：只动元数据，复用 Arc
        │
        └─ UniFFI
              TopicPostState.presentation: Option<Arc<RenderDocumentHandle>>
              Handle 方法：
                checksum() / plain_text() / is_empty()
                image_attachments()          （小 Record 列表）
                segment_count()
                segment(i) -> RenderUiSegmentState
              默认详情行按需取 segment；列表/搜索/引用只取 plain_text + checksum
        │
        └─ 宿主
              用 Handle 身份做缓存键
              segment → 原生节点
              不再持有 FireRichTextNode 作为中间 IR（或只在单段映射时临时存在）
```

终态宿主看到的正文不是 HTML，不是 block 树，也不是迷你 `RenderDocument`。它看到的是：

```text
RenderUiSegment
  Rich { nodes: Vec<RenderRichNode> }   // 已按宿主可画的节点收口
  Image { ... }
  Onebox { ... }
```

`RenderDocument` 留在 Handle 里面。没有显式调试需求，不提供 `document()`。

---

## 4. 当前清单

### 4.1 Rust 类型

| 类型 | 位置 | 当前角色 | 终态角色 |
|---|---|---|---|
| `CookedHtmlDocument` | `fire-models` | 解析 AST | 内部，不上 FFI |
| `RenderDocument` + `RenderBlock` | `fire-models` | 语义 IR；也被塞进 Rich segment 出站 | 仅 `PresentedDocument` 内部 |
| `RenderDisplaySegment::{Rich,Image}` | `fire-models` | 迷你文档 / 独立图 | 被 `RenderUiSegment` 取代 |
| `RenderPresentation` | `fire-models` | 出站 Record 的领域镜像 | 过渡；Handle 就位后不再整包出站 |
| `PresentedDocument` | `fire-rich-text` | 名义所有者，出站即拆开 | 运行时唯一所有者，`Arc` 化 |
| `TopicPost.cooked` | `fire-models` | 领域唯一正文 | 持久化/编辑字段；展示走 Arc |
| `TopicPostBoost.cooked` | `fire-models` | 再解析一次出 presentation | 解析后丢掉，只留 plan |
| `ChatMessage.cooked` | `fire-models` | 同上 | 同上 |
| `UserProfile.bio_cooked` | `fire-models` | 原样出 FFI | 出 `bio_plain_text` 或 Handle |
| `TopicPostState.presentation` | `fire-uniffi-topics` | 整包 `RenderPresentationState` | `Option<Arc<RenderDocumentHandle>>` |
| `TopicPostState.raw` | `fire-uniffi-topics` | 每帖默认出站 | 按需 API |
| `TopicDetailSourceSnapshot.loaded_posts` | `fire-models` / UniFFI | 全量帖子 + 全量 presentation | 运行时 Arc 复用；FFI 只出增量或 handle 列表 |
| `TopicTreeRow` | `fire-models` | 只有 id / 层级 | 保持，不要夹带正文 |

### 4.2 当前热路径（必须改）

Rust 出站：

- `fire-uniffi-topics`：`topic_post_state_from_model` / `topic_post_boost_state_from_model`
- `fire-uniffi-chat`：`chat_message_state_from_model` / `ChatStateMapper`
- `fire-uniffi-types`：`presentation_state_from_cooked`（types crate 依赖 fire-core，分层反了）
- `fire-core`：`present_cooked_html`、`boost_display_text`（内部先 `render_cooked_html` 一次）
- `fire-uniffi-topics`：`topic_detail_source_snapshot_state_from_model` 把 **全部** `loaded_posts` 再映射一遍
- `fire-uniffi`：`present_cooked_html` 测试入口

iOS：

- `FireRenderPresentation` / `FireRenderBlockNodeBuilder`
- `FireTopicPresentation.renderContentFromPresentation` + `splitRichNodes`
- `FireTopicDetailStore` 的 `presentationChecksum`
- `FireChatRichText` / `FireChatMessageCell`
- `FireChatBusPayload.jsonObject`（delete / reaction / tracking）
- 资料：`plainTextFromHtml(bioCooked)`，`FireProfileViewController` 仍有 `NSAttributedString.DocumentType.html`

Android：

- `FireRenderPresentation` / `FireRenderBlockBuilder`
- `FireRichTextBlockBuilder`（生产 cell 已不走；夹具和遗留切分仍在）
- `TopicDetailViewModel.parsePostContent` 走 `content()`，`PostViewHolder` 走 `blocks()`，同一帖两条映射
- `LruCache<ULong, FireRichTextContent>(64)`，键是 post id，不是内容身份

### 4.3 宿主仍在做的本该 Rust 做的事

- 从扁平 block 重建树（`FireRenderBlockNodeBuilder`）。
- 从 node 树再拆 onebox（iOS `splitRichNodes`）。
- 从 node 树再拆图文（Android `FireRichTextBlockBuilder`）。
- 用 `plainText + segment 数量 + 图片 URL` 做 checksum，**不含富文本结构**，缓存会误命中。
- iOS 对同一 presentation 建两遍 attributed string：整篇一份，每个 text segment 再一份。

---

## 5. 问题诊断

### 5.1 一份正文的副本

当前一篇帖子在内存里可以同时存在：

1. `TopicPost.cooked`
2. 解析期 `CookedHtmlDocument`（栈上，可接受）
3. `RenderDocument`（plain_text + 图 + blocks）
4. `RenderPresentation` 再拷 plain_text / 图，外加每个 Rich segment 一份迷你文档
5. `RenderPresentationState` FFI 再拷一遍
6. `FireRichTextNode` 树
7. `NSAttributedString` / Spannable

Stage 0 删了「宿主 → Rust」的 5.5。5.4 到 5.6 还在。

### 5.2 每次出站都重算

`TopicPost` 不持有 `PresentedDocument`。下列每次都跑完整解析：

- 详情首屏
- load more（旧帖和新帖一起 remap）
- `fetch_post` / 回复历史 / 编辑回写
- 聊天 REST 与 MessageBus
- Boost：`boost_display_text` 一次，`presentation_state_from_cooked` 再一次

`PresentedDocument::from_document` 算完立刻 `into_presentation()`，Arc 无从挂起。

### 5.3 展示计划不完整

`display_segments` 只保证「独立图片 vs 一段富文本」。Onebox、code、quote 仍埋在迷你文档里。于是：

- iOS 必须再扫 node 才能抽出 onebox 卡
- Android 必须再扫 node 才能切图文
- 两端 `FireRichTextNode` 变成第三套 IR

### 5.4 身份不稳定

`FireRenderPresentation.checksum` 忽略 segment 内容。两篇结构不同、纯文本和图片 URL 相同的帖子会撞键。iOS store 和 Android LruCache 因此不能当权威身份用。

### 5.5 分层反了

`fire-uniffi-types` 依赖 `fire-core` 只为了 `presentation_state_from_cooked`。types crate 应只有 Record 和纯 `From`，不该跑 html5ever。

---

## 6. 阶段总览

| 阶段 | 名称 | 解决什么 | 不解决什么 | 依赖 |
|---|---|---|---|---|
| 0 | 出站改为 Presentation Record | 往返 | 迷你文档、重算、Handle | 已完成 |
| 1 | UI plan 收口 | 迷你文档 + 宿主二次拆分 | 重算、Handle | 无 |
| 2 | 领域持有 `Arc<PresentedDocument>` | 重算、Boost 双解析、types→core | Handle、按需 raw | 1 的类型，可与 1 后半并行 |
| 3 | `RenderDocumentHandle` | FFI 整包树 | bio/bus 边角 | 2 |
| 4 | 收口边角 | checksum、raw、bio、bus、缓存键 | 新的排版引擎 | 2，建议 3 之后 |

顺序硬约束：

- **先改 UI plan 形状，再做 Handle。** Handle 若仍返回现行 `RenderPresentationState`，热路径一份不省。
- **先让领域持有 Arc，再把 Arc 抬成 Object。** 否则 Handle 每次构造都还要 parse。
- Stage 1 可以单独合并。Stage 3 不能跳过 Stage 2。

```text
Stage 0 ──已完成──▶ Stage 1 形状
                      │
                      ▼
                   Stage 2 所有权 / 只算一次
                      │
                      ▼
                   Stage 3 Handle（u64 出站）
                      │
                      ▼
                   Stage 4 边角与分层打扫
```

---

## 7. Stage 1 — 把 segment 收成真正的 UI plan

### 7.1 目标

宿主不再看到 `RenderDocument`。FFI 上的一段正文是「可直接画的 segment 列表」。iOS 删除 `splitRichNodes` 的 onebox 二次拆分。Android 生产路径删除 `FireRichTextBlockBuilder`。`FireRenderBlockNodeBuilder` / `FireRenderBlockBuilder` 在本阶段结束时只服务测试夹具或删除。

### 7.2 目标类型

`fire-models` 新增（名字以落地时 crate 内最终名为准，语义不得变）：

```rust
pub enum RenderUiSegment {
    Rich { nodes: Vec<RenderRichNode> },
    Image(RenderImageAttachment),
    Onebox(RenderOneboxCard),
}

pub struct RenderOneboxCard {
    pub url: Option<String>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub source_name: Option<String>,
    pub icon_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

/// 与当前 FireRichTextNode 一对一，供宿主机械映射。
/// 不是扁平 RenderBlock，不带 id / parent_id / depth。
pub enum RenderRichNode {
    Text { content: String },
    Bold { children: Vec<RenderRichNode> },
    Italic { children: Vec<RenderRichNode> },
    Strikethrough { children: Vec<RenderRichNode> },
    Code { code: String },
    CodeBlock { language: Option<String>, code: String },
    Link { url: String, children: Vec<RenderRichNode> },
    Mention { username: String },
    MentionGroup { name: String, url: String },
    Hashtag { text: String, url: String, kind: Option<String> },
    Emoji { url: String, fallback_text: String, only_emoji: bool },
    Heading { level: u8, children: Vec<RenderRichNode> },
    Blockquote { children: Vec<RenderRichNode> },
    Quote {
        author: Option<String>,
        post_number: Option<u32>,
        topic_id: Option<u64>,
        children: Vec<RenderRichNode>,
    },
    List { ordered: bool, items: Vec<Vec<RenderRichNode>> },
    ListItem { children: Vec<RenderRichNode> },
    Spoiler { children: Vec<RenderRichNode> },
    Details { summary: Vec<RenderRichNode>, children: Vec<RenderRichNode> },
    Table { text: String },
    Video { url: String, title: Option<String> },
    Divider,
    LineBreak,
    Paragraph { children: Vec<RenderRichNode> },
}
```

UniFFI 出站把 `RenderRichNode::List` 和 `RenderBlockKind::List` 命名为 `ListNode`。Kotlin 嵌套类不能叫 `List`，否则会盖住 `kotlin.collections.List`，生成绑定无法编译。

`RenderPresentation` 改为：

```rust
pub struct RenderPresentation {
    pub checksum: u64,
    pub plain_text: String,
    pub image_attachments: Vec<RenderImageAttachment>,
    pub segments: Vec<RenderUiSegment>,
}
```

`checksum` 在 `present_document` 时写入，覆盖 plain_text、每段 kind、富文本结构、图片 URL / 尺寸。宿主禁止再本地哈希。

### 7.3 为什么 Rich 仍是树，而不是 attributed run

Quote、list、details、spoiler 需要嵌套。压成 `Vec<TextSpan>` 会把这些结构抹平，宿主还得自己恢复，等于再造一套 IR。`RenderRichNode` 与现有 `FireRichTextNode` 同构，Stage 1 的宿主改动是机械映射，不是重写排版。

独立成段的只有宿主 **已经当成独立 cell** 的东西：图片、onebox。Code / quote / details 继续留在 Rich 段里，与当前 Texture / Android 行为一致。本阶段不把它们升成独立 cell，避免视觉回归。

### 7.4 `display_segments` 怎么改

现行 `append_display_segments` 把容器打散再 `wrap_rich_segment` 成迷你 `RenderDocument`。改为：

1. 仍按现规则切开独立 `Image`。
2. 遇到 `RenderBlockKind::Onebox` 输出 `RenderUiSegment::Onebox`，不再埋进 Rich。
3. 连续的非图片、非 onebox 子树一次收成 `Vec<RenderRichNode>`。
4. 删除 `wrap_rich_segment` / `subtree_document` 对 `RenderDocument` 的再分配（id remap、再提 plain_text）。

`PresentedDocument` 继续同时持有内部 `RenderDocument`（给 Stage 3 Handle）和这份 UI plan。`present_document` 只生成 plan，不再 `clone` 一份与 document 重复的 attachments 到 plan 之外——plan 的 `image_attachments` 可以是对 document 附件的一次拥有转移或 `Arc<[T]>`。若 Stage 1 先继续 clone 附件列表，必须在注释里标明 Stage 2 改为共享。

### 7.5 FFI

`RenderDisplaySegmentState` 换成 `RenderUiSegmentState`。`RenderDocumentState` 不再出现在 `TopicPostState` / `ChatMessageState` / `TopicPostBoostState` / `RenderPresentationState.segments` 上。

`RenderDocumentState` / `RenderBlockState` 若仍被 `parse_cooked_html` 测试或夹具使用，可以留在 types crate，但标注为内部/测试，生产热路径不得引用。

`present_cooked_html` 改为返回新 `RenderPresentationState`（含 checksum 与新 segment）。测试夹具跟着改。

### 7.6 宿主

iOS：

- `FireRenderPresentation.richNodes` 映射 `RenderRichNode` → `FireRichTextNode`，不再经过 `FireRenderBlockNodeBuilder`。
- `renderContentFromPresentation` 按 Rust segment 直接生成 `FireTopicPostRenderSegment`：`Rich → .text(attributed)`，`Image → .image`，`Onebox → .onebox`。
- 删除 `splitRichNodes`。
- 整篇 `attributedText` 若仍被搜索/引用需要，从 `plain_text` 或把 Rich 段 attributed 接起来；禁止再从「全树 nodes」和「分段 nodes」各建一套逻辑分叉。优先：引用/搜索只用 `plain_text`；cell 只用分段 attributed。
- checksum 改为读 `presentation.checksum`。

Android：

- `FireRenderPresentation.blocks` 直接消费 `RenderUiSegment`。
- `PostViewHolder` 与 `ViewModel` 共用同一映射函数，禁止 `content()` 与 `blocks()` 两套。
- 生产代码删除对 `FireRichTextBlockBuilder.build(nodes, attachments)` 的调用。夹具可暂留，阶段结束时标 deprecated。

### 7.7 文件面

Rust：

- `rust/crates/fire-models/src/rich_text.rs`
- `rust/crates/fire-rich-text/src/lib.rs`（`display_segments`）
- `rust/crates/fire-rich-text/src/presentation.rs`
- `rust/crates/fire-uniffi-types/src/records/render_block.rs`
- 全部构造 `RenderPresentationState` / `RenderDisplaySegmentState` 的测试

iOS：

- `FireRenderPresentation.swift`
- `FireTopicPresentation.swift`
- `FireRenderBlockNodeBuilder.swift`（退场或降为测试）
- `FirePostCellLayout.swift`（Boost 仍走 richNodes）
- 单测：`FireTopicPresentationTests`、layout tests

Android：

- `FireRenderPresentation.kt`
- `FireRenderBlockBuilder.kt` / `FireRichTextBlockBuilder.kt`
- `PostViewHolder.kt` / `TopicDetailViewModel.kt` / `ChatChannelActivity.kt`
- `FireRichTextBlockBuilderTest.kt`

### 7.8 验收

- 生产 FFI 热路径的 grep：`RenderDocumentState` 不得再出现在 `TopicPostState` / `ChatMessageState` / `TopicPostBoostState` / `RenderPresentationState`。
- iOS 生产代码 grep：`splitRichNodes`、`FireRenderBlockNodeBuilder` 为零。
- Android 生产 cell grep：`FireRichTextBlockBuilder` 为零。
- 现有 rich-text 单测（quote / details / onebox / 图注过滤 / emoji fallback）全部改为断言 `RenderUiSegment`，语义不得回退。
- 目视：详情长帖图文交错、onebox 卡、quote 折叠、Boost chip emoji 与 Stage 0 一致。
- checksum 对「同文不同结构」必须变化。补单测。

### 7.9 本阶段明确不做

- 不引入 Handle。
- 不把 `TopicPost` 改成持有 Arc（那是 Stage 2）。
- 不改 MessageBus delete/reaction JSON。
- 不在 Rust 里生成 `NSAttributedString` / Spannable。

---

## 8. Stage 2 — 领域持有 `Arc<PresentedDocument>`

### 8.1 目标

一份 `cooked + base_url` 在进程内只解析一次。load more、点赞、书签、MessageBus 元数据补丁、聊天列表 upsert 复用同一 `Arc`。FFI 映射不再调用 `present_cooked_html`。

### 8.2 类型怎么拆

`TopicPost` 目前既是网络解析结果，也是 serde 缓存形状，也是 FFI 映射源。不要把 `Arc<PresentedDocument>` 塞进会整包 JSON 序列化的缓存记录。

推荐拆成：

```rust
/// 可持久化 / 可 serde。不含运行时 IR。
pub struct TopicPostRecord {
    pub id: u64,
    // ... 现有 TopicPost 字段，包括 cooked、raw ...
}

/// 会话内存里的帖子。展示与元数据一起走。
pub struct TopicPost {
    pub record: TopicPostRecord,
    pub presented: Option<Arc<PresentedDocument>>,
}
```

若希望少改调用点，允许在现有 `TopicPost` 上加：

```rust
#[serde(skip)]
pub presented: Option<Arc<PresentedDocument>>,
```

但 `TopicDetailSourceSnapshot` 一旦 serde 进 SQLite / 文件，必须保证 skip 生效，冷启动从 `cooked` 再 present 一次。两种写法选一个，禁止并行两套「运行时帖子」。

`ChatMessage`、`TopicPostBoost` 同样处理。Boost 的 `display_text` 从 `presented.plain_text()` 做归因剥离，禁止再跑一遍 `render_cooked_html`。

### 8.3 何时 present

唯一入口：

```rust
fn attach_presentation(post: TopicPostRecord, base_url: &str) -> TopicPost
```

调用点：

- `topic_payloads` 解析完 raw post
- `chat_payloads` 解析完 message
- 编辑 / 发帖回写拿到新 cooked 之后
- 冷启动从缓存读出 record 之后

禁止调用点：

- `topic_post_state_from_model`
- `ChatStateMapper`
- 宿主 `presentCookedHtml`

`base_url` 来自 `FireCore` 会话，不写死 `"https://linux.do"`，除非测试夹具。

同一会话内用 `(post_id, cooked_fingerprint, base_url)` 做 memo。编辑后 cooked 变了才换 Arc。点赞 / 反应 / bookmark 只改 record 元数据，`presented` 指针不变。

### 8.4 load more 与快照

今天 `TopicLoadMoreOutcome.source_snapshot` 携带全部 `loaded_posts`。Stage 2 即使还整包出站，也不得对旧帖重 parse：旧帖带着原来的 Arc 走 `From`。

本阶段同时把核心快照改成「全量运行时 + 增量 FFI」的准备：

- 内存：`loaded_posts: HashMap<u64, TopicPost>` 或保留 Vec 但按 id 复用 Arc。
- FFI：可以仍先出全量 handle/record（Stage 3 再变瘦），但映射函数是 `clone Arc`，不是 `present_cooked_html`。

已有 `TopicDetailSourceAppend.appended_posts`。Stage 2 结束时，load more 的 **Rust 内部**必须能只 present 新增帖。FFI 是否改为只推 append 可以放到 Stage 3，与 Handle 一起做，避免改两次出站形状。

### 8.5 分层

`presentation_state_from_cooked` 从 `fire-uniffi-types` 删除。

```text
fire-models        记录 + UI plan 类型
fire-rich-text     document → PresentedDocument（不碰网络、不碰 UniFFI）
fire-core          parse HTML + attach_presentation
fire-uniffi-types  只 From<RenderUiSegment> 等纯映射，不依赖 fire-core 做 present
fire-uniffi-topics 从 TopicPost.presented 升 FFI
```

`fire-uniffi-types` 对 `fire-core` 的依赖若只为 presentation，本阶段去掉。若还有 runtime / error 共享，把 present 辅助挪走，不要为了方便把解析留在 types。

### 8.6 `present_cooked_html` 的命运

- 测试夹具可以继续调用 fire-core / 顶层 UniFFI 函数。
- 生产映射路径 grep 必须为零。
- 文档写明：这是「只有一段 cooked、没有领域对象」的遗留入口，不是帖子主路径。

### 8.7 文件面

- `fire-models/src/topic_detail.rs`、`chat.rs`
- `fire-core/src/topic_payloads.rs`、`chat_payloads.rs`、`rich_text.rs`、`core/topics.rs`
- `fire-uniffi-topics/src/records.rs`、`lib.rs`
- `fire-uniffi-chat/src/records.rs`、`lib.rs`
- `fire-uniffi-types/src/records/render_block.rs`、`Cargo.toml`
- Boost：`boost_display_text`

### 8.8 验收

- 同一 `TopicPost` 在「首屏映射 + load more 再映射」中，`Arc::ptr_eq` 为真（单测）。
- 点赞回写后 `presented` 指针不变。
- Boost 单测：一次 parse，`display_text` 与 presentation.plain_text 同源。
- `fire-uniffi-types` 不再 `use fire_core::present_cooked_html`。
- 基准（至少开发机日志）：大帖详情 load more 不再出现与旧帖数量成正比的 html5ever 时间。允许用 tracing span `present_cooked` 计数断言：第二次 load more 的 present 次数 ≈ 新帖数。

### 8.9 本阶段明确不做

- 不把 `TopicPostState.presentation` 改成 Object（Stage 3）。
- 可以仍整包 lift `RenderPresentationState`，因为 Arc 已算完，lift 只是拷 plan。这是可接受的过渡。
- 不改资料 bio、不改 bus delete JSON。

---

## 9. Stage 3 — `RenderDocumentHandle`

### 9.1 目标

热路径跨 FFI 只传 `u64`。宿主按 Handle 身份缓存原生排版。需要画某一段时再取该段 Record。列表、搜索、引用、checksum 比较不取 segment 树。

### 9.2 对象形状

```rust
#[derive(uniffi::Object)]
pub struct RenderDocumentHandle {
    inner: Arc<PresentedDocument>,
}

#[uniffi::export]
impl RenderDocumentHandle {
    pub fn checksum(&self) -> u64;
    pub fn is_empty(&self) -> bool;
    pub fn plain_text(&self) -> String;
    pub fn image_attachments(&self) -> Vec<RenderImageAttachmentState>;
    pub fn segment_count(&self) -> u32;
    pub fn segment(&self, index: u32) -> Option<RenderUiSegmentState>;

    /// 仅测试 / 调试。生产 cell / store 不得调用。
    pub fn debug_ui_plan(&self) -> RenderPresentationState;
}
```

`TopicPostState` / `TopicPostBoostState` / `ChatMessageState`：

```rust
pub presentation: Option<Arc<RenderDocumentHandle>>,
```

没有 `cooked`，没有 `render_document`，没有内嵌 `RenderPresentationState`。

构造：

```rust
impl RenderDocumentHandle {
    pub fn from_presented(presented: Arc<PresentedDocument>) -> Arc<Self> {
        Arc::new(Self { inner: presented })
    }
}
```

同一 `Arc<PresentedDocument>` 升一次 Handle 并在会话里复用。禁止每次 FFI 映射 `Arc::new(Handle { inner: presented.clone() })` 又包一层新 Object——否则宿主身份每次都变，缓存全废。做法：`PresentedDocument` 侧可持有弱引用或在会话表 `HashMap<ArcPtr, Arc<Handle>>`。更简单：Handle 就是 `#[uniffi::Object]` 包着的 `Arc<PresentedDocument>`，映射时对已有 `Arc<RenderDocumentHandle>` 做 clone（clone 的是外层 Arc，handle id 不变）。因此 Stage 2 的运行时帖子应直接存 `Arc<RenderDocumentHandle>`，或存 `Arc<PresentedDocument>` 并保证「一个 PresentedDocument 只对应一个 Handle」。推荐后者加一层 `HandleBox`：

```rust
pub struct PresentedBody {
    document: Arc<PresentedDocument>,
    handle: Arc<RenderDocumentHandle>, // 与 document 同一份 inner
}
```

创建一次，之后只 clone `PresentedBody`。

### 9.3 宿主怎么用

详情 cell configure：

```text
let handle = post.presentation
if handle.checksum() == cached.checksum { reuse nodes }
else {
  for i in 0..handle.segmentCount() {
    map(handle.segment(i))
  }
}
```

搜索 / 引用 / 列表预览：只调 `plainText()`。

禁止：

- `debug_ui_plan()` 出现在 `FireTopicPresentation` / `PostViewHolder` / `FireChatRichText`
- 把所有 segment 一次性取回再塞进自己的平行 cache，作为长期 IR（一次性取可以，但缓存键必须是 handle checksum / object identity）

iOS `contentInputsByPostID` 的输入改为 `presentationChecksum: handle.checksum()`。Android `LruCache` 键改为 `checksum` 或 `(postId, checksum)`，避免编辑后命中旧 Spannable。

### 9.4 详情快照出站变瘦

与 Handle 同一阶段做：

`TopicDetailSourceSnapshotState.loaded_posts` 仍可给宿主一张「id → 帖子元数据 + handle」表，这是投影需要的。但：

- 不要把 `raw` 放进这张表。
- load more FFI 改为「append 的 posts + 更新后的 cursor / ranges / tree」，不要把旧帖元数据再写一遍。宿主已有的 handle 继续持有。
- `TopicTreePresentationState` 继续只有 `TopicTreeRow`（id 与层级）。

已有类型 `TopicDetailSourceAppend` 应对齐成 UniFFI Record，作为 `load_more` 的出站，而不是每次 `TopicLoadMoreOutcomeState` 复制整表。

### 9.5 raw 按需

新增或复用现有 `fetch_post`：编辑弹窗只在用户点编辑时要 `raw`。`TopicPostState.raw` 从默认详情快照删除。若 `fetch_post` 已返回完整 `TopicPostState`，编辑路径走它，并允许这一次带 `raw`。

### 9.6 UniFFI / 绑定

- 重新生成 Swift / Kotlin bindings。
- Object 跨线程：Handle 必须 `Send + Sync`（`Arc<PresentedDocument>` 已满足）。
- 宿主不得对 Handle 做深比较；用 checksum 或引用身份。
- 文档写明：Handle 生命周期由 Rust Arc 与 UniFFI 引用计数共同管理；宿主存 Handle 即延长 IR 寿命。详情页释放后，旧 cell 不得再调方法。

### 9.7 验收

- 生产 `TopicPostState` 无 `RenderPresentationState` 字段。
- 大帖详情首屏 FFI 载荷不再含每帖完整 block 树；可用绑定生成物或集成测试断言 `segment()` 才触发该段 lift。
- load more 不把旧帖的 segment 再 lift 一遍（tracing 或测试桩计数）。
- iOS/Android 编辑：未点编辑时详情快照不含 raw；点编辑后能拿到 raw。
- 点赞后 cell 不因新 Handle 身份重建正文（checksum 不变且 handle 身份不变）。

### 9.8 本阶段明确不做

- 不在 Handle 上暴露 `document()` / `blocks()`。
- 不用 `ForeignBytes` 手写序列化格式。
- 不把 pixel buffer / 图片解码塞进 Handle。

---

## 10. Stage 4 — 边角、身份、剩余混杂逻辑

Stage 2/3 做完后，这些才能收得干净。可拆成独立 PR，但必须落在同一规格下。

### 10.1 checksum 权威化

- 唯一写入点：`present_document`。
- 算法固定：对 UI plan 做稳定序列化（长度前缀或明确分隔），再 hash（xxhash / siphash，选一个写死）。
- 宿主、store、Android LruCache、聊天 `contentID` 全部读这个 `u64`。
- 删除 `FireRenderPresentation.checksum` 的本地字符串拼接。

### 10.2 资料 bio

`UserProfile.bio_cooked` 不再出给宿主当 HTML。

二选一，优先 A：

- A. `bio_plain_text: Option<String>`。资料卡只显示纯文本，不必上富文本。
- B. 与帖子同一套 Handle。仅当产品要在资料页渲染 mention / emoji 时才用。

删除 iOS `NSAttributedString.DocumentType.html` 资料路径。`plainTextFromHtml` 对 bio 的调用改为读 Rust 字段。

### 10.3 聊天 MessageBus 剩余 JSON

iOS 仍用 `FireChatBusPayload.jsonObject` 处理：

- delete：`deleted_id`
- reaction：`chat_message_id` / `emoji` / `action` / `user`
- tracking：`channel_id` / `unread_count` / `mention_count` / `thread_id`
- new-messages 的 `type == "channel"` 过滤

这些与展示无关，但是协议解析。收口到 `fire-core` 的 typed bus payload：

```rust
pub enum ChatBusEvent {
    MessageUpsert { message: ChatMessage },
    MessageDeleted { id: u64 },
    Reaction { message_id: u64, emoji: String, action: ChatReactionAction, actor_id: Option<u64> },
    Tracking { channel_id: u64, unread: u32, mention: u32, thread_id: Option<u64> },
    ChannelUpsert { channel: ChatChannel },
    Ignored,
}
```

FFI：`chat_bus_event_from_payload(payload_json, fallback_channel_id, base_url) -> ChatBusEventState`。

iOS 删除 `jsonObject` 的生产调用。Android 列表侧现有的 `JSONObject` 轻量解析一并换掉，避免两端协议分叉。

### 10.4 双端缓存对齐

| 用途 | 键 |
|---|---|
| iOS topic render cache | `post_id + handle.checksum` |
| iOS chat NSCache | `message_id + checksum + is_deleted` |
| Android LruCache | 同上，禁止只按 `post_id` |
| 引用 / 搜索 | 只用 `plain_text`，不建 attributed |

### 10.5 测试入口收敛

- `present_cooked_html`：仅测试 target 可见，或留在 UniFFI 但文档标 `testonly`。
- `parse_cooked_html`：继续仅内部 / 单测。
- 删除任何「平台传入 cooked 换 presentation」的生产调用点。

### 10.6 文档与仓库地图

本阶段结束时必须同步：

- 本文状态改为 Implemented，逐阶段打勾
- `2026-09-19-render-presentation.md` 改写为终态摘要，不再描述 Record 热路径
- `fire-native-architecture.md` §3.6 / §4.6 / §7.5
- `2026-06-05-rich-text-and-state-observer-design.md` 顶部备注
- `2026-08-09-chat-tab-design.md`
- `docs/knowledge/api/03-topics.md`、用户资料相关 knowledge
- iOS / Android README 里仍写 `RenderPresentationState` 整包出站的句子

### 10.7 验收

- 宿主生产代码 grep：`presentCookedHtml`、`plainTextFromHtml` 用于 bio、`jsonObject(from: event)` 用于 chat bus，均为零。
- `FireChatBusPayload` 若只剩空壳则删除。
- checksum 单测覆盖结构变化。
- 资料卡不再走 HTML 文档类型。

---

## 11. 跨阶段：crate、测试、验证

### 11.1 crate 责任（终态）

```text
fire-models        领域记录、UI plan 类型、不跑 parser
fire-rich-text     RenderDocument + PresentedDocument + checksum
fire-core          HTML parse、attach_presentation、bus typed parse
fire-store         只存 record（cooked/raw/元数据），不存 IR
fire-uniffi-types  FFI Record / Enum，纯 From
fire-uniffi-topics / chat / user   Handle 提升、命令
native hosts       原生节点、手势、图片管线
```

### 11.2 测试策略

每个阶段都要有：

1. `fire-rich-text` 语义金标（现有 quote / onebox / 图注 / emoji 测试改断言，不删场景）。
2. FFI 形状测试：生产 Record 不含 `cooked`、不含迷你 `RenderDocument`（Stage 1+）；Stage 3 起含 Handle。
3. 所有权测试：Arc 指针在元数据补丁后保持不变（Stage 2+）。
4. 宿主单测：夹具改为 `present_cooked_html` 或构造 `RenderUiSegment`，不再手搭 `RenderDocumentState`。
5. 阶段结束前：相关 crate `cargo test --lib` 与 clippy `--no-deps -D warnings`。

没有浏览器可验原生详情。用现有 iOS/Android 单测 + 必要的真机/模拟器目视清单（长帖、onebox、Boost、聊天实时消息、编辑）。

### 11.3 验证清单（目视）

- 详情：图文交错、onebox 卡、quote 折叠与展开、表格纯文本、视频占位、mention / hashtag 点击。
- Boost overlay 与 chip 的 emoji。
- 聊天 REST 历史 + MessageBus 新消息，正文与删除态。
- 点赞 / 反应后正文不闪、不重排（Stage 2/3）。
- 编辑保存后 checksum 变、正文更新。
- 资料卡 bio 纯文本，无 HTML 标签泄漏。

### 11.4 文档纪律

实现某阶段时同步改本文对应章节的状态，并改「当前清单」表。禁止只在代码里演进、让本文停在 Stage 0 口吻。

---

## 12. 明确不做

- 不在 Rust 做 Core Text / Yoga / 完整排版。宿主继续拥有字体、颜色、手势、图片请求。
- 不引入第二套 renderer，不用 WebView 画正文。
- 不把 `ForeignBytes` 当出站方案。
- 不为旧 `RenderPresentationState` 热路径留双栈。Stage 1 换 segment 形状就是切断。
- 不把 `RenderDocumentState` 重新放回 `TopicPostState`「以备调试」。调试走 Handle 的 `debug_ui_plan` 或 Rust 日志。
- 不为 parser / presenter 做 trait。没有第二实现。
- 不把 chat 的 delete/reaction 继续留在宿主「因为很小」。Stage 4 一次收完，避免协议再分叉。
- 不在 Stage 1 把 code/quote/details 改成独立 cell。那是产品改版，不是本规划。

---

## 13. 风险

| 风险 | 为什么会发生 | 处理 |
|---|---|---|
| `RenderRichNode` 与 `FireRichTextNode` 漏字段 | 两端 node 手写 | Stage 1 用对照表 + 穷尽 match；未知 kind 显式缺口，不吞 |
| onebox 提前成段导致位置错 | 现行拆分把 onebox 留在富文本流里 | 金标用真实 cooked 夹具比位置，不只比字段 |
| serde skip 丢 presented，冷启动全页卡顿 | 缓存只有 cooked | 冷启动 present 放后台映射线程；UI 先出树行，正文按 handle 就位填充 |
| Handle 每次 remap 新 Object | 宿主缓存全失效 | `PresentedBody` 固定一对 document/handle |
| 过早做 Stage 3 | 仍整包 lift plan | 代码审拒绝合并「Handle.getPresentation()」热路径 |
| 大文档与代码漂移 | 阶段多 | 每阶段改本文状态，否则不算完成 |

没有「旧路径回退」。阶段中途发现语义回归，停在该阶段修权威路径。

---

## 14. 阶段验收总表

| 项 | Stage 1 | Stage 2 | Stage 3 | Stage 4 |
|---|---|---|---|---|
| 热路径无迷你 `RenderDocument` | 必须 | 保持 | 保持 | 保持 |
| 宿主无二次拆 onebox/图文 | 必须 | 保持 | 保持 | 保持 |
| 生产映射不再 parse cooked | | 必须 | 保持 | 保持 |
| `Arc` 在元数据补丁后稳定 | | 必须 | 必须（含 Handle 身份） | 保持 |
| 帖子出站是 Object handle | | | 必须 | 保持 |
| 默认快照无 raw | | 可选 | 必须 | 保持 |
| bio / bus JSON 离开宿主 | | | | 必须 |
| checksum 只来自 Rust | 写入字段 | 领域携带 | Handle 暴露 | 宿主删除本地哈希 |
| 文档与代码一致 | 改形状描述 | 改所有权描述 | 改 FFI 描述 | 本文标 Implemented |

---

## 15. 建议的提交切片

不要把四个阶段做成一个 PR。建议：

1. **Stage 1a**：`RenderUiSegment` / `RenderRichNode` + `display_segments` 改写 + Rust 单测。FFI 仍可暂时从新 plan 再填旧 `RenderDisplaySegment::Rich(document)`——**不推荐**。能直接切 FFI 就直接切。
2. **Stage 1b**：UniFFI + iOS/Android 映射，删除宿主二次拆分。
3. **Stage 2**：`attach_presentation`、Boost 单次 parse、去掉 types→core present。
4. **Stage 3a**：Handle 类型 + 会话内 `PresentedBody`；`TopicPostState` 改字段。
5. **Stage 3b**：load more 增量 FFI + raw 按需。
6. **Stage 4**：bio、bus typed event、缓存键、文档终态。

1a 与 1b 若拆开，中间不得出现「Rust 已是新 plan、宿主仍走旧 segment」的双栈超过一个 PR 周期。

---

## 16. 与 Stage 0 文档的关系

- `docs/architecture/2026-09-19-render-presentation.md` 描述 **当前已落地** 的 Handle 出站。
- 本文是 Stage 1–4 的规格与阶段记录；细节以代码和那篇终态摘要为准，避免两份当前边界。

`docs/architecture/fire-native-architecture.md` 的富文本管道图已改到 Handle。
