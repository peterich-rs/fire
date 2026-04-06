[返回总览](../backend-api.md)

# 话题与帖子

本页覆盖主站最核心的内容接口：话题列表、话题详情、发帖回帖、书签、举报、回应和解决方案。

## 话题列表与详情

### `GET /latest.json`

- 用途：
  - 首页最新话题
  - 按 `topic_ids` 批量回拉指定话题
- 认证：匿名可访问
- Query：
  - `topic_ids?: string`，逗号分隔，例如 `1,2,3`
  - `page?: integer`
  - `order?: string`
  - `ascending?: "true" | "false"`
- 响应：`TopicListResponse`

### `GET /new.json`

- 用途：新话题列表
- Query：
  - `page?: integer`
  - `order?: string`
  - `ascending?: "true" | "false"`
- 响应：`TopicListResponse`

### `GET /unread.json`

- 用途：未读话题列表
- Query：
  - `page?: integer`
  - `order?: string`
  - `ascending?: "true" | "false"`
- 响应：`TopicListResponse`

### `GET /unseen.json`

- 用途：未看过话题列表
- Query：
  - `page?: integer`
  - `order?: string`
  - `ascending?: "true" | "false"`
- 响应：`TopicListResponse`

### `GET /hot.json`

- 用途：热门话题列表
- Query：
  - `page?: integer`
  - `order?: string`
  - `ascending?: "true" | "false"`
- 响应：`TopicListResponse`

### `GET /top.json`

- 用途：Top 话题列表
- 认证：匿名可访问
- 响应：`TopicListResponse`

### `GET /{filter}.json`

- 用途：无分类、无标签时的泛化列表接口
- 典型 `filter`：
  - `latest`
  - `new`
  - `unread`
  - `unseen`
  - `top`
  - `hot`
- Query：
  - `page?: integer`
  - `period?: string`
  - `order?: string`
  - `ascending?: "true" | "false"`
- 响应：`TopicListResponse`

### `GET /c/{categorySlug}.json`

- 用途：分类话题列表
- 认证：匿名可访问
- 响应：`TopicListResponse`

### `GET /c/{categorySlug}/{categoryId}/l/{filter}.json`

### `GET /c/{parentCategorySlug}/{categorySlug}/{categoryId}/l/{filter}.json`

- 用途：分类筛选话题列表
- Query：
  - `tags[]?: string[]`
  - `page?: integer`
  - `period?: string`
  - `order?: string`
  - `ascending?: "true" | "false"`
- 响应：`TopicListResponse`

### `GET /tag/{tag}/l/{filter}.json`

- 用途：标签筛选话题列表
- Query：
  - `tags[]?: string[]`，多标签时追加剩余标签
  - `match_all_tags?: "true"`
  - `page?: integer`
  - `period?: string`
  - `order?: string`
  - `ascending?: "true" | "false"`
- 响应：`TopicListResponse`

### `GET /t/{topicId}.json`

### `GET /t/{topicId}/{postNumber}.json`

- 用途：按数字 ID 获取话题详情
- Query：
  - `track_visit?: true`
  - `filter?: string`
  - `username_filters?: string`
  - `filter_top_level_replies?: true`
- 特殊请求头：
  - `Discourse-Track-View: 1`
  - `Discourse-Track-View-Topic-Id: {topicId}`
- 响应：`TopicDetail`
- 补充说明：
  - `filter_top_level_replies=true` 时，服务端返回可能不包含主贴
  - 当前客户端会在必要时额外请求 `GET /posts/by_number/{topicId}/1` 补回首贴
  - 当前代码同时保留两种消费方式：
    - 共享 Rust Core 的“完整详情”路径会继续按缺失的 `post_ids[]` 调用 `GET /t/{topicId}/posts.json`，补齐整条评论流
    - iOS 帖子详情页的滚动列表路径会先消费首屏 `post_stream.posts`，再依据 `post_stream.stream` 自动分批请求 `GET /t/{topicId}/posts.json?post_ids[]=` 续载后续评论
  - 进入“只看顶层回复”模式后，后续翻页依赖 `post_stream.stream` 和 `GET /t/{topicId}/posts.json?post_ids[]=`，不是继续用 `post_number + asc`

### `GET /t/{slug}.json`

### `GET /t/{slug}/{postNumber}.json`

- 用途：按 slug 获取话题详情
- Query：
  - `track_visit?: true`
- 特殊请求头：
  - `Discourse-Track-View: 1`
- 响应：`TopicDetail`

### `GET /t/{topicId}/posts.json`

- 用途 1：按 `post_ids[]` 批量获取帖子
- Query：

```json
{
  "post_ids[]": [111, 112, 113]
}
```

- 用途 2：按楼层号附近分页获取
- Query：

```json
{
  "post_number": 10,
  "asc": true
}
```

- 响应：

```json
{
  "user_badges": [],
  "post_stream": {
    "posts": [Post],
    "stream": [111, 112],
    "gaps": {
      "before": [],
      "after": []
    }
  }
}
```

- 补充说明：
  - 当前客户端会消费顶层 `user_badges`，并把它注入帖子徽章渲染
  - `post_stream.gaps` 用于处理被屏蔽用户、缺口分页等异常帖子流场景

### `POST /posts.json`

- 用途：创建新话题
- 认证：需要登录
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "title": "标题",
  "raw": "正文 Markdown",
  "category": 1,
  "archetype": "regular",
  "tags[]": ["flutter", "dart"]
}
```

- 开发前置约束：
  - 创建话题前通常要先读取 `siteSettings.min_topic_title_length`、`siteSettings.min_first_post_length`
  - 分类元数据还会决定 `categoryId`、`slug`、`minimum_required_tags`、`required_tag_groups`、`allowed_tags`、`permission`、`topic_template`

- 成功响应常见结构：

```json
{
  "post": {
    "topic_id": 123
  }
}
```

- 审核队列响应：

```json
{
  "action": "enqueued",
  "pending_count": 1
}
```

### `PUT /topics/reset-new.json`

- 用途：忽略新话题
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "dismiss_topics": true,
  "dismiss_posts": false,
  "category_id": 1
}
```

### `PUT /topics/bulk.json`

- 用途：忽略未读话题
- `Content-Type`: `application/json`
- Body：

```json
{
  "filter": "unread",
  "operation": {
    "type": "dismiss_posts"
  },
  "category_id": 1
}
```

### `POST /t/{topicId}/notifications`

- 用途：设置话题通知级别
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "notification_level": 2
}
```

### `PUT /t/-/{topicId}.json`

- 用途：编辑话题标题、分类、标签
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "title": "新标题",
  "category_id": 2,
  "tags[]": ["tag-a", "tag-b"]
}
```

### `GET /discourse-ai/summarization/t/{topicId}`

- 用途：获取 AI 话题摘要
- Query：
  - `skip_age_check?: "true"`
- 响应：

```json
{
  "ai_topic_summary": {
    "summarized_text": "摘要正文",
    "algorithm": "model-name",
    "outdated": false,
    "can_regenerate": false,
    "new_posts_since_summary": 0,
    "updated_at": "2026-03-26T00:00:00Z"
  }
}
```

### `GET /t/{topicId}/1.json`

- 用途：轻量获取主贴 HTML
- 响应：`TopicDetail`，客户端只读取 `post_stream.posts[0].cooked`

## 帖子、回复、书签、举报、解决方案

### `POST /posts.json`

- 用途：回复话题/帖子
- 认证：需要登录
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "topic_id": 123,
  "raw": "回复内容",
  "reply_to_post_number": 2
}
```

- 成功响应：`Post` 或 `{ "post": Post }`

### `GET /posts/{postId}.json`

- 用途：获取单贴完整数据，或只取 `raw`
- 当前编辑流程最少依赖字段：
  - `id`
  - `raw`
  - `post_number`
  - `topic_id`
- 响应：`Post`

### `PUT /posts/{postId}.json`

- 用途：编辑帖子
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "post[raw]": "新的 Markdown 正文",
  "post[edit_reason]": "修改原因"
}
```

- 响应：

```json
{
  "post": Post
}
```

### `DELETE /posts/{postId}.json`

- 用途：删除帖子

### `PUT /posts/{postId}/recover.json`

- 用途：恢复已删除帖子

### `GET /posts/{postId}/reply-history`

- 用途：获取帖子编辑/回复历史
- 响应：`Post[]`

### `GET /posts/{postId}/replies`

- 用途：获取帖子的直接回复列表
- Query：
  - `after?: integer`，默认 `1`
- 响应：`Post[]`

### `GET /posts/by_number/{topicId}/{postNumber}`

- 用途：通过话题 ID + 楼层号获取单贴
- 响应：`Post`

### `GET /posts/{postId}/reply-ids.json`

- 用途：获取回复树中的回复 ID 列表
- 响应：

```json
[
  { "id": 1001 },
  { "id": 1002 }
]
```

### `POST /post_actions`

- 用途 1：点赞
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "id": 111,
  "post_action_type_id": 2
}
```

- 用途 2：举报
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "id": 111,
  "post_action_type_id": 7,
  "message": "举报原因"
}
```

### `DELETE /post_actions/{postId}`

- 用途：取消点赞
- Query：
  - `post_action_type_id=2`

### `GET /post_action_types.json`

- 用途：获取服务端支持的帖子操作类型
- 关键响应字段：
  - `post_action_types`

### `PUT /discourse-reactions/posts/{postId}/custom-reactions/{reaction}/toggle.json`

- 用途：切换帖子回应
- 响应：

```json
{
  "reactions": [PostReaction],
  "current_user_reaction": PostReaction
}
```

### `GET /discourse-reactions/posts/{postId}/reactions-users.json`

- 用途：获取每种回应下的用户列表
- 响应：

```json
{
  "reaction_users": [
    {
      "id": "heart",
      "count": 2,
      "users": [ReactionUser]
    }
  ]
}
```

### `POST /solution/accept`

- 用途：接受答案
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "id": 111
}
```

### `POST /solution/unaccept`

- 用途：取消接受答案
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "id": 111
}
```

### `POST /bookmarks.json`

- 用途：新增 Topic 书签或 Post 书签
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "bookmarkable_id": 123,
  "bookmarkable_type": "Topic",
  "name": "书签备注",
  "reminder_at": "2026-03-26T08:00:00.000Z",
  "auto_delete_preference": 0
}
```

- `bookmarkable_type` 可选：
  - `Topic`
  - `Post`

- 成功响应：

```json
{
  "id": 999
}
```

### `PUT /bookmarks/{bookmarkId}.json`

- 用途：修改书签备注/提醒
- `Content-Type`: `application/json`
- Body：

```json
{
  "name": "新的书签名",
  "reminder_at": "2026-03-27T08:00:00.000Z",
  "auto_delete_preference": 1
}
```

### `PUT /bookmarks/bulk.json`

- 用途：清除书签提醒
- `Content-Type`: `application/json`
- Body：

```json
{
  "bookmark_ids": [999],
  "operation": {
    "type": "clear_reminder"
  }
}
```

### `DELETE /bookmarks/{bookmarkId}.json`

- 用途：删除书签

### `GET /posts/{postId}/cooked.json`

- 用途：获取帖子渲染后的 HTML，常用于隐藏帖恢复查看
- 响应：

```json
{
  "cooked": "<p>html</p>"
}
```

### `POST /clicks/track`

- 用途：上报链接点击
- `Content-Type`: `application/x-www-form-urlencoded`
- Body：

```json
{
  "url": "https://example.com",
  "post_id": 111,
  "topic_id": 123
}
```
