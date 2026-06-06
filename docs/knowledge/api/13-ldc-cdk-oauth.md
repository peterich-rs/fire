# LDC OAuth、CDK OAuth、LDC 打赏 API

> 对应 FluxDO 源文档第 23-25 节

---

# 第 23 节：LDC OAuth API

**Base URL：** `https://credit.linux.do`

---

## 23.1 获取授权 URL

```
GET https://credit.linux.do/api/v1/oauth/login
```

**场景**：用户发起 LDC（信用积分）OAuth 授权。

**Request Options：** `skipCsrf: true`

**Response (200)：**

```json
{
  "data": "https://connect.linux.do/oauth2/authorize?..."
}
```

---

## 23.2 获取授权页面

```
GET <authUrl>
```

**Request Options：** `skipCsrf: true`, `allowRedirectSetCookie: true`, 不自动重定向

**Response：** HTML 页面，解析其中的授权链接：

```html
<a href="/oauth2/approve/...">Approve</a>
```

---

## 23.3 确认授权

```
GET https://connect.linux.do/oauth2/approve/...
```

**Request Options：** `skipCsrf: true`, `skipRedirect: true`, `allowRedirectSetCookie: true`

**Response：** 302 重定向，`Location` Header 中包含 `code` 和 `state` 参数。

---

## 23.4 OAuth 回调

```
POST https://credit.linux.do/api/v1/oauth/callback
```

**Request Body（form-urlencoded）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string | 是 | 授权码 |
| `state` | string | 是 | 状态参数 |

**Request Options：** `skipCsrf: true`

---

## 23.5 获取用户信息

```
GET https://credit.linux.do/api/v1/oauth/user-info
```

**Request Options：** `skipCsrf: true`, `showErrorToast: false`

**Response (200)：**

```json
{
  "data": {
    "id": 1,
    "username": "example",
    "nickname": "昵称",
    "trust_level": 2,
    "avatar_url": "https://...",
    "total_receive": "100.00",
    "total_payment": "50.00",
    "total_transfer": "10.00",
    "total_community": "5.00",
    "community_balance": "3.00",
    "available_balance": "42.00",
    "pay_score": 80,
    "is_pay_key": false,
    "is_admin": false,
    "remain_quota": "100.00",
    "pay_level": 1,
    "daily_limit": "50.00"
  }
}
```

**Response (401/403)：** 抛出 `OAuthExpiredException`。

---

## 23.6 登出 LDC

```
GET https://credit.linux.do/api/v1/oauth/logout
```

**Request Options：** `skipCsrf: true`

---

# 第 24 节：CDK OAuth API

**Base URL：** `https://cdk.linux.do`

接口与 LDC OAuth 完全对称，仅域名不同：

| 接口 | URL |
|------|-----|
| 获取授权 URL | `GET https://cdk.linux.do/api/v1/oauth/login` |
| OAuth 回调 | `POST https://cdk.linux.do/api/v1/oauth/callback` |
| 获取用户信息 | `GET https://cdk.linux.do/api/v1/oauth/user-info` |
| 登出 | `GET https://cdk.linux.do/api/v1/oauth/logout` |

**Request/Response 格式：** 与 LDC 完全一致。

---

# 第 25 节：LDC 打赏 API

---

## 25.1 执行打赏

```
POST https://credit.linux.do/epay/pay/distribute
```

**场景**：对帖子/用户进行 LDC 信用积分打赏。

**Request Headers：**

```
Authorization: Basic <base64(clientId:clientSecret)>
Content-Type: application/json
```

**Request Body（JSON）：** `LdcRewardRequest` 对象（由模型定义）。

**Response (200)：** `LdcRewardResult` 对象。

**Response (401)：** 认证失败。
