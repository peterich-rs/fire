use fire_models::{
    CanonicalCookie, CookieSameSite, CookieSnapshot, CookieSource, CookieSweepIntent,
    CookieSweepPlan, NuclearResetPlan, PlatformCookie, WebViewCookieAction, WebViewCookieInfo,
};

#[derive(uniffi::Record, Debug, Clone)]
pub struct PlatformCookieState {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub expires_at_unix_ms: Option<i64>,
    pub same_site: Option<String>,
}

impl From<PlatformCookie> for PlatformCookieState {
    fn from(value: PlatformCookie) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
            expires_at_unix_ms: value.expires_at_unix_ms,
            same_site: value.same_site,
        }
    }
}

impl From<PlatformCookieState> for PlatformCookie {
    fn from(value: PlatformCookieState) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
            expires_at_unix_ms: value.expires_at_unix_ms,
            same_site: value.same_site,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum CookieSameSiteState {
    Unspecified,
    Lax,
    Strict,
    None,
}

impl From<CookieSameSite> for CookieSameSiteState {
    fn from(value: CookieSameSite) -> Self {
        match value {
            CookieSameSite::Unspecified => Self::Unspecified,
            CookieSameSite::Lax => Self::Lax,
            CookieSameSite::Strict => Self::Strict,
            CookieSameSite::None => Self::None,
        }
    }
}

impl From<CookieSameSiteState> for CookieSameSite {
    fn from(value: CookieSameSiteState) -> Self {
        match value {
            CookieSameSiteState::Unspecified => Self::Unspecified,
            CookieSameSiteState::Lax => Self::Lax,
            CookieSameSiteState::Strict => Self::Strict,
            CookieSameSiteState::None => Self::None,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum CookieSourceState {
    Unknown,
    NetworkSetCookie,
    WebViewLogin,
    WebViewChallenge,
    WebViewBulkRead,
    ManualRestore,
}

impl From<CookieSource> for CookieSourceState {
    fn from(value: CookieSource) -> Self {
        match value {
            CookieSource::Unknown => Self::Unknown,
            CookieSource::NetworkSetCookie => Self::NetworkSetCookie,
            CookieSource::WebViewLogin => Self::WebViewLogin,
            CookieSource::WebViewChallenge => Self::WebViewChallenge,
            CookieSource::WebViewBulkRead => Self::WebViewBulkRead,
            CookieSource::ManualRestore => Self::ManualRestore,
        }
    }
}

impl From<CookieSourceState> for CookieSource {
    fn from(value: CookieSourceState) -> Self {
        match value {
            CookieSourceState::Unknown => Self::Unknown,
            CookieSourceState::NetworkSetCookie => Self::NetworkSetCookie,
            CookieSourceState::WebViewLogin => Self::WebViewLogin,
            CookieSourceState::WebViewChallenge => Self::WebViewChallenge,
            CookieSourceState::WebViewBulkRead => Self::WebViewBulkRead,
            CookieSourceState::ManualRestore => Self::ManualRestore,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CanonicalCookieState {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: String,
    pub host_only: bool,
    pub secure: bool,
    pub http_only: bool,
    pub same_site: CookieSameSiteState,
    pub partition_key: Option<String>,
    pub partitioned: bool,
    pub expires_at_unix_ms: Option<i64>,
    pub max_age_seconds: Option<i64>,
    pub creation_time_unix_ms: i64,
    pub last_access_time_unix_ms: i64,
    pub version: u64,
    pub source: CookieSourceState,
    pub raw_set_cookie: Option<String>,
    pub origin_url: Option<String>,
}

impl From<CanonicalCookie> for CanonicalCookieState {
    fn from(value: CanonicalCookie) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
            host_only: value.host_only,
            secure: value.secure,
            http_only: value.http_only,
            same_site: value.same_site.into(),
            partition_key: value.partition_key,
            partitioned: value.partitioned,
            expires_at_unix_ms: value.expires_at_unix_ms,
            max_age_seconds: value.max_age_seconds,
            creation_time_unix_ms: value.creation_time_unix_ms,
            last_access_time_unix_ms: value.last_access_time_unix_ms,
            version: value.version,
            source: value.source.into(),
            raw_set_cookie: value.raw_set_cookie,
            origin_url: value.origin_url,
        }
    }
}

impl From<CanonicalCookieState> for CanonicalCookie {
    fn from(value: CanonicalCookieState) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
            host_only: value.host_only,
            secure: value.secure,
            http_only: value.http_only,
            same_site: value.same_site.into(),
            partition_key: value.partition_key,
            partitioned: value.partitioned,
            expires_at_unix_ms: value.expires_at_unix_ms,
            max_age_seconds: value.max_age_seconds,
            creation_time_unix_ms: value.creation_time_unix_ms,
            last_access_time_unix_ms: value.last_access_time_unix_ms,
            version: value.version,
            source: value.source.into(),
            raw_set_cookie: value.raw_set_cookie,
            origin_url: value.origin_url,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum WebViewCookieActionState {
    SetRaw {
        url: String,
        set_cookie: String,
    },
    DeleteExact {
        url: String,
        name: String,
        domain: Option<String>,
        path: String,
    },
    DeleteByName {
        url: String,
        name: String,
    },
}

impl From<WebViewCookieAction> for WebViewCookieActionState {
    fn from(value: WebViewCookieAction) -> Self {
        match value {
            WebViewCookieAction::SetRaw { url, set_cookie } => Self::SetRaw { url, set_cookie },
            WebViewCookieAction::DeleteExact {
                url,
                name,
                domain,
                path,
            } => Self::DeleteExact {
                url,
                name,
                domain,
                path,
            },
            WebViewCookieAction::DeleteByName { url, name } => Self::DeleteByName { url, name },
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct WebViewCookieInfoState {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub host_only: Option<bool>,
    pub secure: Option<bool>,
    pub http_only: Option<bool>,
    pub same_site: Option<CookieSameSiteState>,
    pub expires_at_unix_ms: Option<i64>,
}

impl From<WebViewCookieInfoState> for WebViewCookieInfo {
    fn from(value: WebViewCookieInfoState) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
            host_only: value.host_only,
            secure: value.secure,
            http_only: value.http_only,
            same_site: value.same_site.map(Into::into),
            expires_at_unix_ms: value.expires_at_unix_ms,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum CookieSweepIntentState {
    EnsureUnique,
    Delete,
}

impl From<CookieSweepIntent> for CookieSweepIntentState {
    fn from(value: CookieSweepIntent) -> Self {
        match value {
            CookieSweepIntent::EnsureUnique => Self::EnsureUnique,
            CookieSweepIntent::Delete => Self::Delete,
        }
    }
}

impl From<CookieSweepIntentState> for CookieSweepIntent {
    fn from(value: CookieSweepIntentState) -> Self {
        match value {
            CookieSweepIntentState::EnsureUnique => Self::EnsureUnique,
            CookieSweepIntentState::Delete => Self::Delete,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookieSweepPlanState {
    pub name: String,
    pub intent: CookieSweepIntentState,
    pub actions: Vec<WebViewCookieActionState>,
    pub selected_winner: Option<CanonicalCookieState>,
}

impl From<CookieSweepPlan> for CookieSweepPlanState {
    fn from(value: CookieSweepPlan) -> Self {
        Self {
            name: value.name,
            intent: value.intent.into(),
            actions: value.actions.into_iter().map(Into::into).collect(),
            selected_winner: value.selected_winner.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NuclearResetPlanState {
    pub actions: Vec<WebViewCookieActionState>,
}

impl From<NuclearResetPlan> for NuclearResetPlanState {
    fn from(value: NuclearResetPlan) -> Self {
        Self {
            actions: value.actions.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookieState {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
    pub cf_clearance: Option<String>,
    pub csrf_token: Option<String>,
    pub platform_cookies: Vec<PlatformCookieState>,
    pub canonical_cookies: Vec<CanonicalCookieState>,
}

impl From<CookieSnapshot> for CookieState {
    fn from(value: CookieSnapshot) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
            cf_clearance: value.cf_clearance,
            csrf_token: value.csrf_token,
            platform_cookies: value.platform_cookies.into_iter().map(Into::into).collect(),
            canonical_cookies: value
                .canonical_cookies
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}

impl From<CookieState> for CookieSnapshot {
    fn from(value: CookieState) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
            cf_clearance: value.cf_clearance,
            csrf_token: value.csrf_token,
            last_challenged_cf_clearance: None,
            platform_cookies: value.platform_cookies.into_iter().map(Into::into).collect(),
            canonical_cookies: value
                .canonical_cookies
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}
