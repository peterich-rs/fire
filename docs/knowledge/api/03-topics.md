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

### Fire authoritative topic-detail contract

Fire 当前主详情页不再把 `GET /t/{id}.json` 或 `GET /t/{id}/posts.json` 直接当成平台 UI 契约，而是明确拆成两层：

- Raw source
  - `GET /t/{id}.json` / `GET /t/{id}/{postNumber}.json` 只负责给出 header、body、anchor 与原始 `post_stream.stream`
  - 后续分页只允许按 `post_stream.stream` 的下一个 offset 切 batch，再通过 `post_ids[]` 拉取 raw posts
  - 契约关键字段：`initial_batch_size`、`load_more_batch_size`、`target_post_number`、`next_stream_offset`、`last_loaded_post_id`
- Tree presentation
  - Rust 基于已加载的 raw posts 生成 `reply_rows`、`depth`、`parent_post_number`、`root_post_number`
  - 树状 rows 只属于呈现层，不能反向决定下一批网络边界
  - Fire 的 UniFFI tree presentation 只传 post id / post number / hierarchy 元数据，完整 post payload 仍只来自 source snapshot
  - 当没有显式 `target_post_number` 且查询显式允许首次未读根帖建议时，Rust 会依据 detail header 的 `last_read_post_number` / `highest_post_number` 和已加载根帖计算 `first_unread_root_post_number`；如果首批尚未覆盖首个未读根帖，`fetchTopicDetailPage` 会按现有自动 batch 限额继续拉 source batch，直到找到该根帖、source exhausted，或达到自动补批上限
  - iOS/Android 只在首次打开且没有通知、书签、搜索、分享链接等显式 target 时把该查询开关设为允许并消费 `first_unread_root_post_number`，刷新、load-more、MessageBus 更新不得触发自动补批或自动跳转

每个 raw post 还会保留作者展示元数据：`user_id`、`user_title`、`primary_group_name`、`flair_url`、`flair_name`、`flair_bg_color`、`flair_color`、`flair_group_id`、`admin`、`moderator`、`group_moderator`，以及 `user_status.emoji` / `user_status.description`。Fire 在 Rust 模型中将这些字段收敛为 `TopicPostAuthorMetadata`，通过 UniFFI 暴露给 iOS/Android 原生 runtime cell；平台只负责展示，不重新解析 `post.cooked` 或从 profile API 拼装这些字段。

带有 Boost 插件数据的 raw post 会暴露 `boosts` 与 `can_boost`。Fire 在 Rust 中解析每个 Boost 的 `id`、`cooked`、用户 `id` / `username` / `name` / `avatar_template`、`can_delete`、`can_flag`、`user_flag_status`、`available_flags`，生成去 HTML 的 `display_text`，并通过 UniFFI 暴露同一段 `cooked` 生成的 `render_document`，让原生端能展示 emoji 等富文本附件。iOS/Android 消费 UniFFI 的 `TopicPostBoostState`：原帖且正文可见时可以把 Boost 作为正文 overlay/弹幕展示，回复或无正文目标时使用固定高度的两行手动横向滑动 chips，不做自动 ticker；overlay 展示固定取最多 5 条可见 Boost，最多 5 条 lane，滑动期间暂停并在滑动结束后恢复，避免 Boost 之间重叠或大面积遮挡正文。平台不得重新解析 Boost `cooked` 或把 Boost 与 quote/blockquote preview 混用。

`forceLoad` 当前仍保留在 Fire 主路径查询参数中，用于显式跳过当前 source session 缓存并重新拉取 source snapshot；它属于 Fire 运行时契约，不是 Discourse 原始端点字段。

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

### Fire 主路径约束

- `GET /t/{topicId}/posts.json` 在 Fire 主详情页中只作为 raw-source append 接口使用
- 平台不得自己切 `post_stream.posts` 窗口当主分页，也不得用 root-level rows 反推 `post_ids[]`
- `postNumber` deep link 只影响首包 anchor，不改变后续 load-more 的 raw stream 线性分页模型
- 显式 `target_post_number` 优先于 Rust 的首个未读根帖建议；平台不得用 `first_unread_root_post_number` 覆盖通知、书签、搜索或分享链接定位

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
