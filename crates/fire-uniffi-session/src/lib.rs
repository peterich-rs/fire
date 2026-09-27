uniffi::setup_scaffolding!("fire_uniffi_session");

use std::sync::Arc;

use fire_uniffi_types::{run_fallible, run_infallible, FireUniFfiError, SharedFireCore};

pub mod handle;
pub mod records;

pub use records::{
    format_probe_result, AppStateRefreshEventState, AppStateRefreshHandler, AuthRecoveryHintState,
    AuthRuntimeSignalKindState, AuthRuntimeSignalSourceState, AuthRuntimeSignalState,
    AuthRuntimeSignalStrengthState, BootstrapState, BrowserHttpError, BrowserHttpHandler,
    BrowserHttpRequestState, BrowserHttpResponseState, BrowserTransportPrefState,
    CanonicalCookieState, CloudflareChallengeHandler, CloudflareChallengeRequestState,
    CloudflareChallengeResultState, CloudflareClearanceResolvedEventState,
    CloudflareClearanceResolvedHandler, CloudflarePolicyState, CookieReplayEntryState,
    CookieSameSiteState, CookieSelfHealingHandler, CookieSelfHealingPhaseState,
    CookieSelfHealingRequestState, CookieSelfHealingResultState, CookieSourceState, CookieState,
    CookieSweepIntentState, CookieSweepPlanState, CurrentUserSnapshotState, DohPresetState,
    DohProbeResultState, DohSettingsState, HomeTopicListScopeState, LoginFailureKindState,
    LoginFailureState, LoginFinalizationResultState, LoginPhaseState, LoginStateDeterminationState,
    LoginSyncState, NuclearResetPlanState, PassiveLogoutTriggerState, PlatformCookieState,
    PreloadedDataStateState, QrLoginPayloadState, ReadPathLoginRequestState, RefreshBatchState,
    RefreshTriggerState, SecondFactorRequirementState, SessionCandidateCookiesState,
    SessionCandidateHandler, SessionPersistenceState, SessionReadinessState, SessionRecoveryState,
    SessionState, TopicCategoryState, UserApiKeyAuthRedirectResultState,
    UserApiKeyAuthorizeUrlState, UserApiKeyCryptoHandler, WebViewCookieActionState,
    WebViewCookieInfoState, WebViewLoginDecisionState, WebViewLoginJsResultState,
    WebViewLoginPhaseState,
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
    pub fn resolve_workspace_path(&self, relative_path: String) -> Result<String, FireUniFfiError> {
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
    pub fn snapshot(&self) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "snapshot",
            |inner| SessionState::from_snapshot(inner.snapshot()),
        )
    }
    pub fn session_epoch(&self) -> Result<u64, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "session_epoch",
            |inner| inner.session_epoch(),
        )
    }
    pub fn session_persistence_state(&self) -> Result<SessionPersistenceState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "session_persistence_state",
            |inner| inner.session_persistence_state().into(),
        )
    }
    pub fn auth_recovery_hint(&self) -> Result<Option<AuthRecoveryHintState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "auth_recovery_hint",
            |inner| inner.auth_recovery_hint().map(Into::into),
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
}
