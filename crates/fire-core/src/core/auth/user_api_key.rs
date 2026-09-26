use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use http::Method;
use serde_json::Value;
use tracing::{info, warn};

use super::super::network::header_value;
use super::super::FireCore;
use crate::error::FireCoreError;

pub const USER_API_KEY_APPLICATION_NAME: &str = "Fire";
pub const USER_API_KEY_QR_APPLICATION_NAME: &str = "Fire QR Login";
pub const USER_API_KEY_SCOPES: &str = "one_time_password";
pub const USER_API_KEY_AUTH_REDIRECT: &str = "discourse://auth_redirect";
const SELF_HEAL_COOLDOWN: Duration = Duration::from_secs(10 * 60);

pub(crate) type UserApiKeyPublicKeyFn = Arc<dyn Fn() -> String + Send + Sync>;
pub(crate) type UserApiKeyDecryptFn = Arc<dyn Fn(String) -> Option<String> + Send + Sync>;
pub(crate) type UserApiKeyReadFn = Arc<dyn Fn() -> Option<String> + Send + Sync>;
pub(crate) type UserApiKeyWriteFn = Arc<dyn Fn(String) + Send + Sync>;
pub(crate) type UserApiKeyClearFn = Arc<dyn Fn() + Send + Sync>;

#[derive(Clone)]
pub(crate) struct FireUserApiKeyCryptoHandler {
    pub public_key_pem: UserApiKeyPublicKeyFn,
    pub decrypt: UserApiKeyDecryptFn,
    pub read_api_key: UserApiKeyReadFn,
    pub write_api_key: UserApiKeyWriteFn,
    pub clear_api_key: UserApiKeyClearFn,
}

#[derive(Clone, Default)]
pub(crate) struct FireUserApiKeyCryptoRegistry {
    inner: Arc<Mutex<Option<FireUserApiKeyCryptoHandler>>>,
}

impl FireUserApiKeyCryptoRegistry {
    pub(crate) fn set(&self, handler: FireUserApiKeyCryptoHandler) {
        *self
            .inner
            .lock()
            .expect("user api key crypto mutex poisoned") = Some(handler);
    }

    pub(crate) fn clear(&self) {
        *self
            .inner
            .lock()
            .expect("user api key crypto mutex poisoned") = None;
    }

    pub(crate) fn get(&self) -> Option<FireUserApiKeyCryptoHandler> {
        self.inner
            .lock()
            .expect("user api key crypto mutex poisoned")
            .clone()
    }
}

#[derive(Default)]
pub(crate) struct FireUserApiKeyRuntime {
    pending_nonce: Option<String>,
    last_self_heal_failure_at: Option<Instant>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserApiKeyAuthorizeUrl {
    pub url: String,
    pub nonce: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserApiKeyAuthRedirectResult {
    pub ok: bool,
    pub stale: bool,
    pub username: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QrLoginPayload {
    pub version: i32,
    pub api_key: String,
    pub otp: String,
    pub username: String,
    pub expires_at_unix_ms: Option<i64>,
}

impl QrLoginPayload {
    pub fn is_expired(&self) -> bool {
        let Some(expires_at) = self.expires_at_unix_ms else {
            return false;
        };
        current_unix_ms() > expires_at
    }
}

impl FireCore {
    pub fn set_user_api_key_crypto_handler(
        &self,
        public_key_pem: impl Fn() -> String + Send + Sync + 'static,
        decrypt: impl Fn(String) -> Option<String> + Send + Sync + 'static,
        read_api_key: impl Fn() -> Option<String> + Send + Sync + 'static,
        write_api_key: impl Fn(String) + Send + Sync + 'static,
        clear_api_key: impl Fn() + Send + Sync + 'static,
    ) {
        self.user_api_key_crypto.set(FireUserApiKeyCryptoHandler {
            public_key_pem: Arc::new(public_key_pem),
            decrypt: Arc::new(decrypt),
            read_api_key: Arc::new(read_api_key),
            write_api_key: Arc::new(write_api_key),
            clear_api_key: Arc::new(clear_api_key),
        });
    }

    pub fn clear_user_api_key_crypto_handler(&self) {
        self.user_api_key_crypto.clear();
    }

    pub fn build_user_api_key_authorize_url(
        &self,
        public_key_pem: String,
        client_id: String,
        application_name: Option<String>,
    ) -> Result<UserApiKeyAuthorizeUrl, FireCoreError> {
        let nonce = new_nonce();
        {
            let mut runtime = self
                .user_api_key_runtime
                .lock()
                .expect("user api key runtime mutex poisoned");
            runtime.pending_nonce = Some(nonce.clone());
        }
        persist_pending_nonce(self.workspace_path(), Some(&nonce));
        let url = build_authorize_url(
            self.base_url(),
            application_name
                .as_deref()
                .unwrap_or(USER_API_KEY_APPLICATION_NAME),
            &client_id,
            &public_key_pem,
            &nonce,
        )?;
        Ok(UserApiKeyAuthorizeUrl { url, nonce })
    }

    pub async fn complete_user_api_key_login(
        &self,
        otp: String,
        api_key: Option<String>,
    ) -> Result<UserApiKeyAuthRedirectResult, FireCoreError> {
        if !redeem_otp(self, &otp).await? {
            return Ok(UserApiKeyAuthRedirectResult {
                ok: false,
                stale: false,
                username: None,
            });
        }
        if let Some(api_key) = api_key
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            if key_worth_keeping() {
                if let Some(handler) = self.user_api_key_crypto.get() {
                    (handler.write_api_key)(api_key.to_string());
                }
            } else {
                let _ = revoke_user_api_key(self, api_key).await;
                if let Some(handler) = self.user_api_key_crypto.get() {
                    (handler.clear_api_key)();
                }
            }
        }
        let snapshot = self.finalize_login_ready().await?;
        Ok(UserApiKeyAuthRedirectResult {
            ok: snapshot.cookies.has_login_session(),
            stale: false,
            username: snapshot.bootstrap.current_username,
        })
    }

    pub async fn handle_user_api_key_auth_redirect(
        &self,
        uri: String,
    ) -> Result<UserApiKeyAuthRedirectResult, FireCoreError> {
        let Some(handler) = self.user_api_key_crypto.get() else {
            return Ok(UserApiKeyAuthRedirectResult {
                ok: false,
                stale: true,
                username: None,
            });
        };
        let parsed = url::Url::parse(&uri).map_err(|_| FireCoreError::InvalidArgument {
            operation: "handle_user_api_key_auth_redirect",
            details: "invalid auth redirect".to_string(),
        })?;
        if !is_auth_redirect(&parsed) {
            return Ok(UserApiKeyAuthRedirectResult {
                ok: false,
                stale: true,
                username: None,
            });
        }
        let pending_nonce = self
            .user_api_key_runtime
            .lock()
            .expect("user api key runtime mutex poisoned")
            .pending_nonce
            .clone()
            .or_else(|| load_pending_nonce(self.workspace_path()));
        let Some(payload_param) = query_param(&parsed, "payload") else {
            return Ok(UserApiKeyAuthRedirectResult {
                ok: false,
                stale: true,
                username: None,
            });
        };
        let Some(decrypted) = (handler.decrypt)(payload_param) else {
            return Ok(UserApiKeyAuthRedirectResult {
                ok: false,
                stale: true,
                username: None,
            });
        };
        let payload: Value = serde_json::from_str(&decrypted).unwrap_or_default();
        let nonce = payload
            .get("nonce")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if pending_nonce.as_deref() != Some(nonce) {
            return Ok(UserApiKeyAuthRedirectResult {
                ok: false,
                stale: true,
                username: None,
            });
        }
        self.clear_pending_nonce();
        let api_key = payload
            .get("key")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string);
        let otp = query_param(&parsed, "oneTimePassword")
            .and_then(|value| (handler.decrypt)(value))
            .unwrap_or_default();
        if otp.is_empty() {
            if let Some(api_key) = api_key {
                (handler.write_api_key)(api_key);
            }
            return Ok(UserApiKeyAuthRedirectResult {
                ok: false,
                stale: false,
                username: None,
            });
        }
        self.complete_user_api_key_login(otp, api_key).await
    }

    pub async fn redeem_user_api_key_otp(&self, otp: String) -> Result<bool, FireCoreError> {
        redeem_otp(self, &otp).await
    }

    pub async fn revoke_user_api_key(&self, api_key: String) -> Result<bool, FireCoreError> {
        revoke_user_api_key(self, &api_key).await
    }

    pub fn encode_qr_login_payload(&self, payload: &QrLoginPayload, scheme: &str) -> String {
        encode_qr_login_payload(payload, scheme)
    }

    pub fn parse_qr_login_payload(raw: &str) -> Option<QrLoginPayload> {
        parse_qr_login_payload(raw)
    }

    pub async fn create_qr_login_payload(
        &self,
        public_key_pem: String,
        client_id: String,
        username: Option<String>,
    ) -> Result<QrLoginPayload, FireCoreError> {
        let Some(handler) = self.user_api_key_crypto.get() else {
            return Err(FireCoreError::InvalidArgument {
                operation: "create_qr_login_payload",
                details: "user api key crypto handler is not registered".to_string(),
            });
        };
        let nonce = new_nonce();
        if !self.snapshot().cookies.has_csrf_token() {
            let _ = self.refresh_csrf_token_if_needed().await;
        }
        let traced = self.build_form_request_with_headers(
            "create_qr_user_api_key",
            Method::POST,
            "/user-api-key",
            vec![
                (
                    "application_name".to_string(),
                    USER_API_KEY_QR_APPLICATION_NAME.to_string(),
                ),
                ("client_id".to_string(), client_id),
                ("scopes".to_string(), USER_API_KEY_SCOPES.to_string()),
                ("public_key".to_string(), public_key_pem),
                ("nonce".to_string(), nonce.clone()),
                (
                    "auth_redirect".to_string(),
                    USER_API_KEY_AUTH_REDIRECT.to_string(),
                ),
            ],
            vec![("X-Requested-With", "XMLHttpRequest".to_string())],
            true,
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let status = response.status().as_u16();
        let location = header_value(response.headers(), "location");
        let body = self.read_response_text(trace_id, response).await.ok();
        let redirect = location.or_else(|| {
            body.as_deref()
                .and_then(|text| serde_json::from_str::<Value>(text).ok())
                .and_then(|json| {
                    json.get("redirect_url")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                })
        });
        let Some(redirect) = redirect else {
            return Err(FireCoreError::InvalidArgument {
                operation: "create_qr_login_payload",
                details: format!("create user api key returned no redirect ({status})"),
            });
        };
        let redirect_url =
            url::Url::parse(&redirect).map_err(|_| FireCoreError::InvalidArgument {
                operation: "create_qr_login_payload",
                details: "invalid redirect url".to_string(),
            })?;
        let payload_param =
            query_param(&redirect_url, "payload").ok_or(FireCoreError::InvalidArgument {
                operation: "create_qr_login_payload",
                details: "redirect missing payload".to_string(),
            })?;
        let otp_param = query_param(&redirect_url, "oneTimePassword").ok_or(
            FireCoreError::InvalidArgument {
                operation: "create_qr_login_payload",
                details: "redirect missing oneTimePassword".to_string(),
            },
        )?;
        let decrypted = (handler.decrypt)(payload_param).ok_or(FireCoreError::InvalidArgument {
            operation: "create_qr_login_payload",
            details: "failed to decrypt payload".to_string(),
        })?;
        let payload: Value = serde_json::from_str(&decrypted).unwrap_or_default();
        if payload.get("nonce").and_then(Value::as_str) != Some(nonce.as_str()) {
            return Err(FireCoreError::InvalidArgument {
                operation: "create_qr_login_payload",
                details: "nonce mismatch".to_string(),
            });
        }
        let api_key = payload
            .get("key")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or(FireCoreError::InvalidArgument {
                operation: "create_qr_login_payload",
                details: "payload missing key".to_string(),
            })?
            .to_string();
        let otp = (handler.decrypt)(otp_param).ok_or(FireCoreError::InvalidArgument {
            operation: "create_qr_login_payload",
            details: "failed to decrypt otp".to_string(),
        })?;
        Ok(QrLoginPayload {
            version: 2,
            api_key,
            otp,
            username: username
                .or_else(|| self.snapshot().bootstrap.current_username)
                .unwrap_or_default(),
            expires_at_unix_ms: None,
        })
    }

    pub async fn login_with_qr_payload(
        &self,
        raw: String,
    ) -> Result<UserApiKeyAuthRedirectResult, FireCoreError> {
        let payload = parse_qr_login_payload(&raw).ok_or(FireCoreError::InvalidArgument {
            operation: "login_with_qr_payload",
            details: "invalid qr login payload".to_string(),
        })?;
        if payload.version != 2 {
            return Err(FireCoreError::InvalidArgument {
                operation: "login_with_qr_payload",
                details: "unsupported qr login version".to_string(),
            });
        }
        if payload.is_expired() {
            return Err(FireCoreError::InvalidArgument {
                operation: "login_with_qr_payload",
                details: "qr login payload expired".to_string(),
            });
        }
        let result = self
            .complete_user_api_key_login(payload.otp, Some(payload.api_key.clone()))
            .await?;
        let _ = revoke_user_api_key(self, &payload.api_key).await;
        Ok(result)
    }

    pub(crate) async fn recover_via_user_api_key(
        &self,
    ) -> Result<Option<fire_models::ProbeResult>, FireCoreError> {
        let Some(handler) = self.user_api_key_crypto.get() else {
            return Ok(None);
        };
        {
            let runtime = self
                .user_api_key_runtime
                .lock()
                .expect("user api key runtime mutex poisoned");
            if runtime
                .last_self_heal_failure_at
                .is_some_and(|at| at.elapsed() < SELF_HEAL_COOLDOWN)
            {
                return Ok(None);
            }
        }
        let Some(api_key) = (handler.read_api_key)()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        else {
            return Ok(None);
        };
        let public_key_pem = (handler.public_key_pem)();
        if public_key_pem.trim().is_empty() {
            return Ok(None);
        }
        match request_otp(self, &api_key, &public_key_pem, &handler).await {
            Ok(Some(otp)) => {
                if redeem_otp(self, &otp).await? {
                    match self.probe_session_with_override(None).await {
                        Ok(result @ fire_models::ProbeResult::Valid { .. }) => {
                            self.clear_self_heal_failure();
                            Ok(Some(result))
                        }
                        Ok(_) => {
                            self.mark_self_heal_failure();
                            Ok(None)
                        }
                        Err(error) => Err(error),
                    }
                } else {
                    self.mark_self_heal_failure();
                    Ok(None)
                }
            }
            Ok(None) => {
                self.mark_self_heal_failure();
                Ok(None)
            }
            Err(error) => {
                self.mark_self_heal_failure();
                Err(error)
            }
        }
    }

    pub(crate) async fn revoke_stored_user_api_key(&self) {
        let Some(handler) = self.user_api_key_crypto.get() else {
            return;
        };
        if let Some(api_key) = (handler.read_api_key)()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        {
            let _ = revoke_user_api_key(self, &api_key).await;
        }
        (handler.clear_api_key)();
        self.clear_pending_nonce();
    }

    fn clear_pending_nonce(&self) {
        self.user_api_key_runtime
            .lock()
            .expect("user api key runtime mutex poisoned")
            .pending_nonce = None;
        persist_pending_nonce(self.workspace_path(), None);
    }

    fn mark_self_heal_failure(&self) {
        self.user_api_key_runtime
            .lock()
            .expect("user api key runtime mutex poisoned")
            .last_self_heal_failure_at = Some(Instant::now());
    }

    fn clear_self_heal_failure(&self) {
        self.user_api_key_runtime
            .lock()
            .expect("user api key runtime mutex poisoned")
            .last_self_heal_failure_at = None;
    }
}

async fn redeem_otp(core: &FireCore, otp: &str) -> Result<bool, FireCoreError> {
    let otp = otp.trim();
    if !otp.bytes().all(|byte| byte.is_ascii_hexdigit()) || otp.is_empty() {
        warn!("otp redeem rejected malformed token");
        return Ok(false);
    }
    let before = core.snapshot().cookies.t_token.clone();
    let path = format!("/session/otp/{otp}");
    let traced = core.build_api_request("redeem_user_api_key_otp", Method::POST, &path, true)?;
    let (trace_id, response) = core.execute_request(traced).await?;
    let status = response.status().as_u16();
    let _ = core.read_response_text(trace_id, response).await;
    let after = core.snapshot().cookies.t_token.clone();
    let ok = after
        .as_deref()
        .is_some_and(|token| !token.is_empty() && Some(token) != before.as_deref());
    info!(status, ok, "otp redeem finished");
    Ok(ok)
}

async fn revoke_user_api_key(core: &FireCore, api_key: &str) -> Result<bool, FireCoreError> {
    if api_key.trim().is_empty() {
        return Ok(false);
    }
    let traced = core
        .build_form_request_with_headers(
            "revoke_user_api_key",
            Method::POST,
            "/user-api-key/revoke",
            Vec::new(),
            vec![("User-Api-Key", api_key.to_string())],
            false,
        )?
        .without_csrf_header();
    match core.execute_request(traced).await {
        Ok((trace_id, response)) => {
            let status = response.status().as_u16();
            let _ = core.read_response_text(trace_id, response).await;
            Ok((200..400).contains(&status))
        }
        Err(error) => {
            warn!(error = %error, "user api key revoke failed");
            Ok(false)
        }
    }
}

async fn request_otp(
    core: &FireCore,
    api_key: &str,
    public_key_pem: &str,
    handler: &FireUserApiKeyCryptoHandler,
) -> Result<Option<String>, FireCoreError> {
    let traced = core
        .build_form_request_with_headers(
            "request_user_api_key_otp",
            Method::POST,
            "/user-api-key/otp",
            vec![
                ("public_key".to_string(), public_key_pem.to_string()),
                (
                    "auth_redirect".to_string(),
                    USER_API_KEY_AUTH_REDIRECT.to_string(),
                ),
                (
                    "application_name".to_string(),
                    USER_API_KEY_APPLICATION_NAME.to_string(),
                ),
            ],
            vec![("User-Api-Key", api_key.to_string())],
            false,
        )?
        .without_csrf_header();
    let (trace_id, response) = core.execute_request(traced).await?;
    let status = response.status().as_u16();
    let location = header_value(response.headers(), "location");
    let _ = core.read_response_text(trace_id, response).await;
    if status == 403 {
        (handler.clear_api_key)();
        return Ok(None);
    }
    let Some(location) = location else {
        return Ok(None);
    };
    let redirect = url::Url::parse(&location).ok();
    let Some(encrypted) = redirect
        .as_ref()
        .and_then(|url| query_param(url, "oneTimePassword"))
    else {
        return Ok(None);
    };
    Ok((handler.decrypt)(encrypted))
}

fn build_authorize_url(
    base_url: &str,
    application_name: &str,
    client_id: &str,
    public_key_pem: &str,
    nonce: &str,
) -> Result<String, FireCoreError> {
    let mut url = url::Url::parse(base_url)?.join("/user-api-key/new")?;
    url.query_pairs_mut()
        .append_pair("application_name", application_name)
        .append_pair("client_id", client_id)
        .append_pair("scopes", USER_API_KEY_SCOPES)
        .append_pair("public_key", public_key_pem)
        .append_pair("nonce", nonce)
        .append_pair("auth_redirect", USER_API_KEY_AUTH_REDIRECT);
    Ok(url.into())
}

pub fn encode_qr_login_payload(payload: &QrLoginPayload, scheme: &str) -> String {
    let mut url = url::Url::parse(&format!("{scheme}://qr-login"))
        .unwrap_or_else(|_| url::Url::parse("fire://qr-login").expect("static fire qr url"));
    url.query_pairs_mut()
        .append_pair("v", &payload.version.to_string())
        .append_pair("k", &payload.api_key)
        .append_pair("o", &payload.otp)
        .append_pair("u", &payload.username)
        .append_pair(
            "exp",
            &payload
                .expires_at_unix_ms
                .map(|value| value.to_string())
                .unwrap_or_else(|| "0".to_string()),
        );
    url.into()
}

pub fn parse_qr_login_payload(raw: &str) -> Option<QrLoginPayload> {
    let uri = url::Url::parse(raw.trim()).ok()?;
    let scheme = uri.scheme();
    if scheme != "fire" && scheme != "fluxdo" {
        return None;
    }
    let host_or_path = if uri.host_str().is_some_and(|host| !host.is_empty()) {
        uri.host_str()?.to_string()
    } else {
        uri.path_segments()?.next()?.to_string()
    };
    if host_or_path != "qr-login" {
        return None;
    }
    let version = uri
        .query_pairs()
        .find(|(key, _)| key == "v")?
        .1
        .parse()
        .ok()?;
    let api_key = query_from_pairs(&uri, "k")?;
    let otp = query_from_pairs(&uri, "o")?;
    let username = query_from_pairs(&uri, "u").unwrap_or_default();
    let exp = query_from_pairs(&uri, "exp")
        .unwrap_or_else(|| "0".to_string())
        .parse::<i64>()
        .ok()?;
    if exp < 0 || api_key.is_empty() || otp.is_empty() {
        return None;
    }
    Some(QrLoginPayload {
        version,
        api_key,
        otp,
        username,
        expires_at_unix_ms: (exp > 0).then_some(exp),
    })
}

fn is_auth_redirect(uri: &url::Url) -> bool {
    matches!(uri.scheme(), "discourse" | "fire")
        && (uri.host_str() == Some("auth_redirect")
            || uri.path().trim_matches('/') == "auth_redirect")
}

fn query_param(uri: &url::Url, name: &str) -> Option<String> {
    query_from_pairs(uri, name)
}

fn query_from_pairs(uri: &url::Url, name: &str) -> Option<String> {
    uri.query_pairs().find_map(|(key, value)| {
        (key == name)
            .then(|| value.trim().to_string())
            .filter(|value| !value.is_empty())
    })
}

fn key_worth_keeping() -> bool {
    USER_API_KEY_SCOPES
        .split(',')
        .any(|scope| scope.trim() == "write")
}

fn new_nonce() -> String {
    format!("{:x}{:x}", current_unix_ms(), std::process::id())
}

fn current_unix_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or(0)
}

fn nonce_path(workspace_path: &std::path::Path) -> std::path::PathBuf {
    workspace_path.join("cache").join("user-api-key-nonce.json")
}

fn persist_pending_nonce(workspace_path: Option<&std::path::Path>, nonce: Option<&str>) {
    let Some(workspace_path) = workspace_path else {
        return;
    };
    let path = nonce_path(workspace_path);
    if let Some(nonce) = nonce {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(path, nonce);
    } else {
        let _ = std::fs::remove_file(path);
    }
}

fn load_pending_nonce(workspace_path: Option<&std::path::Path>) -> Option<String> {
    let path = nonce_path(workspace_path?);
    let payload = std::fs::read_to_string(path).ok()?;
    let trimmed = payload.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qr_payload_round_trip_accepts_fire_and_fluxdo() {
        let payload = QrLoginPayload {
            version: 2,
            api_key: "key-1".into(),
            otp: "abc123".into(),
            username: "alice".into(),
            expires_at_unix_ms: None,
        };
        let fire = encode_qr_login_payload(&payload, "fire");
        let fluxdo = encode_qr_login_payload(&payload, "fluxdo");
        assert_eq!(parse_qr_login_payload(&fire), Some(payload.clone()));
        assert_eq!(parse_qr_login_payload(&fluxdo), Some(payload));
        assert!(parse_qr_login_payload("https://example.com").is_none());
    }

    #[test]
    fn authorize_url_uses_discourse_redirect_and_otp_scope() {
        let url = build_authorize_url(
            "https://linux.do",
            "Fire",
            "client",
            "-----BEGIN PUBLIC KEY-----",
            "nonce",
        )
        .expect("url");
        let parsed = url::Url::parse(&url).expect("parse");
        let pairs: Vec<(String, String)> = parsed
            .query_pairs()
            .map(|(k, v)| (k.into_owned(), v.into_owned()))
            .collect();
        assert!(url.starts_with("https://linux.do/user-api-key/new?"));
        assert!(pairs.contains(&("scopes".into(), "one_time_password".into())));
        assert!(pairs.contains(&("auth_redirect".into(), "discourse://auth_redirect".into())));
    }
}
