# Fire Rich Text + StateObserver 实施说明

> 日期: 2026-06-05
> 状态: Implemented
> 范围: `fire-rich-text`、UniFFI 富文本/observer 边界、iOS/Android 双端接入
> 结论: 富文本语义已收口到 Rust；StateObserver 已落到当前可稳定消费的 snapshot 边界；未引入并行渲染路径或平台回退路径
> 备注: 文中早期提到的 `TopicDetailFeedSnapshotState` 已在 2026-06-06 的 topic-detail source/presentation 收口中被 `TopicDetailSourceSnapshotState + TopicTreePresentationState` 取代；2026-06-07 起 topic-detail poll option 纯文本也由 Rust payload 提供，平台 cell/layout 路径不再同步解析 option HTML；本文件保留为富文本与 observer 设计的历史实现记录。

---

## 1. 本次交付落地了什么

### 1.1 Rust 统一富文本主路径

- 新增 `rust/crates/fire-rich-text/`
- 新增共享模型：
  - `fire-models::RenderBlockKind`
  - `fire-models::RenderBlock`
  - `fire-models::RenderDocument`
  - `fire-models::RenderImageAttachment`
- `fire-core` 新增 `render_cooked_html(raw_html, base_url)`；`parse_cooked_html(raw_html)` 是 Rust 内部 parser / AST 单测入口，不是平台渲染入口

### 1.2 FFI 边界

- `fire-uniffi-types` 新增：
  - `RenderBlockKindState`
  - `RenderBlockState`
  - `RenderDocumentState`
  - `RenderImageAttachmentState`
- 顶层 `fire-uniffi` 新增：
  - `render_cooked_html(raw_html, base_url) -> RenderDocumentState`
  - `collect_images_from_render_document(document) -> [RenderImageAttachmentState]`
  - `plain_text_from_render_document(document) -> String`
  - `StateObserver` callback interface
- `fire-uniffi-topics::TopicPostState` 新增 `render_document`

### 1.3 双端接入

- iOS:
  - 删除平台侧 cooked HTML 解析路径
  - 只消费 `TopicPostState.render_document` / `RenderDocumentState`
  - `FireRenderBlockNodeBuilder` 负责 `RenderDocumentState -> [FireRichTextNode]` 的轻映射
  - `FireTopicPresentation.renderContent(from post:)` 缺少 `renderDocument` 时返回空，不再从 `post.cooked` 生成正文 fallback
- Android:
  - 删除平台侧 cooked HTML 解析路径
  - 只消费 `TopicPostState.render_document` / `RenderDocumentState`
  - `FireRenderBlockBuilder` 负责 `RenderDocumentState -> [FireRichTextNode]` 的轻映射
  - `PostViewHolder` / `TopicDetailViewModel` 缺少 `renderDocument` 时不显示伪造正文，不再从 `post.cooked` 生成正文 fallback

### 1.4 StateObserver

- `FireAppCore` 提供统一 `register_state_observer()` / `unregister_state_observer()`
- Rust 内部通过 `fire-core/src/state_observer.rs` 维护单一 observer 注册点
- 同一 snapshot 域通过 100ms debounce 合并连续更新，只推最新值
- observer callback 使用 `catch_unwind` 做错误隔离，单个回调异常不会污染其他域
- 当前会主动推送的 snapshot 边界：
  - `SessionState`
  - `TopicListState`
  - `NotificationCenterState`

### 1.5 Topic detail poll option boundary

- `PollOption` / `PollOptionState` 现在携带 Rust 侧生成的 `plain_text` / `plainText`。
- iOS `FirePostPollRenderModel` 和 Android `PostViewHolder` 直接消费这个纯文本标题，空值才回退到 option id。
- poll-bearing cell configure、layout key、layout precompute 路径不得调用 `render_cooked_html` 或任何平台 HTML parser 来同步解析 option HTML。

---

## 2. 实际采用的设计

### 2.1 为什么不是递归 RenderBlock tree FFI

最终没有把 FFI 设计成递归 `children: Vec<RenderBlockState>`，而是采用了扁平文档：

```rust
pub struct RenderDocument {
    pub blocks: Vec<RenderBlock>,
    pub plain_text: String,
    pub image_attachments: Vec<RenderImageAttachment>,
}

pub struct RenderBlock {
    pub id: u32,
    pub parent_id: Option<u32>,
    pub depth: u32,
    pub kind: RenderBlockKind,
}
```

原因：

1. 当前双端本来就已经有轻量 parent/child 重建逻辑，保留这一步几乎没有维护成本
2. UniFFI 对扁平 record 的代码生成和平台调试更直接
3. 真正需要收口的是“语义判断”和“URL/quote/details/image attachment 规则”，不是平台内的 `childrenByParentId` 映射

这次交付的目标是消灭双端语义分叉，而不是为了数据结构形式强行重写平台渲染器。

### 2.2 RenderBlockKind 以“当前原生渲染语义”对齐

实现没有强行追求抽象过度的 block taxonomy，而是直接对齐当前双端原生渲染需要：

- 文本与样式：`Text` / `Bold` / `Italic` / `Strikethrough` / `InlineCode` / `CodeBlock`
- 结构：`Paragraph` / `Heading` / `LineBreak` / `List` / `ListItem`
- 链接语义：`Link` / `Mention` / `MentionGroup` / `Hashtag`
- 媒体：`Image` / `Emoji` / `Video` / `Onebox`
- 论坛特有结构：`Quote` / `Blockquote` / `Spoiler` / `Details` / `DetailsSummary`
- 降级块：`Table { text }` / `Divider` / `Unknown`

这样做的结果是：

- 平台端只做轻映射
- quote/details/emoji/attachment/lightbox 规则只有 Rust 一处
- onebox 标题/描述提取也只有 Rust 一处，平台不抓取或解析 Open Graph / HTML preview
- 现有 iOS `NSAttributedString` / Android `Spannable` 渲染器可以直接复用

### 2.3 图片附件提取也回到 Rust

`RenderDocument.image_attachments` 现在由 Rust 统一生成，包含：

- lightbox 优先取祖先链接 URL
- emoji 不进入附件列表
- avatar / quote avatar / thumbnail 被统一过滤
- 宽高在 Rust 侧标准化成 `Option<u32>`

平台端不再各自维护一套附件提取和去重规则。

2026-06-07 起，双端 topic detail 不再把 `image_attachments` 当成“文末附件区”单独追加。平台仍从
`RenderBlockKind::Image` 保留图片在正文中的顺序，但图片展示 URL 以 Rust 生成的
`RenderDocument.image_attachments` 为准：lightbox / generic linked image 场景优先使用 original URL，
正文缩略展示和点击预览因此共享同一个缓存键。平台端只负责按节点顺序切分 text/image segment、选择显示尺寸、
展示加载/失败/重试状态，以及打开原生图片预览。

图片附件旁的上传元信息 chrome 也只在 Rust 侧过滤。匹配规则不依赖 `image` 这种固定前缀，前缀可以是文件名、
hash 或其他服务器输出字符串；只有末尾满足“尺寸 + 文件大小”的附件说明会被剥离，普通 caption / 正文文本必须保留。

Quote / onebox preview 的语义同样在 Rust 侧收口。Rust 会移除 Discourse quote chrome/avatar，并从 onebox
节点树提取标题与描述；iOS / Android 只负责把共享节点映射成两行以内的 compact quote preview、可点击链接和原生
onebox 文本展示，不保留平台侧 link-preview fetcher 或 HTML fallback。

### 2.4 RenderDocument 辅助能力也回到 Rust

除了主渲染入口，这次还把两类派生能力统一到了共享层：

- `collect_images_from_render_document()`：基于共享 `RenderDocumentState` 重新提取附件，平台无需再扫一遍节点树
- `plain_text_from_render_document()`：直接从共享 block 文档生成纯文本，避免双端各自做文本折叠规则

这两个 API 的价值不是“提供回退路径”，而是保证 render document 成为富文本派生数据的唯一 authoritative source。

---

## 3. StateObserver 的当前边界

### 3.1 Rust 内触发点

当前 observer 不是“全状态自动广播”，而是基于已经稳定存在的 snapshot 边界推送：

- `AppStateRefresher`
  - `refresh_bootstrap()` 后推 `SessionState`
  - 当前 home 话题列表刷新成功后推 `TopicListState`
  - 二阶段通知刷新后推 `NotificationCenterState`
- `FireTopicsHandle`
  - `fetch_topic_list()` 后推 `TopicListState`
- `FireNotificationsHandle`
  - `fetch_recent_notifications()` / `fetch_notifications()` 后推 `NotificationCenterState`
  - `mark_notification_read()` / `mark_all_notifications_read()` 后推 `NotificationCenterState`

### 3.2 双端当前消费方式

#### iOS

- `FireAppViewModel` 注册 `StateObserver`
- observer 直接驱动：
  - `applySession`
  - `FireHomeFeedStore.applyTopicList`
  - `FireNotificationStore.apply`
- 旧的 `AppStateRefreshEvent` 拉取型处理保留了接口，但不再承担 home/notification 的主刷新路径

#### Android

- `FireSessionStore` 初始化时自动注册 `FireStateObserverRepository`
- 当前已直接消费：
  - `HomeViewModel` 监听 `sessionSnapshots`
  - `NotificationsViewModel` 监听 `notificationCenterSnapshots`
- `topicDetailFeedSnapshots` 已暴露，但 Android 话题详情列表仍沿用现有 screen/paging 组装路径

### 3.3 这次没有做的事

以下项目不属于这次 merge 的实现边界：

- 不把 Android home `PagingSource` 整体改成 snapshot-backed 列表
- 不把 topic detail 的 MessageBus 触发器整体下沉进 Rust observer 自动刷新
- 不移除所有同步 fetch API

原因不是“保留回退”，而是这些路径当前仍承担：

- 分页命令
- 显式刷新命令
- Cloudflare 恢复入口
- screen-owned 生命周期控制

本次变更已经把 observer 建成 authoritative push boundary；剩余部分应在后续单独围绕分页和 MessageBus 编排继续收口，而不是把这次改造成大范围控制流重写。

---

## 4. 双端渲染落地结果

### 4.1 iOS

当前链路：

```text
TopicPostState.render_document / render_cooked_html()
  -> FireRenderBlockNodeBuilder
  -> [FireRichTextNode]
  -> FireTopicPostRenderSegment
  -> ASTextNode / Nuke-backed 原生图片节点 / JXPhotoBrowser preview
```

保留下来的平台职责：

- 原生字体、颜色、交互样式
- `NSAttributedString` 生成
- Texture 节点布局、图片显示尺寸、失败重试和 JXPhotoBrowser 图片预览手势

已移出平台的职责：

- mention / mention-group / hashtag 语义识别
- quote 标准化
- details summary/body 拆分
- onebox 标题/描述提取
- emoji fallback 解析
- image attachment 选择与过滤，包括图片元信息文本和 quote chrome/avatar 过滤
- 相对 URL 解析
- 平台本地从 cooked HTML 合成 RenderDocument 的路径

### 4.2 Android

当前链路：

```text
TopicPostState.render_document / render_cooked_html()
  -> FireRenderBlockBuilder
  -> [FireRichTextNode]
  -> FireRichTextBlockBuilder
  -> FireRichTextView / Coil-backed ImageView / ZoomImage preview
```

保留下来的平台职责：

- `Spannable` span 组合
- 文本/链接/代码块样式
- `TextView` / `ImageView` 展示、图片失败重试和 ZoomImage 预览手势

已移出平台的职责与 iOS 相同，语义解析不再双写。

---

## 5. 文档与代码对齐后的结论

### 5.1 已完成

- [x] 新增 `fire-rich-text`
- [x] 新增共享 RenderDocument 模型
- [x] 新增 FFI `render_cooked_html`
- [x] 新增 RenderDocument 辅助 FFI（图片提取 / 纯文本）
- [x] `TopicPostState` 携带 `render_document`
- [x] iOS 富文本改为消费 `RenderDocumentState`
- [x] Android 富文本改为消费 `RenderDocumentState`
- [x] 双端提取出 RenderDocument builder 分层，平台 parser 不再承担语义映射
- [x] 删除双端 topic detail 正文 cooked HTML fallback；平台缺少 `render_document` 时暴露缺口，不伪造正文
- [x] 新增统一 `StateObserver`
- [x] Rust 内部建立 observer 注册与推送机制
- [x] Rust observer 推送具备 debounce 与 callback 错误隔离
- [x] iOS 接入 session/topic-list/notification/topic-detail-feed observer 消费入口
- [x] Android 接入 session/notification observer 消费入口

### 5.2 当前明确保留的边界

- [x] 保留平台原生显示适配器，不引入并行 renderer 或 cooked HTML fallback
- [x] 保留显式分页/刷新命令
- [x] Rust 内部保留 `parse_cooked_html()` 作为 parser / AST 单测入口；平台不得调用它来渲染 topic body
- [x] 不把 observer 扩大成无边界的“任何状态变化都广播”

---

## 6. 验证

本次实现已通过以下验证：

- `cargo test -p fire-rich-text -p fire-uniffi-types -p fire-uniffi-topics -p fire-uniffi --lib`
- `cargo test -p fire-uniffi -p fire-uniffi-topics -p fire-uniffi-notifications -p fire-core --lib`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- `cd native/android-app && ./gradlew compileDebugKotlin`

---

## 7. 后续演进方向

后续如果继续收口，可以沿这三条线推进，而不需要回退本次结构：

1. Android home 改成 observer-fed snapshot + adapter diff，而不是 PagingSource refresh
2. topic detail 继续维持 source snapshot + tree presentation 的显式双层契约，而不是重新引入 processed feed snapshot
3. profile / bookmark / 其他 `cooked` 文本字段继续优先消费 `RenderDocumentState`
