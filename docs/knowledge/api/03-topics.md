# 话题 API

## 1. 最新话题列表

```http
GET /latest.json
```

### Query Parameters

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `page` | integer | 否 | 页码；通常从 `0` 开始，首屏可省略 |
| `order` | string | 否 | 排序字段 |
| `ascending` | boolean/string | 否 | 是否升序 |
| `topic_ids` | string | 否 | 逗号分隔 topic id；用于按 ID 批量刷新话题卡片 |

### Response

```json
{
  "topic_list": {
    "topics": [
      {
        "id": 123,
        "title": "话题标题",
        "fancy_title": "话题标题",
        "slug": "topic-slug",
        "category_id": 1,
        "tags": ["tag1"],
        "posts_count": 10,
        "reply_count": 9,
        "like_count": 5,
        "views": 100,
        "created_at": "2024-01-01T00:00:00.000Z",
        "last_posted_at": "2024-01-02T00:00:00.000Z",
        "highest_post_number": 10,
        "unseen": false,
        "new_posts": 2,
        "unread_posts": 1,
        "bookmarked": false,
        "liked": false,
        "pinned": false,
        "closed": false,
        "archived": false,
        "posters": [
          {
            "user_id": 1,
            "username": "user1",
            "avatar_template": "/user_avatar/...",
            "description": "Original Poster"
          }
        ]
      }
    ],
    "more_topics_url": "/latest?page=1"
  },
  "users": [],
  "primary_groups": [],
  "flair_groups": []
}
```

The `users`, `primary_groups`, and `flair_groups` arrays may be present and should be used to resolve compact topic/poster references when needed.

## 2. Filtered Topic Lists

```http
GET /{filter}.json
GET /c/{category_slug}/{category_id}/l/{filter}.json
GET /c/{parent_category_slug}/{category_slug}/{category_id}/l/{filter}.json
GET /tag/{tag_name}/l/{filter}.json
```

Common filters include `latest`, `top`, `new`, `unread`, `unseen`, and `hot`.

### Query Parameters

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `page` | integer | 否 | 页码 |
| `period` | string | 否 | `top` 等筛选使用的时间范围，如 `daily`/`weekly`/`monthly`/`yearly` |
| `order` | string | 否 | 排序字段 |
| `ascending` | boolean/string | 否 | 是否升序 |
| `subset` | string | 否 | 子过滤，例如新话题列表的二级过滤 |
| `tags[]` | string[] | 否 | 分类内标签筛选，或多标签筛选时除第一个标签外的其余标签 |
| `match_all_tags` | boolean/string | 否 | 多标签筛选时设为 `true`，表示同时匹配所有标签 |

Response shape is the same as `GET /latest.json`.

## 3. Common Topic List Shortcuts

| Purpose | Endpoint | Notes |
|---|---|---|
| New topics | `GET /new.json` | Supports `page`, `order`, `ascending`, `subset` |
| Unread topics | `GET /unread.json` | Supports `page`, `order`, `ascending` |
| Unseen topics | `GET /unseen.json` | Supports `page`, `order`, `ascending` |
| Hot topics | `GET /hot.json` | Supports `page`, `order`, `ascending` |
| Top topics | `GET /top.json` | Can also be represented by filtered list paths |
| Category topics | `GET /c/{category_slug}.json` | Lightweight category topic list |

## 4. Topic Detail

```http
GET /t/{topic_id}.json
GET /t/{topic_id}/{post_number}.json
GET /t/{slug}.json
GET /t/{slug}/{post_number}.json
```

`post_number` anchors the initial detail response around a specific floor. Access by slug returns the real topic id in the response payload.

### Query Parameters

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `track_visit` | boolean | 否 | Whether to record a topic visit |
| `filter` | string | 否 | Server-side post filter |
| `username_filters` | string | 否 | Username filter string |
| `filter_top_level_replies` | boolean | 否 | Filter top-level replies |

When `track_visit=true`, browser requests also send:

```http
Discourse-Track-View: 1
Discourse-Track-View-Topic-Id: <topic_id>
```

The topic-id header is only possible when the client already knows the numeric topic id.

### Response

The response is a topic object with metadata and a `post_stream`:

```json
{
  "id": 123,
  "title": "话题标题",
  "slug": "topic-slug",
  "posts_count": 42,
  "highest_post_number": 42,
  "last_read_post_number": 12,
  "post_stream": {
    "posts": [
      {
        "id": 1001,
        "post_number": 1,
        "post_type": 1,
        "username": "user1",
        "name": "User One",
        "avatar_template": "/user_avatar/...",
        "cooked": "<p>HTML</p>",
        "created_at": "2024-01-01T00:00:00.000Z",
        "updated_at": "2024-01-01T00:00:00.000Z",
        "reply_to_post_number": null,
        "reply_count": 2,
        "reads": 10,
        "score": 1,
        "yours": false,
        "can_edit": false,
        "can_delete": false,
        "actions_summary": []
      }
    ],
    "stream": [1001, 1002, 1003]
  },
  "details": {
    "can_reply_as_new_topic": true,
    "can_flag_topic": true
  }
}
```

Post payloads may include additional display and plugin fields. Preserve unknown fields when possible. Common useful fields include author flair data (`user_title`, `primary_group_name`, `flair_url`, `flair_name`, `flair_bg_color`, `flair_color`, `flair_group_id`), moderator/admin booleans, `user_status`, polls, reactions, accepted-answer data, and Boost plugin data such as `boosts` and `can_boost`.

## 5. Batch Load Posts

```http
GET /t/{topic_id}/posts.json
```

Used to load post payloads after a topic detail response exposes post IDs in `post_stream.stream`.

### Query Parameters

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `post_ids[]` | integer[] | 条件必填 | Repeated post IDs to load |
| `post_number` | integer | 条件必填 | Anchor post number for number-based loading |
| `asc` | boolean | 否 | Sort direction when using `post_number` |

Use one mode per request:

```text
post_ids[]=1001&post_ids[]=1002
```

or:

```text
post_number=20&asc=true
```

### Response Variants

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
  - iOS/Android 可以在同一份 tree presentation 上默认只展示根回复，把二级及更深回复折叠到根回复的“查看更多 N 条回复”入口；显式跳转目标位于折叠层级时，只临时展示目标的祖先链路，不能为了折叠另建 source 或重新定义分页边界
  - 当没有显式 `target_post_number` 且查询显式允许首次未读根帖建议时，Rust 会依据 detail header 的 `last_read_post_number` / `highest_post_number` 和已加载根帖计算 `first_unread_root_post_number`；如果首批尚未覆盖首个未读根帖，`fetchTopicDetailPage` 会按现有自动 batch 限额继续拉 source batch，直到找到该根帖、source exhausted，或达到自动补批上限
  - iOS/Android 只在首次打开且没有通知、书签、搜索、分享链接等显式 target 时把该查询开关设为允许并消费 `first_unread_root_post_number`，刷新、load-more、MessageBus 更新不得触发自动补批或自动跳转

每个 raw post 还会保留作者展示元数据：`user_id`、`user_title`、`primary_group_name`、`flair_url`、`flair_name`、`flair_bg_color`、`flair_color`、`flair_group_id`、`admin`、`moderator`、`group_moderator`，以及 `user_status.emoji` / `user_status.description`。Fire 在 Rust 模型中将这些字段收敛为 `TopicPostAuthorMetadata`，通过 UniFFI 暴露给 iOS/Android 原生 runtime cell；平台只负责展示，不重新解析 `post.cooked` 或从 profile API 拼装这些字段。

带有 Boost 插件数据的 raw post 会暴露 `boosts` 与 `can_boost`。Fire 在 Rust 中解析每个 Boost 的 `id`、`cooked`、用户 `id` / `username` / `name` / `avatar_template`、`can_delete`、`can_flag`、`user_flag_status`、`available_flags`，生成去 HTML 且去掉开头 `@username:` / `username:` / display name 前缀的正文-only `display_text`，并通过 UniFFI 暴露同一段 `cooked` 生成的 `render_document`，让原生端能展示 emoji 等富文本附件。iOS/Android 消费 UniFFI 的 `TopicPostBoostState`：原帖且正文可见时可以把 Boost 作为正文 overlay/弹幕展示，回复或无正文目标时使用固定高度的两行手动横向滑动 chips，不做自动 ticker；overlay 展示固定取最多 5 条可见 Boost，最多 5 条 lane，每个 post/Boost 批次只播放一次，运行中可以随滚动暂停并在滚动结束后恢复，播放完成后隐藏，避免 Boost 之间重叠或大面积遮挡正文。平台不得重新解析 Boost `cooked`、不得重新添加作者前缀，或把 Boost 与 quote/blockquote preview 混用。

`forceLoad` 当前仍保留在 Fire 主路径查询参数中，用于显式跳过当前 source session 缓存并重新拉取 source snapshot；它属于 Fire 运行时契约，不是 Discourse 原始端点字段。

Wrapped response:

```json
{
  "post_stream": {
    "posts": []
  },
  "badges": {}
}
```

Bare post-stream response:

```json
{
  "posts": []
}
```

Clients should accept both shapes. Top-level topic metadata such as `badges` can accompany the wrapped shape and may be needed to enrich post/user presentation.

## 6. First Post Cooked HTML

```http
GET /t/{topic_id}/1.json
```

This is a detail request anchored at the first post. A lightweight client can read:

```json
{
  "post_stream": {
    "posts": [
      {
        "post_number": 1,
        "cooked": "<p>HTML content</p>"
      }
    ]
  }
}
```

## 7. Create Topic

```http
POST /posts.json
Content-Type: application/x-www-form-urlencoded
```

### Form Fields

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `title` | string | 是 | Topic title |
| `raw` | string | 是 | Markdown body |
| `category` | integer | 是 | Category id |
| `archetype` | string | 是 | Usually `regular` |
| `tags[]` | string[] | 否 | Repeated tag values |

### Response Variants

Nested post envelope:

```json
{
  "post": {
    "id": 1001,
    "topic_id": 123,
    "post_number": 1
  }
}
```

Root topic id:

```json
{
  "topic_id": 123
}
```

Queued for moderation:

```json
{
  "action": "enqueued",
  "pending_count": 1
}
```

Validation failure:

```json
{
  "success": false,
  "errors": ["Title is too short"]
}
```

Clients should derive the created topic id from `post.topic_id` first, then root `topic_id`.

## 8. Update Topic Metadata

```http
PUT /t/-/{topic_id}.json
Content-Type: application/x-www-form-urlencoded
```

### Form Fields

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `title` | string | 否 | New title |
| `category_id` | integer | 否 | New category id |
| `tags[]` | string[] | 否 | Repeated tag values |

## 9. Dismiss New Topics

```http
PUT /topics/reset-new.json
Content-Type: application/x-www-form-urlencoded
```

### Form Fields

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `dismiss_topics` | boolean | 是 | Mark new topics as seen |
| `dismiss_posts` | boolean | 是 | Also dismiss new posts |
| `category_id` | integer | 否 | Limit to a category |

## 10. Dismiss Unread Topics

```http
PUT /topics/bulk.json
Content-Type: application/json
```

```json
{
  "filter": "unread",
  "operation": {
    "type": "dismiss_posts"
  },
  "category_id": 1
}
```

`category_id` is optional.

## 11. Topic Notification Level

```http
POST /t/{topic_id}/notifications
Content-Type: application/x-www-form-urlencoded
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `notification_level` | integer | 是 | Discourse notification level, commonly `0` muted, `1` regular, `2` tracking, `3` watching |

## 12. Topic AI Summary

```http
GET /discourse-ai/summarization/t/{topic_id}
```

### Query Parameters

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `skip_age_check` | boolean/string | 否 | Request a summary even when the topic age check would normally skip it |

### Response

```json
{
  "ai_topic_summary": {
    "summarized_text": "...",
    "algorithm": "...",
    "created_at": "2024-01-01T00:00:00.000Z"
  }
}
```

`404` or `403` can mean the summary capability is unavailable or not visible to the current user.
