# 统一启动登录页设计

> 日期：2026-06-17
> 状态：已确认，待实现（rev 3 — 对齐启动会话恢复语义与 validation 时序）
> 范围：iOS 启动流程 UI 合并，逻辑层保持解耦

## 修订记录

- **rev 3（本次）**：根据 `9a6fe30` 的启动会话恢复更新，修正 `performStartupValidation()` 设计：validation 必须自己拥有 `prepareStartupSession → awaitPreloadedData → completeStartupAfterPreheat` 全链路，不能依赖 `RootCoordinator.start()` 中的 `loadInitialState()` 先完成；`awaitPreloadedData()` 失败时需沿用当前 PreheatGate 的会话保留规则，存在 `canReadAuthenticatedApi` 或 `hasLoginCookie` 时继续完成启动判定，避免把仍需判定的本地会话直接判为启动失败。
- **rev 2**：根据对实际源码的二次核实修正四处 P1 缺陷与两处 P2。原 rev 1 误判 `isBootstrappingSession` 已覆盖校验全链路，且忽略了删除 preheat/auth modal 后 `completeStartupAfterPreheat()` 失去驱动方、captcha dialog 失去 dismiss 路径、saved credential 失去加载入口三个回归。详见各节"⚠️ rev 2 修正"标记。

## 背景与问题

当前 iOS 启动阶段存在三段式割裂体验，用户需要多次手动跳转和点击才能进入登录表单：

```
PreheatGate 页 (logo + loading "正在校验登录态…")
    │ 校验失败
    ▼
点击 "登录 LinuxDo" 按钮          ← 多一次手动点击
    ▼
FireLoginViewController (logo + 账号密码表单 + 登录按钮)  ← 又一个 logo，又一个页面
    │ 点击 "登录" 按钮
    ▼
hCaptcha dialog → 登录完成
```

割裂的根因是三个页面服务于两个独立的 root kind 状态加一个 modal present 路径：

| 控制器 | 角色 | 触发条件 |
|---|---|---|
| `FirePreheatGateWaitingViewController`（含 `FirePreheatGateViewController`） | root kind `.preheat`，校验本地登录态 | 冷启动 |
| `FireOnboardingViewController` | root kind `.onboarding`，未认证的等待页 | preheat 完成且未认证 |
| `FireLoginViewController` | modal 全屏页，账号密码表单 | `authPresentationState == .login` |

三套 UI 各自重复了 logo + title + subtitle + button 布局，违反 AGENTS.md "prefer one authoritative implementation path per feature" 原则。

## 目标

将启动校验态、账号密码表单、登录中态合并到单一页面（`FireOnboardingViewController`），通过内部状态机切换中间内容区域，消除用户的手动跳转和重复点击。逻辑层（`FireSessionStore`、`FireWebViewLoginCoordinator`、`FireCaptchaLoginDialogController`、`FireAppViewModel` 登录编排方法）保持不动。

## 非目标

- 不改动 `FireSessionStore`、`FireWebViewLoginCoordinator`、`FireCaptchaLoginDialogController` 的任何 public API。
- 不改动 `FireAppViewModel` 的登录编排方法签名（`ensureCloudflareClearance`、`loginCoordinatorForDialog`、`classifyLoginResult`、`completeMinimalLogin`、`recoverLoginCloudflareChallenge`）。
- 不引入 SwiftUI（保持与现有 UIKit 启动页惯例一致）。

## 设计

### §1 状态模型

#### Root Coordinator 状态简化

`FireRootCoordinator.RootKind` 从三态简化为两态：

```swift
private enum RootKind: Equatable {
    case launch    // 合并原 .preheat + .onboarding
    case main
}
```

删除 `preheatComplete` 布尔标记。`updateRoot(animated:)` 由 `currentAuthenticationState` 直接驱动：未认证 → `.launch`，已认证 → `.main`。

#### Onboarding 页内部状态机

新增纯 UI 状态枚举，由 viewModel 的 `@Published` 派生：

```swift
enum FireOnboardingPhase: Equatable {
    case validating          // 正在校验登录态（loading）
    case credential          // 显示账号密码表单
    case loggingIn           // 登录请求中（表单 disabled + loading overlay）
}
```

派生规则（在 onboarding 页 `bindState` 里组合 viewModel 状态）：

| viewModel 状态组合 | phase |
|---|---|
| `isStartupValidationComplete == false` | `.validating` |
| `isStartupValidationComplete == true` 且未认证 | `.credential` |
| `isSyncingLoginSession == true` 或 captchaDialog 已 present | `.loggingIn` |

`.validating → .credential` 的切换不需要用户点击，纯响应式。

#### ⚠️ rev 2 修正：启动校验状态必须覆盖全链路

原 rev 1 用 `isBootstrappingSession` 派生 `.validating`，经代码核实**不成立**：

- `loadInitialState()`（`FireAppViewModel.swift:126-174`）只调用 `sessionStore.prepareStartupSession()` 并调度 `ensurePreloadedDataLoaded()`，**不调用 `determineLoginStateWithProbe()` 或 `applySession()`**。
- `isBootstrappingSession` 在 `finishInitialStateLoading(generation:)`（`FireAppViewModel.swift:1114`）翻为 false，这发生在 `prepareStartupSession` 返回时，**早于**登录态判定。
- 真正的登录态判定（`determineLoginStateWithProbe` + `applySession`）在 `completeStartupAfterPreheat()`（`FireAppViewModel.swift:176`），当前唯一驱动方是 `FirePreheatGateViewController.awaitPreloadedData()` 的 `onComplete` 回调 → `FireRootCoordinator.completePreheat()`（`FireRootCoordinator.swift:340`）。
- PreheatGate 实际等待两个阶段：`prepareStartupSession()` **和** `awaitPreloadedData()`（`FirePreheatGateViewController.swift:46-63`），rev 1 只覆盖前者。
- `9a6fe30` 后，`awaitPreloadedData()` 失败不再等同于启动校验失败：当前 PreheatGate 会读取 `sessionStore.snapshot().readiness`，只要 `canReadAuthenticatedApi == true` 或 `hasLoginCookie == true`，就保留本地会话并继续 `onComplete`，让 `completeStartupAfterPreheat()` 做最终登录态分流。

**修正方案**：新增 viewModel 状态与方法，把"校验完成"语义收口到 viewModel，由 onboarding VC 在 `viewDidLoad` 时触发。`performStartupValidation()` 是新的启动校验权威路径，自己执行 `prepareStartupSession()`，不依赖 `RootCoordinator.start()` 中的 `loadInitialState()` 先完成。

```swift
// FireAppViewModel 新增
@Published private(set) var isStartupValidationComplete = false
private var isStartupValidationInFlight = false

/// 替代 PreheatGate 的 prepareStartupSession + awaitPreloadedData
/// + completeStartupAfterPreheat 链路。
/// 由 onboarding VC 在 viewDidLoad 触发一次（冷启动 root == .launch 时）。
func performStartupValidation() async {
    guard !isStartupValidationComplete else { return }
    guard !isStartupValidationInFlight else { return }

    isStartupValidationInFlight = true
    defer {
        isStartupValidationInFlight = false
        isStartupValidationComplete = true
    }

    do {
        let sessionStore = try await sessionStoreValue()
        _ = try await sessionStore.prepareStartupSession()
        do {
            _ = try await sessionStore.awaitPreloadedData()
        } catch {
            let readiness = try? sessionStore.snapshot().readiness
            guard readiness?.canReadAuthenticatedApi == true
                || readiness?.hasLoginCookie == true
            else {
                throw error
            }
        }
        await completeStartupAfterPreheat()
    } catch {
        completeStartupAfterPreheatFailure(message: "网络异常，请重新登录")
    }
}
```

`isBootstrappingSession` 保留原语义（仅标记 `prepareStartupSession` 阶段），不再用于 onboarding phase 派生。onboarding phase 的 `.validating` 完全由 `isStartupValidationComplete == false` 决定。

`loadInitialState()` 不再是冷启动 root 的前置条件，避免 onboarding `viewDidLoad` 早于 `RootCoordinator.start()` 后半段执行时出现 validation 先于 prepare 的竞态。该方法保留给开发者工具/诊断入口继续使用；启动页只调用 `performStartupValidation()`。

#### `authPresentationState` 弃用（不删除）

`openLogin()` 和 `dismissAuthPresentation()` 保留方法定义，但 onboarding 页不再调用 `openLogin()`（表单内嵌）。`completeMinimalLogin` / `completeLogin` 成功时 `setAuthPresentationState(nil)` 不再驱动 modal dismiss——dismiss 责任迁移到 onboarding VC 的 `isSyncingLoginSession` 监听（见 §4 "登录成功后必须显式清理"）。`dismissAuthPresentation()` 的唯一调用方（login VC 关闭按钮）随 login VC 删除而消失，保留方法不删除以避免连锁改动。

### §2 页面结构与视图拆分

#### 整体布局

```
┌──────────────────────────────────┐
│  [dev tools]               (nav) │  保留现有开发者工具入口
├──────────────────────────────────┤
│            🔥 (logo)             │  Hero 区（固定，所有 phase 共享）
│            Fire                  │
│       LinuxDo 原生客户端          │
├──────────────────────────────────┤
│   ┌──────────────────────────┐   │
│   │   可替换的中间内容区       │   │  PhaseContainerView
│   │   (loading / 表单 / 空)   │   │
│   └──────────────────────────┘   │
├──────────────────────────────────┤
│   [error banner]  (有错才显示)    │  复用现有 FireOnboardingErrorBannerView
└──────────────────────────────────┘
```

#### 子视图拆分

为避免 `FireOnboardingViewController` 变胖，中间内容区拆成三个子 `UIView`：

1. **`FireOnboardingValidatingView`**（新建，约 40 行）
   - `UIActivityIndicatorView` + `UILabel`（"正在校验登录态…"）。
   - 从现有 `FireStartupOnboardingStatusView.showLoading` 抽取，纯展示。

2. **`FireOnboardingCredentialFormView`**（新建，约 280 行，从 `FireLoginViewController` 迁移）
   - 包含：用户名输入、密码输入、记住密码开关、登录按钮、忘记密码、其他方式登录。
   - 迁移自 `FireLoginViewController` 的 `setupCredentialFields` / `setupRememberPassword` / `setupLoginButton` / `setupForgotPassword` / `setupOtherMethods`。
   - **保留 `UIScrollView` + `contentView` 容器结构**（迁移自 `FireLoginViewController.setupScrollView` L128-148），以适配小屏键盘遮挡：`scrollView.keyboardDismissMode = .interactive`、`contentView.widthAnchor == scrollView.frameLayoutGuide.widthAnchor` 保证竖向滚动 + 横向不溢出。
   - 外层 onboarding VC 将品牌区固定在 safe area 顶部的紧凑头部，`phaseContainerView` 占满品牌下方到 safe area / 键盘上方的可用空间，避免 logo 居中挤压账号密码和其他登录方式。
   - 监听键盘 `willChangeFrame` / `willHide` 通知，外层移动表单容器到键盘上方，表单内部按本地坐标补充 `scrollView.contentInset.bottom`，并支持点空白、拖动、Return/Go、输入工具栏"完成"关闭键盘。
   - 不持有 viewModel，通过闭包回调：`onLoginTapped(identifier:password:remember:)`、`onForgotPassword`、`onOtherMethods`。
   - 暴露 `applySavedCredential(_:)` 用于回填已保存凭据。
   - 暴露 `setLoggingIn(_:)` 用于 disable/enable 表单。
   - **不包含 error banner**（见下方"error banner 职责统一"）。

3. **`FireOnboardingLoggingInView`**（新建，约 30 行）
   - 全屏半透明遮罩 + `UIActivityIndicatorView`（large）+ "正在登录…"。
   - 覆盖在 credential form 之上。

#### PhaseContainerView 切换逻辑

onboarding VC 持有 `phaseContainerView`，根据 phase 切换子视图：

| phase | container 内容 |
|---|---|
| `.validating` | `FireOnboardingValidatingView` |
| `.credential` | `FireOnboardingCredentialFormView` |
| `.loggingIn` | `FireOnboardingCredentialFormView`（disabled）+ `FireOnboardingLoggingInView`（overlay） |

切换用 `UIView.transition` crossDissolve，duration 0.22（与 root 切换一致）。

#### Hero 区复用

`FireOnboardingViewController.configureBrand()` 的 logo + title + subtitle 作为所有 phase 共享的固定头部，但布局必须靠近 safe area 顶部并保持紧凑，给 `.credential` phase 留出完整表单高度。

#### error banner 职责统一

合并前存在两个 error banner：

- `FireLoginViewController` 的顶部红色横幅（`setupErrorBanner`，自动 4 秒消失）——用于登录流程中的即时失败提示（如"密码错误"、"网络验证失败"）。
- `FireOnboardingViewController` 的底部 `FireOnboardingErrorBannerView`（可手动关闭）——用于 viewModel.errorMessage。

合并后**统一使用 onboarding VC 的 error banner**（底部、可关闭），但增加自动消失能力（4 秒）。`FireOnboardingCredentialFormView` 不内嵌 error banner，登录失败消息通过 onboarding VC 的 `showErrorBanner(_:)` 方法统一展示。这样消除重复 UI，且错误提示位置在所有 phase 一致。

### §3 Root Coordinator 改动

#### 删除的状态与方法

```swift
private var preheatComplete = false                              // 删除
private weak var preheatController: FirePreheatGateWaitingViewController?  // 删除
private var preheatSessionStoreTask: Task<Void, Never>?         // 删除
private weak var authController: UIViewController?               // 删除

private func makePreheatController() -> UIViewController         // 删除
private func preparePreheatSessionStoreIfNeeded()                // 删除
private func completePreheat()                                   // 删除
private func requestLoginAfterPreheatFailure(message: String?)   // 删除
private func syncAuthPresentation(_ state: FireAuthPresentationState?)  // 删除
```

所有删除的方法和状态都只在 `FireRootCoordinator` 内部被调用，无外部依赖。

#### `updateRoot` 简化

```swift
private func updateRoot(animated: Bool) {
    let nextKind: RootKind = currentAuthenticationState ? .main : .launch
    guard rootKind != nextKind else { return }
    rootKind = nextKind
    let controller: UIViewController
    switch nextKind {
    case .launch:
        controller = makeOnboardingController()
    case .main:
        controller = makeMainTabBarController()
    }
    // 现有 window transition 逻辑不变
}
```

#### `start()` 简化

```swift
func start() {
    guard let window else { return }
    Self.activeCoordinator = self
    bindState()
    updatePreferredAppearance()
    updateRoot(animated: false)
    window.makeKeyAndVisible()
    homeFeedStore.setSceneActive(false)
    FireAPMManager.shared.setScenePhase(ScenePhaseLabel.inactive.rawValue)
    updateTopLevelAPMRoute()
    // 删除 viewModel.loadInitialState()
    // 删除 preparePreheatSessionStoreIfNeeded()
}
```

`viewModel.loadInitialState()` 也从 `start()` 删除。统一启动页创建后由 `FireOnboardingViewController.viewDidLoad` 调用 `viewModel.performStartupValidation()`，避免 RootCoordinator 和 onboarding VC 同时驱动 session restore / preload。

#### `bindState` 简化

删除两个 binding：

- `viewModel.$authPresentationState` 的 `syncAuthPresentation` binding（登录表单不再 modal present）。
- `viewModel.$session` 的 `handleAuthenticationChange` **保留**（这是 `.launch → .main` 的唯一驱动）。

`syncTopicPresentation` 里的 `guard authController == nil` 守卫（`FireRootCoordinator.swift:381`）删除。

### §4 Onboarding VC 登录编排

#### 迁移自 `FireLoginViewController` 的方法

以下方法原样迁移到 `FireOnboardingViewController`（逻辑不变，宿主变化）：

- `performLogin()` — `ensureCloudflareClearance` → `loginCoordinatorForDialog` → `presentCaptchaDialog`
- `presentCaptchaDialog(loginCoordinator:)` — 构造 `FireCaptchaLoginDialogController`，设置 `classifyResult` 回调
- `dialogResult(from:)` / `handleDialogResult(_:)` — success / needSecondFactor / retryCloudflare / failure 分发
- `completeLoginFromDialog()` — `viewModel.completeMinimalLogin(...)`
- `showSecondFactorPrompt(requirement:)` — `UIAlertController` 6 位验证码
- `recoverCloudflare()` — `cfRetryUsed` 单次重试
- `presentWebViewBrowser(url:)` — 忘记密码 / 其他方式登录的 WKWebView 兜底
- `setLoginLoading(_:)` / `showErrorBanner(_:)` / `hideErrorBanner()` / `dismissCaptchaDialog()`

所有 viewModel 调用的方法签名不变。

#### `FireCaptchaLoginDialogController` 的 present 宿主变化

现在由 onboarding VC present（而非 login VC）。`captchaDialog` 持有变量、`present(dialog, animated: true)` 调用点不变。dialog 内部逻辑（hCaptcha、JS login、cookie 提取）零改动。

#### 表单触发流程

```
onboarding phase == .credential
  → 用户在 FireOnboardingCredentialFormView 填账号密码
  → 点击登录按钮 → formView.onLoginTapped(identifier:password:remember:) 闭包
  → onboarding VC:
      pendingIdentifier = identifier
      pendingPassword = password
      pendingRememberCredential = remember
      cfRetryUsed = false
      hasShownSecondFactor = false
      phase = .loggingIn
      Task { await performLogin() }
```

`.loggingIn` 状态下 `FireOnboardingLoggingInView` overlay 显示，表单 disabled。

#### ⚠️ rev 2 修正：saved credential 必须显式加载

原 rev 1 说迁移 `$savedLoginCredential` 订阅即可回填表单。经代码核实**不成立**：

`loadSavedCredential()` 只在 `openLogin()`（`FireAppViewModel.swift:236-244`）的 Task 里调用。`$savedLoginCredential` 订阅本身不触发加载，只在 viewModel 已发布值时回调。onboarding 页不调用 `openLogin()`，则 `savedLoginCredential` 永远为初始值 `nil`，表单无法回填。

**修正方案**：从 `openLogin()` 抽出登录表单准备逻辑为独立方法，onboarding VC 在进入 `.credential` phase 时调用：

```swift
// FireAppViewModel 新增（从 openLogin L236-244 抽取）
func prepareLoginForm() async {
    do {
        let sessionStore = try await sessionStoreValue()
        savedLoginCredential = try await sessionStore.loadSavedCredential()
        _ = try await loginCoordinatorValue()   // 预热 coordinator
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

onboarding VC 的 phase 派生逻辑里，当 `isStartupValidationComplete == true` 且未认证（即将进入或已在 `.credential`）时触发一次：

```swift
private func applyPhase(_ next: FireOnboardingPhase) {
    if next == .credential, phase != .credential {
        Task { await viewModel.prepareLoginForm() }
    }
    phase = next
    // ...container view 切换
}
```

`openLogin()` 保留供其他入口（开发者工具等，实现阶段确认 call site），但其内部的 credential 加载逻辑改为调用 `prepareLoginForm()` 以避免重复。

#### errorMessage 绑定

现有 `FireOnboardingView.swift:113-118` 的 `viewModel.$errorMessage` 订阅保留。当 `phase == .loggingIn` 时收到 errorMessage，走与 `handleDialogResult(.failure)` 相同的 dismiss + showErrorBanner 路径（迁移自 `FireLoginViewController.swift:95-105`），并让 phase 回到 `.credential`。

#### ⚠️ rev 2 修正：登录成功后必须显式清理 captcha dialog 与 loggingIn phase

原 rev 1 称 `setAuthPresentationState(nil)` 变成 no-op "无害"。经代码核实**有害**：

当前成功路径 `completeMinimalLogin`（`FireAppViewModel.swift:324`）调用 `setAuthPresentationState(nil)`，RootCoordinator 的 `syncAuthPresentation(nil)`（`FireRootCoordinator.swift:368-377`）负责 `authController.dismiss(animated:)`，**这个 dismiss 同时移除了 login VC 及其 present 的 captcha dialog**。

删除 `syncAuthPresentation` binding 后，onboarding 页成为 captcha dialog 的 present 宿主。成功路径不再有任何代码 dismiss dialog 或退出 `.loggingIn` phase。

**修正方案**：在 onboarding VC 监听 `viewModel.$isSyncingLoginSession` 的 false 翻转，作为登录完成的权威信号：

```swift
viewModel.$isSyncingLoginSession
    .receive(on: RunLoop.main)
    .sink { [weak self] isSyncing in
        guard let self else { return }
        guard !isSyncing, self.phase == .loggingIn else { return }
        self.setLoginLoading(false)
        self.dismissCaptchaDialog()     // 显式关闭 hCaptcha dialog
        // phase 无需手动复位：root 即将切到 .main，onboarding VC 随之销毁。
        // 若登录失败（未切 root），completeMinimalLogin 的 catch 分支会
        // 通过 errorMessage 绑定走 dismiss + showErrorBanner 路径。
    }
    .store(in: &cancellables)
```

`dismissCaptchaDialog()` 迁移自 `FireLoginViewController`，负责 `captchaDialog?.dismiss(animated:)` + 置空持有变量。

登录失败路径（未切 root）由上文 errorMessage 绑定处理：`setLoginLoading(false)` + `dismissCaptchaDialog()` + `showErrorBanner(message)`，phase 回到 `.credential`。

### §5 ViewModel 改动

> ⚠️ rev 3：原 rev 1 称"不新增 `@Published`"。经核实需新增启动校验完成状态、single-flight guard 与两个方法，否则 preheat 链路断裂或产生时序竞态（见 §1 修正说明）。

#### 新增的状态与方法

| 新增 | 用途 |
|---|---|
| `@Published private(set) var isStartupValidationComplete` | onboarding phase `.validating` ↔ `.credential` 的权威派生源（替代语义不符的 `isBootstrappingSession`） |
| `private var isStartupValidationInFlight` | 保证 startup validation single-flight，避免重复 `viewDidLoad` / 重渲染触发并发校验 |
| `func performStartupValidation() async` | 替代 PreheatGate 的 `prepareStartupSession + awaitPreloadedData + completeStartupAfterPreheat` 链路，由 onboarding VC viewDidLoad 触发 |
| `func prepareLoginForm() async` | 从 `openLogin()` 抽取，负责 `loadSavedCredential` + coordinator 预热，由 onboarding VC 进入 `.credential` phase 时触发 |

`openLogin()` 的内部 credential 加载逻辑改为调用 `prepareLoginForm()` 以避免重复。

#### 不改动的部分

- `FireSessionStore` 全部 public API（含 `awaitPreloadedData`）
- `FireWebViewLoginCoordinator` 全部 public API
- `FireCaptchaLoginDialogController` 全部 API
- `loadInitialState()` 的方法签名和核心逻辑不变，但不再由 `RootCoordinator.start()` 驱动冷启动；保留给 Developer Tools / 诊断重新加载入口。
- `completeStartupAfterPreheat()` / `completeStartupAfterPreheatFailure()` 的**方法签名和核心逻辑**不变（`performStartupValidation` 内部调用它们，不重写）
- 所有登录编排方法签名

#### `authPresentationState` 弃用

`openLogin()` 保留但 onboarding 页不再调用（credential 加载逻辑已抽出到 `prepareLoginForm()`）。`dismissAuthPresentation()` 保留但无调用方（login VC 删除后）。这两个方法标记为后续清理，不在本次删除。

#### call site 影响清单

| 被删除的调用方 | 被调用的方法 | 处理 |
|---|---|---|
| `FireRootCoordinator.requestLoginAfterPreheatFailure` | `openLogin()` | 删除调用方 |
| `FireOnboardingView` 登录按钮 | `openLogin()` | 改为直接切到 `.credential` phase |
| `FireLoginViewController.closeTapped` | `dismissAuthPresentation()` | 删除调用方 |
| `FireRootCoordinator.syncAuthPresentation` | `FireLoginViewController` 构造 | 删除整个方法 |

### §6 迁移步骤与验证

每个 Step 是独立 commit，可独立编译验证。

#### Step 1 — 新建子视图（纯增量）

新建 `FireOnboardingValidatingView`、`FireOnboardingCredentialFormView`、`FireOnboardingLoggingInView`。内容从现有文件抽取，先不接入 onboarding VC。

验证：`xcodebuild` 编译通过。

#### Step 2 — Onboarding VC 接入 phase 状态机 + viewModel 新增

先在 `FireAppViewModel` 新增 `isStartupValidationComplete` / `isStartupValidationInFlight` / `performStartupValidation()` / `prepareLoginForm()`（见 §5）。再在 `FireOnboardingViewController` 加 `phase` 属性 + `bindState` 派生逻辑（用 `isStartupValidationComplete` 而非 `isBootstrappingSession`）。中间区域换成 `phaseContainerView`，挂载 Step 1 的子视图。hero 区和 error banner 保留。onboarding VC 的 `viewDidLoad` 触发 `Task { await viewModel.performStartupValidation() }`，`applyPhase(.credential)` 时触发 `viewModel.prepareLoginForm()`。迁移 `savedLoginCredential` / `errorMessage` / `isSyncingLoginSession` 绑定。

验证：onboarding 页能显示 loading 态，校验结束后能切到表单且表单有已保存凭据回填；构造 `awaitPreloadedData()` 失败但 snapshot readiness 仍有 `canReadAuthenticatedApi` 或 `hasLoginCookie` 的场景时，不能直接显示启动失败，而应继续执行 `completeStartupAfterPreheat()`，再由 `determineLoginStateWithProbe()` 决定进入 `.main` 还是留在 `.credential`。只有本次 preload 明确拿到 fresh `currentUser` 时才允许跳过 probe；持久化 session 里的旧 `currentUser` 不能单独作为冷启动登录态凭据。

#### Step 3 — 迁移登录编排逻辑

把 `performLogin` / `presentCaptchaDialog` / `handleDialogResult` / `showSecondFactorPrompt` / `recoverCloudflare` / `presentWebViewBrowser` / `setLoginLoading` / `showErrorBanner` / `hideErrorBanner` / `dismissCaptchaDialog` 迁移到 onboarding VC。`FireOnboardingCredentialFormView` 的 `onLoginTapped` 闭包接到这些方法。

验证：onboarding 页的 `.credential` 态能完整跑通登录流程（hCaptcha → second factor → cloudflare retry → 成功）。

#### Step 4 — Root Coordinator 简化

删除 `preheatComplete` / `preheatController` / `preheatSessionStoreTask` / `authController`。删除 `makePreheatController` / `preparePreheatSessionStoreIfNeeded` / `completePreheat` / `requestLoginAfterPreheatFailure` / `syncAuthPresentation`。`RootKind` 改为 `.launch` / `.main`。`bindState` 删除 `authPresentationState` binding。`start()` 删除 `viewModel.loadInitialState()` 和 preheat 调用。

验证：冷启动直接进 `.launch`，onboarding `viewDidLoad` 后只启动一条 validation task，校验成功自动切 `.main`，不可恢复校验失败自动切表单。

#### Step 5 — 删除废弃文件

删除 `App/Startup/FirePreheatGateWaitingViewController.swift`、`App/Startup/FirePreheatGateViewController.swift`、`App/Views/Other/FireLoginViewController.swift`。

验证：`xcodebuild` 编译通过，无残留引用。

#### Step 6 — 文档同步

> ⚠️ rev 2：扩大同步范围。原 rev 1 只提 architecture 文档。

删除 `FireLoginViewController` / PreheatGate 后，以下文档都引用了它们，必须一并更新：

- `docs/architecture/fire-native-architecture.md`：
  - L253 `FireRootCoordinator.swift` 注释（删 "preheat"、保留 "root/auth/route"）。
  - L307 `FireLoginViewController.swift` 条目删除，改为 onboarding 合并后的条目。
  - L1000 登录/Cloudflare auth 段落，把 `FireLoginViewController` 替换为 onboarding VC 内嵌表单的描述。
- `native/ios-app/README.md`：
  - L77 `App/Views/Other/FireLoginViewController.swift` 文件清单条目删除，补 `FireOnboardingCredentialFormView` 等新文件。
  - L93 RootCoordinator 职责描述（删 "auth modal presentation"）。
  - L103 onboarding/PreheatGate 段落改为统一启动页描述。
  - L274-275 UX note 改为反映单页多 phase 体验。
- 全仓 grep `FirePreheatGate`、`FireLoginViewController`、`authPresentationState`、`PreheatGate`，确认无其他残留引用。

#### 验证命令

每个 Step 完成后：

```bash
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire \
    -destination 'generic/platform=iOS Simulator' build
```

Step 2-4 还应跑现有单元测试：

```bash
xcodebuild test -project native/ios-app/Fire.xcodeproj -scheme Fire \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

特别关注 `FireSessionStoreTests`、`FireAppRouteTests`、`FireLoginScriptsTests`（预计不受影响，因为逻辑层未动）。

#### 风险与回退

- **主要风险**（rev 3 更新）：`completeStartupAfterPreheat()` 失去 RootCoordinator 驱动方，需由 `performStartupValidation()` 接管；若遗漏 `prepareStartupSession()`、`awaitPreloadedData()` 的可恢复失败分支，或 `determineLoginStateWithProbe()`，校验链路会断裂或把仍需判定的本地会话直接推到启动失败/登录表单。**缓解**：Step 2 的验证项必须确认冷启动能走完 `prepareStartupSession → awaitPreloadedData → determineLoginStateWithProbe → applySession` 全链路，并覆盖 `awaitPreloadedData` 失败但 snapshot readiness 仍可恢复的场景。
- **次要风险**：登录成功后 captcha dialog 不 dismiss。**缓解**：Step 3 验证项必须覆盖"成功登录 → dialog 消失 → root 切 .main"完整路径。
- **回退**：每个 Step 是独立 commit，任何一步出问题可 revert 单步。

## 文件变更摘要

### 新建

| 文件 | 内容 | 行数估算 |
|---|---|---|
| `App/Startup/FireOnboardingValidatingView.swift` | 校验中 loading 视图 | ~40 |
| `App/Startup/FireOnboardingCredentialFormView.swift` | 账号密码表单（含 scrollView + 键盘适配，从 login VC 迁移） | ~280 |
| `App/Startup/FireOnboardingLoggingInView.swift` | 登录中 overlay 视图 | ~30 |

### 修改

| 文件 | 改动 |
|---|---|
| `App/ViewModels/FireAppViewModel.swift` | 新增 `isStartupValidationComplete` / `isStartupValidationInFlight` / `performStartupValidation()` / `prepareLoginForm()`（rev 3） |
| `App/Views/Other/FireOnboardingView.swift` | 接入 phase 状态机、phaseContainerView、登录编排逻辑迁移、`performStartupValidation` 触发 |
| `App/Core/FireRootCoordinator.swift` | RootKind 两态化，删除 preheat/auth presentation 路径 |

### 删除

| 文件 | 行数 |
|---|---|
| `App/Startup/FirePreheatGateWaitingViewController.swift` | 72 |
| `App/Startup/FirePreheatGateViewController.swift`（含 `FireStartupOnboardingStatusView`） | 221 |
| `App/Views/Other/FireLoginViewController.swift` | 622 |

净删除约 900 行，新增约 370 行（含 onboarding VC 增量约 200 行、viewModel 增量约 30 行、表单 view 含 scrollView 增量约 30 行）。
