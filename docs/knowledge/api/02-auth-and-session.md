# 认证与会话管理 API

> 对应 FluxDO 源文档第 4-5 节

---

## 1. 检查登录状态（带服务端验证）

```
GET /session/current.json
```

**场景**：应用启动时验证本地会话是否仍然有效。

### Query Parameters

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `_` | int | 否 | 时间戳（`DateTime.now().millisecondsSinceEpoch`），防缓存 |

### Request Headers

```
（继承全局 Header，额外标记）
skipAuthCheck: true
skipCsrf: true
```

### Response (200)

```json
{
  "current_user": {
    "id": 12345,
    "username": "example",
    "name": "Example User",
    "avatar_template": "/user_avatar/...",
    "trust_level": 2
  }
}
```

- 若 `current_user` 存在：会话有效，更新本地缓存的用户信息和 token。
- 若 `current_user` 不存在：会话失效，执行登出。

### 其他响应

| 状态码 | 处理 |
|--------|------|
| 404 | 会话失效（无用户） |
| 401/403 | 会话失效 |
| 网络异常 | 保守保留本地状态（不登出） |

---

## 2. 会话 Probe（内部机制）

```
GET /session/current.json
```

**场景**：收到 `discourse-logged-out` 响应 Header 或 `not_logged_in` 错误后的二次验证。

与"检查登录状态"相同接口，但行为不同：

- 先同步 `cf_clearance` Cookie（不同步 `_t`）
- 返回值：
  - `true` — 会话有效
  - `false` — 确认失效
  - `null` — 无法判断

### Probe 防护机制

| 机制 | 说明 |
|------|------|
| 防并发折叠 | 多个信号只发一次请求 |
| 冷却期 | inconclusive 后 30 秒内抑制弱信号 |
| Strike 累积 | 强信号 1 次即触发 probe，弱信号需 2 次 |

---

## 3. 登出

```
DELETE /session/{username}
```

**场景**：用户主动登出或会话失效被动登出。

### Path Parameters

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `username` | string | 是 | 当前登录用户的用户名 |

### 执行流程

1. 切断所有在途请求（advance session generation）
2. 停止后台 Service（MessageBus、CF Refresh）
3. 调用登出 API（可选，被动登出时 `callApi=false`）
4. 清除内存状态（token、username、缓存）
5. 清除 Cookie（保留 `cf_clearance`）
6. 刷新预加载数据
7. 广播状态变更

---

## 4. CSRF Token

### 4.1 获取 CSRF Token

```
GET /session/csrf
```

**场景**：发起 POST/PUT/DELETE 请求前，若本地无 CSRF token 则自动获取。带防并发去重（多个并发请求共享同一个 CSRF 刷新请求）。

#### Request Headers

```
（使用独立的 Dio 实例，带 Cookie 管理但无并发限制）
skipCsrf: true
skipAuthCheck: true
isSilent: true
skipScheduler: true
```

#### Response (200)

```json
{
  "csrf": "xxxxxxxxxxxxxxxxxxxx"
}
```

### 4.2 CSRF 策略

| 规则 | 说明 |
|------|------|
| 非 GET 请求前检查 | 若 CSRF token 为空 → 先调用 `/session/csrf` 获取 |
| 403 + BAD CSRF | 清空 token → 重新获取 → 重试原请求（仅一次） |
| HTML 提取 | CSRF token 也可从首页 HTML 的 `<meta name="csrf-token">` 中提取 |
