# RenderPresentation 收口

日期：2026-09-19  
状态：已实现（Stage 0–4）  
范围：帖子 / Boost / 聊天 / 资料 bio 的展示数据在 Rust 算完；热路径出站是 `RenderDocumentHandle`  
规格全文：`docs/architecture/2026-09-19-render-presentation-roadmap.md`

## 问题

上一轮把 cooked HTML 解析收到了 `fire-rich-text`，但 FFI 仍把整棵 `RenderDocument`（block 树）交给平台，平台再回传文档去拆 segment、抽图片、折纯文本。一篇帖子因此在 HTML、block 树、segment 树之间来回搬。真正的开销在这份记录树的往返，不在 C ABI 本身。

UniFFI 0.32 的 `ForeignBytes` / `&[u8]` 只覆盖 **foreign → Rust、同步、顶层参数**，不能用来把展示树零拷贝送回 Swift/Kotlin。Object 已经是 `u64` handle。热路径因此只传 handle，按需 `segment(i)`。

## 当前边界

```text
网络 JSON / MessageBus
  → fire-core 解析 + attach_presentation
  → TopicPost / ChatMessage 持有 cooked + Arc<PresentedDocument>
  → intern_presented_handle（按 Arc 指针保身份）
  → TopicPostState.presentation: Option<Arc<RenderDocumentHandle>>
        │
        ├─ checksum() / plainText() / imageAttachments()
        └─ segment(i) → RenderUiSegmentState::{Rich{nodes}, Image, Onebox}
  → iOS / Android FireRenderPresentation
  → 原生节点 / Spannable
```

- `PresentedDocument` 住在 `fire-models`（数据）。`present_*` 住在 `fire-rich-text` / `fire-core`。`fire-models` 不依赖 `fire-rich-text`。
- `TopicPostState` / `TopicPostBoostState` / `ChatMessageState` 只带 `presentation: Option<Arc<RenderDocumentHandle>>`，不带 `cooked`、`render_document`，也不内嵌整包 `RenderPresentationState`。
- UI plan 是 `RenderUiSegment::{Rich{nodes: Vec<RenderRichNode>}, Image, Onebox}`。`RenderRichNode` 与宿主 `FireRichTextNode` 同构。Image / Onebox 是一等段；quote / list / details 留在 Rich。UniFFI 把 `RenderRichNode::List` / `RenderBlockKind::List` 出站成 `ListNode`，避免 Kotlin 嵌套类 `List` 盖住 `kotlin.collections.List`。
- checksum 只在 `present_document` 写入（FNV-1a，结构变化即变）。宿主缓存键读 `handle.checksum()`。
- 详情默认快照的 `TopicPostState.raw` 为 `None`。编辑走 `fetch_post` → `topic_post_state_from_model_with_raw`。
- load more FFI 是 `TopicLoadMoreOutcomeState`：只出 `appended_posts` + cursor / ranges / tree，不出整表旧帖。
- `UserProfileState.bio_plain_text` 已在解析时折好。资料卡不再吃 `bio_cooked` HTML。
- 聊天 bus 出站是 `ChatBusEventState`。宿主用 `chat_bus_event_from_payload`，不在生产路径拆 JSONObject。
- `present_cooked_html` 只给测试夹具。生产 FFI 映射只 intern 已有 `Arc<PresentedDocument>`，不再二次 html5ever。
- `debug_ui_plan()` 仅调试。生产 cell 不得调用。
- 正文 leftover `:shortcode:`（引用摘录等未煮成 `<img class="emoji">` 的片段）在 `fire-rich-text` 收成 `RenderRichNode::Emoji`，标准 URL 为 `{base}/images/emoji/twitter/{name}.png?v=12`（肤色 `{name}/t{n}`）。代码块不展开。宿主只加载 URL，不再扫 shortcode。

## 所有权

`PresentedDocument` 同时拥有 IR 和 UI plan。同一 `cooked` 的 remap（点赞、load more 旧帖、列表 upsert）复用 `Arc`，intern 表按指针保持 Handle 身份。

`AttachedPresentation` 的 `PartialEq` 恒真，serde 跳过；帖子相等不比较 presented。

缺少 `presentation` 时暴露缺口，不从 `raw` 或平台 HTML 伪造正文。iOS 帖子行走 native runtime cell，不重开 SwiftUI post-row fallback。

## 宿主职责

| 层 | 做什么 |
|---|---|
| Rust | 解析、语义、过滤 quote chrome、选附件、拆 UI plan、折纯文本、checksum、intern Handle |
| iOS | `FireRenderPresentation` 映射 Handle segment → Texture / `NSAttributedString` / Nuke |
| Android | `FireRenderPresentation` 映射 Handle segment → Spannable / `FireRichTextView` / Coil |

搜索 / 引用 / 列表预览只调 `plainText()`。渲染缓存键是 `(postId, checksum)`。
