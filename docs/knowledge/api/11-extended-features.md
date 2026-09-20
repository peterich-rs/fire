# 模板、嵌套视图、Policy、Emoji、Boost API

## 17. 模板 API

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

## 18. 嵌套视图 API

---

## 18.1 获取根帖子列表

```
GET /n/topic/{topicId}.json
```

**场景**：使用 nested/root-children API 获取根帖子列表。

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

**场景**：使用 nested/root-children API 获取某个帖子的子回复。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sort` | string | 否 | 排序（默认 `"old"`） |
| `page` | int | 否 | 页码（默认 0） |
| `depth` | int | 否 | 嵌套深度（默认 1） |

---

## 19. Policy API

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

## 20. Emoji 与表情回应 API

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

`GET /emojis.json` 只服务选择器目录，不参与正文渲染。

---

## 20.2 获取可用回应表情

从预加载数据中读取，不单独请求 API。默认值：`['heart', '+1', 'laughing', 'open_mouth']`。

---

## 20.3 cooked 正文里的 emoji

官方 cook 把 `:name:` 收成站点 emoji 图，常见形状：

```html
<img src="/images/emoji/twitter/waving_hand.png?v=12" title=":waving_hand:" class="emoji" alt=":waving_hand:">
```

肤色路径是 `/images/emoji/{set}/{name}/t{n}.png?v=12`（`n` 为 1–6）。引用摘录和部分插件片段会把 `:name:` 原样留在文本节点，不再包一层 `img`。站点自定义表情来自 bootstrap `customEmoji`，不在这条标准路径上。

---

## 21. Boost API

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
