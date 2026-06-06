# Discourse WebView 登录实现指南

> 本文档描述基于 Discourse 论坛（如 Linux.do）的 WebView 登录方案的完整实现链路与技术细节。文档不绑定任何特定技术栈，可据此在任意移动/桌面平台上复刻。

---

## 目录

1. [整体架构](#1-整体架构)
2. [核心概念与数据结构](#2-核心概念与数据结构)
3. [登录流程详述](#3-登录流程详述)
4. [WebView 注入脚本清单](#4-webview-注入脚本清单)
5. [Cookie 双端同步机制](#5-cookie-双端同步机制)
6. [登录态检测与保持](#6-登录态检测与保持)
7. [保守登出机制](#7-保守登出机制)
8. [CSRF Token 管理](#8-csrf-token-管理)
9. [Cloudflare 对抗](#9-cloudflare-对抗)
10. [会话代管理与请求生命周期](#10-会话代管理与请求生命周期)
11. [平台差异处理](#11-平台差异处理)
12. [安全注意事项](#12-安全注意事项)
13. [完整流程时序图](#13-完整流程时序图)

---

## 1. 整体架构

### 1.1 核心思路

Discourse 使用基于 Cookie 的会话认证，核心会话标识为 `_t` cookie。客户端不实现原生登录表单，而是通过内嵌 WebView 加载 Discourse 官方登录页面，用户完成登录后从 WebView 中提取会话 Cookie，同步到客户端 HTTP 层使用。

这样做的原因：
- Discourse 登录页可能包含 hCaptcha、第三方 OAuth（GitHub/Google 等）、WebAuthn/PassKey 等复杂交互，原生复现成本极高且难以跟随服务端变更
- WebView 登录天然继承 Discourse 的所有安全策略和登录方式

### 1.2 三层架构

```
┌─────────────────────────────────────────────┐
│                  UI 层                       │
│  登录页 → WebView → 检测登录成功 → 关闭页面   │
└──────────────────┬──────────────────────────┘
                   │ Cookie 同步
┌──────────────────▼──────────────────────────┐
│              Cookie 同步层                    │
│  WebView CookieManager ←→ BoundarySync      │
│                              ←→ CookieJar    │
└──────────────────┬──────────────────────────┘
                   │ Cookie 读写
┌──────────────────▼──────────────────────────┐
│              HTTP 请求层                      │
│  拦截器链：SessionGuard → Cookie → CSRF →    │
│  CF Challenge → Redirect → Retry             │
└─────────────────────────────────────────────┘
```

### 1.3 Cookie 存储双端模型

客户端维护两套 Cookie 存储，需要在关键时机双向同步：

| 存储 | 作用域 | 读写方 |
|------|--------|--------|
| **WebView CookieManager** | WebView 引擎内部 | WebView 页面、JS 脚本 |
| **客户端 CookieJar** | 客户端 HTTP 层 | HTTP 拦截器、业务代码 |

两者在以下时机同步：
- **WebView → CookieJar**：登录成功后、Cloudflare 验证通过后（"边界同步"）
- **CookieJar → WebView**：打开 WebView 前（"Cookie 回放"）

---

## 2. 核心概念与数据结构

### 2.1 关键 Cookie

| Cookie 名 | 类型 | 说明 |
|-----------|------|------|
| `_t` | 会话 Cookie（核心） | Discourse 主会话 Token，用户身份的唯一凭证。HttpOnly，登录后由服务端 Set-Cookie 下发 |
| `_forum_session` | 会话 Cookie | 论话会话辅助 Cookie，与 `_t` 共同构成完整会话状态 |
| `cf_clearance` | 持久 Cookie | Cloudflare 人机验证通过凭证，跨请求复用以避免重复验证 |
| `_ga` / `_gid` 等 | 分析 Cookie | Google Analytics，非关键 |
| `hc_accessibility` | 第三方 Cookie | hCaptcha 无障碍 Cookie，允许视障用户跳过验证码 |

会话 Cookie 集合定义：`{ "_t", "_forum_session" }`

关键 Cookie 集合定义：`{ "_t", "_forum_session", "cf_clearance" }`

### 2.2 会话快照（SessionSnapshot）

用于跨请求比较会话状态是否变化，避免不必要的处理：

```
SessionSnapshot {
    tToken: string | null        // _t cookie 值
    forumSession: string | null  // _forum_session cookie 值

    hasSession: bool             // tToken 非空
    hasForumSession: bool        // forumSession 非空
    fingerprint: string | null   // 会话指纹（用 tToken 值充当）

    isStableWith(other): bool    // 与另一个快照比较是否一致
}
```

用途：在 HTTP 响应后对比请求前后的会话快照，检测 `_t` 是否发生 rotation。

### 2.3 会话代（Generation）

全局单调递增的整数，每次登录/登出状态变更时 +1。作用：

- 所有进行中的 HTTP 请求携带当前 generation 标记
- 登录/登出时 generation 递增，旧 generation 的请求响应被丢弃
- 防止登录收口期间旧响应的 `Set-Cookie` 竞争写入

### 2.4 凭证存储

用户名和密码安全存储于平台密钥链（Keychain / Keystore / Credential Manager），用于：
- WebView 登录表单自动填充
- 登录按钮点击时捕获最新凭证（用户可能修改了密码）

### 2.5 预加载数据

Discourse 首页 HTML 中嵌入了 `<div id="data-preloaded" data-preloaded="...">` 和 `<script id="data-discourse-setup">` 标签，包含当前用户信息、站点设置、CSRF Token 等数据。登录成功后从 WebView 页面中提取这些数据，可以避免额外的 HTTP 请求。

---

## 3. 登录流程详述

### 3.1 全流程

```
用户点击"登录"按钮
    │
    ▼
[1] 初始化 WebView
    │ Cookie 回放：将客户端 CookieJar 中的 Set-Cookie 队列写入 WebView
    │ hCaptcha Cookie 注入：同步 hc_accessibility 到 hcaptcha.com 域
    │
    ▼
[2] 加载登录页 URL: {baseUrl}/login
    │ 等待 Cookie 回放完成后再执行 loadUrl
    │
    ▼
[3] 页面加载完成 (onLoadStop)
    │ 注入滚动修复脚本（部分平台需要）
    │ 注入指纹上报 Hook 脚本
    │ 注入凭证自动填充 + 登录按钮 Hook 脚本
    │ 检测登录状态（首次检测）
    │
    ▼
[4] 用户在 WebView 中完成登录
    │ 页面路由变化 (onUpdateVisitedHistory) → 再次检测登录状态
    │ 首页资源加载 (onLoadResource) → 检测到首页响应 → 再次检测
    │
    ▼
[5] 检测到登录成功（读取到 currentUsername + _t cookie）
    │
    ▼
[6] 登录收口（_finalizeLoginBeforeExit）
    │ a. 保存用户名到安全存储
    │ b. 从 WebView 页面提取 CSRF Token → 写入 CSRF 服务
    │ c. 会话代递增，切断旧请求
    │ d. 边界同步：WebView → CookieJar（会话 Cookie + 允许低置信度）
    │ e. 从 CookieJar 读取 _t，与 WebView 中读取的 _t 对比
    │    - 一致：正常
    │    - 不一致：以 CookieJar 为准，记录告警日志
    │ f. 设置内存中的 token，触发登录成功回调
    │ g. 等待指纹上报完成（最多 15 秒）
    │ h. 读取页面预加载数据 (window.__rawPreloaded)
    │
    ▼
[7] 关闭登录页，返回主界面
    │
    ▼
[8] 登录后收尾（异步，不阻塞 UI）
    │ a. 用预加载数据 hydrate 本地缓存（省一次 HTTP 请求）
    │ b. 若无可复用数据，则发 HTTP 请求刷新预加载
    │ c. 记录登录成功日志
```

### 3.2 登录状态检测逻辑

登录状态检测在多个时机触发：`onLoadStop`、`onUpdateVisitedHistory`、`onLoadResource`（仅首页资源）。

检测步骤：

```
1. 通过 JS 读取当前用户名
   - 优先: document.querySelector('meta[name="current-username"]').content
   - 备选: Discourse.User.current().username
   - 无用户名 → 若刚收到过首页响应，则安排重检；否则跳过

2. 等待初始 Cookie 回放完成

3. 执行边界同步：WebView → CookieJar
   - 默认拒绝低置信度会话 Cookie
   - Android 因 `CookieManager` 只能拿到 name/value，登录收口仍保留低置信度例外

4. 从 WebView 读取 _t cookie
   - 候选 URL: baseUrl, baseUrl + "/", currentUrl
   - 逐一查询 CookieManager 中名为 _t 的 cookie
   - 兜底：通过 JS 读取 document.cookie

5. 若 _t 为空 → 安排重检（最多 15 次，间隔 500ms）

6. _t 非空 → 进入登录收口流程
```

**重检机制**：Discourse 是 SPA 应用，登录后页面不会完全刷新，`_t` cookie 可能延迟写入。最多重试 15 次，每次间隔 500ms，覆盖约 7.5 秒的窗口。

### 3.3 邮箱链接登录

Discourse 支持通过邮件发送一键登录链接，URL 格式为 `{baseUrl}/session/email-login/{token}`。

处理方式：
- 从剪贴板粘贴：验证 URL 路径前缀为 `/session/email-login/`，然后在 WebView 中加载
- 从深度链接接收：客户端注册 URL Scheme / Universal Link，接收到链接后打开 WebView 并加载该 URL

注意：邮箱链接登录页不需要自动填充凭证。

---

## 4. WebView 注入脚本清单

### 4.1 预加载数据捕获（文档开始时注入，AT_DOCUMENT_START）

**目的**：监听 Discourse 页面初始化，捕获嵌入的预加载数据。

```javascript
new MutationObserver(function(_, obs) {
  var el = document.querySelector('[data-preloaded]');
  if (!el) return;
  obs.disconnect();
  var parts = [el.outerHTML];
  document.querySelectorAll('meta[name]').forEach(function(m) {
    parts.push(m.outerHTML);
  });
  var setup = document.getElementById('data-discourse-setup');
  if (setup) parts.push(setup.outerHTML);
  window.__rawPreloaded = parts.join('\n');
}).observe(document.documentElement, {childList: true, subtree: true});
```

**要点**：
- 必须在文档开始时注入（`AT_DOCUMENT_START`），因为 `data-preloaded` 元素在 DOM 构建早期就存在
- 捕获三部分：`data-preloaded` 内容、所有 `<meta>` 标签、`data-discourse-setup` 脚本
- 登录成功后通过 `window.__rawPreloaded` 读取

### 4.2 凭证自动填充 + 登录按钮 Hook（页面加载完成后注入）

**目的**：自动填入保存的用户名密码，并拦截登录按钮点击以捕获最新凭证。

```javascript
(function() {
  var savedUser = /* 安全存储中的用户名（JSON 转义） */;
  var savedPass = /* 安全存储中的密码（JSON 转义） */;
  var filled = false;
  var hooked = false;
  var attempts = 0;
  var timer = setInterval(function() {
    var userInput = document.getElementById('login-account-name');
    var passInput = document.getElementById('login-account-password');
    if (userInput && passInput) {
      // 自动填充（仅一次）
      if (!filled && savedUser && savedPass) {
        filled = true;
        userInput.value = savedUser;
        passInput.value = savedPass;
        userInput.dispatchEvent(new Event('input', {bubbles: true}));
        passInput.dispatchEvent(new Event('input', {bubbles: true}));
      }
      // Hook 登录按钮
      if (!hooked) {
        hooked = true;
        var loginBtn = document.getElementById('login-button');
        if (loginBtn) {
          loginBtn.addEventListener('click', function() {
            var u = document.getElementById('login-account-name');
            var p = document.getElementById('login-account-password');
            if (u && p && u.value && p.value) {
              // 通过原生桥接回调，传递 {username, password}
              nativeBridge.callHandler('onLoginCredentials', {
                username: u.value,
                password: p.value
              });
            }
          }, true);  // 使用捕获阶段，在表单提交前执行
        }
      }
      clearInterval(timer);
    }
    if (++attempts > 30) clearInterval(timer);  // 最多约 9 秒
  }, 300);  // 每 300ms 轮询
})();
```

**要点**：
- Discourse 登录表单的 DOM ID 是固定的：`login-account-name`、`login-account-password`、`login-button`
- 用户名和密码必须通过 JSON 转义（`JSON.stringify`）注入，防止 XSS
- 填充后必须触发 `input` 事件（`dispatchEvent`），否则 Discourse 的前端框架（Ember.js）不会感知到值变化
- 登录按钮 Hook 使用捕获阶段（`true` 参数），确保在表单提交前获取凭证
- 轮询方式是因为 Discourse 的登录表单可能是动态渲染的，首次执行时 DOM 可能不完整

### 4.3 指纹上报拦截（页面加载完成后注入）

**目的**：Discourse 在登录后会发送设备指纹（含 `visitor_id` 的 POST 请求），需要等待指纹上报完成再关闭 WebView，否则服务端可能记录不到设备信息。

```javascript
(function() {
  if (window.__fpHooked) return;  // 防止重复注入
  window.__fpHooked = true;

  function notify() {
    try { nativeBridge.callHandler('onFingerprintDone'); } catch(e) {}
  }

  // Hook fetch
  var _f = window.fetch;
  window.fetch = function(input, init) {
    var result = _f.apply(this, arguments);
    if (init && init.method && init.method.toUpperCase() === 'POST' &&
        typeof init.body === 'string' && init.body.indexOf('visitor_id=') !== -1) {
      result.then(notify, notify);  // 无论成功失败都通知
    }
    return result;
  };

  // Hook XMLHttpRequest
  var _o = XMLHttpRequest.prototype.open;
  var _s = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m, u) {
    this._m = m;
    return _o.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function(body) {
    if (this._m === 'POST' && typeof body === 'string' &&
        body.indexOf('visitor_id=') !== -1) {
      this.addEventListener('loadend', notify);
    }
    return _s.apply(this, arguments);
  };
})();
```

**要点**：
- 同时 Hook `fetch` 和 `XMLHttpRequest`，覆盖 Discourse 所有可能的请求方式
- 拦截条件：POST 请求且 body 包含 `visitor_id=`
- 登录流程等待指纹上报最多 15 秒，超时后继续
- 使用 `__fpHooked` 标志防止重复注入

### 4.4 当前用户名读取（登录检测时执行）

```javascript
(function() {
  try {
    var meta = document.querySelector('meta[name="current-username"]');
    if (meta && meta.content) return meta.content;
    if (typeof Discourse !== 'undefined' && Discourse.User &&
        Discourse.User.current()) {
      return Discourse.User.current().username;
    }
    return null;
  } catch(e) { return null; }
})();
```

**要点**：
- 优先读取 `<meta name="current-username">` 标签，无需等 JS 框架初始化
- 备选使用 Discourse 全局对象的 `User.current()` 方法
- 返回 `null` 表示未登录

### 4.5 CSRF Token 提取（登录成功后执行）

```javascript
(function() {
  var meta = document.querySelector('meta[name="csrf-token"]');
  return meta && meta.content ? meta.content : null;
})();
```

---

## 5. Cookie 双端同步机制

### 5.1 边界同步：WebView → CookieJar

**触发时机**（只在关键边界调用，不做常态同步）：
1. 登录成功后
2. Cloudflare 验证通过后
3. 认证探测（probe）前（仅同步 `cf_clearance`）

**同步流程**：

```
1. 从 WebView CookieManager 读取指定 URL 的所有 Cookie
   - URL: 当前页面 URL 或 baseUrl
   - 可选过滤：仅同步指定名称的 Cookie

2. 分类处理：
   - 会话 Cookie（_t, _forum_session）：需要选优去重
   - 其他 Cookie：直接加入写入列表

3. 会话 Cookie 选优（当存在重复时）：
   评分维度（从高到低）：
   a. 值非空 (+100000)
   b. 未过期 (+50000)
   c. Domain 属性：
      - 无 domain（host-only） (+40000)  ← 优先
      - domain == 当前主机 (+30000)
      - 当前主机是 domain 的子域名 (+20000)
   d. HttpOnly (+500)
   e. Secure (+250)
   f. path 长度、value 长度作为次要排序

4. 低置信度过滤：
   - WebView 返回的 Cookie 如果缺少 domain/path/secure/httpOnly/expires/sameSite
     所有属性，视为"低置信度"快照
   - 默认不同步低置信度的会话 Cookie
   - iOS 登录收口已改为高置信度优先
   - Android 登录收口仍保留 `allowLowConfidenceSessionCookies = true` 例外，直到平台能稳定提供 domain/path/flags

5. Domain 处理（平台差异大，详见第 11 节）：
   - Android 会话 Cookie：强制设为 host-only（domain = null）
   - 其他平台：优先使用平台返回值

6. 值编码：
   - 如果 Cookie 值包含 RFC 不允许的字符（如 {}" 等），
     用自定义前缀 + URL 编码存储，读取时解码
```

### 5.2 Cookie 回放：CookieJar → WebView

**触发时机**：打开 WebView 前

**为什么需要**：
- 客户端 HTTP 层通过 `Set-Cookie` 响应头收到的新 Cookie（如 `_t` rotation 后的新值、`cf_clearance`）只存在于 CookieJar 中
- WebView 不知道这些新 Cookie，如果不回放，WebView 可能以旧身份或未登录状态打开

**回放方式**：

```
方式 1（首选）：原始 Set-Cookie 头回放
  - HTTP 响应收到 Set-Cookie 时，将原始头字符串和 URL 入队持久化
  - 打开 WebView 前，通过平台原生 API 将原始头写入 WebView CookieManager
  - 优势：保留完整的 cookie 语义（host-only / domain / sameSite / httpOnly）
  - 各平台实现：
    - Android: CookieManager.setCookie(url, rawSetCookie)
    - iOS/macOS: HTTPCookie.cookies(withResponseHeaderFields:for:) → WKHTTPCookieStore.setCookie
    - Windows: CDP (Chrome DevTools Protocol) Network.setCookie
    - Linux: soup_cookie_jar_set_cookie

方式 2（兜底）：从 CookieJar 已有数据构造
  - 队列为空时（冷启动/长时间无请求），从 CookieJar 读取所有 cookie 及其 rawSetCookie 字段
  - 若有原始头，同方式 1 写入
  - 若无原始头，逐个设置 cookie 属性
```

**队列持久化**：原始 Set-Cookie 队列持久化到磁盘，进程被杀后不丢失。队列中的条目按 `(cookieName, domain)` 去重，保留最新值。

### 5.3 HTTP 请求的 Cookie 处理

```
请求发出前：
  1. 从 CookieJar 加载目标 URL 的所有 Cookie
  2. 设置 Cookie 请求头
  3. 若内存中有 _t token，设置额外头：
     - Discourse-Logged-In: true
     - Discourse-Present: true

响应收到后：
  1. 解析 Set-Cookie 响应头，写入 CookieJar
  2. 检查是否有 auth.session-token 的 Set-Cookie，特殊处理
  3. Cookie 去重：host-only cookie 优先于 domain cookie（同名同路径）
  4. 原始 Set-Cookie 头入队（供后续 WebView 回放）
  5. 对比请求前后的 SessionSnapshot，检测 _t 是否变化
  6. 若 _t 发生 rotation，更新内存中的 token
```

---

## 6. 登录态检测与保持

### 6.1 判断是否已登录

```
isLoggedIn():
  1. 本地检查：CookieJar 中是否有 _t + 安全存储中是否有 username
     → 任一缺失 → 未登录
  2. 服务端验证：GET /session/current.json
     → 有 current_user → 已登录，更新内存 token 和 username
     → 无 current_user → 未登录，执行登出
     → 404 → 未登录（Discourse session_controller 无用户时返回 404）
     → 401/403 → 未登录
     → 网络异常 → 保守返回已登录（避免网络抖动导致误判）
```

### 6.2 会话 Token 的内存-存储对齐

每次 HTTP 请求发出前，从 CookieJar 读取最新的 `_t` 与内存中的 `_tToken` 对比：

- CookieJar 有值但内存为空 → 更新内存（可能由 WebView 边界同步写入）
- CookieJar 为空但内存有值 → 记录告警日志，不立即清空（由 probe 确认后再清）
- 两者不同 → 以 CookieJar 为准

### 6.3 预加载数据的作用

应用启动时，从首页 HTML 提取的预加载数据中包含 `current_user` 信息。作用：
- 同步返回用户信息，避免启动时短暂显示"未登录"状态
- 减少启动时的 API 请求量
- 登录成功后复用 WebView 页面中的预加载数据，省去一次 HTTP 请求

---

## 7. 保守登出机制

### 7.1 设计动机

Discourse 服务端在以下情况会返回 `discourse-logged-out` 响应头：
1. 有 `_t` cookie 但服务端 `UserAuthToken.lookup` 找不到对应用户（token 已失效）
2. 没有 `_t` cookie 但请求携带了 `Discourse-LoggedIn` 头

然而，收到此头不一定会话真的失效。可能的原因包括：
- Cookie 传输瞬时问题（网络延迟、编码问题）
- `_t` token rotation 窗口（新旧 token 交替的短暂不一致）
- Cloudflare 中间层修改了请求

因此采用"保守登出"策略，不立即登出，而是通过累积 + 探测的方式二次确认。

### 7.2 信号分类

| 信号来源 | 强度 | 说明 |
|----------|------|------|
| 响应体 `error_type: "not_logged_in"` | **强** | 服务端明确说未登录 |
| 4xx + `discourse-logged-out` header | **强** | 认证失败 + 登出标记 |
| 2xx + `discourse-logged-out` header | **弱** | 矛盾信号：请求成功了但标记已登出 |

### 7.3 Strike 系统

```
收到 auth 信号时：
  1. 若正在登出中 → 忽略
  2. 若处于 inconclusive 冷却期（30秒）且为弱信号 → 忽略
  3. 若 probe 正在进行中 → 折叠（不增加 strike）
  4. 累加 strike：
     - 距上次 strike 超过 45 秒 → 重置为 1
     - 否则 → +1
  5. 判断是否达到阈值：
     - 强信号：1 次
     - 弱信号：2 次
  6. 达到阈值 → 执行 session probe
```

### 7.4 Session Probe

通过 `GET /session/current.json` 验证会话是否有效：

```
probe 结果：
  有 current_user → 会话有效
    - 恢复内存 token（从 CookieJar 刷新）
    - 更新 username
    - 重置所有 strike
    - 返回 true

  无 current_user (200 响应) → 确认失效
    - 执行登出
    - 返回 false

  404 → 确认失效（session_controller 无用户时返回 404）
    - 执行登出
    - 返回 false

  网络异常 → 不确定
    - 若累积 strike >= 2 → 升级为登出（宁可误登出也不留在假在线状态）
    - 否则标记 inconclusive，进入 30 秒冷却期
    - 返回 null
```

### 7.5 被动登出处理

确认需要登出后：

```
1. 立即递增会话代，切断所有在途请求
2. 记录被动退出日志（含触发来源、cookie 诊断信息）
3. 记录被动退出次数（24 小时内 3 次以上建议用户清除数据）
4. 执行登出流程
5. 通过错误流通知 UI 层
```

---

## 8. CSRF Token 管理

### 8.1 Discourse CSRF 策略

Discourse 对齐 Ruby on Rails 的 CSRF 保护：
- 所有非 GET 请求必须携带 `X-CSRF-Token` 请求头
- Token 值从页面 `<meta name="csrf-token">` 标签获取
- Token 过期或无效时，服务端返回 `403` + `["BAD CSRF"]`

### 8.2 客户端 CSRF 管理

```
CSRF Token 生命周期：

  初始获取：
    方式 1: 从 WebView 页面 <meta> 标签提取（登录时）
    方式 2: 请求 GET /session/csrf.json（客户端 HTTP 层）

  使用策略（对齐 Discourse 官方前端）：
    - 非 GET 请求发出前，若 CSRF token 为空，先请求 /session/csrf.json 获取
    - 将 token 设置到 X-CSRF-Token 请求头
    - 若 token 为空，设置 "undefined"（与 Discourse 前端行为一致）

  BAD CSRF 处理：
    收到 403 + ["BAD CSRF"] 时：
    1. 清空当前 CSRF token
    2. 请求 /session/csrf.json 获取新 token
    3. 用新 token 重试原请求（仅重试一次，用标记防止无限循环）
    4. 重试时重新加载 Cookie（清除请求中缓存的 Cookie 头）

  清除时机：
    - 登出时
    - BAD CSRF 时
```

### 8.3 防止并发 CSRF 刷新

使用活跃请求锁（`_activeCsrfRequest`）：如果已有请求正在获取 CSRF token，后续请求等待同一个 Future，避免并发重复请求。

---

## 9. Cloudflare 对抗

### 9.1 问题

Discourse 站点通常使用 Cloudflare CDN/Bot Management。客户端原生 HTTP 请求的 TLS 指纹与浏览器不同，可能被 Cloudflare 识别为机器人并返回 403（Turnstile Challenge）。

### 9.2 解决方案

#### 方案 A：WebView HTTP Adapter（透明代理）

通过 WebView 的 JS `fetch()` API 发送 HTTP 请求，利用真实浏览器引擎的 TLS 指纹绕过 Cloudflare Bot Management：

```
1. 维护一个隐藏的 WebView 实例
2. 在其中注入 JS fetch() 调用
3. 将请求参数序列化传入，将响应序列化传出
4. 自动处理 cookie 同步
```

#### 方案 B：Turnstile Challenge 处理

收到 403 + Turnstile Challenge 时：

```
1. 弹出悬浮 WebView 展示 Turnstile 验证
2. 用户完成人机验证
3. 从 WebView 同步 cf_clearance cookie 到 CookieJar
4. 用新 cookie 重试原请求
```

#### 方案 C：cf_clearance 自动续期

```
1. 维护一个持久的 HeadlessInAppWebView
2. 加载包含 Turnstile 自动刷新模式的页面
3. cf_clearance 即将过期前自动刷新
4. 新 cookie 同步到 CookieJar
```

### 9.3 Cloudflare 相关的请求头

所有 XHR 请求必须设置以下请求头，缺失会被 Cloudflare Bot Management 识别：

```
Origin: {baseUrl}
Referer: {baseUrl}/
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: same-origin
```

---

## 10. 会话代管理与请求生命周期

### 10.1 核心机制

```
AuthSession {
    generation: int          // 当前代（初始为 0）
    cancelToken: CancelToken // 当前代的请求取消令牌

    advance() → int          // 递增 generation，取消旧 cancelToken，创建新的
    isValid(gen) → bool      // 检查 gen 是否等于当前 generation
}
```

### 10.2 请求打标

每个 HTTP 请求发出时：
1. 将当前 `generation` 戳入请求的 `extra` 字段
2. 合并请求自带的 `cancelToken`（如有）与会话的 `cancelToken`

### 10.3 响应校验

每个 HTTP 响应（成功或失败）返回时：
- 检查请求携带的 generation 是否仍然有效
- 无效则丢弃响应（转为 cancel 类型错误）
- 有效则正常处理

### 10.4 触发 advance() 的时机

| 时机 | 原因 |
|------|------|
| 登录收口时 | 防止登录前的旧响应（带旧 Set-Cookie）竞争写入 |
| 被动登出确认时 | 切断失效会话的所有在途请求 |
| 主动登出时 | 确保旧会话请求不再发出去 |

---

## 11. 平台差异处理

### 11.1 Cookie Domain 语义

| 平台 | WebView CookieManager 返回的 domain | 处理策略 |
|------|--------------------------------------|----------|
| iOS/macOS (WKWebView) | 完整属性（domain, path, secure 等） | 直接使用 |
| Android (WebView) | 新设备返回完整属性；旧设备 `GET_COOKIE_INFO` 不支持，domain 返回 null | 会话 Cookie 强制 host-only；其他 Cookie 继承 CookieJar 中的 domain 或兜底 `.{host}` |
| Windows (WebView2) | 走 CDP 协议读取 | 直接使用 |
| Linux (WebKitGTK) | 可能不返回 domain | 兜底 `.{host}` |

### 11.2 Cookie 回放方式

| 平台 | 回放方式 |
|------|----------|
| Android | 原生平台通道 → `CookieManager.setCookie(url, rawSetCookie)` |
| iOS/macOS | 原生平台通道 → `HTTPCookie.parse` → `WKHTTPCookieStore.setCookie` |
| Windows | CDP `Network.setCookie` |
| Linux | `soup_cookie_jar_set_cookie` 或 `getAllCookies` 兜底 |

### 11.3 特殊处理

- **Android WebAuthn/PassKey**：需通过平台通道显式启用 Web Authentication API
- **hCaptcha 无障碍**：仅在 Android 和 Windows 可用（Apple 平台 WKWebView 从底层阻止跨域 iframe 中的第三方 Cookie 访问）
- **Windows WebView2 环境**：需确保 CookieManager、InAppWebView、HeadlessInAppWebView 共享同一个 WebView2 环境和 userDataFolder
- **Windows/Linux 滚动修复**：部分平台 WebView 存在滚动穿透问题，需注入 CSS/JS 修复

---

## 12. 安全注意事项

### 12.1 凭证安全

- 用户名和密码必须存储在平台安全存储中（Keychain / Keystore / Credential Manager）
- JS 注入凭证时必须通过 `JSON.stringify` 转义，防止 XSS 注入攻击
- 日志中只记录 token 的长度和存在性，不记录实际值

### 12.2 Cookie 安全

- `_t` cookie 是 HttpOnly 的，JS 无法通过 `document.cookie` 读取
- 只能通过 WebView CookieManager API 或 CDP 协议读取
- CookieJar 文件应存储在应用私有目录

### 12.3 请求安全

- 所有请求必须设置正确的 `Origin`、`Referer`、`Sec-Fetch-*` 头
- CSRF Token 遵循 Discourse 官方前端策略
- 登录/登出状态变更时立即切断旧请求，防止状态不一致

---

## 13. 完整流程时序图

```
用户          登录页(WebView)         CookieJar         HTTP层           服务端
 │               │                     │                │                │
 │  点击登录      │                     │                │                │
 │──────────────→│                     │                │                │
 │               │  Cookie回放          │                │                │
 │               │←────────────────────│                │                │
 │               │  hCaptcha Cookie注入 │                │                │
 │               │────┐                │                │                │
 │               │←───┘                │                │                │
 │               │  加载 /login         │                │                │
 │               │─────────────────────────────────────────────────────→│
 │               │←────────────────────────────────────────────────────│
 │               │  注入脚本(预加载/指纹/自动填充)                        │
 │               │────┐                │                │                │
 │               │←───┘                │                │                │
 │  输入凭证      │                     │                │                │
 │──────────────→│  (自动填充/手动输入)  │                │                │
 │  点击登录按钮   │                     │                │                │
 │──────────────→│  捕获凭证→安全存储    │                │                │
 │               │  POST /session      │                │                │
 │               │─────────────────────────────────────────────────────→│
 │               │  302 → 首页          │                │                │
 │               │←────────────────────────────────────────────────────│
 │               │  Set-Cookie: _t=xxx  │                │                │
 │               │                     │                │                │
 │               │  [检测到 currentUsername + _t]        │                │
 │               │                     │                │                │
 │               │  边界同步: WebView→CookieJar          │                │
 │               │────────────────────→│                │                │
 │               │  提取CSRF Token      │                │                │
 │               │  会话代递增(切断旧请求)│                │                │
 │               │  等待指纹上报(≤15s)   │                │                │
 │               │  读取预加载数据       │                │                │
 │               │                     │                │                │
 │  关闭登录页    │                     │                │                │
 │←──────────────│                     │                │                │
 │               │                     │  后台: hydrate预加载数据          │
 │               │                     │                │                │
 │  已登录状态    │                     │  后续请求携带Cookie+CSRF          │
 │←──────────────────────────────────────────────────│                │
 │               │                     │  GET/POST ...  │                │
 │               │                     │                │───────────────→│
```

---

## 附录 A：关键 API 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `/login` | GET | 登录页面（WebView 加载） |
| `/session/email-login/{token}` | GET | 邮箱一键登录 |
| `/session/current.json` | GET | 验证当前会话是否有效（probe） |
| `/session/csrf.json` | GET | 获取 CSRF Token |
| `/session/{username}` | DELETE | 主动登出 |

## 附录 B：关键 HTTP 响应头

| 响应头 | 说明 |
|--------|------|
| `discourse-logged-out` | Discourse 标记用户已登出（BAD_TOKEN 场景） |
| `x-discourse-username` | 当前请求对应的用户名 |
| `Set-Cookie: _t=...` | 会话 Token |

## 附录 C：Discourse 前端关键 DOM 元素

| 元素 | ID / Selector | 用途 |
|------|---------------|------|
| 用户名输入框 | `#login-account-name` | 自动填充 |
| 密码输入框 | `#login-account-password` | 自动填充 |
| 登录按钮 | `#login-button` | Hook 凭证捕获 |
| CSRF Token | `meta[name="csrf-token"]` | 提取 CSRF |
| 当前用户名 | `meta[name="current-username"]` | 登录状态检测 |
| 预加载数据 | `[data-preloaded]` | 首页数据提取 |
| Discourse 初始化 | `#data-discourse-setup` | 站点配置提取 |

## 附录 D：错误码与处理

| 场景 | 状态码 | 响应体 | 处理 |
|------|--------|--------|------|
| CSRF Token 无效 | 403 | `["BAD CSRF"]` | 清空 CSRF → 刷新 → 重试一次 |
| 未登录 | 200/4xx | `{"error_type": "not_logged_in"}` | 强信号 → probe |
| Token 失效 | 200/4xx | Header: `discourse-logged-out` | 强/弱信号 → strike → probe |
| Cloudflare 拦截 | 403 | Turnstile Challenge | 弹出验证 → 同步 cookie → 重试 |
