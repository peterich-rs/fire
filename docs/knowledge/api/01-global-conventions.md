# 全局约定与拦截器链

> 对应 FluxDO 源文档第 1-3 节

---

## 1. 服务端点

| 服务 | Base URL |
|------|----------|
| Discourse 主站 | `https://linux.do` |
| LDC Credit | `https://credit.linux.do` |
| CDK | `https://cdk.linux.do` |
| Connect OAuth | `https://connect.linux.do` |
| GitHub API | `https://api.github.com` |
| 表情包市场 | `https://s.pwsh.us.kg`（可配置） |

---

## 2. 全局请求 Header

以下 Header 由 `DiscourseService` 构造时和 `RequestHeaderInterceptor` 自动注入，**所有 Discourse API 请求**均携带：

```
Accept: application/json, text/javascript, */*; q=0.01
Accept-Language: zh-CN,zh;q=0.9,en;q=0.8
X-Requested-With: XMLHttpRequest
User-Agent: <动态获取的 WebView UA，降级为 Chrome 131>
X-CSRF-Token: <从 /session/csrf 获取或从 HTML meta 提取>
Origin: https://linux.do
Referer: https://linux.do/
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: same-origin
Discourse-Present: true
Discourse-Logged-In: true  （仅已登录时）
```

### 移动端额外 Header（Android/iOS）

```
Sec-CH-UA: <由 ua_client_hints 包生成>
Sec-CH-UA-Mobile: ?
Sec-CH-UA-Platform: "<OS>"
Sec-CH-UA-Platform-Version: "<version>"
```

---

## 3. Cookie 管理

- 使用 `CookieJar` 管理所有 Cookie
- 关键 Cookie：
  - `_t` — 会话 token
  - `_forum_session` — 论坛会话
  - `cf_clearance` — Cloudflare 验证通过凭证
- 请求时由 `AppCookieManager`（基于 CookieJar）自动注入 `Cookie` Header
- 重定向时清除旧 `Cookie` Header，由 CookieManager 重新注入

---

## 4. 超时配置

| Dio 实例 | 连接超时 | 接收超时 |
|-----------|---------|---------|
| DiscourseService | 30s | 30s |
| PreloadedDataService | 30s | 30s |
| MessageBus 长轮询 | 30s | **60s** |
| 表情包市场 | 15s | 15s |

---

## 5. 通用响应状态码处理

| 状态码 | 处理方式 |
|--------|---------|
| 200-399 | 正常处理（重定向 301/302/307/308 由 RedirectInterceptor 手动处理） |
| 403 + `["BAD CSRF"]` | Rust 清空 CSRF token → 重新获取 `/session/csrf` → 重试原请求（仅一次） |
| 403/429 + Cloudflare HTML | Rust 记录 CF 信号；前台请求可调用平台 challenge handler，回灌新 `cf_clearance` 后自动重试一次；否则返回 `CloudflareChallenge` |
| 429 | 解析 `Retry-After` Header 或响应体中的等待时间 → 抛出 `RateLimitException` |
| 401/403 + `not_logged_in` | 强 auth signal → probe `/session/current.json` → 仅在 probe invalid 或 escalated inconclusive 时被动登出 |
| 401/403 + `discourse-logged-out` | 强 auth signal → 1 次即触发 probe；不直接清会话 |
| 2xx + `discourse-logged-out` | 弱 auth signal → 记录 strike，拦截 `_t` / `_forum_session` 删除，累计 2 次后 probe |
| 502/503/504 | 重试（最多 3 次，间隔 1s/2s/4s），耗尽后抛出 `ServerException` |

---

## 6. 通用响应 Header 处理

| 响应 Header | 处理方式 |
|-------------|---------|
| `discourse-logged-out` | `2xx` 记为弱信号；`401/403` 记为强信号；只有 probe 能最终决定是否登出 |
| `x-discourse-username` | 更新本地缓存的用户名 |
| `Set-Cookie: _t=...` | 更新 Rust CookieJar；若成功响应同时带 `discourse-logged-out`，会话 cookie 删除会被忽略并交由 probe 决策 |
| `Retry-After` | 429 响应中解析等待秒数 |

---

## 7. 并发控制

- **最大并发请求数**：3（可配置，`RequestSchedulerConfig.maxConcurrent`）
- **滑动窗口速率限制**：6 请求 / 3 秒（可配置）
- **优先级**：POST/PUT/DELETE/PATCH > 普通 GET > 静默请求（`isSilent: true`）
- MessageBus 长轮询不参与并发限制（`maxConcurrent: null`）

---

## 8. 请求体编码

除非特别说明：
- **POST/PUT/DELETE** 请求使用 `application/x-www-form-urlencoded` 编码
- 文件上传使用 `multipart/form-data`
- 少数接口使用 `application/json`（会在各接口中单独标注）

---

## 9. 拦截器链

所有 Discourse API 请求经过以下拦截器链（按执行顺序）：

```
 1. RequestEpochGuard            — 会话 epoch 守卫，丢弃过期响应
 2. FireCommonHeaderInterceptor  — User-Agent、CSRF、Sec-Fetch-*、登录标记注入
 3. FireSessionCookieJar         — Cookie ingress/egress 与同站点约束
 4. Rust CSRF retry wrapper      — 缺失 token 预刷新 + BAD CSRF 单次重试
 5. Auth signal / probe policy   — strong/weak signal、冷却期、被动登出
 6. Cloudflare challenge handler — 前台 WebView 验证完成后回灌 `cf_clearance` 并重试一次
 7. Trace / diagnostics          — 请求日志、网络追踪、host breadcrumbs
```

### 各拦截器职责详解

| # | 拦截器 | 职责 |
|---|--------|------|
| 1 | SessionGuardInterceptor | 检查会话是否已过期（通过 session generation），若已过期则直接取消请求 |
| 2 | DiscourseService 业务拦截器 | 检查认证状态、同步 token、处理 CSRF 403 错误并自动重试 |
| 3 | RequestSchedulerInterceptor | 实现并发控制和滑动窗口限速，按优先级排队请求 |
| 4 | AppCookieManager | 基于 CookieJar 自动注入和管理请求的 Cookie Header |
| 5 | CronetFallbackInterceptor | 当 Cronet 引擎出错时，自动降级到默认 HTTP 客户端 |
| 6 | RetryInterceptor | 对 429（限流）和 502/503/504（服务端错误）自动重试，含指数退避 |
| 7 | RequestHeaderInterceptor | 注入 User-Agent、CSRF Token、Sec-Fetch-* 等必要请求头 |
| 8 | RedirectInterceptor | 手动处理 301/302/307/308 重定向（清除旧 Cookie Header 后重新注入） |
| 9 | ErrorInterceptor | 将 429/502/503/504 转换为自定义异常，并显示 Toast 提示 |
| 10 | CfChallengeInterceptor | 检测 Cloudflare 挑战页面，触发 Turnstile 验证流程 |
| 11 | NetworkLogInterceptor | 记录请求和响应日志，用于调试 |

---

## 10. 请求配置工厂

```
DiscourseDio.create({
  baseUrl,            // 默认 "https://linux.do"
  connectTimeout,     // 默认 30s
  receiveTimeout,     // 默认 30s
  defaultHeaders,     // 自定义默认请求头
  maxConcurrent,      // 并发限制，null 表示不限制
  enableRetry,        // 是否启用自动重试（默认 true）
  enableCfChallenge,  // 是否启用 CF 验证拦截器（默认 true）
  enableCookies,      // 是否启用 Cookie 管理（默认 true）
})
```
