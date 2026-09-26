use fire_models::{
    CloudflareChallengeRequest, CloudflareChallengeResult, CookieSelfHealingPhase,
    CookieSelfHealingRequest, CookieSelfHealingResult,
};

use super::cookie::PlatformCookieState;

#[derive(uniffi::Record, Debug, Clone)]
pub struct CloudflareChallengeRequestState {
    pub operation: String,
    pub request_url: String,
    pub origin_url: Option<String>,
    pub is_foreground: bool,
    pub session_epoch: u64,
}

impl From<CloudflareChallengeRequest> for CloudflareChallengeRequestState {
    fn from(value: CloudflareChallengeRequest) -> Self {
        Self {
            operation: value.operation,
            request_url: value.request_url,
            origin_url: value.origin_url,
            is_foreground: value.is_foreground,
            session_epoch: value.session_epoch,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CloudflareChallengeResultState {
    pub completed: bool,
    pub user_cancelled: bool,
    pub fresh_cf_clearance: Option<String>,
    pub cookies: Vec<PlatformCookieState>,
    pub browser_user_agent: Option<String>,
}

impl From<CloudflareChallengeResultState> for CloudflareChallengeResult {
    fn from(value: CloudflareChallengeResultState) -> Self {
        Self {
            completed: value.completed,
            user_cancelled: value.user_cancelled,
            fresh_cf_clearance: value.fresh_cf_clearance,
            cookies: value.cookies.into_iter().map(Into::into).collect(),
            browser_user_agent: value.browser_user_agent,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum CookieSelfHealingPhaseState {
    Sweep,
    NuclearReset,
}

impl From<CookieSelfHealingPhase> for CookieSelfHealingPhaseState {
    fn from(value: CookieSelfHealingPhase) -> Self {
        match value {
            CookieSelfHealingPhase::Sweep => Self::Sweep,
            CookieSelfHealingPhase::NuclearReset => Self::NuclearReset,
        }
    }
}

impl From<CookieSelfHealingPhaseState> for CookieSelfHealingPhase {
    fn from(value: CookieSelfHealingPhaseState) -> Self {
        match value {
            CookieSelfHealingPhaseState::Sweep => Self::Sweep,
            CookieSelfHealingPhaseState::NuclearReset => Self::NuclearReset,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookieSelfHealingRequestState {
    pub operation: String,
    pub request_url: String,
    pub target_url: String,
    pub phase: CookieSelfHealingPhaseState,
    pub attempt: u8,
    pub cookie_names: Vec<String>,
    pub session_epoch: u64,
}

impl From<CookieSelfHealingRequest> for CookieSelfHealingRequestState {
    fn from(value: CookieSelfHealingRequest) -> Self {
        Self {
            operation: value.operation,
            request_url: value.request_url,
            target_url: value.target_url,
            phase: value.phase.into(),
            attempt: value.attempt,
            cookie_names: value.cookie_names,
            session_epoch: value.session_epoch,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookieSelfHealingResultState {
    pub completed: bool,
    pub session_epoch: u64,
}

impl From<CookieSelfHealingResultState> for CookieSelfHealingResult {
    fn from(value: CookieSelfHealingResultState) -> Self {
        Self {
            completed: value.completed,
            session_epoch: value.session_epoch,
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait CookieSelfHealingHandler: Send + Sync {
    fn heal_cookies(&self, request: CookieSelfHealingRequestState) -> CookieSelfHealingResultState;
}

#[derive(uniffi::Record, Debug, Clone, Default)]
pub struct SessionCandidateCookiesState {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
}

impl From<SessionCandidateCookiesState> for fire_core::SessionCandidateCookies {
    fn from(value: SessionCandidateCookiesState) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait SessionCandidateHandler: Send + Sync {
    fn session_candidate_cookies(&self) -> SessionCandidateCookiesState;
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserApiKeyAuthorizeUrlState {
    pub url: String,
    pub nonce: String,
}

impl From<fire_core::UserApiKeyAuthorizeUrl> for UserApiKeyAuthorizeUrlState {
    fn from(value: fire_core::UserApiKeyAuthorizeUrl) -> Self {
        Self {
            url: value.url,
            nonce: value.nonce,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserApiKeyAuthRedirectResultState {
    pub ok: bool,
    pub stale: bool,
    pub username: Option<String>,
}

impl From<fire_core::UserApiKeyAuthRedirectResult> for UserApiKeyAuthRedirectResultState {
    fn from(value: fire_core::UserApiKeyAuthRedirectResult) -> Self {
        Self {
            ok: value.ok,
            stale: value.stale,
            username: value.username,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct QrLoginPayloadState {
    pub version: i32,
    pub api_key: String,
    pub otp: String,
    pub username: String,
    pub expires_at_unix_ms: Option<i64>,
}

impl From<fire_core::QrLoginPayload> for QrLoginPayloadState {
    fn from(value: fire_core::QrLoginPayload) -> Self {
        Self {
            version: value.version,
            api_key: value.api_key,
            otp: value.otp,
            username: value.username,
            expires_at_unix_ms: value.expires_at_unix_ms,
        }
    }
}

impl From<QrLoginPayloadState> for fire_core::QrLoginPayload {
    fn from(value: QrLoginPayloadState) -> Self {
        Self {
            version: value.version,
            api_key: value.api_key,
            otp: value.otp,
            username: value.username,
            expires_at_unix_ms: value.expires_at_unix_ms,
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait UserApiKeyCryptoHandler: Send + Sync {
    fn public_key_pem(&self) -> String;
    fn decrypt_payload(&self, payload: String) -> Option<String>;
    fn read_api_key(&self) -> Option<String>;
    fn write_api_key(&self, api_key: String);
    fn clear_api_key(&self);
}
