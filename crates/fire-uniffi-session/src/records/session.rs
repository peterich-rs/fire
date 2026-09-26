use fire_core::{
    FireAuthRecoveryHint, FireAuthRecoveryHintReason,
    FireSessionPersistenceState as CoreSessionPersistenceState,
};
use fire_models::{SessionReadiness, SessionRecovery, SessionSnapshot};

use super::auth_signal::AuthRuntimeSignalState;
use super::bootstrap::BootstrapState;
use super::cookie::CookieState;
use super::login::LoginPhaseState;

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum AuthRecoveryHintReasonState {
    TOnlyRotation,
    ForumSessionOnlyRotation,
}

impl From<FireAuthRecoveryHintReason> for AuthRecoveryHintReasonState {
    fn from(value: FireAuthRecoveryHintReason) -> Self {
        match value {
            FireAuthRecoveryHintReason::TOnlyRotation => Self::TOnlyRotation,
            FireAuthRecoveryHintReason::ForumSessionOnlyRotation => Self::ForumSessionOnlyRotation,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct AuthRecoveryHintState {
    pub observed_epoch: u64,
    pub reason: AuthRecoveryHintReasonState,
}

impl From<FireAuthRecoveryHint> for AuthRecoveryHintState {
    fn from(value: FireAuthRecoveryHint) -> Self {
        Self {
            observed_epoch: value.observed_epoch,
            reason: value.reason.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SessionPersistenceState {
    pub snapshot_revision: u64,
    pub auth_cookie_revision: u64,
}

impl From<CoreSessionPersistenceState> for SessionPersistenceState {
    fn from(value: CoreSessionPersistenceState) -> Self {
        Self {
            snapshot_revision: value.snapshot_revision,
            auth_cookie_revision: value.auth_cookie_revision,
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

#[derive(uniffi::Enum, Debug, Clone, Copy, Default)]
pub enum SessionRecoveryState {
    #[default]
    Idle,
    Cloudflare,
}

impl From<SessionRecovery> for SessionRecoveryState {
    fn from(value: SessionRecovery) -> Self {
        match value {
            SessionRecovery::Idle => Self::Idle,
            SessionRecovery::Cloudflare => Self::Cloudflare,
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
    pub browser_user_agent: Option<String>,
    pub profile_display_name: String,
    pub login_phase_label: String,
    pub read_path_login_request: Option<ReadPathLoginRequestState>,
    pub last_auth_runtime_signal: Option<AuthRuntimeSignalState>,
    pub recovery: SessionRecoveryState,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ReadPathLoginRequestState {
    pub generation: u64,
    pub operation: String,
}

impl SessionState {
    pub fn from_snapshot(snapshot: SessionSnapshot) -> Self {
        let readiness = snapshot.readiness();
        let login_phase = snapshot.login_phase();
        let profile_display_name = snapshot.profile_display_name();
        let login_phase_label = snapshot.login_phase_label();
        Self {
            has_login_session: snapshot.cookies.has_login_session(),
            profile_display_name,
            login_phase_label,
            cookies: snapshot.cookies.into(),
            bootstrap: snapshot.bootstrap.into(),
            readiness: readiness.into(),
            login_phase: login_phase.into(),
            browser_user_agent: snapshot.browser_user_agent,
            read_path_login_request: snapshot.read_path_login_request.map(|request| {
                ReadPathLoginRequestState {
                    generation: request.generation,
                    operation: request.operation,
                }
            }),
            last_auth_runtime_signal: snapshot.last_auth_runtime_signal.map(Into::into),
            recovery: snapshot.recovery.into(),
        }
    }
}
