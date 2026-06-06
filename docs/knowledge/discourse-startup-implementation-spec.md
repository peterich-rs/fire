# Discourse 客户端启动阶段技术实现指引

> 本文档仅聚焦**从 App 启动到主界面就绪**这一阶段的技术细节，包括启动初始化顺序、首页请求、登录态判断、数据解析、MessageBus 初始化等。文档面向跨技术栈复刻，所有接口入参出参、数据结构、判断逻辑均给出完整细节。

---

## 目录

1. [启动阶段总览](#1-启动阶段总览)
2. [初始化顺序与依赖关系](#2-初始化顺序与依赖关系)
3. [首页 HTML 请求](#3-首页-html-请求)
4. [首页 HTML 解析](#4-首页-html-解析)
5. [data-preloaded 完整解析流程](#5-data-preloaded-完整解析流程)
6. [启动期登录态判断路径](#6-启动期登录态判断路径)
7. [GET /session/current.json 接口](#7-get-sessioncurrentjson-接口)
8. [GET /u/{username}.json 接口](#8-get-uusernamejson-接口)
9. [User 数据模型](#9-user-数据模型)
10. [CSRF Token 启动期获取与恢复](#10-csrf-token-启动期获取与恢复)
11. [Cookie 启动期恢复](#11-cookie-启动期恢复)
12. [cf_clearance 自动续期启动条件](#12-cf_clearance-自动续期启动条件)
13. [MessageBus 初始化](#13-messagebus-初始化)
14. [AppStateRefresher 全量刷新](#14-appstaterefresher-全量刷新)
15. [会话代管理](#15-会话代管理)
16. [启动期网络请求时序](#16-启动期网络请求时序)

---

## 1. 启动阶段总览

启动分为三个阶段，从第一个代码执行到主界面渲染完成：

```
阶段 A: main() 初始化（UI 框架渲染前）
  1. 基础框架 → 并行初始化（CookieJar, CSRF, prefs 等）
  2. 数据迁移（可能清空 Cookie → 需重新登录）
  3. 网络栈初始化
  4. 提前发起首页请求（与 UI 渲染并行，不阻塞）

阶段 B: Widget 树构建（UI 渲染）
  1. 引导页关卡 → 已完成引导则跳过
  2. 预热关卡 → 阻塞等待首页数据加载完成
     - 失败 → 显示错误页面（重试/退出登录/网络设置）

阶段 C: MainPage 就绪后
  1. 设置导航 context
  2. 初始化深度链接
  3. currentUserProvider 触发 → 可能调 /session/current.json
  4. 已登录 → 初始化 MessageBus 长轮询
  5. authStateProvider listener → AppStateRefresher.refreshAll()
```

---

## 2. 初始化顺序与依赖关系

### 2.1 同步初始化（无依赖，无 await）

```
1. UI 框架绑定初始化
2. 系统沉浸式模式设置
3. 语法高亮预热（后台，不阻塞）
4. 本地通知权限请求（后台，不阻塞）
5. 关闭 WebView DevTools
```

### 2.2 第一批并行初始化（Future.wait，无相互依赖）

| 序号 | 初始化项 | 产出 | 后续谁依赖 |
|------|---------|------|-----------|
| 1 | SharedPreferences 获取 | prefs 实例 | 几乎所有后续服务 |
| 2 | UserAgent 初始化 | 清理后的 UA 字符串 + Client Hints | 所有 HTTP 请求 |
| 3 | 日志写入器 | 日志实例 | 日志记录 |
| 4 | 代理证书 | 证书就绪 | DOH 网络 |
| 5 | CookieJar 初始化 | 持久化 Cookie 存储就绪 | 所有 Cookie 操作 |
| 6 | CSRF Token 恢复 | 从 Secure Storage 恢复上次 token | 所有非 GET 请求 |
| 7 | 时间工具 | 时区就绪 | 时间解析 |
| 8 | 桌面窗口管理器 | 窗口就绪 | 桌面平台 |

### 2.3 依赖 prefs 的串行步骤

```
AuthIssueNoticeService.initialize(prefs)
    ↓
桌面窗口状态恢复
    ↓
MigrationService.runAll(prefs)        ← 可能在网络服务启动前清空 Cookie
    ↓
第二批并行初始化（CF 日志、代理、Android CDP 等）
    ↓
网络栈顺序初始化:
  RhttpSettingsService → WebViewAdapterSettings → rhttp init → NetworkSettingsService
    ↓
连接服务（VPN、hCaptcha、cf_clearance 配置、连通性检查）
    ↓
下载服务
```

### 2.4 首页请求与 UI 并行

```
unawaited(PreloadedDataService().ensureLoaded())    ← 不阻塞，与 runApp 并行
    ↓
runApp()                                             ← 开始渲染 Widget 树
```

PreheatGate 中再次 `await ensureLoaded()`，复用已进行的请求（不会重复请求）。

---

## 3. 首页 HTML 请求

这是启动期**最核心**的网络请求。

### 3.1 请求

```
GET https://linux.do

请求头:
  Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
  Accept-Language: zh-CN,zh;q=0.9,en;q=0.8

请求 extra:
  skipCsrf: true        ← 首次请求尚无 CSRF token，跳过

Cookie: 自动携带 CookieJar 中已恢复的 _t, _forum_session 等
```

### 3.2 响应

```
Content-Type: text/html; charset=utf-8
```

响应体为完整 HTML 页面。

### 3.3 请求时机

| 时机 | 说明 |
|------|------|
| main() 尾部 | `unawaited(ensureLoaded())`，与 runApp 并行 |
| PreheatGate | `await ensureLoaded()`，复用 main() 的请求或重新发起 |

防重入：`_loading` 标志确保不会同时发起两个请求。

---

## 4. 首页 HTML 解析

从 HTML 中提取 6 类数据，按顺序处理：

### 4.1 CSRF Token

**提取方式**：正则匹配 `<meta>` 标签

```
正则: <meta[^>]+name=["']csrf-token["'][^>]+content=["']([^"']+)["']
大小写不敏感
```

**处理**：
- 对提取值做 HTML entity 解码：`&quot;` → `"`, `&amp;` → `&`, `&lt;` → `<`, `&gt;` → `>`, `&#39;` → `'`
- 写入 CsrfTokenService → 同时写入 Secure Storage（key: `linux_do_csrf_token`）

**示例**：
```html
<meta name="csrf-token" content="abc123def456">
```

### 4.2 Shared Session Key

**提取方式**：

```
正则: <meta[^>]+name=["']shared_session_key["'][^>]+content=["']([^"']+)["']
```

**处理**：
- HTML entity 解码
- 存入 `_sharedSessionKey`

**用途**：MessageBus 独立域名认证（如 `ping.linux.do`），独立域名时禁用 Cookie，改用 `X-Shared-Session-Key` 请求头。

### 4.3 Turnstile Sitekey

**提取方式**：

```
正则: data-sitekey="([0-9a-zA-Zx_-]+)"
```

**处理**：传入 CfClearanceRefreshService，用于 `cf_clearance` 自动续期。

### 4.4 Discourse Base URI

**提取方式**：

```
正则: <meta[^>]+name=["']discourse-base-uri["'][^>]+content=["']([^"']*)["']
```

**处理**：
- 空或 `/` → `_baseUri = ""`
- 否则标准化为 `/path` 格式（确保前缀 `/`，去除尾部 `/`）

### 4.5 CDN 配置

**提取方式**：先找 `data-discourse-setup` 标签

```
正则: id=["']data-discourse-setup["'][^>]*>
```

从标签内提取属性：

| data 属性 | 存入字段 | 示例 |
|----------|---------|------|
| `data-cdn` | `_cdnUrl` | `https://cdn.linux.do` |
| `data-s3-cdn` | `_s3CdnUrl` | `https://cdn3.linux.do` |
| `data-s3-base-url` | `_s3BaseUrl` | `//linuxdo-uploads.s3.linux.do` |

值以 `/` 结尾时去除尾部 `/`。

### 4.6 data-preloaded（核心！）

见下一节。

---

## 5. data-preloaded 完整解析流程

### 5.1 提取

```
正则: data-preloaded="([^"]*)"
```

从 HTML 的 `<div id="data-preloaded" data-preloaded="...">` 提取属性值。

### 5.2 解析步骤（建议在后台线程执行）

```
步骤 1: HTML entity 解码
  &quot; → "
  &amp;  → &
  &lt;   → <
  &gt;   → >
  &#39;  → '

步骤 2: 外层 JSON 解码
  得到 Map<String, dynamic>
  key 为数据类型名，value 为 JSON 字符串（或已解码的对象）

步骤 3: 内层 value JSON 解码
  遍历 Map，若 value 为 String 则再 jsonDecode 一次
  非 JSON 字符串保持原值
```

### 5.3 解析后的 Key 映射

| Key | 目标字段 | 类型 | 必需 | 说明 |
|-----|---------|------|------|------|
| `currentUser` | `_currentUser` | `Map<String, dynamic>` | 否 | 当前用户数据，**已登录时存在**。结构同 User.fromJson 的输入 |
| `siteSettings` | `_siteSettings` | `Map<String, dynamic>` | 否 | 站点设置 |
| `site` | `_site` | `Map<String, dynamic>` | 否 | 站点信息 |
| `topicTrackingStateMeta` | `_topicTrackingStateMeta` | `Map<String, dynamic>` | 否 | MessageBus 频道初始 message ID |
| `topicTrackingStates` | `_topicTrackingStates` | `List<Map<String, dynamic>>` | 否 | 话题追踪状态 |
| `customEmoji` | `_customEmoji` | `List<Map<String, dynamic>>` | 否 | 自定义 Emoji |
| `topicList` 或 `topic_list` 或 `latest` | `_topicListData` | `Map<String, dynamic>` | 否 | 首页话题列表（三个 key 任一） |

**重要**：`currentUser` 的存在与否是启动期判断登录态的**首要依据**。

### 5.4 siteSettings 重要子字段

| JSON Key | 类型 | 说明 |
|----------|------|------|
| `discourse_reactions_enabled_reactions` | `String` | `|` 分隔的 emoji 名称，如 `"heart\|+1\|laughing\|open_mouth"` |
| `long_polling_base_url` | `String?` | MessageBus 独立域名，如 `https://ping.linux.do`。无值或 `/` 表示使用主站 |
| `min_topic_title_length` | `int/String` | 话题标题最小长度，默认 15 |
| `min_personal_message_title_length` | `int/String` | 私信标题最小长度，默认 2 |
| `min_post_length` | `int/String` | 回复最小长度，默认 8 |
| `min_first_post_length` | `int/String` | 首帖最小长度，默认 20 |
| `min_personal_message_post_length` | `int/String` | 私信最小长度，默认 10 |
| `default_composer_category` | `int/String?` | 默认发帖分类 ID，≤0 视为未设置 |
| `ai_embeddings_semantic_search_enabled` | `bool?` | AI 语义搜索开关 |

### 5.5 site 重要子字段

| JSON Key | 类型 | 说明 |
|----------|------|------|
| `categories` | `List` | 分类列表，每个元素含 `id`, `name`, `slug`, `color` 等 |
| `top_tags` | `List` | 热门标签，元素为字符串或 `{name: "..."}` 对象 |
| `post_action_types` | `List` | 帖子操作类型（如举报原因） |
| `can_tag_topics` | `bool?` | 是否支持标签功能 |
| `system_user_avatar_template` | `String?` | 系统用户头像模板 |

### 5.6 topicTrackingStateMeta 格式

```json
{
  "/latest": 6855147,
  "/new": 104155,
  "/unread": 50023,
  "/topic_tracking_state": 3000001
}
```

key 为 MessageBus 频道名，value 为该频道当前的 `message_id`。订阅时使用此 ID 作为起始位置。

### 5.7 topicList 数据结构

```json
{
  "topic_list": {
    "topics": [
      {
        "id": 123,
        "title": "话题标题",
        "slug": "topic-slug",
        "category_id": 5,
        "posts_count": 42,
        "like_count": 10,
        ...
      }
    ]
  }
}
```

可能的外层 key：`topicList`、`topic_list`、`latest`（按顺序尝试）。

### 5.8 解析完成后

检查 `currentUser` 是否非空：
- **非空（已登录）** → 启动 `CfClearanceRefreshService().start()`（`cf_clearance` 自动续期）
- **空（未登录）** → 不启动续期

---

## 6. 启动期登录态判断路径

```
首页 HTML 请求完成 → 解析 data-preloaded
  │
  ├── currentUser 存在（最常见路径）
  │     → 已登录
  │     → 同步返回用户数据给 UI
  │     → 后台静默刷新（2 分钟冷却）
  │
  └── currentUser 不存在（未登录或 Cookie 失效）
        → CookieJar 中有 _t 吗？
            ├── 无 → 确认未登录
            └── 有 → 调 GET /session/current.json 服务端验证
                  ├── 有 current_user → 确认已登录
                  ├── 无 / 404 → 确认失效 → 执行登出
                  ├── 401/403 → 确认失效 → 执行登出
                  └── 网络异常 → 保守保留登录态
```

**关键设计**：首页 HTML 请求同时完成了 CSRF Token 获取和登录态快照两个目的。已登录用户的 `currentUser` 直接嵌入在 HTML 的 `data-preloaded` 中，无需额外 API 调用。

---

## 7. GET /session/current.json 接口

仅在**无预加载 currentUser 但 CookieJar 中有 _t** 时调用。

### 7.1 请求

```
GET /session/current.json?_=1717488000000

请求参数:
  _: int  =  当前毫秒时间戳（防缓存）

请求 extra:
  skipAuthCheck: true
  skipCsrf: true

请求头（有 _t cookie 时自动添加）:
  Discourse-Logged-In: true
  Discourse-Present: true

Cookie: 自动携带 CookieJar 中的 _t, _forum_session 等
```

### 7.2 响应

**200 + 有 current_user**（会话有效）：
```json
{
  "current_user": {
    "id": 12345,
    "username": "example",
    "name": "Example User",
    "avatar_template": "/user_avatar/linux.do/example/{size}/xxxxx.png",
    "trust_level": 2,
    "unread_notifications": 5,
    "unread_high_priority_notifications": 1,
    "all_unread_notifications_count": 8,
    "seen_notification_id": 99999,
    "notification_channel_position": 42,
    "status": {
      "description": " coding",
      "emoji": "💻"
    },
    "last_posted_at": "2026-06-01T12:00:00.000Z",
    "last_seen_at": "2026-06-04T08:30:00.000Z",
    "created_at": "2024-01-15T00:00:00.000Z",
    ...更多字段见第 9 节
  }
}
```

**200 + 无 current_user**（确认失效）：
```json
{}
```

**404**：无用户（Discourse session_controller.rb:676），确认失效

**401/403**：明确拒绝，确认失效

**网络异常**：保守返回已登录（避免网络抖动导致误判）

### 7.3 处理

| 结果 | 动作 |
|------|------|
| 有 current_user | 更新内存 `_tToken`（从 CookieJar 刷新）、更新 `_username`、重置 auth strike |
| 无 / 404 / 401/403 | 执行登出流程 |
| 网络异常 | 保守保留本地登录态 |

---

## 8. GET /u/{username}.json 接口

在 `currentUserProvider` 后台静默刷新时调用，或 UI 进入用户主页时调用。

### 8.1 请求

```
GET /u/{username}.json

请求头:
  Accept: application/json
  X-Requested-With: XMLHttpRequest

Cookie: 自动携带
```

### 8.2 响应

```json
{
  "user": {
    "id": 12345,
    "username": "example",
    ...完整 User 字段见第 9 节
  }
}
```

### 8.3 去重

相同 username 的并发请求合并为同一个（`_activeUserRequests` Map），避免重复请求。

---

## 9. User 数据模型

### 9.1 完整字段

以下字段同时适用于 `/session/current.json` 的 `current_user` 和 `/u/{username}.json` 的 `user`：

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | `int` | `id` | 用户 ID |
| username | `String` | `username` | 用户名 |
| name | `String?` | `name` | 显示名称 |
| avatarTemplate | `String?` | `avatar_template` | 头像模板，含 `{size}` 占位符 |
| animatedAvatar | `String?` | `animated_avatar` | 动画头像 URL |
| trustLevel | `int` | `trust_level` | 信任等级 (0-4) |
| bio | `String?` | `bio_cooked` > `bio_excerpt` > `bio_raw` | 个人简介，优先级递减 |
| bioCooked | `String?` | `bio_cooked` | 简介 HTML |
| bioRaw | `String?` | `bio_raw` | 原始简介 |
| cardBackgroundUploadUrl | `String?` | `card_background_upload_url` | 卡片背景 |
| profileBackgroundUploadUrl | `String?` | `profile_background_upload_url` | 个人页背景 |
| unreadNotifications | `int` | `unread_notifications` | 未读通知数 |
| unreadHighPriorityNotifications | `int` | `unread_high_priority_notifications` | 高优先级未读 |
| allUnreadNotificationsCount | `int` | `all_unread_notifications_count` | 总未读 |
| seenNotificationId | `int` | `seen_notification_id` | 已查看通知 ID |
| notificationChannelPosition | `int` | `notification_channel_position` | 通知频道位置，默认 -1 |
| status | `UserStatus?` | `status` | 在线状态 |
| lastPostedAt | `DateTime?` | `last_posted_at` | 最后发帖（UTC） |
| lastSeenAt | `DateTime?` | `last_seen_at` | 最后在线（UTC） |
| createdAt | `DateTime?` | `created_at` | 注册时间（UTC） |
| location | `String?` | `location` | 所在地 |
| website | `String?` | `website` | 网站 |
| websiteName | `String?` | `website_name` | 网站名 |
| flairUrl | `String?` | `flair_url` | 徽章图标 URL |
| flairName | `String?` | `flair_name` | 徽章名 |
| flairBgColor | `String?` | `flair_bg_color` | 徽章背景色 |
| flairColor | `String?` | `flair_color` | 徽章前景色 |
| flairGroupId | `int?` | `flair_group_id` | 徽章组 ID |
| canFollow | `bool?` | `can_follow` | 可关注 |
| isFollowed | `bool?` | `is_followed` | 已关注 |
| totalFollowers | `int?` | `total_followers` | 粉丝数 |
| totalFollowing | `int?` | `total_following` | 关注数 |
| canSendPrivateMessages | `bool?` | `can_send_private_messages` | 可发私信 |
| canSendPrivateMessageToUser | `bool?` | `can_send_private_message_to_user` | 可给该用户发私信 |
| gamificationScore | `int?` | `gamification_score` | 积分 |
| muted | `bool?` | `muted` | 已静音 |
| ignored | `bool?` | `ignored` | 已忽略 |
| canMuteUser | `bool?` | `can_mute_user` | 可静音 |
| canIgnoreUser | `bool?` | `can_ignore_user` | 可忽略 |
| suspendReason | `String?` | `suspend_reason` | 封禁原因 |
| suspendedTill | `DateTime?` | `suspended_till` | 封禁截止（UTC） |
| silenceReason | `String?` | `silence_reason` | 禁言原因 |
| silencedTill | `DateTime?` | `silenced_till` | 禁言截止（UTC） |

### 9.2 UserStatus

| 字段 | 类型 | JSON 键 |
|------|------|---------|
| description | `String?` | `description` |
| emoji | `String?` | `emoji` |

### 9.3 fromJson 特殊处理

| 字段 | 处理 |
|------|------|
| avatarTemplate, animatedAvatar, cardBackgroundUploadUrl, profileBackgroundUploadUrl, flairUrl | 经过 CDN URL 解析：相对路径 → CDN 域名拼接 |
| bio, bioCooked | HTML 修复：`src="/..."` → `src="https://linux.do/..."` |
| bio | 取值优先级：`bio_cooked` > `bio_excerpt` > `bio_raw` |
| 所有时间字段 | UTC 解析后自行 toLocal 转换，不直接用 `DateTime.parse` |

### 9.4 头像 URL 计算

```
优先使用 animatedAvatar（非空时直接用作 URL）
否则使用 avatarTemplate：
  将 {size} 替换为实际像素值（默认 120）
  若为相对路径，拼接 baseUrl
  若以 // 开头，补充 https:
```

### 9.5 缓存 User（启动期优化）

启动时将 User 序列化到 SharedPreferences（key: `current_user_cache`），下次启动在首页请求完成前可先从缓存返回，避免短暂显示"未登录"。

缓存仅保存部分字段：`id`, `username`, `name`, `avatar_template`, `animated_avatar`, `trust_level`, `status`(简化), `flair_*`, `gamification_score`

---

## 10. CSRF Token 启动期获取与恢复

### 10.1 恢复（main() 阶段）

```
CsrfTokenService.init():
  1. 从 Secure Storage 读取 key=linux_do_csrf_token
  2. 非空 → 写入内存 _csrfToken
  3. 空 → _csrfToken = null（后续首次 POST 时自动获取）
```

### 10.2 从首页 HTML 获取（Preload 阶段）

首页 HTML 解析时提取 `<meta name="csrf-token">` → `CsrfTokenService.setCsrfToken(token)`

同时写入 Secure Storage 持久化。

### 10.3 运行时按需获取

若 POST 请求发出前 CSRF token 仍为空：

```
GET /session/csrf

请求 extra: {skipCsrf: true, skipAuthCheck: true, isSilent: true, skipScheduler: true}

响应: {"csrf": "new_token_string"}

→ setCsrfToken(newToken)
```

去重：并发调用共享同一个请求。

---

## 11. Cookie 启动期恢复

### 11.1 CookieJar 初始化

```
1. 获取应用文档目录
2. 创建 .cookies/ 子目录
3. 初始化 EnhancedPersistCookieJar（文件持久化）
4. 初始化 RawSetCookieQueue（从 .cookies/pending_set_cookies.json 恢复待回放队列）
```

启动后 CookieJar 中已包含上次关闭时持久化的所有 Cookie（`_t`, `_forum_session`, `cf_clearance` 等）。

### 11.2 数据迁移可能清空 Cookie

`MigrationService.runAll(prefs)` 执行 4 个迁移项，部分会清空所有 Cookie：
- Cookie 格式切换 → 清空
- 双通道切换 → 清空
- storageKey 放宽 → 清空

如果迁移导致 Cookie 被清空，设置 `requiresRelogin = true`，在 PreheatGate 中弹窗提示用户重新登录。

### 11.3 首页请求自动携带 Cookie

首页 `GET https://linux.do` 请求时，HTTP 拦截器自动从 CookieJar 加载 Cookie 设置到请求头。服务端根据 `_t` cookie 返回对应的用户数据。

---

## 12. cf_clearance 自动续期启动条件

```
首页数据解析完成后:
  if (_currentUser != null)    ← 已登录
    CfClearanceRefreshService().start()
  else                         ← 未登录
    不启动
```

原因：未登录状态下的 CF 刷新请求可能干扰 auth 判断。

续期服务行为：
- 维持一个 Headless WebView
- 加载含 Turnstile 自动刷新模式的页面
- 使用从首页 HTML 提取的 sitekey
- `cf_clearance` 即将过期前自动刷新
- 新 cookie 通过 CDP 协议同步到 CookieJar

---

## 13. MessageBus 初始化

### 13.1 触发时机

MainPage `initState` 中监听 `currentUserProvider`（`fireImmediately: true`），当首次返回非 null 用户时触发。

### 13.2 初始化步骤

```
1. 配置 MessageBus:
   - longPollingBaseUrl: 从 siteSettings.long_polling_base_url 获取
   - sharedSessionKey: 从首页 HTML 提取

2. 获取频道初始 ID:
   - 从 topicTrackingStateMetaProvider 读取
   - 格式: {"/latest": 6855147, "/new": 104155, ...}

3. 批量订阅频道（使用初始 ID）:
   - /latest
   - /new
   - /unread
   - /topic_tracking_state

4. 订阅通知频道（需要 userId）:
   - /notification/{userId}
   - /notification-alert/{userId}
```

### 13.3 长轮询协议

```
POST /message-bus/{clientId}/poll

Content-Type: application/x-www-form-urlencoded

请求体: /latest=6855147&/new=104155&/unread=50023&/topic_tracking_state=3000001

请求头（额外）:
  X-Shared-Session-Key: {key}     ← 仅独立域名时
  X-SILENCE-LOGGER: true
  Discourse-Background: true

请求 extra: {isSilent: true, skipCsrf: true}
responseType: stream

响应: 流式文本，| 分隔
每块为 JSON 数组:
  [{"channel": "/latest", "message_id": 6855148, "data": {...}}, ...]

特殊频道 /__status:
  data 为 Map: {"/latest": 6855147, ...} → 更新 lastMessageId
```

### 13.4 独立域名配置

当 `long_polling_base_url` 有值时（如 `https://ping.linux.do`）：
- 轮询请求发往独立域名
- **禁用 Cookie 发送**
- 改用 `X-Shared-Session-Key` 认证

---

## 14. AppStateRefresher 全量刷新

### 14.1 触发时机

`authStateProvider` 发出事件时（登录/登出后），触发 `refreshAll()`。

### 14.2 去抖

2 秒内重复调用直接跳过。

### 14.3 第一批（立即执行，核心数据）

| Provider | API | 说明 |
|----------|-----|------|
| `currentUserProvider` | `/session/current.json` 或 `/u/{username}.json` | 当前用户 |
| `categoriesProvider` | 首页预加载 | 分类列表 |
| `topicTrackingStateMetaProvider` | 首页预加载 | MessageBus 频道 ID |
| `topicTrackingStateProvider` | 首页预加载 | 话题追踪状态 |
| 当前 tab 的话题列表 | `/latest.json` 等 | 首页话题 |

### 14.4 第二批（延迟 1 秒，避免并发过多触发风控）

| Provider | API | 说明 |
|----------|-----|------|
| `userSummaryProvider` | `/u/{username}/summary.json` | 用户统计 |
| `notificationListProvider` | `/notifications.json` | 通知列表 |
| `tagsProvider` | `/tags.json` | 标签 |
| `canTagTopicsProvider` | 首页预加载 | 标签功能开关 |
| 浏览历史 | `/read.json` | 浏览历史 |
| 书签 | `/u/{username}/bookmarks.json` | 书签 |
| 我的话题 | `/topics/created-by/{username}.json` | 用户话题 |
| 通知计数 | MessageBus `/notification/{userId}` | 实时更新 |
| `messageBusInitProvider` | 重新初始化 | MessageBus 重连 |
| `ldcUserInfoProvider` | `credit.linux.do/api/v1/oauth/user-info` | LDC 用户 |
| `cdkUserInfoProvider` | `cdk.linux.do/api/v1/oauth/user-info` | CDK 用户 |

---

## 15. 会话代管理

### 15.1 数据结构

```
AuthSession (单例):
  generation: int              // 当前代，初始 0
  cancelToken: CancelToken     // 当前的取消令牌
```

### 15.2 方法

| 方法 | 说明 |
|------|------|
| `advance()` | generation++，取消旧 cancelToken，创建新的 |
| `isValid(gen)` | `gen == generation` |

### 15.3 启动期用法

- 每个 HTTP 请求发出时戳入 `generation` + 合并 `cancelToken`
- 登录/登出时 `advance()` 切断旧请求
- 响应中检查 generation，过期则丢弃

---

## 16. 启动期网络请求时序

```
时间线 →

main() 开始
  │
  ├─ [同步] CookieJar.initialize()      ← 恢复磁盘 Cookie (_t 等)
  ├─ [同步] CsrfTokenService.init()     ← 恢复 CSRF token
  │
  ├─ [同步] MigrationService.runAll()   ← 可能清空 Cookie
  │
  ├─ [同步] NetworkSettingsService      ← 网络栈就绪
  │
  ├─ [异步, unawaited] GET https://linux.do (首页 HTML) ← 与 runApp 并行
  │   ├─ 解析 CSRF Token → CsrfTokenService
  │   ├─ 解析 sharedSessionKey
  │   ├─ 解析 Turnstile sitekey
  │   ├─ 解析 baseUri / CDN URLs
  │   ├─ 解析 data-preloaded:
  │   │   ├─ currentUser → 有/无（★ 登录态首要判断）
  │   │   ├─ siteSettings → reactions, longPollingBaseUrl, ...
  │   │   ├─ site → categories, top_tags, ...
  │   │   ├─ topicTrackingStateMeta → MessageBus 频道 ID
  │   │   ├─ topicTrackingStates → 话题追踪
  │   │   ├─ customEmoji
  │   │   └─ topicList → 首页话题
  │   └─ 已登录? → start CfClearanceRefresh
  │
  ├─ runApp()
  │   │
  │   ├─ OnboardingGate → 已完成引导? 跳过
  │   │
  │   ├─ PreheatGate
  │   │   ├─ requiresRelogin? → 弹对话框
  │   │   ├─ await ensureLoaded()     ← 复用 main() 的请求
  │   │   ├─ getEnabledReactions()
  │   │   └─ EmojiHandler.init()
  │   │
  │   └─ MainPage
  │       │
  │       ├─ [fireImmediately] currentUserProvider
  │       │   ├─ 有预加载 currentUser → 同步返回 + 后台刷新
  │       │   │   └─ [后台] GET /u/{username}.json
  │       │   └─ 无预加载 currentUser + 有 _t → isLoggedIn()
  │       │       └─ GET /session/current.json
  │       │
  │       ├─ [已登录] MessageBus 初始化
  │       │   ├─ 配置独立域名
  │       │   ├─ 获取频道 ID
  │       │   └─ POST /message-bus/{id}/poll (持续)
  │       │
  │       ├─ [事件] authStateProvider → refreshAll()
  │       │   ├─ 第一批: currentUser, categories, ...
  │       │   └─ 第二批(1s后): userSummary, notifications, ...
  │       │
  │       └─ [后台] 检查更新、剪贴板检测
  │
  └─ 主界面渲染完成，用户可交互
```

---

## 附录 A：启动期所有网络请求清单

| 序号 | 时机 | 请求 | 阻塞? | 条件 |
|------|------|------|-------|------|
| 1 | main() | `GET https://linux.do` (首页 HTML) | 否(unawaited) | 始终 |
| 2 | PreheatGate | 复用 #1 或重新请求 | 是(await) | 始终 |
| 3 | PreheatGate | `GET /discourse-reactions/posts/reactions` | 否 | 始终 |
| 4 | currentUserProvider | `GET /session/current.json` | 否 | 无预加载用户 + 有 _t |
| 5 | currentUserProvider | `GET /u/{username}.json` | 否 | 后台静默刷新 |
| 6 | MainPage | `POST /message-bus/{id}/poll` | 否(持续) | 已登录 |
| 7 | refreshAll 第一批 | `GET /latest.json` 等 | 否 | authState 变化 |
| 8 | refreshAll 第二批 | 多个 API | 否(1s后) | authState 变化 |
| 9 | MainPage 后台 | GitHub Release API | 否 | 检查更新 |

## 附录 B：启动期错误处理

| 场景 | 处理 |
|------|------|
| 首页请求失败 | PreheatGate 显示错误页面，提供重试/退出登录/网络设置选项 |
| /session/current.json 失败 | 保守保留登录态（网络异常），确认失效则执行登出 |
| MessageBus 轮询失败 | 指数退避重试（最大 30s），429 读取 Retry-After |
| 数据迁移清空 Cookie | 设置 requiresRelogin，PreheatGate 弹窗提示 |
| 缓存用户存在但网络失败 | 返回缓存数据，标记错误状态 |
