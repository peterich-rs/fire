# 模板、嵌套视图、Policy、Emoji、Boost API

> 对应 FluxDO 源文档第 17-21 节

---

# 第 17 节：模板 API

---

## 17.1 获取模板列表

```
GET /discourse_templates
```

**Response (200)：**

```json
{
  "templates": [
    {
      "id": 1,
      "title": "模板标题",
      "content": "模板内容",
      ...
    }
  ]
}
```

---

## 17.2 记录模板使用

```
POST /discourse_templates/{templateId}/use
```

**场景**：使用模板后静默上报（失败不影响主流程）。

---

# 第 18 节：嵌套视图 API

---

## 18.1 获取根帖子列表

```
GET /n/topic/{topicId}.json
```

**场景**：树形视图模式下获取根帖子。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sort` | string | 否 | 排序（默认 `"old"`） |
| `page` | int | 否 | 页码（默认 0） |
| `track_visit` | bool | 否 | 是否记录访问 |

---

## 18.2 获取子回复

```
GET /n/topic/{topicId}/children/{postNumber}.json
```

**场景**：树形视图模式下展开子回复。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sort` | string | 否 | 排序（默认 `"old"`） |
| `page` | int | 否 | 页码（默认 0） |
| `depth` | int | 否 | 嵌套深度（默认 1） |

---

# 第 19 节：Policy API

---

## 19.1 接受政策

```
PUT /policy/accept
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `post_id` | int | 是 | 帖子 ID |

---

## 19.2 撤销接受

```
PUT /policy/unaccept
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `post_id` | int | 是 | 帖子 ID |

---

## 19.3 获取已接受用户列表

```
GET /policy/accepted
```

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `post_id` | int | 是 | 帖子 ID |
| `offset` | int | 是 | 分页偏移 |

---

## 19.4 获取未接受用户列表

```
GET /policy/not-accepted
```

**Query Parameters：** 同 19.3。

---

# 第 20 节：Emoji 与表情回应 API

---

## 20.1 获取 Emoji 列表

```
GET /emojis.json
```

**Response (200)：**

```json
{
  "smileys": [
    {"name": "grinning", "url": "/images/emoji/..."},
    ...
  ],
  "people": [...],
  ...
}
```

---

## 20.2 获取可用回应表情

从预加载数据中读取，不单独请求 API。默认值：`['heart', '+1', 'laughing', 'open_mouth']`。

---

# 第 21 节：Boost API

---

## 21.1 创建 Boost

```
POST /discourse-boosts/posts/{postId}/boosts
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `raw` | string | 是 | Boost 内容 |

---

## 21.2 删除 Boost

```
DELETE /discourse-boosts/boosts/{boostId}
```

---

## 21.3 获取 Boost 详情

```
GET /discourse-boosts/boosts/{boostId}
```

---

## 21.4 举报 Boost

```
POST /discourse-boosts/boosts/{boostId}/flags
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `flag_type_id` | int | 是 | 举报类型 ID |
| `message` | string | 否 | 举报说明 |
