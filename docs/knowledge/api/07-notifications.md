# 通知 API

## 10.1 获取最近通知

```
GET /notifications
```

**场景**：快捷面板获取最近通知（非分页，重置未读计数）。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `recent` | bool | 是 | 固定值 `true` |
| `limit` | int | 是 | 固定值 `30` |
| `bump_last_seen_reviewable` | bool | 是 | 固定值 `true` |

**Response (200)：**

```json
{
  "notifications": [
    {
      "id": 123,
      "notification_type": 1,
      "read": false,
      "created_at": "2024-01-01T00:00:00.000Z",
      "data": {}
    }
  ],
  "total_rows_notifications": 30,
  "seen_notification_id": 120,
  "load_more_notifications": null
}
```

---

## 10.2 获取通知列表（分页）

```
GET /notifications
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | int | 是 | 固定值 `60` |
| `offset` | int | 否 | 分页偏移 |

**Response (200)：** same envelope as recent notifications. `load_more_notifications`
may contain a server-provided URL/path for the next page; clients can also use
`offset` with `total_rows_notifications` for pagination.

---

## 10.3 标记通知已读

**全部已读：**
```
PUT /notifications/mark-read
```

**单条已读：**
```
PUT /notifications/mark-read
```

| Request Body 字段 | 类型 | 说明 |
|-------------------|------|------|
| `id` | int | 通知 ID（仅单条标记时） |

## 10.4 实时徽章闩

MessageBus `/notification/{user_id}` 会合并未读计数。客户端一旦应用过本会话的 live 计数，之后的 bootstrap / `currentUser` 种子不得把徽章回滚到旧值。冷启动尚未收到 live 事件时，仍可用 bootstrap 种子。本地 mark-read 后，更大的 live 值仍可上升。登出时清闩。
