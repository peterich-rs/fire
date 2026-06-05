# Presence、分类与标签、书签、草稿 API

> 对应 FluxDO 源文档第 13-16 节

---

# 第 13 节：Presence API

---

## 13.1 上报帖子阅读时间

```
POST /topics/timings
Content-Type: application/x-www-form-urlencoded
```

**场景**：用户阅读话题时定期上报阅读时间（静默请求，不弹错误提示）。

**Request Headers（额外）：**

```
X-SILENCE-LOGGER: true
Discourse-Background: true
```

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `topic_id` | int | 是 | 话题 ID |
| `topic_time` | int | 是 | 总阅读时间（毫秒） |
| `timings[{postNumber}]` | int | 是 | 各帖子阅读时间（毫秒），如 `timings[1]=5000&timings[2]=3000` |

---

## 13.2 获取话题在线状态

```
GET /presence/get
```

**场景**：查看话题详情页时获取其他正在查看/回复的用户。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `channels[]` | string | 是 | 频道名，如 `/discourse-presence/reply/{topicId}` |

---

## 13.3 更新 Presence 状态

```
POST /presence/update
Content-Type: application/x-www-form-urlencoded
```

**场景**：用户进入/离开话题详情页时更新在线状态（静默请求）。

**Request Headers（额外）：**

```
X-SILENCE-LOGGER: true
Discourse-Background: true
```

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `client_id` | string | 是 | MessageBus 客户端 ID |
| `present_channels[]` | string[] | 否 | 进入的频道列表 |
| `leave_channels[]` | string[] | 否 | 离开的频道列表 |

---

# 第 14 节：分类与标签 API

---

## 14.1 获取站点信息（含所有分类）

```
GET /site.json
```

**场景**：获取分类列表、标签、站点设置等。首次从预加载 HTML 获取，后续按需请求。

**Response (200)：**

```json
{
  "categories": [...],
  "top_tags": [...],
  "can_tag_topics": true,
  "post_action_types": [...],
  "system_user_avatar_template": "...",
  ...
}
```

---

## 14.2 设置分类通知级别

```
POST /category/{categoryId}/notifications
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `notification_level` | int | 是 | 通知级别 |

---

## 14.3 获取首页书签 Tab

```
GET /bookmarks.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 否 | 页码 |

---

# 第 15 节：书签 API

---

## 15.1 创建书签（话题）

```
POST /bookmarks.json
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bookmarkable_id` | int | 是 | 话题 ID |
| `bookmarkable_type` | string | 是 | 固定值 `"Topic"` |
| `name` | string | 否 | 书签名称 |
| `reminder_at` | string | 否 | 提醒时间（ISO 8601 UTC） |
| `auto_delete_preference` | int | 否 | 自动删除偏好 |

---

## 15.2 创建书签（帖子）

```
POST /bookmarks.json
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `bookmarkable_id` | int | 是 | 帖子 ID |
| `bookmarkable_type` | string | 是 | 固定值 `"Post"` |
| `name` | string | 否 | 书签名称 |
| `reminder_at` | string | 否 | 提醒时间 |
| `auto_delete_preference` | int | 否 | 自动删除偏好 |

---

## 15.3 更新书签

```
PUT /bookmarks/{bookmarkId}.json
Content-Type: application/json
```

**Request Body（JSON）：**

```json
{
  "name": "新名称",
  "reminder_at": "2024-12-31T23:59:59Z",
  "auto_delete_preference": 3
}
```

---

## 15.4 清除书签提醒

```
PUT /bookmarks/bulk.json
Content-Type: application/json
```

```json
{
  "bookmark_ids": [123],
  "operation": {
    "type": "clear_reminder"
  }
}
```

---

## 15.5 删除书签

```
DELETE /bookmarks/{bookmarkId}.json
```

---

# 第 16 节：草稿 API

---

## 16.1 获取草稿列表

```
GET /drafts.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `offset` | int | 否 | 偏移（默认 0） |
| `limit` | int | 否 | 每页数量（默认 20） |

---

## 16.2 获取指定草稿

```
GET /drafts/{draftKey}.json
```

**Response (200)：**

```json
{
  "draft": { ... },
  "draft_sequence": 1
}
```

**Response (404)：** 草稿不存在，返回 `null`。

---

## 16.3 保存草稿

```
POST /drafts.json
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `draft_key` | string | 是 | 草稿键 |
| `data` | string | 是 | 草稿数据（JSON 字符串） |
| `sequence` | int | 是 | 序列号（乐观锁） |

**Response (200)：**

```json
{
  "draft_sequence": 2
}
```

**Response (409)：** 序列号冲突，返回最新序列号：

```json
{
  "draft_sequence": 5
}
```

---

## 16.4 删除草稿

```
DELETE /drafts/{draftKey}.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sequence` | int | 否 | 序列号 |

**Response (404)：** 静默忽略（草稿已不存在）。
