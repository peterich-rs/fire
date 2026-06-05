# 搜索 API

> 对应 FluxDO 源文档第 9 节

---

## 9.1 全文搜索

```
GET /search.json
```

**场景**：搜索帖子、用户、分类、标签。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `q` | string | 是 | 搜索关键词 |
| `page` | int | 否 | 页码（默认 1，>1 时传递） |
| `type_filter` | string | 否 | 类型过滤：`topic`/`post`/`user`/`category`/`tag` |

**注意：** 分页仅在指定 `type_filter` 时生效。

---

## 9.2 AI 语义搜索

```
GET /discourse-ai/embeddings/semantic-search
```

**场景**：基于 AI 的语义搜索（需站点启用）。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `q` | string | 是 | 搜索关键词 |

**Response：** 与标准搜索相同的 `SearchResult` 结构。

---

## 9.3 搜索标签

```
GET /tags/filter/search
```

**场景**：标签自动补全。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `q` | string | 是 | 搜索关键词 |
| `limit` | int | 否 | 返回数量限制 |
| `categoryId` | int | 否 | 分类 ID |
| `selected_tags` | string[] | 否 | 已选标签 |
| `filterForInput` | bool | 否 | true 时只返回当前分类允许的标签 |

---

## 9.4 搜索用户（@提及）

```
GET /u/search/users
```

**场景**：编辑器中 @提及用户时的自动补全。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `term` | string | 是 | 搜索词 |
| `topic_id` | int | 否 | 当前话题 ID |
| `category_id` | int | 否 | 当前分类 ID |
| `include_groups` | bool | 否 | 是否包含群组（默认 true） |
| `limit` | int | 否 | 返回数量（默认 6） |

---

## 9.5 验证 @提及

```
GET /composer/mentions
```

**场景**：发帖前验证 @提及的用户名是否有效。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `names[]` | string[] | 是 | 待验证的用户名列表 |

---

## 9.6 最近搜索记录

**获取：**
```
GET /u/recent-searches.json
```

**清空：**
```
DELETE /u/recent-searches.json
```
