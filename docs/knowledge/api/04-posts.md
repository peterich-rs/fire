# 帖子 API

> 对应 FluxDO 源文档第 7 节

---

## 7.1 创建回复

```
POST /posts.json
Content-Type: application/x-www-form-urlencoded
```

**场景**：回复话题或回复某个帖子。

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `topic_id` | int | 是 | 话题 ID |
| `raw` | string | 是 | 回复内容（Markdown） |
| `reply_to_post_number` | int | 否 | 回复的目标楼层号 |

**Response：** 同创建话题，可能返回 `enqueued`。

---

## 7.2 更新帖子内容

```
PUT /posts/{postId}.json
Content-Type: application/x-www-form-urlencoded
```

**场景**：编辑帖子内容。

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `post[raw]` | string | 是 | 新的 Markdown 内容 |
| `post[edit_reason]` | string | 否 | 编辑原因 |

**Response (200)：**

```json
{
  "post": { ... }
}
```

---

## 7.3 删除帖子

```
DELETE /posts/{postId}.json
```

**场景**：删除自己的帖子。

---

## 7.4 恢复已删除的帖子

```
PUT /posts/{postId}/recover.json
```

**场景**：恢复已软删除的帖子。

---

## 7.5 获取单个帖子

```
GET /posts/{postId}.json
```

**场景**：MessageBus 通知帖子更新后获取最新数据。

**Response (200)：** `Post` 对象。

---

## 7.6 获取帖子原始内容

```
GET /posts/{postId}.json
```

**场景**：编辑帖子时获取 raw 内容。

**Response：** 同上，取 `data['raw']` 字段。

---

## 7.7 获取帖子 cooked 内容

```
GET /posts/{postId}/cooked.json
```

**场景**：获取隐藏帖子的 HTML 内容。

**Response (200)：**

```json
{
  "cooked": "<p>HTML 内容</p>"
}
```

---

## 7.8 获取帖子回复历史

```
GET /posts/{postId}/reply-history
```

**Response (200)：** `Post[]` 数组。

---

## 7.9 获取帖子回复列表

```
GET /posts/{postId}/replies
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `after` | int | 否 | 起始位置（默认 1） |

**Response (200)：** `Post[]` 数组。

---

## 7.10 通过楼层号获取帖子

```
GET /posts/by_number/{topicId}/{postNumber}
```

**Response (200)：** `Post` 对象。

---

## 7.11 获取帖子回复 ID 列表

```
GET /posts/{postId}/reply-ids.json
```

**Response (200)：**

```json
[
  {"id": 1},
  {"id": 2}
]
```

---

## 7.12 点赞/取消点赞

**点赞：**
```
POST /post_actions
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int | 是 | 帖子 ID |
| `post_action_type_id` | int | 是 | 固定值 `2`（点赞） |

**取消点赞：**
```
DELETE /post_actions/{postId}
```

| Query Parameter | 类型 | 说明 |
|----------------|------|------|
| `post_action_type_id` | int | 固定值 `2` |

---

## 7.13 切换回应（Reaction）

```
PUT /discourse-reactions/posts/{postId}/custom-reactions/{reaction}/toggle.json
```

**场景**：对帖子进行表情回应（如 ❤️、👍、😄）。

**Path Parameters：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `postId` | int | 帖子 ID |
| `reaction` | string | 表情名称（如 `heart`、`+1`、`laughing`） |

**Response (200)：**

```json
{
  "reactions": [
    {
      "id": "heart",
      "count": 5,
      "users": [...]
    }
  ],
  "current_user_reaction": {
    "id": "heart",
    ...
  }
}
```

---

## 7.14 获取回应人列表

```
GET /discourse-reactions/posts/{postId}/reactions-users.json
```

**Response (200)：**

```json
{
  "reaction_users": [
    {
      "reaction": "heart",
      "users": [...]
    }
  ]
}
```

---

## 7.15 举报帖子

```
POST /post_actions
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int | 是 | 帖子 ID |
| `post_action_type_id` | int | 是 | 举报类型 ID |
| `message` | string | 否 | 举报说明 |

---

## 7.16 获取举报类型

```
GET /post_action_types.json
```

**Response (200)：**

```json
{
  "post_action_types": [
    {
      "id": 4,
      "name_key": "inappropriate",
      "name": "不当内容",
      "description": "...",
      "is_flag": true
    }
  ]
}
```

---

## 7.17 接受/取消接受答案

**接受答案：**
```
POST /solution/accept
Content-Type: application/x-www-form-urlencoded
```

**取消接受答案：**
```
POST /solution/unaccept
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int | 是 | 帖子 ID |

---

## 7.18 追踪链接点击

```
POST /clicks/track
Content-Type: application/x-www-form-urlencoded
```

**场景**：用户点击帖子中的链接时异步上报（fire-and-forget）。

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `url` | string | 是 | 点击的 URL |
| `post_id` | int | 是 | 帖子 ID |
| `topic_id` | int | 是 | 话题 ID |
