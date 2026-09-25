use serde::{Deserialize, Serialize};

use super::snapshot::SessionSnapshot;
use crate::cookie::PlatformCookie;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoginSyncInput {
    pub current_url: Option<String>,
    pub username: Option<String>,
    pub csrf_token: Option<String>,
    pub home_html: Option<String>,
    #[serde(default)]
    pub browser_user_agent: Option<String>,
    pub cookies: Vec<PlatformCookie>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WebViewLoginPhase {
    Csrf,
    Hcaptcha,
    Session,
    Exception,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebViewLoginJsResult {
    pub phase: WebViewLoginPhase,
    pub status: u16,
    pub body: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LoginFailureKind {
    InvalidCredentials,
    NotActivated,
    NotApproved,
    PasswordExpired,
    Network,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoginFailure {
    pub kind: LoginFailureKind,
    pub message: Option<String>,
    pub sent_to_email: Option<String>,
    pub current_email: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SecondFactorRequirement {
    pub totp_enabled: bool,
    pub security_key_enabled: bool,
    pub backup_enabled: bool,
    pub message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum WebViewLoginDecision {
    Success,
    NeedSecondFactor(SecondFactorRequirement),
    RetryCloudflare,
    Failure(LoginFailure),
}

#[derive(Debug, Clone)]
pub struct LoginFinalizationResult {
    pub success: bool,
    pub session: SessionSnapshot,
    pub t_token_verified: bool,
    pub fingerprint_wait_needed: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LoginStateDetermination {
    LoggedIn { username: String, user_id: u64 },
    NotLoggedIn,
    SessionExpired,
    NetworkErrorPreserveState,
}
