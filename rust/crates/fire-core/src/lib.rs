use std::{
    fs, io,
    path::{Path, PathBuf},
    sync::{Arc, OnceLock, RwLock},
    time::{SystemTime, UNIX_EPOCH},
};

use fire_models::{BootstrapArtifacts, CookieSnapshot, LoginSyncInput, SessionSnapshot};
use http::{
    header::{HeaderMap, HeaderValue},
    Method, Request, StatusCode,
};
use mars_xlog::{LogLevel, Xlog, XlogConfig, XlogError};
use openwire::{Client, CookieJar, RequestBody, ResponseBody, WireError};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;
use tracing::{debug, warn};
use url::Url;

#[derive(Debug, Clone)]
pub struct FireCoreConfig {
    pub base_url: String,
}

impl Default for FireCoreConfig {
    fn default() -> Self {
        Self {
            base_url: "https://linux.do".to_string(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct FireLoggerConfig {
    pub log_dir: String,
    pub cache_dir: Option<String>,
    pub name_prefix: String,
    pub level: LogLevel,
}

#[derive(Clone)]
pub struct FireLogger {
    inner: Xlog,
}

impl FireLogger {
    pub fn init(config: FireLoggerConfig) -> Result<Self, FireCoreError> {
        let mut xlog_config = XlogConfig::new(config.log_dir, config.name_prefix);
        if let Some(cache_dir) = config.cache_dir {
            xlog_config = xlog_config.cache_dir(cache_dir);
        }
        let inner = Xlog::init(xlog_config, config.level)?;
        Ok(Self { inner })
    }

    pub fn set_console_log_open(&self, open: bool) {
        self.inner.set_console_log_open(open);
    }
}

#[derive(Clone)]
pub struct FireCore {
    base_url: Url,
    client: Client,
    session: Arc<RwLock<SessionSnapshot>>,
}

impl FireCore {
    pub fn new(config: FireCoreConfig) -> Result<Self, FireCoreError> {
        let base_url = Url::parse(&config.base_url)?;
        let session = SessionSnapshot {
            cookies: CookieSnapshot::default(),
            bootstrap: BootstrapArtifacts {
                base_url: base_url.as_str().to_string(),
                ..BootstrapArtifacts::default()
            },
        };
        let session = Arc::new(RwLock::new(session));
        let cookie_jar = Arc::new(FireSessionCookieJar::new(base_url.clone(), session.clone()));
        let client = Client::builder()
            .cookie_jar(cookie_jar)
            .build()
            .map_err(|source| FireCoreError::ClientBuild { source })?;

        Ok(Self {
            base_url,
            client,
            session,
        })
    }

    pub fn base_url(&self) -> &str {
        self.base_url.as_str()
    }

    pub fn snapshot(&self) -> SessionSnapshot {
        self.session.read().expect("session poisoned").clone()
    }

    pub fn apply_cookies(&self, cookies: CookieSnapshot) -> SessionSnapshot {
        self.update_session(|session| {
            session.cookies.merge_patch(&cookies);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "updated session cookies"
            );
        })
    }

    pub fn apply_bootstrap(&self, bootstrap: BootstrapArtifacts) -> SessionSnapshot {
        self.update_session(|session| {
            session.bootstrap.merge_patch(&bootstrap);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "updated bootstrap artifacts"
            );
        })
    }

    pub fn apply_csrf_token(&self, csrf_token: String) -> SessionSnapshot {
        self.update_session(|session| {
            session.cookies.merge_patch(&CookieSnapshot {
                csrf_token: Some(csrf_token),
                ..CookieSnapshot::default()
            });
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "updated csrf token"
            );
        })
    }

    pub fn clear_csrf_token(&self) -> SessionSnapshot {
        self.update_session(|session| {
            session.cookies.csrf_token = None;
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "cleared csrf token"
            );
        })
    }

    pub fn apply_home_html(&self, html: String) -> SessionSnapshot {
        let parsed = parse_home_state(self.base_url(), &html);
        self.update_session(|session| {
            session.cookies.merge_patch(&parsed.cookies_patch);
            session.bootstrap.merge_patch(&parsed.bootstrap_patch);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "applied home html bootstrap"
            );
        })
    }

    pub fn sync_login_context(&self, input: LoginSyncInput) -> SessionSnapshot {
        let parsed_html = input
            .home_html
            .as_deref()
            .map(|html| parse_home_state(self.base_url(), html));
        self.update_session(|session| {
            session.cookies.merge_platform_cookies(&input.cookies);

            if let Some(csrf_token) = input.csrf_token {
                session.cookies.merge_patch(&CookieSnapshot {
                    csrf_token: Some(csrf_token),
                    ..CookieSnapshot::default()
                });
            }

            if let Some(username) = input.username {
                session.bootstrap.merge_patch(&BootstrapArtifacts {
                    current_username: Some(username),
                    ..BootstrapArtifacts::default()
                });
            }

            if let Some(parsed_html) = parsed_html {
                session.cookies.merge_patch(&parsed_html.cookies_patch);
                session.bootstrap.merge_patch(&parsed_html.bootstrap_patch);
            }

            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                cookie_count = input.cookies.len(),
                has_home_html = input.home_html.as_ref().is_some_and(|html| !html.is_empty()),
                "synced platform login context"
            );
        })
    }

    pub fn logout_local(&self, preserve_cf_clearance: bool) -> SessionSnapshot {
        self.update_session(|session| {
            session.clear_login_state(preserve_cf_clearance);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                preserve_cf_clearance,
                "cleared local login state"
            );
        })
    }

    pub fn export_session_json(&self) -> Result<String, FireCoreError> {
        let envelope = PersistedSessionEnvelope::new(self.snapshot());
        serde_json::to_string_pretty(&envelope).map_err(FireCoreError::PersistSerialize)
    }

    pub fn restore_session_json(&self, json: String) -> Result<SessionSnapshot, FireCoreError> {
        let envelope: PersistedSessionEnvelope =
            serde_json::from_str(&json).map_err(FireCoreError::PersistDeserialize)?;
        let snapshot = self.normalize_persisted_snapshot(envelope)?;
        Ok(self.update_session(|session| {
            *session = snapshot.clone();
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "restored persisted session from json"
            );
        }))
    }

    pub fn save_session_to_path(&self, path: impl AsRef<Path>) -> Result<(), FireCoreError> {
        let path = path.as_ref();
        let payload = self.export_session_json()?;
        write_atomic(path, payload.as_bytes()).map_err(|source| FireCoreError::PersistIo {
            path: path.to_path_buf(),
            source,
        })
    }

    pub fn load_session_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<SessionSnapshot, FireCoreError> {
        let path = path.as_ref();
        let payload = fs::read_to_string(path).map_err(|source| FireCoreError::PersistIo {
            path: path.to_path_buf(),
            source,
        })?;
        let snapshot = self.restore_session_json(payload)?;
        debug!(path = %path.display(), "restored persisted session from path");
        Ok(snapshot)
    }

    pub fn clear_session_path(&self, path: impl AsRef<Path>) -> Result<(), FireCoreError> {
        let path = path.as_ref();
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(source) => Err(FireCoreError::PersistIo {
                path: path.to_path_buf(),
                source,
            }),
        }
    }

    pub fn has_login_session(&self) -> bool {
        self.session
            .read()
            .expect("session poisoned")
            .cookies
            .has_login_session()
    }

    pub fn shared_client(&self) -> Client {
        self.client.clone()
    }

    pub async fn refresh_bootstrap(&self) -> Result<SessionSnapshot, FireCoreError> {
        let request = self.build_home_request()?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let response = expect_success("refresh bootstrap", response).await?;
        let response_username = header_value(response.headers(), "x-discourse-username");
        let html = response
            .into_body()
            .text()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let parsed = parse_home_state(self.base_url(), &html);

        Ok(self.update_session(|session| {
            session.cookies.merge_patch(&parsed.cookies_patch);
            session.bootstrap.merge_patch(&parsed.bootstrap_patch);
            if let Some(response_username) = response_username.clone() {
                session.bootstrap.merge_patch(&BootstrapArtifacts {
                    current_username: Some(response_username),
                    ..BootstrapArtifacts::default()
                });
            }
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "refreshed bootstrap over network"
            );
        }))
    }

    pub async fn refresh_csrf_token(&self) -> Result<SessionSnapshot, FireCoreError> {
        let request = self.build_api_request(Method::GET, "/session/csrf", false)?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let response = expect_success("refresh csrf token", response).await?;
        let payload: CsrfResponse = response
            .into_body()
            .json()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        if payload.csrf.is_empty() {
            return Err(FireCoreError::InvalidCsrfResponse);
        }

        Ok(self.update_session(|session| {
            session.cookies.merge_patch(&CookieSnapshot {
                csrf_token: Some(payload.csrf.clone()),
                ..CookieSnapshot::default()
            });
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "refreshed csrf token over network"
            );
        }))
    }

    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionSnapshot, FireCoreError> {
        let username = self
            .snapshot()
            .bootstrap
            .current_username
            .ok_or(FireCoreError::MissingCurrentUsername)?;

        if !self.snapshot().cookies.has_csrf_token() {
            let _ = self.refresh_csrf_token().await?;
        }

        let path = format!("/session/{username}");
        let request = self.build_api_request(Method::DELETE, &path, true)?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;

        if response.status() == StatusCode::FORBIDDEN {
            let body = response
                .into_body()
                .text()
                .await
                .map_err(|source| FireCoreError::Network { source })?;
            if is_bad_csrf_body(&body) {
                warn!("logout received BAD CSRF, refreshing token and retrying once");
                let _ = self.clear_csrf_token();
                let _ = self.refresh_csrf_token().await?;
                let retry = self.build_api_request(Method::DELETE, &path, true)?;
                let response = self
                    .client
                    .execute(retry)
                    .await
                    .map_err(|source| FireCoreError::Network { source })?;
                let _ = expect_success("logout", response).await?;
                return Ok(self.logout_local(preserve_cf_clearance));
            }

            return Err(FireCoreError::HttpStatus {
                operation: "logout",
                status: StatusCode::FORBIDDEN.as_u16(),
                body,
            });
        }

        let _ = expect_success("logout", response).await?;
        Ok(self.logout_local(preserve_cf_clearance))
    }

    fn build_home_request(&self) -> Result<Request<RequestBody>, FireCoreError> {
        let uri = self.base_url.join("/")?;
        Request::builder()
            .method(Method::GET)
            .uri(uri.as_str())
            .header("Accept", "text/html")
            .header("User-Agent", "Fire/0.1")
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)
    }

    fn build_api_request(
        &self,
        method: Method,
        path: &str,
        requires_csrf: bool,
    ) -> Result<Request<RequestBody>, FireCoreError> {
        let uri = self.base_url.join(path)?;
        let origin = request_origin(&self.base_url);
        let referer = request_referer(&self.base_url);
        let snapshot = self.snapshot();

        let mut builder = Request::builder()
            .method(method)
            .uri(uri.as_str())
            .header(
                "Accept",
                "application/json;q=0.9, text/plain;q=0.8, */*;q=0.5",
            )
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
            .header("X-Requested-With", "XMLHttpRequest")
            .header("User-Agent", "Fire/0.1")
            .header("Origin", origin)
            .header("Referer", referer);

        if snapshot.cookies.has_login_session() {
            builder = builder
                .header("Discourse-Logged-In", "true")
                .header("Discourse-Present", "true");
        }

        if requires_csrf {
            let csrf_token = snapshot
                .cookies
                .csrf_token
                .ok_or(FireCoreError::MissingCsrfToken)?;
            builder = builder.header("X-CSRF-Token", csrf_token);
        }

        builder
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)
    }

    fn update_session<F>(&self, mutate: F) -> SessionSnapshot
    where
        F: FnOnce(&mut SessionSnapshot),
    {
        let mut session = self.session.write().expect("session poisoned");
        mutate(&mut session);
        session.clone()
    }

    fn normalize_persisted_snapshot(
        &self,
        envelope: PersistedSessionEnvelope,
    ) -> Result<SessionSnapshot, FireCoreError> {
        if envelope.version != PersistedSessionEnvelope::CURRENT_VERSION {
            return Err(FireCoreError::PersistVersionMismatch {
                expected: PersistedSessionEnvelope::CURRENT_VERSION,
                found: envelope.version,
            });
        }

        let mut snapshot = envelope.snapshot;
        let persisted_base_url = snapshot.bootstrap.base_url.clone();
        if !persisted_base_url.is_empty() && persisted_base_url != self.base_url() {
            return Err(FireCoreError::PersistBaseUrlMismatch {
                expected: self.base_url().to_string(),
                found: persisted_base_url,
            });
        }

        snapshot = sanitize_snapshot_for_restore(self.base_url(), snapshot);
        Ok(snapshot)
    }
}

#[derive(Debug, Error)]
pub enum FireCoreError {
    #[error("invalid url: {0}")]
    InvalidUrl(#[from] url::ParseError),
    #[error("failed to build request: {0}")]
    RequestBuild(http::Error),
    #[error("failed to build network client: {source}")]
    ClientBuild { source: WireError },
    #[error("network request failed: {source}")]
    Network { source: WireError },
    #[error("failed to initialize logger: {0}")]
    Logger(#[from] XlogError),
    #[error("{operation} failed with HTTP {status}: {body}")]
    HttpStatus {
        operation: &'static str,
        status: u16,
        body: String,
    },
    #[error("logout requires a current username")]
    MissingCurrentUsername,
    #[error("request requires a csrf token")]
    MissingCsrfToken,
    #[error("csrf response did not contain a usable token")]
    InvalidCsrfResponse,
    #[error("failed to serialize persisted session: {0}")]
    PersistSerialize(serde_json::Error),
    #[error("failed to deserialize persisted session: {0}")]
    PersistDeserialize(serde_json::Error),
    #[error("persisted session uses unsupported version {found}, expected {expected}")]
    PersistVersionMismatch { expected: u32, found: u32 },
    #[error("persisted session base url mismatch: expected {expected}, found {found}")]
    PersistBaseUrlMismatch { expected: String, found: String },
    #[error("failed to access persisted session at {path}: {source}")]
    PersistIo { path: PathBuf, source: io::Error },
}

#[derive(Debug, Default)]
struct ParsedHomeState {
    cookies_patch: CookieSnapshot,
    bootstrap_patch: BootstrapArtifacts,
}

#[derive(Debug, Deserialize)]
struct CsrfResponse {
    csrf: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct PersistedSessionEnvelope {
    version: u32,
    saved_at_unix_ms: u64,
    snapshot: SessionSnapshot,
}

impl PersistedSessionEnvelope {
    const CURRENT_VERSION: u32 = 1;

    fn new(snapshot: SessionSnapshot) -> Self {
        Self {
            version: Self::CURRENT_VERSION,
            saved_at_unix_ms: now_unix_ms(),
            snapshot,
        }
    }
}

#[derive(Clone)]
struct FireSessionCookieJar {
    base_url: Url,
    session: Arc<RwLock<SessionSnapshot>>,
}

impl FireSessionCookieJar {
    fn new(base_url: Url, session: Arc<RwLock<SessionSnapshot>>) -> Self {
        Self { base_url, session }
    }
}

impl CookieJar for FireSessionCookieJar {
    fn set_cookies(&self, cookie_headers: &mut dyn Iterator<Item = &HeaderValue>, url: &Url) {
        if !same_cookie_scope(&self.base_url, url) {
            return;
        }

        let mut patch = CookieSnapshot::default();
        for header in cookie_headers {
            let Ok(value) = header.to_str() else {
                continue;
            };
            let Some((name, value)) = parse_set_cookie(value) else {
                continue;
            };

            match name {
                "_t" => patch.t_token = Some(value.to_string()),
                "_forum_session" => patch.forum_session = Some(value.to_string()),
                "cf_clearance" => patch.cf_clearance = Some(value.to_string()),
                _ => {}
            }
        }

        if patch == CookieSnapshot::default() {
            return;
        }

        let mut session = self.session.write().expect("session poisoned");
        session.cookies.merge_patch(&patch);
    }

    fn cookies(&self, url: &Url) -> Option<HeaderValue> {
        if !same_cookie_scope(&self.base_url, url) {
            return None;
        }

        let session = self.session.read().expect("session poisoned");
        let cookies = build_cookie_header(&session.cookies);
        if cookies.is_empty() {
            return None;
        }

        HeaderValue::from_str(&cookies).ok()
    }
}

fn parse_home_state(base_url: &str, html: &str) -> ParsedHomeState {
    let mut parsed = ParsedHomeState {
        bootstrap_patch: BootstrapArtifacts {
            base_url: base_url.to_string(),
            ..BootstrapArtifacts::default()
        },
        ..ParsedHomeState::default()
    };

    parsed.cookies_patch.csrf_token = find_meta_content(html, "csrf-token");
    parsed.bootstrap_patch.shared_session_key = find_meta_content(html, "shared_session_key");
    parsed.bootstrap_patch.current_username = find_meta_content(html, "current-username");
    parsed.bootstrap_patch.discourse_base_uri = find_meta_content(html, "discourse-base-uri");
    parsed.bootstrap_patch.turnstile_sitekey = find_first_attr(html, "data-sitekey");

    if let Some(preloaded_json) = find_first_attr(html, "data-preloaded") {
        let decoded = decode_html_entities(&preloaded_json);
        parsed.bootstrap_patch.preloaded_json = Some(decoded.clone());
        parsed.bootstrap_patch.has_preloaded_data = true;
        hydrate_preloaded_fields(&decoded, &mut parsed.bootstrap_patch);
    }

    parsed
}

fn hydrate_preloaded_fields(preloaded_json: &str, bootstrap: &mut BootstrapArtifacts) {
    let Ok(preloaded) = serde_json::from_str::<Value>(preloaded_json) else {
        warn!("failed to parse data-preloaded json");
        return;
    };

    if let Some(username) = preloaded
        .get("currentUser")
        .and_then(|value| value.get("username"))
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
    {
        bootstrap.current_username = Some(username.to_string());
    }

    if let Some(long_polling_base_url) = preloaded
        .get("siteSettings")
        .and_then(|value| value.get("long_polling_base_url"))
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
    {
        bootstrap.long_polling_base_url = Some(long_polling_base_url.to_string());
    }

    if let Some(meta) = preloaded.get("topicTrackingStateMeta") {
        if !meta.is_null() {
            bootstrap.topic_tracking_state_meta = serde_json::to_string(meta).ok();
        }
    }
}

fn find_meta_content(html: &str, target_name: &str) -> Option<String> {
    for tag in all_tags(html) {
        if !tag.starts_with("<meta") && !tag.starts_with("<META") {
            continue;
        }

        let name = extract_attr(tag, "name")?;
        if !name.eq_ignore_ascii_case(target_name) {
            continue;
        }

        if let Some(content) = extract_attr(tag, "content") {
            return Some(decode_html_entities(&content));
        }
    }

    None
}

fn find_first_attr(html: &str, attribute_name: &str) -> Option<String> {
    for tag in all_tags(html) {
        if let Some(value) = extract_attr(tag, attribute_name) {
            return Some(decode_html_entities(&value));
        }
    }

    None
}

fn all_tags(html: &str) -> impl Iterator<Item = &str> {
    static TAG_RE: OnceLock<Regex> = OnceLock::new();
    let regex = TAG_RE.get_or_init(|| Regex::new(r"(?is)<[^>]+>").expect("tag regex"));
    regex.find_iter(html).map(|matched| matched.as_str())
}

fn extract_attr(tag: &str, attribute_name: &str) -> Option<String> {
    static ATTR_RE: OnceLock<Regex> = OnceLock::new();
    let regex = ATTR_RE.get_or_init(|| {
        Regex::new(
            r#"(?is)\b([a-zA-Z0-9:_-]+)\s*=\s*"([^"]*)"|\b([a-zA-Z0-9:_-]+)\s*=\s*'([^']*)'"#,
        )
        .expect("attr regex")
    });

    for captures in regex.captures_iter(tag) {
        let (name, value) = if let (Some(name), Some(value)) = (captures.get(1), captures.get(2)) {
            (name.as_str(), value.as_str())
        } else if let (Some(name), Some(value)) = (captures.get(3), captures.get(4)) {
            (name.as_str(), value.as_str())
        } else {
            continue;
        };

        if !name.eq_ignore_ascii_case(attribute_name) {
            continue;
        }
        return Some(value.to_string());
    }

    None
}

fn decode_html_entities(raw: &str) -> String {
    raw.replace("&quot;", "\"")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&#39;", "'")
}

fn same_cookie_scope(base_url: &Url, request_url: &Url) -> bool {
    base_url.scheme() == request_url.scheme()
        && base_url.host_str() == request_url.host_str()
        && base_url.port_or_known_default() == request_url.port_or_known_default()
}

fn build_cookie_header(cookies: &CookieSnapshot) -> String {
    let mut pairs = Vec::new();
    push_cookie_pair(&mut pairs, "_t", cookies.t_token.as_deref());
    push_cookie_pair(
        &mut pairs,
        "_forum_session",
        cookies.forum_session.as_deref(),
    );
    push_cookie_pair(&mut pairs, "cf_clearance", cookies.cf_clearance.as_deref());
    pairs.join("; ")
}

fn push_cookie_pair(pairs: &mut Vec<String>, name: &str, value: Option<&str>) {
    let Some(value) = value.filter(|value| !value.is_empty()) else {
        return;
    };
    pairs.push(format!("{name}={value}"));
}

fn parse_set_cookie(value: &str) -> Option<(&str, &str)> {
    let first = value.split(';').next()?.trim();
    let (name, value) = first.split_once('=')?;
    let value = if value.is_empty() || value == "del" {
        ""
    } else {
        value
    };
    Some((name.trim(), value))
}

fn request_origin(base_url: &Url) -> String {
    let mut origin = base_url.clone();
    origin.set_path("");
    origin.set_query(None);
    origin.set_fragment(None);
    let value = origin.as_str().trim_end_matches('/');
    value.to_string()
}

fn request_referer(base_url: &Url) -> String {
    let mut referer = base_url.clone();
    referer.set_path("/");
    referer.set_query(None);
    referer.set_fragment(None);
    referer.to_string()
}

fn header_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn is_bad_csrf_body(body: &str) -> bool {
    body == r#"["BAD CSRF"]"#
}

fn sanitize_snapshot_for_restore(base_url: &str, mut snapshot: SessionSnapshot) -> SessionSnapshot {
    snapshot.bootstrap.base_url = base_url.to_string();

    normalize_option(&mut snapshot.cookies.t_token);
    normalize_option(&mut snapshot.cookies.forum_session);
    normalize_option(&mut snapshot.cookies.cf_clearance);
    normalize_option(&mut snapshot.cookies.csrf_token);

    normalize_option(&mut snapshot.bootstrap.discourse_base_uri);
    normalize_option(&mut snapshot.bootstrap.shared_session_key);
    normalize_option(&mut snapshot.bootstrap.current_username);
    normalize_option(&mut snapshot.bootstrap.long_polling_base_url);
    normalize_option(&mut snapshot.bootstrap.turnstile_sitekey);
    normalize_option(&mut snapshot.bootstrap.topic_tracking_state_meta);
    normalize_option(&mut snapshot.bootstrap.preloaded_json);

    if let Some(preloaded_json) = snapshot.bootstrap.preloaded_json.clone() {
        snapshot.bootstrap.has_preloaded_data = true;
        hydrate_preloaded_fields(&preloaded_json, &mut snapshot.bootstrap);
    } else {
        snapshot.bootstrap.has_preloaded_data = false;
    }

    if !snapshot.cookies.can_authenticate_requests() {
        snapshot.clear_login_state(true);
        snapshot.bootstrap.base_url = base_url.to_string();
    }

    snapshot
}

fn normalize_option(slot: &mut Option<String>) {
    if slot.as_ref().is_some_and(|value| value.is_empty()) {
        *slot = None;
    }
}

fn write_atomic(path: &Path, contents: &[u8]) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let temp_path = temp_path_for(path);
    fs::write(&temp_path, contents)?;

    if path.exists() {
        fs::remove_file(path)?;
    }

    fs::rename(temp_path, path)
}

fn temp_path_for(path: &Path) -> PathBuf {
    let millis = now_unix_ms();
    let pid = std::process::id();
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .map_or_else(|| "fire-session".to_string(), ToOwned::to_owned);
    path.with_file_name(format!("{file_name}.{pid}.{millis}.tmp"))
}

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_millis() as u64)
}

async fn expect_success(
    operation: &'static str,
    response: http::Response<ResponseBody>,
) -> Result<http::Response<ResponseBody>, FireCoreError> {
    if response.status().is_success() {
        return Ok(response);
    }

    let status = response.status().as_u16();
    let body = response
        .into_body()
        .text()
        .await
        .unwrap_or_else(|error| format!("<failed to read error body: {error}>"));
    Err(FireCoreError::HttpStatus {
        operation,
        status,
        body,
    })
}

#[cfg(test)]
mod tests {
    use std::{
        env, fs, io,
        net::SocketAddr,
        path::PathBuf,
        sync::{
            atomic::{AtomicUsize, Ordering},
            Arc,
        },
    };

    use super::FireCore;
    use crate::{FireCoreConfig, FireCoreError};
    use fire_models::{LoginPhase, LoginSyncInput, PlatformCookie};
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
        task::JoinHandle,
    };

    #[test]
    fn apply_home_html_extracts_bootstrap_and_readiness() {
        let core = FireCore::new(FireCoreConfig::default()).expect("core");
        let snapshot = core.apply_home_html(sample_home_html());

        assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
        assert_eq!(
            snapshot.bootstrap.shared_session_key.as_deref(),
            Some("shared-session")
        );
        assert_eq!(
            snapshot.bootstrap.current_username.as_deref(),
            Some("alice")
        );
        assert_eq!(
            snapshot.bootstrap.long_polling_base_url.as_deref(),
            Some("https://linux.do")
        );
        assert_eq!(
            snapshot.bootstrap.turnstile_sitekey.as_deref(),
            Some("turnstile-key")
        );
        assert!(snapshot.bootstrap.has_preloaded_data);
    }

    #[test]
    fn sync_login_context_merges_platform_cookies_and_html() {
        let core = FireCore::new(FireCoreConfig::default()).expect("core");
        let snapshot = core.sync_login_context(LoginSyncInput {
            username: Some("alice".into()),
            home_html: Some(sample_home_html()),
            csrf_token: None,
            current_url: Some("https://linux.do/".into()),
            cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "token".into(),
                    domain: None,
                    path: None,
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "forum".into(),
                    domain: None,
                    path: None,
                },
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "clearance".into(),
                    domain: None,
                    path: None,
                },
            ],
        });

        assert_eq!(snapshot.login_phase(), LoginPhase::Ready);
        assert!(snapshot.readiness().can_write_authenticated_api);
        assert!(snapshot.readiness().can_open_message_bus);
    }

    #[test]
    fn session_can_roundtrip_through_json_export_and_restore() {
        let core = FireCore::new(FireCoreConfig::default()).expect("core");
        let expected = core.sync_login_context(LoginSyncInput {
            username: Some("alice".into()),
            home_html: Some(sample_home_html()),
            csrf_token: None,
            current_url: Some("https://linux.do/".into()),
            cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "token".into(),
                    domain: None,
                    path: None,
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "forum".into(),
                    domain: None,
                    path: None,
                },
            ],
        });

        let json = core.export_session_json().expect("export");
        let restored_core = FireCore::new(FireCoreConfig::default()).expect("core");
        let restored = restored_core.restore_session_json(json).expect("restore");

        assert_eq!(restored, expected);
    }

    #[test]
    fn restore_drops_incomplete_login_state_but_keeps_cf_clearance() {
        let core = FireCore::new(FireCoreConfig::default()).expect("core");
        let json = r#"
{
  "version": 1,
  "saved_at_unix_ms": 1,
  "snapshot": {
    "cookies": {
      "t_token": "token",
      "forum_session": "",
      "cf_clearance": "clearance",
      "csrf_token": "csrf"
    },
    "bootstrap": {
      "base_url": "https://linux.do/",
      "discourse_base_uri": "/",
      "shared_session_key": "shared",
      "current_username": "alice",
      "long_polling_base_url": "https://linux.do",
      "turnstile_sitekey": "sitekey",
      "topic_tracking_state_meta": "{\"message_bus_last_id\":42}",
      "preloaded_json": "{\"currentUser\":{\"username\":\"alice\"}}",
      "has_preloaded_data": true
    }
  }
}
"#;

        let restored = core
            .restore_session_json(json.to_string())
            .expect("restore");

        assert_eq!(restored.cookies.cf_clearance.as_deref(), Some("clearance"));
        assert_eq!(restored.cookies.t_token, None);
        assert_eq!(restored.cookies.csrf_token, None);
        assert_eq!(restored.bootstrap.current_username, None);
        assert!(!restored.bootstrap.has_preloaded_data);
    }

    #[test]
    fn session_can_roundtrip_through_file_persistence() {
        let core = FireCore::new(FireCoreConfig::default()).expect("core");
        let expected = core.sync_login_context(LoginSyncInput {
            username: Some("alice".into()),
            home_html: Some(sample_home_html()),
            csrf_token: Some("csrf-token".into()),
            current_url: Some("https://linux.do/".into()),
            cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "token".into(),
                    domain: None,
                    path: None,
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "forum".into(),
                    domain: None,
                    path: None,
                },
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "clearance".into(),
                    domain: None,
                    path: None,
                },
            ],
        });

        let path = temp_session_file("session-roundtrip.json");
        core.save_session_to_path(&path).expect("save");

        let restored_core = FireCore::new(FireCoreConfig::default()).expect("core");
        let restored = restored_core.load_session_from_path(&path).expect("load");
        restored_core.clear_session_path(&path).expect("clear");

        assert_eq!(restored, expected);
        assert!(!path.exists());
    }

    #[test]
    fn restore_rejects_base_url_mismatch() {
        let core = FireCore::new(FireCoreConfig::default()).expect("core");
        let json = r#"
{
  "version": 1,
  "saved_at_unix_ms": 1,
  "snapshot": {
    "cookies": {
      "t_token": "token",
      "forum_session": "forum",
      "cf_clearance": null,
      "csrf_token": null
    },
    "bootstrap": {
      "base_url": "https://example.com/",
      "discourse_base_uri": null,
      "shared_session_key": null,
      "current_username": null,
      "long_polling_base_url": null,
      "turnstile_sitekey": null,
      "topic_tracking_state_meta": null,
      "preloaded_json": null,
      "has_preloaded_data": false
    }
  }
}
"#;

        match core.restore_session_json(json.to_string()) {
            Err(FireCoreError::PersistBaseUrlMismatch { .. }) => {}
            other => panic!("unexpected restore result: {other:?}"),
        }
    }

    #[tokio::test]
    async fn refresh_csrf_token_updates_session_from_network() {
        let responses = vec![raw_json_response(
            200,
            "application/json",
            r#"{"csrf":"fresh-csrf"}"#,
        )];
        let server = TestServer::spawn(responses).await.expect("server");
        let core = FireCore::new(FireCoreConfig {
            base_url: server.base_url(),
        })
        .expect("core");

        let snapshot = core.refresh_csrf_token().await.expect("csrf refresh");
        server.shutdown().await;

        assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("fresh-csrf"));
    }

    #[tokio::test]
    async fn logout_remote_retries_after_bad_csrf() {
        let responses = vec![
            raw_text_response(403, r#"["BAD CSRF"]"#),
            raw_json_response(200, "application/json", r#"{"csrf":"retry-csrf"}"#),
            raw_text_response(200, "{}"),
        ];
        let server = TestServer::spawn(responses).await.expect("server");
        let core = FireCore::new(FireCoreConfig {
            base_url: server.base_url(),
        })
        .expect("core");

        let _ = core.sync_login_context(LoginSyncInput {
            username: Some("alice".into()),
            home_html: Some(sample_home_html()),
            csrf_token: Some("stale-csrf".into()),
            current_url: Some(server.base_url()),
            cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "token".into(),
                    domain: None,
                    path: None,
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "forum".into(),
                    domain: None,
                    path: None,
                },
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "clearance".into(),
                    domain: None,
                    path: None,
                },
            ],
        });

        let snapshot = core.logout_remote(true).await.expect("logout");
        let requests = server.shutdown().await;

        assert!(!snapshot.cookies.has_login_session());
        assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
        assert_eq!(requests.load(Ordering::SeqCst), 3);
    }

    fn sample_home_html() -> String {
        r#"
<!doctype html>
<html>
  <head>
    <meta name="csrf-token" content="csrf-token">
    <meta name="shared_session_key" content="shared-session">
    <meta name="current-username" content="alice">
    <meta name="discourse-base-uri" content="/">
  </head>
  <body>
    <div data-sitekey="turnstile-key"></div>
    <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;username&quot;:&quot;alice&quot;},&quot;siteSettings&quot;:{&quot;long_polling_base_url&quot;:&quot;https://linux.do&quot;},&quot;topicTrackingStateMeta&quot;:{&quot;message_bus_last_id&quot;:42}}"></div>
  </body>
</html>
"#
        .to_string()
    }

    fn raw_json_response(status: u16, content_type: &str, body: &str) -> String {
        format!(
            "HTTP/1.1 {status} TEST\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        )
    }

    fn raw_text_response(status: u16, body: &str) -> String {
        raw_json_response(status, "application/json", body)
    }

    struct TestServer {
        addr: SocketAddr,
        requests: Arc<AtomicUsize>,
        handle: JoinHandle<()>,
    }

    impl TestServer {
        async fn spawn(responses: Vec<String>) -> io::Result<Self> {
            let listener = TcpListener::bind("127.0.0.1:0").await?;
            let addr = listener.local_addr()?;
            let requests = Arc::new(AtomicUsize::new(0));
            let requests_handle = requests.clone();
            let responses = Arc::new(responses);
            let handle = tokio::spawn(async move {
                for response in responses.iter() {
                    let Ok((mut stream, _)) = listener.accept().await else {
                        return;
                    };
                    let mut buffer = vec![0_u8; 4096];
                    let _ = stream.read(&mut buffer).await;
                    requests_handle.fetch_add(1, Ordering::SeqCst);
                    let _ = stream.write_all(response.as_bytes()).await;
                    let _ = stream.shutdown().await;
                }
            });

            Ok(Self {
                addr,
                requests,
                handle,
            })
        }

        fn base_url(&self) -> String {
            format!("http://{}", self.addr)
        }

        async fn shutdown(self) -> Arc<AtomicUsize> {
            let _ = self.handle.await;
            self.requests
        }
    }

    #[tokio::test]
    async fn refresh_bootstrap_fetches_home_html() -> Result<(), FireCoreError> {
        let responses = vec![raw_text_response(200, &sample_home_html())];
        let server = TestServer::spawn(responses).await.expect("server");
        let core = FireCore::new(FireCoreConfig {
            base_url: server.base_url(),
        })?;

        let snapshot = core.refresh_bootstrap().await?;
        let _ = server.shutdown().await;

        assert_eq!(
            snapshot.bootstrap.current_username.as_deref(),
            Some("alice")
        );
        assert!(snapshot.bootstrap.has_preloaded_data);
        Ok(())
    }

    fn temp_session_file(name: &str) -> PathBuf {
        let mut path = env::temp_dir();
        path.push(format!("fire-tests-{}", std::process::id()));
        fs::create_dir_all(&path).expect("temp dir");
        path.push(name);
        path
    }
}
