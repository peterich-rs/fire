# 投票 API

> 对应 FluxDO 源文档第 12 节

---

## 12.1 投票

```
PUT /polls/vote
Content-Type: application/x-www-form-urlencoded
```

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `post_id` | int | 是 | 帖子 ID |
| `poll_name` | string | 是 | 投票名称 |
| `options[]` | string | 是 | 选项值（可多个） |

**Response (200)：**

```json
{
  "poll": { ... }
}
```

---

## 12.2 撤销投票

```
DELETE /polls/vote
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `post_id` | int | 是 | 帖子 ID |
| `poll_name` | string | 是 | 投票名称 |

---

## 12.3 话题投票（Voting 插件）

**投票：**
```
POST /voting/vote
Content-Type: application/x-www-form-urlencoded
```

**取消投票：**
```
POST /voting/unvote
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `topic_id` | int | 是 | 话题 ID |

---

## 12.4 获取投票用户列表

```
GET /voting/who
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `topic_id` | int | 是 | 话题 ID |

**Response (200)：** `VotedUser[]` 数组。
