use std::sync::Arc;

use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{BootstrapArtifacts, CookieSnapshot};

uniffi::setup_scaffolding!("fire_uniffi");

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
    pub shared_session_key: Option<String>,
    pub current_username: Option<String>,
    pub long_polling_base_url: Option<String>,
    pub has_preloaded_data: bool,
}

impl From<BootstrapArtifacts> for BootstrapState {
    fn from(value: BootstrapArtifacts) -> Self {
        Self {
            base_url: value.base_url,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            long_polling_base_url: value.long_polling_base_url,
            has_preloaded_data: value.has_preloaded_data,
        }
    }
}

impl From<BootstrapState> for BootstrapArtifacts {
    fn from(value: BootstrapState) -> Self {
        Self {
            base_url: value.base_url,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            long_polling_base_url: value.long_polling_base_url,
            has_preloaded_data: value.has_preloaded_data,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SessionState {
    pub cookies: CookieState,
    pub bootstrap: BootstrapState,
    pub has_login_session: bool,
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
        let snapshot = self.inner.snapshot();
        SessionState {
            has_login_session: snapshot.cookies.has_login_session(),
            cookies: snapshot.cookies.into(),
            bootstrap: snapshot.bootstrap.into(),
        }
    }

    pub fn apply_cookies(&self, cookies: CookieState) -> SessionState {
        let snapshot = self.inner.apply_cookies(cookies.into());
        SessionState {
            has_login_session: snapshot.cookies.has_login_session(),
            cookies: snapshot.cookies.into(),
            bootstrap: snapshot.bootstrap.into(),
        }
    }

    pub fn apply_bootstrap(&self, bootstrap: BootstrapState) -> SessionState {
        let snapshot = self.inner.apply_bootstrap(bootstrap.into());
        SessionState {
            has_login_session: snapshot.cookies.has_login_session(),
            cookies: snapshot.cookies.into(),
            bootstrap: snapshot.bootstrap.into(),
        }
    }
}
