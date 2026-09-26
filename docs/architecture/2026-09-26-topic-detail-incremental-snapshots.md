# 2026-09-26：话题详情增量快照

| 项 | 值 |
| --- | --- |
| 日期 | 2026-09-26 |
| 状态 | 当前实现 |
| 范围 | `TopicDetailObserver` 推送协议、宿主镜像、行消费 |
| 参考 | [fire-native-architecture.md](fire-native-architecture.md)、[2026-09-25-module-boundaries.md](2026-09-25-module-boundaries.md) |

话题详情只保留一条推送路径：常规发布跨 FFI 的数据量和变化量成正比。整份 `TopicDetailUiSnapshotState` 不再推送，只在首帧和失步恢复时由宿主从 `TopicDetailSnapshotHandle.full()` 主动拉取。这是协议的起始状态，不是备用渲染路径。

## 发布

`publish_now` 先投影、再 `diff_snapshots`、再 `assign_revisions`、再 fan-out。所有 owner 共享同一份 `Arc<TopicDetailUiSnapshot>`。

- 行指纹是 `(row_shape, layout_checksum, interaction_checksum)`。`row_checksums` 对 `TopicDetailUiRow` 做穷举解构，新字段必须归到 shape / layout / interaction，否则编译失败。
- 区块用 `PartialEq`（reply context 按 root id + 追加 id + 历史行指纹，不依赖 `AttachedPresentation` 的恒真 `PartialEq`）。
- 全都没变且没有 `home_row_patch` 时不盖章、不回调、不增加 generation。滚动中的空 `NoteVisible` 发布因此直接消失。
- 第一次发布：`base_generation = None`，变化记录不带行数据，宿主拉 `full()`。

## 宿主

iOS `FireTopicDetailSnapshotMirror` 与 Android `TopicDetailSnapshotMirror` 规则相同，在回调线程同步应用：

1. `generation <= mirror`：丢弃（重复投递 / 过期）。
2. 无镜像或 `base_generation` 对不上：`full()` 重建。
3. 否则覆盖非空区块，upsert 行；`row_order` 出现时裁掉不在里面的行。
4. `order` 里缺行则再 `full()`。

物化结果是完整快照。iOS `store.apply` 仍用 `generation >= applied` 丢更旧的一份。消费端（iOS adopt / 行补丁，Android `postsById`）只和自己上一次结果比 checksum，不依赖中间是否被合并。

## 投影缓存

source session 在 `post_mut` / `merge_posts` 递增帖子版本。投影缓存键是 `(version, 树形, mutating, loading_reply_context)`。`make_snapshot` 在 session 锁内借用帖子，不再为发布克隆整份 cooked。

## 第 0 步测量清单

在 300 楼话题上跑：点 10 次赞、连续打字 20 秒、滚动 10 秒、load more 两次、下拉刷新。

- Rust：`debug!` 记录 `published_rows` 与 `upserted_rows`。
- iOS：Instruments Time Profiler 看 lift / `store.apply` / adopt / 行补丁。
- Android：Perfetto 看 lift / `applyUiSnapshot` / DiffUtil。
