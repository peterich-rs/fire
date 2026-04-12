[返回总览](../backend-api.md)

# 扩展服务与外部接口

本页覆盖 Linux.do 扩展服务和项目中实际使用到的辅助外部接口。

## LDC 与 CDK 扩展接口

### LDC OAuth `https://credit.linux.do`

#### `GET /api/v1/oauth/login`

- 用途：获取授权入口 URL
- 认证：依赖当前论坛登录态 Cookie
- 备注：
  - 移动端侧没有单独配置 `client_id/client_secret`
  - 前提是 `https://credit.linux.do` 服务端自己的 OAuth 配置已经就绪
- 响应：

```json
{
  "data": "https://connect.linux.do/oauth2/authorize?..."
}
```

#### `POST /api/v1/oauth/callback`

- 用途：提交 OAuth 回调参数
- `Content-Type`: `application/json`
- Body：

```json
{
  "code": "oauth-code",
  "state": "oauth-state"
}
```

#### `GET /api/v1/oauth/logout`

- 用途：退出 LDC OAuth

#### `GET /api/v1/oauth/user-info`

- 用途：获取 LDC 用户信息
- 401/403 表示授权已过期
- 响应：

```json
{
  "data": {
    "id": 1,
    "username": "alice",
    "nickname": "Alice",
    "trust_level": 3,
    "avatar_url": "https://...",
    "total_receive": "0",
    "total_payment": "0",
    "total_transfer": "0",
    "total_community": "0",
    "community_balance": "0",
    "available_balance": "0",
    "pay_score": 0,
    "is_pay_key": false,
    "is_admin": false,
    "remain_quota": "0",
    "pay_level": 0,
    "daily_limit": 0
  }
}
```

### CDK OAuth `https://cdk.linux.do`

#### `GET /api/v1/oauth/login`

- 用途：获取授权入口 URL
- 认证：依赖当前论坛登录态 Cookie
- 备注：
  - 移动端侧没有单独配置 `client_id/client_secret`
  - 前提是 `https://cdk.linux.do` 服务端自己的 OAuth 配置已经就绪
- 响应：

```json
{
  "data": "https://connect.linux.do/oauth2/authorize?..."
}
```

#### `POST /api/v1/oauth/callback`

- 用途：提交 OAuth 回调参数
- `Content-Type`: `application/json`
- Body：

```json
{
  "code": "oauth-code",
  "state": "oauth-state"
}
```

#### `GET /api/v1/oauth/logout`

- 用途：退出 CDK OAuth

#### `GET /api/v1/oauth/user-info`

- 用途：获取 CDK 用户信息
- 401/403 表示授权已过期
- 响应：

```json
{
  "data": {
    "id": 1,
    "username": "alice",
    "nickname": "Alice",
    "trust_level": 3,
    "avatar_url": "https://...",
    "score": 100
  }
}
```

### OAuth 授权确认 `https://connect.linux.do`

#### `GET /oauth2/approve/{id}` 或 HTML 页面中的 approve 链接

- 用途：确认第三方授权
- 客户端流程：
  1. 先请求 `/api/v1/oauth/login` 拿到授权地址
  2. 访问授权页 HTML
  3. 解析出 `a[href*="/oauth2/approve/"]`
  4. 请求 `https://connect.linux.do{approveLink}`
  5. 从 `Location` 中解析 `code` 和 `state`
  6. 回调到各自服务的 `/api/v1/oauth/callback`

- 请求特点：
  - `followRedirects: false`
  - 通过 `Location` 头读取回跳参数
- 补充说明：
  - 当前客户端没有自定义 deep link / 回调地址注册
  - `code` / `state` 是从服务端重定向 `Location` 中取出，再由客户端 POST 给各自服务的 callback 端点
  - 如果你不是接现成的 `credit.linux.do` / `cdk.linux.do` 服务，还需要服务端先完成 OAuth client / redirect 配置；本仓库不包含这部分实现

## LDC 打赏接口

Base URL：`https://credit.linux.do`

### `POST /epay/pay/distribute`

- 用途：执行打赏
- 认证：`Basic Auth`
- 开发前置条件：
  - 必须先到 `https://credit.linux.do/merchant` 创建应用
  - 手工拿到 `clientId` / `clientSecret`
  - 再由客户端本地保存后使用
- 请求头：

```http
Authorization: Basic base64(clientId:clientSecret)
Content-Type: application/json
```

- Body：

```json
{
  "user_id": 1,
  "username": "alice",
  "amount": 10.5,
  "out_trade_no": "LDR_T123_P456_1711111111111_1234",
  "remark": "optional"
}
```

- 成功响应：

```json
{
  "data": {
    "trade_no": "xxx"
  }
}
```

- 失败响应常见字段：

```json
{
  "error_msg": "错误信息",
  "msg": "错误信息"
}
```

- 补充说明：
  - 当前客户端对非 200 响应更稳定地只解析 `msg`
  - `error_msg` 虽然是服务端常见字段，但当前客户端错误提示不一定直接消费它

## 辅助外部接口

### GitHub 更新检查

Base URL：`https://api.github.com`

#### `GET /repos/<owner>/fire/releases/latest`

- 用途：检查新版本
- 请求头：

```http
User-Agent: Fire-App
Accept: application/vnd.github.v3+json
If-None-Match: <etag>
```

- 允许状态码：
  - `200`
  - `304`

- 关键响应字段：
  - `tag_name`
  - `html_url`
  - `body`
  - `assets[].name`
  - `assets[].browser_download_url`
  - `assets[].size`
- 发布契约补充：
  - 如果 Fire 继续保留 Android 自动更新，建议沿用“架构名出现在 APK 文件名中”的约定
  - Android 自动下载/校验仍建议依赖与 APK 同名的 `.sha256` 侧车文件
  - 如果不采用这套命名规则，客户端需要自行定义新的资产筛选逻辑

### APK SHA256 文本文件

#### `GET <sha256-url>`

- 用途：下载 APK 对应的 SHA256 校验文件
- 响应格式：
  - `hash`
  - 或 `hash  filename`
- 命名约定：
  - Fire 建议按“APK 完整文件名 + .sha256”去匹配侧车文件
  - 例如 `fire-arm64-v8a.apk` 对应 `fire-arm64-v8a.apk.sha256`

### 贴纸市场 `https://s.pwsh.us.kg`

- 该域名是当前客户端默认源，不是唯一合法源
- 当前客户端允许把 base URL 改成任意兼容的静态 JSON 源

#### `GET /assets/market/index/index.json`

- 用途：获取贴纸市场索引
- 最少返回结构示例：

```json
{
  "totalPages": 3,
  "pageSize": 20,
  "totalGroups": 52
}
```

#### `GET /assets/market/index/page-{page}.json`

- 用途：获取某页分组
- 最少返回结构示例：

```json
{
  "groups": [
    {
      "id": "cat",
      "name": "Cats",
      "icon": "https://example.com/icon.png",
      "order": 1
    }
  ]
}
```

#### `GET /assets/market/group-{groupId}.json`

- 用途：获取贴纸分组详情
- 最少返回结构示例：

```json
{
  "id": "cat",
  "name": "Cats",
  "icon": "https://example.com/icon.png",
  "emojis": [
    {
      "id": "cat_1",
      "name": "cat-1",
      "url": "https://example.com/cat-1.png",
      "width": 128,
      "height": 128,
      "groupId": "cat"
    }
  ]
}
```

这些接口均为匿名 GET，无认证要求，返回 JSON 静态资源。
