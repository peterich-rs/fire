[返回总览](../backend-api.md)

# MessageBus 长轮询

本页覆盖 Discourse MessageBus 的轮询入口、鉴权方式和 Fire 当前规划复用的频道模型。

## 启动前置数据

- 进入长轮询前，当前客户端通常会从登录 WebView 捕获的首页 HTML、已持久化 bootstrap，或显式 bootstrap 刷新结果中获得：
  - `siteSettings.long_polling_base_url`
  - HTML `<meta name="shared_session_key" ...>`，仅跨域长轮询场景需要；同域 `linux.do` 常为空
  - `topicTrackingStateMeta`
  - `currentUser.notification_channel_position`
- 前台 `clientId` 是单例，并在上传、Presence、MessageBus 之间复用
- iOS 后台通知拉取会生成单独的临时 `clientId`（例如 `ios_bg_<timestamp>`）
- iOS 前台冷启动不会为了 MessageBus 单独 native `GET /` 刷新 bootstrap；它会等首次首页话题列表请求结束后再启动 MessageBus，避免 bootstrap、首页列表、通知/个人页预热和长轮询在同一个启动窗口内并发。

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
  - `Accept: text/plain, */*; q=0.01`
  - `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`
  - `Origin: https://linux.do`
  - `Referer: https://linux.do/`
  - `X-Shared-Session-Key: <meta shared_session_key>`，跨域时需要
  - `X-SILENCE-LOGGER: true`
  - `Dont-Chunk: true`
  - `Sec-Fetch-Dest: empty`
  - `Sec-Fetch-Mode: cors`
  - `Sec-Fetch-Site: cross-site`，同域 poll 时为 `same-origin`
  - `Priority: u=1, i`
  - `Discourse-Logged-In: true` / `Discourse-Present: true`，已登录前台 poll 会带
  - `Discourse-Background: true` 只用于 iOS 后台 `notification-alert` 单次拉取；前台 poll 不带

- Body 本质上是“频道 -> last_message_id”的字典，外加递增的 `__seq`：

```json
{
  "/latest": "-1",
  "/new": "100",
  "/topic/123": "999",
  "__seq": "117"
}
```

- 响应是一个流式或文本分段结果，最终内容可解析为 `MessageBusMessage[]`
- 当前客户端会把响应按 `|` 分段处理，不是只收一个完整 JSON 数组
- Fire 当前对单条 MessageBus item 做容错解析：`message_id` 支持数字或字符串数字；若某条 item 本身缺字段、为 `null` 或类型不对，只会跳过该条，不会把整个 chunk 判成失败
- 还需要特殊处理控制消息：
  - `channel="/__status"` 时，`data` 里的 `channel -> last_message_id` 映射要回写到本地订阅位点
- Fire 当前实现维持单个前台轮询任务；订阅变更不会再为每个 `subscribe/unsubscribe` 直接重建 task，而是唤醒已有轮询并在 `150ms` 的最小重启间隔后合并到下一次 poll
- Fire 当前在本地运行时按 `channel -> owner_token[]` 跟踪订阅归属；同一频道可以被多个页面/生命周期共同持有，只有最后一个 owner 释放时才真正从下一次 poll 中移除
- `MESSAGE_BUS_CALL_TIMEOUT=35s` 触发的非连接超时会被视为一次正常长轮询周期结束，不累计失败退避；`429/502/503/504` 仍记录为服务端侧异常并进入退避。失败退避从 `1s` 起步，封顶 `15s`

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
- `/latest` 和 `/new` 只是页面级额外订阅，不代表全量 tracking 频道

### 话题列表页面级频道

- `/latest`
  - `message_type="latest"`，表示已有话题收到新回复
  - iOS 首页在全局 Latest、无分类、无标签时会用 `topic_ids` 做增量回拉并合并到现有列表；Android 首页当前在收到匹配事件后按同样的 debounce / 最小间隔策略刷新 Paging 列表。
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

- `/polls/{topicId}`
  - 投票结果或投票状态更新
  - Fire 将其映射为 `TopicDetail` 事件，`detail_event_type="polls"`，并设置 `refresh_stream=true`

- `/presence/discourse-presence/reply/{topicId}`
  - 正在输入/Presence 推送
  - 通常要先订阅，再 `GET /presence/get`，最后用响应里的 `last_message_id` 重新订阅

- 当前 iOS / Android 详情页进入后会同时持有：
  - `/topic/{topicId}`，初始 last id 来自详情 payload 顶层 `message_bus_last_id`
  - `/topic/{topicId}/reactions`
  - `/polls/{topicId}`，初始 last id 为 `0`
  - `/presence/discourse-presence/reply/{topicId}`，先订阅再 bootstrap Presence
- 详情页收到 topic / reaction / polls / presence 事件后不会立即反复刷新，而是做短 debounce；刷新详情时使用 `track_visit=false&forceLoad=false`

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
