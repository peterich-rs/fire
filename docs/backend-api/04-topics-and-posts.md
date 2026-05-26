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
  - 当前话题详情页由共享 Rust Core 拆成三个消费段：
    - `header`：标题与话题元数据，进入详情时可复用首页已有标题，再由详情返回值轻量校正
    - `body`：固定为 `post_number == 1` 的主贴；如果 `filter_top_level_replies=true` 的负载里缺失，Rust 会额外请求 `GET /posts/by_number/{topicId}/1`
    - `response`：仅包含 `post_number > 1` 的回复树
  - 当前回复区分页不再按整条 `post_stream.stream` 平铺补齐，而是由 Rust 先用 `filter_top_level_replies=true` 获取顶层回复根列表，再按根分支分页
  - 当前 Rust 会按根分支调用 `GET /posts/{postId}/reply-ids.json` 获取整棵回复子树的帖子 ID，再按批次调用 `GET /t/{topicId}/posts.json?post_ids[]=` 拉取该分支的完整帖子并构建树序行
  - 当前 iOS 和 Android 都会消费 `post_stream.posts[].polls` 和 `post_stream.posts[].polls_votes`，用于在 topic detail 渲染原生 poll 卡片并恢复当前用户的已选项
  - 当前共享 Rust 解析 `post_stream.posts[].reply_to_user`，并通过 UniFFI 暴露到 `TopicPostState.reply_to_user` / `replyToUser`；iOS / Android 用它把回复关系显示为 `回复 @username`，缺失时才回退到 `reply_to_post_number`
  - 当前 iOS 也会消费顶层 `archetype` 以及 `details.participants[]`，用于把 `private_message` 线程渲染成私信详情页，并在头部展示会话参与者
  - `details.created_by`、`post_stream.posts[].current_user_reaction` 这类可选嵌套对象如果类型漂移，Fire 会将其按缺失处理，而不是让整个详情解析失败

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

- 当前客户端映射：
  - `0`: muted
  - `1`: regular
  - `2`: tracking
  - `3`: watching
  - iOS / Android 当前只在普通公开话题里暴露这个入口；`archetype = "private_message"` 的私信线程会隐藏话题通知级别设置

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

- 当前客户端行为：
  - iOS 在 topic detail 顶栏 menu 提供原生 topic editor
  - 成功后会刷新当前 topic detail，并触发首页话题流同步刷新
  - iOS 当前不会对私信线程暴露这个编辑入口；`private_message` 仍复用详情页，但不允许走公开话题编辑能力
  - Android 话题详情页在 `details.can_edit` / `details.canEdit` 为 true 时显示顶部编辑入口
  - Android 编辑器提交前复用共享 bootstrap 的 `min_topic_title_length` / `minTopicTitleLength`、`site.categories[].permission`、`minimum_required_tags` 和 `allowed_tags` 做本地校验；保存后刷新当前 topic detail

### `GET /discourse-ai/summarization/t/{topicId}`

- 用途：获取 AI 话题摘要
- Query：
  - `skip_age_check?: "true"`
- 当前客户端行为：
  - 共享 Rust 层通过 `fetch_topic_ai_summary` 请求并解析 `ai_topic_summary`，再通过 `TopicAiSummaryState` 暴露给 iOS / Android
  - 普通 `403` / `404` 按“当前话题没有可展示摘要或当前用户不可取摘要”处理，返回空摘要；Cloudflare challenge 形态的 `403` 仍返回 `CloudflareChallenge`，由宿主走交互式恢复
  - iOS 和 Android topic detail 在 `summarizable` / `has_cached_summary` / `has_summary` 为真时非阻塞加载并渲染 AI 摘要；摘要缺失不占位，加载失败只影响摘要卡片，不阻塞正文详情
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
- 渲染备注：共享 Rust 层现在用 `scraper` / `html5ever` 解析 Discourse `cooked` HTML，产出扁平 cooked-HTML AST、共享纯文本、图片 URL 和链接 URL，并通过顶层 UniFFI `parseCookedHtml` 暴露给宿主。宿主仍负责高性能原生渲染和排版；iOS 现有富文本 renderer 继续覆盖 inline emoji、链接图片原图优先、引用块、列表、details/spoiler、简单表格、onebox/video 降级链接、group mention、hashtag 和站内 topic/profile/badge 链接；Android 话题详情正文现在也消费同一 Rust AST，原生渲染段落、标题、引用、列表、代码块、details/spoiler、表格文本降级、链接/mention/hashtag span，以及图片/onebox/iframe/附件降级卡片。

## 帖子、回复、书签、举报、解决方案

### `POST /posts.json`

- 用途：创建主题、回复话题/帖子，也可用同一端点创建私信
- 认证：需要登录
- `Content-Type`: `application/x-www-form-urlencoded`
- 创建公开主题 Body：

```json
{
  "title": "主题标题",
  "raw": "首帖正文",
  "category": 7,
  "archetype": "regular",
  "tags[]": ["rust", "ios"]
}
```

- 回复 Body：

```json
{
  "topic_id": 123,
  "raw": "回复内容",
  "reply_to_post_number": 2
}
```

- 成功响应：创建主题/私信返回可解析 `topic_id` 的 `Post` 或包装对象；回复返回 `Post` 或 `{ "post": Post }`
- 当前 Fire 行为：
  - 共享 Rust 写接口通过 UniFFI 暴露 `create_topic` / `createTopic(TopicCreateRequestState)`，发送 `title`、`raw`、`category`、`archetype=regular` 和重复的 `tags[]`，并复用认证写请求的 CSRF 刷新 / Cloudflare 恢复流程
  - Android 主话题列表提供新建主题入口；提交前使用共享 bootstrap 的 `min_topic_title_length` / `minTopicTitleLength`、`min_first_post_length` / `minFirstPostLength`、`default_composer_category`、`site.categories[].permission`、`minimum_required_tags` 和 `allowed_tags` 做本地校验
  - Android 创建主题成功后会打开新 topic detail，并刷新当前最新列表把新主题作为选中项
  - 共享 Rust 写接口通过 UniFFI 暴露 `create_reply` / `createReply(TopicReplyRequestState)`，并复用认证写请求的 CSRF 刷新 / Cloudflare 恢复流程
  - Android 话题详情页顶部提供回复话题入口，每条帖子也提供回复该楼层入口；提交前使用共享 bootstrap 的 `min_post_length` / `minPostLength` 做最小长度校验
  - 回复成功后 Android 会刷新当前 topic detail，并跳转到新创建帖子的楼层
  - 共享 Rust 已有 `create_private_message` / `createPrivateMessage(PrivateMessageCreateRequestState)`，使用 `archetype=private_message` 和 `target_recipients`；Android 公开用户页会从 profile 私信入口创建单收件人私信，成功后打开新私信线程

### `GET /posts/{postId}.json`

- 用途：获取单贴完整数据，或只取 `raw`
- 当前编辑流程最少依赖字段：
  - `id`
  - `raw`
  - `post_number`
  - `topic_id`
  - `cooked` 仅作为客户端在 `raw` 缺失时的降级回退
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

- 当前客户端行为：
  - iOS 在可编辑帖子右上角 menu 提供原生 post editor
  - Android 话题详情页在 `Post.can_edit` / `canEdit` 为 true 且帖子未隐藏时，从每帖 Actions 菜单提供原生 post editor
  - `edit_reason` 为可选字段
  - 成功后会刷新当前 topic detail，并跳回被编辑的楼层

### `DELETE /posts/{postId}.json`

- 用途：删除帖子
- 当前 Fire 行为：
  - 共享 Rust 写接口通过 UniFFI 暴露给宿主，并复用 CSRF 刷新 / 重试处理
  - iOS 仅在 `Post.can_delete == true` 且帖子未隐藏时显示删除入口
  - Android 话题详情页在 `Post.can_delete == true` 且帖子未隐藏时，在每帖 Actions 菜单中显示删除入口
  - 成功后刷新当前 topic detail，并让宿主同步最新 session 状态

### `PUT /posts/{postId}/recover.json`

- 用途：恢复已删除帖子
- 当前 Fire 行为：
  - 共享 Rust 写接口通过 UniFFI 暴露给宿主，并复用 CSRF 刷新 / 重试处理
  - iOS 仅在 `Post.can_recover == true` 时显示恢复入口
  - Android 话题详情页在 `Post.can_recover == true` 时，在每帖 Actions 菜单中显示恢复入口
  - 成功后刷新当前 topic detail，并让宿主同步最新 session 状态

### `GET /posts/{postId}/reply-history`

- 用途：获取帖子编辑/回复历史
- 响应：`Post[]`
- 当前 Fire 行为：
  - 共享 Rust 通过 `fetch_post_reply_history` 调用该接口，并复用普通认证请求的 Cloudflare / LoginRequired 分类与恢复路径
  - UniFFI topics namespace 暴露 `fetchPostReplyHistory(postId:)`
  - iOS 话题详情页在帖子有 `reply_to_post_number` 时加载这组数据，并在回复上下文 sheet 的“回复来源”区展示；Android 话题详情页在原生弹窗中展示同一组来源帖子；点选条目会跳转到对应楼层

### `GET /posts/{postId}/replies`

- 用途：获取帖子的直接回复列表
- Query：
  - `after?: integer`，默认 `1`
- 响应：`Post[]`
- 当前 Fire 行为：
  - 共享 Rust 通过 `fetch_post_replies(post_id, after)` 调用该接口，并解析返回的 `Post[]` 与 `reply_to_user`
  - UniFFI topics namespace 暴露 `fetchPostReplies(postId:after:)`
  - iOS / Android 话题详情页只在 `reply-ids` 返回空列表时把该接口作为直接回复回退路径；点选条目会跳转到对应楼层

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

- 当前 Fire 行为：
  - 共享 Rust 通过 `fetch_post_reply_ids(post_id)` 调用该接口，兼容对象数组和数字 ID 数组，并过滤无效 ID
  - UniFFI topics namespace 暴露 `fetchPostReplyIds(postId:)`
  - iOS / Android 话题详情页在 `reply_count > 0` 的帖子下优先读取这组回复树 ID，然后按批次调用 `GET /t/{topicId}/posts.json?post_ids[]=...` 拉取完整帖子并在原生回复上下文中展示；如果 ID 列表为空，再回退到 `GET /posts/{postId}/replies`

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

- 成功响应：
  - 线上实测服务端可能直接返回完整 `Post` 对象，而不是空体
  - 该对象里会带更新后的 `reactions`、`current_user_reaction`，以及 `actions_summary` 中对应操作的 `acted/can_undo`
  - 客户端如果拿到了这些字段，不应该直接丢弃
- 当前 Fire 行为：
  - 共享 Rust 写接口通过 UniFFI 暴露 `like_post` / `likePost`，并把服务端返回的 reaction 更新映射为 `PostReactionUpdateState`
  - Android 话题详情页在每条帖子下显示 heart 点赞按钮；点击后调用共享 Rust `likePost(postId)`，先应用返回的 `reactions` / `current_user_reaction`，再刷新目标楼层以同步完整帖子状态。非 heart 自定义回应走 `/discourse-reactions/.../toggle.json`。

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

- 当前 Fire 行为：
  - 共享 Rust 写接口通过 UniFFI 暴露 `id`、`post_action_type_id` 和可选 `message`
  - 共享 Rust 读接口会优先读取 bootstrap `data-preloaded.site.post_action_types`，缺失时回退 `GET /post_action_types.json`
  - iOS 在已认证且帖子可交互、未隐藏时显示举报入口，并使用服务端返回的 enabled flag 类型；只有服务端类型不可用时才回退 LinuxDo / Discourse 常见类型：`3` off-topic、`4` inappropriate、`7` notify moderators、`8` spam
  - Android 话题详情页在未隐藏帖子 Actions 菜单中显示举报入口，先读取同一套服务端 flag 类型，再按服务端 `require_message` 决定是否要求填写补充说明
  - 如果服务端标记某个举报类型 `require_message=true`，iOS / Android 会要求填写补充说明
  - 成功后刷新当前 topic detail，并让宿主同步最新 session 状态

### `DELETE /post_actions/{postId}`

- 用途：取消点赞
- Query：
  - `post_action_type_id=2`
- 当前 Fire 行为：
  - 共享 Rust 写接口通过 UniFFI 暴露 `unlike_post` / `unlikePost`，并复用与点赞相同的 reaction 更新解析
  - Android 话题详情页在当前用户 heart 已选且可撤销时把按钮切换为取消点赞；成功后刷新目标楼层以同步 reaction 计数与当前用户状态

### `GET /post_action_types.json`

- 用途：获取服务端支持的帖子操作类型
- 关键响应字段：
  - `post_action_types`
- 兼容性说明：
  - Fire 共享层也接受顶层数组、根对象 `post_action_types`、以及嵌套 `site.post_action_types`
  - 当前解析字段包括 `id`、`name_key` / `nameKey`、`name`、`description`、`short_description` / `shortDescription`、`is_flag` / `isFlag`、`require_message` / `requireMessage`、`enabled`、`position`、`applies_to` / `appliesTo`
  - iOS / Android 举报弹窗只展示 `is_flag=true`、`enabled=true`，且 `applies_to` 为空或包含 `Post` 的类型，并按 `position`、`id` 排序

### `PUT /discourse-reactions/posts/{postId}/custom-reactions/{reaction}/toggle.json`

- 用途：切换帖子回应
- 响应：

```json
{
  "reactions": [PostReaction],
  "current_user_reaction": PostReaction
}
```

- 兼容性说明：
  - `current_user_reaction` 如果不是对象，Fire 会按未设置处理；`reactions[]` 里的单个坏项会被跳过
- 当前 Fire 行为：
  - 共享 Rust 写接口通过 UniFFI 暴露 `toggle_post_reaction` / `togglePostReaction(postId, reactionId)`，并解析返回的 `reactions` 与 `current_user_reaction`
  - Android 话题详情页从共享 bootstrap 的 `enabled_reaction_ids` / `enabledReactionIds`、当前帖子已有 `reactions[]`、以及 `current_user_reaction` 合并生成自定义 reaction picker
  - Android picker 排除 `heart`，因为 heart 继续使用 Discourse 标准 `POST /post_actions` / `DELETE /post_actions/{postId}` 快捷路径；切换自定义 reaction 成功后刷新目标楼层

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

- 兼容性说明：
  - Fire 共享层接受顶层数组、根对象 `reaction_users[]`，以及兼容性的根对象 `reactions[]`
  - 每个 group 解析 `id`、`count` 和 `users[]`；`id` 缺失或不是标量时跳过该 group，`count` 缺失时回退为成功解析的 `users.length`
  - 每个用户解析 `id`、`username`、`name`、`avatar_template`；`username` 缺失或不是标量时跳过该用户
- 当前 Fire 行为：
  - 共享 Rust 读接口通过 UniFFI 暴露 `fetch_reaction_users` / `fetchReactionUsers(postId)`
  - Android 话题详情页会把帖子 reaction summary 作为入口，点击后拉取该接口并用原生弹窗按 reaction 分组展示用户；用户行继续打开原生 profile

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
- 当前 Fire 行为：
  - 共享 Rust 写接口通过 UniFFI 暴露创建 Topic/Post 书签，并复用认证写请求的 CSRF 刷新 / Cloudflare 恢复流程
  - iOS 话题详情页顶部菜单可添加或编辑 Topic 书签
  - iOS 话题详情页每条可交互且未隐藏的帖子菜单可添加或编辑 Post 书签；弹窗复用同一套书签备注/提醒编辑 UI，保存后刷新当前 topic detail 以同步 `bookmarked` / `bookmark_id` / `bookmark_name` / `bookmark_reminder_at`
  - Android 话题详情页顶部按钮可添加或编辑 Topic 书签
  - Android 话题详情页每条未隐藏帖子的 Actions 菜单可添加或编辑 Post 书签；弹窗保存后刷新当前 topic detail 以同步 `bookmarked` / `bookmark_id` / `bookmark_name` / `bookmark_reminder_at`

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

- 当前客户端约束：
  - 若未设置提醒，则会直接省略 `reminder_at`
  - `auto_delete_preference` 当前仅透传数值，不在宿主层做额外枚举扩展
  - Android 复用 topic/post 书签弹窗编辑 `name` 和 `reminder_at`，保存后刷新当前 topic detail

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
- 当前 Fire 行为：
  - iOS 书签编辑弹窗在已有 `bookmark_id` 时显示删除入口
  - Android 书签编辑弹窗在已有 `bookmark_id` 时显示删除入口
  - 删除 Topic/Post 书签后会刷新当前列表或 topic detail

### `GET /posts/{postId}/cooked.json`

- 用途：获取帖子渲染后的 HTML，常用于隐藏帖恢复查看
- 渲染备注：返回的 `cooked` HTML 应按与话题详情帖子相同的容错规则处理；未知标签应降级为可读文本或链接，不应阻塞帖子展示。
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
