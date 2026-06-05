# 话题 API

> 对应 FluxDO 源文档第 6 节

---

## 6.1 获取最新话题列表

```
GET /latest.json
```

**场景**：首页加载话题列表。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 否 | 页码（从 0 开始） |
| `order` | string | 否 | 排序方式 |
| `ascending` | string | 否 | "true"/"false" |
| `topic_ids` | string | 否 | 逗号分隔的 topic ID 列表（批量查询） |

**Response (200)：**

```json
{
  "topic_list": {
    "topics": [
      {
        "id": 123,
        "title": "话题标题",
        "slug": "topic-slug",
        "category_id": 1,
        "tags": ["tag1"],
        "posts_count": 10,
        "reply_count": 9,
        "like_count": 5,
        "views": 100,
        "created_at": "2024-01-01T00:00:00.000Z",
        "last_posted_at": "2024-01-02T00:00:00.000Z",
        "poster_count": 3,
        "unseen": false,
        "new_posts": 2,
        "unread_posts": 1,
        "highest_post_number": 10,
        "fancy_title": "...",
        "bookmarked": false,
        "liked": false,
        "pinned": false,
        "closed": false,
        "archived": false,
        "thumbnails": [...],
        "posters": [
          {
            "user_id": 1,
            "description": "Original Poster",
            "avatar_template": "...",
            "username": "user1"
          }
        ]
      }
    ],
    "more_topics_url": "/latest?page=1"
  }
}
```

---

## 6.2 获取筛选话题列表

```
GET /{filter}.json
GET /c/{categorySlug}/{categoryId}/l/{filter}.json
GET /c/{parentCategorySlug}/{categorySlug}/{categoryId}/l/{filter}.json
GET /tag/{tagName}/l/{filter}.json
```

**场景**：按分类/标签/时间维度筛选话题。

**Path Parameters：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `filter` | string | `latest`/`top`/`new`/`unread`/`unseen`/`hot` 等 |
| `categorySlug` | string | 分类 URL slug |
| `categoryId` | int | 分类 ID |
| `parentCategorySlug` | string | 父分类 slug（子分类时使用） |
| `tagName` | string | 标签名 |

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 否 | 页码 |
| `period` | string | 否 | 时间范围（如 `weekly`/`monthly`/`yearly`） |
| `order` | string | 否 | 排序方式 |
| `ascending` | string | 否 | "true"/"false" |
| `subset` | string | 否 | 子集过滤 |
| `tags[]` | string[] | 否 | 额外标签过滤（分类+标签或纯多标签时使用） |
| `match_all_tags` | string | 否 | "true"（多标签时使用，匹配全部标签） |

**Response：** 同 6.1 `TopicListResponse` 结构。

---

## 6.3 获取新话题 / 未读 / 未见 / 热门 / Top

| 接口 | URL |
|------|-----|
| 新话题 | `GET /new.json` |
| 未读 | `GET /unread.json` |
| 未见 | `GET /unseen.json` |
| 热门 | `GET /hot.json` |
| Top | `GET /top.json` |

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 否 | 页码 |
| `order` | string | 否 | 排序 |
| `ascending` | string | 否 | "true"/"false" |
| `subset` | string | 否 | 仅 `/new.json` |

**Response：** 同 `TopicListResponse`。

---

## 6.4 获取话题详情

```
GET /t/{id}.json
GET /t/{id}/{postNumber}.json
GET /t/{slug}.json
GET /t/{slug}/{postNumber}.json
```

**场景**：进入话题详情页。`postNumber` 用于定位到特定楼层。

**Path Parameters：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `id` | int | 话题 ID |
| `slug` | string | 话题 slug（通过 URL 分享的链接） |
| `postNumber` | int | 目标帖子楼层号 |

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `track_visit` | bool | 否 | 是否记录访问 |
| `filter` | string | 否 | 帖子过滤 |
| `username_filters` | string | 否 | 用户名过滤 |
| `filter_top_level_replies` | bool | 否 | 仅显示顶层回复 |

**Request Headers（track_visit=true 时额外添加）：**

```
Discourse-Track-View: 1
Discourse-Track-View-Topic-Id: <topicId>  （仅通过 ID 访问时）
```

**Response (200)：** `TopicDetail` 对象，包含 `post_stream`（含 posts 列表）、topic 元数据等。

---

## 6.5 批量获取帖子

```
GET /t/{topicId}/posts.json
```

**场景**：话题详情页滚动加载更多帖子。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `post_ids[]` | int[] | 是 | 帖子 ID 列表 |
| `post_number` | int | 否 | 按楼层号获取 |
| `asc` | bool | 否 | 升序排列 |

两种模式：
1. 按 ID 列表：`post_ids[]=1&post_ids[]=2&post_ids[]=3`
2. 按楼层号：`post_number=5&asc=true`

**Response (200)：**

```json
{
  "post_stream": {
    "posts": [...]
  },
  "badges": {...}
}
```

---

## 6.6 获取话题第一楼内容

```
GET /t/{topicId}/1.json
```

**场景**：轻量获取话题首帖 HTML 内容。

**Response (200)：**

```json
{
  "post_stream": {
    "posts": [
      {
        "cooked": "<p>HTML 内容</p>"
      }
    ]
  }
}
```

---

## 6.7 获取分类话题

```
GET /c/{categorySlug}.json
```

**场景**：获取指定分类的话题列表。

**Response：** 同 `TopicListResponse`。

---

## 6.8 创建话题

```
POST /posts.json
Content-Type: application/x-www-form-urlencoded
```

**场景**：用户发布新话题。

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `title` | string | 是 | 话题标题 |
| `raw` | string | 是 | 正文内容（Markdown） |
| `category` | int | 是 | 分类 ID |
| `archetype` | string | 是 | 固定值 `"regular"` |
| `tags[]` | string[] | 否 | 标签列表 |

**Response (200)：**

```json
{
  "post": {
    "topic_id": 12345,
    "id": 67890,
    ...
  }
}
```

**特殊响应 - 审核队列：**

```json
{
  "action": "enqueued",
  "pending_count": 3
}
```

此时客户端抛出 `PostEnqueuedException`。

---

## 6.9 更新话题元数据

```
PUT /t/-/{topicId}.json
Content-Type: application/x-www-form-urlencoded
```

**场景**：编辑话题标题、分类、标签。

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `title` | string | 否 | 新标题 |
| `category_id` | int | 否 | 新分类 ID |
| `tags[]` | string[] | 否 | 新标签列表 |

---

## 6.10 忽略新话题

```
PUT /topics/reset-new.json
Content-Type: application/x-www-form-urlencoded
```

**场景**：一键忽略所有新话题。

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `dismiss_topics` | bool | 是 | 是否忽略话题 |
| `dismiss_posts` | bool | 是 | 是否忽略帖子 |
| `category_id` | int | 否 | 限定分类 ID |

---

## 6.11 忽略未读话题

```
PUT /topics/bulk.json
```

**场景**：一键忽略所有未读话题。

**Request Body（JSON）：**

```json
{
  "filter": "unread",
  "operation": {
    "type": "dismiss_posts"
  },
  "category_id": 1
}
```

---

## 6.12 设置话题通知级别

```
POST /t/{topicId}/notifications
Content-Type: application/x-www-form-urlencoded
```

**场景**：订阅/取消订阅话题通知。

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `notification_level` | int | 是 | 通知级别（0=静默, 1=普通, 2=追踪, 3=关注） |

---

## 6.13 获取话题 AI 摘要

```
GET /discourse-ai/summarization/t/{topicId}
```

**场景**：获取话题的 AI 生成摘要。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `skip_age_check` | string | 否 | "true" 跳过年龄检查 |

**Response (200)：**

```json
{
  "ai_topic_summary": {
    "summarized_text": "AI 生成的摘要文本...",
    "topic_id": 123
  }
}
```

**Response (403/404)：** 返回 `null`（无摘要或无权限）。
