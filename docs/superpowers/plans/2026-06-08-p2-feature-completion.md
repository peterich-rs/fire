# P2 功能补全 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 API 表面中的未实现功能，LDC/CDK OAuth 优先实现

**Architecture:** LDC/CDK OAuth 从 Rust core 新模块开始，通过 UniFFI 暴露给 iOS/Android 原生 UI。编辑器增强、线程视图、话题搜索等功能在现有 Rust 模型基础上扩展原生 UI 层。

**Tech Stack:** Rust (fire-core, fire-models, fire-uniffi) / SwiftUI (iOS) / Kotlin + ViewBinding (Android)

---

## File Structure

### Rust Changes

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `rust/crates/fire-models/src/ldc.rs` | LDC/CDK 模型类型 |
| Create | `rust/crates/fire-core/src/core/ldc.rs` | LDC OAuth + API 实现 |
| Create | `rust/crates/fire-core/src/core/cdk.rs` | CDK OAuth + API 实现 |
| Create | `rust/crates/fire-core/src/ldc_payloads.rs` | LDC/CDK JSON 解析 |
| Modify | `rust/crates/fire-models/src/lib.rs` | 注册 ldc 模块 |
| Modify | `rust/crates/fire-core/src/core/mod.rs` | 注册 ldc/cdk 模块 |
| Modify | `rust/crates/fire-uniffi/src/lib.rs` | 暴露 LDC/CDK handle |

### iOS Changes

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `App/Views/FireLDCView.swift` | LDC 信用主页 |
| Create | `App/Views/FireCDKView.swift` | CDK 连接页 |
| Create | `App/Views/FireConnectStatsView.swift` | Connect 统计页 |
| Create | `App/Views/FireThreadedView.swift` | 线程视图 |
| Create | `App/Core/FireMarkdownToolbar.swift` | Markdown 格式化工具栏 |
| Modify | `App/Views/FireComposerView.swift` | 集成工具栏和引用插入 |
| Modify | `App/Views/FirePostEditorView.swift` | 升级为 FireComposerTextView |
| Modify | `App/TopicDetail/` 相关文件 | 话题通知级别 UI、话题内搜索 |

### Android Changes

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ui/ldc/LDCFragment.kt` | LDC 信用主页 |
| Create | `ui/ldc/LDCViewModel.kt` | LDC ViewModel |
| Create | `ui/ldc/CDKFragment.kt` | CDK 连接页 |
| Create | `ui/topicdetail/ThreadedPostAdapter.kt` | 线程视图适配器 |
| Create | `ui/composer/MarkdownToolbarView.kt` | Markdown 工具栏 |
| Modify | `ui/composer/ReplyComposerSheet.kt` | 集成工具栏 |

---

## Task 1: LDC/CDK — Rust 模型层

**Files:**
- Create: `rust/crates/fire-models/src/ldc.rs`
- Modify: `rust/crates/fire-models/src/lib.rs`

- [x] **Step 1: 创建 LDC/CDK 模型类型**

Implemented in `rust/crates/fire-models/src/ldc.rs`.

Implementation note: the original schematic fields were replaced with the observed protocol contract from `docs/knowledge/api/13-ldc-cdk-oauth.md` and `references/fluxdo/lib/models/`.

- `LdcUserInfo` mirrors `GET https://credit.linux.do/api/v1/oauth/user-info`: `nickname`, `trust_level`, `avatar_url`, receive/payment/transfer/community totals, balances, quota, pay flags, pay level, daily limit, and optional gamification score.
- `CdkUserInfo` mirrors `GET https://cdk.linux.do/api/v1/oauth/user-info`: `nickname`, `trust_level`, `avatar_url`, and `score`; it intentionally does not reuse LDC balance/payment fields.
- `LdcAuthorizationUrl`, `CdkAuthorizationUrl`, `LdcApprovalStatus`, `LdcPayment`, `LdcPaymentList`, `ConnectTrustLevelProgress`, and `TrustLevelRequirement` are present for the next core and UI tasks.
- `LdcApprovalStatus::Approved` carries both `code` and `state`, matching the OAuth approval redirect.
- Serialization tests cover the documented LDC and CDK `user-info` shapes.

- [x] **Step 2: 注册模块**

在 `rust/crates/fire-models/src/lib.rs` 中添加：

```rust
mod ldc;
pub use ldc::*;
```

- [x] **Step 3: 构建验证**

Run: `cd rust && cargo check -p fire-models 2>&1 | tail -5`
Expected: `Finished` without errors

- [x] **Step 4: Commit**

```bash
git add rust/crates/fire-models/src/ldc.rs rust/crates/fire-models/src/lib.rs
git commit -m "feat(models): add LDC Credit and CDK OAuth model types"
```

---

## Task 2: LDC/CDK — Rust Core 实现

**Files:**
- Create: `rust/crates/fire-core/src/core/ldc.rs`
- Create: `rust/crates/fire-core/src/core/cdk.rs`
- Create: `rust/crates/fire-core/src/ldc_payloads.rs`
- Modify: `rust/crates/fire-core/src/core/mod.rs`
- Modify: `rust/crates/fire-core/src/core/network.rs`
- Modify: `rust/crates/fire-core/src/lib.rs`
- Modify: `rust/crates/fire-core/Cargo.toml`
- Modify: `rust/crates/fire-models/src/ldc.rs`

- [x] **Step 1: 实现 LDC OAuth 流程**

Implemented in `rust/crates/fire-core/src/core/ldc.rs`.

Implementation note: the stale schematic endpoints were replaced with the observed contract in `docs/knowledge/api/13-ldc-cdk-oauth.md`.

- `ldc_authorization_url()` calls `GET https://credit.linux.do/api/v1/oauth/login`.
- `ldc_approval_link()` loads the returned authorization URL as HTML and parses `a[href*="/oauth2/approve/"]`.
- `ldc_approve()` calls `https://connect.linux.do/oauth2/approve/...` with redirects disabled and parses `code` + `state` from `Location`.
- `ldc_callback(code, state)` posts `application/x-www-form-urlencoded` to `https://credit.linux.do/api/v1/oauth/callback`.
- `ldc_user_info()` calls `GET https://credit.linux.do/api/v1/oauth/user-info`.
- `ldc_logout()` calls `GET https://credit.linux.do/api/v1/oauth/logout`.
- `ldc_reward()` implements the documented Basic-auth JSON reward API at `https://credit.linux.do/epay/pay/distribute`.
- No LDC payment-history endpoint was added because it is not present in the current knowledge doc.

- [x] **Step 2: 实现 CDK OAuth 流程**

Implemented in `rust/crates/fire-core/src/core/cdk.rs`.

- CDK uses the same OAuth flow helpers as LDC against `https://cdk.linux.do/api/v1/oauth/*`.
- CDK user-info is parsed into `CdkUserInfo` with `score`; it does not reuse LDC balance/payment fields.

- [x] **Step 3: 实现 JSON/HTML 解析**

Implemented in `rust/crates/fire-core/src/ldc_payloads.rs`.

- Parsers return `serde_json::Error`, matching existing `fire-core` payload modules.
- Unit tests cover LDC user-info, CDK user-info, authorization URL state extraction, approval HTML link extraction, and reward success/failure response shapes.

- [x] **Step 4: 注册模块**

`rust/crates/fire-core/src/core/mod.rs` registers `mod ldc;` and `mod cdk;`. `rust/crates/fire-core/src/lib.rs` registers `mod ldc_payloads;`.

- [x] **Step 5: 构建验证**

Run: `cd rust && cargo check -p fire-core`
Result: passed.

- [x] **Step 6: 运行测试**

Run: `cd rust && cargo test -p fire-core`
Result: passed.

- [x] **Step 7: Commit**

```bash
git add rust/crates/fire-core/Cargo.toml Cargo.lock rust/crates/fire-core/src/core/ldc.rs rust/crates/fire-core/src/core/cdk.rs rust/crates/fire-core/src/ldc_payloads.rs rust/crates/fire-core/src/core/mod.rs rust/crates/fire-core/src/core/network.rs rust/crates/fire-core/src/lib.rs rust/crates/fire-models/src/ldc.rs docs/superpowers/plans/2026-06-08-p2-feature-completion.md
git commit -m "feat(core): implement LDC Credit and CDK OAuth flows"
```

---

## Task 3: LDC/CDK — UniFFI 桥接

**Files:**
- Create: `rust/crates/fire-uniffi-ldc/` (新 crate)
- Modify: `rust/crates/fire-uniffi/src/lib.rs`
- Modify: `rust/crates/fire-uniffi-types/` (新增 LDC state types)

- [ ] **Step 1: 创建 fire-uniffi-ldc crate**

遵循现有 handle crate 模式（如 `fire-uniffi-search`），创建：

- `rust/crates/fire-uniffi-ldc/Cargo.toml`
- `rust/crates/fire-uniffi-ldc/src/lib.rs`

```rust
use fire_core::FireCore;
use fire_uniffi_types::FireUniFfiError;

#[derive(uniffi::Object)]
pub struct FireLdcHandle {
    core: std::sync::Arc<FireCore>,
}

#[uniffi::export]
impl FireLdcHandle {
    pub async fn authorization_url(&self) -> Result<String, FireUniFfiError> {
        let result = self.core.ldc_authorization_url().await?;
        Ok(result.url)
    }

    pub async fn approval_link(&self, authorization_url: String) -> Result<String, FireUniFfiError> {
        self.core.ldc_approval_link(&authorization_url).await.map_err(Into::into)
    }

    pub async fn approve(&self, approve_path: String) -> Result<LdcApprovalStatusState, FireUniFfiError> {
        let status = self.core.ldc_approve(&approve_path).await?;
        Ok(LdcApprovalStatusState::from(status))
    }

    pub async fn callback(&self, code: String, state: String) -> Result<(), FireUniFfiError> {
        self.core.ldc_callback(&code, &state).await?;
        Ok(())
    }

    pub async fn user_info(&self) -> Result<LdcUserInfoState, FireUniFfiError> {
        let info = self.core.ldc_user_info().await?;
        Ok(LdcUserInfoState::from(info))
    }

    pub async fn logout(&self) -> Result<(), FireUniFfiError> {
        self.core.ldc_logout().await?;
        Ok(())
    }
}
```

State types（`LdcUserInfoState`, `CdkUserInfoState`, `LdcApprovalStatusState`, reward request/result states）使用 `#[derive(uniffi::Record)]` 或合适的 UniFFI enum/object 形态。CDK handle should expose the symmetric authorization URL, approval link, approve, callback, user-info, and logout methods. LDC reward can be exposed from the same handle after deciding where client credentials are stored.

- [ ] **Step 2: 在 FireAppCore 中暴露 handle**

在 `fire-uniffi/src/lib.rs` 的 `FireAppCore` 中添加 `ldc` handle。

- [ ] **Step 3: 构建验证**

Run: `cd rust && cargo check -p fire-uniffi 2>&1 | tail -5`
Expected: `Finished` without errors

- [ ] **Step 4: Commit**

```bash
git add rust/crates/fire-uniffi-ldc/ rust/crates/fire-uniffi/src/lib.rs rust/crates/fire-uniffi-types/
git commit -m "feat(uniffi): add LDC/CDK handle and FFI bridge"
```

---

## Task 4: LDC/CDK — iOS UI

**Files:**
- Create: `native/ios-app/App/Views/FireLDCView.swift`
- Create: `native/ios-app/App/Views/FireCDKView.swift`
- Modify: `native/ios-app/App/Views/FireProfileView.swift` (添加入口)

- [ ] **Step 1: 创建 LDC 信用视图**

`FireLDCView.swift`：

```swift
import SwiftUI

struct FireLDCView: View {
    @State private var userInfo: LdcUserInfoState?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let info = userInfo {
                Section {
                    HStack {
                        Text("余额")
                            .font(FireTheme.tertiaryInk)
                        Spacer()
                        Text(info.balance)
                            .font(.title2.bold())
                            .foregroundStyle(FireTheme.accent)
                    }
                    // total_earned, total_paid, pending_balance
                } header: {
                    Text("账户概览")
                }

                Section {
                    // 支付记录列表 (payments)
                } header: {
                    Text("交易记录")
                }
            }
        }
        .task { await loadUserInfo() }
        .navigationTitle("LDC 信用")
    }

    private func loadUserInfo() async {
        // 调用 Rust core -> LdcHandle.user_info()
    }
}
```

- [ ] **Step 2: 创建 CDK 连接视图**

`FireCDKView.swift`：显示绑定状态、授权按钮、用户信息。

- [ ] **Step 3: 在 Profile 中添加入口**

在 `FireProfileView` 的 sections 中添加：

```swift
NavigationLink {
    FireLDCView()
} label: {
    Label("LDC 信用", systemImage: "creditcard")
}
```

- [ ] **Step 4: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Views/FireLDCView.swift native/ios-app/App/Views/FireCDKView.swift native/ios-app/App/Views/FireProfileView.swift
git commit -m "feat(ios): add LDC Credit and CDK connection views"
```

---

## Task 5: LDC/CDK — Android UI

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/ldc/LDCFragment.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/ldc/LDCViewModel.kt`
- Create: `native/android-app/src/main/res/layout/fragment_ldc.xml`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt`

- [ ] **Step 1: 创建 LDC ViewModel 和 Fragment**

遵循 Android MVVM 模式（参考 `HomeViewModel` + `HomeFragment`）：
- `LDCViewModel`: `StateFlow<LdcUserInfoState?>`, `loadUserInfo()`, `loadPayments()`
- `LDCFragment`: 余额展示 + 交易记录列表 + 空状态/加载状态

- [ ] **Step 2: 布局和导航**

`fragment_ldc.xml`：余额卡片 + 交易记录 RecyclerView。
导航图添加 `ldcFragment`。
Profile 中添加入口。

- [ ] **Step 3: 构建验证**

Run: `cd native/android-app && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/ldc/ native/android-app/src/main/res/layout/fragment_ldc.xml native/android-app/src/main/res/navigation/fire_nav_graph.xml native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt
git commit -m "feat(android): add LDC Credit and CDK connection screens"
```

---

## Task 6: 线程视图 — iOS

**Files:**
- Create: `native/ios-app/App/Views/FireThreadedView.swift`
- Modify: `native/ios-app/App/TopicDetail/FireTopicDetailToolbarCoordinator.swift` (添加切换按钮)
- Reference: `rust/crates/fire-models/src/topic_detail.rs` (TopicThread, TopicThreadFlatPost)

- [ ] **Step 1: 创建线程视图组件**

```swift
import SwiftUI

struct FireThreadedView: View {
    let threads: [TopicThreadState]
    let onPostTap: (UInt64) -> Void
    let onReplyTap: (UInt64) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(threads) { thread in
                FireThreadRow(thread: thread, onPostTap: onPostTap, onReplyTap: onReplyTap)
                FireTheme.divider.frame(height: 1)
            }
        }
    }
}

struct FireThreadRow: View {
    let thread: TopicThreadState
    let onPostTap: (UInt64) -> Void
    let onReplyTap: (UInt64) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Root post (always visible)
            FireThreadedPostRow(post: thread.rootPost, depth: 0, onTap: onPostTap)

            // Replies (expandable)
            if isExpanded {
                ForEach(thread.replies) { reply in
                    FireThreadedPostRow(post: reply, depth: 1, onTap: onPostTap)
                }
            }

            Button {
                withAnimation(.fireDefault) { isExpanded.toggle() }
            } label: {
                Text(isExpanded ? "收起回复" : "展开 \(thread.replies.count) 条回复")
                    .font(.caption)
                    .foregroundStyle(FireTheme.accent)
                    .padding(.leading, 20)
                    .padding(.vertical, 8)
            }
        }
    }
}

struct FireThreadedPostRow: View {
    let post: TopicThreadFlatPostState
    let depth: Int
    let onTap: (UInt64) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if depth > 0 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(FireTheme.accent.opacity(0.3))
                    .frame(width: 3)
                    .padding(.trailing, 12)
                    .padding(.leading, 8)
            }
            VStack(alignment: .leading, spacing: 4) {
                // Author + timestamp
                HStack {
                    Text(post.username)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(post.createdAt)
                        .font(.caption)
                        .foregroundStyle(FireTheme.tertiaryInk)
                }
                // Excerpt
                Text(post.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(FireTheme.ink)
                    .lineLimit(3)
            }
            .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap(post.id) }
    }
}
```

- [ ] **Step 2: 话题详情工具栏添加视图切换**

在话题详情顶部工具栏添加「树状」/「线程」切换按钮。切换时重新渲染帖子列表。

- [ ] **Step 3: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/Views/FireThreadedView.swift native/ios-app/App/TopicDetail/
git commit -m "feat(ios): add threaded view mode for topic detail"
```

---

## Task 7: 线程视图 — Android

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/ThreadedPostAdapter.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt` (添加切换按钮)
- Modify: `native/android-app/src/main/res/layout/activity_topic_detail.xml` (添加切换 toggle)

- [ ] **Step 1: 创建 ThreadedPostAdapter**

展开/折叠式线程列表适配器，使用缩进表示层级。

- [ ] **Step 2: TopicDetailActivity 添加视图模式切换**

工具栏添加切换按钮（树状 ↔ 线程），切换时更换 RecyclerView 的 Adapter。

- [ ] **Step 3: 构建验证**

Run: `cd native/android-app && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/topicdetail/ThreadedPostAdapter.kt native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt
git commit -m "feat(android): add threaded view mode for topic detail"
```

---

## Task 8: 编辑器增强 — Markdown 工具栏

**Files:**
- Create: `native/ios-app/App/Core/FireMarkdownToolbar.swift`
- Create: `native/android-app/src/main/java/com/fire/app/ui/composer/MarkdownToolbarView.kt`
- Modify: `native/ios-app/App/Views/FireComposerView.swift`

- [ ] **Step 1: iOS Markdown 工具栏组件**

```swift
import SwiftUI

struct FireMarkdownToolbar: View {
    let onInsert: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                toolbarButton("B", bold: true) { onInsert("**") }
                toolbarButton("I", italic: true) { onInsert("*") }
                toolbarButton("S", strikethrough: true) { onInsert("~~") }
                toolbarButton("<>", systemImage: "chevron.left.forwardslash.chevron.right") { onInsert("`") }
                toolbarButton("```", systemImage: "text.append") { onInsert("```\n") }
                toolbarButton("Quote", systemImage: "text.quote") { onInsert("> ") }
                toolbarButton("UL", systemImage: "list.bullet") { onInsert("- ") }
                toolbarButton("OL", systemImage: "list.number") { onInsert("1. ") }
                toolbarButton("Link", systemImage: "link") { onInsert("[") }
                toolbarButton("Image", systemImage: "photo") { onInsert("![") }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 40)
        .background(FireTheme.chrome)
    }

    private func toolbarButton(
        _ title: String? = nil,
        bold: Bool = false,
        italic: Bool = false,
        strikethrough: Bool = false,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else if let title {
                    Text(title)
                        .font(.system(size: 14, weight: bold ? .bold : (italic ? .medium : .regular)))
                        .strikethrough(strikethrough)
                }
            }
            .frame(width: 36, height: 36)
            .foregroundStyle(FireTheme.ink)
        }
        .accessibilityLabel(title ?? systemImage ?? "")
    }
}
```

- [ ] **Step 2: 集成到 FireComposerView**

在键盘上方（`inputAccessoryView` 位置）添加 `FireMarkdownToolbar`。

`onInsert` 回调需要在 `UITextView` 的当前光标位置插入 Markdown 标记。

- [ ] **Step 3: Android Markdown 工具栏**

创建 `MarkdownToolbarView.kt`：水平 LinearLayout 内的格式化按钮组。

集成到 `ReplyComposerSheet`、`TopicComposerSheet`、`PrivateMessageComposerSheet`。

- [ ] **Step 4: 构建验证（两端）**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Run: `cd native/android-app && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: Both BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Core/FireMarkdownToolbar.swift native/ios-app/App/Views/FireComposerView.swift native/android-app/src/main/java/com/fire/app/ui/composer/MarkdownToolbarView.kt native/android-app/src/main/java/com/fire/app/ui/composer/
git commit -m "feat(composer): add Markdown formatting toolbar for iOS and Android"
```

---

## Task 9: 编辑器增强 — 引用插入

**Files:**
- Modify: `native/ios-app/App/Views/FireComposerView.swift`
- Modify: `native/ios-app/App/TopicDetail/` (post action callbacks)
- Modify: Android 对应文件

- [ ] **Step 1: iOS 引用插入实现**

在话题详情的帖子操作菜单中添加「引用回复」选项。

当用户选择引用时：
1. 提取选中帖子的 `cooked` 内容
2. 在编辑器中插入 `[quote="username, post:{number}, topic:{id}"]\n{plain_text}\n[/quote]\n\n`
3. 打开编辑器并将光标定位到引用之后

```swift
func insertQuote(username: String, postNumber: UInt32, topicId: UInt64, text: String) {
    let quote = "[quote=\"\(username), post:\(postNumber), topic:\(topicId)\"]\n\(text)\n[/quote]\n\n"
    composerTextView.insertTextAtCursor(quote)
}
```

- [ ] **Step 2: Android 引用插入**

同样的 `[quote]` 格式，在 `ReplyComposerSheet` 中添加引用插入方法。

- [ ] **Step 3: 构建验证**

Run: Both platforms build successfully

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "feat(composer): add quote insertion from topic detail posts"
```

---

## Task 10: 编辑器增强 — PostEditorView 升级

**Files:**
- Modify: `native/ios-app/App/Views/FirePostEditorView.swift`

- [ ] **Step 1: 替换基础 TextEditor**

将 `FirePostEditorView` 中的 SwiftUI `TextEditor` 替换为 `FireComposerTextView`（UITextView 包装），与主编辑器保持一致的编辑体验。

包含：
- `FireMarkdownToolbar` 集成
- 自动保存
- 预览模式
- 图片上传支持

- [ ] **Step 2: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme FireApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add native/ios-app/App/Views/FirePostEditorView.swift
git commit -m "refactor(ios): upgrade PostEditorView to use FireComposerTextView"
```

---

## Task 11: 话题通知级别控制

**Files:**
- Modify: `native/ios-app/App/TopicDetail/FireTopicDetailToolbarCoordinator.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt`
- Reference: `docs/knowledge/api/03-topics.md` (topic notification level API)

- [ ] **Step 1: iOS 通知级别按钮**

在话题详情工具栏添加通知级别按钮（bell 图标）。

点击弹出 `.confirmationDialog`：

```swift
.confirmationDialog("通知设置", isPresented: $showNotificationLevel) {
    Button("静音") { setLevel(.muted) }
    Button("常规") { setLevel(.regular) }
    Button("跟踪") { setLevel(.tracking) }
    Button("关注") { setLevel(.watching) }
    Button("取消", role: .cancel) {}
}
```

图标根据当前级别变化：静音用 `bell.slash.fill`，跟踪用 `bell.fill`，其他用 `bell`。

- [ ] **Step 2: Android 通知级别按钮**

在 `TopicDetailActivity` 工具栏添加同样的弹窗选择。

- [ ] **Step 3: 构建验证**

Run: Both platforms build successfully

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "feat(topic-detail): add topic notification level control to toolbar"
```

---

## Task 12: Reaction 选择器增强

**Files:**
- Modify: iOS topic detail reaction picker
- Modify: Android topic detail reaction picker
- Reference: `docs/knowledge/api/04-posts.md` (reaction APIs)

- [ ] **Step 1: 获取可用 Reaction 列表**

调用 Rust core 获取 `availableReactions` 列表，在选择器中展示完整表情网格。

- [ ] **Step 2: 搜索表情**

在选择器中添加搜索栏，过滤表情列表。

- [ ] **Step 3: Reaction 用户列表**

长按某个 Reaction 显示使用了该 Reaction 的用户列表。

- [ ] **Step 4: 构建验证**

Run: Both platforms build successfully

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "feat(reactions): enhance reaction picker with full list, search, and user list"
```

---

## Task 13: 书签提醒 UI

**Files:**
- Modify: `native/ios-app/App/Views/FireBookmarkEditorSheet.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`
- Reference: `docs/knowledge/api/10-presence-and-categories.md` (bookmark reminders)

- [ ] **Step 1: iOS 书签编辑器添加提醒选择器**

在 `FireBookmarkEditorSheet` 中添加：

```swift
Section {
    Toggle("设置提醒", isOn: $hasReminder)
    if hasReminder {
        DatePicker("提醒时间", selection: $reminderDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
    }
}
```

保存时将 `reminderDate` 传递给 Rust core 的 `createBookmark` API。

- [ ] **Step 2: 提醒触发时展示本地通知**

注册 `UNUserNotificationCenter` 通知，当书签提醒到期时展示本地通知。

- [ ] **Step 3: Android 对称实现**

在 Android 端的 AlertDialog 中添加日期时间选择器，使用 `AlarmManager` 触发本地通知。

- [ ] **Step 4: 构建验证**

Run: Both platforms build successfully

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "feat(bookmarks): add reminder date picker and local notifications for bookmark reminders"
```

---

## Task 14: 话题内搜索

**Files:**
- Create: `native/ios-app/App/TopicDetail/FireTopicSearchBar.swift`
- Modify: `native/ios-app/App/TopicDetail/FireTopicDetailViewController.swift`
- Create: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicSearchOverlay.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt`

- [ ] **Step 1: iOS 话题搜索 UI**

在话题详情工具栏添加搜索按钮。点击后顶部展示搜索栏：

```swift
struct FireTopicSearchBar: View {
    @Binding var query: String
    let resultCount: Int
    let currentIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            TextField("搜索话题内容", text: $query)
                .textFieldStyle(.roundedBorder)
            if resultCount > 0 {
                Text("\(currentIndex + 1)/\(resultCount)")
                    .font(.caption)
                    .foregroundStyle(FireTheme.tertiaryInk)
                Button(action: onPrevious) { Image(systemName: "chevron.up") }
                Button(action: onNext) { Image(systemName: "chevron.down") }
            }
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(FireTheme.chrome)
    }
}
```

- [ ] **Step 2: 搜索逻辑**

在已加载的帖子列表中搜索纯文本内容：
- 输入关键词后匹配所有帖子的 `plain_text`
- 高亮匹配帖子
- 支持上/下导航

- [ ] **Step 3: Android 话题搜索**

顶部搜索覆盖层，同样的匹配和导航逻辑。

- [ ] **Step 4: 构建验证**

Run: Both platforms build successfully

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/TopicDetail/FireTopicSearchBar.swift native/ios-app/App/TopicDetail/ native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicSearchOverlay.kt native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt
git commit -m "feat(topic-detail): add in-topic text search with highlight navigation"
```
