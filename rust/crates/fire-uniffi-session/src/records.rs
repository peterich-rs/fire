use fire_core::{FireAuthRecoveryHint, FireAuthRecoveryHintReason};
use fire_models::{
    BootstrapArtifacts, CookieSnapshot, LoginPhase, LoginSyncInput, PlatformCookie,
    SessionReadiness, SessionSnapshot, TopicCategory,
};

use fire_uniffi_types::RequiredTagGroupState;

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
pub struct PlatformCookieState {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub expires_at_unix_ms: Option<i64>,
}

impl From<PlatformCookie> for PlatformCookieState {
    fn from(value: PlatformCookie) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
            expires_at_unix_ms: value.expires_at_unix_ms,
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
}

impl From<CookieSnapshot> for CookieState {
    fn from(value: CookieSnapshot) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
            cf_clearance: value.cf_clearance,
            csrf_token: value.csrf_token,
            platform_cookies: value.platform_cookies.into_iter().map(Into::into).collect(),
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
    pub profile_display_name: String,
    pub login_phase_label: String,
}

impl SessionState {
    pub fn from_snapshot(snapshot: SessionSnapshot) -> Self {
        let readiness = snapshot.readiness();
        let login_phase = snapshot.login_phase();
        Self {
            has_login_session: snapshot.cookies.has_login_session(),
            profile_display_name: snapshot.profile_display_name(),
            login_phase_label: snapshot.login_phase_label(),
            cookies: snapshot.cookies.into(),
            bootstrap: snapshot.bootstrap.into(),
            readiness: readiness.into(),
            login_phase: login_phase.into(),
        }
    }
}
