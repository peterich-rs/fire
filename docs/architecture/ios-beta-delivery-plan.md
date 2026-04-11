# Fire iOS Beta Delivery Plan

本文档记录 Fire iOS beta 的执行计划、阶段状态、worktree 策略、提交切分规则和验证门槛，供后续长期维护使用。

适用范围：

- 当前 iOS beta 交付线
- `feature/ios-beta` 分支上的持续产品开发
- `main` 分支上的基线维护与最终集成

## 使用原则

- 代码是最终事实来源；本文档负责描述当前执行策略和阶段状态。
- 只要发生以下变化，就必须同步更新本文档：
  - 阶段状态变化
  - worktree / branch 策略变化
  - 提交切分策略变化
  - 验证门槛变化
  - Stage 3 及以后范围变化
- 后续如果实现与本文档冲突，以代码为准，并在同一轮改动里回写文档。

## 当前交付策略

### Worktree 拓扑

- Root worktree：`/Users/zhangfan/develop/github.com/fire`
  - 角色：参考线
  - 约束：允许 owner 保留临时基础设施实验，不作为当前 beta 的交付基线
- Main baseline line：
  - branch：`main`
  - 角色：始终代表最新主线基线
  - 维护规则：每次开始新一轮功能开发或集成验证前，先 `git fetch origin`，再把本地 `main` 快进到最新 `origin/main`
- Clean main validation worktree：
  - worktree：`../fire-worktrees/<main-validation>`
  - branch：`main`
  - 角色：在不污染 root worktree 的前提下验证“最新 main + 当前 feature”是否可编译、可测试、可合并
- Single feature line：
  - worktree：`/Users/zhangfan/develop/github.com/fire-worktrees/feature-ios-beta-reading`
  - branch：`feature/ios-beta`
  - 角色：承接所有 iOS beta 产品能力开发

### 为什么只保留一个 feature worktree

- 之前按阶段拆独立 feature worktree，适合前期并行规划。
- 当前 beta 进入连续实现阶段后，Stage 1 和 Stage 2 都已经接在同一条产品线上完成。
- 为了降低切分、rebase、文档同步和验证成本，后续 Stage 3 继续堆在 `feature/ios-beta` 上，不再按阶段新建 feature worktree。
- `feature/ios-beta` 不是基线，只是长期产品开发线；它必须定期吸收最新 `main`，不能脱离主线长期漂移。
- 只有在以下情况才允许再拆新的 feature worktree：
  - 用户明确要求
  - 需要并行处理互不重叠的大改动
  - 当前 feature 线已经出现高风险冲突，不适合继续线性推进

### 当前目录与分支名不一致的原因

- 当前物理 worktree 目录仍叫 `feature-ios-beta-reading`
- 但其实际 branch 已经改为 `feature/ios-beta`
- 原因：该 worktree 含有 submodule，Git 不允许直接 `git worktree move`
- 维护规则：以 branch 名为准，目录名暂不再调整

## 提交切分规则

每个阶段尽量保持以下切分顺序：

1. `feat(core)` 或 `feat(composer)`：
   shared Rust / parsing / UniFFI surface
2. `feat(ios)`：
   iOS host UI / navigation / interaction wiring
3. `docs(...)`：
   backend-api / architecture / README 同步
4. `fix(...)`：
   编译修正、测试修正、回归修正

约束：

- 一个 commit 只覆盖一个清晰职责
- 文档不和大块功能改动混在同一个 commit 尾部
- 如果有 `xcodegen generate` 结果，必须和对应 Swift 改动一起提交

## 基线同步规则

每次继续推进 `feature/ios-beta` 之前，默认按以下顺序操作：

1. `git fetch origin`
2. 把本地 `main` 快进到最新 `origin/main`
3. 在 clean worktree 中确认 `main` 的 submodule 状态、Rust build 和 iOS build/test 正常
4. 再从最新 `main` 创建新 feature worktree，或者把现有 `feature/ios-beta` rebase / merge 到最新 `main`

每次准备把当前 iOS beta 结果并回主线时，默认按以下顺序操作：

1. 先让 `feature/ios-beta` 吸收最新 `main`
2. 在独立 `main` worktree 上把 `main` 更新到 `feature/ios-beta`
3. 只在 `main` worktree 上执行最终验证
4. 验证通过后，才把 `main` 视作新的交付基线

## 阶段状态总览

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| Stage 0 | 已完成 | clean baseline、submodule guard、workspace 说明 |
| Stage 1 | 已完成 | 阅读后管理闭环：bookmarks / badge detail / topic actions / notification navigation |
| Stage 2 | 已完成 | 原生 composer：create-topic / advanced reply / drafts / uploads / tag / mention |
| Stage 3 | 已完成 | history / drafts inbox / social graph / invite / vote-poll / edit |

## Stage 0：Clean Baseline

### 目标

- 固定这轮 beta 的 clean trunk
- 明确 root worktree 不等于交付基线
- 把 submodule 漂移在 CI 和本地验证阶段提前拦住

### 已落地内容

- 新增 `./scripts/check_clean_submodules.sh`
- Rust / native CI workflow 接入 submodule clean guard
- `docs/architecture/fire-native-workspace.md` 明确基于最新 `main` 的 clean worktree 流程
- `native/ios-app/README.md` 补充 clean baseline 要求

### 当前提交切片

- `chore(ci): guard clean submodule baselines`
- `docs(workspace): document clean integration worktrees`

### 验证门槛

- `./scripts/check_clean_submodules.sh`
- `cargo test -p fire-core`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

## Stage 1：阅读后管理闭环

### 目标

- 在“能读”的基础上补齐“读完之后怎么管理”的能力
- 不先做重型 composer，优先补通知、书签和 topic-level 管理

### 已落地内容

#### Shared / Rust

- 书签列表：`GET /u/{username}/bookmarks.json`
- 书签写操作：
  - `POST /bookmarks.json`
  - `PUT /bookmarks/{bookmarkId}.json`
  - `DELETE /bookmarks/{bookmarkId}.json`
- 徽章详情：`GET /badges/{badgeId}.json`
- 话题通知级别：`POST /t/{topicId}/notifications`
- Topic / TopicDetail / TopicPost 扩展书签拍平字段

#### iOS

- 真实 bookmarks 页面
- bookmark add / edit / delete
- 从书签跳回目标楼层
- badge detail 页面
- public profile 页面
- 通知跳转补全：
  - topic
  - profile
  - badge
- topic detail 增加：
  - 分享
  - 图片全屏查看
  - 话题通知级别设置

### 当前提交切片

- `feat(reading): add bookmark, badge, and topic management flows`
- `docs(backend-api): sync stage1 reading management behavior`

### 验证门槛

- `cargo test -p fire-core -p fire-uniffi -p fire-models`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -derivedDataPath /tmp/fire-ios-beta-reading CODE_SIGNING_ALLOWED=NO test`

## Stage 2：原生 Composer

### 目标

- 从“能读能快回”升级到“能稳定发帖和写长回复”
- 保留 quick reply，但增加完整原生 composer 作为升级路径

### 已落地内容

#### Shared / Rust

- bootstrap 扩展：
  - `min_topic_title_length`
  - `min_first_post_length`
  - `default_composer_category`
- category 扩展：
  - `topic_template`
  - `minimum_required_tags`
  - `required_tag_groups`
  - `allowed_tags`
  - `permission`
- drafts API：
  - `GET /drafts.json`
  - `GET /drafts/{draftKey}.json`
  - `POST /drafts.json`
  - `DELETE /drafts/{draftKey}.json`
- upload API：
  - `POST /uploads.json`
  - `POST /uploads/lookup-urls`
- create-topic API：
  - `POST /posts.json`
- UniFFI 新增：
  - `fetch_drafts`
  - `fetch_draft`
  - `save_draft`
  - `delete_draft`
  - `upload_image`
  - `lookup_upload_urls`
  - `create_topic`

#### iOS

- 首页 toolbar create-topic 入口
- topic detail quick reply 升级到 advanced reply composer
- 独立原生 full-screen composer
- server-backed 草稿恢复 / 自动保存 / 删除
- 图片上传并插入 `upload://` Markdown
- composer 预览阶段解析 `upload://`
- 标签输入框内联建议
- 正文编辑器内联 `@mention` 建议
- create-topic 成功后刷新首页 feed
- advanced reply 成功后刷新当前 topic detail

### 当前提交切片

- `feat(composer): add shared drafts, uploads, and topic creation surfaces`
- `feat(ios): add native create-topic and advanced reply composer`
- `docs(architecture): sync native composer ownership`
- `fix(composer): stabilize editor state and upload request assertions`
- `fix(composer): finalize upload button and binary handoff`
- `docs(backend-api): align composer metadata and iOS behavior`

### Stage 2 当时未纳入的能力

- drafts inbox / drafts list 页面
  - 已在 Stage 3A 落地
- 私信 composer
- 多图自动 grid 排版
- 服务端 mention 校验 `GET /composer/mentions`
- Markdown cooked 级别服务端预览

### 验证门槛

- `cargo test -p fire-core -p fire-uniffi -p fire-models`
- `xcodegen generate --spec native/ios-app/project.yml`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -derivedDataPath /tmp/fire-ios-stage2 CODE_SIGNING_ALLOWED=NO test`

## Stage 3：剩余 Beta Scope

Stage 3 沿用同一条 `feature/ios-beta` 产品线推进，现已完成交付。

### 3A：History 与个人内容管理

#### 目标

- 补齐“我发过什么、看过什么、存过什么”的管理视图

#### 已落地内容

#### Shared / Rust

- `GET /read.json`
- drafts list 已有 shared surface，直接复用

#### iOS

- 浏览历史页
- drafts inbox / drafts list 页
- 从 drafts list 跳回 create-topic / reply composer

#### 当前提交切片

- `feat(core): expose read-history for beta management flows`
- `feat(ios): add history and drafts management screens`
- `docs(backend-api): sync history and draft-list ownership`

### 3B：社交与邀请

#### 目标

- 补齐用户关系和邀请管理

#### 已落地内容

#### Shared / Rust

- following / followers
- follow / unfollow
- pending invites / create invite

#### iOS

- following / followers 列表
- follow / unfollow 操作
- invite links 管理页

#### 当前提交切片

- `feat(core): add follow and invite beta surfaces`
- `feat(ios): add follow graph and invite management`
- `docs(backend-api): sync social beta flows`

### 3C：话题扩展动作

#### 目标

- 补齐 topic vote / poll / edit topic/post

#### 已落地内容

#### Shared / Rust

- poll vote / unvote
- topic vote / unvote / voters
- edit topic / edit post

#### iOS

- topic detail 中的 vote / poll 动作
- edit topic / edit post 原生入口

#### 当前提交切片

- `feat(core): add vote poll and edit surfaces`
- `feat(ios): add topic vote poll and edit actions`
- `docs(backend-api): sync topic extension flows`

### Stage 3 验证门槛

- 不允许破坏现有阅读链路、通知链路和 session restore
- 每个子阶段至少重复执行：
  - `cargo test -p fire-core -p fire-uniffi -p fire-models`
  - `xcodegen generate --spec native/ios-app/project.yml`
  - `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test`

## 明确不纳入当前 beta 的范围

- Fluxdo 的 DOH / proxy / VPN / Cronet / 网络栈实验能力
- AI 助手 / AI 分享图
- 桌面或大屏专用适配壳
- 多图标 / 主题实验
- 任何绕过 Rust shared core、直接在 Swift 写登录后协议的实现

## 维护检查清单

每次继续推进 `feature/ios-beta` 时，至少执行一次以下检查：

1. 当前分支是否仍然是 `feature/ios-beta`
2. 本地 `main` 是否已经同步到最新 `origin/main`
3. `./scripts/check_clean_submodules.sh` 是否通过
4. 当前阶段是否已经写入本文档
5. backend-api 文档是否已经同步到真实实现
6. `xcodegen generate` 结果是否已提交
7. Rust / iOS 验证是否已经跑完

## 当前结论

- Fire iOS beta 已经不再处于“只做阅读”的阶段。
- 当前长期维护策略已经从“每阶段一个 feature worktree”收敛为：
  - 一个始终跟随最新 `main` 的基线
  - 一个长期 feature line `feature/ios-beta`
- Stage 0、Stage 1、Stage 2、Stage 3 已完成。
- 当前默认下一步是：
  - 在 clean `main` worktree 上执行最新主线集成验证
  - 确认 docs / xcodegen / Rust / iOS 测试结果与交付基线一致
