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
| Create | `App/Views/Profile/FireLDCView.swift` | LDC 信用主页 |
| Create | `App/Views/Profile/FireCDKView.swift` | CDK 连接页 |
| Create | `App/Views/FireConnectStatsView.swift` | Connect 统计页 |
| Modify | `App/TopicDetail/` | 原生 runtime 话题详情视图模式切换 |
| Modify | `App/Views/Composer/FireComposerView.swift` | 集成 Markdown 工具栏和引用插入 |
| Modify | `App/Views/Composer/FirePostEditorView.swift` | 升级为 FireComposerTextView |
| Modify | `App/TopicDetail/` 相关文件 | 话题通知级别 UI、话题内搜索 |

### Android Changes

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `ui/ldc/LDCFragment.kt` | LDC 信用主页 |
| Create | `ui/ldc/LDCViewModel.kt` | LDC ViewModel |
| Create | `ui/ldc/CDKFragment.kt` | CDK 连接页 |
| Modify | `ui/topicdetail/TopicDetailViewModel.kt` | 线程/平铺 row projection |
| Modify | `ui/topicdetail/TopicDetailActivity.kt` | 话题详情视图模式切换 |
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
- Modify: `Cargo.toml`
- Modify: `rust/crates/fire-uniffi/Cargo.toml`
- Modify: `rust/crates/fire-uniffi/src/lib.rs`
- Modify: `native/ios-app/project.yml`

- [x] **Step 1: 创建 fire-uniffi-ldc crate**

Implemented in `rust/crates/fire-uniffi-ldc/` following the existing handle crate pattern.

- `rust/crates/fire-uniffi-ldc/Cargo.toml`
- `rust/crates/fire-uniffi-ldc/src/lib.rs`
- `rust/crates/fire-uniffi-ldc/src/records.rs`

Implementation notes:

- `FireLdcHandle` stores `Arc<SharedFireCore>` and uses `run_on_ffi_runtime`, matching the existing `fire-uniffi-search`/`fire-uniffi-user` pattern.
- One handle exposes both service flows because LDC and CDK share the same OAuth approval mechanics.
- LDC methods: `ldc_authorization_url`, `ldc_approval_link`, `ldc_approve`, `ldc_callback`, `ldc_user_info`, `ldc_logout`, and `ldc_reward`.
- CDK methods: `cdk_authorization_url`, `cdk_approval_link`, `cdk_approve`, `cdk_callback`, `cdk_user_info`, and `cdk_logout`.
- `LdcApprovalStatusState` is a record with a simple `LdcApprovalStatusKindState` plus optional `code`/`state`, which keeps payload-carrying OAuth approval data easy for Swift/Kotlin to consume.
- LDC/CDK state records live in the feature crate instead of `fire-uniffi-types`, because they are not shared by other handles.
- `ldc_reward` takes client credentials per call and does not persist them in Rust; platform keychain/keystore ownership remains unchanged.

- [x] **Step 2: 在 FireAppCore 中暴露 handle**

`rust/crates/fire-uniffi/src/lib.rs` adds an `ldc` handle field, initializes it from the shared core, and exposes `FireAppCore::ldc()`.

`Cargo.toml` registers `fire-uniffi-ldc` as a workspace member and `rust/crates/fire-uniffi/Cargo.toml` depends on it.

`native/ios-app/project.yml` lists `Generated/FireUniFfi/fire_uniffi_ldc.swift` as a UniFFI prebuild output. Android bindgen copies generated namespaces wholesale, so no Android source-list change is needed.

- [x] **Step 3: 构建验证**

Run: `cargo fmt --all --check`
Result: passed.

Run: `cargo check -p fire-uniffi-ldc`
Result: passed.

Run: `cargo test -p fire-uniffi-ldc`
Result: passed.

Run: `cargo check -p fire-uniffi`
Result: passed after clearing stale package build artifacts with `cargo clean -p fire-models -p fire-core -p fire-uniffi -p fire-uniffi-ldc`.

Run: temporary UniFFI bindgen for Swift and Kotlin against `rust/target/debug/libfire_uniffi.dylib`
Result: generated `fire_uniffi_ldc.swift`, `uniffi/fire_uniffi_ldc/fire_uniffi_ldc.kt`, and `FireAppCore.ldc()`.

- [x] **Step 4: Commit**

```bash
git add Cargo.toml Cargo.lock rust/crates/fire-uniffi-ldc/ rust/crates/fire-uniffi/Cargo.toml rust/crates/fire-uniffi/src/lib.rs native/ios-app/project.yml docs/superpowers/plans/2026-06-08-p2-feature-completion.md
git commit -m "feat(uniffi): add LDC and CDK OAuth bridge"
```

---

## Task 4: LDC/CDK — iOS UI

**Files:**
- Create: `native/ios-app/App/Views/Profile/FireLDCView.swift`
- Create: `native/ios-app/App/Views/Profile/FireCDKView.swift`
- Modify: `native/ios-app/App/Views/Profile/FireProfileView.swift` (添加入口)
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift` (透传 LDC/CDK calls)
- Modify: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` (唯一 Rust bridge)
- Modify: `native/ios-app/Fire.xcodeproj/project.pbxproj` (注册新 Swift sources)

- [x] **Step 1: 创建 LDC 信用视图**

`FireLDCView` lives in the existing profile SwiftUI surface and uses the shared `FireTheme`, `FireMetricTile`, `FireKeyValueRow`, and `FireErrorBanner` components. It loads `ldcUserInfo()` through `FireAppViewModel`, showing available/community balances, receive/payment/transfer/community totals, quota, pay score/level, pay-key/admin flags, daily limit, and optional gamification score.

No LDC payment-history list is present yet because neither `docs/knowledge/api/13-ldc-cdk-oauth.md` nor the read-only FluxDo reference exposes a payment-history endpoint. The implemented UI displays the documented `user-info` balance/aggregate fields rather than adding an undocumented secondary API path.

- [x] **Step 2: 创建 CDK 连接视图**

`FireCDKView` mirrors the LDC authorization surface while using `CdkUserInfoState`: identity, trust level, and CDK score. CDK intentionally does not reuse LDC balance/payment fields.

- [x] **Step 3: 在 Profile 中添加入口**

`FireProfileView` adds two profile shortcuts:
- `LDC 信用` (`creditcard.fill`) pushes `FireLDCView(viewModel:)`.
- `CDK 连接` (`key.fill`) pushes `FireCDKView(viewModel:)`.

- [x] **Step 4: 接入授权/登出流程**

The iOS session facade now exposes the full UniFFI LDC/CDK handle surface:
- authorization URL fetch
- approval-page link extraction
- approve redirect
- callback POST
- user-info refresh
- logout

The views run the approval/callback sequence from explicit user actions and never own cookies, WebView login, or credential persistence; those remain platform-owned browser/session concerns and Rust-owned API orchestration as required by the architecture split.

- [x] **Step 5: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 6: Commit**

```bash
git add native/ios-app/App/Views/Profile/FireLDCView.swift native/ios-app/App/Views/Profile/FireCDKView.swift native/ios-app/App/Views/Profile/FireProfileView.swift native/ios-app/App/ViewModels/FireAppViewModel.swift native/ios-app/Sources/FireAppSession/FireSessionStore.swift native/ios-app/Fire.xcodeproj/project.pbxproj
git commit -m "feat(ios): add LDC Credit and CDK connection views"
```

---

## Task 5: LDC/CDK — Android UI

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/ldc/LDCFragment.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/ldc/CDKFragment.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/ldc/LdcCdkFragment.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/ldc/LdcCdkViewModel.kt`
- Create: `native/android-app/src/main/res/layout/fragment_ldc.xml`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`
- Modify: `native/android-app/src/main/res/layout/fragment_profile.xml`
- Modify: `native/android-app/src/main/res/values/strings.xml`

- [x] **Step 1: 创建 LDC/CDK ViewModel 和 Fragment**

遵循 Android MVVM 模式（参考 `HomeViewModel` + `HomeFragment`）：
- `LdcCdkViewModel`: `StateFlow<LdcCdkUiState>`, user-info state, authorization state, `loadUserInfo()`, `prepareAuthorization()`, `completeAuthorization()`, `logout()`
- `LDCFragment`: LDC 余额/信用指标展示 + 授权/登出操作 + 空状态/加载状态
- `CDKFragment`: CDK 连接账号/积分展示 + 授权/登出操作 + 空状态/加载状态

- [x] **Step 2: 布局和导航**

`fragment_ldc.xml` uses one fixed ViewBinding layout for both services: overview metrics, optional LDC detail rows, explicit refresh, authorization URL/link rows with copy actions, approve/callback completion, and logout.

Navigation graph adds `ldcFragment` and `cdkFragment`. The current-user profile action strip adds `LDC` and `CDK` entries using a horizontal scroll container so the existing Bookmarks/Drafts/Messages/Read History actions stay reachable on narrow screens.

`FireSessionStore.kt` wraps the generated `core.ldc()` methods and remains Android's only Rust bridge for these screens. Cookie stores, WebView login, and platform browser context remain outside the new UI.

- [x] **Step 3: 构建验证**

Run: `cd native/android-app && ./gradlew assembleDebug`
Result: `BUILD SUCCESSFUL`

- [x] **Step 4: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/ldc/ native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt native/android-app/src/main/res/drawable/bg_ldc_*.xml native/android-app/src/main/res/layout/fragment_ldc.xml native/android-app/src/main/res/layout/fragment_profile.xml native/android-app/src/main/res/navigation/fire_nav_graph.xml native/android-app/src/main/res/values/strings.xml
git commit -m "feat(android): add LDC Credit and CDK connection screens"
```

---

## Task 6: 线程视图 — iOS

**Files:**
- Modify: `native/ios-app/App/TopicDetail/Support/FireTopicDetailSharedModels.swift`
- Modify: `native/ios-app/App/TopicDetail/State/FireTopicDetailPageState.swift`
- Modify: `native/ios-app/App/TopicDetail/State/FireTopicDetailPageSnapshot.swift`
- Modify: `native/ios-app/App/TopicDetail/State/FireTopicDetailSnapshotAssembler.swift`
- Modify: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedModels.swift`
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailToolbarCoordinator.swift`
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`
- Modify: `native/ios-app/Tests/Unit/FireTopicDetailRuntimeTests.swift`

- [x] **Step 1: 创建线程视图组件**

Implemented as a topic-detail native runtime view mode instead of a SwiftUI post-row surface.

- `FireTopicDetailViewMode` adds `conversation` and `threaded`.
- The existing Texture `ASCollectionNode` feed and `FirePostCellNode` path remain authoritative for original post and reply rows.
- Conversation mode preserves the existing collapsed root-reply projection.
- Threaded mode renders every loaded Rust tree row in order, preserves Rust-provided depth, disables root shortcut hiding, and keeps scroll lookup available for loaded nested replies.

- [x] **Step 2: 话题详情工具栏添加视图切换**

`FireTopicDetailToolbarCoordinator` adds a compact view-mode menu in the navigation bar. Switching modes updates controller-local presentation state and rebuilds the feed snapshot; Rust source snapshots, raw-stream pagination, render documents, and native cell layout remain unchanged.

Unit coverage in `FireTopicDetailRuntimeTests` asserts the conversation projection still hides secondary replies by default while threaded mode shows all loaded nested replies with the native runtime cell context.

- [x] **Step 3: 构建验证**

Run: `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet`
Result: `** BUILD SUCCEEDED **`

Run: `cd native/ios-app && xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:FireTests/FireTopicDetailRuntimeTests -quiet`
Result: passed.

- [x] **Step 4: Commit**

```bash
git add native/ios-app/App/TopicDetail/ native/ios-app/Tests/Unit/FireTopicDetailRuntimeTests.swift native/ios-app/README.md docs/superpowers/plans/2026-06-08-p2-feature-completion.md
git commit -m "feat(ios): add threaded view mode for topic detail"
```

---

## Task 7: 线程视图 — Android

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt`
- Modify: `native/android-app/src/main/res/values/strings.xml`
- Modify: `native/android-app/src/test/java/com/fire/app/ui/topicdetail/TopicDetailPostRowsTest.kt`

- [x] **Step 1: 添加 view-mode row projection**

Implemented on the existing authoritative topic-detail list path instead of adding
a second adapter. `TopicDetailViewMode` defaults to `THREADED`, preserving the
current Rust tree row order, depth, parent post number, and child markers. `FLAT`
sorts loaded reply rows by floor, removes tree indentation, and keeps reply
context from the post's `replyToPostNumber`.

- [x] **Step 2: TopicDetailActivity 添加视图模式切换**

The toolbar opens a single-choice mode dialog. Both modes continue to use the
same `ConcatAdapter` / `PostListAdapter`, the same Rust source snapshot, and the
same Rust tree presentation rows; switching only republishes projected rows from
the ViewModel.

- [x] **Step 3: 构建验证**

Run:

```bash
cd native/android-app
./gradlew testDebugUnitTest --tests com.fire.app.ui.topicdetail.TopicDetailPostRowsTest
./gradlew assembleDebug
```

Result: both commands completed with `BUILD SUCCESSFUL`.

- [x] **Step 4: Commit**

Committed as `31f9216 feat(android): add threaded view mode for topic detail`.

```bash
git add docs/superpowers/plans/2026-06-08-p2-feature-completion.md native/android-app/README.md native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt native/android-app/src/main/res/values/strings.xml native/android-app/src/test/java/com/fire/app/ui/topicdetail/TopicDetailPostRowsTest.kt
git commit -m "feat(android): add threaded view mode for topic detail"
```

---

## Task 8: 编辑器增强 — Markdown 工具栏

**Files:**
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift`
- Modify: `native/ios-app/App/Views/Composer/FirePostEditorView.swift`
- Modify: `native/ios-app/Tests/Unit/FireComposerValidationTests.swift`
- Create: `native/android-app/src/main/java/com/fire/app/ui/composer/MarkdownToolbarView.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/composer/ComposerAssist.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/composer/ReplyComposerSheet.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/composer/TopicComposerSheet.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/composer/PrivateMessageComposerSheet.kt`
- Modify: Android composer sheet layouts/resources/tests

- [x] **Step 1: iOS Markdown 工具栏组件**

Implemented in the already-compiled composer source to avoid mixing this task
with the unrelated dirty `Fire.xcodeproj/project.pbxproj` state. The reusable
`FireMarkdownToolbar` and `FireMarkdownInsertion` model support bold, italic,
strikethrough, inline code, code block, quote, unordered list, ordered list,
link, and image marker actions.

- [x] **Step 2: 集成到 FireComposerView / FirePostEditorView**

`FireComposerView` and `FirePostEditorView` now share the `FireComposerTextView`
selection-binding path. Formatting wraps selected text, inserts paired markers
at the cursor when there is no selection, and keeps focus/selection in the text
view. This also completes the planned PostEditorView text editor upgrade without
introducing a second edit path.

- [x] **Step 3: Android Markdown 工具栏**

`MarkdownToolbarView.kt` provides the horizontal formatting toolbar and binds to
the target body `EditText`. `ComposerAssist.kt` owns the pure
`MarkdownInsertion` helper plus the `EditText` adapter. The toolbar is integrated
into `ReplyComposerSheet`, `TopicComposerSheet`, and
`PrivateMessageComposerSheet`, and is hidden with the editor while preview mode
is active.

- [x] **Step 4: 构建验证（两端）**

Focused tests already passed:

```bash
cd native/ios-app
xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:FireTests/FireComposerValidationTests -quiet

cd native/android-app
./gradlew testDebugUnitTest --tests com.fire.app.ui.composer.MarkdownInsertionTest
```

Final build commands:

```bash
cd native/ios-app
xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet

cd native/android-app
./gradlew assembleDebug
```

Result: focused tests and both final build commands completed successfully.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-06-08-p2-feature-completion.md native/ios-app/README.md native/ios-app/App/Views/Composer/FireComposerView.swift native/ios-app/App/Views/Composer/FirePostEditorView.swift native/ios-app/Tests/Unit/FireComposerValidationTests.swift native/android-app/README.md native/android-app/src/main/java/com/fire/app/ui/composer/ComposerAssist.kt native/android-app/src/main/java/com/fire/app/ui/composer/MarkdownToolbarView.kt native/android-app/src/main/java/com/fire/app/ui/composer/ReplyComposerSheet.kt native/android-app/src/main/java/com/fire/app/ui/composer/TopicComposerSheet.kt native/android-app/src/main/java/com/fire/app/ui/composer/PrivateMessageComposerSheet.kt native/android-app/src/main/res/layout/sheet_reply_composer.xml native/android-app/src/main/res/layout/sheet_topic_composer.xml native/android-app/src/main/res/layout/sheet_private_message_composer.xml native/android-app/src/main/res/values/strings.xml native/android-app/src/test/java/com/fire/app/ui/composer/MarkdownInsertionTest.kt
git commit -m "feat(composer): add Markdown formatting toolbar for iOS and Android"
```

---

## Task 9: 编辑器增强 — 引用插入

**Files:**
- Modify: `native/ios-app/App/Views/Composer/FireComposerView.swift`
- Modify: `native/ios-app/App/TopicDetail/` (post action callbacks)
- Modify: Android 对应文件

- [x] **Step 1: iOS 引用插入实现**

iOS topic-detail native post cells now expose 「引用回复」 from the existing
post operation menu. The action builds Discourse quote Markdown through
`FireQuoteMarkdown`, using Rust-provided `post.renderDocument?.plainText`
rather than parsing `post.cooked` on the platform. Empty render text surfaces a
notice instead of inventing a fallback body.

Selecting quote opens the full-screen advanced reply composer with:

- `replyToPostNumber` / `replyToUsername` set to the quoted post
- `[quote="username, post:{number}, topic:{id}"]\n{plain_text}\n[/quote]\n\n`
  inserted as `initialBody`
- cursor positioned after the quote block
- restored drafts preserved by prepending the quote once if a matching draft
  already exists

- [x] **Step 2: Android 引用插入**

Android post rows now show a Quote action beside Reply. `QuoteMarkdown` builds
the same Discourse `[quote]` block from `post.renderDocument?.plainText`, and
`ReplyComposerSheet` accepts an `initialBody` argument. Existing restored draft
content is kept and the quote is inserted once at the beginning.

- [x] **Step 3: 构建验证**

Focused verification passed:

```bash
cd native/android-app
./gradlew testDebugUnitTest --tests com.fire.app.ui.composer.MarkdownInsertionTest
./gradlew assembleDebug

cd native/ios-app
xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:FireTests/FireComposerValidationTests -quiet
xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet
```

iOS still emits the existing deprecation / Swift 6 migration warnings noted in
earlier tasks, but the build and focused test target pass.

- [x] **Step 4: Commit**

Committed as `d0528bd feat(composer): add quote insertion from topic detail posts`.

```bash
git add -u
git commit -m "feat(composer): add quote insertion from topic detail posts"
```

---

## Task 10: 编辑器增强 — PostEditorView 升级

**Files:**
- Modify: `native/ios-app/App/Views/Composer/FirePostEditorView.swift`

- [x] **Step 1: 替换基础 TextEditor**

Completed as part of Task 8 to keep Markdown formatting on one authoritative
iOS text editing path. `FirePostEditorView` now uses `FireComposerTextView` with
selection binding and `FireMarkdownToolbar`.

Post edit remains intentionally narrower than full composer flows: it does not
add draft autosave, preview mode, or image upload in this task because the
existing post-edit API requires server-provided raw text and a direct save
mutation path.

- [x] **Step 2: 构建验证**

Run:

```bash
cd native/ios-app
xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:FireTests/FireComposerValidationTests -quiet
xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet
```

Result: both commands completed successfully.

- [x] **Step 3: Commit**

Included in `feat(composer): add Markdown formatting toolbar for iOS and Android`.

---

## Task 11: 话题通知级别控制

**Files:**
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailToolbarCoordinator.swift`
- Modify: `native/ios-app/App/TopicDetail/Support/FireTopicDetailSharedModels.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/PostListAdapter.kt`
- Modify: `native/android-app/src/main/res/layout/item_topic_header.xml`
- Modify: `native/android-app/src/main/res/values/strings.xml`
- Create: `native/android-app/src/main/res/drawable/ic_notifications_active.xml`
- Create: `native/android-app/src/main/res/drawable/ic_notifications_off.xml`
- Reference: `docs/knowledge/api/03-topics.md` (topic notification level API)

- [x] **Step 1: iOS 通知级别按钮**

`FireTopicDetailToolbarCoordinator` now owns a dedicated bell item in the topic
detail navigation toolbar. The item is hidden for private-message threads,
disabled when write interactions are unavailable, and opens a `UIMenu` titled
「通知设置」 with the four Discourse levels: 静音、常规、跟踪、关注.

The icon reflects the Rust-provided current notification level:

- muted: `bell.slash.fill`
- regular: `bell`
- tracking / watching: `bell.fill`

The old notification section was removed from the ellipsis menu so the toolbar
bell is the one authoritative control.

- [x] **Step 2: Android 通知级别按钮**

`TopicDetailActivity` now adds a toolbar bell menu item that is hidden for
private-message threads, updates its title and icon from
`detail.details.notificationLevel`, and opens the notification-level chooser.
The previous header-row notification button was removed from
`PostListAdapter` / `item_topic_header.xml` so Android also has one
authoritative toolbar control.

- [x] **Step 3: 构建验证**

Run:

```bash
cd native/android-app
./gradlew assembleDebug

cd native/ios-app
xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet
```

Result: both commands completed successfully. iOS still emits the existing
deprecation / Swift 6 migration warnings noted in earlier tasks.

- [x] **Step 4: Commit**

Included in `feat(topic-detail): add topic notification level control to toolbar`.

```bash
git add -u
git commit -m "feat(topic-detail): add topic notification level control to toolbar"
```

---

## Task 12: Reaction 选择器增强

**Files:**
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailModalRouter.swift`
- Modify: `native/ios-app/App/TopicDetail/Support/FireTopicDetailModalViews.swift`
- Modify: `native/ios-app/App/TopicDetail/Support/FireTopicPresentation.swift`
- Modify: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/ReactionPresentation.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt`
- Reference: `docs/knowledge/api/04-posts.md` (reaction APIs)

- [x] **Step 1: 获取可用 Reaction 列表**

iOS and Android now build reaction picker options from the Rust-owned bootstrap
`enabledReactionIds` list, with `heart` retained in the picker and the current
reaction preserved if it is not present in bootstrap. iOS exposes the picker
from the native post operation menu; Android upgrades the existing React action
dialog.

- [x] **Step 2: 搜索表情**

Both picker implementations support search over reaction id, localized label,
and emoji symbol.

- [x] **Step 3: Reaction 用户列表**

iOS adds a Rust-backed reaction-user sheet via
`FireSessionStore.fetchReactionUsers(postID:)`. Android keeps the existing
summary-level reaction-user lookup and adds long-press lookup from a specific
picker row.

- [x] **Step 4: 构建验证**

Run:

```bash
cd native/android-app
./gradlew testDebugUnitTest --tests com.fire.app.ui.topicdetail.ReactionPresentationTest
./gradlew assembleDebug

cd native/ios-app
xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:FireTests/FireTopicPresentationTests -quiet
xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet
```

Result: all commands completed successfully. iOS still emits the existing
deprecation / Swift 6 migration warnings noted in earlier tasks.

- [x] **Step 5: Commit**

Included in `feat(reactions): enhance reaction picker with full list, search, and user list`.

```bash
git add -u
git commit -m "feat(reactions): enhance reaction picker with full list, search, and user list"
```

---

## Task 13: 书签提醒 UI

**Files:**
- Modify: `native/ios-app/App/Views/Bookmarks/FireBookmarkEditorSheet.swift`
- Modify: iOS bookmark context call sites
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`
- Create: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/BookmarkReminderScheduler.kt`
- Reference: `docs/knowledge/api/10-presence-and-categories.md` (bookmark reminders)

- [x] **Step 1: iOS 书签编辑器添加提醒选择器**

`FireBookmarkEditorSheet` already owns the native `Toggle` + `DatePicker`
reminder UI. This task kept that authoritative shared sheet, ensured past saved
reminders do not initialize outside the DatePicker range, and continued passing
ISO UTC `reminder_at` through the existing Rust bookmark APIs.

- [x] **Step 2: 提醒触发时展示本地通知**

Added host-owned local reminder scheduling to the shared iOS bookmark editor.
Successful saves schedule or cancel `UNUserNotificationCenter` requests keyed by
bookmarkable type/id; deletes cancel the matching local reminder. Notification
payloads reuse the typed route keys so taps route back to the bookmarked topic
or post.

- [x] **Step 3: Android 对称实现**

Android topic-detail bookmark editing now uses a native reminder toggle plus
`DatePickerDialog` / `TimePickerDialog`, sends ISO UTC `reminder_at` to Rust,
and schedules host-owned local notifications through `AlarmManager` only after
the Rust bookmark mutation succeeds. Reminder notifications deep-link back to
the topic detail screen, and Android 13+ notification permission is requested
when needed.

- [x] **Step 4: 构建验证**

Run:

```bash
cd native/android-app
./gradlew testDebugUnitTest --tests com.fire.app.ui.topicdetail.BookmarkReminderSchedulerTest
./gradlew assembleDebug

cd native/ios-app
xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet
```

Result: all commands completed successfully. iOS still emits the existing
deprecation / Swift 6 migration warnings noted in earlier tasks.

- [x] **Step 5: Commit**

Included in `feat(bookmarks): add reminder date picker and local notifications for bookmark reminders`.

```bash
git add -u
git commit -m "feat(bookmarks): add reminder date picker and local notifications for bookmark reminders"
```

---

## Task 14: 话题内搜索

**Files:**
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailToolbarCoordinator.swift`
- Modify: `native/ios-app/App/TopicDetail/Nodes/FireTopicDetailRootNode.swift`
- Modify: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift`
- Modify: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedModels.swift`
- Modify: `native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift`
- Modify: `native/ios-app/App/ListKit/TopicDetail/FirePostCellLayout.swift`
- Modify: `native/ios-app/App/TopicDetail/Support/FireTopicPresentation.swift`
- Create: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicSearchOverlay.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/PostListAdapter.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/PostViewHolder.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt`

- [x] **Step 1: iOS 话题搜索 UI**

Implemented on the existing UIKit/Texture topic-detail runtime path, not as a
new SwiftUI post-row or SwiftUI search component. `FireTopicDetailToolbarCoordinator`
adds a toolbar `magnifyingglass` button, and `FireTopicDetailViewController`
owns a small UIKit `FireTopicSearchBar` subview above the `ASCollectionNode`.
`FireTopicDetailRootNode` tracks the top chrome inset so the search bar does not
cover feed content.

- [x] **Step 2: 搜索逻辑**

Both platforms search only loaded `TopicPostState.renderDocument.plainText`.
The helper returns de-duplicated matches sorted by post number, ignores posts
without Rust render documents, highlights the active matched post, and supports
previous/next wraparound navigation. Navigation reuses the authoritative
topic-detail floor scroll path instead of adding a server-side search API or a
parallel post projection.

- [x] **Step 3: Android 话题搜索**

`TopicSearchOverlay` is a native ViewBinding-backed toolbar overlay under the
Material toolbar. `TopicDetailActivity` owns query/result state and scrolls via
the existing `scrollToPostNumber` helper. `PostListAdapter`, `HeaderAdapter`,
and `PostViewHolder` render the current active-match highlight across the
original post and reply rows.

- [x] **Step 4: 构建验证**

Run:
- `cd native/android-app && ./gradlew testDebugUnitTest --tests com.fire.app.ui.topicdetail.TopicDetailPostRowsTest`
- `cd native/android-app && ./gradlew assembleDebug`
- `cd native/ios-app && xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:FireTests/FireTopicPresentationTests/testTopicSearchMatchesLoadedRenderPlainTextInPostOrder -quiet`
- `cd native/ios-app && xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -quiet`

Result: passed, with existing iOS deprecation / Swift 6 migration warnings.

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/TopicDetail/ native/ios-app/App/ListKit/TopicDetail/ native/ios-app/Tests/Unit/FireTopicPresentationTests.swift native/ios-app/Tests/Unit/FirePostCellLayoutCalculatorTests.swift native/ios-app/Tests/Unit/FireTopicDetailRuntimeTests.swift native/android-app/src/main/java/com/fire/app/ui/topicdetail/ native/android-app/src/main/res/layout/activity_topic_detail.xml native/android-app/src/main/res/values/ids.xml native/android-app/src/main/res/values/strings.xml native/android-app/src/test/java/com/fire/app/ui/topicdetail/TopicDetailPostRowsTest.kt docs/superpowers/plans/2026-06-08-p2-feature-completion.md native/ios-app/README.md native/android-app/README.md
git commit -m "feat(topic-detail): add in-topic text search with highlight navigation"
```
