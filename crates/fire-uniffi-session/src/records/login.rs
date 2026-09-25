use fire_models::{
    LoginFailure, LoginFailureKind, LoginFinalizationResult, LoginPhase, LoginSyncInput,
    PassiveLogoutTrigger, ProbeResult, SecondFactorRequirement, SignalStrength,
    WebViewLoginDecision, WebViewLoginJsResult, WebViewLoginPhase,
};
use fire_store::cookie_replay::CookieReplayEntry;

use super::cookie::PlatformCookieState;
use super::session::SessionState;

#[derive(uniffi::Record, Debug, Clone)]
pub struct LoginSyncState {
    pub current_url: Option<String>,
    pub username: Option<String>,
    pub csrf_token: Option<String>,
    pub home_html: Option<String>,
    pub browser_user_agent: Option<String>,
    pub cookies: Vec<PlatformCookieState>,
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum WebViewLoginPhaseState {
    Csrf,
    Hcaptcha,
    Session,
    Exception,
}

impl From<WebViewLoginPhaseState> for WebViewLoginPhase {
    fn from(value: WebViewLoginPhaseState) -> Self {
        match value {
            WebViewLoginPhaseState::Csrf => Self::Csrf,
            WebViewLoginPhaseState::Hcaptcha => Self::Hcaptcha,
            WebViewLoginPhaseState::Session => Self::Session,
            WebViewLoginPhaseState::Exception => Self::Exception,
        }
    }
}

impl From<WebViewLoginPhase> for WebViewLoginPhaseState {
    fn from(value: WebViewLoginPhase) -> Self {
        match value {
            WebViewLoginPhase::Csrf => Self::Csrf,
            WebViewLoginPhase::Hcaptcha => Self::Hcaptcha,
            WebViewLoginPhase::Session => Self::Session,
            WebViewLoginPhase::Exception => Self::Exception,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct WebViewLoginJsResultState {
    pub phase: WebViewLoginPhaseState,
    pub status: u16,
    pub body: String,
}

impl From<WebViewLoginJsResultState> for WebViewLoginJsResult {
    fn from(value: WebViewLoginJsResultState) -> Self {
        Self {
            phase: value.phase.into(),
            status: value.status,
            body: value.body,
        }
    }
}

impl From<WebViewLoginJsResult> for WebViewLoginJsResultState {
    fn from(value: WebViewLoginJsResult) -> Self {
        Self {
            phase: value.phase.into(),
            status: value.status,
            body: value.body,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum LoginFailureKindState {
    InvalidCredentials,
    NotActivated,
    NotApproved,
    PasswordExpired,
    Network,
    Unknown,
}

impl From<LoginFailureKind> for LoginFailureKindState {
    fn from(value: LoginFailureKind) -> Self {
        match value {
            LoginFailureKind::InvalidCredentials => Self::InvalidCredentials,
            LoginFailureKind::NotActivated => Self::NotActivated,
            LoginFailureKind::NotApproved => Self::NotApproved,
            LoginFailureKind::PasswordExpired => Self::PasswordExpired,
            LoginFailureKind::Network => Self::Network,
            LoginFailureKind::Unknown => Self::Unknown,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LoginFailureState {
    pub kind: LoginFailureKindState,
    pub message: Option<String>,
    pub sent_to_email: Option<String>,
    pub current_email: Option<String>,
}

impl From<LoginFailure> for LoginFailureState {
    fn from(value: LoginFailure) -> Self {
        Self {
            kind: value.kind.into(),
            message: value.message,
            sent_to_email: value.sent_to_email,
            current_email: value.current_email,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SecondFactorRequirementState {
    pub totp_enabled: bool,
    pub security_key_enabled: bool,
    pub backup_enabled: bool,
    pub message: Option<String>,
}

impl From<SecondFactorRequirement> for SecondFactorRequirementState {
    fn from(value: SecondFactorRequirement) -> Self {
        Self {
            totp_enabled: value.totp_enabled,
            security_key_enabled: value.security_key_enabled,
            backup_enabled: value.backup_enabled,
            message: value.message,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum WebViewLoginDecisionState {
    Success,
    NeedSecondFactor {
        requirement: SecondFactorRequirementState,
    },
    RetryCloudflare,
    Failure {
        failure: LoginFailureState,
    },
}

impl From<WebViewLoginDecision> for WebViewLoginDecisionState {
    fn from(value: WebViewLoginDecision) -> Self {
        match value {
            WebViewLoginDecision::Success => Self::Success,
            WebViewLoginDecision::NeedSecondFactor(requirement) => Self::NeedSecondFactor {
                requirement: requirement.into(),
            },
            WebViewLoginDecision::RetryCloudflare => Self::RetryCloudflare,
            WebViewLoginDecision::Failure(failure) => Self::Failure {
                failure: failure.into(),
            },
        }
    }
}

impl From<LoginSyncInput> for LoginSyncState {
    fn from(value: LoginSyncInput) -> Self {
        Self {
            current_url: value.current_url,
            username: value.username,
            csrf_token: value.csrf_token,
            home_html: value.home_html,
            browser_user_agent: value.browser_user_agent,
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
            browser_user_agent: value.browser_user_agent,
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
pub struct LoginFinalizationResultState {
    pub success: bool,
    pub session: SessionState,
    pub t_token_verified: bool,
    pub fingerprint_wait_needed: bool,
}

impl From<LoginFinalizationResult> for LoginFinalizationResultState {
    fn from(value: LoginFinalizationResult) -> Self {
        Self {
            success: value.success,
            session: SessionState::from_snapshot(value.session),
            t_token_verified: value.t_token_verified,
            fingerprint_wait_needed: value.fingerprint_wait_needed,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PassiveLogoutTriggerState {
    pub source: String,
    pub signal_strength: String,
    pub cookie_diagnostic: String,
}

impl From<PassiveLogoutTrigger> for PassiveLogoutTriggerState {
    fn from(value: PassiveLogoutTrigger) -> Self {
        Self {
            source: value.source,
            signal_strength: match value.signal_strength {
                SignalStrength::Strong => "strong".to_string(),
                SignalStrength::Weak => "weak".to_string(),
            },
            cookie_diagnostic: value.cookie_diagnostic,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookieReplayEntryState {
    pub url: String,
    pub raw_set_cookie: String,
    pub cookie_name: String,
    pub domain: String,
    pub inserted_at: u64,
}

impl From<CookieReplayEntry> for CookieReplayEntryState {
    fn from(value: CookieReplayEntry) -> Self {
        Self {
            url: value.url,
            raw_set_cookie: value.raw_set_cookie,
            cookie_name: value.cookie_name,
            domain: value.domain,
            inserted_at: value.inserted_at,
        }
    }
}

pub fn format_probe_result(result: ProbeResult) -> String {
    match result {
        ProbeResult::Valid { username } => format!("valid:{}", username),
        ProbeResult::Invalid => "invalid".to_string(),
        ProbeResult::Inconclusive => "inconclusive".to_string(),
    }
}
