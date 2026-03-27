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

## TopicDetail

```json
{
  "id": 123,
  "title": "Topic title",
  "slug": "topic-title",
  "posts_count": 10,
  "category_id": 1,
  "tags": ["flutter"],
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
