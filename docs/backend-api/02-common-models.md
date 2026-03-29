[返回总览](../backend-api.md)

# 公共数据结构

本页收敛多个模块共用的返回结构、草稿数据格式和常量定义。其它模块文档中提到的 `TopicListResponse`、`Post` 等名称，均以这里为准。

## TopicListResponse

```json
{
  "topic_list": {
    "topics": [Topic],
    "more_topics_url": "/latest?page=1"
  },
  "users": [TopicUser]
}
```

关键字段：

- `topic_list.topics`: 话题数组
- `topic_list.more_topics_url`: 下一页 URL
- `users`: 话题创建者/参与者侧载数据
- `topic_list.topics[].tags`: LinuxDo 当前 `latest` 负载里常见为 `TopicTag[]` 对象数组；旧格式也可能仍是字符串数组，客户端需要兼容两种形态
- `topic_list.topics[].unread_posts` / `new_posts` / `last_read_post_number`: 实际返回里可能为 `null`
- `topic_list.topics[].can_have_answer`: 实际返回里可能为 `null`

## TopicTag

```json
{
  "id": 3,
  "name": "ChatGPT",
  "slug": "chatgpt"
}
```

补充说明：

- 当前 LinuxDo `latest` / topic detail 负载中，`tags` 常见为 `TopicTag[]`
- 旧格式里 `tags` 也可能仍是 `["chatgpt", "flutter"]` 这样的字符串数组
- 客户端共享模型建议统一收敛为结构化 `TopicTag`

## TopicDetail

```json
{
  "id": 123,
  "title": "Topic title",
  "slug": "topic-title",
  "posts_count": 10,
  "category_id": 1,
  "tags": [
    {
      "id": 3,
      "name": "ChatGPT",
      "slug": "chatgpt"
    }
  ],
  "views": 100,
  "like_count": 20,
  "created_at": "2026-03-26T00:00:00Z",
  "last_read_post_number": 3,
  "post_stream": {
    "posts": [Post],
    "stream": [111, 112, 113]
  },
  "details": {
    "notification_level": 1,
    "can_edit": true,
    "created_by": {
      "id": 1,
      "username": "alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
    }
  }
}
```

客户端实际关心的补充字段：

- `bookmarks`
- `accepted_answer`
- `has_accepted_answer`
- `can_vote`
- `vote_count`
- `user_voted`
- `summarizable`
- `has_cached_summary`
- `has_summary`
- `archetype`
- `tags` 在不同接口/站点版本中可能返回 `TopicTag[]` 或旧的字符串数组
- `accepted_answer` 在 topic detail 里常见为对象 `{ post_number, username, ... }`，未采纳时才可能是 `false`
- `bookmarks` 实际是书签对象数组，不是单纯的 ID 列表；常见字段包括 `id`、`bookmarkable_type`、`bookmarkable_id`、`name`、`reminder_at`
- `details` 可能为 `null`
- `category_id`、`notification_level`、`vote_count` 以及帖子内多数字段在实际返回里都应按“可空/可字符串化标量”容错，而不要假设总是稳定的 JSON 标量类型

## Post

```json
{
  "id": 111,
  "username": "alice",
  "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
  "cooked": "<p>html</p>",
  "post_number": 1,
  "post_type": 1,
  "created_at": "2026-03-26T00:00:00Z",
  "updated_at": "2026-03-26T00:00:00Z",
  "like_count": 3,
  "reply_count": 1,
  "reply_to_post_number": 0,
  "bookmarked": false,
  "bookmark_id": null,
  "reactions": [],
  "current_user_reaction": null,
  "polls": [],
  "accepted_answer": false,
  "can_edit": false,
  "can_delete": false,
  "can_recover": false,
  "hidden": false
}
```

补充说明：

- `username`、`cooked`、`like_count`、`reply_count`、`bookmarked`、`accepted_answer`、`can_edit`、`can_delete`、`can_recover`、`hidden` 在实际负载里都应按可空字段容错
- `reactions` 可能为 `null` 或空数组

## User

```json
{
  "id": 1,
  "username": "alice",
  "name": "Alice",
  "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
  "trust_level": 3,
  "bio_cooked": "<p>bio</p>",
  "created_at": "2026-03-26T00:00:00Z",
  "last_seen_at": "2026-03-26T00:00:00Z",
  "can_follow": true,
  "is_followed": false,
  "muted": false,
  "ignored": false
}
```

## UserSummary

```json
{
  "user_summary": {
    "days_visited": 100,
    "posts_read_count": 1000,
    "likes_received": 50,
    "likes_given": 80,
    "topic_count": 20,
    "post_count": 200,
    "time_read": 36000,
    "bookmark_count": 5
  },
  "topics": [],
  "badges": []
}
```

## SearchResult

```json
{
  "posts": [SearchPost],
  "topics": [SearchTopic],
  "users": [SearchUser],
  "grouped_search_result": {
    "term": "flutter",
    "more_posts": true,
    "more_users": false,
    "more_categories": false,
    "more_full_page_results": true,
    "search_log_id": 123
  }
}
```

## NotificationListResponse

```json
{
  "notifications": [DiscourseNotification],
  "total_rows_notifications": 100,
  "seen_notification_id": 1234,
  "load_more_notifications": "/notifications?offset=60"
}
```

## DraftData

保存草稿时 `data` 字段实际是一个 JSON 字符串，结构如下：

```json
{
  "reply": "正文",
  "title": "标题",
  "categoryId": 1,
  "tags": ["flutter", "dart"],
  "replyToPostNumber": 2,
  "action": "create_topic",
  "recipients": ["alice", "bob"],
  "archetypeId": "regular",
  "composerTime": 120000,
  "typingTime": 45000
}
```

`action` 可选值：

- `create_topic`
- `reply`
- `private_message`

## MessageBusMessage

```json
{
  "channel": "/topic/123",
  "message_id": 10001,
  "data": {}
}
```

## 枚举与常量

Topic 通知级别：

| 值 | 含义 |
| --- | --- |
| `0` | muted |
| `1` | regular |
| `2` | tracking |
| `3` | watching |

Category 通知级别：

| 值 | 含义 |
| --- | --- |
| `0` | muted |
| `1` | regular |
| `2` | tracking |
| `3` | watching |
| `4` | watching_first_post |

Bookmark 自动删除偏好：

| 值 | 含义 |
| --- | --- |
| `0` | never |
| `1` | when_reminder_sent |
| `2` | on_owner_reply |
| `3` | clear_reminder |

帖子操作类型：

| 值 | 含义 |
| --- | --- |
| `2` | 点赞 |
| `3` | Off Topic 举报 |
| `4` | Inappropriate 举报 |
| `7` | Notify Moderators / Other |
| `8` | Spam 举报 |

用户订阅级别字符串：

- `normal`
- `mute`
- `ignore`
