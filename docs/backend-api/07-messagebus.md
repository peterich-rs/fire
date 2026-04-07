[返回总览](../backend-api.md)

# MessageBus 长轮询

本页覆盖 Discourse MessageBus 的轮询入口、鉴权方式和 Fire 当前规划复用的频道模型。

## 启动前置数据

- 进入长轮询前，当前客户端通常会先从首页 `GET /` 提取：
  - `siteSettings.long_polling_base_url`
  - HTML `<meta name="shared_session_key" ...>`，仅跨域长轮询场景需要；同域 `linux.do` 常为空
  - `topicTrackingStateMeta`
  - `currentUser.notification_channel_position`
- 前台 `clientId` 是单例，并在上传、Presence、MessageBus 之间复用
- iOS 后台通知拉取会生成单独的临时 `clientId`（例如 `ios_bg_<timestamp>`）

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
- Fire 当前实现维持单个前台轮询任务；订阅变更不会再为每个 `subscribe/unsubscribe` 直接重建 task，而是唤醒已有轮询并在 `150ms` 的最小重启间隔后合并到下一次 poll
- Fire 当前在本地运行时按 `channel -> owner_token[]` 跟踪订阅归属；同一频道可以被多个页面/生命周期共同持有，只有最后一个 owner 释放时才真正从下一次 poll 中移除
- `MESSAGE_BUS_CALL_TIMEOUT=75s` 触发的非连接超时会被视为一次正常长轮询周期结束，不累计失败退避；`429/502/503/504` 仍记录为服务端侧异常并进入退避

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
