# DNS over HTTPS

日期：2026-08-22  
状态：已实现

## 范围

Fire 在 **openwire 建连 DNS** 这一条权威路径上支持 RFC 8484 DoH。用户可在设置里开关，并选择内置源或填写自定义 `https://` URL。

| 层 | 路径 |
|----|------|
| 模型 | `fire-models::doh` |
| Core | `fire-core::doh` → `Client::builder().dns_resolver(FireDohResolver)` |
| UniFFI | `FireSessionHandle::{list_doh_presets,get_doh_settings,set_doh_settings,probe_doh_settings}` |
| iOS | 设置 → DNS over HTTPS（`FireDohSourceViewController`） |
| Android | 个人页 → 设置（`SettingsActivity`） |

## 权威路径

每次 API / MessageBus 请求建立 TCP 前，openwire 调用 `DnsResolver`。`FireDohResolver`：

1. 关闭 → `tokio::net::lookup_host`（系统 DNS）
2. 主机已是 IP → 直接使用
3. 主机等于当前 DoH 服务器主机 → 预设 bootstrap IP 或系统 DNS（禁止递归 DoH）
4. 否则 POST `application/dns-message` 查 A + AAAA，按 TTL 缓存

失败语义仍是 `WireErrorKind::Dns`。**不会**在 DoH 失败后回退系统 DNS 去解析业务域名——污染环境下回退会假装成功。

设置热更新：resolver 持有 `Arc<RwLock<DohSettings>>`，不重建 HTTP Client。持久化在 `workspace/cache/doh-settings.json`。

## 预设

默认关闭，默认 URL 为阿里 DNS。内置源：阿里 DNS、DNSPod、腾讯 DNS、Cloudflare、Google、Quad9、Canadian Shield。预设主机带 bootstrap IP，避免解析 DoH 主机时再走被污染的系统 DNS。

## 非范围

- 不引入 FluxDO 本地 MITM 代理、不安装用户 CA、不做 ECH。
- WebView 登录 / Cloudflare challenge 仍走系统 DNS（platform-owned）。
- Nuke / Coil 图片请求仍走系统 DNS。linux.do 图床若也被污染，会出现 API 通、图片不通；后续工作流再考虑平台 DNS 挂钩。

## 验证

```bash
cargo fmt --all --check
cargo clippy --keep-going -p fire-models -p fire-core -p fire-uniffi --all-targets --no-deps -- -D warnings
cargo test -p fire-models -p fire-core -p fire-uniffi --all-targets
```
