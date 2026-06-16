use fire_core::{
    FireAuthRecoveryHint, FireAuthRecoveryHintReason,
    FireSessionPersistenceState as CoreSessionPersistenceState,
};
use fire_models::{
    AppStateRefreshEvent, BootstrapArtifacts, CanonicalCookie, CloudflareChallengeRequest,
    CloudflareChallengeResult, CookieSameSite, CookieSelfHealingPhase, CookieSelfHealingRequest,
    CookieSelfHealingResult, CookieSnapshot, CookieSource, CookieSweepIntent, CookieSweepPlan,
    HomeTopicListScope, LoginFailure, LoginFailureKind, LoginFinalizationResult, LoginPhase,
    LoginSyncInput, NuclearResetPlan, PassiveLogoutTrigger, PlatformCookie, ProbeResult,
    RefreshBatch, SecondFactorRequirement, SessionReadiness, SessionSnapshot, SignalStrength,
    TopicCategory, WebViewCookieAction, WebViewCookieInfo, WebViewLoginDecision,
    WebViewLoginJsResult, WebViewLoginPhase,
};
use fire_store::cookie_replay::CookieReplayEntry;

use fire_uniffi_types::{RequiredTagGroupState, TopicListKindState};

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
            platform_cookies: value.platform_cookies.into_iter().map(Into::into).collect(),
            canonical_cookies: value
                .canonical_cookies
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicCategoryState {
    pub id: u64,
    pub name: String,
    pub slug: String,
    pub parent_category_id: Option<u64>,
    pub color_hex: Option<String>,
    pub text_color_hex: Option<String>,
    pub topic_template: Option<String>,
    pub minimum_required_tags: u32,
    pub required_tag_groups: Vec<RequiredTagGroupState>,
    pub allowed_tags: Vec<String>,
    pub permission: Option<u32>,
    pub notification_level: Option<i32>,
}

impl From<TopicCategory> for TopicCategoryState {
    fn from(value: TopicCategory) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
            parent_category_id: value.parent_category_id,
            color_hex: value.color_hex,
            text_color_hex: value.text_color_hex,
            topic_template: value.topic_template,
            minimum_required_tags: value.minimum_required_tags,
            required_tag_groups: value
                .required_tag_groups
                .into_iter()
                .map(Into::into)
                .collect(),
            allowed_tags: value.allowed_tags,
            permission: value.permission,
            notification_level: value.notification_level,
        }
    }
}

impl From<TopicCategoryState> for TopicCategory {
    fn from(value: TopicCategoryState) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
            parent_category_id: value.parent_category_id,
            color_hex: value.color_hex,
            text_color_hex: value.text_color_hex,
            topic_template: value.topic_template,
            minimum_required_tags: value.minimum_required_tags,
            required_tag_groups: value
                .required_tag_groups
                .into_iter()
                .map(Into::into)
                .collect(),
            allowed_tags: value.allowed_tags,
            permission: value.permission,
            notification_level: value.notification_level,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct HomeTopicListScopeState {
    pub kind: TopicListKindState,
    pub category_id: Option<u64>,
    pub tags: Vec<String>,
}

impl From<HomeTopicListScope> for HomeTopicListScopeState {
    fn from(value: HomeTopicListScope) -> Self {
        Self {
            kind: value.kind.into(),
            category_id: value.category_id,
            tags: value.tags,
        }
    }
}

impl From<HomeTopicListScopeState> for HomeTopicListScope {
    fn from(value: HomeTopicListScopeState) -> Self {
        Self {
            kind: value.kind.into(),
            category_id: value.category_id,
            tags: value.tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BootstrapState {
    pub base_url: String,
    pub discourse_base_uri: Option<String>,
    pub shared_session_key: Option<String>,
    pub current_username: Option<String>,
    pub current_user_id: Option<u64>,
    pub notification_channel_position: Option<i64>,
    pub long_polling_base_url: Option<String>,
    pub turnstile_sitekey: Option<String>,
    pub topic_tracking_state_meta: Option<String>,
    pub preloaded_json: Option<String>,
    pub has_preloaded_data: bool,
    pub has_site_metadata: bool,
    pub top_tags: Vec<String>,
    pub can_tag_topics: bool,
    pub categories: Vec<TopicCategoryState>,
    pub has_site_settings: bool,
    pub enabled_reaction_ids: Vec<String>,
    pub min_post_length: u32,
    pub min_topic_title_length: u32,
    pub min_first_post_length: u32,
    pub min_personal_message_title_length: u32,
    pub min_personal_message_post_length: u32,
    pub default_composer_category: Option<u64>,
}

impl From<BootstrapArtifacts> for BootstrapState {
    fn from(value: BootstrapArtifacts) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            current_user_id: value.current_user_id,
            notification_channel_position: value.notification_channel_position,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
            has_site_metadata: value.has_site_metadata,
            top_tags: value.top_tags,
            can_tag_topics: value.can_tag_topics,
            categories: value.categories.into_iter().map(Into::into).collect(),
            has_site_settings: value.has_site_settings,
            enabled_reaction_ids: value.enabled_reaction_ids,
            min_post_length: value.min_post_length,
            min_topic_title_length: value.min_topic_title_length,
            min_first_post_length: value.min_first_post_length,
            min_personal_message_title_length: value.min_personal_message_title_length,
            min_personal_message_post_length: value.min_personal_message_post_length,
            default_composer_category: value.default_composer_category,
        }
    }
}

impl From<BootstrapState> for BootstrapArtifacts {
    fn from(value: BootstrapState) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            current_user_id: value.current_user_id,
            notification_channel_position: value.notification_channel_position,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
            has_site_metadata: value.has_site_metadata,
            top_tags: value.top_tags,
            can_tag_topics: value.can_tag_topics,
            categories: value.categories.into_iter().map(Into::into).collect(),
            has_site_settings: value.has_site_settings,
            enabled_reaction_ids: value.enabled_reaction_ids,
            min_post_length: value.min_post_length,
            min_topic_title_length: value.min_topic_title_length,
            min_first_post_length: value.min_first_post_length,
            min_personal_message_title_length: value.min_personal_message_title_length,
            min_personal_message_post_length: value.min_personal_message_post_length,
            default_composer_category: value.default_composer_category,
        }
    }
}

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

#[derive(uniffi::Record, Debug, Clone)]
pub struct CurrentUserSnapshotState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub animated_avatar: Option<String>,
    pub trust_level: u8,
    pub status_description: Option<String>,
    pub status_emoji: Option<String>,
    pub flair_url: Option<String>,
    pub flair_name: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub flair_group_id: Option<u64>,
    pub gamification_score: Option<i64>,
    pub unread_notifications: u32,
    pub unread_high_priority_notifications: u32,
    pub all_unread_notifications_count: u32,
    pub seen_notification_id: u64,
    pub notification_channel_position: i64,
}

impl From<fire_models::CurrentUserSnapshot> for CurrentUserSnapshotState {
    fn from(value: fire_models::CurrentUserSnapshot) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            animated_avatar: value.animated_avatar,
            trust_level: value.trust_level,
            status_description: value.status.as_ref().and_then(|s| s.description.clone()),
            status_emoji: value.status.and_then(|s| s.emoji),
            flair_url: value.flair_url,
            flair_name: value.flair_name,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            flair_group_id: value.flair_group_id,
            gamification_score: value.gamification_score,
            unread_notifications: value.unread_notifications,
            unread_high_priority_notifications: value.unread_high_priority_notifications,
            all_unread_notifications_count: value.all_unread_notifications_count,
            seen_notification_id: value.seen_notification_id,
            notification_channel_position: value.notification_channel_position,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum PreloadedDataStateState {
    NotStarted,
    Loading,
    Ready,
    Failed { error: String },
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum LoginStateDeterminationState {
    LoggedIn { username: String, user_id: u64 },
    NotLoggedIn,
    SessionExpired,
    NetworkErrorPreserveState,
}

impl From<fire_models::LoginStateDetermination> for LoginStateDeterminationState {
    fn from(value: fire_models::LoginStateDetermination) -> Self {
        match value {
            fire_models::LoginStateDetermination::LoggedIn { username, user_id } => {
                Self::LoggedIn { username, user_id }
            }
            fire_models::LoginStateDetermination::NotLoggedIn => Self::NotLoggedIn,
            fire_models::LoginStateDetermination::SessionExpired => Self::SessionExpired,
            fire_models::LoginStateDetermination::NetworkErrorPreserveState => {
                Self::NetworkErrorPreserveState
            }
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum RefreshTriggerState {
    LoginCompleted,
    LogoutCompleted,
    SessionRestored,
}

impl From<RefreshTriggerState> for fire_models::RefreshTrigger {
    fn from(value: RefreshTriggerState) -> Self {
        match value {
            RefreshTriggerState::LoginCompleted => Self::LoginCompleted,
            RefreshTriggerState::LogoutCompleted => Self::LogoutCompleted,
            RefreshTriggerState::SessionRestored => Self::SessionRestored,
        }
    }
}

impl From<fire_models::RefreshTrigger> for RefreshTriggerState {
    fn from(value: fire_models::RefreshTrigger) -> Self {
        match value {
            fire_models::RefreshTrigger::LoginCompleted => Self::LoginCompleted,
            fire_models::RefreshTrigger::LogoutCompleted => Self::LogoutCompleted,
            fire_models::RefreshTrigger::SessionRestored => Self::SessionRestored,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum RefreshBatchState {
    Core,
    Secondary,
}

impl From<RefreshBatch> for RefreshBatchState {
    fn from(value: RefreshBatch) -> Self {
        match value {
            RefreshBatch::Core => Self::Core,
            RefreshBatch::Secondary => Self::Secondary,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct AppStateRefreshEventState {
    pub batch: RefreshBatchState,
    pub trigger: RefreshTriggerState,
}

impl From<AppStateRefreshEvent> for AppStateRefreshEventState {
    fn from(value: AppStateRefreshEvent) -> Self {
        Self {
            batch: value.batch.into(),
            trigger: value.trigger.into(),
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait AppStateRefreshHandler: Send + Sync {
    fn on_app_state_refresh_event(&self, event: AppStateRefreshEventState);
}

#[uniffi::export(with_foreign)]
pub trait CloudflareChallengeHandler: Send + Sync {
    fn complete_cloudflare_challenge(
        &self,
        request: CloudflareChallengeRequestState,
    ) -> CloudflareChallengeResultState;
}

#[uniffi::export(with_foreign)]
pub trait CookieSelfHealingHandler: Send + Sync {
    fn heal_cookies(&self, request: CookieSelfHealingRequestState) -> CookieSelfHealingResultState;
}
