use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
};

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthRuntimeSignalStrengthState {
    Diagnostic,
    Weak,
    Strong,
    Terminal,
}

impl From<AuthRuntimeSignalStrength> for AuthRuntimeSignalStrengthState {
    fn from(value: AuthRuntimeSignalStrength) -> Self {
        match value {
            AuthRuntimeSignalStrength::Diagnostic => Self::Diagnostic,
            AuthRuntimeSignalStrength::Weak => Self::Weak,
            AuthRuntimeSignalStrength::Strong => Self::Strong,
            AuthRuntimeSignalStrength::Terminal => Self::Terminal,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthRuntimeSignalSourceState {
    HttpResponse,
    SetCookieIngress,
    Probe,
    StartupAuthority,
    PlatformSync,
}

impl From<AuthRuntimeSignalSource> for AuthRuntimeSignalSourceState {
    fn from(value: AuthRuntimeSignalSource) -> Self {
        match value {
            AuthRuntimeSignalSource::HttpResponse => Self::HttpResponse,
            AuthRuntimeSignalSource::SetCookieIngress => Self::SetCookieIngress,
            AuthRuntimeSignalSource::Probe => Self::Probe,
            AuthRuntimeSignalSource::StartupAuthority => Self::StartupAuthority,
            AuthRuntimeSignalSource::PlatformSync => Self::PlatformSync,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthRuntimeSignalKindState {
    NotLoggedInBody,
    DiscourseLoggedOutHeader,
    MixedLoggedOutHeader,
    AuthCookieDeletion,
    MixedSignalCookieDeletionBlocked,
    InvalidAccessForbidden,
    BadCsrf,
    CloudflareChallenge,
    AskEnableBrowserTransport,
    RateLimit,
    ProbeValid,
    ProbeInvalid,
    ProbeInconclusive,
    ProbeInconclusiveEscalated,
}

impl From<AuthRuntimeSignalKind> for AuthRuntimeSignalKindState {
    fn from(value: AuthRuntimeSignalKind) -> Self {
        match value {
            AuthRuntimeSignalKind::NotLoggedInBody => Self::NotLoggedInBody,
            AuthRuntimeSignalKind::DiscourseLoggedOutHeader => Self::DiscourseLoggedOutHeader,
            AuthRuntimeSignalKind::MixedLoggedOutHeader => Self::MixedLoggedOutHeader,
            AuthRuntimeSignalKind::AuthCookieDeletion => Self::AuthCookieDeletion,
            AuthRuntimeSignalKind::MixedSignalCookieDeletionBlocked => {
                Self::MixedSignalCookieDeletionBlocked
            }
            AuthRuntimeSignalKind::InvalidAccessForbidden => Self::InvalidAccessForbidden,
            AuthRuntimeSignalKind::BadCsrf => Self::BadCsrf,
            AuthRuntimeSignalKind::CloudflareChallenge => Self::CloudflareChallenge,
            AuthRuntimeSignalKind::AskEnableBrowserTransport => Self::AskEnableBrowserTransport,
            AuthRuntimeSignalKind::RateLimit => Self::RateLimit,
            AuthRuntimeSignalKind::ProbeValid => Self::ProbeValid,
            AuthRuntimeSignalKind::ProbeInvalid => Self::ProbeInvalid,
            AuthRuntimeSignalKind::ProbeInconclusive => Self::ProbeInconclusive,
            AuthRuntimeSignalKind::ProbeInconclusiveEscalated => Self::ProbeInconclusiveEscalated,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone, PartialEq, Eq)]
pub struct AuthRuntimeSignalState {
    pub kind: AuthRuntimeSignalKindState,
    pub strength: AuthRuntimeSignalStrengthState,
    pub source: AuthRuntimeSignalSourceState,
    pub operation: Option<String>,
    pub status: Option<u16>,
}

impl From<AuthRuntimeSignal> for AuthRuntimeSignalState {
    fn from(value: AuthRuntimeSignal) -> Self {
        Self {
            kind: value.kind.into(),
            strength: value.strength.into(),
            source: value.source.into(),
            operation: value.operation,
            status: value.status,
        }
    }
}
