# 全局 HTTP 约定

本文描述 LinuxDo Discourse 站点及相邻服务的通用 HTTP 约定。内容只约束协议行为，不要求客户端使用特定语言、网络库、状态管理方式或 UI 框架。

## 1. 服务端点

| 服务 | Base URL | 说明 |
|---|---|---|
| Discourse 主站 | `https://linux.do` | 论坛 HTML、JSON API、会话 Cookie、上传、MessageBus |
| LDC Credit | `https://credit.linux.do` | LDC OAuth、余额信息、打赏 |
| CDK | `https://cdk.linux.do` | CDK OAuth、用户信息 |
| Connect | `https://connect.linux.do` | Connect HTML 统计页，如信任等级相关统计 |

可配置的第三方静态资源服务，例如表情包市场，不属于 LinuxDo 核心论坛协议；如需使用，应在具体产品中单独配置。

## 2. 常用请求头

Discourse API 通常期望请求看起来接近同源浏览器请求：

```http
Accept: application/json, text/javascript, */*; q=0.01
Accept-Language: zh-CN,zh;q=0.9,en;q=0.8
X-Requested-With: XMLHttpRequest
User-Agent: <browser-compatible user agent>
Origin: https://linux.do
Referer: https://linux.do/
```

Mutating requests should include:

```http
X-CSRF-Token: <csrf token>
```

Some browser-like clients also send Fetch Metadata and Client Hints headers:

```http
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: same-origin
Sec-CH-UA: <client hints>
Sec-CH-UA-Mobile: ?0 or ?1
Sec-CH-UA-Platform: "<platform>"
```

Authenticated browser requests may include these Discourse-specific hints:

```http
Discourse-Present: true
Discourse-Logged-In: true
```

These hints are not a substitute for cookies; the server still authenticates by session cookies.

## 3. Cookies

Important cookies:

| Cookie | Purpose |
|---|---|
| `_t` | Authenticated Discourse session token |
| `_forum_session` | Forum session state |
| `cf_clearance` | Cloudflare challenge clearance |

Clients should store cookies with their original domain, path, expiry, Secure, HttpOnly, and SameSite attributes when available. WebView/browser login flows and programmatic HTTP requests must share the same effective cookie state for `https://linux.do`.

Recommended policy:

- Send cookies according to RFC cookie matching rules for each request URL.
- Process all `Set-Cookie` response headers, including on redirects.
- Do not manually replay stale `Cookie` headers across redirects; recompute cookies for each target URL.
- Preserve `cf_clearance` across user logout unless the user explicitly clears all site data.
- Treat session-cookie deletion in a response that also carries `discourse-logged-out` as an auth signal, not necessarily final proof that the session is invalid.

## 4. CSRF

Discourse mutating endpoints generally require a CSRF token in `X-CSRF-Token`.

Sources:

- Bootstrap HTML: `<meta name="csrf-token" content="...">`
- API: `GET /session/csrf`

Recommended refresh behavior:

1. If a mutating request has no token, fetch `/session/csrf` before sending it.
2. If the server returns `403` with `BAD CSRF`, clear the cached token, fetch a new one, and retry the original request once.
3. Do not treat `BAD CSRF` by itself as proof that the user is logged out.

## 5. Content Types

Unless an endpoint says otherwise:

| Request type | Encoding |
|---|---|
| Most `POST` / `PUT` / `DELETE` Discourse actions | `application/x-www-form-urlencoded` |
| Uploads | `multipart/form-data` |
| Bulk operations and some plugin APIs | `application/json` when explicitly documented |
| Ordinary reads | Query string parameters |

Array parameters use repeated form/query keys, for example:

```text
post_ids[]=1&post_ids[]=2
tags[]=rust&tags[]=ios
options[]=choice_a&options[]=choice_b
```

Clients must use an encoder that preserves repeated keys.

## 6. Timeouts And Rate Limits

Suggested client defaults:

| Request family | Connect timeout | Read timeout |
|---|---:|---:|
| Ordinary Discourse API | 30s | 30s |
| Bootstrap HTML | 30s | 30s |
| MessageBus long polling | 30s | 60s |
| Optional static asset indexes | 15s | 15s |

Suggested anti-burst policy:

- Limit concurrent ordinary API requests.
- Use lower priority for silent/background refreshes than for user-initiated actions.
- Exclude MessageBus long-poll requests from ordinary API concurrency slots.
- On `429`, honor `Retry-After` when present and add jitter before retrying.

These are client safety recommendations rather than server-declared limits.

## 7. Status And Header Signals

| Signal | Meaning | Recommended handling |
|---|---|---|
| `200-399` | Request succeeded or was followed through redirects | Parse response and process cookies/headers |
| `403` + `BAD CSRF` | CSRF token rejected | Refresh CSRF and retry once |
| `401` / `403` + `not_logged_in` | Strong auth-invalid signal | Verify with `GET /session/current.json` before clearing local state |
| `discourse-logged-out` response header | Logout/session-invalid signal; can appear on both success and failure responses | Treat `401/403` as strong, `2xx` as weak; verify before destructive logout |
| `429` | Rate limited | Honor `Retry-After`; retry later if the action is retryable |
| Cloudflare challenge HTML or headers | Bot/challenge gate, not a forum API response | Complete challenge in a WebView, sync fresh `cf_clearance`, freeze business requests while verification is active, then retry eligible foreground requests once |
| `502` / `503` / `504` | Transient upstream failure | Retry idempotent or explicitly safe requests with backoff |

Useful response headers:

| Header | Use |
|---|---|
| `Set-Cookie` | Update cookie store |
| `Retry-After` | Rate-limit wait seconds or HTTP date |
| `x-discourse-username` | Authenticated username hint |
| `discourse-logged-out` | Session-invalid signal requiring verification |

## 8. Redirects

Clients should follow standard HTTP redirects with a conservative policy:

- Preserve method/body only where the redirect status code allows it.
- Limit redirect count.
- Do not downgrade HTTPS to HTTP.
- Remove sensitive headers such as `Authorization` and manually supplied `Cookie` when crossing origins.
- Recalculate cookies for the redirected URL.

## 9. Error Body Shape

Discourse errors commonly return one of these shapes:

```json
{ "errors": ["message"], "error_type": "invalid_access" }
```

```json
["BAD CSRF"]
```

```json
{ "success": false, "errors": ["message"] }
```

Clients should parse structured fields first, then fall back to a generic HTTP error message.

## 10. Detailed Session Guides

- [../discourse-webview-login-guide.md](../discourse-webview-login-guide.md)
  defines the password-login WebView JS contract.
- [../discourse-cloudflare-challenge-guide.md](../discourse-cloudflare-challenge-guide.md)
  defines challenge detection, manual verification, and request freezing.
- [../discourse-cookie-session-state-guide.md](../discourse-cookie-session-state-guide.md)
  defines canonical cookie state, freshness, priming, sweep, and self-healing.
