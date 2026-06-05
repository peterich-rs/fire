# 应用更新检查、表情包市场、预加载首页 HTML、调用顺序

> 对应 FluxDO 源文档第 26-29 节

---

# 第 26 节：应用更新检查 API

---

## 26.1 检查最新版本

```
GET https://api.github.com/repos/Lingyan000/fluxdo/releases/latest
```

**场景**：应用启动时自动检查更新，或用户手动触发。

**Request Headers：**

```
User-Agent: FluxDO-App
Accept: application/vnd.github.v3+json
If-None-Match: <ETag>  （有缓存时）
```

**Response (200)：** GitHub Release JSON。

**Response (304)：** 无变更，使用缓存。

- 支持 ETag 缓存
- 缓存有效期：1 小时
- 缓存到 SharedPreferences

---

# 第 27 节：表情包市场 API

**Base URL：** `https://s.pwsh.us.kg`（可配置，存储在 SharedPreferences）

**使用独立 Dio 实例**，不需要 Discourse 认证。

---

## 27.1 获取市场索引

```
GET {baseUrl}/assets/market/index/index.json
```

---

## 27.2 获取分页数据

```
GET {baseUrl}/assets/market/index/page-{page}.json
```

---

## 27.3 获取分组详情

```
GET {baseUrl}/assets/market/group-{groupId}.json
```

**缓存策略：** 所有请求结果缓存到 SharedPreferences，24 小时过期。网络失败时使用过期缓存兜底。

---

# 第 28 节：预加载首页 HTML

---

## 28.1 获取首页 HTML

```
GET https://linux.do
```

**场景**：应用启动时获取首页 HTML，从中提取预加载数据（`data-preloaded` 属性），避免后续额外 API 请求。

**Request Headers：**

```
Accept: text/html
Accept-Language: zh-CN,zh;q=0.9,en;q=0.8
```

**Request Options：** `skipCsrf: true`（首页请求不需要 CSRF token）

**Response (200)：** HTML 字符串。

**从 HTML 中提取的信息：**

| 信息 | 提取方式 | 用途 |
|------|---------|------|
| CSRF Token | `<meta name="csrf-token" content="...">` | 保存到 CsrfTokenService |
| Shared Session Key | `data-shared-session-key` | MessageBus 跨域认证 |
| Turnstile Sitekey | `data-turnstile-sitekey` | CF 验证 |
| Base URI | `data-discourse-setup` 中的 `baseUri` | 子路径前缀 |
| CDN URL | `data-discourse-setup` 中的 `cdnUrl` | 静态资源 CDN |
| S3 CDN URL | `data-discourse-setup` 中的 `s3CdnUrl` | 上传文件 CDN |
| 预加载数据 | `<div data-preloaded="...">` | 解析为 JSON，包含以下数据块 |

**预加载数据块：**

| 数据块 | 说明 |
|--------|------|
| `currentUser` | 当前登录用户信息 |
| `siteSettings` | 站点设置（包含各种最小长度、是否启用 AI 搜索等） |
| `site` | 站点信息（分类列表、标签、post_action_types 等） |
| `topicList` | 首页话题列表 |
| `topicTrackingStateMeta` | MessageBus 频道初始 message_id |
| `topicTrackingStates` | 话题追踪状态（未读、新话题等） |
| `customEmoji` | 自定义 emoji 列表 |
| `enabledReactions` | 可用的回应表情列表 |

---

# 第 29 节：调用顺序与场景总结

---

## 29.1 应用启动流程

```
1. AppConstants.initUserAgent()          — 获取 WebView UA
2. PreloadedDataService.refresh()        — GET / (首页 HTML)
   ├─ 提取 CSRF Token
   ├─ 提取 CF Turnstile Sitekey
   ├─ 提取预加载数据 (currentUser, siteSettings, site, topicList, etc.)
   └─ CfClearanceRefreshService.start()  — 启动 CF 自动续期
3. DiscourseService.isLoggedIn()         — GET /session/current.json（验证会话）
4. MessageBusService.subscribe()         — POST /message-bus/{clientId}/poll（开始长轮询）
```

---

## 29.2 登录流程

```
1. WebView 加载 OAuth 登录页面
2. 登录成功后 WebView 拿到 _t Cookie
3. 边界同步 Cookie（_t, _forum_session）到 CookieJar
4. DiscourseService.onLoginSuccess(tToken)
5. PreloadedDataService.hydrateFromHtml(html) 或 refresh()
6. MessageBusService 配置并开始轮询
```

---

## 29.3 话题详情页流程

```
1. GET /t/{topicId}.json                 — 获取话题详情
2. GET /t/{topicId}/posts.json           — 按需加载帖子
3. POST /topics/timings                  — 上报阅读时间（定期）
4. GET /presence/get                     — 获取在线用户
5. POST /presence/update                 — 进入/离开频道
6. POST /clicks/track                    — 链接点击追踪（异步）
```

---

## 29.4 发布内容流程

```
1. GET /drafts/{draftKey}.json           — 获取已有草稿
2. POST /drafts.json                     — 保存草稿（编辑过程中定期保存）
3. POST /uploads.json                    — 上传图片/附件
4. POST /uploads/lookup-urls             — 解析短链接
5. GET /u/search/users                   — @提及用户搜索
6. GET /composer/mentions                — 验证 @提及
7. POST /posts.json                      — 发布话题/回复
8. DELETE /drafts/{draftKey}.json        — 删除草稿
```

---

## 29.5 搜索流程

```
1. GET /search.json                      — 全文搜索
   或 GET /discourse-ai/embeddings/semantic-search — AI 语义搜索
2. GET /tags/filter/search               — 标签搜索
3. GET /u/recent-searches.json           — 获取搜索历史
4. DELETE /u/recent-searches.json        — 清空搜索历史
```

---

## 29.6 通知流程

```
1. MessageBus /notification/{userId}     — 实时推送新通知
2. GET /notifications?recent=true        — 快捷面板获取最近通知
3. PUT /notifications/mark-read          — 标记已读
4. GET /notifications                    — 完整分页列表
```

---

## 29.7 登出流程

```
1. AuthSession.advance()                 — 切断所有在途请求
2. MessageBusService.stopAll()           — 停止长轮询
3. CfClearanceRefreshService.stop()      — 停止 CF 续期
4. DELETE /session/{username}            — 服务端登出（可选）
5. 清除内存状态（token、username、缓存）
6. CookieJar 清除（保留 cf_clearance）
7. CsrfTokenService.reset()              — 清除 CSRF token
8. PreloadedDataService.reset()          — 清除预加载数据
9. PreloadedDataService.refresh()        — 重新加载（匿名状态）
10. 广播状态变更
```
