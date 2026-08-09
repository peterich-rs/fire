# Chat Tab（Discourse Chat）落地说明

日期：2026-08-09  
状态：已实现（REST 首版）

## 范围

在 iOS / Android 主壳新增 **聊天** tab，对接 Discourse Chat 插件（不是论坛私信 topic 列表）。

| 层 | 路径 |
|----|------|
| 协议知识 | `docs/knowledge/api/15-chat.md` |
| 模型 | `fire-models::chat` |
| Core | `fire-core::core::chat` + `chat_payloads` |
| UniFFI | `fire-uniffi-chat` → `FireAppCore.chat()` |
| iOS | `App/Views/Chat/*` + tab shell 第 3 项 |
| Android | `ui/chat/*` + bottom nav `chatFragment` |

## 产品行为

1. 频道列表：私信 / 公共频道分段
2. 未读徽章：DM = unread+mention；公共 = 仅 mention；muted 不计
3. 进入会话：拉消息（`fetch_from_last_read`）、发送、上报已读
4. 新建 DM：`POST /chat/api/direct-message-channels`（1:1 默认 upsert）
5. 滑动操作：标记已读、退出会话（iOS）

## 实时与增强（已实现）

- **MessageBus**：`MessageBusEventKind::Chat`；列表订阅 `/chat/new-channel`、`/chat/user-tracking-state/{userId}`、逐频道 `/chat/{id}/new-messages`；会话订阅 `/chat/{id}` 或 `/chat/{id}/thread/{tid}`
- **Thread**：`create_chat_thread` / `fetch_chat_thread_messages` / `mark_chat_thread_read` + 原生线程页
- **置顶**：pins 列表、pin/unpin、顶栏 banner
- **表情回应**：消息操作面板（heart/tada/laughing/+1/eyes）
- **图片直发**：相册选择 → 既有 `uploadImage` → `send` with `upload_ids`

## 验证

```bash
cargo fmt --all --check
cargo clippy --keep-going -p fire-models -p fire-core -p fire-uniffi --all-targets --no-deps -- -D warnings
cargo test -p fire-models -p fire-core -p fire-uniffi --all-targets
xcodegen generate --spec native/ios-app/project.yml
```
