[返回总览](../backend-api.md)

# 上传、草稿与互动能力

本页覆盖内容创作和互动相关接口，包括上传、投票、Presence、阅读时长、草稿、模板和私信。

## 开发前置约束

- 创建话题/编辑前，通常要先拿到这些 `siteSettings`：
  - `min_topic_title_length`
  - `min_first_post_length`
  - `min_post_length`
  - `min_personal_message_title_length`
  - `min_personal_message_post_length`
  - `default_composer_category`
  - `discourse_reactions_enabled_reactions`
- 分类元数据还会决定：
  - `categoryId`
  - `slug`
  - `parent_category_id`
  - `minimum_required_tags`
  - `required_tag_groups`
  - `allowed_tags`
  - `permission`
  - `topic_template`
- 这些数据主要来自首页 `data-preloaded.siteSettings` 和 `data-preloaded.site.categories`

## 上传

### `POST /uploads.json`

- 用途：上传图片
- 认证：需要登录
- Query：
  - `client_id: string`
- `Content-Type`: `multipart/form-data`
- Form 字段：
  - `upload_type: "composer"`
  - `synchronous: true`
  - `file: <binary>`
- `client_id` 说明：
  - 当前客户端会复用与 MessageBus / Presence 相同的单例 `clientId`
  - 独立实现时也建议把上传、Presence、长轮询绑定到同一个前台 `clientId`

- 成功响应关键字段：

```json
{
  "short_url": "upload://abc.png",
  "url": "/uploads/short-url/abc.png",
  "original_filename": "abc.png",
  "width": 100,
  "height": 100,
  "thumbnail_width": 100,
  "thumbnail_height": 100
}
```

### `POST /uploads/lookup-urls`

- 用途：把 `upload://` 短地址解析成真实 URL
- `Content-Type`: `application/json`
- Body：

```json
{
  "short_urls": ["upload://abc.png", "upload://def.jpg"]
}
```

- 响应：

```json
[
  {
    "short_url": "upload://abc.png",
    "short_path": "/uploads/short-url/abc.png",
    "url": "/uploads/default/original/1X/abc.png"
  }
]
```

### `GET <任意图片 URL>`

- 用途：下载图片二进制
- `Response-Type`: bytes
- 额外约束：
  - 客户端要求响应 `Content-Type` 以 `image/` 开头
  - 会做 PNG/JPEG/GIF/WebP/BMP/ICO 魔数校验

## 投票、Poll、Presence

### `PUT /polls/vote`

- 用途：对帖子内投票组件投票
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "post_id": 111,
  "poll_name": "poll",
  "options[]": ["1", "2"]
}
```

- 响应：

```json
{
  "poll": Poll
}
```

- 补充说明：
  - 协议层应支持重复提交 `options[]` 表单字段来表达多选
  - 当前客户端代码存在多选实现偏差，实际更可靠的是单值 `options[]`

### `DELETE /polls/vote`

- 用途：撤销投票
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "post_id": 111,
  "poll_name": "poll"
}
```

- 响应：

```json
{
  "poll": Poll
}
```

### `POST /voting/vote`

- 用途：话题投票插件投票
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "topic_id": 123
}
```

- 响应：`VoteResponse`

### `POST /voting/unvote`

- 用途：取消话题投票
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "topic_id": 123
}
```

- 响应：`VoteResponse`

### `GET /voting/who`

- 用途：获取话题投票用户列表
- Query：
  - `topic_id: integer`
- 响应：`VotedUser[]`

### `POST /topics/timings`

- 用途：上报阅读时长
- `Content-Type`: `application/x-www-form-urlencoded`
- 关键请求头：
  - `X-SILENCE-LOGGER: true`
  - `Discourse-Background: true`
- Body：

```json
{
  "topic_id": 123,
  "topic_time": 15000,
  "timings[111]": 5000,
  "timings[112]": 10000
}
```

- 限流响应与 `POST /presence/update` 一致，服务端会通过 `extras.wait_seconds`（兼容 `time_left`）返回建议冷却时长
- Fire 当前实现约束：
  - Rust 共享层持有 `/topics/timings` 的限流冷却窗口；冷却期内会直接跳过请求，避免继续撞 429
  - `429` 对 `/topics/timings` 也是“软失败”；Rust 返回“本次未上报”给宿主层，iOS 会保留待发送时长，等下一次 flush 周期重试
  - 如果响应里没有可解析的等待时长，客户端回退到一个短默认冷却时间再恢复请求

### `GET /presence/get`

- 用途：获取“正在输入/正在回复”的用户列表
- 前置条件：
  - `siteSettings.presence_enabled == true`
  - 当前用户未隐藏 Presence（例如 `hide_presence != true`）
- Query：

```json
{
  "channels[]": ["/discourse-presence/reply/123"]
}
```

- 响应：

```json
{
  "/discourse-presence/reply/123": {
    "users": [
      {
        "id": 1,
        "username": "alice",
        "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
      }
    ],
    "message_id": 1000
  }
}
```

- 当前客户端 bootstrap 顺序：
  1. 先订阅 `/presence/discourse-presence/reply/{topicId}`
  2. 再调用 `GET /presence/get`
  3. 最后用响应里的 `message_id` 重新订阅，避免在初始化窗口期丢事件

### `POST /presence/update`

- 用途：更新 Presence 状态
- `Content-Type`: `application/x-www-form-urlencoded`
- 关键请求头：
  - `X-SILENCE-LOGGER: true`
  - `Discourse-Background: true`
- Body：

```json
{
  "client_id": "client-id",
  "present_channels[]": ["/discourse-presence/reply/123"],
  "leave_channels[]": ["/discourse-presence/reply/456"]
}
```

- `client_id` 说明：
  - 当前客户端复用 MessageBus 的单例 `clientId`
- Fire 当前实现约束：
  - 宿主层在 quick composer 获得焦点时会立即触发一次 `present_channels[]` 更新
  - 已处于 reply-presence 活跃状态的同一 topic，Rust 共享层仍会把重复 `present_channels[]` 限制到至少 `30s` 一次，避免宿主层重复触发
  - 对已经本地判定为非活跃的 topic，重复 `leave_channels[]` 会在客户端被直接丢弃，避免重复打点
- 限流响应：

```json
{
  "errors": "You’ve performed this action too many times, please try again later.",
  "extras": {
    "wait_seconds": 8.72
  }
}
```

- 限流处理：
  - `429` 对 presence 更新是“软失败”；Fire 会读取 `extras.wait_seconds`（兼容 `time_left`），进入冷却窗口
  - 冷却窗口内后续 `POST /presence/update` 不再继续请求服务端，避免把 typing/presence 心跳错误冒泡给宿主层
  - 如果响应里没有可解析的等待时长，客户端回退到一个短默认冷却时间再恢复请求

## 草稿

### `GET /drafts.json`

- 用途：获取草稿列表
- Query：
  - `offset: integer`
  - `limit: integer`
- 响应：

```json
{
  "drafts": [Draft],
  "has_more": false
}
```

### `GET /drafts/{draftKey}.json`

- 用途：获取单个草稿
- `draftKey` 常见规则：
  - `new_topic`
  - `new_private_message`
  - `topic_{topicId}`
  - `topic_{topicId}_post_{postNumber}`
- 成功响应：

```json
{
  "draft": "{\"reply\":\"...\"}",
  "draft_sequence": 1
}
```

- 404 表示草稿不存在

### `POST /drafts.json`

- 用途：保存草稿
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "draft_key": "new_topic",
  "data": "{\"reply\":\"正文\",\"title\":\"标题\"}",
  "sequence": 0
}
```

- 成功响应：

```json
{
  "draft_sequence": 1
}
```

- `409 Conflict` 表示序列号冲突，响应中可能返回新的 `draft_sequence`

### `DELETE /drafts/{draftKey}.json`

- 用途：删除草稿
- Query：
  - `sequence: integer`
- 404 可视为幂等成功
- 补充说明：
  - `DELETE` 应尽量带最新的 `draft_sequence`
  - 当前客户端会等待进行中的保存完成，再用最新 sequence 删除，避免并发冲突

## 模板

### `GET /discourse_templates`

- 用途：获取模板列表
- 响应可能是：

```json
{
  "templates": [Template]
}
```

或：

```json
[
  Template
]
```

`Template` 关键字段：

```json
{
  "id": 1,
  "title": "模板标题",
  "slug": "template-slug",
  "content": "模板内容",
  "tags": ["tag-a"],
  "usages": 10
}
```

### `POST /discourse_templates/{templateId}/use`

- 用途：记录模板被使用
- 备注：`/discourse_templates*` 属于站点模板能力，独立开发前应确认目标站点已开启对应路由/插件

## 私信

### `POST /posts.json`

- 用途：创建私信
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "title": "私信标题",
  "raw": "私信正文",
  "archetype": "private_message",
  "target_recipients": "alice,bob"
}
```

- 成功响应与“创建话题”相同，客户端最终取 `topic_id`
- 开发前置约束：
  - 当前客户端会先读取 `min_personal_message_title_length`
  - 以及 `min_personal_message_post_length`
