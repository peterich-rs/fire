# Discourse Chat API

> 观测来源：fluxdo `lib/services/discourse/_chat.dart` 与 Discourse Chat 插件 HTTP 面。  
> 实现入口：`fire-core::core::chat` / `fire-uniffi-chat` / 平台 Chat tab。

Discourse Chat 与论坛私信（`private-messages` topic 列表）是两条独立产品面：

| 能力 | 路径族 | 说明 |
|------|--------|------|
| Chat 频道 / 实时会话 | `/chat/api/*` 与少数 `/chat/*` | 本文件 |
| 论坛私信 topic | `/topics/private-messages*` + `/posts.json` | 见 `05-users.md` |

## 15.1 我的频道列表

```
GET /chat/api/me/channels
```

**场景**：Chat tab 首屏；返回公共频道、DM 频道、未读 tracking、MessageBus 起始位点。

**Response（结构化，关键字段）：**

```json
{
  "public_channels": [ /* ChatChannel */ ],
  "direct_message_channels": [ /* ChatChannel */ ],
  "tracking": {
    "channel_tracking": {
      "20": { "unread_count": 2, "mention_count": 0 }
    }
  },
  "meta": {
    "message_bus_last_ids": {
      "user_tracking_state": 3,
      "new_channel": 4
    }
  }
}
```

**未读徽章口径（对齐官方 web / fluxdo）：**

- DM：`unread_count + mention_count`
- 公共频道：仅 `mention_count`
- `current_user_membership.muted == true` 的频道不计

## 15.2 单频道详情

```
GET /chat/api/channels/{channel_id}
```

响应根可能是 `{ "channel": { ... } }` 或频道对象本身。

频道关键字段：

| 字段 | 说明 |
|------|------|
| `id` | 频道 ID |
| `title` / `unicode_title` | 展示标题 |
| `chatable_type` | `DirectMessage` 或 `Category` |
| `chatable.users` | DM 对端用户列表 |
| `chatable.group` | 是否群聊 DM |
| `current_user_membership` | following / muted / starred / last_read_message_id |
| `last_message` | 最后一条消息摘要 |
| `meta.can_*` | 能力位 |
| `meta.message_bus_last_ids` | 该频道 bus 位点 |

## 15.3 创建 / 复用 DM 频道

```
POST /chat/api/direct-message-channels
Content-Type: application/json
```

| Body | 说明 |
|------|------|
| `target_usernames` | 对方用户名数组（不含自己） |
| `name` | 可选群名 |
| `upsert` | `true` 时 1:1 复用已有频道 |

参与者（含自己）> 2 或带 `name` 时按群聊处理。

## 15.4 消息列表

```
GET /chat/api/channels/{channel_id}/messages
```

| Query | 说明 |
|-------|------|
| `page_size` | 默认 50，服务端上限约 50–100 |
| `direction` | `past` / `future`，配合 `target_message_id` 翻页 |
| `target_message_id` | 游标 / 跳转锚点 |
| `fetch_from_last_read` | `true` 时首屏定位未读 |

**Response：**

```json
{
  "messages": [ /* ChatMessage */ ],
  "meta": {
    "can_load_more_past": true,
    "can_load_more_future": false,
    "target_message_id": 123
  }
}
```

## 15.5 发送消息

```
POST /chat/{channel_id}
Content-Type: application/json
```

| Body | 说明 |
|------|------|
| `message` | Markdown 文本 |
| `staged_id` | 客户端临时 ID，MessageBus `sent` 回传用于对账 |
| `in_reply_to_id` | 平面回复 |
| `thread_id` | 消息串内回复 |
| `upload_ids` | 附件 ID 列表 |

成功响应含 `message_id`。

## 15.6 标记已读

```
PUT /chat/api/channels/{channel_id}/read?message_id={id}
```

`message_id` 可选；服务端要求 last_read 单调不减。

## 15.7 浏览 / 加入 / 退出公共频道

```
GET  /chat/api/channels?status=open&offset=0&limit=25&filter=...
POST /chat/api/channels/{id}/memberships/me
DELETE /chat/api/channels/{id}/memberships/me/follows
```

`DELETE .../follows` 对 DM 语义是 unfollow（列表隐藏，有新消息可再出现）。

## 15.8 成员 / 通知 / 收藏

```
GET /chat/api/channels/{id}/memberships
PUT /chat/api/channels/{id}/memberships/me          # { "starred": true }
PUT /chat/api/channels/{id}/notifications-settings/me
```

通知设置 body：

```json
{
  "notifications_settings": {
    "muted": false,
    "notification_level": "mention"
  }
}
```

`notification_level` 常见值：`never` / `mention` / `always`（观测以站点配置为准）。

## 15.9 消息操作

```
PUT    /chat/api/channels/{id}/messages/{mid}     # 编辑
DELETE /chat/api/channels/{id}/messages/{mid}     # 删除
PUT    /chat/{id}/react/{mid}                     # { "emoji", "react_action": "add"|"remove" }
GET    /chat/api/search?query=...&channel_id=...  # 搜索
```

## 15.10 MessageBus 通道

频道列表与会话增量依赖 MessageBus（与 `/message-bus/{client_id}/poll` 共用连接）：

| 通道 | 用途 |
|------|------|
| `/chat/new-channel` | 新 DM / 被拉群 |
| `/chat/channel-edits` | 频道改名/描述 |
| `/chat/user-tracking-state/{userId}` | 已读 / tracking 同步 |
| `/chat/{channelId}/new-messages` | 列表最后一条与本地未读 +1 |
| `/chat/{channelId}` | 频道内消息事件（sent / edit / delete / reaction / pin） |
| `/chat/{channelId}/thread/{threadId}` | 消息串子流事件 |

Fire 将 `/chat/*` 事件分类为 `MessageBusEventKind::Chat`，`payload_json` 携带原始 JSON；路径可解析时 `topic_id` 复用为 chat `channel_id`。

## 15.11 Thread / 置顶

```
POST   /chat/api/channels/{id}/threads                 # { original_message_id }
GET    /chat/api/channels/{id}/threads/{tid}/messages
PUT    /chat/api/channels/{id}/threads/{tid}/read
GET    /chat/api/channels/{id}/pins
POST   /chat/api/channels/{id}/messages/{mid}/pin
DELETE /chat/api/channels/{id}/messages/{mid}/pin
PUT    /chat/api/channels/{id}/pins/read
```
