# 2026-09-23：页面组合拆分与 Rust 大文件切目录

| 项 | 值 |
| --- | --- |
| 日期 | 2026-09-23 |
| 状态 | 已落地（文件边界；Session 控制面升级仍按 TopicDetail 刀法预备，未迁行为） |
| 范围 | iOS 高流量页目录拆分 + fire-core / fire-models / fire-rich-text / fire-uniffi-session 模块切分 |
| 参考 | [2026-09-22-ios-topic-detail-session.md](2026-09-22-ios-topic-detail-session.md) |

对照 TopicDetail 落地：先立 Host / Shell / Controller / Feed / State 目录，Swift store 暂不改行为。下一波 Session（`HomeFeedSession` / `ChatChannelSession` / `ComposerSession` / Notification runtime 收口）在边界稳定后再迁控制面。

## iOS 页面目录

| 面 | 新根 | 说明 |
| --- | --- | --- |
| Topic List Kit | `App/ListKit/TopicList/` | 从 Bookmarks 文件抽出共用 cell / metric / toast / palette |
| Composer | `App/Composer/` | Route/Validation/Markdown/Shell/Host + VC 扩展 |
| Home | `App/Home/` | Controller + Feed + Shell；scope/drawer 仍在 `Views/Home/` |
| Search | `App/Search/` | Controller + Feed + Header |
| Notifications | `App/Notifications/` | Inbox / History / Cells；presentation 仍在 `Views/Notifications/` |
| Chat Channel | `App/Chat/Channel/` | Load / Bus / Interactions / Table + message cell |
| Messages / Drafts / Profile cells | `Views/Messages/`、`Views/Drafts/`、`Views/Profile/Cells/` | 轻量拆；死 SwiftUI Profile/PublicProfile 已删 |

## Rust 模块目录

| 原文件 | 现目录 |
| --- | --- |
| `fire-core/src/core/network.rs` | `core/network/{mod,constants,client,traced,execute,request,csrf,challenge,heal,auth_signals,headers,body,tests}.rs` |
| `fire-core/src/diagnostics.rs` | `diagnostics/{models,store,listener,logs,bundle,tests}.rs` |
| `fire-models/src/cookie.rs` | `cookie/{canonical,snapshot,sweep,tests}.rs` |
| `fire-core/src/topic_payloads.rs` | `topic_payloads/{list,post,detail,poll,deser}.rs` |
| `fire-rich-text/src/lib.rs` | `map.rs` / `onebox.rs` / `images.rs` / `plain_text.rs` / `tests.rs` |
| `fire-uniffi-session/src/records.rs` | `records/{cookie,session,bootstrap,login,challenge,refresh,handlers,doh}.rs` |
| `fire-uniffi-session/src/lib.rs` handle | `handle/{cookies,challenge,login,refresh,doh,scope}.rs` |
| `fire-core/src/core/interactions.rs` | `interactions/{bookmarks,posts,replies,polls,votes,reactions,boosts,timings,...}.rs` |
| `fire-core/src/core/session.rs` | `session/{classify,challenge,cookies,bootstrap,login}.rs` |
| `fire-core/src/core/chat.rs` | `chat/{channels,messages,reactions,pins,threads,search}.rs` |
| `fire-core/src/core/notifications.rs` | `notifications/{fetch,runtime,read}.rs` |
| `topic_detail_project.rs` | `topic_detail/project/{row,chrome,checksum}.rs` |
| `topics/source/load.rs` | `topics/source/load/{initial,page,load_more}.rs` |
| hydrate AI summary | `topics/source/summary.rs` |

对外 crate 路径保持稳定（`mod` 目录替换单文件）。

## 下一波 Session（预备，未迁行为）

- `HomeFeedSession`：吃掉 `FireHomeFeedStore` 的 scope / merge / MB debounce / unread patch
- `ChatChannelSession`：每频道 open/close，对齐 TopicDetail
- Notification runtime 收口：Swift 分页并回 `FireNotificationRuntime`
- `ComposerSession`：draft / validation / 三类 submit / upload resolve
