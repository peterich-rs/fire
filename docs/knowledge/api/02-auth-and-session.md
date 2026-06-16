# 认证与会话 API

LinuxDo 使用 Discourse 的 Cookie 会话认证。Fire 的密码登录边界是原生
用户名/密码表单加最小 WebView JS 登录事务：WebView 负责登录 CSRF、
hCaptcha create 和 `/session.json`，Rust 负责结果解析、cookie 仲裁和会话
收口。

OAuth、PassKey、邮件链接等浏览器型能力应单独设计。它们不能把 Ember
`/login` 页面重新变成密码登录的主路径。

## 1. 当前会话

```http
GET /session/current.json
```

用于验证当前 Cookie 是否对应一个有效登录用户。

### Query Parameters

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `_` | integer | 否 | 防缓存时间戳 |

### Request

```http
GET https://linux.do/session/current.json
Accept: application/json, text/javascript, */*; q=0.01
Cookie: _t=...; _forum_session=...
```

This endpoint does not require a CSRF token.

### Response

Authenticated response:

```json
{
  "current_user": {
    "id": 12345,
    "username": "example",
    "name": "Example User",
    "avatar_template": "/user_avatar/linux.do/example/{size}/1.png",
    "trust_level": 2
  }
}
```

Unauthenticated or invalid sessions can appear as:

- `404`
- `401` / `403`
- `200` with no `current_user`
- A structured error body such as `{"error_type":"not_logged_in"}`

Recommended normalization:

| Result | Meaning |
|---|---|
| `current_user` object exists | Session is valid |
| `404`, `not_logged_in`, or no `current_user` | Session is invalid |
| Network failure, Cloudflare challenge, timeout | Session state is inconclusive; do not destructively log out based on this result alone |

## 2. Conservative Session Probe

Use `GET /session/current.json` as the authority before clearing local session state.

Recommended policy:

- Treat `not_logged_in` and `401/403` responses with `discourse-logged-out` as strong invalid-session signals.
- Treat successful responses that include `discourse-logged-out` as weak signals.
- Do not log out solely because of `BAD CSRF`, ordinary `403 invalid_access`, a Cloudflare challenge, or a transient network error.
- Fold concurrent probes so multiple failing requests trigger only one session verification.
- Keep `cf_clearance` when clearing a user session; it is a Cloudflare clearance cookie, not a Discourse identity cookie.

This is a client policy recommendation. The backend authority remains the `/session/current.json` response.

## 3. CSRF Token

```http
GET /session/csrf
```

Fetches a CSRF token suitable for mutating Discourse requests.

### Request

```http
GET https://linux.do/session/csrf
Accept: application/json, text/javascript, */*; q=0.01
Cookie: _forum_session=...; _t=...
```

### Response

```json
{
  "csrf": "xxxxxxxxxxxxxxxxxxxx"
}
```

### Strategy

| Case | Recommended handling |
|---|---|
| Bootstrap HTML has `<meta name="csrf-token">` | Cache that token |
| No cached token before a mutating request | Fetch `/session/csrf` |
| `403` body contains `BAD CSRF` | Clear cached token, fetch a new token, retry the original request once |
| `/session/csrf` succeeds but response includes `discourse-logged-out` | Keep the token but verify session separately before destructive logout |

## 4. Logout

```http
DELETE /session/{username}
```

Logs out the current Discourse session on the server.

### Path Parameters

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `username` | string | 是 | 当前登录用户名 |

### Request

```http
DELETE https://linux.do/session/example
X-CSRF-Token: <csrf token>
Cookie: _t=...; _forum_session=...
```

### Response

Discourse logout responses vary by server version and plugin state. Clients should treat any `2xx` response as successful logout and then clear local identity cookies such as `_t` and `_forum_session`. Preserve unrelated cookies such as `cf_clearance` unless the user requested a full site-data reset.

## 5. Login Boundary

Password login is not a Rust/OpenWire JSON-login flow. The robust path is:

1. Ensure `cf_clearance` exists, running manual WebView verification if needed.
2. Open a minimal same-origin WebView document, not the Ember `/login` page.
3. Let WebView fetch `/session/csrf`, create the hCaptcha session cookie, and
   post `/session.json`.
4. Parse the raw session response through the shared Rust classifier.
5. On success, extract `_t`, `_forum_session`, `cf_clearance`, and related
   cookies from the live WebView before disposal.
6. Apply extracted cookies as trusted writes and finalize login with a bounded
   bootstrap refresh.

See [../discourse-webview-login-guide.md](../discourse-webview-login-guide.md)
for the stack-neutral password-login protocol.
