# 2026-09-25：模块边界（当前口径）

| 项 | 值 |
| --- | --- |
| 日期 | 2026-09-25 |
| 状态 | 当前实现 |
| 范围 | iOS / Android / Rust 宿主与核心模块边界 |
| 参考 | [2026-09-19-ios-topic-detail-local-updates.md](2026-09-19-ios-topic-detail-local-updates.md)、[2026-09-19-render-presentation.md](2026-09-19-render-presentation.md) |

本文件只描述**现在怎么切**。

## 拆法

```text
页面骨架 Activity / VC
  └─ Fragment          一个 region 内独立刷新的块
       └─ View/方法     单个视觉单元，或单一职责函数
```

- 一个文件只回答一个问题。
- 深模块对外 interface 小，实现可以长；不要为了行数切开。
- 禁止第二份 session 状态、第二条渲染 / 登录 / CF 路径。
- 话题帖子行：iOS 留 Texture runtime cell；Android 留 `PostViewHolder` + `item_topic_post`。
- UniFFI 签名、crate-root `pub use`、生成绑定不拆。

## Session 控制面

| 域 | iOS | Android | Rust |
| --- | --- | --- | --- |
| TopicDetail | `FireTopicDetailStore` 持 handle | `TopicDetailViewModel` 持 `TopicDetailSessionHandle`，只投 snapshot | `TopicDetailSession` actor |
| Home | `FireHomeFeedSession` + 薄 `FireHomeFeedStore` | `HomeViewModel` + Paging3 + Rust `currentHomeTopicListScope` | 列表 scope / patch，不造 HomeFeedSession |
| Notifications | `FireNotificationStore` 读 runtime 快照 | `NotificationsViewModel` 是 Paging 胶水 | `FireNotificationRuntime` |
| Chat 列表 | `FireChatListSession` | `ChatChannelsViewModel` | RPC + Bus |
| Chat 单频道 | `FireChatChannelSession` | `ChatChannelSession` | RPC + Bus；尚未下沉 actor |
| Composer | `FireComposerSession` | `ComposerViewModel` 已是提交门面 | 写路径走现有 RPC |

平台态留下：WebView 登录、CF、cookie 提取、键盘、滚动、展开、图片选择器、输入草稿。

不要横切：`FireSessionStore`、`FireSpannableBuilder`、`HomeViewModel`、`NotificationsViewModel`、登录 / CF 协调器。

## iOS 页面目录

| 面 | 根 |
| --- | --- |
| Topic List Kit | `App/ListKit/TopicList/` |
| Composer | `App/Composer/` |
| Home | `App/Home/` |
| Search | `App/Search/` |
| Notifications | `App/Notifications/` |
| Chat Channel | `App/Chat/Channel/` |
| TopicDetail | `App/TopicDetail/`（Host / Feed / Modal / Runtime） |

## Android 宿主

- TopicDetail：同一 `TopicDetailActivity` / `PostViewHolder`，弹层与 bind 族是同包 `internal` 扩展；adapter 一 type 一文件。
- `TopicDetailViewModel` 是 snapshot 门面：展开走 `snapshotReplyRows`，投票 / 通知档走 handle，不再本地 merge。
- Chat：`ChatChannelActivity` 只留键盘、滚动、图片 picker、输入；策略在 `ChatChannelSession`。
- ComposerAssist 已按 mention / tag / recipient / draft / upload / markdown 分文件。

## Rust 模块目录

对外 crate 路径保持稳定（`mod` 目录替换单文件）。

| 域 | 现目录 |
| --- | --- |
| network | `fire-core/src/core/network/` |
| session / auth | `fire-core/src/core/session/`、`auth/` |
| chat | `fire-core/src/core/chat/` |
| notifications | `fire-core/src/core/notifications/` |
| interactions | `fire-core/src/core/interactions/` |
| topic detail | `fire-core` actor + `fire-models/src/topic_detail/` |
| payloads | `topic_payloads/`、`user_payloads/`、`chat_payloads/`、`cookies/` |
| parsing | `fire-core/src/core/parsing/` |
| rich text | `fire-rich-text/`、`fire-models/src/rich_text/` |
| UniFFI session | `fire-uniffi-session/src/{records,handle}/` |

Home / Chat / Composer 若再下沉 Rust actor，按 TopicDetail 模板，不要平行第二份策略。

## 话题详情会话

`TopicDetailSession` 是唯一控制面。平台只持 handle、投 snapshot、保留本地 chrome（展开、搜索高亮、键盘、滚动）。不要再开第二套分页 merge / MessageBus 刷新。iOS 帖子行留 Texture runtime cell。Rust checksum 只覆盖服务端字段；本地 chrome 折进 layout / in-place token 的规则见 [2026-09-19-ios-topic-detail-local-updates.md](2026-09-19-ios-topic-detail-local-updates.md)。
