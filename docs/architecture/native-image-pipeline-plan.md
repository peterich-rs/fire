# 原生图片管线规划（头像先行）

## 背景

这份文档聚焦两个目标：

1. 基于当前代码，解释 iOS 首页列表、帖子详情页列表里的头像为何在滚出屏幕后再滚回时，会先闪回字母默认头像，再恢复真实头像。
2. 在不改业务代码的前提下，给后续图片能力做一份分阶段规划，范围覆盖头像、帖子内容图片、图片查看/保存，以及未来 Android 复用边界。

相关背景文档：

- `docs/architecture/ios-topic-detail-loading-and-notification-routing.md` 已把“production image/rendering infrastructure”列为后续工作，但还停留在一句 follow-up，没有落到具体方案。
- `docs/architecture/profile-page-redesign.md` 已把“Avatar -> Full-screen image preview”列进交互设计，说明头像大图查看迟早要进入同一条图片能力演进路径。
- `docs/architecture/fire-native-workspace.md` 明确把 `media` 归到 platform-owned，这对后面判断“平台库 / Rust / C++ 哪层适合作为主实现”是约束，不是偏好。

## Phase 1 Spike / Phase 2 Slice 状态（2026-04-18）

- 已落地 Fire 自有远程图片层：头像继续通过 `FireAvatarView` 消费，同一条 decoded-image memory cache + in-flight request coalescing 现在也复用到了帖子正文图片。
- 这次仍然没有引入第三方图片库；viewer 手势、保存/分享、磁盘缓存和更广的媒体面统一还没开始。
- 当前实现的关键收益是：热头像与热帖子图片在 view 重建时都可以先同步命中 decoded image memory cache，再决定是否异步补请求；正文卡片和全屏 cover 也能共享同一条加载状态。

## 核心结论

### 1. 当前头像如何加载，使用什么库

- 首页列表链路：`FireHomeCollectionView` -> `FireTopicRow` -> `FireAvatarView`。
- 帖子详情链路：`FireTopicDetailView` -> `FirePostRow` -> `FireAvatarView`。
- `FireAvatarView` 现在会先把 `avatar_template` 解析成绝对 URL，请求键稳定后优先同步查询 Fire 自己的 decoded image memory cache；只有未命中时才走平台异步加载。
- 当前 iOS 工程里没有接入任何第三方图片库。仓库检索 `native/ios-app/` 没有发现 `Nuke`、`Kingfisher`、`SDWebImage` 等实际代码或依赖声明。现状是头像和帖子正文图片已经走 Fire 自有平台图片层，badge/composer 等零散图片面仍在使用 `AsyncImage`。

### 2. 为什么 item 滚回屏幕内会先出现字母头像，再变成真实头像

这更像是“视图重建 + 当前实现没有 app-owned 图片状态保留层”造成的，而不是当前自定义 `URLSession` 缓存策略导致的。

代码证据有两条：

- 首页不是 `List`，而是 `FireCollectionHost` 包的 `UICollectionView`。`FireDiffableListController` 用 `UICollectionView.CellRegistration` + `UIHostingConfiguration` 把 `FireTopicRow` 装进 cell。offscreen item 被复用后，SwiftUI row 会重新构建，头像视图也跟着重建。
- 帖子详情页是 `ScrollView` + `LazyVStack`。`LazyVStack` 的 offscreen row 同样可能被销毁并在重新进入可视区时重建。

而 `FireAvatarView` 的实现又明确写成了：

- `AsyncImage` 成功时才显示真实头像。
- `.empty` 和 `.failure` 都显示 `monogramView`。

这意味着只要 `FireAvatarView` 被重建，新的 `AsyncImage` 实例就会先从 `.empty` 开始，界面自然先看到默认字母头像。

### 3. 即使短期视图重建不可避免，理论上应该依赖什么缓存；为什么体感像没命中

当前实现理论上只能依赖系统 HTTP 缓存和上游 CDN 缓存，因为应用代码里没有任何显式图片内存缓存、磁盘缓存、预取器、解码缓存或图片状态保留层。

这次手工验证了头像响应头：

- 真实头像入口如 `https://linux.do/user_avatar/.../102/...png` 先返回 `302`，跳到 `https://cdn.linux.do/user_avatar/.../96/...png`。
- 最终 CDN 响应返回 `Cache-Control: public, max-age=31556952, immutable`，而且 `cf-cache-status: HIT`。
- 字母头像 `letter_avatar` 直接 `200`，同样是长期 immutable 缓存。

所以“字节层面完全没缓存”这个判断不成立；缓存大概率是有的。问题在于：

1. `AsyncImage` 重建时仍然要从 `.empty` 开始。
2. `FireAvatarView` 把 `.empty` 明确映射成字母占位头像。
3. 应用没有自己的已解码图片内存缓存，也没有“上一次成功图片”状态保留。
4. 真实头像请求还要先走一次 `linux.do -> cdn.linux.do` 的重定向归一化入口，哪怕最终 CDN 图是热的，整个视图层仍然会重新启动一次异步加载流程。

因此，当前实现不是“完全没命中缓存”，而是“就算命中了底层 HTTP/CDN 缓存，也不足以避免 SwiftUI 视图重建后的 placeholder 回闪”。

### 4. 现阶段最适合本项目架构的图片方案

结论：Phase 1 先落一个 platform-owned 的 Fire 自有头像图片包装层，用最小改动把头像从直接依赖 `AsyncImage` 提升到“同步内存命中 + 异步补加载”的状态；是否在后续更大范围图片能力里引入 `Nuke`，留到 Phase 2 再判断。

### 5. 方案不能只管头像

当前仓库已经有比头像更完整的图片需求链路：

- 帖子内容图片：`FireTopicPresentation.imageAttachments(from:baseURLString:)` 目前在 Swift 里从 `post.cooked` HTML 正则提取图片，再由 `FireCookedImageCard` / `FireTopicImageViewer` 用 `AsyncImage` 展示。
- 全屏查看：`FireTopicDetailView` 已经用 `fullScreenCover(item: $selectedImage)` 打开 `FireTopicImageViewer`，但目前只有 `scaledToFit()`，没有缩放手势、拖拽关闭状态机，也没有保存/分享。
- 发图上传：`FireComposerView` 已经通过 `PhotosPicker` 选图，`FireAppViewModel.uploadImage()` 再转发到 Rust `upload_image`。也就是说，上传链路已经是 Rust-owned API orchestration，而显示链路还完全是平台零散实现。

因此，这份规划必须同时覆盖头像、帖子图片、查看器和保存能力，而不是只修一个头像闪烁点。

### 6. 平台侧图片库、Rust 实现、C++ 实现哪层更适合作为主实现

主实现应放在平台侧图片栈，不应放在 Rust，也不应新开一个 C++ 图片引擎。

- 平台侧最合适：图片下载、解码、下采样、动画格式支持、内存压力响应、列表预取、全屏查看、保存到 Photos / MediaStore，本质上都和 UIKit / SwiftUI / Android View 生命周期紧耦合。
- Rust 不适合作为主图片栈：Rust 当前已经很好地承担了会话、API orchestration、上传接口、共享模型这些职责，但让 Rust 负责 on-screen image fetch/decode/cache，意味着要把大量字节、bitmap 生命周期和平台 UI 状态跨 UniFFI 边界搬运，收益很低，复杂度很高。
- C++ 更不合适：仓库没有现成的 C++ 图片基础设施，引入新 ABI、编译链和跨平台图像对象桥接，只会额外放大复杂度。

Rust 与平台图片栈的合理边界应该是：

- Rust-owned：媒体元数据、短链上传 URL 解析、上传 API orchestration、未来可选的共享 `MediaAttachment` / `ImageRequestDescriptor` 定义。
- Platform-owned：实际请求执行、内存/磁盘缓存、图片解码/下采样、占位图策略、过渡动画、查看器手势、保存/分享。

### 7. 分阶段实施计划

- 第一阶段只先解决头像滚动回显问题，不改首页/详情页宿主结构，也不同时推进帖子图片查看器重写。
- 第二阶段把同一条图片管线扩展到帖子内容图片与全屏查看器。
- 第三阶段再谈 Android 对齐、共享媒体模型，以及必要时的共享解析能力。

## 当前实现拆解

### 首页头像链路

- `FireHomeCollectionView` 渲染 home feed row。
- row 内容是 `FireTopicRow`。
- `FireTopicRow` 直接把 `row.originalPosterAvatarTemplate` 和用户名传给 `FireAvatarView`。
- `FireAvatarView` 自己构造 URL，请求图片层同步查询内存缓存，并在未命中时异步拉取头像。

首页列表的关键点不只是“用了头像组件”，而是它承载在 collection-backed host 上：`FireDiffableListController` 用 `UIHostingConfiguration` 给 `UICollectionViewListCell` 装 SwiftUI row。这类结构天然会在 cell 复用时重建 row 子树。

### 帖子详情头像链路

- `FireTopicDetailView` 顶层是 `ScrollView` + `LazyVStack`。
- `replyPostRows(_:)` 为每个 timeline row 构造 `FirePostRow`。
- `FirePostRow` 里的头像仍然是 `FireAvatarView`。

所以首页和详情页虽然宿主不同，一个是 `UICollectionView`，一个是 `LazyVStack`，但头像加载实现是同一套：都落到 `FireAvatarView` + `FireAvatarImagePipeline`。

### 当前帖子图片链路

- `FireTopicPresentation.imageAttachments` 仍然是 Swift 侧能力，不在 Rust。
- `FireCookedImageCard` 和 `FireTopicImageViewer` 现在已经改走同一条 Fire 自有远程图片层，不再直接依赖 `AsyncImage`。
- `FireTopicImageViewer` 仍然只是一个全屏 cover，不是完整 viewer：没有 pinch zoom、double tap、drag-to-dismiss 动画状态，也没有保存到相册。

### 当前上传链路

- `FireComposerView` 通过 `PhotosPicker` 读 `Data`。
- `FireAppViewModel.uploadImage()` 转发到 `sessionStore.uploadImage()`。
- Rust `fire-core` 的 `upload_image` 负责 multipart 请求和 CSRF/session orchestration。

这说明“图片上传”已经有清晰的 Rust-owned API 边界，而“图片显示”也开始向统一平台管线收口，只是覆盖面还没有扩到所有媒体 surface。

## 根因判断

### 主要根因

当前头像滚动回显问题的第一根因是视图重建，第二根因是图片层没有 app-owned 的缓存/状态保留抽象。

更具体地说：

- 首页：collection cell 复用导致 `UIHostingConfiguration` 重新配置内容，`FireTopicRow` / `FireAvatarView` 重建。
- 详情页：`LazyVStack` 的 offscreen row 回收后，`FirePostRow` / `FireAvatarView` 重建。
- 头像 view 一旦重建，`AsyncImage` 从 `.empty` 开始。
- `.empty` 被当前代码渲染成字母头像。

因此，用户看到的不是“加载失败”，而是“每次重建都先走占位图，再异步切回真实图”。

### 不是主要根因的项

#### 不是当前自定义 `URLSession` 缓存策略

仓库搜索只发现 `.reloadIgnoringLocalCacheData` 用在两类地方：

- `FireCfClearanceRefreshService`
- `FireAppViewModel` 里的特定诊断/同步请求

它们不在 `FireAvatarView`、`FireCookedImageCard`、`FireTopicImageViewer` 的图片加载链路上。当前图片加载没有接入这套自定义 session，因此不能把头像回闪归因到这些 request cache policy。

#### 也不是 Rust 层“没有缓存头像”

Rust 当前只负责把 `avatar_template` 等字段透传出来，并不负责图片下载显示。头像滚动回闪发生在纯平台 UI 层。

## 为什么现在的缓存“看起来像没命中”

如果只看响应头，真实头像和字母头像都具备很强的 CDN 缓存条件；但当前 UI 体验并不会因此自动变好。

原因是当前缺的是“图片状态层”，不是“CDN 缓存头”：

- HTTP/CDN 缓存只能减少字节回源。
- 它不能让新的 `AsyncImage` 实例跳过 `.empty`。
- 它也不能在 view 被销毁后，帮 Fire 保留上一张已解码图片并同步回填。

换句话说，当前体验更像“缓存存在，但 UI 不知道怎么无闪回地消费它”。

## 方案比较

### 方案 A：继续使用当前 `AsyncImage`

优点：

- 零新增依赖。
- 代码最少。

问题：

- 没有 Fire 自己的图片管线抽象。
- 无法显式控制内存缓存、磁盘缓存、下采样、预取、优先级、失败重试。
- 对列表回收/重建场景不友好，头像回闪问题无法从根上解决。
- 后续扩展到帖子图片 viewer、保存、动画格式时会继续散落在业务 view 中。

结论：不适合继续作为长期方案。

### 方案 B：iOS 在 Phase 2+ 评估引入 Nuke，并继续包在 Fire 自己的图片层后面

优点：

- 有明确的 `ImagePipeline` 心智模型，适合收口成 Fire 自己的 `FireImagePipeline` / `FireRemoteImage`。
- 有显式 memory cache、disk cache、downsampling、prefetch 能力，适合从头像扩到帖子图片。
- SwiftUI 友好，但又不强迫业务 view 直接依赖一堆底层实现细节。
- 后续如果图片请求需要更细的 cookie / header / redirect / cache key 策略，也更容易集中处理。

问题：

- 引入新依赖。
- 仍是 iOS 平台专用，不能直接给 Android 复用实现。

结论：对帖子内容图片、viewer、预取和磁盘缓存来说依然是强候选，但不是这次头像 Phase 1 spike 的必要前提。

### 方案 C：iOS 引入 Kingfisher，并包在 Fire 自己的图片层后面

优点：

- 生态成熟，缓存和处理能力也足够完整。
- SwiftUI 支持成熟，落地速度也快。

问题：

- API 面更大，更容易让业务代码直接写满库特定类型，收口成 Fire 自有抽象的纪律要求更高。
- 相比 Nuke，没有明显更贴合当前问题的架构优势。

结论：可行，但不是第一选择。

## 推荐技术方向

### 推荐方案

推荐采用“平台主实现 + Fire 自有包装层 + Rust 只提供协作边界”的方向：

- iOS 第一阶段先落 Fire 自有头像图片层，底座是 `URLSession` + decoded image memory cache + in-flight request coalescing。
- 不让业务 view 直接散落图片实现细节，而是在平台侧建立 Fire 自己的图片入口。
- 第一阶段只替换 `FireAvatarView` 的内部实现，先吃到首页和帖子详情的最大收益。
- 等帖子图片、viewer、保存等需求进入同一条管线时，再决定是否把底座升级到 `Nuke` 这类更完整实现。

### 推荐边界

#### iOS / Android 平台侧负责

- 请求执行
- 内存缓存 / 磁盘缓存
- 解码与下采样
- viewer 手势和过渡
- 保存/分享
- 列表预取与滚动感知

#### Rust 负责

- 会话 / cookie / CSRF / API orchestration
- 上传图片、短链解析等接口能力
- 未来如果 Android 和 iOS 都要统一帖子图片提取规则，可以再把 `MediaAttachment` 抽成共享模型，但这不应阻塞第一阶段头像修复

#### 不推荐把主实现放到 C++

- 当前仓库没有现成基础设施。
- 不会减少平台 UI 集成工作。
- 会额外增加 ABI、构建和调试复杂度。

## 分阶段计划

### Phase 1：只修头像滚动回显

目标：解决首页和帖子详情页里“滚回屏幕后先出现字母头像”的问题。

范围：

- 新建平台图片管线封装。
- `FireAvatarView` 内部从直接依赖 `AsyncImage` 切到统一图片层。
- 首页 `FireTopicRow` 和详情 `FirePostRow` 自动受益。
- 顺带覆盖通知、关注列表、个人资料页头像可以接受，但不是本阶段验收重点。

明确不做：

- 不改首页 `FireCollectionHost` 结构。
- 不改帖子详情 `LazyVStack` 宿主。
- 不重写 viewer。
- 不迁移帖子内容图片。

验收标准：

- 已经加载过的头像在滚出屏幕后再滚回，不应再明显闪回字母占位头像。
- 请求次数和滚动流畅度不倒退。

### Phase 2：扩展到帖子内容图片与 viewer（已落最小切片）

目标：把同一条图片管线扩到帖子正文图片。

范围：

- 已完成：`FireCookedImageCard` 改走统一图片层。
- 已完成：`FireTopicImageViewer` 改走统一图片层，与正文卡片共享热缓存和同 URL 的 in-flight 请求。
- 已完成：viewer 手势状态机第一步，`FireTopicImageViewer` 已支持 pinch zoom、放大后拖拽平移、未放大时下拉关闭。
- 未完成：double tap。
- 未完成：保存到 Photos 和系统分享。

这时再决定是否需要把 `imageAttachments(from:baseURLString:)` 这类解析能力向 Rust 侧收敛；如果 Android 近期也要渲染相同帖子图片结构，这一步才值得做。

### Phase 3：扩展到更多媒体面和 Android 对齐

目标：把图片能力从“头像 + 帖子图片”扩成真正的 media stack。

范围：

- badge image、profile hero/avatar preview、flair 等更多媒体面统一接入。
- 如 Android 开始进入真实图片列表/详情渲染，再定义共享 `MediaAttachment` / `ImageRequestDescriptor`。
- Android 采用自己的 native image loader，复用的是请求/模型边界，不是 iOS 的库实现本身。

当前 Android 宿主还是 ViewBinding-based，图片库不必现在定死；真正进入图片列表渲染阶段时，再根据 Android UI 栈选择更合适的 loader 即可。

## 测试与验证建议

### 实现前必须先做的验证

1. 验证常用头像尺寸的重定向归一化规律。
   现在看到 `102 -> 96` 的真实头像重定向，但这是否稳定覆盖 `26 / 32 / 34 / 36 / 40 / 86pt * scale` 还没系统确认。若规律稳定，可考虑把头像请求尺寸在客户端先归一化，减少重定向入口抖动。

2. 用一个最小 spike 验证 Fire 自有图片层在这两类宿主里是否能消除热图回闪。
   重点不是“底层网络有没有缓存”，而是：
   - 在 `UICollectionView + UIHostingConfiguration` 中回到可视区时是否还会先出 placeholder；
   - 在 `LazyVStack` row 重建时是否能直接从内存命中恢复。

3. 验证帖子图片里是否存在需要 auth 的资源。
   如果未来帖子图片不仅是公开 CDN 图，还包含短链或需 cookie 的资源，统一图片层就要提前预留 request customization 能力。

### Phase 1 完成后建议验证

- 首页快速滚动 3-5 屏后再回滚，观察头像是否闪回 monogram。
- 帖子详情长串楼层滚动回退，观察头像是否闪回 monogram。
- 冷启动首次加载与热滚动回退分别记录请求数。
- 前后台切换、内存压力、重新登录后确认不会出现错误头像复用。

### Phase 2 前建议补充验证

- 是否需要 GIF / WebP / animated avatar / flair 支持。
- iOS 保存到 Photos 的权限和失败态设计。
- Android 后续保存到 MediaStore 的权限/行为预期。

## 最终建议

短结论只有三条：

1. 当前头像回闪的主要原因不是“完全没缓存”，而是首页/详情页宿主都会触发 view 重建，而 `FireAvatarView` 又把新的 `AsyncImage(.empty)` 明确显示成字母占位头像。
2. 现阶段最适合本项目的主方向是：平台侧建立 Fire 自有图片层，Phase 1 先用轻量自实现拿到头像同步内存命中，Rust 保持在 metadata / upload / request descriptor 协作边界，不去做主图片栈；是否引入 `Nuke` 留给后续更大范围图片面统一时再判断。
3. 第一阶段只先修头像滚动回显；帖子图片、viewer、保存、Android 对齐留在后续阶段推进，不要把所有 media 问题捆成一次大改。