// Discourse strips `data-preloaded` for crawler-style requests, so the shared
// Rust client needs a browser-style fallback UA until hosts pass through an
// exact WebView/browser UA.
#[cfg(target_os = "ios")]
pub(super) const FIRE_USER_AGENT: &str = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
#[cfg(target_os = "android")]
pub(super) const FIRE_USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36";
#[cfg(target_os = "macos")]
pub(super) const FIRE_USER_AGENT: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";
#[cfg(all(
    not(target_os = "ios"),
    not(target_os = "android"),
    not(target_os = "macos")
))]
pub(super) const FIRE_USER_AGENT: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
pub(super) const FIRE_ACCEPT_LANGUAGE: &str = "zh-CN,zh;q=0.9,en;q=0.8";
pub(super) const FIRE_JSON_ACCEPT: &str = "application/json, text/javascript, */*; q=0.01";
pub(super) const FIRE_MESSAGE_BUS_ACCEPT: &str = "text/plain, */*; q=0.01";
pub(super) const LOGIN_INVALIDATED_MESSAGE: &str = "登录状态已失效，请重新登录。";
pub(super) const COOKIE_SELF_HEALING_NAMES: &[&str] =
    &["_t", "_forum_session", "cf_clearance", "_cfuvid"];

/// Placeholder header value used when a write request needs CSRF but Fire's
/// preflight has not yet populated the token. Mirrors Discourse's official web
/// client, which sends `X-CSRF-Token: undefined` so the server can answer with
/// BAD CSRF and let the client refresh + retry. See
/// `execute_api_request_with_csrf_retry`.
pub(super) const MISSING_CSRF_TOKEN_PLACEHOLDER: &str = "undefined";
