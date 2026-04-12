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
- 当前 Fire iOS 行为：
  - 宿主层负责图片选择与 `Data` 读取
  - Rust 共享层负责 multipart 上传
  - 上传成功后 iOS composer 会把返回的 `short_url` 直接插入正文 Markdown

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

- 兼容性说明：
  - 数组里的单个坏项会被跳过，不再让整次短链解析失败

- 当前 Fire iOS 行为：
  - 仅在 composer 预览阶段解析 `upload://`
  - 解析后的真实 URL 不会回写正文，正文仍保留 `upload://...`

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
  - 当前 Fire iOS 会从 `posts[].polls` + `posts[].polls_votes` 渲染原生 poll 卡片：
    - `type="regular"` 按单选处理
    - `type` 含 `multiple` 按多选处理
  - 提交成功后会刷新当前 topic detail

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

- 当前客户端行为：
  - iOS 在已投票的 poll 卡片上提供“撤销投票”
  - 撤销后会刷新当前 topic detail

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
- 当前客户端行为：
  - iOS 在 topic detail header 提供原生话题投票面板
  - 成功后会刷新当前 topic detail
  - `VoteResponse.who_voted[]` 中单个坏项会被跳过

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
- 当前客户端行为：
  - iOS 在已投票状态下显示“取消投票”
  - 成功后会刷新当前 topic detail
  - `VoteResponse.who_voted[]` 中单个坏项会被跳过

### `GET /voting/who`

- 用途：获取话题投票用户列表
- Query：
  - `topic_id: integer`
- 响应：`VotedUser[]`
- 当前客户端行为：
  - iOS 在 topic detail vote panel 提供 voters sheet
  - `VotedUser[]` 中单个坏项会被跳过

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
  - 若前面某个普通响应已经附带 `discourse-logged-out: 1` 或 `Set-Cookie: _t=; Max-Age=0`，`/topics/timings` 往往只是第一个暴露出来的写接口；根因通常是更早一步会话已被服务端判定失效

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
    "last_message_id": 1000
  }
}
```

- 当前客户端 bootstrap 顺序：
  1. 先订阅 `/presence/discourse-presence/reply/{topicId}`
  2. 再调用 `GET /presence/get`
  3. 最后用响应里的 `last_message_id` 重新订阅，避免在初始化窗口期丢事件
- 兼容性说明：
  - 线上真实回包当前使用 `last_message_id`
  - Fire 共享层兼容历史样例里的 `message_id`
  - 服务端也可能返回 `"/discourse-presence/reply/{topicId}": null`；Fire 会将其视为空 Presence 快照，按 `users = []`、`message_id = -1` 处理，而不是把它当成解析错误
  - 若 `last_message_id` / `message_id` 缺失、为 `null` 或是字符串数字，Fire 共享层会尽量解析；无法解析时回退为 `-1`
  - `users[]` 中单个成员如果缺少可用 `id` / `username`，Fire 会跳过坏项，不让整次 Presence bootstrap 失败
  - 宿主层不要在“话题详情首次加载尚未确认成功”之前抢先 bootstrap Presence。对不存在、不可见或无权限的话题，Linux.do 观测上可能在 `GET /presence/get` 返回 `null` 快照的同时附带 `discourse-logged-out: 1` 和 `Set-Cookie: _t=; Max-Age=0`，从而把当前登录态清掉

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

- 兼容性说明：
  - `drafts[]` 中单个坏项会被跳过

### `GET /drafts/{draftKey}.json`

- 用途：获取单个草稿
- `draftKey` 常见规则：
  - `new_topic`
  - `new_private_message`
  - `topic_{topicId}`
  - `topic_{topicId}_post_{postNumber}`
- 当前 Fire iOS 行为：
  - create-topic composer 使用 `new_topic`
  - 新建私信 composer 使用 `new_private_message`
  - advanced reply 使用：
    - 回复话题：`topic_{topicId}`
    - 回复指定楼层：`topic_{topicId}_post_{postNumber}`
  - 私信线程内的完整回复继续沿用 `topic_{topicId}` / `topic_{topicId}_post_{postNumber}`，不会改成 `new_private_message`
  - `new_private_message` 草稿当前会恢复标题、正文和收件人列表；私信线程回复草稿则依赖 `draft.data.archetypeId = "private_message"` 区分
- 成功响应：

```json
{
  "draft": "{\"reply\":\"...\"}",
  "draft_sequence": 1
}
```

- 404 表示草稿不存在
- 兼容性说明：
  - `draft.data` 当前按宽松规则解析；字符串化 JSON 损坏或字段类型漂移时，Fire 会回退为空 `DraftData`，避免整个读取失败

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
- 当前 Fire iOS 行为：
  - composer 输入变更后会防抖自动保存
  - 私信 composer 保存草稿时会额外写入：
    - `action = "private_message"`
    - `archetypeId = "private_message"`
    - `recipients = ["alice", "bob"]`
  - 关闭 composer 时：
    - 有内容则立即 flush 一次草稿
    - 无内容则删除草稿

### `DELETE /drafts/{draftKey}.json`

- 用途：删除草稿
- Query：
  - `sequence: integer`
- 404 可视为幂等成功
- 补充说明：
  - `DELETE` 应尽量带最新的 `draft_sequence`
  - 当前客户端会等待进行中的保存完成，再用最新 sequence 删除，避免并发冲突

## 创建话题与完整回复

### `POST /posts.json`

- 用途 1：创建新话题
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "title": "话题标题",
  "raw": "正文 Markdown",
  "category": 2,
  "archetype": "regular",
  "tags[]": ["rust", "ios"]
}
```

- 成功响应常见形态：

```json
{
  "post": {
    "topic_id": 123
  }
}
```

或：

```json
{
  "topic_id": 123
}
```

- Fire 当前实现约束：
  - iOS 使用独立原生 full-screen composer，而不是首页内联弹层
  - create-topic 入口当前在首页 toolbar
  - advanced reply 入口当前在 topic detail 的 quick reply bar
  - mention autocomplete 当前在正文编辑器里跟随 `@term` 原生弹出建议，走 `GET /u/search/users`
  - tag autocomplete 当前在 create-topic 的标签输入框里原生弹出建议，走 `GET /tags/filter/search`
  - 预览阶段会异步解析 `upload://`，但正文不会被替换成真实 URL
  - 成功后 create-topic 会刷新首页话题流；advanced reply 直接复用现有 reply 提交流程刷新当前 detail

### `POST /posts.json`

- 用途 2：完整回复话题 / 回复指定楼层
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "topic_id": 123,
  "raw": "回复 Markdown",
  "reply_to_post_number": 2
}
```

- 补充说明：
  - `reply_to_post_number` 可选；省略时表示回复话题本身
  - Fire 当前保留了 quick reply，同时新增 full composer 作为升级路径

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
- 当前 Fire iOS 行为：
  - 通过 profile 页“私信”入口或公开用户页 header 的“私信”按钮进入原生 full-screen composer
  - `target_recipients` 由选中的用户名列表按逗号拼接，当前不支持群组收件人
  - 收件人搜索走 `GET /u/search/users?include_groups=false`
  - 发送成功后会刷新私信 mailbox，并直接跳入新建出的私信详情线程
