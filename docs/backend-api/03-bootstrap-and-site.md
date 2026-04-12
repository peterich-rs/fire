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
  - iOS 当前把登录页收口做成“自动探测、手动 Sync”：只有同时拿到 `current-username`、有效 `_t` / `_forum_session` Cookie，以及可复用的首页 bootstrap HTML 时，才允许用户点击“完成登录”
  - iOS 当前在登录页优先通过浏览器上下文内的 `fetch("/")` 抓首页 HTML；只有这份首页 HTML 不够完整时，才回退到当前页面 `document.documentElement.outerHTML`
  - 在把 bootstrap 视为“已就绪”前，应该确认至少拿到了当前用户、站点级 `site` 元数据（分类/标签能力）和 `siteSettings`（最小长度、reactions、长轮询域等）；缺失时继续回源 `GET /` 刷新，而不要仅凭 `hasPreloadedData=true` 就跳过
  - 当前 Fire 实现还会在首页 bootstrap 仍缺少 `site` 元数据时自动补一次 `GET /site.json`，用于回填 `categories`、`top_tags`、`can_tag_topics`
  - iOS 当前在真正提交登录前后都会先后各做一次平台 Cookie 刷新：先把 `WKHTTPCookieStore` 里的同站 Cookie 回灌到共享层，再执行 `sync_login_context` / bootstrap 刷新，最后再把浏览器最新 Cookie 状态回灌一次，确保 `_t`、`_forum_session`、`cf_clearance` 以浏览器为准
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

### 会话失效信号

- Linux.do/Discourse 不一定等写接口才暴露“登录已失效”
- 当前观测里，普通成功响应也可能直接宣告登录态失效，例如：
  - `discourse-logged-out: 1`
  - `Set-Cookie: _t=; path=/; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT`
- 客户端不要继续把这种响应后的会话当作“仍可写入”；应立即清掉本地登录态并提示重新登录
- Fire 共享层现在把 `discourse-logged-out`、清空 `_t` / `_forum_session` 的 `Set-Cookie`、`error_type=not_logged_in` 统一视为登录失效信号，并先推进内部 session epoch，再清掉本地登录态
- Fire 共享层现在会在 `sync_login_context`、`apply_platform_cookies` 导致 auth Cookie 轮换时、显式登出、被动失效时推进 session epoch；晚到的旧请求响应仍可写入非认证 Cookie（例如 `cf_clearance`），但不得再覆盖 `_t` / `_forum_session`，也不得把旧会话“复活”
- 当前 `BAD CSRF` 只触发一次性 CSRF 刷新与单次重试；如果同一请求同时已经暴露登录失效信号，则优先按登录失效收口，而不是继续保留本地登录态
- 否则后续最常见的表现是：前面的列表、详情等匿名可读请求仍然成功，但稍后的 `/topics/timings`、点赞、回复等写请求才返回 `403` / `error_type=not_logged_in`

### `GET /challenge`

- 用途：打开 Cloudflare 挑战页面，通常在 WebView 中人工完成
- 认证：匿名可访问
- 响应：HTML 页面，不是 JSON

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
  - 当前 Fire iOS 一期没有直接在宿主里回放这条 `rc` 内部接口；iOS 改为在会话已连接、已有 `cf_clearance`、且首页 bootstrap 已暴露 Turnstile `sitekey` 时，启动一个离屏 `WKWebView` 定时加载首页，并把浏览器里更新后的 Cookie 再次同步回共享层
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
