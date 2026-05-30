[返回总览](../backend-api.md)

# 引导与站点信息

本页覆盖主站 `https://linux.do` 的启动阶段接口和站点级公共接口，主要用于初始化客户端运行环境、提取预加载数据和同步分类/标签等基础配置。

## 引导与会话

### `GET /`

- 用途：获取首页 HTML，并从 HTML 中提取启动数据
- 认证：匿名可用，登录后返回带当前用户信息的预加载数据
- 关键请求头：
  - `Accept: text/html`
  - `Accept-Language: zh-CN,zh;q=0.9,en;q=0.8`
  - `User-Agent: <浏览器风格 UA>`
- 关键 HTML 元信息：
  - `<meta name="csrf-token" content="...">`
  - `<meta name="shared_session_key" content="...">`，仅跨域长轮询场景通常可见；同域 `linux.do` 站点常为空
  - `<meta name="discourse-base-uri" content="...">`
  - Cloudflare Turnstile 容器上的 `data-sitekey="..."`
  - `id="data-discourse-setup"` 元素上的：
    - `data-cdn`
    - `data-s3-cdn`
    - `data-s3-base-url`
  - `data-preloaded="..."`，其中包含：
    - `currentUser`
    - `siteSettings`
    - `site`
    - `topicTrackingStateMeta`
    - `topicTrackingStates`
    - `customEmoji`
    - `topicList` / `topic_list` / `latest`
- 客户端接入备注：
  - 登录回调页、用户页、话题页等“非首页” HTML 里也可能带 `data-preloaded`，但有时只包含 `currentUser` 等局部字段，不一定带完整的 `site` / `siteSettings`
  - 某些 LinuxDo 页面里，`data-preloaded.currentUser`、`siteSettings`、`site`、`topicTrackingStateMeta` 本身不是对象，而是“JSON 字符串”；客户端在提取字段前需要先解包这层字符串
  - iOS 当前把登录页收口做成“自动探测、按 readiness 同步”：实时探测会先轻量检查当前页的用户名 / bootstrap 标记与同站 auth Cookie，只在 auth Cookie 已就绪但当前页元数据仍不完整时，才补一次浏览器上下文内的首页 `fetch("/")`；只有最终同时拿到 `current-username`、有效 `_t` / `_forum_session` Cookie，以及可复用的首页 bootstrap HTML 时，才允许普通登录点击“完成登录”
  - iOS 登录与 Cloudflare 验证 WebView 使用同一套 auth-browser profile：默认持久化 `WKWebsiteDataStore`、不自定义进程池、浏览器兼容 UA、JavaScript、新窗口处理、inline media 设置、调试可检查 WebView，以及少量浏览器兼容 polyfill；完成登录时再读取实际 `navigator.userAgent`，通过 `sync_login_context.browser_user_agent` 交给共享层保存，并由 `SessionState.browser_user_agent` 暴露回宿主
  - iOS 登录 `WKWebView` 现在会显式开启 `window.open` / 新窗口请求，并把 `target="_blank"` 或脚本弹出的登录跳转收口到当前浏览器上下文继续导航，避免第三方登录选择页因为缺少 `WKUIDelegate` 而直接失效
  - Android 登录 `WebView` 当前显式启用 AndroidX WebKit Safe Browsing、持久化 Cookie、JavaScript 和 DOM storage，并禁止非 Web scheme、file/content 访问和 mixed content；沉浸式壳层下登录顶部 chrome 会应用真实状态栏 inset，保证关闭和登录同步按钮可点击
  - iOS 的交互式 Cloudflare 恢复不再单独打开 `/challenge` 页面，也不再把 topic-detail 触发的恢复默认带回登录页：话题详情内触发时打开对应 topic HTML 页 `https://linux.do/t/{slug}/{topicId}`，缺少 slug 时退回 `https://linux.do/t/{topicId}`；其他恢复默认使用站点 root，并继续复用同一个 auth-browser profile 与登录页 readiness 探测。当页面满足普通登录“完成登录”按钮的同一套可用条件（WebView 已停止 loading、用户名、同站 auth Cookie、可复用 bootstrap、且当前没有同步任务）时，会自动执行一次 `completeLogin` 并恢复原始操作
  - 这个 WebView profile 只用于让 LinuxDo 登录、Cloudflare challenge 和普通站内跳转尽量接近系统 `WKWebView` 浏览器环境，不能绕过第三方 OAuth 的嵌入式浏览器限制。Google OAuth 仍可能在 `WKWebView` 中返回 `disallowed_useragent`；如需支持 Google 登录，需要系统认证会话 / Safari fallback，并配套服务端 redirect 或 Cookie 交换能力。
  - iOS 当前在真正提交登录时仍会优先通过浏览器上下文内的 `fetch("/")` 抓首页 HTML；只有这份首页 HTML 不够完整时，才回退到当前页面 `document.documentElement.outerHTML`，并会用优选后的 HTML 回填缺失的 `current-username` / `csrf-token`
  - 在把 bootstrap 视为“已就绪”前，应该确认至少拿到了当前用户、站点级 `site` 元数据（分类/标签能力）和 `siteSettings`（最小长度、reactions、长轮询域等）；显式 bootstrap 刷新路径缺失时继续回源 `GET /` 刷新，而不要仅凭 `hasPreloadedData=true` 就跳过。iOS 冷启动热路径例外：它不再为了补齐这些字段主动 native `GET /`，而是先恢复 Cookie/持久化 snapshot 并加载首页列表。
  - 当前 Fire 实现还会在首页 bootstrap 仍缺少 `site` 元数据时自动补一次 `GET /site.json`，用于回填 `categories`、`top_tags`、`can_tag_topics`
  - iOS 当前在真正提交登录时会先把 `WKWebView` 里抓到的同站 auth Cookie 批量回灌到共享层，再执行 `sync_login_context` / bootstrap 刷新，并在把状态交给 UI 前额外保证 CSRF 已可用；Android 登录完成后也会做同样的 CSRF 补齐；因此主界面不会再看到“已登录但 `csrf` 为空”的中间态
  - 宿主层不再按同名 Cookie 做“best score”选优；Cookie 归并由共享层按 `(name, normalizedDomain, path)` 处理，其中 `normalizedDomain` 会去掉前导 `.`。因此 `linux.do` 与 `.linux.do` 的同名同路径 Cookie 只保留最后写入的一份，请求发送阶段再按 URL/path/domain 规则决定可发送项。
  - 当前 Fire 还会从 `siteSettings` 提取 composer 约束：
    - `min_post_length`
    - `min_topic_title_length`
    - `min_first_post_length`
    - `min_personal_message_title_length`
    - `min_personal_message_post_length`
    - `default_composer_category`
  - 如果站点首页 bootstrap 暂时没有返回私信最小长度，Fire 当前会回退到：
    - `min_personal_message_title_length = 2`
    - `min_personal_message_post_length = 10`
  - 当前 Fire 还会从 `site.categories[]` 提取 create-topic 所需的分类约束：
    - `topic_template`
    - `minimum_required_tags`
    - `required_tag_groups`
    - `allowed_tags`
    - `permission`
    - `notification_level`

### `GET /session/csrf`

- 用途：获取 CSRF Token
- 认证：通常匿名和登录态都可访问
- 响应：

```json
{
  "csrf": "token"
}
```

- 兼容性说明：
  - Fire 共享层会把 `csrf` 按标量字段解析；字符串数字也会接受
  - `csrf` 缺失、为 `null`、空字符串或根节点不是对象时，Rust 会把它视为无效 CSRF 响应而不是继续带着脏值写回会话

### `DELETE /session/{username}`

- 用途：登出
- 认证：需要已登录 Cookie
- `X-CSRF-Token`：需要
- 路径参数：
  - `username: string`
- `username` 常见来源：
  - 登录页 HTML 中 `meta[name="current-username"]`
  - 任意主站响应头 `x-discourse-username`
  - 首页 `data-preloaded.currentUser.username`

### 会话失效与 auth 轮换

- Linux.do/Discourse 不一定等写接口才暴露登录态问题，但这里要区分“显式失效”和“auth 上下文轮换”两类现象。
- 当前 Fire 仍把这些当作强失效信号：
  - `401` / `403` 且 body 里有 `error_type=not_logged_in`
  - 成功响应或 `401` 响应上的 `discourse-logged-out: 1`
- 普通资源权限 `403` 不能只凭 `discourse-logged-out: 1` 或 auth Cookie 删除判定为后台剔除登录态；例如 `error_type=invalid_access` 仍按普通 `HttpStatus` 暴露，保留本地会话。
- 成功响应里的 auth Cookie 删除不再单独作为登出依据；仅靠 `Set-Cookie: _t=; Max-Age=0` 或 `_forum_session=; Max-Age=0`，Fire 只保留诊断线索，不会直接清掉本地登录态。
- Fire 共享层现在会在 `sync_login_context`、`apply_platform_cookies`、以及网络 `Set-Cookie` 导致 auth key `(_t, _forum_session)` 变化时推进 session epoch；晚到的旧请求响应仍会作为 stale response 整批丢弃。
- 如果 auth key 变化但同一批更新没有带来新的 CSRF，Fire 会立即清掉旧 CSRF，让下一次认证写请求先刷新 token。
- 如果网络侧只轮换了 `_t` / `_forum_session` 的一部分，Fire 会记录一次运行时 recovery hint，并把必要的 host cookie resync 延迟到下一次认证写请求，而不是在读路径里立刻探测 WebKit。
- 当前 `BAD CSRF` 仍只触发一次性 CSRF 刷新与单次重试；如果同一请求同时已经暴露强失效信号，则优先按登录失效收口。Rust 的自动 CSRF 刷新会做 in-flight 去重，避免多个认证写请求同时发现缺 token 时重复打 `/session/csrf`。
- 因此后续常见表现不只有“更早一步已明确失效”，也可能是“更早一步成功读请求触发了 partial auth rotation，首个写请求才真正暴露问题”。

### 交互式 Cloudflare 恢复

- 用途：在浏览器上下文内完成 Cloudflare 验证并把新的浏览器 Cookie 回灌到共享 Rust session。
- Fire iOS 的交互式恢复会先删除 `WKHTTPCookieStore` 中旧的 `cf_clearance`，再打开触发场景对应的浏览器 HTML URL：topic detail 使用 `/t/{slug}/{topicId}` 或 `/t/{topicId}`，首页/列表/通知等非 topic 场景使用站点 root；显式登录仍使用 `/login`。恢复 WebView 继续复用登录页 readiness 探测，当页面拿到用户名、同站 auth Cookie 和可复用 bootstrap，且 WebView 不再 loading 后，宿主按普通登录按钮可用状态自动执行登录同步并重试原操作。
- Fire Android 不自动关闭挑战 WebView，也不在挑战完成后立即重试当前 native 操作：topic detail 在当前详情页 toolbar 下加载 `https://linux.do/t/{topicId}`，其他页面加载 `https://linux.do/`；一旦 WebView Cookie 中出现 `cf_clearance`，宿主调用 `sync_login_context` 同步到 Rust，WebView 保持可见，后续新开的 native 页面继续走原生读取链路。
- 认证：匿名可访问
- 响应：HTML 页面，不是 JSON
- 识别：共享层只把 `403` 且响应头指向 Cloudflare HTML challenge 的回包归类为 `CloudflareChallenge`；优先使用 `cf-mitigated: challenge`，缺失时再用 HTML 中的 `cf_chl_opt`、`challenge-platform`、`Just a moment` 等特征兜底

### `POST /cdn-cgi/challenge-platform/h/g/rc/{chlId}`

- 用途：Cloudflare Turnstile/挑战续期内部流程
- 不是稳定公开 API；当前客户端只在拦截到浏览器运行时的 Turnstile 请求后才会回放
- 认证：依赖现有站点上下文、Cookie，以及最终把新的 `cf_clearance` 回灌到 HTTP CookieJar
- 前置条件：
  - 已能访问首页并提取 `data-sitekey`
  - 已进入 Cloudflare 验证上下文
  - 运行时拿到 `chlId`
  - 运行时请求体里可能带 `secondaryToken`
- Body（当前客户端从被拦截的请求体里动态提取，不是静态常量）：

```json
{
  "secondaryToken": "optional",
  "sitekey": "required"
}
```

- 常见请求头：
  - `Origin: https://linux.do`
  - `Referer: https://linux.do/`
- 备注：
  - 当前客户端没有把这一步当成独立业务接口暴露，而是视为 Cloudflare 内部续期流程
  - 当前客户端回放请求时未显式固定 `Content-Type` 为 `application/x-www-form-urlencoded`；拦截到的原始运行时请求体更接近 JSON 形态
  - 当前 Fire iOS 会在会话已连接、已有 `cf_clearance`、且首页 bootstrap 已暴露 Turnstile `sitekey` 时，启动一个离屏 `WKWebView` 承载 Turnstile widget；这个离屏 WebView 使用会话里捕获的浏览器 UA，缺失时回退到登录页同款 Mobile Safari 风格 UA；宿主在 `api.js` 加载前注入 `fetch` 拦截脚本，捕获 `/cdn-cgi/challenge-platform/.../rc/...` 请求后由 `URLSession` 代发，再把真实响应回注到页面，最后把更新后的 Cookie 同步回共享层
  - 交互式恢复与离屏续期不同：恢复前会删除 WebView Store 里的旧 `cf_clearance`，但完成条件不再是单独观察新的 clearance；当前 iOS 入口以登录页 readiness 为准，同步完整浏览器 Cookie 批次后由共享层刷新 bootstrap / CSRF
  - 共享层仍会保留并发送 `cf_clearance`；挑战完成、平台 Cookie 读取、离屏 WebView 续期都仍属于宿主职责

## 站点信息、分类、标签、表情

### `GET /site.json`

- 用途：获取分类、热门标签、帖子动作类型等站点级信息
- 认证：匿名可访问
- 关键返回字段：
  - `categories`
  - `top_tags`
  - `can_tag_topics`
- 当前客户端额外消费的 `categories[]` 字段：
  - `topic_template`
  - `minimum_required_tags`
  - `required_tag_groups`
  - `allowed_tags`
  - `permission`
  - `notification_level`
- 补充说明：
  - 当前举报/Flag 流程优先使用首页 `data-preloaded.site.post_action_types`
  - 分类/热门标签能力也可参考 FluxDo 的做法：优先使用首页 `data-preloaded.site`，缺失时再回退到 `/site.json`
  - 若需要网络 fallback，可单独请求 `/post_action_types.json`

### `GET /emojis.json`

- 用途：获取表情分组
- 认证：匿名可访问
- 备注：
  - 该接口主要用于 emoji picker 分组
  - 自定义 emoji 渲染还依赖首页 `data-preloaded.customEmoji`，仅有 `/emojis.json` 不足以完全复现当前客户端行为
- 响应：

```json
{
  "people": [Emoji],
  "nature": [Emoji]
}
```

### `POST /category/{categoryId}/notifications`

- 用途：设置分类通知级别
- 认证：需要登录
- `Content-Type`: `application/x-www-form-urlencoded`
- `categoryId` 来源：
  - 首页 `data-preloaded.site.categories`
  - 或 `GET /site.json` 的 `categories`
- `notification_level` 取值：
  - `0`: muted
  - `1`: regular
  - `2`: tracking
  - `3`: watching
  - `4`: watching_first_post
- 当前共享 Rust 模型会从 `data-preloaded.site.categories[]` / `/site.json` 读取分类当前 `notification_level`，并通过 UniFFI 暴露给宿主；Android 主页面的分类通知入口会调用共享 `set_category_notification_level`，成功后强制刷新 bootstrap 以回灌服务端状态。
- Body：

```json
{
  "notification_level": 0
}
```

### `GET /bookmarks.json`

- 用途：通用书签列表接口
- 认证：需要登录
- Query：
  - `page?: integer`
- 响应：`TopicListResponse`
- 补充说明：
  - 当前独立“我的书签”页面主数据源是 `GET /u/{username}/bookmarks.json`，见 [05. 用户、搜索与通知](05-users-search-and-notifications.md)
  - `/bookmarks.json` 返回结构相对更浅，不是当前客户端书签页的主接口
