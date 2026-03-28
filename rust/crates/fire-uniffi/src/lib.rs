use std::sync::{Arc, OnceLock};

use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{
    BootstrapArtifacts, CookieSnapshot, LoginPhase, LoginSyncInput, PlatformCookie,
    SessionReadiness, SessionSnapshot,
};
use tokio::runtime::{Builder, Runtime};

uniffi::setup_scaffolding!("fire_uniffi");

#[derive(uniffi::Record, Debug, Clone)]
pub struct PlatformCookieState {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
}

impl From<PlatformCookie> for PlatformCookieState {
    fn from(value: PlatformCookie) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
        }
    }
}

impl From<PlatformCookieState> for PlatformCookie {
    fn from(value: PlatformCookieState) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookieState {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
    pub cf_clearance: Option<String>,
    pub csrf_token: Option<String>,
}

impl From<CookieSnapshot> for CookieState {
    fn from(value: CookieSnapshot) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
            cf_clearance: value.cf_clearance,
            csrf_token: value.csrf_token,
        }
    }
}

impl From<CookieState> for CookieSnapshot {
    fn from(value: CookieState) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
            cf_clearance: value.cf_clearance,
            csrf_token: value.csrf_token,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BootstrapState {
    pub base_url: String,
    pub discourse_base_uri: Option<String>,
    pub shared_session_key: Option<String>,
    pub current_username: Option<String>,
    pub long_polling_base_url: Option<String>,
    pub turnstile_sitekey: Option<String>,
    pub topic_tracking_state_meta: Option<String>,
    pub preloaded_json: Option<String>,
    pub has_preloaded_data: bool,
}

impl From<BootstrapArtifacts> for BootstrapState {
    fn from(value: BootstrapArtifacts) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
        }
    }
}

impl From<BootstrapState> for BootstrapArtifacts {
    fn from(value: BootstrapState) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LoginSyncState {
    pub current_url: Option<String>,
    pub username: Option<String>,
    pub csrf_token: Option<String>,
    pub home_html: Option<String>,
    pub cookies: Vec<PlatformCookieState>,
}

impl From<LoginSyncInput> for LoginSyncState {
    fn from(value: LoginSyncInput) -> Self {
        Self {
            current_url: value.current_url,
            username: value.username,
            csrf_token: value.csrf_token,
            home_html: value.home_html,
            cookies: value.cookies.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<LoginSyncState> for LoginSyncInput {
    fn from(value: LoginSyncState) -> Self {
        Self {
            current_url: value.current_url,
            username: value.username,
            csrf_token: value.csrf_token,
            home_html: value.home_html,
            cookies: value.cookies.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum LoginPhaseState {
    Anonymous,
    CookiesCaptured,
    BootstrapCaptured,
    Ready,
}

impl From<LoginPhase> for LoginPhaseState {
    fn from(value: LoginPhase) -> Self {
        match value {
            LoginPhase::Anonymous => Self::Anonymous,
            LoginPhase::CookiesCaptured => Self::CookiesCaptured,
            LoginPhase::BootstrapCaptured => Self::BootstrapCaptured,
            LoginPhase::Ready => Self::Ready,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SessionReadinessState {
    pub has_login_cookie: bool,
    pub has_forum_session: bool,
    pub has_cloudflare_clearance: bool,
    pub has_csrf_token: bool,
    pub has_current_user: bool,
    pub has_preloaded_data: bool,
    pub has_shared_session_key: bool,
    pub can_read_authenticated_api: bool,
    pub can_write_authenticated_api: bool,
    pub can_open_message_bus: bool,
}

impl From<SessionReadiness> for SessionReadinessState {
    fn from(value: SessionReadiness) -> Self {
        Self {
            has_login_cookie: value.has_login_cookie,
            has_forum_session: value.has_forum_session,
            has_cloudflare_clearance: value.has_cloudflare_clearance,
            has_csrf_token: value.has_csrf_token,
            has_current_user: value.has_current_user,
            has_preloaded_data: value.has_preloaded_data,
            has_shared_session_key: value.has_shared_session_key,
            can_read_authenticated_api: value.can_read_authenticated_api,
            can_write_authenticated_api: value.can_write_authenticated_api,
            can_open_message_bus: value.can_open_message_bus,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SessionState {
    pub cookies: CookieState,
    pub bootstrap: BootstrapState,
    pub readiness: SessionReadinessState,
    pub login_phase: LoginPhaseState,
    pub has_login_session: bool,
}

impl SessionState {
    fn from_snapshot(snapshot: SessionSnapshot) -> Self {
        let readiness = snapshot.readiness();
        let login_phase = snapshot.login_phase();
        Self {
            has_login_session: snapshot.cookies.has_login_session(),
            cookies: snapshot.cookies.into(),
            bootstrap: snapshot.bootstrap.into(),
            readiness: readiness.into(),
            login_phase: login_phase.into(),
        }
    }
}

#[derive(uniffi::Error, thiserror::Error, Debug)]
pub enum FireUniFfiError {
    #[error("{details}")]
    Message { details: String },
}

impl From<FireCoreError> for FireUniFfiError {
    fn from(value: FireCoreError) -> Self {
        Self::Message {
            details: value.to_string(),
        }
    }
}

#[derive(uniffi::Object)]
pub struct FireCoreHandle {
    inner: Arc<FireCore>,
}

#[uniffi::export]
impl FireCoreHandle {
    #[uniffi::constructor]
    pub fn new(base_url: Option<String>) -> Result<Self, FireUniFfiError> {
        let inner = FireCore::new(FireCoreConfig {
            base_url: base_url.unwrap_or_else(|| "https://linux.do".to_string()),
        })?;
        Ok(Self {
            inner: Arc::new(inner),
        })
    }

    pub fn base_url(&self) -> String {
        self.inner.base_url().to_string()
    }

    pub fn has_login_session(&self) -> bool {
        self.inner.has_login_session()
    }

    pub fn snapshot(&self) -> SessionState {
        SessionState::from_snapshot(self.inner.snapshot())
    }

    pub fn export_session_json(&self) -> Result<String, FireUniFfiError> {
        self.inner.export_session_json().map_err(Into::into)
    }

    pub fn restore_session_json(&self, json: String) -> Result<SessionState, FireUniFfiError> {
        let snapshot = self.inner.restore_session_json(json)?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub fn save_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.inner.save_session_to_path(path).map_err(Into::into)
    }

    pub fn load_session_from_path(&self, path: String) -> Result<SessionState, FireUniFfiError> {
        let snapshot = self.inner.load_session_from_path(path)?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub fn clear_session_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.inner.clear_session_path(path).map_err(Into::into)
    }

    pub fn apply_cookies(&self, cookies: CookieState) -> SessionState {
        SessionState::from_snapshot(self.inner.apply_cookies(cookies.into()))
    }

    pub fn apply_bootstrap(&self, bootstrap: BootstrapState) -> SessionState {
        SessionState::from_snapshot(self.inner.apply_bootstrap(bootstrap.into()))
    }

    pub fn apply_csrf_token(&self, csrf_token: String) -> SessionState {
        SessionState::from_snapshot(self.inner.apply_csrf_token(csrf_token))
    }

    pub fn clear_csrf_token(&self) -> SessionState {
        SessionState::from_snapshot(self.inner.clear_csrf_token())
    }

    pub fn apply_home_html(&self, html: String) -> SessionState {
        SessionState::from_snapshot(self.inner.apply_home_html(html))
    }

    pub fn sync_login_context(&self, context: LoginSyncState) -> SessionState {
        SessionState::from_snapshot(self.inner.sync_login_context(context.into()))
    }

    pub fn logout_local(&self, preserve_cf_clearance: bool) -> SessionState {
        SessionState::from_snapshot(self.inner.logout_local(preserve_cf_clearance))
    }

    pub fn refresh_bootstrap(&self) -> Result<SessionState, FireUniFfiError> {
        let snapshot = ffi_runtime().block_on(self.inner.refresh_bootstrap())?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub fn refresh_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        let snapshot = ffi_runtime().block_on(self.inner.refresh_csrf_token())?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        let snapshot = ffi_runtime().block_on(self.inner.logout_remote(preserve_cf_clearance))?;
        Ok(SessionState::from_snapshot(snapshot))
    }
}

fn ffi_runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("failed to create ffi runtime")
    })
}
