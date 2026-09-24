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
