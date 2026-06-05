# Fire Rich Text + StateObserver 改造设计

> 日期: 2026-06-05
> 状态: Draft
> 范围: fire-rich-text crate + StateObserver 推送模型
> 策略: 先 Rich-Text 后 StateObserver（方案 A）

---

## 1. 背景与动机

### 1.1 当前问题

**富文本渲染双端重复：**

Rust 核心层目前只做 HTML → AST 解析（`parse_cooked_html`，~610 行），生成 flat `CookedHtmlNode` 数组。AST → 平台渲染模型的转换在双端各实现了一遍：

| 平台 | 文件 | 行数 | 重复逻辑 |
|------|------|------|----------|
| iOS | `FireRichTextRenderer.swift` | ~1700 | 树重建、语义检测、URL 解析、TextStyle 继承、Quote 标准化、Details 拆分、表格降级、图片提取、AttributedString 渲染 |
| Android | `FireRichTextParser.kt` + `FireSpannableBuilder.kt` | ~840 | 同上 |

两端 ~1200 行逻辑完全相同的解析代码，改一个 bug 要改两处。

**状态同步轮询模式：**

双端通过同步调用 Rust handle 方法拉取状态（如 `topicDetailSnapshot()`）。Rust 无法主动通知平台层变更，导致：
- 各 Store/ViewModel 散布轮询逻辑
- MessageBus 事件到达后仍需平台主动拉取完整 snapshot
- 状态变更延迟取决于轮询频率

### 1.2 目标

1. **消灭双端富文本重复代码**：将 AST → 渲染模型转换统一到 Rust `fire-rich-text` crate
2. **建立 RenderBlock 数据基础**：为后续 node-per-block 渲染、StateObserver payload 统一奠定基础
3. **建立 StateObserver 推送模型**：Rust 主动推送 immutable snapshots，消除平台轮询

---

## 2. 方案选择

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A（推荐）** | 先 Rich-Text 后 StateObserver | RenderBlock 先奠定数据基础，StateObserver payload 一次到位 | 总周期 4-6 周 |
| B | 先 StateObserver 后 Rich-Text | StateObserver 改造面较小 | StateObserver payload 基于 CookedHtml AST，后续需二次迁移 |
| C | 并行推进 | 总周期最短 | FFI 接口变更冲突风险高 |

**选择方案 A**：RenderBlock 是 StateObserver payload 的数据基础。先建立数据模型，再做推送机制，避免二次迁移。

---

## 3. fire-rich-text Crate 设计

### 3.1 Crate 结构

```
rust/crates/fire-rich-text/
  Cargo.toml
  src/
    lib.rs                    ← crate 入口，导出公共 API
    render_block.rs           ← RenderBlock / RenderBlockKind / TextStyle / CellAlignment
    ast_to_render_block.rs    ← CookedHtmlDocument → RenderBlock tree 核心转换
    text_style_resolver.rs    ← AST 节点属性 → TextStyle 计算（含继承链）
    url_resolver.rs           ← 相对 URL → 绝对 URL 解析
    table_formatter.rs        ← 表格结构化 + text fallback 生成
    image_collector.rs        ← RenderBlock tree 图片附件提取
    plain_text_builder.rs     ← RenderBlock tree → 纯文本生成
```

### 3.2 RenderBlock 类型系统

```rust
// render_block.rs

/// 扁平渲染指令，携带完整布局信息，平台无需二次计算
struct RenderBlock {
    kind: RenderBlockKind,
    children: Vec<RenderBlock>,
    metadata: HashMap<String, String>,
}

/// 28 种渲染块类型
enum RenderBlockKind {
    // 块级
    Document,
    Paragraph,
    Heading { level: u8 },
    Blockquote,
    OrderedList { start: u32 },
    UnorderedList,
    ListItem { index: u32 },
    CodeBlock { language: Option<String>, code: String },
    Table { column_count: usize },
    TableRow,
    TableCell { alignment: CellAlignment },
    Spoiler,
    Details { summary: String },
    Divider,
    Onebox {
        url: String,
        title: String,
        description: Option<String>,
        image_url: Option<String>,
    },
    Iframe { url: String, title: Option<String> },
    Image {
        url: String,
        alt: String,
        width: Option<u32>,
        height: Option<u32>,
    },
    Attachment {
        url: String,
        filename: String,
        file_size: Option<String>,
    },

    // 行内
    Text { content: String, style: TextStyle },
    InlineCode { code: String },
    Link { url: String, title: Option<String> },
    Bold,
    Italic,
    Strikethrough,
    Emoji { name: String, url: Option<String> },
    Mention { username: String, url: String },
    Hashtag { tag: String, url: String },

    // 兜底
    Unknown,
}

/// 文本样式，携带完整样式信息
struct TextStyle {
    bold: bool,
    italic: bool,
    strikethrough: bool,
    code: bool,
    link_url: Option<String>,
    font_size: Option<u8>,
    color: Option<String>,
}

/// 表格单元格对齐
enum CellAlignment {
    Left,
    Center,
    Right,
}
```

### 3.3 核心转换逻辑（ast_to_render_block.rs）

将当前双端重复的 ~1200 行解析逻辑统一到 Rust：

| 转换步骤 | 当前位置（双端重复） | 迁移到 Rust 后 |
|----------|---------------------|---------------|
| 树重建 | iOS `FireRichTextParser` + Android `FireRichTextParser` | `ast_to_render_block.rs` |
| 语义检测（CSS class → mention/hashtag/emoji/onebox/spoiler/attachment） | 双端各 ~200 行 | `ast_to_render_block.rs` |
| URL 解析（相对 → 绝对） | 双端各 ~50 行 | `url_resolver.rs` |
| TextStyle 继承（bold/italic/strikethrough 从父节点继承） | 双端各 ~80 行 | `text_style_resolver.rs` |
| Quote 标准化（展开嵌套 blockquote，提取 author + post_number） | 双端各 ~100 行 | `ast_to_render_block.rs` |
| Details 拆分（summary + body） | 双端各 ~40 行 | `ast_to_render_block.rs` |
| 表格降级（保留结构 + text fallback） | 双端各 ~60 行 | `table_formatter.rs` |
| 图片提取（独立 Image 节点收集） | 双端各 ~50 行 | `image_collector.rs` |

### 3.4 公共 API

```rust
// lib.rs

/// 主入口：HTML → RenderBlock tree
/// 替代 parse_cooked_html() 用于渲染场景
pub fn render_cooked_html(html: &str, base_url: &str) -> RenderBlock;

/// 从 RenderBlock tree 提取图片附件列表
pub fn collect_images(block: &RenderBlock) -> Vec<ImageAttachment>;

/// 从 RenderBlock tree 生成纯文本
pub fn plain_text_from_render_block(block: &RenderBlock) -> String;

/// 保留向后兼容：原始 AST 解析仍由 fire-core 提供
```

### 3.5 依赖关系

```
fire-rich-text 依赖:
  fire-models (CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind)
  scraper + html5ever (已在 fire-core 中使用，但 fire-rich-text 不需要 — 它操作 AST 而非 HTML)
```

实际上 `fire-rich-text` 只依赖 `fire-models` 中的 AST 类型，不依赖 HTML 解析库。HTML → AST 仍在 `fire-core` 中完成，`fire-rich-text` 只负责 AST → RenderBlock 转换。

---

## 4. FFI 边界变更

### 4.1 新增 FFI 类型

在 `fire-uniffi-types` 中新增：

```rust
// FFI 镜像类型
pub struct RenderBlockState {
    pub kind: RenderBlockKindState,
    pub children: Vec<RenderBlockState>,
    pub metadata: HashMap<String, String>,
}

pub enum RenderBlockKindState {
    Document,
    Paragraph,
    Heading { level: u8 },
    Text { content: String, style: Box<TextStyleState> },
    Image { url: String, alt: String, width: Option<u32>, height: Option<u32> },
    CodeBlock { language: Option<String>, code: String },
    InlineCode { code: String },
    Blockquote,
    OrderedList { start: u32 },
    UnorderedList,
    ListItem { index: u32 },
    Link { url: String, title: Option<String> },
    Bold,
    Italic,
    Strikethrough,
    Spoiler,
    Details { summary: String },
    Divider,
    Table { column_count: usize },
    TableRow,
    TableCell { alignment: CellAlignmentState },
    Emoji { name: String, url: Option<String> },
    Mention { username: String, url: String },
    Hashtag { tag: String, url: String },
    Onebox { url: String, title: String, description: Option<String>, image_url: Option<String> },
    Iframe { url: String, title: Option<String> },
    Attachment { url: String, filename: String, file_size: Option<String> },
    Unknown,
}

pub struct TextStyleState {
    pub bold: bool,
    pub italic: bool,
    pub strikethrough: bool,
    pub code: bool,
    pub link_url: Option<String>,
    pub font_size: Option<u8>,
    pub color: Option<String>,
}

pub enum CellAlignmentState {
    Left,
    Center,
    Right,
}
```

### 4.2 新增 FFI 函数

在 `fire-uniffi` 中新增：

```rust
/// 渲染入口：HTML → RenderBlock tree（替代 parse_cooked_html 用于渲染）
fn render_cooked_html(html: String, base_url: String) -> RenderBlockState;

/// 从 RenderBlock tree 提取图片列表
fn collect_images_from_render_block(block: &RenderBlockState) -> Vec<ImageAttachmentState>;

/// 从 RenderBlock tree 生成纯文本
fn plain_text_from_render_block(block: &RenderBlockState) -> String;
```

### 4.3 向后兼容

- `parse_cooked_html()` 保持不变，不破坏现有代码
- `render_cooked_html()` 为新增函数，双端可渐进切换
- 旧函数在 Phase 3 清理阶段移除

---

## 5. 双端渲染层改造

### 5.1 iOS 改造

#### 新增

| 文件 | 职责 |
|------|------|
| `FireRenderBlockNodeBuilder.swift` | RenderBlockState → FireRenderBlockNode（轻量映射，~150 行） |
| `FireRenderBlockNode.swift` | 渲染节点模型（简化版，~100 行） |

#### 改造流程

```
当前: Rust parse_cooked_html() → CookedHtmlDocumentState
      → FireRichTextParser.mapNode() (~770 行) → FireRichTextNode
      → FireRichTextAttributedStringBuilder (~630 行) → NSAttributedString
      → ASTextNode (Texture)

改造后: Rust render_cooked_html() → RenderBlockState
        → FireRenderBlockNodeBuilder (~150 行) → FireRenderBlockNode
        → 各 ASDisplayNode（node-per-block 渲染）
```

#### 代码量变化

| 组件 | 当前行数 | 改造后行数 | 减少 |
|------|---------|-----------|------|
| AST → 平台模型 | ~770 | ~150 | -80% |
| 模型定义 | ~34 | ~100 | +66 (更结构化) |
| 渲染逻辑 | ~630 | ~300 | -52% |
| **总计** | ~1434 | ~550 | **-62%** |

### 5.2 Android 改造

#### 新增

| 文件 | 职责 |
|------|------|
| `FireRenderBlockBuilder.kt` | RenderBlockState → Spannable / Compose nodes（~150 行） |

#### 改造流程

```
当前: Rust parse_cooked_html() → CookedHtmlDocumentState
      → FireRichTextParser.mapNode() (~434 行) → FireRichTextNode
      → FireSpannableBuilder (~404 行) → SpannableStringBuilder

改造后: Rust render_cooked_html() → RenderBlockState
        → FireRenderBlockBuilder (~150 行) → SpannableStringBuilder
```

#### 代码量变化

| 组件 | 当前行数 | 改造后行数 | 减少 |
|------|---------|-----------|------|
| AST → 平台模型 | ~434 | ~50 | -88% |
| 模型定义 | ~34 | ~30 | -12% |
| Spannable 渲染 | ~404 | ~300 | -26% |
| **总计** | ~872 | ~380 | **-56%** |

---

## 6. StateObserver 设计

### 6.1 Rust 侧

```rust
// fire-uniffi-types

/// 平台实现的回调 trait，通过 UniFFI callback interface 注册
trait StateObserver: Send + Sync {
    /// 话题列表 snapshot 变更
    fn on_topic_list_snapshot(&self, kind: String, snapshot: TopicListState);

    /// 话题详情 snapshot 变更
    fn on_topic_detail_snapshot(&self, topic_id: u64, snapshot: TopicDetailSnapshotState);

    /// 通知中心 snapshot 变更
    fn on_notification_snapshot(&self, snapshot: NotificationCenterSnapshotState);

    /// 会话状态 snapshot 变更
    fn on_session_snapshot(&self, snapshot: SessionSnapshotState);
}
```

### 6.2 注册机制

```rust
// 各 Handle 提供
impl FireTopicsHandle {
    pub fn register_observer(&self, observer: Arc<dyn StateObserver>);
    pub fn unregister_observer(&self);
}
```

### 6.3 推送策略

| 策略 | 说明 |
|------|------|
| Debounce | 同一域的连续变更合并，100ms 窗口内只推送最新 snapshot |
| Immutable snapshot | 每次 clone 完整 snapshot，平台无需加锁 |
| 主线程安全 | 回调通过 FFI runtime 调度到平台主线程 |
| 错误隔离 | 单个回调异常不影响其他观察者或其他域 |

### 6.4 平台侧

**iOS：**
- `FireSessionStore`（actor）实现 UniFFI `StateObserver` protocol
- 收到 snapshot 后通过 Combine `@Published` 推送到各 View/Store
- `FireTopicDetailStore`、`FireNotificationStore` 等改为被动接收

**Android：**
- ViewModel 实现 observer interface
- 通过 `StateFlow` / `SharedFlow` 推送到 UI 层

### 6.5 与 Rich-Text 的协同

StateObserver 推送的 `TopicDetailSnapshotState` 中，帖子内容字段从 `CookedHtmlDocumentState` 升级为 `RenderBlockState`：

```
改造前: on_topic_detail_snapshot(topic_id, snapshot)
        snapshot.posts[i].cooked_html → CookedHtmlDocumentState

改造后: on_topic_detail_snapshot(topic_id, snapshot)
        snapshot.posts[i].render_blocks → RenderBlockState
```

---

## 7. 实施阶段

### Phase 0：基础设施（1 周）

- [ ] 创建 `fire-rich-text` crate 骨架
- [ ] 定义 `RenderBlock` / `RenderBlockKind` / `TextStyle` / `CellAlignment` 类型
- [ ] 定义 FFI 镜像类型
- [ ] 单元测试框架搭建

### Phase 1：AST → RenderBlock 转换（2 周）

- [ ] 实现 `ast_to_render_block.rs`（树重建 + 语义检测）
- [ ] 实现 `url_resolver.rs`
- [ ] 实现 `text_style_resolver.rs`
- [ ] 实现 `table_formatter.rs`
- [ ] 实现 `image_collector.rs`
- [ ] 实现 `plain_text_builder.rs`
- [ ] 对比测试：RenderBlock 输出 vs 双端当前渲染结果

### Phase 2：FFI + 双端集成（2 周）

- [ ] `render_cooked_html()` FFI 函数
- [ ] iOS: `FireRenderBlockNodeBuilder` + 集成测试
- [ ] Android: `FireRenderBlockBuilder` + 集成测试
- [ ] 双端并行 A/B 测试（新旧 pipeline 对比渲染结果）

### Phase 3：切换与清理（1 周）

- [ ] 双端默认启用新 pipeline
- [ ] 标记旧 `parse_cooked_html()` 为 deprecated
- [ ] 移除双端旧 `FireRichTextParser` 代码
- [ ] 更新文档

### Phase 4：StateObserver（2-3 周）

- [ ] 定义 `StateObserver` callback trait
- [ ] 各 Handle 增加 observer 注册/注销
- [ ] 实现 debounce 推送机制
- [ ] 域验证：notifications（变更频率适中）
- [ ] 域扩展：session → topic list → topic detail
- [ ] 双端接入 observer，移除轮询代码
- [ ] 移除旧同步拉取方法

**总预估：8-10 周**

---

## 8. 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| RenderBlock 类型设计不完整，遗漏双端需要的字段 | Phase 1 中与双端现有渲染逻辑逐一对比，确保无遗漏 |
| FFI callback trait 性能问题（频繁 clone snapshot） | Debounce + 仅在真实变更时推送 |
| 双端切换期间新旧 pipeline 结果不一致 | A/B 测试框架，像素级对比渲染结果 |
| StateObserver 回调异常影响 Rust 侧稳定性 | 错误隔离 + catch_unwind |
| RenderBlock tree 内存占用高于 flat AST | 可选 flat mode（metadata 存 parent_id），但树形模式更直观 |

---

## 9. 成功标准

1. **代码量**：双端富文本解析代码减少 >50%（~1200 行 → ~400 行）
2. **一致性**：双端渲染结果与改造前像素级一致
3. **性能**：RenderBlock pipeline 耗时不超过当前 CookedHtml pipeline
4. **StateObserver**：双端消除所有状态轮询，通过 observer 接收变更
5. **可维护性**：富文本渲染逻辑单点维护（Rust），双端只做布局/样式映射
