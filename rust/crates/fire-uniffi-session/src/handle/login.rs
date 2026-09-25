use fire_uniffi_types::{run_infallible, run_on_ffi_runtime, FireUniFfiError};

use crate::records::*;
use crate::FireSessionHandle;

#[uniffi::export]
impl FireSessionHandle {
    pub fn has_login_session(&self) -> Result<bool, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "has_login_session",
            |inner| inner.has_login_session(),
        )
    }
    pub fn complete_read_path_login(
        &self,
        generation: u64,
        succeeded: bool,
    ) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "complete_read_path_login",
            move |inner| inner.complete_read_path_login(generation, succeeded),
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
    pub fn classify_webview_login_result(
        &self,
        result: WebViewLoginJsResultState,
    ) -> Result<WebViewLoginDecisionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "classify_webview_login_result",
            move |inner| inner.classify_webview_login_result(result.into()).into(),
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
    pub fn finalize_login_from_webview(
        &self,
        username: String,
        csrf_token: Option<String>,
        raw_preloaded_html: Option<String>,
        browser_user_agent: Option<String>,
        cookies: Vec<PlatformCookieState>,
        allow_low_confidence_session_cookies: bool,
    ) -> Result<LoginFinalizationResultState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "finalize_login_from_webview",
            move |inner| {
                inner
                    .finalize_login_from_webview(
                        username,
                        csrf_token,
                        raw_preloaded_html,
                        browser_user_agent,
                        cookies.into_iter().map(Into::into).collect(),
                        allow_low_confidence_session_cookies,
                    )
                    .into()
            },
        )
    }
    /// Post-cookie login handoff: bootstrap with timeout, never block home entry
    /// when auth cookies are already present.
    pub async fn finalize_login_ready(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("finalize_login_ready", panic_state, async move {
            inner.finalize_login_ready().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }
    pub async fn probe_session(&self) -> Result<String, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime("probe_session", panic_state, async move {
            inner.probe_session().await
        })
        .await?;
        Ok(format_probe_result(result))
    }
    pub fn determine_login_state(&self) -> Result<LoginStateDeterminationState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "determine_login_state",
            |inner| inner.determine_login_state().into(),
        )
    }
    pub async fn determine_login_state_with_probe(
        &self,
    ) -> Result<LoginStateDeterminationState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime(
            "determine_login_state_with_probe",
            panic_state,
            async move {
                Ok::<_, fire_core::FireCoreError>(inner.determine_login_state_with_probe().await)
            },
        )
        .await?;
        Ok(result.into())
    }
}
