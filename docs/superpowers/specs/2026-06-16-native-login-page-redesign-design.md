# Native Login Page Redesign

**Date:** 2026-06-16
**Status:** Draft (pending user spec review)
**Related:** `references/fluxdo/` login flow, `docs/knowledge/` login protocol

## Problem Statement

当前 Fire iOS 的登录流程存在时序错误和架构问题：

1. **时序错误**：用户打开登录页后立即触发 Cloudflare challenge + 加载 hCaptcha widget，此时用户尚未输入账号密码。正确流程应是用户先输入凭据、点击登录后再触发验证。
2. **架构耦合**：`FireLoginWebView.swift`（816 行）将原生表单 UI、WebView 配置、hCaptcha 渲染、登录请求、CF 协调全部塞在一个 UIViewController 中，职责混乱。
3. **交互体验差**：社交登录（Google/Apple/浏览器）没有入口；没有"记住密码"勾选；错误用 UIAlertController 弹窗打断体验。

fluxdo 参考实现（`references/fluxdo/lib/pages/login_page.dart` + `lib/widgets/auth/webview_login_dialog.dart`）已经解决了这些问题：原生表单收集凭据，点登录后按需弹 mini WebView dialog 做 hCaptcha + 请求。

## Design Decisions

| 决策 | 选择 | 理由 |
|------|------|------|
| 技术栈 | UIKit (programmatic) | 与现有 iOS 代码一致，不引入 SwiftUI 桥接成本 |
| WebView 交互模式 | Dialog/Sheet 弹出 | 对齐 fluxdo，点登录后才弹出，不占用登录页空间 |
| CF 验证时机 | 点登录后按需触发 | 不再页面打开就验证，减少无意义网络请求 |
| 记住密码 | 复用现有 Keychain 方案 | `FireSavedCredential` + `FireAuthCookieKeychainStore` 已完备 |
| 社交登录图标 | 先展示，点击走完整 WebView | linux.do OAuth 由服务端处理，原生无法替代 |
| 登录成功 dismiss | dismiss 整个 modal | 单次 dismiss 回到主界面 |

## Architecture

### 组件拆分

```
FireRootCoordinator
  └─ present FireLoginViewController (full-screen modal)
       │  纯原生 UIKit VC，不含 WebView
       │
       ├─ 用户点"登录" →
       │    1. viewModel.performLogin(identifier, password)
       │    2. 检查 cf_clearance（按需触发 CF challenge）
       │    3. present FireCaptchaLoginDialogController (form sheet)
       │         │  含 WKWebView
       │         │  - 渲染 hCaptcha widget
       │         │  - 用户通过 hCaptcha → JS __fireLogin(id,pwd,token)
       │         │  - 结果通过 messageHandler 回调
       │         └─ onResult: success / needSecondFactor / retryCloudflare / failure
       │
       ├─ 社交图标点击 →
       │    present FireWebViewBrowserViewController (full WebView, linux.do/login)
       │
       └─ 登录成功 →
            dismiss 整个 modal
```

### 原生登录页布局 (FireLoginViewController)

```
┌─────────────────────────────┐
│                             │
│         [Fire Logo]         │  品牌图标，垂直偏上
│      "Fire × LinuxDo"       │  副标题
│                             │
│  ┌───────────────────────┐  │
│  │ 用户名或邮箱           │  │  UITextField, .username
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 密码                  │  │  UITextField, isSecureTextEntry, .password
│  └───────────────────────┘  │
│                             │
│  [✓] 记住账号密码           │  UIButton checkbox
│                             │
│  ┌───────────────────────┐  │
│  │        登 录          │  │  主按钮，双字段非空时 enable
│  └───────────────────────┘  │
│                             │
│  ─────── 其他方式登录 ─────  │  分割线
│                             │
│   [Google]  [Apple]  [🌐]  │  社交登录图标
│                             │
└─────────────────────────────┘
```

**数据绑定：**
- 复用 `viewModel.$savedLoginCredential` → 有保存的凭据时自动填充，默认勾选"记住密码"
- 登录按钮 `isEnabled` 绑定两个字段都非空
- 错误展示用内联 error banner（不用 UIAlertController）

### hCaptcha Dialog (FireCaptchaLoginDialogController)

```
┌─────────────────────────────┐
│  安全验证              [×]  │  标题栏
├─────────────────────────────┤
│                             │
│    [ hCaptcha Widget ]      │  WKWebView 渲染
│                             │
├─────────────────────────────┤
│  [状态文字 / 错误信息]      │  底部状态区
└─────────────────────────────┘
```

**生命周期：**
```
init(identifier, password, onResult, onCancel)
  ├─ viewDidLoad: 配置 WKWebView → primeCookies → loadHTMLString(minimalLoginHTML)
  ├─ hCaptcha 通过: 自动调用 __fireLogin(id, pwd, token)
  │    → JS: fetch /session/csrf → POST /hcaptcha/create → POST /session.json
  ├─ login_result messageHandler: onResult(result)
  └─ 用户关闭: onCancel()

retryWithSecondFactor(token)
  └─ 同一存活 WebView 内重跑 __fireLogin(hcaptchaToken=nil, secondFactorToken=token)
```

### 登录时序（修正后）

```
[1] 点"登录 LinuxDo" → openLogin() → present FireLoginViewController
    （无网络请求，无 WebView）

[2] 登录页加载 → 自动填充 saved credential（纯本地）

[3] 用户填写凭据，点"登录"
    └─ viewModel.performLogin(identifier, password)
         ├─ [3a] 检查 cf_clearance
         │    ├─ 有 → 进入 [3b]
         │    └─ 无 → completeLoginCloudflareChallenge()
         │         ├─ 成功 → primeCookies → [3b]
         │         └─ 失败 → 登录页报错
         ├─ [3b] present FireCaptchaLoginDialogController
         │    └─ hCaptcha → __fireLogin → session.json → onResult
         └─ [3c] 处理结果
              ├─ success → completeMinimalLogin → dismiss all
              ├─ needSecondFactor → 登录页弹 2FA → dialog.retryWithSecondFactor(code)
              ├─ retryCloudflare → recoverCloudflareAndRetry (一次)
              └─ failure → 登录页显示错误
```

### 社交登录（完整 WebView 兜底）

三个图标（Google / Apple / 浏览器）点击后统一 present `FireWebViewBrowserViewController`，加载 `https://linux.do/login`。Discourse 服务端处理 OAuth/Passkey/注册。

登录成功检测（对齐 fluxdo `WebViewLoginPage`）：
- 监听 WKWebView cookie store 变化
- 检测 `_t` cookie（有效 auth token）→ 触发 finalize
- 或注入 JS 检查 `meta[name="current-username"]`
- 成功后 dismiss WebView → dismiss 登录页 → finalize 路径

### Cookie 流转

```
Keychain/Session → ViewModel → primeCookies into Dialog's WebView
                                    ↓
                              hCaptcha + session.json
                                    ↓
                          Dialog onResult → ViewModel
                                    ↓
                    completeJsLogin: capture cookies from WebView
                                    ↓
                    finalizeLoginFromWebView → Rust session
                                    ↓
                    saveLoginCredential → Keychain (如果勾选记住密码)
```

## Error Handling

| 错误类型 | 来源 | 展示位置 | 行为 |
|---------|------|---------|------|
| 账号/密码错误 | `invalid_credentials` | 登录页内联 error banner | 恢复按钮，清空密码框 |
| CF challenge 失败 | CF 验证超时/拒绝 | 登录页内联 error banner | 提供"重试" |
| hCaptcha 失败/过期 | hCaptcha widget | dialog 底部状态区 | hCaptcha auto reset |
| 需要 2FA | `second_factor` | 登录页弹 native 2FA 输入框 | 输入验证码 → dialog 重试 |
| 2FA 错误 | `invalid_second_factor` | 2FA 输入框下方错误提示 | 清空验证码 |
| 账号未激活 | `not_activated` | 登录页内联 error banner | 提示去邮箱激活 |
| 账号未审批 | `not_approved` | 登录页内联 error banner | 提示等待审批 |
| 网络超时 | fetch 超时 | dialog 底部状态区 | 提供"重试" |
| CSRF 失效 | BAD CSRF | 自动 CF 重试一次 | `recoverCloudflareAndRetry` |

**Dialog dismiss 边界：**
- 登录成功 → dismiss dialog → dismiss 整个 modal
- 登录失败 → dialog 保持显示错误，用户手动关闭后登录页恢复按钮
- 用户关闭 dialog → 取消 loading，登录页恢复初始状态
- CF 验证期间用户可取消，回到登录页

**已有防护保留：**
- `cfRetryUsed`（CF 重试一次）防止无限重试
- `classifyWebViewLoginResult`（Rust 分类）不变
- `completeJsLogin` cookie 捕获不变
- `finalizeLoginFromWebView` Rust finalize 不变

## Implementation Phases

### Phase 1：原生登录页 UI 搭建（纯 UI，登录按钮暂不接通）

新建 `FireLoginViewController.swift` 搭建全部原生 UI（Logo、输入框、记住密码、社交图标、登录按钮）。此阶段登录按钮点击暂不触发实际登录流程（可显示"即将支持"提示或 disabled），社交图标也暂不接通。`FireRootCoordinator` 改为 present 新 VC。旧 `FireLoginWebView.swift` 保留不删，仅从 coordinator 路径上摘除。Phase 2 接通登录流程后删除。

| 文件 | 操作 |
|------|------|
| 新建 `FireLoginViewController.swift` | Logo + 输入框 + 记住密码 + 社交图标 + 登录按钮（纯 UI，按钮暂不触发登录） |
| 修改 `FireRootCoordinator.swift` | present `FireLoginViewController` 替代旧 VC |
| 保留 `FireLoginWebView.swift`（不从路径引用） | Phase 2 删除 |

### Phase 2：接通登录流程 + 拆分 hCaptcha Dialog + 修正时序

新建 `FireCaptchaLoginDialogController`。`FireAppViewModel` 新增 `performLogin(identifier:password:)` 统筹 CF 检查 + dialog present + 结果处理。`FireLoginViewController` 登录按钮接通到 `performLogin`。修正后整个时序为按需触发。删除旧 `FireLoginWebView.swift`。

| 文件 | 操作 |
|------|------|
| 新建 `FireCaptchaLoginDialogController.swift` | hCaptcha WebView + `__fireLogin` + 结果回调 |
| 修改 `FireLoginViewController.swift` | 登录按钮接通 `performLogin` → present dialog |
| 修改 `FireAppViewModel.swift` | `openLogin()` 简化移除预加载；新增 `performLogin(identifier:password:)` |
| 删除 `FireLoginWebView.swift` | 旧 VC 移除 |

### Phase 2：拆分 hCaptcha Dialog + 修正时序

新建 `FireCaptchaLoginDialogController`，WebView hCaptcha + 登录请求剥离到 dialog。修正时序为按需触发。

| 文件 | 操作 |
|------|------|
| 新建 `FireCaptchaLoginDialogController.swift` | hCaptcha WebView + `__fireLogin` + 结果回调 |
| 修改 `FireLoginViewController.swift` | 点登录 → `performLogin` → present dialog |
| 修改 `FireAppViewModel.swift` | 新增 `performLogin(identifier:password:)`，CF 检查 + dialog 协调 |
| 删除 `FireLoginWebView.swift` | 旧 VC 移除 |

### Phase 3：社交登录 WebView 兜底

底部图标完整 WebView 登录路径。

| 文件 | 操作 |
|------|------|
| 新建/复用 `FireWebViewBrowserViewController.swift` | 完整 WebView，linux.do/login |
| 修改 `FireLoginViewController.swift` | 图标点击 → present browser VC |
| 修改 `FireAppViewModel.swift` | 新增 `openFullWebViewLogin(method:)` |

### Phase 4：错误处理打磨

内联 error banner 替代 UIAlertController，2FA 弹窗优化，dialog 错误状态完善。

| 文件 | 操作 |
|------|------|
| 修改 `FireLoginViewController.swift` | 内联 error banner 组件 |
| 修改 `FireCaptchaLoginDialogController.swift` | 底部状态区错误展示 + 重试 |

## File Change Summary

| 文件路径 | 操作 | 阶段 |
|---------|------|------|
| `native/ios-app/App/Views/Other/FireLoginViewController.swift` | 新建 | P1 (UI), P2 (接通), P3 (图标), P4 (error banner) |
| `native/ios-app/App/Views/Other/FireCaptchaLoginDialogController.swift` | 新建 | P2 |
| `native/ios-app/App/Views/Other/FireWebViewBrowserViewController.swift` | 新建/复用 | P3 |
| `native/ios-app/App/Views/Other/FireLoginWebView.swift` | 删除 | P2 |
| `native/ios-app/App/ViewModels/FireAppViewModel.swift` | 修改 | P2 (performLogin), P3 (openFullWebViewLogin) |
| `native/ios-app/App/Core/FireRootCoordinator.swift` | 修改 | P1 |

## Preserved Boundaries (不变)

以下逻辑完全保留不动，确保 Rust 侧和 finalize 链路稳定：

- UniFFI boundary：`finalizeLoginFromWebView`、`classifyWebviewLoginResult`
- Cookie 捕获：`FireWebViewLoginCoordinator.completeJsLogin`
- Keychain 凭据存储：`FireSavedCredential`、`FireAuthCookieKeychainStore`
- Minimal login HTML/JS：`FireLoginScripts.minimalLoginHTML`、`__fireLogin`
- CF challenge coordinator：`FireCloudflareChallengeCoordinator`
- Session store：`FireSessionStore`

## Reference

- fluxdo 登录页：`references/fluxdo/lib/pages/login_page.dart:138-213`
- fluxdo hCaptcha dialog：`references/fluxdo/lib/widgets/auth/webview_login_dialog.dart`
- fluxdo 原生表单：`references/fluxdo/lib/widgets/auth/login_form.dart`
- fluxdo WebView 兜底：`references/fluxdo/lib/pages/webview_login_page.dart`
- Fire 当前登录 VC（待替换）：`native/ios-app/App/Views/Other/FireLoginWebView.swift`
- Fire minimal login 脚本：`native/ios-app/Sources/FireAppSession/FireWebViewBrowserProfile.swift:193-408`
- Fire 登录协调器：`native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift`
