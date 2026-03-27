# Fire 后台接口文档

基于 `references/fluxdo` 的现有行为和当前仓库整理，覆盖 Fire 现阶段需要接入的后端接口、请求头、认证方式、Query、Body 结构和关键返回结构。

适用范围：
- 主站 Discourse 接口：`https://linux.do`
- MessageBus 长轮询接口：主站或 `siteSettings.long_polling_base_url`
- Linux.do 扩展服务：`https://credit.linux.do`、`https://cdk.linux.do`、`https://connect.linux.do`
- Fire 规划中的辅助外部接口：GitHub Releases、贴纸市场

说明：
- 本文档以“参考实现已验证的真实 HTTP 请求”为准，不是官方 Discourse 全量文档。
- 响应字段优先列出客户端实际消费的关键字段；服务端可能返回更多字段。
- 对于同一路径在不同业务下复用的情况，已按“调用语义”拆分到不同模块文档。

开发前请先确认这些前置资源：
- 主站登录态：`_t`、`_forum_session`、`cf_clearance`、`X-CSRF-Token`
- 运行时基础数据：首页 `data-preloaded`、`shared_session_key`、`topicTrackingStateMeta`、`currentUser.username`
- 单例 `clientId`：上传、Presence、MessageBus 当前都复用同一个前台 `clientId`
- 站点/分类约束：`siteSettings` 里的最小长度、默认分类、功能开关，以及分类的 tag/permission 元数据
- 如果用 LDC 打赏：需要先到 `https://credit.linux.do/merchant` 申请 `clientId/clientSecret`
- 如果用 LDC/CDK OAuth：默认假设现成服务端 OAuth 配置已经存在；本仓库只覆盖客户端接入流程
- 如果用 GitHub 更新或贴纸市场：还要满足 release 命名约定和贴纸 JSON schema

## 文档目录

| 模块 | 覆盖内容 |
| --- | --- |
| [01. 接入基础与约定](backend-api/01-access-and-conventions.md) | Base URL、认证、通用请求头、Content-Type、最小调用链路、实现细节 |
| [02. 公共数据结构](backend-api/02-common-models.md) | `TopicListResponse`、`TopicDetail`、`Post`、`User`、枚举与常量 |
| [03. 引导与站点信息](backend-api/03-bootstrap-and-site.md) | 首页引导、CSRF、Cloudflare、站点信息、分类、标签、表情 |
| [04. 话题与帖子](backend-api/04-topics-and-posts.md) | 话题列表、详情、发帖回帖、书签、举报、解决方案、回应 |
| [05. 用户、搜索与通知](backend-api/05-users-search-and-notifications.md) | 用户资料、徽章、关注、邀请、搜索、通知 |
| [06. 上传、草稿与互动能力](backend-api/06-creation-and-interaction.md) | 上传、投票、Presence、阅读时长、草稿、模板、私信 |
| [07. MessageBus 长轮询](backend-api/07-messagebus.md) | 轮询入口、鉴权方式、订阅频道、事件类型 |
| [08. 扩展服务与外部接口](backend-api/08-extensions-and-external-services.md) | LDC/CDK OAuth、打赏、GitHub Releases、SHA256、贴纸市场 |

## 推荐阅读顺序

1. 先读 [01. 接入基础与约定](backend-api/01-access-and-conventions.md)，确认主站认证方式、CSRF、请求头和调用顺序。
2. 再读 [03. 引导与站点信息](backend-api/03-bootstrap-and-site.md)，完成首页启动数据、站点配置和基础分类信息接入。
3. 业务核心接口集中在 [04. 话题与帖子](backend-api/04-topics-and-posts.md) 和 [05. 用户、搜索与通知](backend-api/05-users-search-and-notifications.md)。
4. 如果需要上传、草稿、投票或私信能力，再看 [06. 上传、草稿与互动能力](backend-api/06-creation-and-interaction.md)。
5. 如果需要实时能力，再接 [07. MessageBus 长轮询](backend-api/07-messagebus.md)。
6. Linux.do 扩展能力和辅助外部接口放在 [08. 扩展服务与外部接口](backend-api/08-extensions-and-external-services.md)。

## 最小调用链路

如果你要在其他技术栈复现 Fire 的主要能力，推荐的最小调用链路如下：

1. `GET /`
   获取首页 HTML，提取 `csrf-token`、`shared_session_key`、`data-preloaded`
2. 如需写操作，优先复用首页 HTML / 登录 WebView 中已有的 CSRF；缺失或收到 `BAD CSRF` 时再 `GET /session/csrf`
   获取最新 CSRF
3. 使用 Cookie Session 调用主站 API
4. 如需实时能力，先持久化 `siteSettings.long_polling_base_url`、`shared_session_key`、`topicTrackingStateMeta`
5. 使用单例 `clientId` 调用 `POST /message-bus/{clientId}/poll`
6. 如遇 Cloudflare 挑战，先完成 `/challenge` 页面验证并拿到 `cf_clearance`
