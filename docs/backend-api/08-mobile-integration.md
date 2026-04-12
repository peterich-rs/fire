[返回总览](../backend-api.md)

# 移动端集成约定

本页记录 Fire 当前已经落地的移动端壳层集成约定。它不是某个单独后端服务的 API 文档，而是宿主层如何把站点路由、通知 payload、APNs 注册壳层和后台通知回退接入到现有 Fire / LinuxDo 接口上的统一约束。

## 自定义 URL Scheme

当前 iOS 壳层注册了 `fire://` URL scheme，并为 `https://linux.do/...` 声明了 universal link / Associated Domains 入口，把支持的 URL 统一解析成应用内 route 模型。

### 支持的 URL 形式

- `fire://topic/{topicId}?postNumber={postNumber}`
- `fire://user/{username}`
- `fire://profile/{username}`
- `fire://badge/{badgeId}`
- `fire://badge/{badgeId}?slug={badgeSlug}`

### 兼容的 LinuxDo Web URL

当前 iOS 也会通过 universal link continuation 入口直接解析以下 LinuxDo URL，并映射到同一套 route：

- `https://linux.do/t/{slug}/{topicId}`
- `https://linux.do/t/{slug}/{topicId}/{postNumber}`
- `https://linux.do/t/{topicId}`
- `https://linux.do/u/{username}`
- `https://linux.do/badges/{badgeId}`

### 当前路由行为

- `topic(topicId, postNumber?)`
  - 进入原生 topic detail
  - 如果有 `postNumber`，则按锚点楼层滚动
- `profile(username)`
  - 进入原生公开用户页
- `badge(id, slug?)`
  - 进入原生 badge detail

## 通知 Payload 约定

当前 iOS 壳层有两类通知：

1. 前台/后台本地通知
   - 来源：`/notification-alert/{userId}` 的一跳 MessageBus poll
   - 生产者：`FireBackgroundNotificationAlertWorker`
2. 未来的 APNs 远程通知
   - 当前仅完成本地 APNs 注册壳层
   - 尚未完成 token 上传，也没有后端注册 API

### 当前消费的 payload 字段

本地通知点击和未来 APNs payload 目前都按同一组最小字段映射 route：

- `topicId`
  - `UInt64`
  - 必填；缺失时不跳转
- `postNumber`
  - `UInt32`
  - 可选；存在时按目标楼层打开话题
- `topicTitle`
  - `String`
  - 可选；宿主本地通知会尽量附带，用于详情页首屏标题预览
- `excerpt`
  - `String`
  - 可选；宿主本地通知会尽量附带，用于详情页首屏摘要预览
- `messageId`
  - 当前仅用于通知 request identifier / 本地排重
  - iOS 当前不会把它映射成单独 route

### 当前 route 映射

- payload 有 `topicId`
  - 映射到 `topic(topicId, postNumber?)`
- payload 缺少 `topicId`
  - 当前不执行跳转

## APNs 注册壳层

### 当前已实现

- 请求系统通知权限（`alert` / `badge` / `sound`）
- 在已授权状态下每次进入宿主生命周期都会重新调用 `registerForRemoteNotifications`
- 在宿主本地缓存最新 device token
- 在诊断页暴露：
  - 通知权限状态
  - APNs 注册状态
  - 最新 device token
  - 最近注册错误

### 当前未实现

- device token 上传
- 后端 token 注册 / 解绑 API
- APNs payload 到 LinuxDo 业务通知 ID 的回写对齐

### 约束说明

- 当前 APNs token 只保存在宿主本地，用于诊断和后续生产化接入准备。
- APNs device token 可能轮换，因此宿主需要在已授权时持续重新向 APNs 注册，而不是只依赖首次缓存结果。
- 在 LinuxDo 或 Fire 自有后端提供 token 注册 API 之前，客户端不得假设“拿到 token 就能收到远程推送”。

## 后台通知回退

在没有 APNs token 上传链路之前，iOS 当前正式回退路径仍然是：

1. 宿主调度 `BGAppRefreshTask`
2. 恢复 Rust session + Keychain cookies
3. 调用共享层的一次性 `/notification-alert/{userId}` poll
4. 把返回结果转成宿主本地通知

### 依赖条件

- 通知权限已授权
- `session.readiness.canOpenMessageBus == true`
- `currentUserId` 已知

### 当前限制

- 这是轮询回退，不是实时 APNs push
- 刷新窗口仍受 iOS 后台调度策略影响
- 只有能映射到 route 的 payload 才会在点击后进入目标页面
