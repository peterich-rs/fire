# Discourse 启动阶段对齐实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Fire 启动流程完全对齐 `docs/knowledge/discourse-startup-implementation-spec.md`，包括首页 HTML 并行请求、PreheatGate 阻塞、登录态判断路径、AppStateRefresher 分批刷新、MessageBus 初始化。

**Architecture:** Rust 新增 `PreloadedDataService`（首页 HTML 请求与解析）、`AppStateRefresher`（分批刷新编排）、`determine_login_state()`（登录态判断）；两端平台各新增 `PreheatGate`（阻塞等待首页数据）和 `AppStateRefresher`（去抖代理）。所有业务逻辑在 Rust，平台只做 UI 和用户交互。

**Tech Stack:** Rust + UniFFI + tokio + openwire + SQLite / Swift + UIKit + Texture / Kotlin + androidx + RecyclerView + Paging3

**Design Doc:** `docs/architecture/discourse-startup-implementation-plan.md`

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

### Task 4: 新增 PreloadedDataService

**Files:**
- Create: `rust/crates/fire-core/src/preloaded_data.rs`
- Modify: `rust/crates/fire-core/src/lib.rs`
- Modify: `rust/crates/fire-core/src/core/mod.rs`

- [ ] **Step 1: 创建 `preloaded_data.rs`**

```rust
// fire-core/src/preloaded_data.rs

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use fire_models::{
    BootstrapArtifacts, CurrentUserSnapshot, PreloadedDataResult, PreloadedDataState,
};
use serde_json::Value;
use tracing::{info, warn};

use crate::core::FireCore;
use crate::error::FireCoreError;
use crate::parsing::{hydrate_preloaded_fields, parse_home_state};

pub struct PreloadedDataService {
    core: Arc<FireCore>,
    loading: AtomicBool,
    result: std::sync::Mutex<Option<PreloadedDataResult>>,
}

impl PreloadedDataService {
    pub fn new(core: Arc<FireCore>) -> Self {
        Self {
            core,
            loading: AtomicBool::new(false),
            result: std::sync::Mutex::new(None),
        }
    }

    pub fn state(&self) -> PreloadedDataState {
        if self.loading.load(Ordering::Acquire) {
            return PreloadedDataState::Loading;
        }
        let guard = self.result.lock().unwrap();
        match guard.as_ref() {
            Some(_) => PreloadedDataState::Ready,
            None => PreloadedDataState::NotStarted,
        }
    }

    pub async fn ensure_loaded(&self) -> Result<PreloadedDataState, FireCoreError> {
        {
            let guard = self.result.lock().unwrap();
            if guard.is_some() {
                return Ok(PreloadedDataState::Ready);
            }
        }

        if self
            .loading
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return Ok(PreloadedDataState::Loading);
        }

        let result = self.fetch_and_parse().await;

        self.loading.store(false, Ordering::Release);

        match result {
            Ok(data) => {
                let mut guard = self.result.lock().unwrap();
                *guard = Some(data);
                Ok(PreloadedDataState::Ready)
            }
            Err(e) => {
                warn!(error = %e, "preloaded data fetch failed");
                Err(e)
            }
        }
    }

    pub fn get_result(&self) -> Option<PreloadedDataResult> {
        self.result.lock().unwrap().clone()
    }

    pub fn get_current_user(&self) -> Option<CurrentUserSnapshot> {
        self.result
            .lock()
            .unwrap()
            .as_ref()
            .and_then(|r| r.current_user.clone())
    }

    async fn fetch_and_parse(&self) -> Result<PreloadedDataResult, FireCoreError> {
        let base_url = self.core.base_url().trim_end_matches('/').to_string();
        let html = self.core.fetch_home_html().await?;
        let parsed = parse_home_state(&base_url, &html);

        let mut result = PreloadedDataResult::default();

        if let Some(preloaded_json) = &parsed.bootstrap_patch.preloaded_json {
            self.extract_preloaded_fields(preloaded_json, &mut result);
        }

        result.enabled_reaction_ids = parsed.bootstrap_patch.enabled_reaction_ids.clone();
        result.categories = parsed.bootstrap_patch.categories.clone();
        result.top_tags = parsed.bootstrap_patch.top_tags.clone();
        result.can_tag_topics = if parsed.bootstrap_patch.can_tag_topics {
            Some(true)
        } else {
            None
        };

        if result.current_user.is_some() {
            if let Some(user) = &result.current_user {
                self.cache_current_user(user);
            }
        }

        {
            let state = self.core.session_state();
            let mut snapshot = state.snapshot.clone();
            snapshot.cookies.merge_patch(&parsed.cookies_patch);
            snapshot.bootstrap.merge_patch(&parsed.bootstrap_patch);
            self.core.update_session(snapshot);
        }

        Ok(result)
    }

    fn extract_preloaded_fields(&self, preloaded_json: &str, result: &mut PreloadedDataResult) {
        let Ok(decoded) = html_entity_decode(preloaded_json) else {
            warn!("failed to HTML-decode preloaded JSON");
            return;
        };
        let Ok(parsed): Result<HashMap<String, Value>, _> = serde_json::from_str(&decoded) else {
            warn!("failed to parse preloaded JSON as map");
            return;
        };

        if let Some(user_val) = parsed.get("currentUser") {
            match serde_json::from_value::<CurrentUserSnapshot>(user_val.clone()) {
                Ok(user) => {
                    info!(username = %user.username, "extracted currentUser from preloaded data");
                    result.current_user = Some(user);
                }
                Err(e) => {
                    warn!(error = %e, "failed to parse currentUser from preloaded data");
                }
            }
        }

        if let Some(val) = parsed.get("siteSettings").cloned() {
            result.site_settings = Some(val);
        }
        if let Some(val) = parsed.get("site").cloned() {
            result.site = Some(val);
        }
        if let Some(val) = parsed.get("topicTrackingStateMeta").cloned() {
            if let Ok(meta) = serde_json::from_value::<HashMap<String, u64>>(val) {
                result.topic_tracking_state_meta = Some(meta);
            }
        }
        if let Some(val) = parsed.get("topicTrackingStates").cloned() {
            result.topic_tracking_states = Some(serde_json::from_value(val).unwrap_or_default());
        }
        if let Some(val) = parsed.get("customEmoji").cloned() {
            result.custom_emoji = Some(serde_json::from_value(val).unwrap_or_default());
        }
        for key in &["topicList", "topic_list", "latest"] {
            if let Some(val) = parsed.get(*key).cloned() {
                result.topic_list = Some(val);
                break;
            }
        }
    }

    fn cache_current_user(&self, user: &CurrentUserSnapshot) {
        if let Ok(data) = serde_json::to_string(user) {
            if let Some(store) = self.core.topic_feed_store() {
                if let Err(e) = store.set_cached_user(&data) {
                    warn!(error = %e, "failed to cache current user");
                }
            }
        }
    }

    pub fn get_cached_user(&self) -> Option<CurrentUserSnapshot> {
        let store = self.core.topic_feed_store()?;
        let data = store.get_cached_user().ok()??;
        serde_json::from_str(&data).ok()
    }

    pub fn clear_cached_user(&self) {
        if let Some(store) = self.core.topic_feed_store() {
            let _ = store.clear_cached_user();
        }
    }
}

fn html_entity_decode(input: &str) -> Result<String, ()> {
    let mut result = input.to_string();
    result = result.replace("&quot;", "\"");
    result = result.replace("&amp;", "&");
    result = result.replace("&lt;", "<");
    result = result.replace("&gt;", ">");
    result = result.replace("&#39;", "'");
    Ok(result)
}
```

- [ ] **Step 2: 在 `core/mod.rs` 的 `FireCore` 上添加 `fetch_home_html` 和 `topic_feed_store` 公开方法**

在 `FireCore` 的 `impl` 块中（`session_persistence_state()` 方法之后）追加：

```rust
    pub(crate) async fn fetch_home_html(&self) -> Result<String, FireCoreError> {
        let base_url = self.base_url.as_str().trim_end_matches('/').to_string();
        self.network.get_text(&format!("{}/", base_url)).await
    }

    pub(crate) fn topic_feed_store(&self) -> Option<&FireStore> {
        self.topic_feed_store.lock().ok().and_then(|guard| Some(()))
            .map(|_| self.topic_feed_store.lock().unwrap())
            .map(|guard| &*guard)
            .ok()
    }
```

注意：由于 `topic_feed_store` 是 `Arc<Mutex<FireStore>>`，更安全的写法：

```rust
    pub(crate) fn get_cached_user_from_store(&self) -> Option<String> {
        let store = self.topic_feed_store.lock().ok()?;
        store.get_cached_user().ok()?
    }

    pub(crate) fn set_cached_user_to_store(&self, data: &str) -> Result<(), FireCoreError> {
        let store = self.topic_feed_store.lock().map_err(|_| FireCoreError::Storage)?;
        store.set_cached_user(data)?;
        Ok(())
    }

    pub(crate) fn clear_cached_user_store(&self) -> Result<(), FireCoreError> {
        let store = self.topic_feed_store.lock().map_err(|_| FireCoreError::Storage)?;
        store.clear_cached_user()?;
        Ok(())
    }
```

更新 `preloaded_data.rs` 中的 `cache_current_user`、`get_cached_user`、`clear_cached_user` 方法使用这些新方法。

- [ ] **Step 3: 在 `core/mod.rs` 的 `FireCore` 中添加 `update_session` 公开方法（如果不存在）**

搜索 `fn update_session`，如果已存在则跳过。如果不存在，添加：

```rust
    pub fn update_session(&self, snapshot: SessionSnapshot) {
        let mut state = self.session.write().unwrap();
        state.snapshot = snapshot;
        state.snapshot_revision += 1;
    }
```

- [ ] **Step 4: 在 `network.rs` 中添加 `get_text` 方法**

搜索 `FireNetworkLayer` 的 impl 块，查看是否已有简单的 GET 方法。如果没有，添加：

```rust
    pub(crate) async fn get_text(&self, url: &str) -> Result<String, FireCoreError> {
        let response = self.client.get(url).send().await?;
        let text = response.text().await?;
        Ok(text)
    }
```

注意：实际方法签名取决于 `openwire::Client` 的 API。需要检查 openwire 的 `Client` 是否有 `get().send()` 模式。如果没有，需要使用 `self.client.request(...)` 等价方式。

- [ ] **Step 5: 在 `lib.rs` 注册模块**

在 `rust/crates/fire-core/src/lib.rs` 的 `mod` 声明列表中追加：

```rust
mod preloaded_data;
```

- [ ] **Step 6: 在 `core/mod.rs` 的 `FireCore` 中添加 `preloaded_data_service` 字段**

修改 `FireCore` 结构体：

```rust
pub struct FireCore {
    // ... 现有字段 ...
    preloaded_data: Arc<crate::preloaded_data::PreloadedDataService>,
}
```

在 `FireCore::new()` 的 `Ok(Self { ... })` 中，先创建 core 然后创建 service：

```rust
        let core = Self {
            base_url,
            workspace_path,
            network,
            diagnostics,
            session,
            message_bus: Arc::new(Mutex::new(messagebus::FireMessageBusRuntime::default())),
            notifications: Arc::new(Mutex::new(notifications::FireNotificationRuntime::default())),
            topic_presence: Arc::new(Mutex::new(presence::FireTopicPresenceRuntime::default())),
            topic_timing: Arc::new(Mutex::new(interactions::FireTopicTimingRuntime::default())),
            topic_response: Arc::new(Mutex::new(topics::FireTopicResponseRuntime::default())),
            topic_feed_store,
            csrf_refresh: Arc::new(TokioMutex::new(())),
            preloaded_data: Arc::new(crate::preloaded_data::PreloadedDataService::new(Arc::new(/* self */))),
        };
```

注意：`PreloadedDataService` 需要 `Arc<FireCore>`，但 `FireCore` 正在构造中。解决方案：先构造不含 `preloaded_data` 的 core，再创建 service，再注入。使用 `Arc::new_cyclic` 或将 `preloaded_data` 改为 `Option<Arc<...>>` 延迟初始化。

推荐方案：将 `preloaded_data` 改为 `OnceCell<Arc<PreloadedDataService>>`：

```rust
use std::sync::OnceCell;

pub struct FireCore {
    // ... 现有字段 ...
    preloaded_data: OnceCell<Arc<crate::preloaded_data::PreloadedDataService>>,
}

impl FireCore {
    pub fn preloaded_data_service(&self) -> &Arc<crate::preloaded_data::PreloadedDataService> {
        self.preloaded_data.get_or_init(|| {
            Arc::new(crate::preloaded_data::PreloadedDataService::new(Arc::new(self.clone())))
        })
    }
}
```

注意：这要求 `FireCore` 实现 `Clone`（已实现）。

- [ ] **Step 7: 编译验证**

Run: `cargo build -p fire-core`
Expected: 编译成功。如果有编译错误，修复类型不匹配等问题。

- [ ] **Step 8: Commit**

```bash
git add rust/crates/fire-core/src/preloaded_data.rs rust/crates/fire-core/src/lib.rs rust/crates/fire-core/src/core/mod.rs rust/crates/fire-core/src/core/network.rs
git commit -m "feat(core): add PreloadedDataService for startup HTML fetch and parse"
```

---

### Task 5: 新增 determine_login_state 方法

**Files:**
- Modify: `rust/crates/fire-core/src/core/session.rs`
- Modify: `rust/crates/fire-core/src/core/auth.rs`

- [ ] **Step 1: 在 `session.rs` 的 impl 块中添加 `determine_login_state`**

在 `FireCore` 的 session 相关方法区域，添加：

```rust
    pub fn determine_login_state(&self) -> fire_models::LoginStateDetermination {
        let snapshot = self.snapshot();
        let readiness = snapshot.readiness();

        if readiness.has_current_user {
            if let (Some(username), Some(user_id)) = (
                snapshot.bootstrap.current_username.as_deref(),
                snapshot.bootstrap.current_user_id,
            ) {
                return fire_models::LoginStateDetermination::LoggedIn {
                    username: username.to_string(),
                    user_id,
                };
            }
        }

        if !readiness.has_login_cookie {
            return fire_models::LoginStateDetermination::NotLoggedIn;
        }

        fire_models::LoginStateDetermination::NotLoggedIn
    }

    pub async fn determine_login_state_with_probe(&self) -> fire_models::LoginStateDetermination {
        let initial = self.determine_login_state();
        if !matches!(initial, fire_models::LoginStateDetermination::NotLoggedIn) {
            return initial;
        }

        let snapshot = self.snapshot();
        if !snapshot.cookies.has_login_session() {
            return fire_models::LoginStateDetermination::NotLoggedIn;
        }

        match self.probe_session().await {
            Ok(probe) => match probe {
                fire_models::ProbeResult::Valid { username } => {
                    fire_models::LoginStateDetermination::LoggedIn {
                        username,
                        user_id: snapshot.bootstrap.current_user_id.unwrap_or(0),
                    }
                }
                fire_models::ProbeResult::Invalid => {
                    fire_models::LoginStateDetermination::SessionExpired
                }
                fire_models::ProbeResult::Inconclusive => {
                    fire_models::LoginStateDetermination::NetworkErrorPreserveState
                }
            },
            Err(_) => fire_models::LoginStateDetermination::NetworkErrorPreserveState,
        }
    }
```

- [ ] **Step 2: 编译验证**

Run: `cargo build -p fire-core`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add rust/crates/fire-core/src/core/session.rs
git commit -m "feat(core): add determine_login_state and determine_login_state_with_probe"
```

---

### Task 6: 新增 AppStateRefresher

**Files:**
- Create: `rust/crates/fire-core/src/app_state_refresher.rs`
- Modify: `rust/crates/fire-core/src/lib.rs`

- [ ] **Step 1: 创建 `app_state_refresher.rs`**

```rust
// fire-core/src/app_state_refresher.rs

use std::sync::Arc;
use std::time::{Duration, Instant};

use fire_models::{AppStateRefreshEvent, RefreshBatch, RefreshTrigger};
use tracing::{info, warn};

use crate::core::FireCore;
use crate::error::FireCoreError;

const DEBOUNCE_DURATION: Duration = Duration::from_secs(2);
const SECONDARY_BATCH_DELAY: Duration = Duration::from_millis(1000);
const CURRENT_USER_REFRESH_COOLDOWN: Duration = Duration::from_secs(120);

pub struct AppStateRefresher {
    core: Arc<FireCore>,
    last_refresh: std::sync::Mutex<Option<Instant>>,
}

impl AppStateRefresher {
    pub fn new(core: Arc<FireCore>) -> Self {
        Self {
            core,
            last_refresh: std::sync::Mutex::new(None),
        }
    }

    pub async fn refresh_all(&self, trigger: RefreshTrigger) -> Result<(), FireCoreError> {
        {
            let mut last = self.last_refresh.lock().unwrap();
            if let Some(instant) = *last {
                if instant.elapsed() < DEBOUNCE_DURATION {
                    info!("app state refresh debounced, skipping");
                    return Ok(());
                }
            }
            *last = Some(Instant::now());
        }

        info!(?trigger, "starting app state refresh batch 1 (core)");
        self.refresh_core_batch(&trigger).await?;

        info!("scheduling app state refresh batch 2 (secondary) in 1s");
        let core = self.core.clone();
        tokio::spawn(async move {
            tokio::time::sleep(SECONDARY_BATCH_DELAY).await;
            if let Err(e) = Self::refresh_secondary_batch_inner(&core, &trigger).await {
                warn!(error = %e, "secondary batch refresh failed");
            }
        });

        Ok(())
    }

    async fn refresh_core_batch(&self, _trigger: &RefreshTrigger) -> Result<(), FireCoreError> {
        self.core.refresh_bootstrap_if_needed().await?;
        Ok(())
    }

    async fn refresh_secondary_batch_inner(
        core: &FireCore,
        _trigger: &RefreshTrigger,
    ) -> Result<(), FireCoreError> {
        let snapshot = core.snapshot();
        let username = snapshot.bootstrap.current_username.clone();
        if let Some(username) = username {
            let _ = core.fetch_user_profile(&username).await;
        }
        Ok(())
    }
}
```

注意：`fetch_user_profile` 方法需要确认是否已存在于 `FireCore`。查看 `core/users.rs` 中的方法名。如果方法名不同，使用实际名称。

- [ ] **Step 2: 在 `lib.rs` 注册模块**

在 `rust/crates/fire-core/src/lib.rs` 的 `mod` 声明列表中追加：

```rust
mod app_state_refresher;
```

- [ ] **Step 3: 编译验证**

Run: `cargo build -p fire-core`
Expected: 编译成功

- [ ] **Step 4: Commit**

```bash
git add rust/crates/fire-core/src/app_state_refresher.rs rust/crates/fire-core/src/lib.rs
git commit -m "feat(core): add AppStateRefresher with two-batch refresh and debounce"
```

---

### Task 7: 新增 FFI session 方法

**Files:**
- Modify: `rust/crates/fire-uniffi-session/src/lib.rs`
- Modify: `rust/crates/fire-uniffi-types/src/records/`（新增 FFI record 类型）

- [ ] **Step 1: 在 `fire-uniffi-types` 中新增 FFI record 类型**

创建或修改相关 records 文件，添加：

```rust
// 在 fire-uniffi-types 的 records 模块中

#[derive(Debug, Clone, uniffi::Record)]
pub struct CurrentUserSnapshotState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub animated_avatar: Option<String>,
    pub trust_level: u8,
    pub status_description: Option<String>,
    pub status_emoji: Option<String>,
    pub flair_url: Option<String>,
    pub flair_name: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub flair_group_id: Option<u64>,
    pub gamification_score: Option<i64>,
    pub unread_notifications: u32,
    pub unread_high_priority_notifications: u32,
    pub all_unread_notifications_count: u32,
    pub seen_notification_id: u64,
    pub notification_channel_position: i64,
}

impl From<fire_models::CurrentUserSnapshot> for CurrentUserSnapshotState {
    fn from(value: fire_models::CurrentUserSnapshot) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            animated_avatar: value.animated_avatar,
            trust_level: value.trust_level,
            status_description: value.status.and_then(|s| s.description),
            status_emoji: value.status.and_then(|s| s.emoji),
            flair_url: value.flair_url,
            flair_name: value.flair_name,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            flair_group_id: value.flair_group_id,
            gamification_score: value.gamification_score,
            unread_notifications: value.unread_notifications,
            unread_high_priority_notifications: value.unread_high_priority_notifications,
            all_unread_notifications_count: value.all_unread_notifications_count,
            seen_notification_id: value.seen_notification_id,
            notification_channel_position: value.notification_channel_position,
        }
    }
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum PreloadedDataStateState {
    NotStarted,
    Loading,
    Ready,
    Failed { error: String },
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum LoginStateDeterminationState {
    LoggedIn { username: String, user_id: u64 },
    NotLoggedIn,
    SessionExpired,
    NetworkErrorPreserveState,
}

impl From<fire_models::LoginStateDetermination> for LoginStateDeterminationState {
    fn from(value: fire_models::LoginStateDetermination) -> Self {
        match value {
            fire_models::LoginStateDetermination::LoggedIn { username, user_id } => {
                Self::LoggedIn { username, user_id }
            }
            fire_models::LoginStateDetermination::NotLoggedIn => Self::NotLoggedIn,
            fire_models::LoginStateDetermination::SessionExpired => Self::SessionExpired,
            fire_models::LoginStateDetermination::NetworkErrorPreserveState => {
                Self::NetworkErrorPreserveState
            }
        }
    }
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum RefreshTriggerState {
    LoginCompleted,
    LogoutCompleted,
    SessionRestored,
}

impl From<RefreshTriggerState> for fire_models::RefreshTrigger {
    fn from(value: RefreshTriggerState) -> Self {
        match value {
            RefreshTriggerState::LoginCompleted => Self::LoginCompleted,
            RefreshTriggerState::LogoutCompleted => Self::LogoutCompleted,
            RefreshTriggerState::SessionRestored => Self::SessionRestored,
        }
    }
}
```

- [ ] **Step 2: 在 `fire-uniffi-session/src/lib.rs` 中新增 FFI 方法**

在 `impl FireSessionHandle` 的 `#[uniffi::export]` 块中追加：

```rust
    pub fn ensure_preloaded_data_loaded(&self) -> Result<(), FireUniFfiError> {
        let core = self.0.core();
        let service = core.preloaded_data_service();
        let service = Arc::clone(service);
        run_on_ffi_runtime(async move {
            service.ensure_loaded().await.map_err(FireUniFfiError::from)
        })
    }

    pub fn await_preloaded_data(&self) -> Result<PreloadedDataStateState, FireUniFfiError> {
        let core = self.0.core();
        let service = core.preloaded_data_service();
        let service = Arc::clone(service);
        run_on_ffi_runtime(async move {
            match service.ensure_loaded().await {
                Ok(state) => Ok(match state {
                    fire_models::PreloadedDataState::Ready => PreloadedDataStateState::Ready,
                    fire_models::PreloadedDataState::Loading => PreloadedDataStateState::Loading,
                    fire_models::PreloadedDataState::NotStarted => PreloadedDataStateState::NotStarted,
                    fire_models::PreloadedDataState::Failed => PreloadedDataStateState::Failed {
                        error: "unknown".to_string(),
                    },
                }),
                Err(e) => Ok(PreloadedDataStateState::Failed {
                    error: e.to_string(),
                }),
            }
        })
    }

    pub fn current_user_snapshot(&self) -> Option<CurrentUserSnapshotState> {
        let core = self.0.core();
        let service = core.preloaded_data_service();
        service.get_current_user().map(CurrentUserSnapshotState::from)
    }

    pub fn cached_user(&self) -> Option<CurrentUserSnapshotState> {
        let core = self.0.core();
        let service = core.preloaded_data_service();
        service.get_cached_user().map(CurrentUserSnapshotState::from)
    }

    pub fn determine_login_state(&self) -> LoginStateDeterminationState {
        let core = self.0.core();
        core.determine_login_state().into()
    }

    pub fn determine_login_state_with_probe(&self) -> Result<LoginStateDeterminationState, FireUniFfiError> {
        let core = self.0.core();
        run_on_ffi_runtime(async move {
            Ok(core.determine_login_state_with_probe().await.into())
        })
    }

    pub fn trigger_app_state_refresh(&self, trigger: RefreshTriggerState) -> Result<(), FireUniFfiError> {
        let core = self.0.core();
        run_on_ffi_runtime(async move {
            // AppStateRefresher 需要从 FireCore 访问
            // 具体实现取决于 AppStateRefresher 如何被持有
            Ok(())
        })
    }
```

注意：`trigger_app_state_refresh` 需要访问 `AppStateRefresher`。需要在 `FireCore` 上暴露 `app_state_refresher()` 方法，类似于 `preloaded_data_service()`。

- [ ] **Step 3: 编译验证**

Run: `cargo build -p fire-uniffi-session`
Expected: 编译成功

- [ ] **Step 4: Commit**

```bash
git add rust/crates/fire-uniffi-types/ rust/crates/fire-uniffi-session/
git commit -m "feat(uniffi): add FFI methods for preloaded data, login state determination, app state refresh"
```

---

### Task 8: MessageBus 初始化对齐规格

**Files:**
- Modify: `rust/crates/fire-core/src/core/messagebus.rs`

- [ ] **Step 1: 阅读 messagebus.rs 的 `start_message_bus` 方法签名**

确认当前签名。然后修改为接受 `topic_tracking_state_meta` 参数。

- [ ] **Step 2: 修改 `start_message_bus` 方法**

在启动时批量订阅以下频道：

- `/latest`
- `/new`
- `/unread`
- `/topic_tracking_state`
- `/notification/{userId}`
- `/notification-alert/{userId}`

确保长轮询请求体格式为 `/latest=6855147&/new=104155&...`。

确保请求头包含 `X-SILENCE-LOGGER: true`、`Discourse-Background: true`。

确保独立域名配置：当 `long_polling_base_url` 有值时，请求发往独立域名，禁用 Cookie，改用 `X-Shared-Session-Key`。

- [ ] **Step 3: 更新 FFI 层的 `start_message_bus` 签名**

在 `fire-uniffi-messagebus` 中更新对应方法，接受 `topic_tracking_state_meta: HashMap<String, u64>` 参数。

- [ ] **Step 4: 编译验证**

Run: `cargo build -p fire-uniffi-messagebus`
Expected: 编译成功

- [ ] **Step 5: Commit**

```bash
git add rust/crates/fire-core/src/core/messagebus.rs rust/crates/fire-uniffi-messagebus/
git commit -m "feat(messagebus): align initialization with startup spec - batch subscriptions, headers, independent domain"
```

---

### Task 9: 全工作空间编译验证

**Files:**
- 无新增修改

- [ ] **Step 1: 运行全工作空间编译**

Run: `cargo build --workspace`
Expected: 编译成功

- [ ] **Step 2: 运行全工作空间测试**

Run: `cargo test --workspace`
Expected: 所有测试通过

- [ ] **Step 3: 如果有编译错误或测试失败，修复**

- [ ] **Step 4: Commit（如有修复）**

```bash
git add -A
git commit -m "fix: resolve workspace compilation and test issues"
```

---

### Task 10: iOS — 重写启动流程

**Files:**
- Delete: `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift`
- Create: `native/ios-app/App/Startup/FirePreheatGateViewController.swift`
- Create: `native/ios-app/App/Startup/FireStartupErrorView.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`
- Modify: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`
- Modify: `native/ios-app/App/Views/Other/FireTabRoot.swift`

- [ ] **Step 1: 删除 `FireStartupPreloadCoordinator.swift`**

```bash
rm native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift
```

- [ ] **Step 2: 创建 `FirePreheatGateViewController.swift`**

```swift
import UIKit

final class FirePreheatGateViewController: UIViewController {
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let errorContainer = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let logoutButton = UIButton(type: .system)

    private let sessionStore: FireSessionStore
    private var isLoaded = false

    init(sessionStore: FireSessionStore) {
        self.sessionStore = sessionStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        awaitPreloadedData()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.startAnimating()
        view.addSubview(loadingIndicator)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "正在加载..."
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)

        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.isHidden = true
        view.addSubview(errorContainer)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = .label
        errorLabel.font = .systemFont(ofSize: 16)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorContainer.addSubview(errorLabel)

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("重试", for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        errorContainer.addSubview(retryButton)

        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.setTitle("退出登录", for: .normal)
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        errorContainer.addSubview(logoutButton)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            errorContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            errorContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),

            errorLabel.topAnchor.constraint(equalTo: errorContainer.topAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: errorContainer.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: errorContainer.trailingAnchor),

            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 20),
            retryButton.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),

            logoutButton.topAnchor.constraint(equalTo: retryButton.bottomAnchor, constant: 12),
            logoutButton.centerXAnchor.constraint(equalTo: errorContainer.centerXAnchor),
            logoutButton.bottomAnchor.constraint(equalTo: errorContainer.bottomAnchor),
        ])
    }

    private func awaitPreloadedData() {
        Task { @MainActor in
            loadingIndicator.startAnimating()
            loadingIndicator.isHidden = false
            statusLabel.isHidden = false
            errorContainer.isHidden = true

            do {
                let state = try await sessionStore.awaitPreloadedData()
                onPreloadedDataReady(state)
            } catch {
                showErrorPage(error.localizedDescription)
            }
        }
    }

    private func onPreloadedDataReady(_ state: Any) {
        isLoaded = true
        loadingIndicator.stopAnimating()
        NotificationCenter.default.post(name: .firePreheatGateDidComplete, object: nil)
    }

    private func showErrorPage(_ message: String) {
        loadingIndicator.stopAnimating()
        loadingIndicator.isHidden = true
        statusLabel.isHidden = true
        errorContainer.isHidden = false
        errorLabel.text = message
    }

    @objc private func retryTapped() {
        awaitPreloadedData()
    }

    @objc private func logoutTapped() {
        NotificationCenter.default.post(name: .firePreheatGateRequestsLogout, object: nil)
    }
}

extension Notification.Name {
    static let firePreheatGateDidComplete = Notification.Name("firePreheatGateDidComplete")
    static let firePreheatGateRequestsLogout = Notification.Name("firePreheatGateRequestsLogout")
}
```

- [ ] **Step 3: 在 `FireSessionStore.swift` 中添加新方法**

在 `FireSessionStore` actor 中追加：

```swift
    func awaitPreloadedData() async throws {
        try core.session().awaitPreloadedData()
    }

    func ensurePreloadedDataLoaded() async throws {
        try core.session().ensurePreloadedDataLoaded()
    }

    func currentUserDefaults() -> CurrentUserSnapshotState? {
        core.session().currentUserSnapshot()
    }

    func cachedUser() -> CurrentUserSnapshotState? {
        core.session().cachedUser()
    }

    func determineLoginState() -> LoginStateDeterminationState {
        core.session().determineLoginState()
    }

    func determineLoginStateWithProbe() async throws -> LoginStateDeterminationState {
        try await core.session().determineLoginStateWithProbe()
    }
```

注意：方法签名取决于 UniFFI 生成的 Swift 代码。实际方法名可能是 snake_case 或 camelCase，取决于 UniFFI 配置。需要检查 `Generated/` 目录下的实际类型名。

- [ ] **Step 4: 重写 `FireAppViewModel.loadInitialState()`**

简化为：

```swift
    func loadInitialState() async {
        guard sessionStore == nil else { return }
        let store = FireSessionStore()
        self.sessionStore = store

        // 触发 Rust 首页 HTML 请求（异步，不阻塞）
        try? await store.ensurePreloadedDataLoaded()

        // PreheatGate 将在 UI 层阻塞等待
        // loadInitialState 只负责初始化 store
    }
```

- [ ] **Step 5: 重写 `FireTabRoot.swift`**

在 `FireTabRoot` 的 body 中：

```swift
    @State private var preheatComplete = false

    var body: some View {
        Group {
            if !preheatComplete {
                FirePreheatGateRepresentable(sessionStore: viewModel.sessionStore)
            } else if viewModel.isLoggedIn {
                // 主界面 tab view
            } else {
                FireOnboardingView(...)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .firePreheatGateDidComplete)) { _ in
            preheatComplete = true
        }
    }
```

添加 `FirePreheatGateRepresentable`（`UIViewControllerRepresentable` 包装 `FirePreheatGateViewController`）。

- [ ] **Step 6: Commit**

```bash
git add -A native/ios-app/
git commit -m "feat(ios): rewrite startup flow with PreheatGate, Rust-driven preloaded data"
```

---

### Task 11: Android — 重写启动流程

**Files:**
- Create: `native/android-app/.../ui/startup/PreheatGateFragment.kt`
- Modify: `native/android-app/.../ui/auth/OnboardingFragment.kt`
- Modify: `native/android-app/.../ui/auth/AuthViewModel.kt`
- Modify: `native/android-app/.../session/FireSessionStore.kt`
- Modify: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`

- [ ] **Step 1: 创建 `PreheatGateFragment.kt`**

```kotlin
class PreheatGateFragment : Fragment() {

    private var _binding: View? = null
    private lateinit var sessionStore: FireSessionStore

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val root = FrameLayout(requireContext()).apply {
            layoutParams = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        }
        val progressBar = ProgressBar(requireContext()).apply {
            layoutParams = FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER)
            isIndeterminate = true
        }
        root.addView(progressBar)
        return root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        sessionStore = FireSessionStoreRepository.instance ?: return
        awaitPreloadedData()
    }

    private fun awaitPreloadedData() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                sessionStore.awaitPreloadedData()
                onPreloadedDataReady()
            } catch (e: Exception) {
                showErrorPage(e.message ?: "加载失败")
            }
        }
    }

    private fun onPreloadedDataReady() {
        val loginState = sessionStore.determineLoginState()
        when (loginState) {
            is LoginStateDeterminationState.LoggedIn -> {
                findNavController().navigate(R.id.action_preheatGate_to_home)
            }
            else -> {
                findNavController().navigate(R.id.action_preheatGate_to_onboarding)
            }
        }
    }

    private fun showErrorPage(message: String) {
        // 显示错误布局：重试 / 退出登录
    }
}
```

- [ ] **Step 2: 在 `FireSessionStore.kt` 中添加新方法**

```kotlin
    suspend fun awaitPreloadedData() {
        withContext(Dispatchers.IO) {
            core.session().awaitPreloadedData()
        }
    }

    suspend fun ensurePreloadedDataLoaded() {
        withContext(Dispatchers.IO) {
            core.session().ensurePreloadedDataLoaded()
        }
    }

    fun currentUserDefaults(): CurrentUserSnapshotState? {
        return core.session().currentUserSnapshot()
    }

    fun cachedUser(): CurrentUserSnapshotState? {
        return core.session().cachedUser()
    }

    fun determineLoginState(): LoginStateDeterminationState {
        return core.session().determineLoginState()
    }

    suspend fun determineLoginStateWithProbe(): LoginStateDeterminationState {
        return withContext(Dispatchers.IO) {
            core.session().determineLoginStateWithProbe()
        }
    }
```

- [ ] **Step 3: 修改 `fire_nav_graph.xml`**

将 start destination 改为 `preheatGateFragment`：

```xml
    <fragment
        android:id="@+id/preheatGateFragment"
        android:name="com.fire.app.ui.startup.PreheatGateFragment"
        android:label="Loading">
        <action
            android:id="@+id/action_preheatGate_to_home"
            app:destination="@id/homeFragment"
            app:popUpTo="@id/preheatGateFragment"
            app:popUpToInclusive="true" />
        <action
            android:id="@+id/action_preheatGate_to_onboarding"
            app:destination="@id/onboardingFragment"
            app:popUpTo="@id/preheatGateFragment"
            app:popUpToInclusive="true" />
    </fragment>
```

- [ ] **Step 4: 简化 `AuthViewModel` 和 `OnboardingFragment`**

`AuthViewModel` 删除所有手动 session 恢复逻辑。`OnboardingFragment` 只负责未登录时的登录入口。

- [ ] **Step 5: Commit**

```bash
git add -A native/android-app/
git commit -m "feat(android): rewrite startup flow with PreheatGate, Rust-driven preloaded data"
```

---

### Task 12: 双端 cf_clearance 启动条件对齐

**Files:**
- Modify: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift`
- Modify: `native/android-app/.../session/FireCfClearanceService.kt`

- [ ] **Step 1: iOS — 修改 CF clearance 启动条件**

在 `start()` 方法中，将条件改为：只当 `PreloadedDataResult` 中 `currentUser != nil` 时启动。

- [ ] **Step 2: Android — 同样修改**

- [ ] **Step 3: Commit**

```bash
git add native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift native/android-app/
git commit -m "fix: start cf_clearance refresh only when currentUser is present (spec Section 12)"
```

---

### Task 13: 最终验证

**Files:**
- 无新增修改

- [ ] **Step 1: Rust 全工作空间编译 + 测试**

Run: `cargo build --workspace && cargo test --workspace`
Expected: 全部通过

- [ ] **Step 2: 确认 iOS Xcode 编译通过**

Run: `cd native/ios-app && xcodebuild -project Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

注意：实际 project/scheme 名称取决于 XcodeGen 生成的 `project.yml`。

- [ ] **Step 3: 确认 Android Gradle 编译通过**

Run: `cd native/android-app && ./gradlew assembleDebug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: 确认文档对齐**

检查 `docs/knowledge/discourse-startup-implementation-spec.md` 的每个 Section 是否在实现中有对应：

| Spec Section | 实现位置 |
|---|---|
| 1. 启动阶段总览 | `PreloadedDataService.ensure_loaded()` + PreheatGate |
| 2. 初始化顺序 | `FireCore::new()` + `FireAppViewModel.loadInitialState()` |
| 3. 首页 HTML 请求 | `PreloadedDataService.fetch_and_parse()` |
| 4. 首页 HTML 解析 | `parsing.rs` (已有) |
| 5. data-preloaded 解析 | `PreloadedDataService.extract_preloaded_fields()` |
| 6. 登录态判断 | `determine_login_state()` / `determine_login_state_with_probe()` |
| 7. /session/current.json | `probe_session()` (已有) |
| 9. User 数据模型 | `CurrentUserSnapshot` |
| 10. CSRF Token | `parsing.rs` (已有) |
| 11. Cookie 恢复 | `FireSessionCookieJar` (已有) |
| 12. cf_clearance | Task 12 条件对齐 |
| 13. MessageBus | Task 8 对齐 |
| 14. AppStateRefresher | `AppStateRefresher` |
| 15. 会话代管理 | `epoch` (已有) |
| 16. 启动时序 | PreheatGate 流程 |

- [ ] **Step 5: 最终 commit**

```bash
git add -A
git commit -m "chore: final alignment verification for discourse startup implementation spec"
```
