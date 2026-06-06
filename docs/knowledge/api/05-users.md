# 用户 API

> 对应 FluxDO 源文档第 8 节

---

## 8.1 获取用户信息

```
GET /u/{username}.json
```

**场景**：查看用户资料页。

**Response (200)：**

```json
{
  "user": {
    "id": 12345,
    "username": "example",
    "name": "Example",
    "avatar_template": "/user_avatar/...",
    "trust_level": 2,
    "badge_count": 10,
    "post_count": 100,
    "topic_count": 50,
    "likes_given": 200,
    "likes_received": 150,
    "time_read": 36000,
    "created_at": "2023-01-01T00:00:00.000Z",
    ...
  }
}
```

---

## 8.2 获取用户统计

```
GET /u/{username}/summary.json
```

**场景**：用户资料页的统计摘要（带 5 分钟缓存）。

**Response (200)：** `UserSummary` 对象，包含发帖数、回复数、获赞数等。

---

## 8.3 获取用户动态

```
GET /user_actions.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `username` | string | 是 | 用户名 |
| `filter` | string | 否 | 动作类型过滤 |
| `offset` | int | 否 | 分页偏移（默认 0） |

---

## 8.4 获取用户回应列表

```
GET /discourse-reactions/posts/reactions.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `username` | string | 是 | 用户名 |
| `before_reaction_user_id` | int | 否 | 分页游标 |

---

## 8.5 关注/取消关注用户

**关注：**
```
PUT /follow/{username}
```

**取消关注：**
```
DELETE /follow/{username}
```

---

## 8.6 获取关注列表/粉丝列表

**关注列表：**
```
GET /u/{username}/follow/following
```

**粉丝列表：**
```
GET /u/{username}/follow/followers
```

**Response (200)：** `FollowUser[]` 数组。

---

## 8.7 设置用户通知级别

```
PUT /u/{username}/notification_level.json
```

**场景**：设置对某用户的通知级别（normal/mute/ignore）。

**Request Body（JSON）：**

```json
{
  "notification_level": "normal",
  "expiring_at": "2024-12-31T23:59:59Z"
}
```

---

## 8.8 私信相关

| 接口 | URL |
|------|-----|
| 收件箱 | `GET /topics/private-messages/{username}.json` |
| 已发送 | `GET /topics/private-messages-sent/{username}.json` |
| 归档 | `GET /topics/private-messages-archive/{username}.json` |

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 否 | 页码（>0 时传递） |

---

## 8.9 创建私信

```
POST /posts.json
Content-Type: application/x-www-form-urlencoded
```

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `title` | string | 是 | 私信标题 |
| `raw` | string | 是 | 正文（Markdown） |
| `archetype` | string | 是 | 固定值 `"private_message"` |
| `target_recipients` | string | 是 | 收件人用户名，逗号分隔 |

**Response：** 同创建话题。

---

## 8.10 获取用户浏览历史

```
GET /read.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 否 | 页码 |

---

## 8.11 获取用户书签

```
GET /u/{username}/bookmarks.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 否 | 页码 |
| `limit` | int | 否 | 每页数量（上限 20） |

---

## 8.12 获取用户创建的话题

```
GET /topics/created-by/{username}.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 否 | 页码 |

---

## 8.13 获取用户徽章

```
GET /user-badges/{username}.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `grouped` | string | 是 | 固定值 `"true"` |

---

## 8.14 获取徽章详情

```
GET /badges/{badgeId}.json
```

---

## 8.15 获取徽章获得者

```
GET /user_badges.json
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `badge_id` | int | 是 | 徽章 ID |
| `username` | string | 否 | 用户名 |

---

## 8.16 获取待使用邀请链接

```
GET /u/{username}/invited/pending
```

---

## 8.17 生成邀请链接

```
POST /invites
```

**Request Body（JSON）：**

```json
{
  "max_redemptions_allowed": 5,
  "expires_at": "2024-12-31T23:59:59Z",
  "description": "邀请描述",
  "email": "user@example.com"
}
```

**Response (200)：** `InviteLinkResponse` 对象。
