# 通知 API

> 对应 FluxDO 源文档第 10 节

---

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
