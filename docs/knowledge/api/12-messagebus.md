# MessageBus 长轮询 API

> 对应 FluxDO 源文档第 22 节

---

## 22.1 长轮询

```
POST /message-bus/{clientId}/poll
Content-Type: application/x-www-form-urlencoded
```

**场景**：实时消息推送。客户端启动后持续长轮询，接收话题更新、新通知、在线状态等实时事件。

> Fire 说明：MessageBus 在话题详情中的职责是 topic / reaction / poll / presence 事件与失效信号。它不会替代主详情读模型，也不会让平台回退到逐帖 patch 后自行重建分页状态。

**特殊配置：**
- 接收超时：60 秒
- 不参与并发限制（`maxConcurrent: null`）
- 可配置独立域名（如 `https://ping.linux.do`）
- 独立域名时通过 `X-Shared-Session-Key` Header 认证
- 禁用 CSRF（`skipCsrf: true`）

**Request Headers（额外）：**

```
X-SILENCE-LOGGER: true
Discourse-Background: true
X-Shared-Session-Key: <key>  （仅独立域名时）
```

**Request Body（form-urlencoded）：**

```
/latest=6855147&/new=104155&/__status=0&/topic/123=5678
```

键为频道名，值为上次接收到的 message_id（-1 表示从头开始）。

**Response（流式，`ResponseType.stream`）：**

响应以 `|` 分隔的 JSON 数组块：

```
[{"channel":"/latest","message_id":6855148,"data":{...}}]|[{"channel":"/new","message_id":104156,"data":{...}}]|
```

**消息格式：**

```json
{
  "channel": "/latest",
  "message_id": 6855148,
  "data": { ... }
}
```

**特殊频道：**
- `/__status`：服务器推送各频道的最新 message_id，用于初始化
- `/latest`：首页话题列表更新
- `/new`：新话题
- `/unread`：未读
- `/notification/{userId}`：通知
- `/topic/{topicId}`：话题更新

**错误处理：**
- `429`：解析 `Retry-After` Header，等待后重试
- 超时：正常行为，立即重新轮询
- 其他错误：指数退避重试（最大 30 秒）

**后台模式：** 每次轮询间增加 60 秒等待间隔。
