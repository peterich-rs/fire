use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub struct PassiveLogoutTrigger {
    pub source: String,
    pub signal_strength: SignalStrength,
    pub cookie_diagnostic: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SignalStrength {
    Strong,
    Weak,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AuthRuntimeSignalStrength {
    Diagnostic,
    Weak,
    Strong,
    Terminal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AuthRuntimeSignalSource {
    HttpResponse,
    SetCookieIngress,
    Probe,
    StartupAuthority,
    PlatformSync,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AuthRuntimeSignalKind {
    NotLoggedInBody,
    DiscourseLoggedOutHeader,
    MixedLoggedOutHeader,
    AuthCookieDeletion,
    MixedSignalCookieDeletionBlocked,
    InvalidAccessForbidden,
    BadCsrf,
    CloudflareChallenge,
    RateLimit,
    ProbeValid,
    ProbeInvalid,
    ProbeInconclusive,
    ProbeInconclusiveEscalated,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuthRuntimeSignal {
    pub kind: AuthRuntimeSignalKind,
    pub strength: AuthRuntimeSignalStrength,
    pub source: AuthRuntimeSignalSource,
    pub operation: Option<String>,
    pub status: Option<u16>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ProbeResult {
    Valid { username: String },
    Invalid,
    Inconclusive,
}
