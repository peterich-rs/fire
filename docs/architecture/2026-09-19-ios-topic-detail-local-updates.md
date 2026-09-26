# iOS 详情页局部更新

日期：2026-09-19（2026-09-25 按 checksum / revision 收口重写）

详情页数据只来自 `TopicDetailSession` 快照，Swift 不合并分页。实现是真相源：单测跟落地行为走，不为过期断言改产品幅度。

## Rust revision：每个 revision 只管一块

`ActorState::assign_revisions` 是唯一给快照盖 generation 和 revision 的地方。投影出来的快照 revision 全为 0，不得直接发布。

| revision | 什么时候 +1 | iOS 做什么 |
| --- | --- | --- |
| `collection_revision` | `structure_changed`：phase / 错误 / 分页状态，或任一行的树形（post id、楼号、root、parent、depth、has_children、is_last_sibling、descendant_count、`reply_count`、是否主楼）变了 | 整页重建，评论行重算 |
| `interaction_revision` | 结构没变，但某行 `interaction_checksum` 或 `layout_checksum` 变了（点赞、表情、书签、mutating、投票、boost、编辑、flair） | 后台 adopt 后只换 token 变了的帖子 item |
| `composer_revision` | 正在输入的用户或 `is_submitting` 变了 | 只刷输入栏，不碰 feed |
| `chrome_revision` | 标题、分类、标签、书签、通知级别等头部字段 | 刷工具栏和输入栏，并重建头部（评论行复用） |
| `sidecar_revision` | AI 摘要 / notice | 重建头部（评论行复用） |

`reply_count` 算结构，是因为楼层的「展开 N 条回复」数量来自根楼的 `reply_count`，行级补丁不会重算回复树。

滚动中（`NoteScroll(true)`）发布只记一个标记，第一次推迟时起 100ms 定时器。定时器到点或停手时，按当时的状态重新投影、与上一份已发布快照做 diff；没有变化则不盖章、不跨 FFI。有变化才走 `assign_revisions`。推迟发布和推迟刷新（`arm_refresh`）是两个独立标记，互不覆盖。增量协议见 [2026-09-26-topic-detail-incremental-snapshots.md](2026-09-26-topic-detail-incremental-snapshots.md)。

## Rust 行 checksum

`layout_checksum` 和 `interaction_checksum` 合起来覆盖 `TopicDetailUiRow` 除树形外的每个字段；树形由 `structure_changed` 直接比较。宿主据此把「两个 checksum 都相等」当作这一行没变。`layout_checksum` 覆盖会影响行高的字段（作者、正文 checksum、投票、boost、回复对象、帖子类型、有无反应、操作权限）；`interaction_checksum` 覆盖原地可变的字段（计数、反应、书签、采纳、mutating、加载回复上下文等）。

另有四个 band checksum：`author_band_checksum`、`text_band_checksum`、`actions_band_checksum`、`reactions_band_checksum`。

## Swift token

主楼、回复行、原地刷新都只走 `FireTopicDetailRuntimeConfiguration.makePostItem(context:)`，上下文来自 `originalPostContext()` / `replyPostContext(...)`。同样的状态一定得到同样的 token，刷新不会因为 token 格式不同而误判变化。

- `contentToken`（要不要重新量高）= `layoutChecksum` + 本地布局 chrome（写权限、引用入口有无、回复快捷入口有无、回复树展开、表情条展开、正文展开 / 可折叠）。
- `messageBands`：每一段 band 的 token 必须覆盖 `FirePostCellNode.applyBands` 对应分支读到的全部输入，否则变化到不了屏幕。actions 段带写权限、mutating 和搜索高亮；reactions 段带写权限和表情条；showMore 段带回复数、回复树展开和加载回复上下文；quote 段带引用文案和目标楼号。
- `inPlaceUpdateToken` = `interactionChecksum` + 全部 band。任何 band 变了都算原地变化；只有点按时才读的字段（书签名、采纳菜单）靠 `interactionChecksum` 把最新 payload 送进 cell。

`applyBands` 即使没有 band 要重画也会换上新的 payload，点按回调读到的永远是最新帖子。

没有 Rust 行（只在单测里）时，同一套 token 退回用帖子字段拼出。

## 快照调度

`FireTopicDetailViewController+SnapshotApplication.swift`：

- 同一时刻只有一份待完成工作 `FireTopicDetailSnapshotWork`（`fullBuild(rebuildsComments:)` 或 `interactionRows`）。新请求与它合并，而不是互相取消：整页重建加行补丁合成「重建评论行」，所以结构变化不会被随后的点赞吞掉。
- adopt（把 Rust 行投影成 `TopicPostState`、复用或构建 attributed text）只在后台跑。`FireTopicDetailAdoptedProjection` 同时保存这次 adopt 的 `rowsByPostID`、mutating 和加载回复上下文集合，token、帖子和正文始终来自同一份 Rust 快照。
- 行补丁和本地展开都以 `latestBuiltFeedSnapshot` 为底：滚动中被挂起的那批 collection 更新也算在内，不会被补丁覆盖。
- 展开正文、表情条、回复树这类本地操作在主线程直接刷被点的行，用的是已 adopt 的行。若有待完成工作，会立刻按新本地状态重启它，旧工作不会把刚展开的行打回去。

## 页面骨架

详情页按四块刷新，正文和评论仍在同一条滚动列表里：

| 区域 | 组成 | 刷新 |
| --- | --- | --- |
| 标题栏 | 系统返回、中间标题、右侧图标 | 标题和右侧图标各比一次，没变的槽不重画 |
| 头部正文 | 标题和标签、摘要、正文、表情图标、数值统计 | 标题和统计是独立 cell。原帖 cell 内作者、正文、操作图标、表情、楼层线按 `messageBands` 只刷变化的一块 |
| 评论列表 | 楼层头、消息 item、楼层尾 | 一条评论再拆成引用入口、独立引用段、图片、文案、展示更多。引用不再并进正文 rich 段。展开正文或楼层只刷展示更多，不重建图片 |
| 底部输入 | 正在输入、回复目标、输入框、校验文案 | 由 `composer_revision` / chrome 驱动；只改正在输入时不重写输入框 |

## 三档管道

`FireTopicDetailFeedUpdatePipeline` 按 token 选档：

1. **复用档**：`invalidationToken` 相同且 rendered content 相同。点赞、换表情、mutating、搜索高亮走这里，并补一次 `applyVisibleNodeUpdates`。
2. **可见行 relayout**：`contentToken` 变（高度变）且该行可见。展开正文、展开表情条、从无到有的首枚反应、投票结果、boost 走这里。只改变化的 band，不整帖 `configure()`。
3. **collection diff**：插删 item（展开回复树、分页、新回复）。父行气泡高亮走 in-place，子楼走 `performBatch`。

`FireTopicDetailFeedInvalidationToken` 不含点赞计数，所以续赞停在第一档。

结构 diff 与原地更新按 item id 对齐。`FireTopicDetailCommitDecision` 以已提交行 `currentItems` 为基准、以最新 `latestItems` 为目标；Texture 还在 `performBatch` 时只覆盖 latest，不重算中间计划。数据源交换发生在 `updates` 闭包里。item 数量变化时，id 仍在且只变了 `inPlaceUpdateToken` 的行仍走 `applyVisibleNodeUpdates`，不因为插删被丢掉。`replyIndex` 不参与 rendered content 比较。楼层尾 id 固定为 `reply-footer:{topicId}`，加载中、失败、空、到底只改 content token。主贴 cooked 未就绪时保留上一份评论行，占位只替换 `original:{topicId}` 那一格。队列重试不再退回 `reloadData`。帖子行高度只来自 `FirePostCellNode` 自己的 `layoutSpecThatFits`，不再走 `FirePostLayoutManager`。换肤和宽度变化对可见 chrome 节点（含投票、AI 摘要、notice）调用 `apply`，宽度变化用 `relayoutItems()`。引用是独立 `RenderUiSegment::Quote`，楼层线和分隔线是 overlay，长按选择在拖动或离屏时拆掉。帖内图按目标尺寸走 Nuke processor，并异步上屏。

## 哪些操作走 in-place

| 操作 | 档 | 说明 |
| --- | --- | --- |
| 续赞 / 换已有表情 / mutating | 复用 + in-place | 只改 chip 标题与选中色 |
| 搜索结果切换 | 复用 + in-place | actions band 变，只刷高亮 |
| 首枚反应 | 可见行 relayout | 插入 chip，不在即将被替换的旧 node 上播 bounce |
| 展开 / 收起正文 | 可见行 relayout | 同一控件再点即收起；主线程只刷被点的行 |
| 表情条显隐 | 可见行 relayout | 主线程只刷被点的行 |
| overflow 展开 | cell 本地 | in-place / relayout 不得把 `areOverflowActionsExpanded` 打回 false |
| 展开回复树 | collection batch | 只插删子楼 |

`configure()` 仍留给 reuse / 主题 / 宽度变化，并继续重置 overflow。

## 共享 mutating 只暗表情

`isMutating` 是帖级 in-flight 锁（赞 / 表情 / boost / 投票 / 管理共用）。行内回复、boost、overflow、二级操作、投票选项都不因此变暗或禁用。只有表情图标在请求进行中 alpha 0.45。actions band 的 in-place / relayout 会刷新这组 enabled/alpha、投票可交互状态和书签图标，避免 `configure()` 在 mutating=true 时把回复/boost 锁死后请求结束仍不恢复。反应 chip 签名不收录 mutating，避免点赞时重写 chip 标题打断 bounce。

## 动画单通道

`fireTapBounce` 只走一条 `CAKeyframeAnimation(transform.scale)`：pressed → overshoot → 1.0。现网幅度保留（chip `0.80` / `1.10`）。模型层保持 identity，避免和 layout 抢 `UIView.transform`。按下态仍用 `firePressScaleHighlight`（compact `0.88`，alpha `0.92`）。

不为动画引入 SwiftUI `fireLikeEffect`。
