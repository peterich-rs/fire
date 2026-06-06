# 文件上传 API

> 对应 FluxDO 源文档第 11 节

---

## 11.1 上传文件

```
POST /uploads.json
Content-Type: multipart/form-data
```

**场景**：编辑器中上传图片或附件。内置速率限制重试（最多 3 次）。

**Query Parameters：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `client_id` | string | 是 | MessageBus 客户端 ID |

**Request Body（multipart/form-data）：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `upload_type` | string | 是 | 固定值 `"composer"` |
| `synchronous` | bool | 是 | 固定值 `true` |
| `file` | File | 是 | 文件（MultipartFile） |

**Response (200)：**

```json
{
  "id": 123,
  "url": "/uploads/...",
  "short_url": "upload://xxxxx",
  "short_path": "/uploads/short-url/...",
  "original_filename": "image.png",
  "width": 1920,
  "height": 1080,
  "thumbnail_width": 400,
  "thumbnail_height": 225,
  "filesize": 123456,
  "human_filesize": "120.5 KB",
  "extension": "png"
}
```

**错误码：**
- `413`：文件过大
- `422`：格式不支持
- `429`：速率限制（自动重试）

---

## 11.2 批量解析短链接

```
POST /uploads/lookup-urls
```

**场景**：将 `upload://` 格式的短链接解析为实际 URL。

**Request Body（JSON）：**

```json
{
  "short_urls": ["upload://xxxxx", "upload://yyyyy"]
}
```

**Response (200)：**

```json
[
  {
    "short_url": "upload://xxxxx",
    "url": "/uploads/...",
    "short_path": "/uploads/short-url/..."
  }
]
```
