# Fire API 总览

## 服务端点

| 服务 | Base URL |
|------|----------|
| Discourse 主站 | `https://linux.do` |
| LDC Credit | `https://credit.linux.do` |
| CDK | `https://cdk.linux.do` |
| Connect OAuth | `https://connect.linux.do` |
| GitHub API | `https://api.github.com` |
| 表情包市场 | `https://s.pwsh.us.kg`（可配置） |

## 核心约定（摘要）

- **Content-Type**: POST/PUT/DELETE 使用 `application/x-www-form-urlencoded`，文件上传使用 `multipart/form-data`，少数接口使用 `application/json`
- **全局 Header**: Accept, Accept-Language, X-Requested-With, User-Agent, X-CSRF-Token, Origin, Referer, Sec-Fetch-*, Discourse-Present, Discourse-Logged-In
- **Cookie 管理**: `_t`（会话 token）、`_forum_session`、`cf_clearance`（Cloudflare）
- **并发控制**: 最大并发 3, 滑动窗口 6请求/3秒
- **超时**: 连接 30s, 接收 30s (MessageBus 60s)

## API 模块索引

### 核心模块

| 模块 | 详细文档 | 说明 |
|------|---------|------|
| 全局约定与拦截器 | [api/01-global-conventions.md](api/01-global-conventions.md) | Base URL、Headers、Cookie、超时、并发控制、拦截器链 |
| 认证与会话管理 | [api/02-auth-and-session.md](api/02-auth-and-session.md) | 登录状态检查、Session Probe、登出、CSRF Token |
| 话题 | [api/03-topics.md](api/03-topics.md) | 话题列表、详情、创建、更新、通知级别、AI摘要 |
| 帖子 | [api/04-posts.md](api/04-posts.md) | 回复、编辑、删除、点赞、回应、举报、答案接受 |
| 用户 | [api/05-users.md](api/05-users.md) | 用户信息、统计、动态、关注、私信、徽章、邀请 |
| 搜索 | [api/06-search.md](api/06-search.md) | 全文搜索、AI语义搜索、标签搜索、@提及、搜索历史 |
| 通知 | [api/07-notifications.md](api/07-notifications.md) | 获取通知、标记已读 |
| MessageBus | [api/12-messagebus.md](api/12-messagebus.md) | 长轮询实时消息推送、频道管理 |

### 扩展模块

| 模块 | 详细文档 | 说明 |
|------|---------|------|
| 文件上传 | [api/08-file-upload.md](api/08-file-upload.md) | 上传文件、批量解析短链接 |
| 投票 | [api/09-polls.md](api/09-polls.md) | 投票、撤销投票、话题投票、投票用户列表 |
| Presence 与分类标签 | [api/10-presence-and-categories.md](api/10-presence-and-categories.md) | 阅读时间、在线状态、分类通知、书签、草稿 |
| 扩展功能 | [api/11-extended-features.md](api/11-extended-features.md) | 模板、嵌套视图、Policy、Emoji、Boost |
| LDC/CDK OAuth 与打赏 | [api/13-ldc-cdk-oauth.md](api/13-ldc-cdk-oauth.md) | LDC/CDK OAuth授权、用户信息、打赏 |
| 其他 API | [api/14-misc-apis.md](api/14-misc-apis.md) | 更新检查、表情包市场、预加载HTML、调用顺序 |

## 关键流程概览

### 应用启动

1. 获取 WebView UA
2. GET / (预加载首页 HTML，提取 CSRF/预加载数据)
3. GET /session/current.json (验证会话)
4. POST /message-bus/{clientId}/poll (开始长轮询)

### 登录

1. WebView OAuth → 获取 _t Cookie
2. 同步 Cookie 到 CookieJar
3. 刷新预加载数据
4. 启动 MessageBus

### 话题详情

1. Primary source: `GET /t/{topicId}.json` 或 `GET /t/{topicId}/{postNumber}.json` 获取 header/body/raw `post_stream.stream`
2. Raw append: `GET /t/{topicId}/posts.json?post_ids[]=...` 只按 raw stream slice 批量补齐 `loaded_posts`
3. Presentation: Rust 基于 `raw_stream_ids + loaded_posts` 构建树状 reply rows；平台只消费结果，不反向驱动分页
4. Sidecar: `POST /topics/timings`、`GET /presence/get`、`POST /presence/update`、AI summary、MessageBus

### 发布内容

1. 获取/保存草稿
2. 上传图片
3. @提及搜索与验证
4. POST /posts.json → 发布
5. 删除草稿
