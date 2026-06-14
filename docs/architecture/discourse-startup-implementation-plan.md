# 重构 Fire 启动阶段：对齐 Discourse 启动实现规格

## Breaking Change Notice

本文档为**破坏性重构**。所有启动阶段代码将完全重写以对齐 `docs/knowledge/discourse-startup-implementation-spec.md`。不保留任何兼容代码，不提供迁移路径。

1. iOS 端：删除 `FireStartupPreloadCoordinator`，重写 `FireAppViewModel.loadInitialState()`，新增 `FirePreheatGateViewController`、`FireAppStateRefresher`。
2. Android 端：删除 `AuthViewModel.restoreSession()` 现有逻辑，重写 `OnboardingFragment` 启动流程，新增 `PreheatGateFragment`、`AppStateRefresher`。
3. Rust 端：新增 `PreloadedDataService` 模块、`AppStateRefresher` 模块；重写启动时序编排。

## Feasibility Assessment

Fully feasible。Rust 核心已有完整的 bootstrap 解析（`parsing.rs`）、session 管理（`core/session.rs`）、CSRF 刷新（`core/auth.rs`）、cookie 管理（`cookies.rs`）、MessageBus（`core/messagebus.rs`）、auth strike（`core/auth_strike.rs`）、probe（`core/auth.rs`）等能力。两端平台已有 WebView login coordinator 和 FFI 桥接。缺失部分是启动阶段编排（首页 HTML 请求与 UI 并行、PreheatGate 阻塞、AppStateRefresher 分批刷新）和 User 数据模型在 Rust 侧的完整定义。这些都是增量开发，无技术障碍。

## Current Surface Inventory

### Rust（需变更）

- `fire-core/src/core/mod.rs` — `FireCore` 主结构体，持有 session/network/diagnostics
- `fire-core/src/core/session.rs` — session 应用方法（merge/apply/sync/finalize）
- `fire-core/src/core/auth.rs` — bootstrap 刷新、CSRF 刷新、probe、passive logout、strike
- `fire-core/src/core/network.rs` — 网络层 + 拦截器
- `fire-core/src/parsing.rs` — HTML bootstrap 解析（parse_home_state）
- `fire-core/src/session_store.rs` — session 持久化
- `fire-models/src/session.rs` — BootstrapArtifacts、LoginPhase、SessionSnapshot
- `fire-models/src/user.rs` — UserProfile（目前只有 profile/summary 模型，缺少启动期 currentUser 快照模型）
- `fire-uniffi-session/src/lib.rs` — session FFI handle

### iOS（需变更）

- `native/ios-app/App/ViewModels/FireAppViewModel.swift`（~2664 行）— 中央 ViewModel，包含启动、登录、所有 API 调用
- `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift` — 当前启动预加载（将被删除）
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`（~1314 行）— actor FFI 桥接
- `native/ios-app/App/Core/FireRootCoordinator.swift` — UIKit root/preheat/auth/main-tab gate
- `native/ios-app/App/Core/FireMainTabBarController.swift` — UIKit authenticated tab shell
- `native/ios-app/App/Views/Other/FireOnboardingView.swift` — SwiftUI 引导页（将被重写为 UIKit）

### Android（需变更）

- `native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt` — 启动鉴权
- `native/android-app/src/main/java/com/fire/app/ui/auth/AuthViewModel.kt` — session 恢复
- `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt` — FFI 桥接
- `native/android-app/src/main/java/com/fire/app/data/repository/SessionRepository.kt` — session 操作

## Design

以 `docs/knowledge/discourse-startup-implementation-spec.md` 为唯一权威目标规格。所有实现细节严格对齐该文档，不论现有代码如何。

### Key Design Decisions

1. **首页 HTML 请求归 Rust 所有，与 UI 并行发起** — 规格要求 `main()` 尾部 `unawaited(ensureLoaded())` 与 UI 渲染并行。Rust 新增 `PreloadedDataService`，在 `FireCore` 构造后立即发起 `GET https://linux.do` HTML 请求，平台在 `main()`/`Application.onCreate()` 触发。不用平台发起 HTTP。

2. **PreheatGate 阻塞 UI 渲染** — 规格要求 Widget 树中 PreheatGate 阻塞等待首页数据。iOS 新增 `FirePreheatGateViewController`，Android 新增 `PreheatGateFragment`。在首页数据加载完成前显示加载指示器；失败则显示错误页面（重试/退出登录/网络设置）。

3. **data-preloaded 作为登录态首要判断依据** — 规格明确 `currentUser` 的存在与否是启动期判断登录态的首要依据。不依赖额外的 `/session/current.json` 调用（除非无预加载 currentUser 但 CookieJar 有 _t）。

4. **AppStateRefresher 由 Rust 单点编排** — 规格要求 authState 变化后，第一批立即刷新核心数据，第二批延迟 1 秒刷新次要数据。当前实现以 Rust `AppStateRefresher` 为唯一编排器；平台只触发 `triggerAppStateRefresh(...)` 并消费批次 callback，不再各自维护平台版 refresher。首页当前 tab 的 `kind/category/tags` 选择状态也由 Rust runtime 持有，平台只同步 UI 选择。

5. **User 启动期缓存模型** — 规格要求启动时将 User 序列化缓存，下次启动先从缓存返回。Rust 侧新增 `CurrentUserCache`，持久化到 SQLite。

6. **会话代完全归 Rust** — 规格的 `AuthSession.advance()` 已在 Rust 中以 `epoch` 实现。平台不再自行维护代数，只从 Rust session snapshot 读取。

7. **删除 Flutter/Dart 特有概念** — 规格中 SharedPreferences、CookieJar（Dart 实现）、MigrationService 等 Flutter 概念不迁移。对应功能在 Rust 中已有（session.json 持久化、openwire CookieJar、session_store 迁移）。

### 新增类型定义

#### Rust: CurrentUserSnapshot（轻量启动期用户缓存）

```rust
// fire-models/src/user.rs

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CurrentUserSnapshot {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub animated_avatar: Option<String>,
    pub trust_level: u8,
    pub status: Option<UserStatus>,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserStatus {
    pub description: Option<String>,
    pub emoji: Option<String>,
}
```

#### Rust: PreloadedDataService 输出

```rust
// fire-models/src/session.rs additions

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreloadedDataResult {
    pub current_user: Option<CurrentUserSnapshot>,
    pub site_settings: Option<serde_json::Value>,
    pub site: Option<serde_json::Value>,
    pub topic_tracking_state_meta: Option<std::collections::HashMap<String, u64>>,
    pub topic_tracking_states: Option<Vec<serde_json::Value>>,
    pub custom_emoji: Option<Vec<serde_json::Value>>,
    pub topic_list: Option<serde_json::Value>,
    pub enabled_reaction_ids: Option<Vec<String>>,
    pub categories: Option<Vec<serde_json::Value>>,
    pub top_tags: Option<Vec<String>>,
    pub can_tag_topics: Option<bool>,
}
```

#### Rust: AppStateRefresherRequest

```rust
// fire-models/src/session.rs additions

#[derive(Debug, Clone)]
pub enum RefreshBatch {
    Core,
    Secondary,
}

#[derive(Debug, Clone)]
pub struct AppStateRefreshEvent {
    pub batch: RefreshBatch,
    pub trigger: RefreshTrigger,
}

#[derive(Debug, Clone)]
pub enum RefreshTrigger {
    LoginCompleted,
    LogoutCompleted,
    SessionRestored,
}
```

#### FFI: StateObserver 回调增强

```rust
// fire-uniffi-types additions

trait StateObserver: Send + Sync {
    fn on_session_snapshot(&self, snapshot: SessionSnapshotState);
    fn on_passive_logout(&self, trigger: PassiveLogoutTriggerState);
    fn on_cf_clearance_expired(&self);
    fn on_preloaded_data_ready(&self, result: PreloadedDataResultState);
    fn on_app_state_refresh_needed(&self, event: AppStateRefreshEventState);
}
```

#### iOS: PreheatGate

```swift
// native/ios-app/App/Startup/FirePreheatGateViewController.swift

final class FirePreheatGateViewController: UIViewController {
    // 阻塞等待首页数据加载完成
    // 显示 UI: 加载指示器 / 错误页面
    // 成功后自动 transition 到 FireMainTabViewController
    // 失败: 重试 / 退出登录 / 网络设置
}
```

#### Android: PreheatGate

```kotlin
// native/android-app/.../ui/startup/PreheatGateFragment.kt

class PreheatGateFragment : Fragment() {
    // 阻塞等待首页数据加载完成
    // 显示 UI: ProgressBar / Error layout
    // 成功后自动 navigate 到 HomeFragment
    // 失败: 重试 / 退出登录 / 网络设置
}
```

## Phased Implementation

### Phase 1: Rust — 新增 PreloadedDataService 与 User 启动期模型

#### File: `rust/crates/fire-models/src/user.rs`

- 新增 `CurrentUserSnapshot` 结构体（规格 Section 9 所有字段）
- 新增 `UserStatus` 结构体（description + emoji）
- 新增 `AvatarUrlCalculator` 工具：`calculate_avatar_url(template, animated_avatar, base_url, size) -> String`

#### File: `rust/crates/fire-models/src/session.rs`

- 新增 `PreloadedDataResult` 结构体
- 新增 `AppStateRefreshEvent`、`RefreshBatch`、`RefreshTrigger` 枚举
- 新增 `PreloadedDataState` 枚举：`NotStarted` | `Loading` | `Ready(PreloadedDataResult)` | `Failed(Error)`

#### File: `rust/crates/fire-models/src/lib.rs`

- 注册新模块，确保编译通过

#### File: `rust/crates/fire-core/src/preloaded_data.rs`（新文件）

- `PreloadedDataService` 结构体：
  - `ensure_loaded(&self) -> Result<()>`：发起 `GET https://linux.do` HTML 请求，调用 `parse_home_state()` + `hydrate_preloaded_fields()`，将结果存入内存
  - 防重入：`_loading` 标志
  - 成功后通过 `StateObserver.on_preloaded_data_ready()` 推送
- `get_current_user_snapshot(&self) -> Option<CurrentUserSnapshot>`：同步返回已加载的用户数据
- `get_cached_user(&self) -> Option<CurrentUserSnapshot>`：从 SQLite 缓存读取（启动早期）
- `cache_current_user(&self, user: &CurrentUserSnapshot)`：写入 SQLite 缓存
- 解析逻辑复用现有 `parsing.rs`

#### File: `rust/crates/fire-core/src/core/mod.rs`

- 新增 `preloaded_data: Arc<RwLock<PreloadedDataState>>` 字段
- 新增 `preloaded_data_service: Arc<PreloadedDataService>` 字段
- 新增公开方法 `preloaded_data_service(&self) -> Arc<PreloadedDataService>`

#### File: `rust/crates/fire-store/src/lib.rs`

- 新增 `current_user_cache` 表：key TEXT PRIMARY KEY, data TEXT, updated_at INTEGER
- 新增 `get_cached_user() -> Option<String>`
- 新增 `set_cached_user(data: &str)`
- 新增 `clear_cached_user()`

#### File: `rust/crates/fire-core/src/lib.rs`

- 注册 `preloaded_data` 模块

### Phase 2: Rust — AppStateRefresher 编排

#### File: `rust/crates/fire-core/src/app_state_refresher.rs`（新文件）

- `AppStateRefresher` 结构体，持有 `FireCore` 引用
- `refresh_all(&self, trigger: RefreshTrigger)`:
  - 第一批（立即执行）：
    - 强制刷新 bootstrap / categories / current user / topic tracking 基线
    - 使用 Rust 持有的 `current home topic-list scope` 请求当前首页列表
    - 向平台回调 `RefreshBatch::Core`
  - 第二批（延迟 1 秒，避免并发过多触发风控）：
    - userSummary（`/u/{username}/summary.json`）
    - recent notifications（`/notifications.json`）
    - 浏览历史（`/read.json`）
    - bookmarks（`/u/{username}/bookmarks.json`）
    - 向平台回调 `RefreshBatch::Secondary`
- 去抖：2 秒内重复调用直接跳过
- 通过 UniFFI `AppStateRefreshHandler` 通知平台各批次完成

#### File: `rust/crates/fire-core/src/core/auth.rs`

- 修改 `probe_session()` 返回值增加 `CurrentUserSnapshot`
- 修改 `refresh_bootstrap()` 解析完成后同时填充 `PreloadedDataService` 的内存状态和 User 缓存
- 新增 `refresh_current_user_with_cooldown(&self) -> Result<Option<CurrentUserSnapshot>>`：2 分钟冷却

#### File: `rust/crates/fire-core/src/core/session.rs`

- 新增 `determine_login_state(&self) -> LoginStateDetermination` 方法，实现规格 Section 6 的完整判断路径：
  ```
  首页 HTML 解析完成 → data-preloaded 有 currentUser?
    ├── 有 → 已登录，同步返回用户数据
    └── 无 → CookieJar 有 _t?
              ├── 无 → 确认未登录
              └── 有 → probe_session()
                        ├── 有 current_user → 确认已登录
                        ├── 无/404/401/403 → 确认失效 → 执行登出
                        └── 网络异常 → 保守保留登录态
  ```

#### File: `rust/crates/fire-core/src/core/mod.rs`

- 新增 `app_state_refresher: Arc<AppStateRefresher>` 字段
- 新增公开方法 `app_state_refresher(&self) -> Arc<AppStateRefresher>`
- 在 session state 变更时触发 `app_state_refresher.refresh_all()`

#### File: `rust/crates/fire-core/src/lib.rs`

- 注册 `app_state_refresher` 模块

### Phase 3: Rust — FFI 暴露启动阶段 API

#### File: `rust/crates/fire-uniffi-session/src/lib.rs`

新增 FFI 方法：

- `fn ensure_preloaded_data_loaded(&self) -> Result<()>` — 触发首页 HTML 请求
- `fn preloaded_data_state(&self) -> PreloadedDataStateState` — 返回当前状态
- `fn current_user_snapshot(&self) -> Option<CurrentUserSnapshotState>` — 返回已加载用户
- `fn cached_user(&self) -> Option<CurrentUserSnapshotState>` — 返回缓存用户
- `fn determine_login_state(&self) -> LoginStateDeterminationState` — 登录态判断
- `fn trigger_app_state_refresh(&self, trigger: RefreshTriggerState) -> Result<()>` — 手动触发刷新

#### File: `rust/crates/fire-uniffi-types/src/records/`

新增 FFI record 类型：

- `CurrentUserSnapshotState` — 映射 `CurrentUserSnapshot`
- `PreloadedDataResultState` — 映射 `PreloadedDataResult`
- `PreloadedDataStateState` — 枚举：NotStarted / Loading / Ready / Failed
- `LoginStateDeterminationState` — 枚举：LoggedIn(CurrentUserSnapshotState) / NotLoggedIn / SessionExpired / NetworkErrorPreserveState
- `AppStateRefreshEventState` — 映射刷新事件
- `RefreshTriggerState` — 枚举
- `RefreshBatchState` — 枚举

#### File: `rust/crates/fire-uniffi/src/lib.rs`

- 确保 `FireAppCore` 暴露新增的 session 方法

### Phase 4: Rust — MessageBus 初始化对齐规格

#### File: `rust/crates/fire-core/src/core/messagebus.rs`

- 修改 `start_message_bus()` 接受 `topic_tracking_state_meta: HashMap<String, u64>` 参数
- 启动时批量订阅频道：`/latest`、`/new`、`/unread`、`/topic_tracking_state`
- 额外订阅通知频道：`/notification/{userId}`、`/notification-alert/{userId}`
- 长轮询请求体格式对齐规格：`/latest=6855147&/new=104155&...`
- 请求头：`X-Shared-Session-Key`（独立域名时）、`X-SILENCE-LOGGER: true`、`Discourse-Background: true`
- 独立域名配置：当 `long_polling_base_url` 有值时，请求发往独立域名，禁用 Cookie，改用 `X-Shared-Session-Key`

#### File: `rust/crates/fire-uniffi-messagebus/src/lib.rs`

- 修改 `start_message_bus()` 签名，接受 `topic_tracking_state_meta` 参数

### Phase 5: Rust — 启动时序编排

#### File: `rust/crates/fire-core/src/core/mod.rs`

新增 `initialize_startup_sequence(&self) -> Result<()>` 方法，实现规格的完整启动时序：

```
Phase A: main() 初始化
  1. 创建 FireCore（已有的构造函数）
  2. 并行触发 PreloadedDataService.ensure_loaded()（unawaited）
  3. 返回，让平台开始 UI 渲染

Phase B: 平台 PreheatGate 调用 await_preloaded_data()
  1. 阻塞等待首页数据加载完成
  2. 解析 data-preloaded → 判断登录态
  3. 已登录 → 启动 CfClearanceRefresh（通知平台）
  4. 失败 → 返回错误，平台显示错误页面

Phase C: 主界面就绪后
  1. 平台调用 initialize_post_ui() 
  2. 已登录 → 启动 MessageBus（传入 topic_tracking_state_meta）
  3. 触发 AppStateRefresher.refresh_all(SessionRestored)
```

#### File: `rust/crates/fire-uniffi-session/src/lib.rs`

新增 FFI 方法：

- `fn await_preloaded_data(&self) -> Result<PreloadedDataResultState>` — 阻塞等待首页数据
- `fn initialize_post_ui(&self) -> Result<()>` — 主界面就绪后初始化

### Phase 6: iOS — 重写启动流程

#### 删除以下文件

- **File: `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift`** — 删除，被 Rust PreloadedDataService 替代

#### File: `native/ios-app/App/Startup/FirePreheatGateViewController.swift`（新文件）

UIKit ViewController 实现 PreheatGate：

```swift
final class FirePreheatGateViewController: UIViewController {
    private let sessionStore: FireSessionStore
    private let loadingView = UIActivityIndicatorView(style: .large)
    private let errorView: FireStartupErrorView  // 自定义错误视图

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI() // 加载指示器居中
        awaitPreloadedData()
    }

    private func awaitPreloadedData() {
        Task {
            do {
                let result = try await sessionStore.awaitPreloadedData()
                onPreloadedDataReady(result)
            } catch {
                showErrorPage(error)
            }
        }
    }

    private func onPreloadedDataReady(_ result: PreloadedDataResultState) {
        // 检查是否需要重新登录（数据迁移导致 Cookie 清空）
        if result.requiresRelogin {
            showReloginDialog()
            return
        }
        // 成功 → transition 到主界面
        transitionToMainTab()
    }

    private func showErrorPage(_ error: Error) {
        // 显示错误页面：重试 / 退出登录 / 网络设置
    }
}
```

#### File: `native/ios-app/App/Startup/FireStartupErrorView.swift`（新文件）

自定义 UIKit 错误视图：图标 + 错误信息 + 三个按钮（重试/退出登录/网络设置）

#### File: `native/ios-app/App/Startup/FireAppStateRefresher.swift`（新文件）

```swift
actor FireAppStateRefresher {
    private let sessionStore: FireSessionStore
    private var lastRefreshTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 2.0

    func refreshAll(trigger: RefreshTriggerState) async {
        // 去抖：2 秒内跳过
        guard Date().timeIntervalSince(lastRefreshTime) > debounceInterval else { return }
        lastRefreshTime = Date()

        // 第一批（通过 Rust FFI 触发，Rust 内部执行）
        // Rust 推送 on_app_state_refresh_needed(batch: .core)

        // 第二批（1 秒后）
        // Rust 推送 on_app_state_refresh_needed(batch: .secondary)
    }
}
```

#### File: `native/ios-app/App/ViewModels/FireAppViewModel.swift`

**大幅重写**。删除现有 `loadInitialState()` 中所有手动编排逻辑，替换为：

```swift
func loadInitialState() async {
    // 1. 创建 FireSessionStore（Rust FireAppCore）
    // 2. 触发 Rust ensurePreloadedDataLoaded()（异步，不阻塞）
    // 3. 展示 FirePreheatGateViewController
    // 4. PreheatGate 完成后：
    //    - 设置 StateObserver 监听 session 变化
    //    - 调用 initializePostUi()
    //    - 根据 loginState 决定显示 Onboarding 还是 MainTab
}
```

删除所有直接 API 调用方法（topicList、search、notifications 等）。这些现在由 Stores 直接调用 Rust FFI。

#### File: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`

新增方法（包装 Rust FFI）：

- `func ensurePreloadedDataLoaded() async throws`
- `func awaitPreloadedData() async throws -> PreloadedDataResultState`
- `func initializePostUi() async throws`
- `func currentUserDefaults() -> CurrentUserSnapshotState?`
- `func cachedUser() -> CurrentUserSnapshotState?`
- `func determineLoginState() async -> LoginStateDeterminationState`
- `func triggerAppStateRefresh(trigger: RefreshTriggerState) async throws`

#### File: `native/ios-app/App/Core/FireRootCoordinator.swift`

当前 UIKit root gate：

- 未初始化：显示 `FirePreheatGateWaitingViewController` / `FirePreheatGateViewController`
- 已初始化未登录：显示当前 onboarding host（后续迁 UIKit）
- 已初始化已登录：显示 `FireMainTabBarController`（UIKit `UITabBarController`）

#### File: `native/ios-app/App/Views/Other/FireOnboardingView.swift`

重写为 UIKit：`FireOnboardingViewController`（如果 Phase 6 前尚未完成登录文档中要求的 UIKit 迁移）。

#### File: `native/ios-app/App/Navigation/FireMessageBusCoordinator.swift`

修改 `startMessageBus()` 调用，传入 `topicTrackingStateMeta`（从 preloaded data 获取）。

#### File: `native/ios-app/App/Core/SessionState+Helpers.swift`

新增 `fromPreloadedData()` 便利方法，从 `PreloadedDataResultState` 构建 UI 可用的 session state。

### Phase 7: Android — 重写启动流程

#### File: `native/android-app/.../ui/startup/PreheatGateFragment.kt`（新文件）

```kotlin
class PreheatGateFragment : Fragment() {
    private lateinit var progressBar: ProgressBar
    private lateinit var errorLayout: View

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        awaitPreloadedData()
    }

    private fun awaitPreloadedData() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val result = sessionStore.awaitPreloadedData()
                onPreloadedDataReady(result)
            } catch (e: Exception) {
                showErrorPage(e)
            }
        }
    }

    private fun onPreloadedDataReady(result: PreloadedDataResultState) {
        if (result.requiresRelogin) {
            showReloginDialog()
            return
        }
        // navigate to home or onboarding
    }

    private fun showErrorPage(error: Exception) {
        // 重试 / 退出登录 / 网络设置
    }
}
```

#### File: `native/android-app/.../ui/startup/PreheatGateLayout.kt`（新文件）

自定义布局：ProgressBar 居中 + Error 状态布局

#### File: `native/android-app/.../session/FireAppStateRefreshRepository.kt`（新文件）

Android 不再实现平台版 `AppStateRefresher`。改为提供一个进程级 callback repository：

- `PreheatGateFragment` / `LoginWebViewFragment` 用它作为 `triggerAppStateRefresh(..., handler)` 的 handler
- `HomeViewModel` 订阅该 repository，收到 `RefreshBatch::Core` 后刷新权威 snapshot、按需接通/关闭 MessageBus，并触发当前列表刷新
- 首页 `kind/category/tags` 选择状态通过 `FireSessionStore.currentHomeTopicListScope()/setCurrentHomeTopicListScope(...)` 与 Rust runtime 同步，不再只存在于 ViewModel 本地
- 平台不再保留去抖和批次编排逻辑

#### File: `native/android-app/.../ui/auth/OnboardingFragment.kt`

**大幅重写**。删除现有 `restoreSession()` 逻辑，替换为：

```kotlin
override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
    super.onViewCreated(view, savedInstanceState)
    // 启动流程现在由 PreheatGateFragment 处理
    // Onboarding 只负责：未登录时显示登录入口
    observeLoginState()
}
```

#### File: `native/android-app/.../ui/auth/AuthViewModel.kt`

**大幅重写**。删除所有手动 session 恢复逻辑。ViewModel 只负责：

- 观察来自 Rust 的 `LoginStateDeterminationState`
- 暴露 `loginState: StateFlow<LoginStateDeterminationState>`
- 暴露 `cachedUser: StateFlow<CurrentUserSnapshotState?>`

#### File: `native/android-app/.../session/FireSessionStore.kt`

新增方法（包装 Rust FFI）：

- `suspend fun ensurePreloadedDataLoaded()`
- `suspend fun awaitPreloadedData(): PreloadedDataResultState`
- `suspend fun initializePostUi()`
- `fun currentUserDefaults(): CurrentUserSnapshotState?`
- `fun cachedUser(): CurrentUserSnapshotState?`
- `suspend fun determineLoginState(): LoginStateDeterminationState`
- `suspend fun triggerAppStateRefresh(trigger: RefreshTriggerState)`

#### File: `native/android-app/.../data/repository/SessionRepository.kt`

**大幅简化**。删除所有手动编排逻辑，保留为轻量包装：

```kotlin
class SessionRepository(private val sessionStore: FireSessionStore) {
    suspend fun restoreSession() {
        // 现在只是触发 Rust ensurePreloadedDataLoaded
        // 实际恢复由 Rust PreloadedDataService + session.json 处理
    }
}
```

#### File: `native/android-app/.../messagebus/FireMessageBusCoordinator.kt`

修改 `startMessageBus()` 调用，传入 `topicTrackingStateMeta`。

#### File: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`

修改导航图：

- Start destination 改为 `preheatGateFragment`
- `preheatGateFragment` → 根据 login state → `homeFragment` 或 `onboardingFragment`
- 删除直接从 `onboardingFragment` 到 `homeFragment` 的 auth check 逻辑（auth check 现在在 PreheatGate 中）

### Phase 8: 双端 — cf_clearance 自动续期对齐

#### File: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift`

修改启动条件：只在登录态已由权威 startup/login 路径确认、且 session 具备 `currentUser + canReadAuthenticatedApi + cf_clearance + turnstileSitekey` 时启动。

#### Android

Android 不保留后台 `cf_clearance` 自动续期 service。Cloudflare 续期继续保持为显式的 host-owned challenge WebView 完成路径；删除未接线、判定过时的 `FireCfClearanceService.kt`，避免形成第二套启动条件。

### Phase 9: 删除废弃代码

#### iOS 删除列表

| 文件 | 原因 |
|------|------|
| `App/Startup/FireStartupPreloadCoordinator.swift` | 被 Rust PreloadedDataService 替代 |

#### Android 删除列表

| 文件 | 原因 |
|------|------|
| `native/android-app/src/main/java/com/fire/app/session/FireCfClearanceService.kt` | 未接线的旧 helper，判定路径与权威 startup/login 状态机不一致 |
| `native/android-app/src/main/java/com/fire/app/data/repository/SessionRepository.kt` | 仅剩未使用的遗留 session 包装层，不再承担任何 startup 或 topic-detail 运行时职责 |

### Phase 10: 验证

- Rust: `cargo build --workspace` 编译通过
- Rust: `cargo test --workspace` 全部通过
- iOS: Xcode 编译通过，冷启动验证完整流程
- Android: Gradle 编译通过，冷启动验证完整流程
- 双端交叉验证启动时序对齐规格 Section 16

## Architectural Notes

- **无兼容层**：所有变更均为破坏性重写。不保留旧代码路径，不添加 fallback。
- **Rust 为唯一逻辑引擎**：启动时序编排、登录态判断、数据刷新全部在 Rust 中。平台只负责 UI 展示和用户交互。
- **StateObserver 推送模型**：Rust 主动推送 state snapshot 和 refresh event，平台被动接收。平台不轮询 Rust。
- **session.json + Keychain/Keystore 双层持久化**不变：Rust 持久化完整 session（含 bootstrap、cookies），平台安全存储 auth cookies。
- **新增 crate 依赖**：`fire-core` 新增对 `fire-store` 的 user cache 表依赖（已有依赖）。
- **MessageBus 启动时机变化**：从「login 完成即启动」改为「PreheatGate 完成 + 主界面就绪 + 已登录」才启动，对齐规格。
- **AppStateRefresher 是 Rust 侧单例**：不是平台侧概念。平台只接收 refresh event 并更新 UI。

## File Change Summary

### Rust

- `rust/crates/fire-models/src/user.rs` — 新增 CurrentUserSnapshot、UserStatus、AvatarUrlCalculator
- `rust/crates/fire-models/src/session.rs` — 新增 PreloadedDataResult、AppStateRefreshEvent、RefreshBatch、RefreshTrigger、PreloadedDataState
- `rust/crates/fire-models/src/lib.rs` — 注册新模块
- `rust/crates/fire-core/src/preloaded_data.rs` — 新文件：PreloadedDataService
- `rust/crates/fire-core/src/app_state_refresher.rs` — 新文件：AppStateRefresher
- `rust/crates/fire-core/src/core/mod.rs` — 新增 preloaded_data/app_state_refresher 字段和方法
- `rust/crates/fire-core/src/core/session.rs` — 新增 determine_login_state()
- `rust/crates/fire-core/src/core/auth.rs` — 修改 probe_session() 返回值，新增 refresh_current_user_with_cooldown()
- `rust/crates/fire-core/src/core/messagebus.rs` — 修改 start_message_bus() 接受 meta 参数，对齐规格轮询协议
- `rust/crates/fire-core/src/lib.rs` — 注册新模块
- `rust/crates/fire-store/src/lib.rs` — 新增 current_user_cache 表和 CRUD
- `rust/crates/fire-store/src/migrations.rs` — 新增 migration
- `rust/crates/fire-uniffi-session/src/lib.rs` — 新增 6 个 FFI 方法
- `rust/crates/fire-uniffi-messagebus/src/lib.rs` — 修改 start_message_bus() 签名
- `rust/crates/fire-uniffi-types/src/records/` — 新增 7 个 FFI record 类型
- `rust/crates/fire-uniffi/src/lib.rs` — 确保暴露新方法

### iOS

- `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift` — **删除**
- `native/ios-app/App/Startup/FirePreheatGateViewController.swift` — **新文件**：PreheatGate
- `native/ios-app/App/Startup/FireStartupErrorView.swift` — **新文件**：错误页面
- `native/ios-app/App/Startup/FireAppStateRefresher.swift` — **新文件**：刷新去抖
- `native/ios-app/App/ViewModels/FireAppViewModel.swift` — **大幅重写**：删除手动编排，改用 Rust 驱动
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` — 新增 7 个 FFI 包装方法
- `native/ios-app/App/Core/FireRootCoordinator.swift` — UIKit PreheatGate → Onboarding/MainTab root owner
- `native/ios-app/App/Core/FireMainTabBarController.swift` — UIKit authenticated tab shell
- `native/ios-app/App/Views/Other/FireOnboardingView.swift` — 重写为 UIKit
- `native/ios-app/App/Navigation/FireMessageBusCoordinator.swift` — 修改 MessageBus 启动参数
- `native/ios-app/App/Core/SessionState+Helpers.swift` — 新增 fromPreloadedData()
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` — 修改启动条件

### Android

- `native/android-app/.../ui/startup/PreheatGateFragment.kt` — **新文件**：PreheatGate
- `native/android-app/.../ui/startup/PreheatGateLayout.kt` — **新文件**：启动布局
- `native/android-app/.../startup/AppStateRefresher.kt` — **新文件**：刷新去抖
- `native/android-app/.../ui/auth/OnboardingFragment.kt` — **大幅重写**
- `native/android-app/.../ui/auth/AuthViewModel.kt` — **大幅重写**
- `native/android-app/.../session/FireSessionStore.kt` — 新增 7 个 FFI 包装方法
- `native/android-app/.../data/repository/SessionRepository.kt` — **大幅简化**
- `native/android-app/.../messagebus/FireMessageBusCoordinator.kt` — 修改 MessageBus 启动参数
- `native/android-app/.../session/FireCfClearanceService.kt` — 修改启动条件
- `native/android-app/src/main/res/navigation/fire_nav_graph.xml` — 修改 start destination
