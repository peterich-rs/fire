# iOS 详情页局部更新

日期：2026-09-19

详情页小操作不再为了刷新计数而 bump collection revision。实现是真相源：单测跟落地行为走，不为过期断言改产品幅度。

## 三档管道

`FireTopicDetailFeedUpdatePipeline` 仍按 token 选档：

1. **复用档**：`invalidationToken` 相同且 rendered content 相同。点赞 / 换表情 / mutating 走这里，并补一次 `applyVisibleNodeUpdates`。以前这一档直接 return，in-place token 变化不会上屏。
2. **可见行 relayout**：`contentToken` 变（高度变）且该行可见。展开正文、展开表情条、从无到有的首枚反应走这里。只改 body / picker / chip，不整帖 `configure()`。
3. **collection diff**：插删 ident（展开回复树、分页）。父行气泡高亮走 in-place，子楼走 `performBatch`。

`FireTopicDetailFeedInvalidationToken` 仍不含点赞计数。interaction revision 会重建 snapshot，但 item 身份和 layout token 不变，所以续赞停在第一档。

## 哪些操作走 in-place

| 操作 | 档 | 说明 |
| --- | --- | --- |
| 续赞 / 换已有表情 / mutating | 复用 + in-place | 只改 chip 标题与选中色 |
| 首枚反应 | 可见行 relayout | 插入 chip，不在即将被替换的旧 node 上播 bounce |
| 展开 / 收起正文 | 可见行 relayout | 同一控件再点即收起；主线程重算 snapshot |
| 表情条显隐 | 可见行 relayout | 主线程重算 |
| overflow 展开 | cell 本地 | in-place / relayout 不得把 `areOverflowActionsExpanded` 打回 false |
| 展开回复树 | collection batch | 只插删子楼 |

`FireTopicPostContentToken` 不再收录 `likeCount` / `reactions` / `currentUserReaction`。反应写入 `topicDetails` 后只 `bumpTopicInteractionRevision`。

`configure()` 仍留给 reuse / 主题 / 宽度变化，并继续重置 overflow。

## 共享 mutating 只暗表情

`isMutating` 是帖级 in-flight 锁（赞 / 表情 / boost / 投票 / 管理共用）。行内回复、boost、overflow、二级操作、投票选项都不因此变暗或禁用。只有 表情 图标在请求进行中 alpha 0.45。in-place / relayout 会刷新这组 enabled/alpha，避免 `configure()` 在 mutating=true 时把回复/boost 锁死后请求结束仍不恢复。反应 chip 签名不再收录 mutating，避免点赞时重写 chip 标题打断 bounce。

## 动画单通道

`fireTapBounce` 只走一条 `CAKeyframeAnimation(transform.scale)`：pressed → overshoot → 1.0。现网幅度保留（chip `0.80` / `1.10`）。模型层保持 identity，避免和 layout 抢 `UIView.transform`。按下态仍用 `firePressScaleHighlight`（compact `0.88`，alpha `0.92`）。

不为动画引入 SwiftUI `fireLikeEffect`。
