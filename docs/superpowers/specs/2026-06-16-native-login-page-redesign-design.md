# Native Login Page Redesign

**Date:** 2026-06-16
**Status:** Draft (pending user spec review, revision 2)
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
| 记住密码 | 复用现有 Keychain 方案 + checkbox 贯穿 API | `FireSavedCredential` + `FireAuthCookieKeychainStore` 已完备；`rememberCredential` 参数一路传到 finalization |
| 社交登录入口 | 一个"其他方式登录"按钮 + 忘记密码链接 | 对齐 fluxdo：单按钮打开完整 WebView 加载 `/login`；忘记密码走 `/password-reset` |
| 登录成功 dismiss | dismiss 整个 modal | 单次 dismiss 回到主界面 |
| ViewModel 职责边界 | ViewModel 只暴露 async 能力，VC 负责 present dialog | 对齐 fluxdo 页面层拉起 dialog 的模式，贴合现有 Fire 边界 |

## Architecture

### 组件拆分

```
FireRootCoordinator
  └─ present FireLoginViewController (full-screen modal)
       │  纯原生 UIKit VC，不含 WebView
       │  负责：UI 展示、present/dismiss dialog、present 完整 WebView 兜底
       │
       ├─ 用户点"登录" →
       │    FireLoginViewController.performLogin(identifier, password, rememberCredential)
       │      │
       │      ├─ [VC 层] await viewModel.ensureCloudflareClearance()
       │      │         （ViewModel async 能力：检查/触发 CF，返回成功/失败）
       │      │
       │      ├─ [VC 层] await viewModel.primeCookiesForLogin()
       │      │         （ViewModel async 能力：读取 canonical cookies 返回给 VC）
       │      │
       │      ├─ [VC 层] present FireCaptchaLoginDialogController (form sheet)
       │      │         │  含 WKWebView
       │      │         │  - 渲染 hCaptcha widget
       │      │         │  - 用户通过 hCaptcha → JS __fireLogin(id,pwd,token)
       │      │         │  - 结果通过 closure onResult 回调
       │      │         │  - WKWebView 在 dialog 存活期间保持 alive
       │      │         │
       │      │         └─ onResult(dialog) → VC 处理:
       │      │              ├─ success: await viewModel.completeMinimalLogin(
       │      │              │     from: dialog.webView,  ← LIVE WebView 传入
       │      │              │     identifier:, password:,
       │      │              │     rememberCredential:  ← 贯穿勾选状态
       │      │              │  ) → dismiss dialog → dismiss 登录 modal
       │      │              │
       │      │              ├─ needSecondFactor(requirement):
       │      │              │     登录页弹 native 2FA 输入框
       │      │              │     → dialog.retryWithSecondFactor(code)
       │      │              │     （同一存活 WebView 重试）
       │      │              │
       │      │              ├─ retryCloudflare:
       │      │              │     await viewModel.recoverCloudflareAndRetry()
       │      │              │     → 重新 prime + dialog 重新执行 __fireLogin
       │      │              │     （限一次，cfRetryUsed）
       │      │              │
       │      │              └─ failure(kind): 登录页显示错误
       │      │
       │      └─ [失败/取消] 恢复登录页初始状态
       │
       ├─ "其他方式登录" 按钮 →
       │    present FireWebViewBrowserViewController (full WebView, linux.do/login)
       │
       ├─ "忘记密码?" 链接 →
       │    present FireWebViewBrowserViewController (full WebView, linux.do/password-reset)
       │
       └─ 登录成功 →
            dismiss 整个 modal
```

### 职责边界（ViewModel vs VC）

对齐 fluxdo 的分工（页面层 `_handleSubmit` 拉起 dialog，service 只做解析/收口）：

| 职责 | 归属 | 说明 |
|------|------|------|
| UI 展示与用户交互 | `FireLoginViewController` | 原生表单、error banner、社交入口 |
| present/dismiss dialog | `FireLoginViewController` | VC 直接 present，不走 ViewModel |
| present/dismiss 完整 WebView | `FireLoginViewController` | "其他方式登录" / "忘记密码" |
| 2FA 输入框展示 | `FireLoginViewController` | native UIAlertController/自定义弹窗 |
| 检查/触发 CF challenge | `FireAppViewModel` (async) | `ensureCloudflareClearance()` → `Bool`/`Error` |
| 读取 canonical cookies | `FireAppViewModel` (async) | `primeCookiesForLogin()` → cookie payload |
| 分类登录结果 | `FireAppViewModel` (async) | `classifyWebViewLoginResult()` → `WebViewLoginDecisionState` |
| Cookie 捕获 + finalize | `FireAppViewModel` (async) | `completeMinimalLogin(from:webView:...)` 需要 live WKWebView |
| CF 重试恢复 | `FireAppViewModel` (async) | `recoverCloudflareAndRetry()` |
| 保存/加载凭据 | `FireAppViewModel` (async) | `saveLoginCredential`/`loadSavedCredential` |

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
│         忘记密码?           │  文字链接，→ WebView /password-reset
│                             │
│  ─────── 或 ────────        │  分割线
│                             │
│  ┌───────────────────────┐  │
│  │ 其他方式登录           │  │  OutlinedButton → WebView /login
│  │ (OAuth / Passkey)     │  │  (对齐 fluxdo 单按钮设计)
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**关于 Google/Apple 独立图标：** fluxdo 使用一个统一的"其他方式登录"按钮而非三个独立图标。linux.do 的 OAuth/Passkey 全部在 Discourse `/login` 页面由服务端处理，原生无法区分。我们采纳 fluxdo 的设计——一个按钮打开完整 WebView。如果后续需要 Google/Apple 原生 OAuth（需要服务端 OAuth client ID 配合），再单独拆分。

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
init(identifier, password, primingCookies, onResult, onCancel)
  ├─ viewDidLoad: 配置 WKWebView → primeCookies → loadHTMLString(minimalLoginHTML)
  ├─ hCaptcha 通过: 自动调用 __fireLogin(id, pwd, token)
  │    → JS: fetch /session/csrf → POST /hcaptcha/create → POST /session.json
  ├─ login_result messageHandler: onResult(result)
  └─ 用户关闭: onCancel()

retryWithSecondFactor(token)
  └─ 同一存活 WebView 内重跑 __fireLogin(hcaptchaToken=nil, secondFactorToken=token)

// 关键：dialog 的 WKWebView 在成功收口前不可销毁
var webView: WKWebView { get }  // 暴露给 VC 传给 completeMinimalLogin
```

**Live WebView 交接约束：**

成功路径必须保持 dialog 内的 WKWebView 存活，直到 cookie 提取完成：

```
dialog onResult(.success)
  → VC 调用 viewModel.completeMinimalLogin(from: dialog.webView, ...)
    → loginCoordinator.completeJsLogin(from: webView)  // 从 LIVE WebView 抽 cookie
      → cookies = relevantCookies(from: webView)         // 提取 _t, _forum_session 等
      → finalizeLoginFromWebView(captured)               // Rust 收口
    → 成功后才 dismiss dialog（此时 WebView 可安全销毁）
```

知识库 `docs/knowledge/discourse-webview-login-guide.md:286` 明确要求：disposal 前必须从 live WebView 提取 `_t`、`_forum_session`、`cf_clearance`、`_cfuvid` 等 cookies。`FireWebViewLoginCoordinator.completeJsLogin(from:)` (`:372`) 直接从传入的 WKWebView 读取 `navigator.userAgent` 和 cookies。因此 dialog 不可在 `onResult` 回调中自动 dismiss，必须由 VC 在 finalize 完成后主动 dismiss。

### 登录时序（修正后）

```
[1] 点"登录 LinuxDo" → openLogin() → present FireLoginViewController
    （无网络请求，无 WebView）

[2] 登录页加载 → 自动填充 saved credential（纯本地）

[3] 用户填写凭据，点"登录"
    └─ FireLoginViewController.performLogin(identifier, password, rememberCredential)
         ├─ [3a] await viewModel.ensureCloudflareClearance()
         │    ├─ true → 进入 [3b]
         │    └─ false/error → 登录页 error banner，终止
         ├─ [3b] let cookies = await viewModel.primeCookiesForLogin()
         ├─ [3c] VC present FireCaptchaLoginDialogController(id, pwd, cookies)
         │    └─ hCaptcha → __fireLogin → session.json → onResult
         └─ [3d] VC 处理结果 (基于 WebViewLoginDecisionState)
              ├─ .success → await completeMinimalLogin(from: dialog.webView, ...)
              │            → dismiss dialog → dismiss 登录 modal
              ├─ .needSecondFactor(req) → VC 弹 2FA → dialog.retryWithSecondFactor(code)
              │    （重试后再次 onResult，可能仍是 needSecondFactor——见错误处理）
              ├─ .retryCloudflare → await recoverCloudflareAndRetry() (一次)
              │    → 重新 prime + dialog 重跑 __fireLogin
              └─ .failure(kind) → dismiss dialog → 登录页 error banner
```

### 记住密码 API 贯穿

`rememberCredential` 参数从 UI checkbox 一路传到 finalization：

```
FireLoginViewController
  ├─ performLogin(identifier, password, rememberCredential: Bool)
  └─ onResult(.success) →
       viewModel.completeMinimalLogin(
           from: dialog.webView,
           identifier: identifier,
           password: password,
           rememberCredential: rememberCredential  ← 新增参数
       )
         └─ completeMinimalLogin 内部:
              if rememberCredential {
                  try await sessionStore.saveLoginCredential(username:, password:)
              } else {
                  // 未勾选时不保存新凭据
                  // 如果 Keychain 中已有旧凭据，保留旧值不清除（不意外删除用户数据）
              }
```

当前 `completeMinimalLogin` (`FireAppViewModel.swift:318`) 无条件调用 `saveLoginCredential`，需要改为根据 `rememberCredential` 条件执行。

### 社交登录与忘记密码（完整 WebView 兜底）

对齐 fluxdo 的两个 WebView 入口：

1. **"其他方式登录"按钮** → present `FireWebViewBrowserViewController`，加载 `https://linux.do/login`。Discourse 服务端处理 OAuth/Passkey/注册。
2. **"忘记密码?"链接** → present `FireWebViewBrowserViewController`，加载 `https://linux.do/password-reset`。

登录成功检测（对齐 fluxdo `WebViewLoginPage`）：
- 监听 WKWebView cookie store 变化
- 检测 `_t` cookie（有效 auth token）→ 触发 finalize
- 或注入 JS 检查 `meta[name="current-username"]`
- 成功后 dismiss WebView → dismiss 登录页 → finalize 路径

### Cookie 流转（含 Live WebView 交接）

```
Keychain/Session → ViewModel.primeCookiesForLogin() → cookie payload
                                                          ↓
                         VC 传入 dialog init → primeCookies into Dialog's WKWebView
                                                          ↓
                                           hCaptcha + session.json
                                                          ↓
                                     dialog onResult → VC
                                                          ↓
              VC: viewModel.completeMinimalLogin(from: dialog.webView, ...)
                    ↓ LIVE WKWebView 传入
                    completeJsLogin(from: webView)
                      → relevantCookies(from: webView)  ← 从 live WebView 提取
                      → finalizeLoginFromWebView → Rust session
                    ↓
                    saveLoginCredential (如果 rememberCredential == true)
                    ↓
                    VC dismiss dialog (WebView 可安全销毁)
                    → VC dismiss 登录 modal
```

## Error Handling

错误处理基于 Rust 的 `WebViewLoginDecisionState`（`rust/crates/fire-core/src/core/session.rs:91-122`），不自行发明状态：

| WebViewLoginDecisionState | 触发条件 | 展示位置 | UI 行为 |
|--------------------------|---------|---------|---------|
| `.success` | session.json 200 | — | completeMinimalLogin → dismiss all |
| `.needSecondFactor(requirement)` | reason=`second_factor` 或 `invalid_second_factor` | VC 弹 native 2FA 输入框 | 输入验证码 → `dialog.retryWithSecondFactor(code)` |
| `.retryCloudflare` | phase `csrf` 返回 CF challenge 响应（非 BAD CSRF 笼统判定） | — | 自动 `recoverCloudflareAndRetry()` 一次 |
| `.failure(kind)` | `invalid_credentials` / `not_activated` / `not_approved` / `expired` / unknown | 登录页内联 error banner | 根据 kind 显示不同文案 |

**2FA 错误处理（重要）：** Rust 把 `invalid_second_factor` 和 `second_factor` 都映射成 `.needSecondFactor`（`session.rs:96`），不产生独立的 `.failure`。2FA 验证码错误时，用户会收到**重复的** `.needSecondFactor(requirement)`，其中 `requirement.message` 包含服务端错误信息。UI 策略：
- 第一次 `.needSecondFactor` → 弹 2FA 输入框
- 重试后再次 `.needSecondFactor` 且 `message` 非空 → 在 2FA 输入框下方显示 `message` 作为错误提示，清空验证码，允许重试
- `requirement.backup_enabled` / `security_key_enabled` 为 true 但用户无此能力 → 显示"备用码/安全密钥请通过其他方式登录"提示，引导走完整 WebView（对齐 fluxdo `two_factor_dialog.dart:94-106` 的 fallback 逻辑）

**CF retry 触发条件（精确）：** 仅当 phase `csrf`（`/session/csrf` 请求）返回 Cloudflare challenge 响应时才触发 `.retryCloudflare`。知识库 `discourse-webview-login-guide.md:252-264` 定义了完整步骤：CF 验证 → 等 cookie 传播 → 提取 `cf_clearance` + `_cfuvid` → 写入 Rust trusted → 重新 prime 同一 live WebView → 重跑 `__fireLogin`（hCaptcha token 可复用，因为 csrf 阶段在 hCaptcha create 之前失败）。不是所有 BAD CSRF 都等于 CF retry。

**hCaptcha widget 错误：** hCaptcha 失败/过期由 widget 自身处理（auto reset），通过 `hcaptcha_error` / `hcaptcha_expired` messageHandler 通知 dialog 底部状态区显示提示。这不经过 Rust 分类。

**网络超时：** JS fetch 层超时由 dialog 自行处理，不产生 `WebViewLoginDecisionState`。dialog 底部状态区显示"网络超时，请重试"。

**Dialog dismiss 边界：**
- 登录成功 → **finalize 完成后** dismiss dialog → dismiss 整个 modal（不可提前 dismiss dialog，否则 live WebView 销毁导致 cookie 提取失败）
- 登录失败 → dismiss dialog → 登录页恢复按钮 + error banner
- 用户点 [×] 关闭 dialog → onCancel → 取消 loading，登录页恢复初始状态
- CF 验证期间用户可取消，回到登录页

**已有防护保留：**
- `cfRetryUsed`（CF 重试一次）防止无限重试
- `classifyWebViewLoginResult`（Rust 分类）不变
- `completeJsLogin` cookie 捕获不变（需要 live WKWebView）
- `finalizeLoginFromWebView` Rust finalize 不变

## Implementation Phases

### Phase 1：原生登录页 UI + 登录流程接通（可验证交付点）

新建 `FireLoginViewController.swift`（纯原生 UI）和 `FireCaptchaLoginDialogController.swift`（hCaptcha dialog）。`FireRootCoordinator` 切换到新 VC。登录按钮接通完整流程（CF 检查 → present dialog → 结果处理 → finalize）。旧 `FireLoginWebView.swift` 删除。

**为什么 UI 和流程必须一起交付：** 如果只替换 UI 但不接通登录流程，用户会从当前可用的登录入口退化成无法登录。此阶段必须是一个完整的、可验证的交付点。

| 文件 | 操作 |
|------|------|
| 新建 `FireLoginViewController.swift` | Logo + 输入框 + 记住密码 + 登录按钮 + 忘记密码链接 + "其他方式登录"按钮 |
| 新建 `FireCaptchaLoginDialogController.swift` | hCaptcha WebView + `__fireLogin` + 结果回调 + live WebView 暴露 |
| 修改 `FireAppViewModel.swift` | `openLogin()` 简化移除预加载；新增 `ensureCloudflareClearance()` / `primeCookiesForLogin()`；`completeMinimalLogin` 增加 `rememberCredential` 参数 |
| 修改 `FireRootCoordinator.swift` | present `FireLoginViewController` 替代旧 VC |
| 删除 `FireLoginWebView.swift` | 旧 VC 移除 |

**验收标准：** 用户可以打开登录页 → 输入账号密码 → 通过 hCaptcha → 成功登录进入主界面。CF 按需触发。记住密码勾选生效。2FA 可用。

### Phase 2：完整 WebView 兜底（社交登录 + 忘记密码）

"其他方式登录"按钮和"忘记密码"链接接通完整 WebView VC。

| 文件 | 操作 |
|------|------|
| 新建/复用 `FireWebViewBrowserViewController.swift` | 完整 WebView，支持加载指定 URL + 登录成功检测 |
| 修改 `FireLoginViewController.swift` | 按钮点击 → present browser VC |

### Phase 3：错误处理打磨

内联 error banner 替代 UIAlertController，2FA 弹窗优化（重复 needSecondFactor 的 message 展示），dialog 底部状态区错误完善。

| 文件 | 操作 |
|------|------|
| 修改 `FireLoginViewController.swift` | 内联 error banner 组件 |
| 修改 `FireCaptchaLoginDialogController.swift` | 底部状态区错误展示 + 重试提示 |

## File Change Summary

| 文件路径 | 操作 | 阶段 |
|---------|------|------|
| `native/ios-app/App/Views/Other/FireLoginViewController.swift` | 新建 | P1, P3 (error banner) |
| `native/ios-app/App/Views/Other/FireCaptchaLoginDialogController.swift` | 新建 | P1, P3 |
| `native/ios-app/App/Views/Other/FireWebViewBrowserViewController.swift` | 新建/复用 | P2 |
| `native/ios-app/App/Views/Other/FireLoginWebView.swift` | 删除 | P1 |
| `native/ios-app/App/ViewModels/FireAppViewModel.swift` | 修改 | P1 |
| `native/ios-app/App/Core/FireRootCoordinator.swift` | 修改 | P1 |

## Preserved Boundaries (不变)

以下逻辑完全保留不动，确保 Rust 侧和 finalize 链路稳定：

- UniFFI boundary：`finalizeLoginFromWebView`、`classifyWebviewLoginResult`
- Cookie 捕获：`FireWebViewLoginCoordinator.completeJsLogin`（需要 live WKWebView）
- Keychain 凭据存储：`FireSavedCredential`、`FireAuthCookieKeychainStore`
- Minimal login HTML/JS：`FireLoginScripts.minimalLoginHTML`、`__fireLogin`
- CF challenge coordinator：`FireCloudflareChallengeCoordinator`
- Session store：`FireSessionStore`
- Rust 登录决策状态机：`WebViewLoginDecision`（success / needSecondFactor / retryCloudflare / failure）

## Reference

- fluxdo 登录页：`references/fluxdo/lib/pages/login_page.dart:138-213`
- fluxdo hCaptcha dialog：`references/fluxdo/lib/widgets/auth/webview_login_dialog.dart`
- fluxdo 原生表单：`references/fluxdo/lib/widgets/auth/login_form.dart`
- fluxdo WebView 兜底：`references/fluxdo/lib/pages/webview_login_page.dart`
- fluxdo 忘记密码：`references/fluxdo/lib/pages/login_page.dart:396`
- fluxdo 其他方式登录：`references/fluxdo/lib/pages/login_page.dart:416`
- Fire 当前登录 VC（待替换）：`native/ios-app/App/Views/Other/FireLoginWebView.swift`
- Fire minimal login 脚本：`native/ios-app/Sources/FireAppSession/FireWebViewBrowserProfile.swift:193-408`
- Fire 登录协调器：`native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift:372`
- Fire completeMinimalLogin（需加 rememberCredential）：`native/ios-app/App/ViewModels/FireAppViewModel.swift:293`
- Rust 登录决策状态机：`rust/crates/fire-core/src/core/session.rs:91-122`
- 登录知识库（cookie 交接、CF retry、2FA）：`docs/knowledge/discourse-webview-login-guide.md:240-299`
