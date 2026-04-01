[返回总览](../backend-api.md)

# 用户、搜索与通知

本页覆盖用户资料、徽章、关注关系、邀请、搜索能力和通知读取/已读操作。

## 用户与徽章

### `GET /u/{username}.json`

- 用途：获取用户详情
- 当前 profile 页常用字段：
  - `user.id`
  - `user.username`
  - `user.name`
  - `user.avatar_template`
  - `user.can_follow`
  - `user.is_followed`
  - `user.total_followers`
  - `user.total_following`
  - `user.can_send_private_message_to_user`
  - `user.muted`
  - `user.ignored`
  - `user.can_mute_user`
  - `user.can_ignore_user`
  - `user.flair_name`
  - `user.flair_url`
  - `user.profile_background`
  - `user.suspended_till`
  - `user.silenced_till`
- 响应：

```json
{
  "user": User
}
```

### `GET /u/{username}/summary.json`

- 用途：获取用户摘要统计
- 当前客户端还会消费的汇总字段：
  - `topics`
  - `replies`
  - `links`
  - `most_replied_to_users`
  - `most_liked_by_users`
  - `most_liked_users`
  - `top_categories`
- 响应：`UserSummary`

### `GET /user_actions.json`

- 用途：获取用户动态
- Query：
  - `username: string`
  - `offset: integer`
  - `filter?: string`
- 响应：
  - `user_actions`
  - `topics`
  - `users`

### `GET /discourse-reactions/posts/reactions.json`

- 用途：获取某用户的回应列表
- Query：
  - `username: string`
  - `before_reaction_user_id?: integer`
- 响应：`UserReactionsResponse`

### `GET /u/{username}/follow/following`

- 用途：获取关注列表
- 响应：`FollowUser[]`

### `GET /u/{username}/follow/followers`

- 用途：获取粉丝列表
- 响应：`FollowUser[]`

### `PUT /follow/{username}`

- 用途：关注用户

### `DELETE /follow/{username}`

- 用途：取消关注用户

### `PUT /u/{username}/notification_level.json`

- 用途：设置用户订阅级别
- `Content-Type`: `application/json`
- Body：

```json
{
  "notification_level": "mute",
  "expiring_at": "2026-03-27T00:00:00.000Z"
}
```

### `GET /read.json`

- 用途：获取浏览历史
- Query：
  - `page?: integer`
- 响应：`TopicListResponse`

### `GET /u/{username}/bookmarks.json`

- 用途：获取用户书签页
- `username` 常见来源：
  - 首页 `data-preloaded.currentUser.username`
  - 登录页 HTML `meta[name="current-username"]`
  - 主站响应头 `x-discourse-username`
- Query：
  - `page?: integer`
- 响应：`TopicListResponse`

### `GET /topics/created-by/{username}.json`

- 用途：获取用户创建的话题
- Query：
  - `page?: integer`
- 响应：`TopicListResponse`

### `GET /user-badges/{username}.json`

- 用途：获取某用户已获得徽章
- Query：
  - `grouped=true`
- 响应：`BadgeDetailResponse`

### `GET /badges/{badgeId}.json`

- 用途：获取单个徽章信息
- 响应：

```json
{
  "badge": Badge
}
```

### `GET /user_badges.json`

- 用途：获取徽章获奖用户列表
- Query：
  - `badge_id: integer`
  - `username?: string`
- 响应：`BadgeDetailResponse`

### `GET /u/{username}/invited/pending`

- 用途：获取待使用邀请链接
- 响应兼容多种结构，客户端统一解析为：

```json
[
  {
    "invite_link": "https://linux.do/invites/xxxx",
    "invite": {
      "id": 1,
      "invite_key": "xxxx",
      "max_redemptions_allowed": 5,
      "redemption_count": 1,
      "expired": false,
      "created_at": "2026-03-26T00:00:00Z",
      "expires_at": "2026-03-30T00:00:00Z"
    }
  }
]
```

### `POST /invites`

- 用途：创建邀请链接
- `Content-Type`: `application/json`
- Body：

```json
{
  "max_redemptions_allowed": 5,
  "expires_at": "2026-03-30T00:00:00.000Z",
  "description": "说明",
  "email": "test@example.com"
}
```

- 响应：`InviteLinkResponse`
- 补充说明：
  - 成功响应可能直接给 `invite_link`
  - 也可能只返回 `invite_key` / `invite_url` / `url` / `link`
  - 当前客户端在拿不到完整链接时，会回查 `GET /u/{username}/invited/pending`

## 搜索

### `GET /search.json`

- 用途：普通搜索
- Query：
  - `q: string`
  - `page?: integer`，当前搜索首屏通常按 `page=1`
  - `type_filter?: "topic" | "post" | "user" | "category" | "tag"`
- `q` 不是只传裸关键词；当前客户端会拼接 Discourse 搜索 DSL，例如：
  - `topic:123 关键词`
  - `in:bookmarks`
  - `in:created`
  - `in:seen`
  - `#category`
  - `#parent:child`
  - `tags:flutter`
  - `status:open`
  - `after:2026-03-01`
  - `before:2026-03-31`
  - `order:latest_topic`
- 分页注意：
  - 当前服务层约定：只有指定 `type_filter` 时翻页才可靠生效
- 当前客户端常用最小返回字段：
  - `posts[].id`
  - `posts[].blurb`
  - `posts[].post_number`
  - `posts[].topic_id`
  - `posts[].topic_title_headline`
  - `topics[].id`
  - `topics[].category_id`
  - `topics[].tags`
  - `topics[].views`
  - `topics[].closed`
  - `topics[].archived`
- 响应：`SearchResult`

### `GET /discourse-ai/embeddings/semantic-search`

- 用途：AI 语义搜索
- 前置条件：
  - 站点启用了 `discourse-ai`
  - 相关 `siteSettings` 已开启语义搜索能力
- Query：
  - `q: string`
- 响应：`SearchResult`

### `GET /u/recent-searches.json`

- 用途：获取最近搜索词
- 响应：

```json
{
  "recent_searches": ["flutter", "linux"]
}
```

### `DELETE /u/recent-searches.json`

- 用途：清空最近搜索

### `GET /tags/filter/search`

- 用途：标签搜索，兼容筛选和发帖场景
- Query：
  - `q?: string`
  - `filterForInput?: true`
  - `limit?: integer`
  - `categoryId?: integer`
  - `selected_tags?: string[]`
- 响应：

```json
{
  "results": [
    {
      "name": "flutter",
      "text": "flutter",
      "count": 100
    }
  ],
  "required_tag_group": {
    "name": "platform",
    "min_count": 1
  }
}
```

### `GET /u/search/users`

- 用途：`@` 提及自动补全
- Query：
  - `term: string`
  - `include_groups: boolean`
  - `limit: integer`
  - `topic_id?: integer`
  - `category_id?: integer`
- 响应：

```json
{
  "users": [UserMentionUser],
  "groups": [UserMentionGroup]
}
```

### `GET /composer/mentions`

- 用途：校验 `@用户名` / `@群组` 是否有效
- Query：
  - `names[]: string[]`
- 响应：

```json
{
  "valid": ["alice"],
  "groups": {
    "staff": {
      "user_count": false,
      "max_mentions": 10
    }
  },
  "cannot_see": [],
  "groups_with_too_many_members": [],
  "invalid_groups": []
}
```

## 通知

### `GET /notifications`

- 用途 1：快捷面板最近通知
- Query：

```json
{
  "recent": true,
  "limit": 30,
  "bump_last_seen_reviewable": true
}
```

- 用途 2：完整分页通知
- Query：

```json
{
  "limit": 60,
  "offset": 60
}
```

- 响应：`NotificationListResponse`
- 当前通知列表/跳转最少依赖字段：
  - `notifications[].id`
  - `notifications[].notification_type`
  - `notifications[].read`
  - `notifications[].high_priority`
  - `notifications[].created_at`
  - `notifications[].topic_id`
  - `notifications[].post_number`
  - `notifications[].slug`
  - `notifications[].fancy_title`
  - `notifications[].acting_user_avatar_template`
  - `notifications[].data.*`
- 补充说明：
  - 当前未读角标和 recent 同步不只依赖该接口
  - 首次计数来自 `currentUser`
  - 实时增量依赖 MessageBus `/notification/{userId}`，详见 [07. MessageBus 长轮询](07-messagebus.md)

### `PUT /notifications/mark-read`

- 用途 1：全部标记已读
- Body：空

- 用途 2：单条标记已读
- `Content-Type`: `application/json`
- Body：

```json
{
  "id": 1234
}
```
