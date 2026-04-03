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
  - 在把 bootstrap 视为“已就绪”前，应该确认至少拿到了当前用户、站点级 `site` 元数据（分类/标签能力）和 `siteSettings`（最小长度、reactions、长轮询域等）；缺失时继续回源 `GET /` 刷新，而不要仅凭 `hasPreloadedData=true` 就跳过
  - 当前 Fire 实现还会在首页 bootstrap 仍缺少 `site` 元数据时自动补一次 `GET /site.json`，用于回填 `categories`、`top_tags`、`can_tag_topics`

### `GET /session/csrf`

- 用途：获取 CSRF Token
- 认证：通常匿名和登录态都可访问
- 响应：

```json
{
  "csrf": "token"
}
```

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

## 站点信息、分类、标签、表情

### `GET /site.json`

- 用途：获取分类、热门标签、帖子动作类型等站点级信息
- 认证：匿名可访问
- 关键返回字段：
  - `categories`
  - `top_tags`
  - `can_tag_topics`
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
