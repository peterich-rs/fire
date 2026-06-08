# Discourse 启动阶段对齐实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Fire 启动流程完全对齐 `docs/knowledge/discourse-startup-implementation-spec.md`，包括首页 HTML 并行请求、PreheatGate 阻塞、登录态判断路径、AppStateRefresher 分批刷新、MessageBus 初始化。

**Architecture:** Rust 统一拥有 `PreloadedDataService`（首页 HTML 请求与解析）、启动期登录态判定、`AppStateRefresher`（分批刷新编排）、MessageBus 启动参数准备。平台只保留 `PreheatGate` 和主界面切换等 UI 职责；平台不得再自行编排 session 恢复、bootstrap 刷新、首页 feed 预刷、MessageBus 提前启动等启动业务逻辑。

**Tech Stack:** Rust + UniFFI + tokio + openwire + SQLite / Swift + UIKit + Texture / Kotlin + androidx + RecyclerView + Paging3

**Design Doc:** `docs/architecture/discourse-startup-implementation-plan.md`

## Audit Corrections (2026-06-05)

本计划基于当前仓库审查结果进行修正。以下事项为**强约束**，后续执行不得回退：

- `PreheatGate` 必须等待首页 HTML 请求进入**终态**（成功或失败）。不得把 `Loading` / in-flight 状态映射为 `Ready`。
- 启动登录态判断必须以 Rust 权威异步路径为准：`currentUser` → 无 `_t` → `NotLoggedIn` → 有 `_t` 时 probe `/session/current.json`。平台不得自行省略 probe 分支。
- `AppStateRefresher` 是 Rust 侧单例编排器；平台只负责触发和消费刷新事件，不得重新手写等价的刷新流程。
- `MessageBus` 的 `topicTrackingStateMeta` 参数变更必须在 Rust FFI、iOS wrapper、Android wrapper、所有调用点一次性收口，不能只改 Rust。
- 当前仓库已经存在部分实现，下面的 Task 4-13 都应视为**纠偏重构**，不是从零新增。任何与当前代码冲突的旧步骤，以本修正版为准。
- 破坏性重构要求继续生效：删除或停用旧启动路径，不保留兼容层，不允许新旧编排并存。

## Implementation Status (2026-06-05)

- 已落地：`PreloadedDataService` 终态等待 / single-flight / `Notify` 并发模型、`parse_preloaded_payload()` 规范化复用、启动 `_t -> /session/current.json` probe 判定、invalid probe 的 Rust 本地登出清理。
- 已落地：`AppStateRefresher` 现在负责 Rust 侧 debounce、第一批 bootstrap 强制刷新、第二批 `user summary` / `bookmarks` / `read history` / `recent notifications` 刷新，并已有 integration test 覆盖立即执行、延迟执行、2 秒去抖。
- 已落地：`topicTrackingStateMeta` 签名已贯通 Rust FFI、iOS wrapper、Android wrapper 与宿主调用点；`cargo build -p fire-core`、`cargo test -p fire-core --test startup_alignment --test app_state_refresher`、`./gradlew assembleDebug`、`xcodebuild ... build` 当前均通过。
- 已落地：preloaded current-user cache 会随 bootstrap 更新同步，并在 `logout_local()` 时清空，避免同进程内登录态切换继续暴露旧 `currentUser`。
- 已落地：iOS `loadInitialState()` 不再直接执行启动登录态判定 / 首页 feed 首刷 / MessageBus 启动；`FirePreheatGateViewController` 等待 preload 终态后，由 `completeStartupAfterPreheat()` 统一执行 post-preheat 登录态分流。
- 已落地：Android Home 首屏不再额外调用 `refreshSession()` 作为冷启动恢复入口，`HomeViewModel` 直接从 `FireSessionStore` 读取权威 snapshot 并按需接通 topic-list MessageBus 监听。
- 已落地：Rust `AppStateRefresher` 批次事件已经通过 UniFFI callback 暴露，iOS 现已使用统一 refresh callback 驱动 auth 后首页列表强刷与通知状态同步，不再由 `completeLogin()` 手写首页刷新 / MessageBus 启动决策。
- 已落地：Android 现在也通过共享 `FireAppStateRefreshRepository` 消费 Rust refresh callback；`PreheatGateFragment` / `LoginWebViewFragment` 不再只 fire-and-forget，`HomeViewModel` 会在 `RefreshBatch::Core` 后刷新权威 snapshot、按需接通/关闭 MessageBus，并触发当前列表刷新。
- 已落地：iOS `FireCfClearanceRefreshService` 现在显式依赖“登录态已确认” gate；Android 删除了未接线且判定过时的 `FireCfClearanceService.kt`，继续只保留显式 challenge WebView 的 host-owned 续期路径。
- 已落地：Rust 现在持有 `current home topic-list scope`（kind/category/tags），双端首页筛选会同步这份权威 scope；`AppStateRefresher` 第一批刷新会据此真实请求当前 tab/topic list，而不是只让平台自己判断该刷哪一路。
- 已落地：Android 未再保留无用的 `SessionRepository` 壳；startup 侧 direct `restoreSession()` grep 已清零，`refreshBootstrapIfNeeded()` 的剩余调用点都只在 login/profile 等非 startup 读写路径。

- 待继续审计：spec Section 14 中仓库尚未建模的 provider（如“我的话题”、外部 credit/cdk user-info）当前没有对应产品 surface，本轮未新增这些能力。

---

### Task 1: 新增 CurrentUserSnapshot 和 UserStatus 数据模型

**Files:**
- Modify: `rust/crates/fire-models/src/user.rs`
- Test: `rust/crates/fire-models/src/lib.rs`（在现有测试模块中添加）

- [ ] **Step 1: 在 `user.rs` 末尾添加 CurrentUserSnapshot 和 UserStatus**

```rust
// fire-models/src/user.rs — 在文件末尾追加

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserStatus {
    pub description: Option<String>,
    pub emoji: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CurrentUserSnapshot {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub animated_avatar: Option<String>,
    pub trust_level: u8,
    #[serde(default)]
    pub status: Option<UserStatus>,
    pub flair_url: Option<String>,
    pub flair_name: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub flair_group_id: Option<u64>,
    pub gamification_score: Option<i64>,
    #[serde(default)]
    pub unread_notifications: u32,
    #[serde(default)]
    pub unread_high_priority_notifications: u32,
    #[serde(default)]
    pub all_unread_notifications_count: u32,
    #[serde(default)]
    pub seen_notification_id: u64,
    #[serde(default = "default_notification_channel_position")]
    pub notification_channel_position: i64,
    pub last_posted_at: Option<String>,
    pub last_seen_at: Option<String>,
    pub created_at: Option<String>,
    pub location: Option<String>,
    pub website: Option<String>,
    pub website_name: Option<String>,
    pub can_follow: Option<bool>,
    pub is_followed: Option<bool>,
    pub total_followers: Option<u32>,
    pub total_following: Option<u32>,
    pub can_send_private_messages: Option<bool>,
    pub can_send_private_message_to_user: Option<bool>,
    pub muted: Option<bool>,
    pub ignored: Option<bool>,
    pub can_mute_user: Option<bool>,
    pub can_ignore_user: Option<bool>,
    pub suspend_reason: Option<String>,
    pub suspended_till: Option<String>,
    pub silence_reason: Option<String>,
    pub silenced_till: Option<String>,
}

fn default_notification_channel_position() -> i64 {
    -1
}
```

- [ ] **Step 2: 在 `user.rs` 顶部确认已有 `use serde::{Deserialize, Serialize};`（已存在，无需改动）**

- [ ] **Step 3: 在 `lib.rs` 测试模块中添加 CurrentUserSnapshot 测试**

在 `rust/crates/fire-models/src/lib.rs` 的 `mod tests` 块中，找到最后一个 `}` 前，追加：

```rust
    #[test]
    fn current_user_snapshot_default_notification_channel_position() {
        use super::CurrentUserSnapshot;
        let snapshot = CurrentUserSnapshot::default();
        assert_eq!(snapshot.notification_channel_position, -1);
    }
```

同时更新 `tests` 模块顶部的 `use super::{...}` 导入，加入 `CurrentUserSnapshot`。

- [ ] **Step 4: 运行测试验证**

Run: `cargo test -p fire-models`
Expected: 所有测试 PASS

- [ ] **Step 5: Commit**

```bash
git add rust/crates/fire-models/src/user.rs rust/crates/fire-models/src/lib.rs
git commit -m "feat(models): add CurrentUserSnapshot and UserStatus for startup preloaded data"
```

---

### Task 2: 新增 PreloadedDataResult 和启动期枚举类型

**Files:**
- Modify: `rust/crates/fire-models/src/session.rs`

- [ ] **Step 1: 在 `session.rs` 文件末尾（`ProbeResult` 之后）追加新类型**

```rust
// fire-models/src/session.rs — 在文件末尾追加

use std::collections::HashMap;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PreloadedDataResult {
    pub current_user: Option<crate::user::CurrentUserSnapshot>,
    pub site_settings: Option<serde_json::Value>,
    pub site: Option<serde_json::Value>,
    pub topic_tracking_state_meta: Option<HashMap<String, u64>>,
    pub topic_tracking_states: Option<Vec<serde_json::Value>>,
    pub custom_emoji: Option<Vec<serde_json::Value>>,
    pub topic_list: Option<serde_json::Value>,
    pub enabled_reaction_ids: Vec<String>,
    pub categories: Vec<crate::topic::TopicCategory>,
    pub top_tags: Vec<String>,
    pub can_tag_topics: Option<bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreloadedDataState {
    NotStarted,
    Loading,
    Ready,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RefreshTrigger {
    LoginCompleted,
    LogoutCompleted,
    SessionRestored,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RefreshBatch {
    Core,
    Secondary,
}

#[derive(Debug, Clone)]
pub struct AppStateRefreshEvent {
    pub batch: RefreshBatch,
    pub trigger: RefreshTrigger,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LoginStateDetermination {
    LoggedIn { username: String, user_id: u64 },
    NotLoggedIn,
    SessionExpired,
    NetworkErrorPreserveState,
}
```

注意：`session.rs` 顶部已有 `use serde::{Deserialize, Serialize};`。需要确认 `serde_json` 在 `Cargo.toml` 的依赖中。检查：

Run: `grep -c 'serde_json' rust/crates/fire-models/Cargo.toml`

如果 `serde_json` 不在依赖中，需要在 `Cargo.toml` 的 `[dependencies]` 中添加 `serde_json = "1"`。

- [ ] **Step 2: 运行测试验证编译**

Run: `cargo build -p fire-models`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add rust/crates/fire-models/src/session.rs rust/crates/fire-models/Cargo.toml
git commit -m "feat(models): add PreloadedDataResult, PreloadedDataState, AppStateRefreshEvent, LoginStateDetermination"
```

---

### Task 3: 新增 fire-store user_cache 表

**Files:**
- Modify: `rust/crates/fire-store/src/migrations.rs`
- Modify: `rust/crates/fire-store/src/lib.rs`

- [ ] **Step 1: 阅读 `migrations.rs` 了解现有 migration 编号**

Run: `grep -n 'fn migration_' rust/crates/fire-store/src/migrations.rs | tail -5`

假设最后一个 migration 是 `migration_3`，新 migration 编号为 4。

- [ ] **Step 2: 在 `migrations.rs` 追加新 migration**

```rust
// 在文件末尾追加

pub(crate) fn migration_4(conn: &rusqlite::Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS current_user_cache (
            cache_key TEXT PRIMARY KEY NOT NULL,
            data TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        );"
    )?;
    Ok(())
}
```

- [ ] **Step 3: 在 `lib.rs` 的 migration 运行链中追加 `migration_4`**

在 `lib.rs` 中找到 `migration_3` 被调用的位置，在其后追加 `migrations::migration_4(&conn)?;`。

- [ ] **Step 4: 在 `lib.rs` 的 `impl FireStore` 中追加 user cache 方法**

```rust
    pub fn get_cached_user(&self) -> Result<Option<String>> {
        let mut stmt = self.conn.prepare(
            "SELECT data FROM current_user_cache WHERE cache_key = 'primary' ORDER BY updated_at DESC LIMIT 1"
        )?;
        let mut rows = stmt.query([])?;
        match rows.next()? {
            Some(row) => Ok(Some(row.get(0)?)),
            None => Ok(None),
        }
    }

    pub fn set_cached_user(&self, data: &str) -> Result<()> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        self.conn.execute(
            "INSERT OR REPLACE INTO current_user_cache (cache_key, data, updated_at) VALUES ('primary', ?1, ?2)",
            rusqlite::params![data, now],
        )?;
        Ok(())
    }

    pub fn clear_cached_user(&self) -> Result<()> {
        self.conn.execute("DELETE FROM current_user_cache", [])?;
        Ok(())
    }
```

- [ ] **Step 5: 编译验证**

Run: `cargo build -p fire-store`
Expected: 编译成功

- [ ] **Step 6: Commit**

```bash
git add rust/crates/fire-store/src/migrations.rs rust/crates/fire-store/src/lib.rs
git commit -m "feat(store): add current_user_cache table and CRUD methods"
```

---

### Task 4: 重构 `PreloadedDataService`（替换当前有缺陷实现）

**Files:**
- Modify: `rust/crates/fire-core/src/preloaded_data.rs`
- Modify: `rust/crates/fire-core/src/parsing.rs`
- Modify: `rust/crates/fire-core/src/core/mod.rs`

- [ ] **Step 1: 以当前实现为基线做纠偏，不再按“从零创建新模块”执行**

当前仓库已经有 `preloaded_data.rs`、`parse_home_state()`、`preloaded_data_service()`。本任务目标是修正行为，不是重复搭壳。

- [ ] **Step 2: 明确两个 API 语义**

要求 Rust 侧至少拆出两个语义清晰的入口：

- `ensure_loaded()`：只负责触发 single-flight 首页请求；若已有请求进行中，不得把 in-flight 当作成功完成。
- `await_loaded_result()`：等待首页请求进入终态，返回 `PreloadedDataResult` 或错误。

`PreheatGate` 和所有启动判定逻辑只能依赖第二个入口。

- [ ] **Step 3: 修正并发等待模型**

当前问题是“已有并发加载时返回 `Loading`，上层又把它映射成 `Ready`”。修正版必须引入 `tokio::sync::Notify`、waiter 列表或等价机制，使并发调用者在已有 in-flight 请求时真正等待到终态。

必须满足：

- main() / host 初始化触发的 preload 可以与 UI 并行。
- `PreheatGate` 复用同一个请求。
- 同时只有一个首页 HTML 请求在飞。
- 失败后允许下一次显式重试重新发起。

- [ ] **Step 4: 统一复用 `parsing.rs` 的规范化解析能力**

不得在 `PreloadedDataService` 再手写一个“一层 JSON decode”版本。真实 Discourse 页面里，`data-preloaded` 的 value 经常是字符串化 JSON；必须复用 `parse_preloaded_payload()` / `hydrate_preloaded_fields()` 已有的“外层 JSON + 内层字符串 JSON 解码”逻辑，确保以下字段真实可用：

- `currentUser`
- `siteSettings`
- `site`
- `topicTrackingStateMeta`
- `topicTrackingStates`
- `customEmoji`
- `topicList` / `topic_list` / `latest`

- [ ] **Step 5: 成功路径要原子收口**

单次成功加载必须在同一条 Rust 权威路径里完成以下动作：

- 更新 session cookies / bootstrap
- 写入 current user cache
- 保存 terminal `PreloadedDataResult`
- 唤醒所有等待者

失败路径也要保存 terminal error 并唤醒等待者，不能让平台侧靠超时或猜测恢复。

- [ ] **Step 6: 不新增旁路网络 API**

优先复用 FireCore 现有的 traced request helpers（如 `build_home_request()` / `execute_request()` / `read_response_text()`）。不要为了实现 preload 再发明一套旁路 HTTP helper。

- [ ] **Step 7: 添加回归测试**

至少覆盖：

- 并发 `ensure_loaded + await_loaded_result` 只发一个请求
- `data-preloaded` 内层字符串 JSON 可正确展开
- in-flight 状态不会被上层视为 `Ready`
- 失败后允许 retry

- [ ] **Step 8: 验证**

Run: `cargo build -p fire-core`

Run: `cargo test -p fire-core preloaded`

---

### Task 5: 收口启动登录态判定为 Rust 权威入口

**Files:**
- Modify: `rust/crates/fire-core/src/core/session.rs`
- Modify: `rust/crates/fire-core/src/core/auth.rs`

- [ ] **Step 1: 保留“本地快照判定”和“启动权威判定”两个层次，但只允许后者驱动 PreheatGate**

推荐约束：

- `determine_login_state()`：仅返回基于当前内存快照的本地判断，可用于 diagnostics / 非启动路径。
- `determine_login_state_with_probe()`：启动权威路径，必须完整执行 spec Section 6/7。

`PreheatGate`、启动导航、cf_clearance 启动条件都只能使用权威异步判定。

- [ ] **Step 2: 强制对齐 spec 分支**

权威异步判定必须严格执行：

1. `data-preloaded.currentUser` 存在 → `LoggedIn`
2. 无 `currentUser` 且无 `_t` → `NotLoggedIn`
3. 无 `currentUser` 但有 `_t` → `GET /session/current.json`
4. probe 有 `current_user` → `LoggedIn`
5. probe 为无用户 / 404 / 401 / 403 → `SessionExpired`
6. probe 网络异常 → `NetworkErrorPreserveState`

- [ ] **Step 3: 失效分支必须执行 Rust 侧清理**

当 probe 明确返回失效时，Rust 权威路径要负责执行本地登出清理（保留 `cf_clearance`），而不是把“判定失效后是否 logout”下放给平台拼装。

- [ ] **Step 4: 增加针对 `_t` cookie 分支的测试**

至少覆盖：

- 预加载有 `currentUser`
- 无 cookie
- 有 `_t` 且 probe valid
- 有 `_t` 且 probe invalid
- 有 `_t` 且 probe network error

- [ ] **Step 5: 验证**

Run: `cargo build -p fire-core`

Run: `cargo test -p fire-core determine_login_state`

---

### Task 6: 补全 Rust 侧 `AppStateRefresher`

**Files:**
- Modify: `rust/crates/fire-core/src/app_state_refresher.rs`
- Modify: `rust/crates/fire-core/src/core/mod.rs`
- Modify: `rust/crates/fire-uniffi-session/src/lib.rs`

- [ ] **Step 1: 将 `AppStateRefresher` 定义为 Rust 唯一编排器**

平台可以有极薄的 wrapper / trigger，但不得再实现独立的数据刷新逻辑。所有 auth 相关 refresh 的调度、节流、批次切分都在 Rust 内完成。

- [ ] **Step 2: 第一批刷新必须不止 `refresh_bootstrap_if_needed()`**

第一批至少要覆盖 spec Section 14 的核心数据：

- current user（带 2 分钟冷却）
- categories
- topic tracking meta
- topic tracking states
- 当前首页 tab/topic list

如果某个数据最终仍由平台 store 展示，Rust 应通过统一 refresh event / callback 触发平台调用现有 Rust fetch API，而不是让平台重新手写一套等价决策树。

- [ ] **Step 3: 第二批延迟 1 秒刷新**

第二批至少覆盖：

- user summary
- notifications list
- tags
- bookmarks
- 我的话题 / 浏览历史（若当前仓库已有）
- MessageBus 重新初始化 / 重连

- [ ] **Step 4: auth 事件必须统一接入**

`LoginCompleted` / `LogoutCompleted` / `SessionRestored` 三个 trigger 都要走同一 Rust refresher。平台侧原有“登录后手动 refreshHomeFeed / 手动 startMessageBus / 手动 snapshot sync”路径必须删除或停用。

- [ ] **Step 5: debounce 和事件语义测试**

至少覆盖：

- 2 秒内重复调用被跳过
- 第一批立即执行
- 第二批延迟执行
- 登录/登出/恢复三类 trigger 都能到达 Rust refresher

- [ ] **Step 6: 验证**

Run: `cargo build -p fire-core`

Run: `cargo test -p fire-core app_state_refresher`

---

### Task 7: 修正 FFI 启动面

**Files:**
- Modify: `rust/crates/fire-uniffi-session/src/lib.rs`
- Modify: `rust/crates/fire-uniffi-session/src/records.rs`
- Modify: `rust/crates/fire-uniffi-messagebus/src/lib.rs`

- [ ] **Step 1: 使用真实 records 文件位置**

当前 session records 位于 `rust/crates/fire-uniffi-session/src/records.rs`，不是 `fire-uniffi-types/src/records/`。后续执行按真实文件布局修改。

- [ ] **Step 2: 把 `await_preloaded_data` 改成终态语义**

允许两种方案，任选其一，但必须避免当前错误：

- 方案 A：`await_preloaded_data()` 直接返回 `PreloadedDataResultState`
- 方案 B：保留 `await_preloaded_data()` 作为终态等待 API，再新增 `preloaded_data_result()` 读取结果

无论选哪种，都必须满足：

- 上层不会把 `Loading` 当 `Ready`
- `PreheatGate` 可以拿到成功结果或错误
- 不再依赖无结构的 bare notification 判断结果

- [ ] **Step 3: 统一暴露启动权威判定和 refresher trigger**

FFI 至少需要稳定暴露：

- `ensure_preloaded_data_loaded()`
- 终态等待 preload 的 API
- `current_user_snapshot()`
- `cached_user()`
- `determine_login_state_with_probe()`（或等价 startup authority API）
- `trigger_app_state_refresh(trigger)`

- [ ] **Step 4: 收口 MessageBus FFI 签名**

`start_message_bus(...)` 的 `topicTrackingStateMeta` 参数变更必须在同一任务内完成：

- Rust core
- `fire-uniffi-messagebus`
- iOS `FireSessionStore`
- Android `FireSessionStore`
- 所有启动 / coordinator 调用点

禁止出现“Rust 已改、host wrapper 未改”的中间状态。

- [ ] **Step 5: 验证**

Run: `cargo build -p fire-uniffi-session`

Run: `cargo build -p fire-uniffi-messagebus`

---

### Task 8: MessageBus 启动对齐 spec

**Files:**
- Modify: `rust/crates/fire-core/src/core/messagebus.rs`
- Modify: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/messagebus/FireMessageBusCoordinator.kt`

- [ ] **Step 1: 统一启动时机**

MessageBus 只能在以下条件同时满足后启动：

- PreheatGate 已完成
- 启动登录态权威判定为 `LoggedIn`
- 主界面已就绪

PreheatGate 自身不启动 MessageBus。

- [ ] **Step 2: 明确 meta 来源**

`topicTrackingStateMeta` 只能来自 Rust preload 结果 / bootstrap，不能让平台重新拼装默认值或静默省略。

- [ ] **Step 3: 保持协议对齐**

继续确保：

- 批量订阅 `/latest` `/new` `/unread` `/topic_tracking_state`
- 订阅 `/notification/{userId}` `/notification-alert/{userId}`
- 请求头包含 `X-SILENCE-LOGGER: true`、`Discourse-Background: true`
- 独立域名时禁用 Cookie，改用 `X-Shared-Session-Key`

- [ ] **Step 4: 编译验证 host wrappers**

必须显式验证 iOS 和 Android wrapper 已跟上 FFI 签名变更。

Run: `cd native/android-app && ./gradlew assembleDebug`

Run: `cd native/ios-app && xcodebuild -project Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16' build`

---

### Task 9: 基线编译与测试前置修正

**Files:**
- 无新增修改

- [ ] **Step 1: Rust workspace 编译必须保持通过**

Run: `cargo build --workspace`

- [ ] **Step 2: 处理 workspace test 基线问题**

Run: `cargo test --workspace`

截至 2026-06-05，已知基线问题为源码版 openwire workspace 的 websocket feature / trait 不匹配。Fire 现已改为从 crates.io 解析 openwire；如果要把本任务标记为“全量验证完成”，必须满足二选一：

- 修复该基线问题
- 明确得到 owner 决策，将其作为独立前置 blocker 记录并从本任务验收项中显式剥离

- [ ] **Step 3: Android host 编译必须恢复为绿色**

截至 2026-06-05，已知当前阻塞是：

- `native/android-app/.../FireSessionStore.kt` 调用 `startMessageBus(...)` 时缺少 `topicTrackingStateMeta` 参数

本问题必须在 Task 7/8 中被消除。

- [ ] **Step 4: 若有验证修复，单独提交**

```bash
git add -A
git commit -m "fix: restore startup alignment build and verification baseline"
```

---

### Task 10: iOS — 删除旧启动编排，收口到 PreheatGate 后单路径

**Files:**
- Delete: `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift`
- Modify: `native/ios-app/App/Startup/FirePreheatGateViewController.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`
- Modify: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`
- Modify: `native/ios-app/App/Views/Other/FireTabRoot.swift`

- [ ] **Step 1: `loadInitialState()` 只负责创建 `FireSessionStore` 和触发 preload**

删除当前 `loadInitialState()` 中所有启动业务编排，包括但不限于：

- `determineLoginState()`
- `restoreColdStartSession()`
- `refreshHomeFeedIfPossible(force: true)`
- `ensureMessageBusActiveIfPossible()`

修正后，`loadInitialState()` 只做两件事：

- 初始化 `FireSessionStore`
- 触发 Rust `ensure_preloaded_data_loaded()`（unawaited / single-flight）

- [ ] **Step 2: `FirePreheatGateViewController` 必须等待终态结果**

Gate 只能依赖 Rust 的终态等待 API，等待完成后再调用启动权威登录态判定。不得用“收到任意成功返回 / 任意 notification”就放行。

- [ ] **Step 3: Gate 结束后只走一个 post-preheat 路径**

成功进入主流程后，iOS 只能通过一个统一入口完成：

- restore / apply session snapshot
- 根据登录态切换 Home / Onboarding
- 触发 `triggerAppStateRefresh(.SessionRestored)`（若已登录）
- 在主界面 ready 后启动 MessageBus（传入 preload meta）

禁止在 `FireTabRoot`、`FireOnboardingView`、已登录 tabs 内再复制一套 startup restore 逻辑。

- [ ] **Step 4: `FireSessionStore.startMessageBus(...)` 跟上 meta 签名**

Swift wrapper 必须显式传 `topicTrackingStateMeta`；不能继续用旧二参调用。

- [ ] **Step 5: 删除遗留启动入口**

清理或停用：

- startup 期间的 `ensureMessageBusActiveIfPossible()`
- startup 期间的手动 home feed refresh
- 任何仅为兼容旧启动路径而保留的 notification / fallback

- [ ] **Step 6: 验证**

Run: `cd native/ios-app && xcodebuild -project Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16' build`

---

### Task 11: Android — 删除旧恢复链，收口到 `PreheatGateFragment`

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/ui/startup/PreheatGateFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/auth/AuthViewModel.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/data/repository/SessionRepository.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/home/HomeFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/home/HomeViewModel.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`

- [ ] **Step 1: `PreheatGateFragment` 等待终态 preload，再走权威登录态判定**

Gate 不得再使用同步 `determineLoginState()` 直接决定导航；必须调用 Rust 权威异步判定 API。

- [ ] **Step 2: 删除旧 startup restore 链**

以下旧路径必须删除或停用：

- `AuthViewModel.restoreSession()`
- `SessionRepository.restoreSession()` 作为启动入口
- `OnboardingFragment` 的 restore button 启动逻辑
- `HomeFragment` / `HomeViewModel.restoreSession()` 冷启动恢复逻辑

Home 页面应默认认为“进入此页面前 session 已经由 PreheatGate 判定完成”。

- [ ] **Step 3: 收口 post-preheat 导航**

Android 启动只允许：

- `preheatGateFragment -> homeFragment`
- `preheatGateFragment -> onboardingFragment`

不得再由 `OnboardingFragment` 或 `HomeFragment` 重做 auth gate。

- [ ] **Step 4: `FireSessionStore.startMessageBus(...)` 跟上 meta 签名**

Kotlin wrapper 和 `FireMessageBusCoordinator` 必须一起更新，消除当前 `assembleDebug` 的编译错误。

- [ ] **Step 5: 验证**

Run: `cd native/android-app && ./gradlew assembleDebug`

---

### Task 12: 双端 `cf_clearance` 启动条件收口

**Files:**
- Modify: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireCfClearanceService.kt`

- [ ] **Step 1: 启动条件统一以 Rust 已确认的 current user 为准**

双端都应基于 Rust 已确认的 session/readiness/current user 信息决定是否启动自动续期，而不是各自做 ad hoc 判定。

- [ ] **Step 2: Gate 未完成前不启动**

`cf_clearance` 自动续期必须发生在 preload 完成、登录态已确认之后，避免在 auth 未判定前干扰启动路径。

- [ ] **Step 3: 验证**

冷启动分别验证：

- 已登录且有 current user → 启动
- 未登录 → 不启动
- preload 失败 / network error → 不抢跑

---

### Task 13: 最终验收与清理

**Files:**
- 无新增修改

- [ ] **Step 1: 跑启动场景矩阵**

至少覆盖：

- 有缓存登录态且 preload 含 `currentUser`
- 有 `_t` 但 preload 无 `currentUser`，必须走 probe
- 无 cookie，直接进入未登录
- preload 失败，PreheatGate 错误页可重试

- [ ] **Step 2: grep 清理遗留旧路径**

重点检查以下模式不再作为启动入口存在：

- `restoreSession()` 被 startup 直接调用
- `refreshBootstrapIfNeeded()` 被 startup 手写调用
- Preheat 完成前直接 `startMessageBus()`

- [ ] **Step 3: 文档对齐**

完成实现后，至少同步以下文档：

- `docs/knowledge/discourse-startup-implementation-spec.md`（若实现反证了 spec，先停下确认，不得默改）
- `docs/architecture/discourse-startup-implementation-plan.md`
- 本执行计划文档

- [ ] **Step 4: 最终提交**

```bash
git add -A
git commit -m "chore: complete discourse startup alignment cleanup and verification"
```
