uniffi::setup_scaffolding!("fire_uniffi_session");

use std::sync::Arc;

use fire_uniffi_types::{
    run_fallible, run_infallible, run_on_ffi_runtime, FireUniFfiError, SharedFireCore,
};

pub mod records;

pub use records::{
    BootstrapState, CookieState, LoginPhaseState, LoginSyncState, PlatformCookieState,
    SessionReadinessState, SessionState, TopicCategoryState,
};

#[derive(uniffi::Object)]
pub struct FireSessionHandle {
    shared: Arc<SharedFireCore>,
}

impl FireSessionHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireSessionHandle {
    pub fn base_url(&self) -> Result<String, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "base_url",
            |inner| inner.base_url().to_string(),
        )
    }

    pub fn workspace_path(&self) -> Result<Option<String>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "workspace_path",
            |inner| {
                inner
                    .workspace_path()
                    .map(|path| path.display().to_string())
            },
        )
    }

    pub fn resolve_workspace_path(
        &self,
        relative_path: String,
    ) -> Result<String, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "resolve_workspace_path",
            move |inner| {
                inner
                    .resolve_workspace_path(relative_path)
                    .map(|path| path.display().to_string())
            },
        )
    }

    pub fn has_login_session(&self) -> Result<bool, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "has_login_session",
            |inner| inner.has_login_session(),
        )
    }

    pub fn snapshot(&self) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "snapshot",
            |inner| SessionState::from_snapshot(inner.snapshot()),
        )
    }

    pub fn export_session_json(&self) -> Result<String, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "export_session_json",
            |inner| inner.export_session_json(),
        )
    }

    pub fn export_redacted_session_json(&self) -> Result<String, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "export_redacted_session_json",
            |inner| inner.export_redacted_session_json(),
        )
    }

    pub fn restore_session_json(&self, json: String) -> Result<SessionState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "restore_session_json",
            move |inner| {
                inner
                    .restore_session_json(json)
                    .map(SessionState::from_snapshot)
            },
        )
    }

    pub fn save_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "save_session_to_path",
            move |inner| inner.save_session_to_path(path),
        )
    }

    pub fn save_redacted_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "save_redacted_session_to_path",
            move |inner| inner.save_redacted_session_to_path(path),
        )
    }

    pub fn load_session_from_path(&self, path: String) -> Result<SessionState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "load_session_from_path",
            move |inner| {
                inner
                    .load_session_from_path(path)
                    .map(SessionState::from_snapshot)
            },
        )
    }

    pub fn clear_session_path(&self, path: String) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "clear_session_path",
            move |inner| inner.clear_session_path(path),
        )
    }

    pub fn apply_cookies(&self, cookies: CookieState) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_cookies",
            move |inner| SessionState::from_snapshot(inner.apply_cookies(cookies.into())),
        )
    }

    pub fn merge_platform_cookies(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "merge_platform_cookies",
            move |inner| {
                SessionState::from_snapshot(
                    inner.merge_platform_cookies(cookies.into_iter().map(Into::into).collect()),
                )
            },
        )
    }

    pub fn apply_platform_cookies(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_platform_cookies",
            move |inner| {
                SessionState::from_snapshot(
                    inner.apply_platform_cookies(cookies.into_iter().map(Into::into).collect()),
                )
            },
        )
    }

    pub fn apply_bootstrap(
        &self,
        bootstrap: BootstrapState,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_bootstrap",
            move |inner| SessionState::from_snapshot(inner.apply_bootstrap(bootstrap.into())),
        )
    }

    pub fn apply_csrf_token(&self, csrf_token: String) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_csrf_token",
            move |inner| SessionState::from_snapshot(inner.apply_csrf_token(csrf_token)),
        )
    }

    pub fn clear_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "clear_csrf_token",
            |inner| SessionState::from_snapshot(inner.clear_csrf_token()),
        )
    }

    pub fn apply_home_html(&self, html: String) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_home_html",
            move |inner| SessionState::from_snapshot(inner.apply_home_html(html)),
        )
    }

    pub fn sync_login_context(
        &self,
        context: LoginSyncState,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "sync_login_context",
            move |inner| SessionState::from_snapshot(inner.sync_login_context(context.into())),
        )
    }

    pub fn logout_local(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "logout_local",
            move |inner| SessionState::from_snapshot(inner.logout_local(preserve_cf_clearance)),
        )
    }

    pub async fn refresh_bootstrap(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("refresh_bootstrap", panic_state, async move {
            inner.refresh_bootstrap().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_bootstrap_if_needed(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("refresh_bootstrap_if_needed", panic_state, async move {
            inner.refresh_bootstrap_if_needed().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("refresh_csrf_token", panic_state, async move {
            inner.refresh_csrf_token().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_csrf_token_if_needed(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot =
            run_on_ffi_runtime("refresh_csrf_token_if_needed", panic_state, async move {
                inner.refresh_csrf_token_if_needed().await
            })
            .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("logout_remote", panic_state, async move {
            inner.logout_remote(preserve_cf_clearance).await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }
}
