[返回总览](../backend-api.md)

# 接入基础与约定

本页聚焦接入 Fire 后端能力时最先要确认的共性信息：服务入口、鉴权方式、默认请求头、内容类型、推荐调用顺序和实现注意事项。

## Base URL

| 服务 | Base URL | 说明 |
| --- | --- | --- |
| 主论坛 | `https://linux.do` | Discourse 主站 |
| MessageBus | `https://linux.do` 或 `siteSettings.long_polling_base_url` | 长轮询实时消息 |
| LDC OAuth / 打赏 | `https://credit.linux.do` | 积分/打赏相关 |
| CDK OAuth | `https://cdk.linux.do` | CDK 授权相关 |
| OAuth 授权确认 | `https://connect.linux.do` | OAuth approve 跳转确认 |
| GitHub 更新检查 | `https://api.github.com` | 辅助接口 |
| 贴纸市场 | `https://s.pwsh.us.kg` | 辅助接口，可配置 |

## 主站认证方式

主站接口使用 Cookie Session 鉴权，客户端依赖的关键 Cookie：

- `_t`: Discourse 登录态
- `_forum_session`: 论坛会话
- `cf_clearance`: Cloudflare 挑战通过后的 Cookie

写操作通常还需要 CSRF Token：

- 获取方式 1：`GET /session/csrf`
- 获取方式 2：首页 HTML 中 `<meta name="csrf-token" ...>`

## 主站通用请求头

主站 JSON/XHR 接口默认请求头：

```http
Accept: application/json;q=0.9, text/plain;q=0.8, */*;q=0.5
Accept-Language: zh-CN,zh;q=0.9,en;q=0.8
X-Requested-With: XMLHttpRequest
User-Agent: <浏览器风格 UA>
Origin: https://linux.do
Referer: https://linux.do/
Cookie: _t=...; _forum_session=...; cf_clearance=...
X-CSRF-Token: <csrf-token>
```

已登录时客户端还会附带：

```http
Discourse-Logged-In: true
Discourse-Present: true
```

补充说明：

- 非 `GET` 请求默认需要 `X-CSRF-Token`
- 首页 HTML 请求不带 `X-Requested-With`，`Accept` 为 `text/html`，但仍会带浏览器风格 `User-Agent` 与 `Accept-Language`
- 宿主登录/验证 WebView 应尽量使用系统浏览器环境：iOS 使用默认持久化 `WKWebsiteDataStore`、浏览器兼容 UA、JavaScript、新窗口处理和同一浏览器上下文内的 Cookie；Android 使用持久化 `WebView` Cookie、JavaScript、DOM storage、AndroidX WebKit Safe Browsing，并禁止非 Web scheme、file/content 访问和 mixed content；iOS 当前默认使用 Mobile Safari 风格 UA，并在登录同步时把实际 `navigator.userAgent` 保存进共享会话
- 这不能绕过第三方 OAuth 的嵌入式浏览器限制。Google OAuth 在 `WKWebView` 里可能直接返回 `disallowed_useragent`；如要支持这类登录，需要系统认证会话 / Safari fallback，并且还要有服务端 redirect 或 Cookie 交换能力把登录态带回 Fire 可读取的会话。
- MessageBus 请求不需要 CSRF，但可能需要 `X-Shared-Session-Key`
- `X-SILENCE-LOGGER`、`Discourse-Background` 是客户端内部使用的静默/后台标记，不是通用必需头
- 当前 `linux.do` 接入中，过于“产品化”的 UA（例如仅 `Fire/0.1`）可能拿到缺少 `data-preloaded` 的降级 HTML；Rust HTTP 栈应维持浏览器风格 fallback UA

## 常见 Content-Type

| 类型 | 使用场景 |
| --- | --- |
| `application/x-www-form-urlencoded` | 大多数 Discourse 写操作 |
| `application/json` | 书签批量操作、部分扩展接口 |
| `multipart/form-data` | 文件上传 |
| `text/html` | 首页预加载、Cloudflare 验证页 |
| `application/json` 流式/文本 | MessageBus 长轮询 |

## 常见认证失败回包

- Discourse 不一定用 `401` 表达登录失效；部分已认证接口会返回 `403`，Body 仍然是 JSON 错误包
- 当前在 `linux.do` 上已经观察到这类格式：

```json
{
  "errors": ["您需要登录才能执行此操作。"],
  "error_type": "not_logged_in"
}
```

- Fire 共享层把 `error_type == "not_logged_in"` 视为登录态失效信号，不按普通 `HttpStatus` 处理；宿主层应清理本地会话并拉起重新登录
- Fire 共享层只在 `403` 同时满足 `server: cloudflare`、`Content-Type: text/html`，并且带 `cf-mitigated: challenge` 或 HTML 中含 Cloudflare challenge 特征时，才分类为 `CloudflareChallenge`；普通 Discourse `403` 不应仅凭正文关键词触发 Cloudflare 恢复流程

## 推荐调用顺序

如果你要在其他技术栈复现 Fire 的主要能力，推荐的最小调用链路如下：

1. `GET /`
   获取首页 HTML，提取 `csrf-token`、`data-preloaded`，以及跨域长轮询场景下可能存在的 `shared_session_key`
2. 如需写操作，优先复用首页 HTML / 登录 WebView 中已有的 CSRF；缺失或收到 `BAD CSRF` 时再 `GET /session/csrf`
   获取最新 CSRF
3. 使用 Cookie Session 调用主站 API
4. 如需实时能力，先持久化 `siteSettings.long_polling_base_url`、`topicTrackingStateMeta`，以及跨域长轮询场景下可能存在的 `shared_session_key`
5. 使用单例 `clientId` 调用 `POST /message-bus/{clientId}/poll`
6. 如遇 Cloudflare 挑战，宿主先删除 WebView Cookie Store 中旧的 `cf_clearance`，再在宿主 auth WebView 的 LinuxDo 登录上下文中完成验证；当登录页达到普通登录同步按钮的同一套可用条件后，把浏览器 Cookie 批量同步回共享层并重试原操作

## 已知实现细节

- 写接口大量依赖 `application/x-www-form-urlencoded`，不要默认全部发 JSON
- MessageBus 仅在独立长轮询域名场景下必须带 `X-Shared-Session-Key`；同域 `linux.do` 站点通常不会下发该字段
- 主站写操作需要 `_t` Cookie 和 `X-CSRF-Token` 同时存在才最稳妥
- `/posts.json` 同时承担“发主题”“发回复”“发私信”三种语义，依靠 Body 字段区分
- 首页 HTML 的 `data-preloaded` 是重要的启动数据源，不只是页面渲染产物
- 当前客户端通常先从首页 HTML 或登录 WebView 提取 CSRF；不是每次写操作固定先调一次 `/session/csrf`。当认证 Cookie 已可用但 CSRF 缺失时，Rust 会在首个认证写请求前主动刷新，且并发的自动刷新会合并为一次 in-flight 请求。
- 某些接口还需要 `username`、`notification_channel_position` 等运行时数据，这些通常来自 `preloaded.currentUser`、登录页 meta 或响应头
