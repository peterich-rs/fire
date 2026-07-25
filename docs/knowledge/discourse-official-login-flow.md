# Discourse 官方登录实现梳理

> **文档性质**：对照 Discourse 上游开源实现，说明 `/login` 及相关登录渠道的**真实协议与前端逻辑**。  
> **不是** Fire 客户端实现规格；Fire 的 WebView 收口见 [discourse-webview-login-guide.md](./discourse-webview-login-guide.md)。  
> **不是** 绕过 Cloudflare / 验证码 / 风控的指南。  
> **目标**：为后续可能的 Native / Hybrid 登录提供**可核对的官方事实源**。

---

## 0. 范围与来源

### 0.1 覆盖范围

| 范围 | 内容 |
|------|------|
| 包含 | 本地密码登录、2FA、外部 OAuth、Passkey、邮箱 magic link、邮箱验证码登录（login code）、CSRF、会话 cookie 产物、OAuth 回流 |
| 包含 | 与登录相关的路由表、前端控制器动作、后端 `SessionController` 行为摘要 |
| 不包含 | 注册全流程细节、User API Key 授权页、LDC/CDK 产品 OAuth（见 [api/13-ldc-cdk-oauth.md](./api/13-ldc-cdk-oauth.md)） |
| 不包含 | linux.do 站点私有插件的未公开逻辑（见 §11 站点层待实测） |

### 0.2 上游源码锚点（discourse/discourse `main`）

| 层级 | 路径 |
|------|------|
| 登录页控制器 | `frontend/discourse/app/controllers/login.js` |
| 登录路由 | `frontend/discourse/app/routes/login.js` |
| 外部登录方法模型 | `frontend/discourse/app/models/login-method.js` |
| 登录 Service | `frontend/discourse/app/services/login.js` |
| 登录按钮 UI | `frontend/discourse/app/components/login-buttons.gjs` |
| Ajax / CSRF 刷新 | `frontend/discourse/app/lib/ajax.js` |
| CSRF Header 注入 | `frontend/discourse/app/instance-initializers/csrf-token.js` |
| OAuth 回流处理 | `frontend/discourse/app/instance-initializers/auth-complete.js` |
| 邮箱链接登录 | `frontend/discourse/app/controllers/email-login.js` |
| WebAuthn / Passkey 前端 | `frontend/discourse/app/lib/webauthn.js` |
| 会话后端 | `app/controllers/session_controller.rb` |
| OAuth 回调后端 | `app/controllers/users/omniauth_callbacks_controller.rb` |
| 2FA 校验 | `app/models/concerns/second_factor_manager.rb` |
| 路由 | `config/routes.rb` |

### 0.3 与「整页登录 HTML」的关系

Discourse 登录页是 **Ember SPA 壳**。真正建立会话的是 **XHR / form POST 到 Session / Auth 端点**，而不是服务端渲染表单直接 `multipart` 提交密码（密码路径尤其如此）。

因此：

- **理解官方实现** = 理解前端控制器 + 路由 + Session/OmniAuth API  
- **不等于** 必须复刻整页 HTML/CSS  
- 客户端（含 Fire）若只打开 WebView 加载 `/login`，是在**复用**这套官方前端，而不是另写一套登录协议

---

## 1. 总览

### 1.1 会话模型

Discourse 浏览器会话的核心不是 Bearer Token，而是 **Cookie**：

| Cookie | 角色 |
|--------|------|
| `_t` | 用户认证 token（`UserAuthToken`），HttpOnly；**已登录的主凭证** |
| `_forum_session` | Rails/Discourse 服务端 session；与 CSRF、部分 challenge 状态相关 |
| `cf_clearance` | **非 Discourse**；Cloudflare 边缘放行（linux.do 前置）。登出时常保留 |

登录成功的本质动作是服务端 `log_on_user` → `Set-Cookie: _t=...`（以及 session 更新）。

### 1.2 渠道总表

| 渠道 | 前端入口 | 建立会话的关键请求 | 导航方式 |
|------|----------|-------------------|----------|
| 本地用户名/密码 | `LoginPageController.localLogin` | `POST /session` | XHR（`discourse/lib/ajax`） |
| TOTP / 备份码 2FA | 同上二次提交 | `POST /session` + `second_factor_*` | XHR |
| Security Key 2FA | WebAuthn 后同上 | `POST /session` + security key token | XHR |
| 外部 OAuth | `LoginMethod.doLogin` | `POST /auth/{provider}` 后整页跳转 IdP | **HTML form 整页提交**（非 XHR） |
| Passkey（一等登录） | `passkeyLogin` | `POST /session/passkey/auth`（前端常带 `.json`） | XHR |
| 邮箱 magic link | Email login 页 | `POST /session/email-login/:token` | XHR |
| 邮箱验证码 login code | Code login UI | `POST /session/login-code` + `.../verify` | XHR |
| DiscourseConnect SSO | route `beforeModel` | `GET /session/sso` | 整页跳转 |

### 1.3 总时序（概念）

```text
                    ┌──────────────────────────┐
                    │  GET /login  (+ 边缘 CF) │
                    │  Ember boot + preloaded  │
                    │  meta csrf-token         │
                    └────────────┬─────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
   本地密码 UI              OAuth 按钮们              Passkey / Email
         │                       │                       │
         ▼                       ▼                       ▼
  GET /session/csrf*      GET /session/csrf*        各渠道 API
  POST /session           POST /auth/{provider}      (见分节)
  (+ 2FA 再 POST)         form 整页跳转 IdP
         │                       │
         │                       ▼
         │              OmniAuth callback
         │              log_on_user / auth data
         ▼                       ▼
              Set-Cookie _t  （会话已建立）
                                 │
                                 ▼
                    前端 redirect / reload /
                    后续 API 带 Cookie + CSRF
```

\* CSRF：见 §2。XHR 在缺 token 时自动拉；OAuth form 提交前也会 `updateCsrfToken()`。

---

## 2. CSRF

### 2.1 两种携带方式

| 场景 | 方式 | 字段/头 |
|------|------|---------|
| Ajax（密码登录、大多数写接口） | Request Header | `X-CSRF-Token: <token>` |
| OAuth 启动 form | Form body | `authenticity_token=<token>` |

### 2.2 前端初始化

`instance-initializers/csrf-token.js`：

1. 从 `document.head meta[name=csrf-token]` 读入 `session.csrfToken`  
2. 通过 `$.ajaxPrefilter` 给**非 crossDomain** 请求自动加 `X-CSRF-Token`

### 2.3 缺 token 时的补齐

`lib/ajax.js`：

- 非 GET 请求且 `Session.csrfToken` 为空  
- 且 URL 不是特例 `/clicks/track`  
- → 先 `GET /session/csrf`，写入 token，再发原请求  
- `updateCsrfToken()` **单飞**（并发共用一个 in-flight）

```http
GET /session/csrf
→ 200 { "csrf": "<token>" }
```

后端：`SessionController#csrf` → `render json: { csrf: form_authenticity_token }`。

### 2.4 BAD CSRF

Ajax error 处理：若 `403` 且 body 精确为 `["BAD CSRF"]`，则清空内存 CSRF（**不在此处自动重试**；Discourse 前端依赖后续请求再次 `updateCsrfToken`）。  
Fire 客户端实现了「清 token → 刷新 → 重试一次」，与官方前端策略有差异，但目标一致。

### 2.5 与 Cookie 的关系

CSRF token 与 `_forum_session` 绑定。密码登录前后通常已有 forum session cookie；OAuth form POST 同样依赖已建立的 session + authenticity_token。

---

## 3. 打开 `/login` 路由逻辑

源：`frontend/discourse/app/routes/login.js`。

### 3.1 `beforeModel` 分支

| 条件 | 行为 |
|------|------|
| 站点只读且非 staff-writes-only | `transition.abort()` + 弹窗「只读不可登录」 |
| DOM 存在 `#data-authentication` | 视为 OAuth/认证回流中，**不**再改写流程 |
| `capabilities.isAppWebview` | `postRNWebviewMessage("showLogin", true)`（给宿主 App 的钩子） |
| 未登录且 URL 可作为 destination | 写 cookie `destination_url`（登录后回跳） |
| `siteSettings.enable_discourse_connect` | **整页** `location = /session/sso?return_path=...`，并挂起 transition |
| 关闭本地登录且外部方法恰好 1 个 | **自动** `singleExternalLogin()`（直接踢进唯一 OAuth） |
| 否则 | 进入登录页渲染 |

### 3.2 站点开关（影响 UI 与是否允许本地登录）

前端会读的关键 `siteSettings`（名称以源码为准）：

| Setting | 作用 |
|---------|------|
| `enable_local_logins` | 是否显示/允许本地密码 |
| `enable_local_logins_via_email` | 是否允许邮箱类本地登录能力 |
| `enable_local_logins_via_code` | 是否启用邮箱验证码登录 UI |
| `enable_passkeys` | 是否显示 Passkey（还需 WebAuthn 支持） |
| `enable_discourse_connect` | SSO 接管，本地登录后端也会拒绝 |
| `auth_immediately` / `login_required` | 影响是否立刻外跳 SSO/唯一 OAuth |
| `auth_skip_create_confirm` | OAuth 新用户是否跳过确认页 |

后端 `check_local_login_allowed`：若 `enable_discourse_connect` 或 `!enable_local_logins`，本地密码/部分邮箱路径会 `InvalidAccess`（admin 特例除外）。

### 3.3 Provider 列表不是写死的

```javascript
// login-method.js
Site.currentProp("auth_providers").map((provider) => LoginMethod.create(provider))
```

每个 provider 至少有 `name`（如 `google_oauth2`、`github`），以及可选 title/icon 覆盖。  
登录按钮组件遍历 `findAll()` 渲染。

---

## 4. 本地用户名密码登录（主路径）

### 4.1 前端：`localLogin`

源：`controllers/login.js` → `async localLogin()`。

**前置校验**

- `loginDisabled`（正在登录/已登录）则返回  
- `loginName` 或 `loginPassword` 为空 → flash：`login.blank_username_or_password`

**请求**

```http
POST /session
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
X-CSRF-Token: <csrf>
X-Requested-With: XMLHttpRequest   # jQuery 默认行为，Discourse 依赖 JSON 风格
Cookie: _forum_session=...

login=<username_or_email>
password=<password>
second_factor_token=<optional>
second_factor_method=<optional int>
timezone=<moment.tz.guess()>
```

前端 data 对象字段名（Ember `ajax` 会编码为 form）：

| 字段 | 说明 |
|------|------|
| `login` | 用户名或邮箱；后端会去 `@` 前缀、normalize、截断 |
| `password` | 明文密码（HTTPS）；超长直接 invalid |
| `second_factor_token` | TOTP/备份码字符串，或 Security Key 凭证数据 |
| `second_factor_method` | 见 §5 |
| `timezone` | 浏览器时区猜测，成功登录后可写回用户 |

**说明**：官方**没有**在核心 `localLogin` 里附加 hCaptcha token。若站点登录出现 captcha，来自**插件或定制**，不属于 Discourse 核心密码路径（见 §11）。

### 4.2 后端：`SessionController#create`

摘要（顺序敏感）：

1. `params.require(:login)` / `require(:password)`  
2. 密码长度 > max → `invalid_credentials`  
3. `User.find_by_username_or_email`  
4. 用户不存在或 `!confirm_password?` → `{ error: I18n login.incorrect_... }`  
5. 需审批且未批准 → `{ error: not_approved }`  
6. 密码过期 → `{ error: "expired", reason: "expired" }`  
7. `login_error_check`：封禁、IP 屏蔽、admin IP 限制  
8. `authenticate_second_factor(user)`；失败 → `failed_json` + 2FA 载荷（§5）  
9. `user.active && email_confirmed?`  
   - 是 → `login(user)` → `log_on_user` + 序列化用户  
   - 否 → `not_activated` JSON（含 `reason: "not_activated"` 等）

限流：`rate_limit_login`（按 IP 的 hour/minute site settings）。

### 4.3 前端对响应的处理

**A. `result.error` 存在**

| 条件 | UI |
|------|-----|
| `(security_key_enabled \|\| totp_enabled) && !secondFactorRequired` | 进入 2FA UI（§5），隐藏外部登录按钮 |
| `reason === "not_activated"` | `NotActivatedModal` |
| `reason === "suspended"` | `dialog.alert(error)` |
| `reason === "expired"` | flash HTML 链到 `/password-reset` |
| 其他 | `flash = result.error` |

**B. 无 `error`（成功）**

1. `loggedIn = true`  
2. 填充页面隐藏静态表单 `#hidden-login-form`（用户名/密码/redirect），用于**触发浏览器密码管理器**  
3. 非 iOS Safari：`hidden form.submit()`；iOS Safari：直接 `location` 到 redirect  
4. redirect 优先 `cookie destination_url`，否则当前页  

此时 **`_t` 已在 `POST /session` 的 Set-Cookie 中下发**；后续跳转只是 UX/密码管理器。

**C. HTTP 层异常（catch）**

| 条件 | flash |
|------|--------|
| 429 | `login.rate_limit` |
| 503 + `error_type === "read_only"` | 只读模式文案 |
| Cookie 被禁用 | `login.cookies_error` |
| 其他 | `login.error` |

### 4.4 登录页固定 DOM ID（官方模板约定）

WebView autofill 与官方页面依赖：

| ID | 用途 |
|----|------|
| `#login-account-name` | 用户名/邮箱输入 |
| `#login-account-password` | 密码输入 |
| `#login-button` | 登录按钮 |
| `#hidden-login-form` | 成功后密码管理器用（客户端协议层可忽略） |
| `#login-buttons` | 外部登录按钮容器 |

### 4.5 成功后的会话产物

| 产物 | 说明 |
|------|------|
| `_t` | 主会话；后续 API 身份 |
| `_forum_session` | 更新后的服务端 session |
| 响应体 User JSON | `UserSerializer`（有 `sso_payload` cookie 时会走 `sso_provider` 分支而非普通序列化） |
| 前端内存 loggedIn | 仅 SPA 状态；客户端应用应信 cookie / `/session/current` |

---

## 5. 二步验证（2FA）

### 5.1 方法枚举（前后端一致）

前端 `SECOND_FACTOR_METHODS`（`models/user.js`）：

| 名称 | 值 |
|------|-----|
| `TOTP` | 1 |
| `BACKUP_CODE` | 2 |
| `SECURITY_KEY` | 3 |
| `PASSKEY` | 4 |

后端 `UserSecondFactor.methods` 同语义。

### 5.2 首次密码成功但未带 2FA 时

`authenticate_second_factor` 在用户启用了 2FA 且请求未给出合法 method/token 时返回失败结果。  
失败结构来自 `SecondFactorAuthenticationResult` Struct，经 `to_h` 合并进 JSON，字段包括：

| 字段 | 含义 |
|------|------|
| `ok` | false |
| `error` | 可读错误文案 |
| `reason` | 如 `invalid_second_factor_method`、`invalid_second_factor`、`invalid_security_key` 等 |
| `backup_enabled` | 是否启用备份码 |
| `security_key_enabled` | 是否启用 security key |
| `totp_enabled` | 是否启用 TOTP |
| `multiple_second_factor_methods` | 是否多种 2FA 可选 |

若启用 security key，后端还会 `stage_challenge` 并 merge WebAuthn 的 `challenge` / `allowed_credential_ids` 等。

前端看到 `totp_enabled` 或 `security_key_enabled` 且尚未进入 2FA UI 时，**切换到 2FA 界面**，而不是当普通密码错误。

### 5.3 二次提交

用户输入 TOTP 或完成 WebAuthn 后，**再次**调用同一 `POST /session`，带上：

```text
login, password,          # 仍带原密码
second_factor_token,      # TOTP 码 或 security key credential
second_factor_method,     # 1/2/3/4
timezone
```

### 5.4 与「操作级 2FA」的区别

另有通用挑战流：

```http
GET  /session/2fa?nonce=...
POST /session/2fa
```

用于**已登录用户**执行敏感操作时的二次确认（`SecondFactor::AuthManager`），**不是**登录页主路径。登录页主路径是 §4 的 `POST /session`。

---

## 6. 外部 OAuth（GitHub / Google / …）

### 6.1 前端启动（关键：整页 form，不是 XHR）

源：`login-method.js` → `doLogin`：

```text
1. updateCsrfToken()                    # GET /session/csrf
2. 创建 hidden <form method="POST" action="/auth/{name}">
     authenticity_token = csrfToken
     可选: reconnect, signup, email, origin
3. document.body.appendChild(form)
4. form.submit()                         # 整页导航离开
```

`LoginService.externalLogin` 仅包装 `doLogin`，并设置 `loggingIn`。

`customLogin` / `custom_url` 存在时走定制逻辑或直接 `location = custom_url`。

### 6.2 路由

```text
GET  /auth/:provider              → confirm_request（确认页，部分流程）
POST /auth/:provider              → OmniAuth 启动（form 常用）
GET|POST /auth/:provider/callback → omniauth_callbacks#complete
GET|POST /auth/failure            → failure
```

### 6.3 回调后端摘要

`Users::OmniauthCallbacksController#complete`：

1. 从 `request.env["omniauth.auth"]` 取 IdP 结果  
2. `authenticator.after_authenticate`  
3. 已有用户 → 登录（`log_on_user` 路径在 authenticator/result 处理中）  
4. 新用户 → 准备注册数据  
5. 写 `cookies[:authentication_data] = client_hash.to_json`  
6. `cookies["_bypass_cache"] = true`  
7. `redirect_to @origin`（通常站点内 path）

### 6.4 前端回流：`auth-complete.js`

页面带 `#data-authentication`（由 cookie/预加载注入 authentication 数据）时：

| 情况 | 行为 |
|------|------|
| 已知 AuthErrors 位 | 回登录页 flash |
| `suspended` | 错误 |
| `omniauth_disallow_totp` | 要求用密码+TOTP；预填 email |
| `authenticated` | 跳 `destination_url` 或 `/` 或 reload |
| 未完成账号（新用户） | 转 signup 并带上 email/username/name/authOptions |

### 6.5 对客户端实现的含义

1. **不要**在 App 内实现 Google/GitHub OAuth Client 去换 Discourse 会话。  
2. **应当**让 Discourse 继续当 OAuth Client：`POST /auth/{provider}` + 浏览器完成 IdP + 回调写 `_t`。  
3. Provider 集合以运行时 `auth_providers` 为准。  
4. IdP 页面（账号密码、2FA、同意）**必须用户可见**；Discourse 中间跳转可短时不可见。  
5. 成功判据与密码路径相同：出现有效 `_t`（及前端 username / authentication 完成）。

---

## 7. Passkey（一等登录因子）

### 7.1 显示条件

```text
enable_local_logins
&& enable_passkeys
&& isWebauthnSupported()
```

按钮在 `login-buttons` / `PasskeyLoginButton`。

### 7.2 前端流程

```text
getPasskeyCredential(mediation)
  → POST /session/passkey/auth(.json)
       body: { publicKeyCredential }
  → 无 error：destination_url 或 location.reload()
```

挑战获取：`GET /session/passkey/challenge`（后端 `passkey_challenge`）。

### 7.3 后端

`passkey_login`：

- 需 `enable_passkeys`  
- `DiscourseWebauthn::AuthenticationService` 校验 `publicKeyCredential`（first_factor）  
- 用户 active、审批、login_error_check  
- email confirmed → `login(user, passkey_login: true)`  
- 否则 not_activated  

---

## 8. 邮箱 Magic Link

### 8.1 路由

```http
GET  /session/email-login/:token   → email_login_info（JSON：能否登录、2FA 需求）
POST /session/email-login/:token   → email_login（确认 token 并登录）
```

用户邮件中的链接通常打开带 token 的页面；Ember `EmailLoginController` 处理。

### 8.2 前端完成登录

```http
POST /session/email-login/{token}
second_factor_method=...
second_factor_token=...   # 或 security key credential
timezone=...
```

成功：`result.success` → `DiscourseURL.redirectTo("/")`（可带 safe_mode query）。

### 8.3 后端要点

- token 经 `EmailToken.confirmable` / `confirm`（scope: email_login）  
- 可要求 2FA（与密码登录共享 `authenticate_second_factor`）  
- 成功 `log_on_user`  
- 本地登录开关 / `enable_local_logins_via_email` 约束  

### 8.4 客户端（含 Fire 文档中的约定）

- Deep link / 剪贴板路径前缀：`/session/email-login/`  
- 现实现：WebView 打开该 URL，检测登录成功后 cookie 收口  

---

## 9. 邮箱验证码登录（Login Code）

较新的本地登录变体（站点需打开相关 settings）。

### 9.1 路由

```http
POST /session/login-code          → create_login_code  （请求发码）
POST /session/login-code/verify   → verify_login_code （校验码并登录/注册尾部）
```

### 9.2 防护

- IP / email 限流  
- Honeypot：`password_confirmation`、`challenge` 与 `GET /session/hp` 下发的 honeypot 关联  
- 失败时故意返回与成功相似的响应，降低邮箱探测  

### 9.3 前端

`LoginPageController`：`showCodeLogin` / `usePassword` 切换 `showCodeLoginForm`。  
需同时：`enable_local_logins_via_code` + `enable_local_logins_via_email` + `enable_local_logins`。

---

## 10. 相关辅助端点

| 方法 | 路径 | 用途 |
|------|------|------|
| GET | `/session/csrf` | 取 CSRF |
| GET | `/session/current` | 当前用户（无用户时 404/空）；Fire 多用 `.json` |
| DELETE | `/session/:username` | 登出（`resources :session` destroy） |
| GET | `/session/hp` | 注册/login-code honeypot |
| POST | `/session/forgot_password` 等 | 忘记密码（`forgot_password` action；具体 path 以 routes 为准） |
| GET | `/session/sso` | DiscourseConnect 消费者入口 |
| GET | `/login` | 静态入口，实际 Ember 登录页 |
| POST | `/login` | `static#enter`（历史/静态入口，**不是** `localLogin` 的 XHR） |

说明：密码登录的权威 API 是 **`POST /session`**，不是 `POST /login`。

---

## 11. 边缘层与站点差异（非 Discourse 核心，但生产关键）

### 11.1 Cloudflare

linux.do 前置 Cloudflare。未持有有效 `cf_clearance` 时，对 `/login` 的直接请求可能：

```text
403
cf-mitigated: challenge
Server: cloudflare
text/html 挑战页（Just a moment / Turnstile 等）
```

这发生在 Discourse 应用**之前**。官方 Ember 登录逻辑只有在挑战通过后才会执行。

客户端策略（Fire 已文档化）：WebView 完成挑战 → 回灌 `cf_clearance` → 再访问应用层 API。详见 [discourse-webview-login-guide.md](./discourse-webview-login-guide.md) §9 与 [api/02-auth-and-session.md](./api/02-auth-and-session.md)。

### 11.2 hCaptcha / 其他插件

- Discourse **核心** `localLogin` **不**发送 captcha token。  
- 官方插件 `discourse-hcaptcha` 等主要面向**注册**等场景。  
- 某站点是否在**登录**强制 captcha，必须以该站实测为准，不能从核心源码推断。

### 11.3 linux.do 待实测清单（站点层）

以下**不能**仅靠上游源码确定，需在已通过 CF 的浏览器/WebView 中用自有账号核对：

| 项 | 如何核对 |
|----|----------|
| `enable_local_logins` 等开关 | 预加载 `siteSettings` / 登录页 UI |
| `auth_providers` 列表与 `name` | `Site` 预加载或登录按钮 |
| 是否 DiscourseConnect-only | 打开 `/login` 是否立即 SSO |
| 密码 `POST /session` 实际请求/响应 | DevTools Network |
| 登录是否触发 captcha 请求 | Network 过滤 captcha/hcaptcha |
| Passkey / email code 是否开启 | UI 是否出现对应入口 |
| OAuth form 的 action URL | 点击按钮后的导航 |

实测结果应另文或本节附录更新，避免与上游通用描述混淆。

---

## 12. 登录成功后的「官方前端」收尾 vs 客户端收尾

### 12.1 浏览器官方

1. `Set-Cookie: _t`  
2. SPA redirect/reload  
3. 首页 preloaded `currentUser`  
4. 后续 ajax 自动带 Cookie；写操作带 CSRF  
5. 可能有 tracking / fingerprint 类请求（站点主题或插件相关；非 SessionController 核心）

### 12.2 Fire / FluxDO 类客户端（现状）

不依赖官方 redirect，而是：

1. WebView 跑完上述任一渠道  
2. 检测 `current-username` + `_t`  
3. 边界同步 Cookie → 客户端 CookieJar  
4. 提取 CSRF / preloaded  
5. 应用内 probe / bootstrap  

见 [discourse-webview-login-guide.md](./discourse-webview-login-guide.md)。

### 12.3 若未来 Native 复刻密码路径

应对齐的是 **§4 的 XHR 协议**，而不是：

- 复刻 Ember 组件树  
- 或错误地 `POST /login` 静态入口  

OAuth 则应对齐 **§6 的 form + 回调**，而不是第三方 OAuth SDK。

---

## 13. 协议速查（给实现者）

### 13.1 密码登录最小序列

```text
GET  /session/csrf
POST /session
     login, password, timezone
     Header: X-CSRF-Token
→ Set-Cookie: _t
→ 200 user JSON  或  error / 2FA 载荷

# 若 2FA
POST /session
     login, password, second_factor_token, second_factor_method, timezone
→ Set-Cookie: _t
```

### 13.2 OAuth 最小序列

```text
GET  /session/csrf
POST /auth/{provider}
     authenticity_token=<csrf>
→ 302 … → IdP …
→ GET|POST /auth/{provider}/callback
→ Set-Cookie: _t 与/或 authentication_data
→ 302 回站内 origin
```

### 13.3 会话校验

```text
GET /session/current.json
→ 200 + current_user | 404/无用户
```

### 13.4 登出

```text
DELETE /session/{username}
```

---

## 14. 与 Fire 文档地图的关系

| 文档 | 角色 |
|------|------|
| **本文** | Discourse **官方**登录协议与前端逻辑（上游事实） |
| [discourse-webview-login-guide.md](./discourse-webview-login-guide.md) | 客户端 **WebView 收口**行为规格（Cookie 同步、probe、CF UI） |
| [api/02-auth-and-session.md](./api/02-auth-and-session.md) | Fire 使用的会话/CSRF/probe/logout API 约定 |
| [api/13-ldc-cdk-oauth.md](./api/13-ldc-cdk-oauth.md) | **已登录后** LDC/CDK 产品授权，不是论坛登录 |
| [architecture/discourse-webview-login-implementation-plan.md](../architecture/discourse-webview-login-implementation-plan.md) | Fire 双端实现职责映射 |

### 14.1 概念对照

| 官方概念 | Fire 现状 |
|----------|-----------|
| Ember `/login` UI | 整页 WebView 加载 |
| `POST /session` | **不由 App 直接调用**；由 WebView 内官方 JS 调用 |
| `POST /auth/*` | WebView 内完成 |
| `_t` Set-Cookie | WebView CookieStore → boundary sync → Rust CookieJar |
| `GET /session/current` | Rust probe |
| `GET /session/csrf` | Rust CSRF 服务 |
| CF 挑战 | 平台 WebView challenge coordinator |

---

## 15. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-10 | 初版：基于 discourse/discourse `main` 前端登录控制器、SessionController、OmniAuth 回调、routes 与 2FA manager 梳理；标明 linux.do 站点层待实测 |

---

## 附录 A. 前端关键伪代码（密码）

```javascript
// 对齐 controllers/login.js localLogin
async function localLogin(loginName, loginPassword, secondFactor) {
  if (!loginName || !loginPassword) throw new BlankCredentials();

  const result = await ajax("/session", {
    type: "POST",
    data: {
      login: loginName,
      password: loginPassword,
      second_factor_token: secondFactor?.token,
      second_factor_method: secondFactor?.method,
      timezone: guessTimezone(),
    },
  });

  if (result?.error) {
    if ((result.totp_enabled || result.security_key_enabled) && !alreadyIn2FA) {
      return { type: "need_second_factor", result };
    }
    return { type: "error", result };
  }
  return { type: "success", result }; // _t already set by Set-Cookie
}
```

## 附录 B. 前端关键伪代码（OAuth）

```javascript
// 对齐 models/login-method.js doLogin
async function startExternalLogin(providerName) {
  await updateCsrfToken();
  const form = document.createElement("form");
  form.method = "post";
  form.action = `/auth/${providerName}`;
  form.style.display = "none";
  // authenticity_token input = Session.csrfToken
  document.body.appendChild(form);
  form.submit(); // full navigation
}
```

## 附录 C. 2FA method 数值

| Method | Int |
|--------|-----|
| TOTP | 1 |
| Backup codes | 2 |
| Security key | 3 |
| Passkey（作为 second factor 时） | 4 |
