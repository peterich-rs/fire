[返回总览](../backend-api.md)

# MessageBus 长轮询

本页覆盖 Discourse MessageBus 的轮询入口、鉴权方式和 Fire 当前规划复用的频道模型。

## 启动前置数据

- 进入长轮询前，当前客户端通常会先从首页 `GET /` 提取：
  - `siteSettings.long_polling_base_url`
  - HTML `<meta name="shared_session_key" ...>`
  - `topicTrackingStateMeta`
  - `currentUser.id`
  - `currentUser.notification_channel_position`
- 前台 `clientId` 是单例，并在上传、Presence、MessageBus 之间复用
- iOS 后台通知拉取会生成单独的临时 `clientId`（例如 `ios_bg_<timestamp>`）

## Fire 当前共享层基础能力

- Rust 共享层现在已经导出 `message_bus_context(client_id?)`
  - 若 `client_id` 为空，则使用默认前台 `clientId` 策略：`fire_<host>_<username-or-foreground>`
  - 会返回：
    - `client_id`
    - `poll_base_url`
    - `poll_url`
    - 是否需要附带 `X-Shared-Session-Key`
    - `shared_session_key`
    - `current_username`
    - `current_user_id`
    - `notification_channel_position`
    - 原始 `topicTrackingStateMeta`
    - 从 `topicTrackingStateMeta` 派生出的初始 `channel -> last_message_id`
- 当前共享层还会额外补出 `/notification/{userId}` 初始订阅位点，前提是 `currentUser.id` 与 `currentUser.notification_channel_position` 都已可用
- Rust 共享层现在还已经导出：
  - `poll_message_bus(client_id?, extra_subscriptions)`
  - `apply_message_bus_status_updates(updates)`
- `poll_message_bus(...)` 当前只做单次请求，不负责无限循环和重连调度：
  - 会把稳定订阅位点和额外页面级订阅合并
  - 会生成 `application/x-www-form-urlencoded` 的 `channel -> last_message_id` 请求体
  - 会按 `|` 分段解析返回内容
  - 会把 `channel="/__status"` 的 `data` 解析成位点更新
  - 会自动把可持久化位点回写到当前 session snapshot
- `apply_message_bus_status_updates(...)` 当前只持久化稳定可恢复位点：
  - `/notification/{userId}` -> `notification_channel_position`
  - 已存在于 `topicTrackingStateMeta` 的频道 -> tracking meta
  - `/latest`、`/new` 之类页面级临时频道不会写回持久化 tracking meta
- 当前共享层只导出可从 session snapshot 稳定恢复的基础上下文，不直接替宿主决定页面级临时频道：
  - `/latest`
  - `/new`
  - `/topic/{topicId}`
  - `/presence/discourse-presence/reply/{topicId}`
- 长轮询循环、重连策略、页面级附加频道管理仍属于后续 orchestration

## 轮询入口

### `POST /message-bus/{clientId}/poll`

- Base URL：
  - 默认 `https://linux.do`
  - 若首页 `siteSettings.long_polling_base_url` 存在，则改用该域名
- 认证：
  - 同域：依赖 Cookie
  - 跨域独立轮询域：依赖 `X-Shared-Session-Key`
- `Content-Type`: `application/x-www-form-urlencoded`
- 关键请求头：
  - `Accept: application/json`
  - `X-Shared-Session-Key: <meta shared_session_key>`，跨域时需要
  - `X-SILENCE-LOGGER: true`
  - `Discourse-Background: true`

- Body 本质上是“频道 -> last_message_id”的字典：

```json
{
  "/latest": "-1",
  "/new": "100",
  "/topic/123": "999"
}
```

- 响应是一个流式或文本分段结果，最终内容可解析为 `MessageBusMessage[]`
- 当前客户端会把响应按 `|` 分段处理，不是只收一个完整 JSON 数组
- 还需要特殊处理控制消息：
  - `channel="/__status"` 时，`data` 里的 `channel -> last_message_id` 映射要回写到本地订阅位点

当前共享层解析后的基础消息结构为：

```json
{
  "channel": "/topic/123",
  "message_id": 1001,
  "data_json": "{\"type\":\"created\"}"
}
```

```json
[
  {
    "channel": "/topic/123",
    "message_id": 1001,
    "data": {}
  }
]
```

## 客户端实际订阅的频道

### 全局 tracking 频道

- 登录后，当前客户端会先把首页 `topicTrackingStateMeta` 中出现的全部 `channel -> messageId` 注册进 MessageBus
- Fire 当前共享层会保留原始 `topicTrackingStateMeta`，并只结构化导出其中可稳定识别的 `channel -> messageId` 项
- `/latest` 和 `/new` 只是页面级额外订阅，不代表全量 tracking 频道

### 话题列表页面级频道

- `/latest`
  - `message_type="latest"`，表示已有话题收到新回复
- `/new`
  - `message_type="new_topic"`，表示有新话题创建

### 话题详情

- `/topic/{topicId}`
  - 常见 `data.type`：
    - `created`
    - `revised`
    - `rebaked`
    - `deleted`
    - `destroyed`
    - `recovered`
    - `acted`
    - `liked`
    - `unliked`
    - `read`
    - `stats`
  - 其它特殊字段：
    - `reload_topic`
    - `refresh_stream`
    - `notification_level_change`

- `/topic/{topicId}/reactions`
  - 帖子回应更新

- `/presence/discourse-presence/reply/{topicId}`
  - 正在输入/Presence 推送
  - 通常要先订阅，再 `GET /presence/get`，最后用响应里的 `message_id` 重新订阅

### 通知

- `/notification/{userId}`
  - 主通知同步频道
  - 负责未读数、recent 列表增量插入、已读状态同步
  - 初始 `messageId` 通常来自 `currentUser.notification_channel_position`

- `/notification-alert/{userId}`
  - 用于桌面/系统通知提示

### 私信相关附加事件

- `/topic/{topicId}` 常见 `data.type` 除公开话题事件外，还可能出现：
  - `move_to_inbox`
  - `archived`
  - `remove_allowed_user`
