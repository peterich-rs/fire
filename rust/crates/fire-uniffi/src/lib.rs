use std::{
    any::Any,
    backtrace::Backtrace,
    future::Future,
    panic::{self, AssertUnwindSafe},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, OnceLock,
    },
};

use fire_core::{
    monogram_for_username as shared_monogram_for_username,
    plain_text_from_html as shared_plain_text_from_html,
    preview_text_from_html as shared_preview_text_from_html, DiagnosticsPageDirection,
    DiagnosticsTextPage, FireCore, FireCoreConfig, FireCoreError, FireHostLogLevel,
    FireLogFileDetail, FireLogFilePage, FireLogFileSummary, FireSupportBundleExport,
    FireSupportBundleHostContext, NetworkTraceBodyPage, NetworkTraceDetail, NetworkTraceEvent,
    NetworkTraceHeader, NetworkTraceOutcome, NetworkTraceSummary,
};
use fire_models::{
    Badge, BootstrapArtifacts, CookieSnapshot, Draft, DraftData, DraftListResponse, FollowUser,
    GroupedSearchResult, InviteCreateRequest, InviteLink, InviteLinkDetails, LoginPhase,
    LoginSyncInput, MessageBusClientMode, MessageBusEvent, MessageBusEventKind,
    MessageBusSubscription, MessageBusSubscriptionScope, NotificationAlert,
    NotificationAlertPollResult, NotificationCounters, NotificationData, NotificationItem,
    NotificationListResponse, NotificationState, PlatformCookie, Poll, PollOption,
    PostReactionUpdate, PostUpdateRequest, ProfileSummaryReply, ProfileSummaryTopCategory,
    ProfileSummaryTopic, ProfileSummaryUserReference, RequiredTagGroup, ResolvedUploadUrl,
    SearchPost, SearchQuery, SearchResult, SearchTopic, SearchTypeFilter, SearchUser,
    SessionReadiness, SessionSnapshot, TagSearchItem, TagSearchQuery, TagSearchResult,
    TopicCategory, TopicCreateRequest, TopicDetail, TopicDetailCreatedBy, TopicDetailMeta,
    TopicDetailQuery, TopicListKind, TopicListQuery, TopicListResponse, TopicPost, TopicPostStream,
    TopicPoster, TopicPresence, TopicPresenceUser, TopicReaction, TopicReplyRequest, TopicRow,
    TopicSummary, TopicTag, TopicThread, TopicThreadFlatPost, TopicThreadReply, TopicThreadSection,
    TopicTimingEntry, TopicTimingsRequest, TopicUpdateRequest, TopicUser, UploadResult, UserAction,
    UserMentionGroup, UserMentionQuery, UserMentionResult, UserMentionUser, UserProfile,
    UserSummaryResponse, UserSummaryStats, VoteResponse, VotedUser,
};
use futures_util::FutureExt;
use tokio::runtime::{Builder, Runtime};
use tracing::error;

uniffi::setup_scaffolding!("fire_uniffi");

#[derive(Default)]
struct PanicState {
    poisoned: AtomicBool,
    last_panic: Mutex<Option<String>>,
}

impl PanicState {
    fn ensure_healthy(&self, operation: &'static str) -> Result<(), FireUniFfiError> {
        if !self.poisoned.load(Ordering::SeqCst) {
            return Ok(());
        }

        let previous = self
            .last_panic
            .lock()
            .ok()
            .and_then(|guard| guard.clone())
            .unwrap_or_else(|| "unknown panic".to_string());
        Err(FireUniFfiError::Internal {
            details: format!(
                "fire core handle is poisoned by a previous panic ({previous}); recreate the handle before calling {operation}"
            ),
        })
    }

    fn capture_panic(
        &self,
        operation: &'static str,
        payload: &(dyn Any + Send),
    ) -> FireUniFfiError {
        let report = CapturedPanic::from_payload(operation, payload);
        report.log();
        self.poisoned.store(true, Ordering::SeqCst);
        if let Ok(mut last_panic) = self.last_panic.lock() {
            *last_panic = Some(report.summary());
        }
        FireUniFfiError::Internal {
            details: report.user_message(),
        }
    }
}

struct CapturedPanic {
    operation: &'static str,
    message: String,
    backtrace: String,
}

impl CapturedPanic {
    fn from_payload(operation: &'static str, payload: &(dyn Any + Send)) -> Self {
        Self {
            operation,
            message: panic_payload_to_string(payload),
            backtrace: Backtrace::force_capture().to_string(),
        }
    }

    fn summary(&self) -> String {
        format!("{} panicked: {}", self.operation, self.message)
    }

    fn user_message(&self) -> String {
        self.summary()
    }

    fn log(&self) {
        error!(
            operation = self.operation,
            panic_message = %self.message,
            backtrace = %self.backtrace,
            "caught panic across fire-uniffi boundary"
        );
        if cfg!(debug_assertions) {
            eprintln!(
                "fire-uniffi caught panic in {}: {}\nbacktrace:\n{}",
                self.operation, self.message, self.backtrace
            );
        }
    }
}

fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&'static str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "non-string panic payload".to_string()
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
    fn from_snapshot(snapshot: SessionSnapshot) -> Self {
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

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum MessageBusClientModeState {
    Foreground,
    IosBackground,
}

impl From<MessageBusClientMode> for MessageBusClientModeState {
    fn from(value: MessageBusClientMode) -> Self {
        match value {
            MessageBusClientMode::Foreground => Self::Foreground,
            MessageBusClientMode::IosBackground => Self::IosBackground,
        }
    }
}

impl From<MessageBusClientModeState> for MessageBusClientMode {
    fn from(value: MessageBusClientModeState) -> Self {
        match value {
            MessageBusClientModeState::Foreground => Self::Foreground,
            MessageBusClientModeState::IosBackground => Self::IosBackground,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum MessageBusSubscriptionScopeState {
    Durable,
    Transient,
}

impl From<MessageBusSubscriptionScope> for MessageBusSubscriptionScopeState {
    fn from(value: MessageBusSubscriptionScope) -> Self {
        match value {
            MessageBusSubscriptionScope::Durable => Self::Durable,
            MessageBusSubscriptionScope::Transient => Self::Transient,
        }
    }
}

impl From<MessageBusSubscriptionScopeState> for MessageBusSubscriptionScope {
    fn from(value: MessageBusSubscriptionScopeState) -> Self {
        match value {
            MessageBusSubscriptionScopeState::Durable => Self::Durable,
            MessageBusSubscriptionScopeState::Transient => Self::Transient,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct MessageBusSubscriptionState {
    pub owner_token: String,
    pub channel: String,
    pub last_message_id: Option<i64>,
    pub scope: MessageBusSubscriptionScopeState,
}

impl From<MessageBusSubscription> for MessageBusSubscriptionState {
    fn from(value: MessageBusSubscription) -> Self {
        Self {
            owner_token: value.owner_token,
            channel: value.channel,
            last_message_id: value.last_message_id,
            scope: value.scope.into(),
        }
    }
}

impl From<MessageBusSubscriptionState> for MessageBusSubscription {
    fn from(value: MessageBusSubscriptionState) -> Self {
        Self {
            owner_token: value.owner_token,
            channel: value.channel,
            last_message_id: value.last_message_id,
            scope: value.scope.into(),
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum MessageBusEventKindState {
    TopicList,
    TopicDetail,
    TopicReaction,
    Presence,
    Notification,
    NotificationAlert,
    Unknown,
}

impl From<MessageBusEventKind> for MessageBusEventKindState {
    fn from(value: MessageBusEventKind) -> Self {
        match value {
            MessageBusEventKind::TopicList => Self::TopicList,
            MessageBusEventKind::TopicDetail => Self::TopicDetail,
            MessageBusEventKind::TopicReaction => Self::TopicReaction,
            MessageBusEventKind::Presence => Self::Presence,
            MessageBusEventKind::Notification => Self::Notification,
            MessageBusEventKind::NotificationAlert => Self::NotificationAlert,
            MessageBusEventKind::Unknown => Self::Unknown,
        }
    }
}

impl From<MessageBusEventKindState> for MessageBusEventKind {
    fn from(value: MessageBusEventKindState) -> Self {
        match value {
            MessageBusEventKindState::TopicList => Self::TopicList,
            MessageBusEventKindState::TopicDetail => Self::TopicDetail,
            MessageBusEventKindState::TopicReaction => Self::TopicReaction,
            MessageBusEventKindState::Presence => Self::Presence,
            MessageBusEventKindState::Notification => Self::Notification,
            MessageBusEventKindState::NotificationAlert => Self::NotificationAlert,
            MessageBusEventKindState::Unknown => Self::Unknown,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct MessageBusEventState {
    pub channel: String,
    pub message_id: i64,
    pub kind: MessageBusEventKindState,
    pub topic_list_kind: Option<TopicListKindState>,
    pub topic_id: Option<u64>,
    pub notification_user_id: Option<u64>,
    pub message_type: Option<String>,
    pub detail_event_type: Option<String>,
    pub reload_topic: bool,
    pub refresh_stream: bool,
    pub all_unread_notifications_count: Option<u32>,
    pub unread_notifications: Option<u32>,
    pub unread_high_priority_notifications: Option<u32>,
    pub payload_json: Option<String>,
}

impl From<MessageBusEvent> for MessageBusEventState {
    fn from(value: MessageBusEvent) -> Self {
        Self {
            channel: value.channel,
            message_id: value.message_id,
            kind: value.kind.into(),
            topic_list_kind: value.topic_list_kind.map(Into::into),
            topic_id: value.topic_id,
            notification_user_id: value.notification_user_id,
            message_type: value.message_type,
            detail_event_type: value.detail_event_type,
            reload_topic: value.reload_topic,
            refresh_stream: value.refresh_stream,
            all_unread_notifications_count: value.all_unread_notifications_count,
            unread_notifications: value.unread_notifications,
            unread_high_priority_notifications: value.unread_high_priority_notifications,
            payload_json: value.payload_json,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPresenceUserState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicPresenceUser> for TopicPresenceUserState {
    fn from(value: TopicPresenceUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPresenceState {
    pub topic_id: u64,
    pub message_id: i64,
    pub users: Vec<TopicPresenceUserState>,
}

impl From<TopicPresence> for TopicPresenceState {
    fn from(value: TopicPresence) -> Self {
        Self {
            topic_id: value.topic_id,
            message_id: value.message_id,
            users: value.users.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationAlertState {
    pub message_id: i64,
    pub notification_type: Option<u32>,
    pub topic_id: Option<u64>,
    pub post_number: Option<u32>,
    pub topic_title: Option<String>,
    pub excerpt: Option<String>,
    pub username: Option<String>,
    pub post_url: Option<String>,
    pub payload_json: Option<String>,
}

impl From<NotificationAlert> for NotificationAlertState {
    fn from(value: NotificationAlert) -> Self {
        Self {
            message_id: value.message_id,
            notification_type: value.notification_type,
            topic_id: value.topic_id,
            post_number: value.post_number,
            topic_title: value.topic_title,
            excerpt: value.excerpt,
            username: value.username,
            post_url: value.post_url,
            payload_json: value.payload_json,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationAlertPollResultState {
    pub notification_user_id: u64,
    pub client_id: String,
    pub last_message_id: i64,
    pub alerts: Vec<NotificationAlertState>,
}

impl From<NotificationAlertPollResult> for NotificationAlertPollResultState {
    fn from(value: NotificationAlertPollResult) -> Self {
        Self {
            notification_user_id: value.notification_user_id,
            client_id: value.client_id,
            last_message_id: value.last_message_id,
            alerts: value.alerts.into_iter().map(Into::into).collect(),
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait MessageBusEventHandler: Send + Sync {
    fn on_message_bus_event(&self, event: MessageBusEventState);
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationCountersState {
    pub all_unread: u32,
    pub unread: u32,
    pub high_priority: u32,
}

impl From<NotificationCounters> for NotificationCountersState {
    fn from(value: NotificationCounters) -> Self {
        Self {
            all_unread: value.all_unread,
            unread: value.unread,
            high_priority: value.high_priority,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationDataState {
    pub display_username: Option<String>,
    pub original_post_id: Option<String>,
    pub original_post_type: Option<i32>,
    pub original_username: Option<String>,
    pub revision_number: Option<u32>,
    pub topic_title: Option<String>,
    pub badge_name: Option<String>,
    pub badge_id: Option<u64>,
    pub badge_slug: Option<String>,
    pub group_name: Option<String>,
    pub inbox_count: Option<String>,
    pub count: Option<u32>,
    pub username: Option<String>,
    pub username2: Option<String>,
    pub avatar_template: Option<String>,
    pub excerpt: Option<String>,
    pub payload_json: Option<String>,
}

impl From<NotificationData> for NotificationDataState {
    fn from(value: NotificationData) -> Self {
        Self {
            display_username: value.display_username,
            original_post_id: value.original_post_id,
            original_post_type: value.original_post_type,
            original_username: value.original_username,
            revision_number: value.revision_number,
            topic_title: value.topic_title,
            badge_name: value.badge_name,
            badge_id: value.badge_id,
            badge_slug: value.badge_slug,
            group_name: value.group_name,
            inbox_count: value.inbox_count,
            count: value.count,
            username: value.username,
            username2: value.username2,
            avatar_template: value.avatar_template,
            excerpt: value.excerpt,
            payload_json: value.payload_json,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationItemState {
    pub id: u64,
    pub user_id: Option<u64>,
    pub notification_type: i32,
    pub read: bool,
    pub high_priority: bool,
    pub created_at: Option<String>,
    pub created_timestamp_unix_ms: Option<u64>,
    pub post_number: Option<u32>,
    pub topic_id: Option<u64>,
    pub slug: Option<String>,
    pub fancy_title: Option<String>,
    pub acting_user_avatar_template: Option<String>,
    pub data: NotificationDataState,
}

impl From<NotificationItem> for NotificationItemState {
    fn from(value: NotificationItem) -> Self {
        Self {
            id: value.id,
            user_id: value.user_id,
            notification_type: value.notification_type,
            read: value.read,
            high_priority: value.high_priority,
            created_at: value.created_at,
            created_timestamp_unix_ms: value.created_timestamp_unix_ms,
            post_number: value.post_number,
            topic_id: value.topic_id,
            slug: value.slug,
            fancy_title: value.fancy_title,
            acting_user_avatar_template: value.acting_user_avatar_template,
            data: value.data.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationListState {
    pub notifications: Vec<NotificationItemState>,
    pub total_rows_notifications: u32,
    pub seen_notification_id: Option<u64>,
    pub load_more_notifications: Option<String>,
    pub next_offset: Option<u32>,
}

impl From<NotificationListResponse> for NotificationListState {
    fn from(value: NotificationListResponse) -> Self {
        Self {
            notifications: value.notifications.into_iter().map(Into::into).collect(),
            total_rows_notifications: value.total_rows_notifications,
            seen_notification_id: value.seen_notification_id,
            load_more_notifications: value.load_more_notifications,
            next_offset: value.next_offset,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationCenterState {
    pub counters: NotificationCountersState,
    pub recent: Vec<NotificationItemState>,
    pub has_loaded_recent: bool,
    pub recent_seen_notification_id: Option<u64>,
    pub full: Vec<NotificationItemState>,
    pub has_loaded_full: bool,
    pub total_rows_notifications: u32,
    pub full_seen_notification_id: Option<u64>,
    pub full_load_more_notifications: Option<String>,
    pub full_next_offset: Option<u32>,
}

impl From<NotificationState> for NotificationCenterState {
    fn from(value: NotificationState) -> Self {
        Self {
            counters: value.counters.into(),
            recent: value.recent.into_iter().map(Into::into).collect(),
            has_loaded_recent: value.has_loaded_recent,
            recent_seen_notification_id: value.recent_seen_notification_id,
            full: value.full.into_iter().map(Into::into).collect(),
            has_loaded_full: value.has_loaded_full,
            total_rows_notifications: value.total_rows_notifications,
            full_seen_notification_id: value.full_seen_notification_id,
            full_load_more_notifications: value.full_load_more_notifications,
            full_next_offset: value.full_next_offset,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum TopicListKindState {
    Latest,
    New,
    Unread,
    Unseen,
    Hot,
    Top,
}

impl From<TopicListKind> for TopicListKindState {
    fn from(value: TopicListKind) -> Self {
        match value {
            TopicListKind::Latest => Self::Latest,
            TopicListKind::New => Self::New,
            TopicListKind::Unread => Self::Unread,
            TopicListKind::Unseen => Self::Unseen,
            TopicListKind::Hot => Self::Hot,
            TopicListKind::Top => Self::Top,
        }
    }
}

impl From<TopicListKindState> for TopicListKind {
    fn from(value: TopicListKindState) -> Self {
        match value {
            TopicListKindState::Latest => Self::Latest,
            TopicListKindState::New => Self::New,
            TopicListKindState::Unread => Self::Unread,
            TopicListKindState::Unseen => Self::Unseen,
            TopicListKindState::Hot => Self::Hot,
            TopicListKindState::Top => Self::Top,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicListQueryState {
    pub kind: TopicListKindState,
    pub page: Option<u32>,
    pub topic_ids: Vec<u64>,
    pub order: Option<String>,
    pub ascending: Option<bool>,
    pub category_slug: Option<String>,
    pub category_id: Option<u64>,
    pub parent_category_slug: Option<String>,
    pub tag: Option<String>,
    pub additional_tags: Vec<String>,
    pub match_all_tags: bool,
}

impl From<TopicListQuery> for TopicListQueryState {
    fn from(value: TopicListQuery) -> Self {
        Self {
            kind: value.kind.into(),
            page: value.page,
            topic_ids: value.topic_ids,
            order: value.order,
            ascending: value.ascending,
            category_slug: value.category_slug,
            category_id: value.category_id,
            parent_category_slug: value.parent_category_slug,
            tag: value.tag,
            additional_tags: value.additional_tags,
            match_all_tags: value.match_all_tags,
        }
    }
}

impl From<TopicListQueryState> for TopicListQuery {
    fn from(value: TopicListQueryState) -> Self {
        Self {
            kind: value.kind.into(),
            page: value.page,
            topic_ids: value.topic_ids,
            order: value.order,
            ascending: value.ascending,
            category_slug: value.category_slug,
            category_id: value.category_id,
            parent_category_slug: value.parent_category_slug,
            tag: value.tag,
            additional_tags: value.additional_tags,
            match_all_tags: value.match_all_tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicUserState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicUser> for TopicUserState {
    fn from(value: TopicUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPosterState {
    pub user_id: u64,
    pub description: Option<String>,
    pub extras: Option<String>,
}

impl From<TopicPoster> for TopicPosterState {
    fn from(value: TopicPoster) -> Self {
        Self {
            user_id: value.user_id,
            description: value.description,
            extras: value.extras,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTagState {
    pub id: Option<u64>,
    pub name: String,
    pub slug: Option<String>,
}

impl From<TopicTag> for TopicTagState {
    fn from(value: TopicTag) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicSummaryState {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub reply_count: u32,
    pub views: u32,
    pub like_count: u32,
    pub excerpt: Option<String>,
    pub created_at: Option<String>,
    pub last_posted_at: Option<String>,
    pub last_poster_username: Option<String>,
    pub category_id: Option<u64>,
    pub pinned: bool,
    pub visible: bool,
    pub closed: bool,
    pub archived: bool,
    pub tags: Vec<TopicTagState>,
    pub posters: Vec<TopicPosterState>,
    pub unseen: bool,
    pub unread_posts: u32,
    pub new_posts: u32,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
    pub bookmarked_post_number: Option<u32>,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub bookmarkable_type: Option<String>,
    pub has_accepted_answer: bool,
    pub can_have_answer: bool,
}

impl From<TopicSummary> for TopicSummaryState {
    fn from(value: TopicSummary) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            reply_count: value.reply_count,
            views: value.views,
            like_count: value.like_count,
            excerpt: value.excerpt,
            created_at: value.created_at,
            last_posted_at: value.last_posted_at,
            last_poster_username: value.last_poster_username,
            category_id: value.category_id,
            pinned: value.pinned,
            visible: value.visible,
            closed: value.closed,
            archived: value.archived,
            tags: value.tags.into_iter().map(Into::into).collect(),
            posters: value.posters.into_iter().map(Into::into).collect(),
            unseen: value.unseen,
            unread_posts: value.unread_posts,
            new_posts: value.new_posts,
            last_read_post_number: value.last_read_post_number,
            highest_post_number: value.highest_post_number,
            bookmarked_post_number: value.bookmarked_post_number,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            bookmarkable_type: value.bookmarkable_type,
            has_accepted_answer: value.has_accepted_answer,
            can_have_answer: value.can_have_answer,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicRowState {
    pub topic: TopicSummaryState,
    pub excerpt_text: Option<String>,
    pub original_poster_username: Option<String>,
    pub original_poster_avatar_template: Option<String>,
    pub tag_names: Vec<String>,
    pub status_labels: Vec<String>,
    pub is_pinned: bool,
    pub is_closed: bool,
    pub is_archived: bool,
    pub has_accepted_answer: bool,
    pub has_unread_posts: bool,
    pub created_timestamp_unix_ms: Option<u64>,
    pub activity_timestamp_unix_ms: Option<u64>,
    pub last_poster_username: Option<String>,
}

impl From<TopicRow> for TopicRowState {
    fn from(value: TopicRow) -> Self {
        Self {
            topic: value.topic.into(),
            excerpt_text: value.excerpt_text,
            original_poster_username: value.original_poster_username,
            original_poster_avatar_template: value.original_poster_avatar_template,
            tag_names: value.tag_names,
            status_labels: value.status_labels,
            is_pinned: value.is_pinned,
            is_closed: value.is_closed,
            is_archived: value.is_archived,
            has_accepted_answer: value.has_accepted_answer,
            has_unread_posts: value.has_unread_posts,
            created_timestamp_unix_ms: value.created_timestamp_unix_ms,
            activity_timestamp_unix_ms: value.activity_timestamp_unix_ms,
            last_poster_username: value.last_poster_username,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicListState {
    pub topics: Vec<TopicSummaryState>,
    pub users: Vec<TopicUserState>,
    pub rows: Vec<TopicRowState>,
    pub more_topics_url: Option<String>,
    pub next_page: Option<u32>,
}

impl From<TopicListResponse> for TopicListState {
    fn from(value: TopicListResponse) -> Self {
        Self {
            topics: value.topics.into_iter().map(Into::into).collect(),
            users: value.users.into_iter().map(Into::into).collect(),
            rows: value.rows.into_iter().map(Into::into).collect(),
            more_topics_url: value.more_topics_url,
            next_page: value.next_page,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum SearchTypeFilterState {
    Topic,
    Post,
    User,
    Category,
    Tag,
}

impl From<SearchTypeFilter> for SearchTypeFilterState {
    fn from(value: SearchTypeFilter) -> Self {
        match value {
            SearchTypeFilter::Topic => Self::Topic,
            SearchTypeFilter::Post => Self::Post,
            SearchTypeFilter::User => Self::User,
            SearchTypeFilter::Category => Self::Category,
            SearchTypeFilter::Tag => Self::Tag,
        }
    }
}

impl From<SearchTypeFilterState> for SearchTypeFilter {
    fn from(value: SearchTypeFilterState) -> Self {
        match value {
            SearchTypeFilterState::Topic => Self::Topic,
            SearchTypeFilterState::Post => Self::Post,
            SearchTypeFilterState::User => Self::User,
            SearchTypeFilterState::Category => Self::Category,
            SearchTypeFilterState::Tag => Self::Tag,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchQueryState {
    pub q: String,
    pub page: Option<u32>,
    pub type_filter: Option<SearchTypeFilterState>,
}

impl From<SearchQuery> for SearchQueryState {
    fn from(value: SearchQuery) -> Self {
        Self {
            q: value.q,
            page: value.page,
            type_filter: value.type_filter.map(Into::into),
        }
    }
}

impl From<SearchQueryState> for SearchQuery {
    fn from(value: SearchQueryState) -> Self {
        Self {
            q: value.q,
            page: value.page,
            type_filter: value.type_filter.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchTopicState {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub category_id: Option<u64>,
    pub tags: Vec<String>,
    pub posts_count: u32,
    pub views: u32,
    pub closed: bool,
    pub archived: bool,
}

impl From<SearchTopic> for SearchTopicState {
    fn from(value: SearchTopic) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            category_id: value.category_id,
            tags: value.tags,
            posts_count: value.posts_count,
            views: value.views,
            closed: value.closed,
            archived: value.archived,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchPostState {
    pub id: u64,
    pub topic_id: Option<u64>,
    pub username: String,
    pub avatar_template: Option<String>,
    pub created_at: Option<String>,
    pub created_timestamp_unix_ms: Option<u64>,
    pub like_count: u32,
    pub blurb: String,
    pub post_number: u32,
    pub topic_title_headline: Option<String>,
}

impl From<SearchPost> for SearchPostState {
    fn from(value: SearchPost) -> Self {
        Self {
            id: value.id,
            topic_id: value.topic_id,
            username: value.username,
            avatar_template: value.avatar_template,
            created_at: value.created_at,
            created_timestamp_unix_ms: value.created_timestamp_unix_ms,
            like_count: value.like_count,
            blurb: value.blurb,
            post_number: value.post_number,
            topic_title_headline: value.topic_title_headline,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<SearchUser> for SearchUserState {
    fn from(value: SearchUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct GroupedSearchResultState {
    pub term: String,
    pub more_posts: bool,
    pub more_users: bool,
    pub more_categories: bool,
    pub more_full_page_results: bool,
    pub search_log_id: Option<u64>,
}

impl From<GroupedSearchResult> for GroupedSearchResultState {
    fn from(value: GroupedSearchResult) -> Self {
        Self {
            term: value.term,
            more_posts: value.more_posts,
            more_users: value.more_users,
            more_categories: value.more_categories,
            more_full_page_results: value.more_full_page_results,
            search_log_id: value.search_log_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchResultState {
    pub posts: Vec<SearchPostState>,
    pub topics: Vec<SearchTopicState>,
    pub users: Vec<SearchUserState>,
    pub grouped_result: GroupedSearchResultState,
}

impl From<SearchResult> for SearchResultState {
    fn from(value: SearchResult) -> Self {
        Self {
            posts: value.posts.into_iter().map(Into::into).collect(),
            topics: value.topics.into_iter().map(Into::into).collect(),
            users: value.users.into_iter().map(Into::into).collect(),
            grouped_result: value.grouped_result.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TagSearchQueryState {
    pub q: Option<String>,
    pub filter_for_input: bool,
    pub limit: Option<u32>,
    pub category_id: Option<u64>,
    pub selected_tags: Vec<String>,
}

impl From<TagSearchQuery> for TagSearchQueryState {
    fn from(value: TagSearchQuery) -> Self {
        Self {
            q: value.q,
            filter_for_input: value.filter_for_input,
            limit: value.limit,
            category_id: value.category_id,
            selected_tags: value.selected_tags,
        }
    }
}

impl From<TagSearchQueryState> for TagSearchQuery {
    fn from(value: TagSearchQueryState) -> Self {
        Self {
            q: value.q,
            filter_for_input: value.filter_for_input,
            limit: value.limit,
            category_id: value.category_id,
            selected_tags: value.selected_tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TagSearchItemState {
    pub name: String,
    pub text: String,
    pub count: u32,
}

impl From<TagSearchItem> for TagSearchItemState {
    fn from(value: TagSearchItem) -> Self {
        Self {
            name: value.name,
            text: value.text,
            count: value.count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct RequiredTagGroupState {
    pub name: String,
    pub min_count: u32,
}

impl From<RequiredTagGroup> for RequiredTagGroupState {
    fn from(value: RequiredTagGroup) -> Self {
        Self {
            name: value.name,
            min_count: value.min_count,
        }
    }
}

impl From<RequiredTagGroupState> for RequiredTagGroup {
    fn from(value: RequiredTagGroupState) -> Self {
        Self {
            name: value.name,
            min_count: value.min_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TagSearchResultState {
    pub results: Vec<TagSearchItemState>,
    pub required_tag_group: Option<RequiredTagGroupState>,
}

impl From<TagSearchResult> for TagSearchResultState {
    fn from(value: TagSearchResult) -> Self {
        Self {
            results: value.results.into_iter().map(Into::into).collect(),
            required_tag_group: value.required_tag_group.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserMentionQueryState {
    pub term: String,
    pub include_groups: bool,
    pub limit: u32,
    pub topic_id: Option<u64>,
    pub category_id: Option<u64>,
}

impl From<UserMentionQuery> for UserMentionQueryState {
    fn from(value: UserMentionQuery) -> Self {
        Self {
            term: value.term,
            include_groups: value.include_groups,
            limit: value.limit,
            topic_id: value.topic_id,
            category_id: value.category_id,
        }
    }
}

impl From<UserMentionQueryState> for UserMentionQuery {
    fn from(value: UserMentionQueryState) -> Self {
        Self {
            term: value.term,
            include_groups: value.include_groups,
            limit: value.limit,
            topic_id: value.topic_id,
            category_id: value.category_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserMentionUserState {
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub priority_group: Option<u32>,
}

impl From<UserMentionUser> for UserMentionUserState {
    fn from(value: UserMentionUser) -> Self {
        Self {
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            priority_group: value.priority_group,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserMentionGroupState {
    pub name: String,
    pub full_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub user_count: Option<u32>,
}

impl From<UserMentionGroup> for UserMentionGroupState {
    fn from(value: UserMentionGroup) -> Self {
        Self {
            name: value.name,
            full_name: value.full_name,
            flair_url: value.flair_url,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            user_count: value.user_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserMentionResultState {
    pub users: Vec<UserMentionUserState>,
    pub groups: Vec<UserMentionGroupState>,
}

impl From<UserMentionResult> for UserMentionResultState {
    fn from(value: UserMentionResult) -> Self {
        Self {
            users: value.users.into_iter().map(Into::into).collect(),
            groups: value.groups.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailQueryState {
    pub topic_id: u64,
    pub post_number: Option<u32>,
    pub track_visit: bool,
    pub filter: Option<String>,
    pub username_filters: Option<String>,
    pub filter_top_level_replies: bool,
}

impl From<TopicDetailQuery> for TopicDetailQueryState {
    fn from(value: TopicDetailQuery) -> Self {
        Self {
            topic_id: value.topic_id,
            post_number: value.post_number,
            track_visit: value.track_visit,
            filter: value.filter,
            username_filters: value.username_filters,
            filter_top_level_replies: value.filter_top_level_replies,
        }
    }
}

impl From<TopicDetailQueryState> for TopicDetailQuery {
    fn from(value: TopicDetailQueryState) -> Self {
        Self {
            topic_id: value.topic_id,
            post_number: value.post_number,
            track_visit: value.track_visit,
            filter: value.filter,
            username_filters: value.username_filters,
            filter_top_level_replies: value.filter_top_level_replies,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicReactionState {
    pub id: String,
    pub kind: Option<String>,
    pub count: u32,
    pub can_undo: Option<bool>,
}

impl From<TopicReaction> for TopicReactionState {
    fn from(value: TopicReaction) -> Self {
        Self {
            id: value.id,
            kind: value.kind,
            count: value.count,
            can_undo: value.can_undo,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PollOptionState {
    pub id: String,
    pub html: String,
    pub votes: u32,
}

impl From<PollOption> for PollOptionState {
    fn from(value: PollOption) -> Self {
        Self {
            id: value.id,
            html: value.html,
            votes: value.votes,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PollState {
    pub id: u64,
    pub name: String,
    pub kind: String,
    pub status: String,
    pub results: String,
    pub options: Vec<PollOptionState>,
    pub voters: u32,
    pub user_votes: Vec<String>,
}

impl From<Poll> for PollState {
    fn from(value: Poll) -> Self {
        Self {
            id: value.id,
            name: value.name,
            kind: value.kind,
            status: value.status,
            results: value.results,
            options: value.options.into_iter().map(Into::into).collect(),
            voters: value.voters,
            user_votes: value.user_votes,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicReplyRequestState {
    pub topic_id: u64,
    pub raw: String,
    pub reply_to_post_number: Option<u32>,
}

impl From<TopicReplyRequestState> for TopicReplyRequest {
    fn from(value: TopicReplyRequestState) -> Self {
        Self {
            topic_id: value.topic_id,
            raw: value.raw,
            reply_to_post_number: value.reply_to_post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicCreateRequestState {
    pub title: String,
    pub raw: String,
    pub category_id: u64,
    pub tags: Vec<String>,
}

impl From<TopicCreateRequestState> for TopicCreateRequest {
    fn from(value: TopicCreateRequestState) -> Self {
        Self {
            title: value.title,
            raw: value.raw,
            category_id: value.category_id,
            tags: value.tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicUpdateRequestState {
    pub topic_id: u64,
    pub title: String,
    pub category_id: u64,
    pub tags: Vec<String>,
}

impl From<TopicUpdateRequestState> for TopicUpdateRequest {
    fn from(value: TopicUpdateRequestState) -> Self {
        Self {
            topic_id: value.topic_id,
            title: value.title,
            category_id: value.category_id,
            tags: value.tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PostUpdateRequestState {
    pub post_id: u64,
    pub raw: String,
    pub edit_reason: Option<String>,
}

impl From<PostUpdateRequestState> for PostUpdateRequest {
    fn from(value: PostUpdateRequestState) -> Self {
        Self {
            post_id: value.post_id,
            raw: value.raw,
            edit_reason: value.edit_reason,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct InviteCreateRequestState {
    pub max_redemptions_allowed: u32,
    pub expires_at: Option<String>,
    pub description: Option<String>,
    pub email: Option<String>,
}

impl From<InviteCreateRequestState> for InviteCreateRequest {
    fn from(value: InviteCreateRequestState) -> Self {
        Self {
            max_redemptions_allowed: value.max_redemptions_allowed,
            expires_at: value.expires_at,
            description: value.description,
            email: value.email,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DraftDataState {
    pub reply: Option<String>,
    pub title: Option<String>,
    pub category_id: Option<u64>,
    pub tags: Vec<String>,
    pub reply_to_post_number: Option<u32>,
    pub action: Option<String>,
    pub recipients: Vec<String>,
    pub archetype_id: Option<String>,
    pub composer_time: Option<u32>,
    pub typing_time: Option<u32>,
}

impl From<DraftData> for DraftDataState {
    fn from(value: DraftData) -> Self {
        Self {
            reply: value.reply,
            title: value.title,
            category_id: value.category_id,
            tags: value.tags,
            reply_to_post_number: value.reply_to_post_number,
            action: value.action,
            recipients: value.recipients,
            archetype_id: value.archetype_id,
            composer_time: value.composer_time,
            typing_time: value.typing_time,
        }
    }
}

impl From<DraftDataState> for DraftData {
    fn from(value: DraftDataState) -> Self {
        Self {
            reply: value.reply,
            title: value.title,
            category_id: value.category_id,
            tags: value.tags,
            reply_to_post_number: value.reply_to_post_number,
            action: value.action,
            recipients: value.recipients,
            archetype_id: value.archetype_id,
            composer_time: value.composer_time,
            typing_time: value.typing_time,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DraftState {
    pub draft_key: String,
    pub data: DraftDataState,
    pub sequence: u32,
    pub title: Option<String>,
    pub excerpt: Option<String>,
    pub updated_at: Option<String>,
    pub username: Option<String>,
    pub avatar_template: Option<String>,
    pub topic_id: Option<u64>,
}

impl From<Draft> for DraftState {
    fn from(value: Draft) -> Self {
        Self {
            draft_key: value.draft_key,
            data: value.data.into(),
            sequence: value.sequence,
            title: value.title,
            excerpt: value.excerpt,
            updated_at: value.updated_at,
            username: value.username,
            avatar_template: value.avatar_template,
            topic_id: value.topic_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DraftListResponseState {
    pub drafts: Vec<DraftState>,
    pub has_more: bool,
}

impl From<DraftListResponse> for DraftListResponseState {
    fn from(value: DraftListResponse) -> Self {
        Self {
            drafts: value.drafts.into_iter().map(Into::into).collect(),
            has_more: value.has_more,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UploadImageRequestState {
    pub file_name: String,
    pub mime_type: Option<String>,
    pub bytes: Vec<u8>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UploadResultState {
    pub short_url: String,
    pub url: Option<String>,
    pub original_filename: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

impl From<UploadResult> for UploadResultState {
    fn from(value: UploadResult) -> Self {
        Self {
            short_url: value.short_url,
            url: value.url,
            original_filename: value.original_filename,
            width: value.width,
            height: value.height,
            thumbnail_width: value.thumbnail_width,
            thumbnail_height: value.thumbnail_height,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ResolvedUploadUrlState {
    pub short_url: String,
    pub short_path: Option<String>,
    pub url: Option<String>,
}

impl From<ResolvedUploadUrl> for ResolvedUploadUrlState {
    fn from(value: ResolvedUploadUrl) -> Self {
        Self {
            short_url: value.short_url,
            short_path: value.short_path,
            url: value.url,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTimingEntryState {
    pub post_number: u32,
    pub milliseconds: u32,
}

impl From<TopicTimingEntryState> for TopicTimingEntry {
    fn from(value: TopicTimingEntryState) -> Self {
        Self {
            post_number: value.post_number,
            milliseconds: value.milliseconds,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTimingsRequestState {
    pub topic_id: u64,
    pub topic_time_ms: u32,
    pub timings: Vec<TopicTimingEntryState>,
}

impl From<TopicTimingsRequestState> for TopicTimingsRequest {
    fn from(value: TopicTimingsRequestState) -> Self {
        Self {
            topic_id: value.topic_id,
            topic_time_ms: value.topic_time_ms,
            timings: value.timings.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PostReactionUpdateState {
    pub reactions: Vec<TopicReactionState>,
    pub current_user_reaction: Option<TopicReactionState>,
}

impl From<PostReactionUpdate> for PostReactionUpdateState {
    fn from(value: PostReactionUpdate) -> Self {
        Self {
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub cooked: String,
    pub raw: Option<String>,
    pub post_number: u32,
    pub post_type: i32,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub like_count: u32,
    pub reply_count: u32,
    pub reply_to_post_number: Option<u32>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub reactions: Vec<TopicReactionState>,
    pub current_user_reaction: Option<TopicReactionState>,
    pub polls: Vec<PollState>,
    pub accepted_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub hidden: bool,
}

impl From<TopicPost> for TopicPostState {
    fn from(value: TopicPost) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            cooked: value.cooked,
            raw: value.raw,
            post_number: value.post_number,
            post_type: value.post_type,
            created_at: value.created_at,
            updated_at: value.updated_at,
            like_count: value.like_count,
            reply_count: value.reply_count,
            reply_to_post_number: value.reply_to_post_number,
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
            polls: value.polls.into_iter().map(Into::into).collect(),
            accepted_answer: value.accepted_answer,
            can_edit: value.can_edit,
            can_delete: value.can_delete,
            can_recover: value.can_recover,
            hidden: value.hidden,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostStreamState {
    pub posts: Vec<TopicPostState>,
    pub stream: Vec<u64>,
}

impl From<TopicPostStream> for TopicPostStreamState {
    fn from(value: TopicPostStream) -> Self {
        Self {
            posts: value.posts.into_iter().map(Into::into).collect(),
            stream: value.stream,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadReplyState {
    pub post_number: u32,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
}

impl From<TopicThreadReply> for TopicThreadReplyState {
    fn from(value: TopicThreadReply) -> Self {
        Self {
            post_number: value.post_number,
            depth: value.depth,
            parent_post_number: value.parent_post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadSectionState {
    pub anchor_post_number: u32,
    pub replies: Vec<TopicThreadReplyState>,
}

impl From<TopicThreadSection> for TopicThreadSectionState {
    fn from(value: TopicThreadSection) -> Self {
        Self {
            anchor_post_number: value.anchor_post_number,
            replies: value.replies.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadState {
    pub original_post_number: Option<u32>,
    pub reply_sections: Vec<TopicThreadSectionState>,
}

impl From<TopicThread> for TopicThreadState {
    fn from(value: TopicThread) -> Self {
        Self {
            original_post_number: value.original_post_number,
            reply_sections: value.reply_sections.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadFlatPostState {
    pub post: TopicPostState,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
    pub shows_thread_line: bool,
    pub is_original_post: bool,
}

impl From<TopicThreadFlatPost> for TopicThreadFlatPostState {
    fn from(value: TopicThreadFlatPost) -> Self {
        Self {
            post: value.post.into(),
            depth: value.depth,
            parent_post_number: value.parent_post_number,
            shows_thread_line: value.shows_thread_line,
            is_original_post: value.is_original_post,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailCreatedByState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicDetailCreatedBy> for TopicDetailCreatedByState {
    fn from(value: TopicDetailCreatedBy) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailMetaState {
    pub notification_level: Option<i32>,
    pub can_edit: bool,
    pub created_by: Option<TopicDetailCreatedByState>,
}

impl From<TopicDetailMeta> for TopicDetailMetaState {
    fn from(value: TopicDetailMeta) -> Self {
        Self {
            notification_level: value.notification_level,
            can_edit: value.can_edit,
            created_by: value.created_by.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailState {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTagState>,
    pub views: u32,
    pub like_count: u32,
    pub interaction_count: u32,
    pub created_at: Option<String>,
    pub last_read_post_number: Option<u32>,
    pub bookmarks: Vec<u64>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub accepted_answer: bool,
    pub has_accepted_answer: bool,
    pub can_vote: bool,
    pub vote_count: i32,
    pub user_voted: bool,
    pub summarizable: bool,
    pub has_cached_summary: bool,
    pub has_summary: bool,
    pub archetype: Option<String>,
    pub post_stream: TopicPostStreamState,
    pub thread: TopicThreadState,
    pub flat_posts: Vec<TopicThreadFlatPostState>,
    pub details: TopicDetailMetaState,
}

impl From<TopicDetail> for TopicDetailState {
    fn from(value: TopicDetail) -> Self {
        let interaction_count = value.interaction_count();
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            category_id: value.category_id,
            tags: value.tags.into_iter().map(Into::into).collect(),
            views: value.views,
            like_count: value.like_count,
            interaction_count,
            created_at: value.created_at,
            last_read_post_number: value.last_read_post_number,
            bookmarks: value.bookmarks,
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            accepted_answer: value.accepted_answer,
            has_accepted_answer: value.has_accepted_answer,
            can_vote: value.can_vote,
            vote_count: value.vote_count,
            user_voted: value.user_voted,
            summarizable: value.summarizable,
            has_cached_summary: value.has_cached_summary,
            has_summary: value.has_summary,
            archetype: value.archetype,
            post_stream: value.post_stream.into(),
            thread: value.thread.into(),
            flat_posts: value.flat_posts.into_iter().map(Into::into).collect(),
            details: value.details.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LogFileSummaryState {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
}

impl From<FireLogFileSummary> for LogFileSummaryState {
    fn from(value: FireLogFileSummary) -> Self {
        Self {
            relative_path: value.relative_path,
            file_name: value.file_name,
            size_bytes: value.size_bytes,
            modified_at_unix_ms: value.modified_at_unix_ms,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LogFileDetailState {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub contents: String,
    pub is_truncated: bool,
}

impl From<FireLogFileDetail> for LogFileDetailState {
    fn from(value: FireLogFileDetail) -> Self {
        Self {
            relative_path: value.relative_path,
            file_name: value.file_name,
            size_bytes: value.size_bytes,
            modified_at_unix_ms: value.modified_at_unix_ms,
            contents: value.contents,
            is_truncated: value.is_truncated,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum DiagnosticsPageDirectionState {
    Older,
    Newer,
}

impl From<DiagnosticsPageDirectionState> for DiagnosticsPageDirection {
    fn from(value: DiagnosticsPageDirectionState) -> Self {
        match value {
            DiagnosticsPageDirectionState::Older => Self::Older,
            DiagnosticsPageDirectionState::Newer => Self::Newer,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DiagnosticsTextPageState {
    pub text: String,
    pub start_offset: u64,
    pub end_offset: u64,
    pub total_bytes: u64,
    pub next_cursor: Option<u64>,
    pub has_more_older: bool,
    pub has_more_newer: bool,
    pub is_head_aligned: bool,
    pub is_tail_aligned: bool,
}

impl From<DiagnosticsTextPage> for DiagnosticsTextPageState {
    fn from(value: DiagnosticsTextPage) -> Self {
        Self {
            text: value.text,
            start_offset: value.start_offset,
            end_offset: value.end_offset,
            total_bytes: value.total_bytes,
            next_cursor: value.next_cursor,
            has_more_older: value.has_more_older,
            has_more_newer: value.has_more_newer,
            is_head_aligned: value.is_head_aligned,
            is_tail_aligned: value.is_tail_aligned,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LogFilePageState {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub page: DiagnosticsTextPageState,
}

impl From<FireLogFilePage> for LogFilePageState {
    fn from(value: FireLogFilePage) -> Self {
        Self {
            relative_path: value.relative_path,
            file_name: value.file_name,
            size_bytes: value.size_bytes,
            modified_at_unix_ms: value.modified_at_unix_ms,
            page: value.page.into(),
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum HostLogLevelState {
    Debug,
    Info,
    Warn,
    Error,
}

impl From<HostLogLevelState> for FireHostLogLevel {
    fn from(value: HostLogLevelState) -> Self {
        match value {
            HostLogLevelState::Debug => Self::Debug,
            HostLogLevelState::Info => Self::Info,
            HostLogLevelState::Warn => Self::Warn,
            HostLogLevelState::Error => Self::Error,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum NetworkTraceOutcomeState {
    InProgress,
    Succeeded,
    Failed,
    Cancelled,
}

impl From<NetworkTraceOutcome> for NetworkTraceOutcomeState {
    fn from(value: NetworkTraceOutcome) -> Self {
        match value {
            NetworkTraceOutcome::InProgress => Self::InProgress,
            NetworkTraceOutcome::Succeeded => Self::Succeeded,
            NetworkTraceOutcome::Failed => Self::Failed,
            NetworkTraceOutcome::Cancelled => Self::Cancelled,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceHeaderState {
    pub name: String,
    pub value: String,
}

impl From<NetworkTraceHeader> for NetworkTraceHeaderState {
    fn from(value: NetworkTraceHeader) -> Self {
        Self {
            name: value.name,
            value: value.value,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceEventState {
    pub sequence: u32,
    pub timestamp_unix_ms: u64,
    pub phase: String,
    pub summary: String,
    pub details: Option<String>,
}

impl From<NetworkTraceEvent> for NetworkTraceEventState {
    fn from(value: NetworkTraceEvent) -> Self {
        Self {
            sequence: value.sequence,
            timestamp_unix_ms: value.timestamp_unix_ms,
            phase: value.phase,
            summary: value.summary,
            details: value.details,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceSummaryState {
    pub id: u64,
    pub call_id: Option<u64>,
    pub operation: String,
    pub method: String,
    pub url: String,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub duration_ms: Option<u64>,
    pub outcome: NetworkTraceOutcomeState,
    pub status_code: Option<u16>,
    pub error_message: Option<String>,
    pub response_content_type: Option<String>,
    pub response_body_truncated: bool,
}

impl From<NetworkTraceSummary> for NetworkTraceSummaryState {
    fn from(value: NetworkTraceSummary) -> Self {
        Self {
            id: value.id,
            call_id: value.call_id,
            operation: value.operation,
            method: value.method,
            url: value.url,
            started_at_unix_ms: value.started_at_unix_ms,
            finished_at_unix_ms: value.finished_at_unix_ms,
            duration_ms: value.duration_ms,
            outcome: value.outcome.into(),
            status_code: value.status_code,
            error_message: value.error_message,
            response_content_type: value.response_content_type,
            response_body_truncated: value.response_body_truncated,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceDetailState {
    pub summary: NetworkTraceSummaryState,
    pub request_headers: Vec<NetworkTraceHeaderState>,
    pub response_headers: Vec<NetworkTraceHeaderState>,
    pub response_body: Option<String>,
    pub response_body_truncated: bool,
    pub response_body_storage_truncated: bool,
    pub response_body_stored_bytes: Option<u64>,
    pub response_body_page_available: bool,
    pub response_body_bytes: Option<u64>,
    pub events: Vec<NetworkTraceEventState>,
}

impl From<NetworkTraceDetail> for NetworkTraceDetailState {
    fn from(value: NetworkTraceDetail) -> Self {
        Self {
            summary: NetworkTraceSummaryState {
                id: value.id,
                call_id: value.call_id,
                operation: value.operation,
                method: value.method,
                url: value.url,
                started_at_unix_ms: value.started_at_unix_ms,
                finished_at_unix_ms: value.finished_at_unix_ms,
                duration_ms: value.duration_ms,
                outcome: value.outcome.into(),
                status_code: value.status_code,
                error_message: value.error_message,
                response_content_type: value.response_content_type,
                response_body_truncated: value.response_body_truncated,
            },
            request_headers: value.request_headers.into_iter().map(Into::into).collect(),
            response_headers: value.response_headers.into_iter().map(Into::into).collect(),
            response_body: value.response_body,
            response_body_truncated: value.response_body_truncated,
            response_body_storage_truncated: value.response_body_storage_truncated,
            response_body_stored_bytes: value.response_body_stored_bytes,
            response_body_page_available: value.response_body_page_available,
            response_body_bytes: value.response_body_bytes,
            events: value.events.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceBodyPageState {
    pub trace_id: u64,
    pub response_content_type: Option<String>,
    pub response_body_storage_truncated: bool,
    pub response_body_stored_bytes: Option<u64>,
    pub page: DiagnosticsTextPageState,
}

impl From<NetworkTraceBodyPage> for NetworkTraceBodyPageState {
    fn from(value: NetworkTraceBodyPage) -> Self {
        Self {
            trace_id: value.trace_id,
            response_content_type: value.response_content_type,
            response_body_storage_truncated: value.response_body_storage_truncated,
            response_body_stored_bytes: value.response_body_stored_bytes,
            page: value.page.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SupportBundleHostContextState {
    pub platform: String,
    pub app_version: Option<String>,
    pub build_number: Option<String>,
    pub scene_phase: Option<String>,
}

impl From<SupportBundleHostContextState> for FireSupportBundleHostContext {
    fn from(value: SupportBundleHostContextState) -> Self {
        Self {
            platform: value.platform,
            app_version: value.app_version,
            build_number: value.build_number,
            scene_phase: value.scene_phase,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SupportBundleExportState {
    pub file_name: String,
    pub relative_path: String,
    pub absolute_path: String,
    pub size_bytes: u64,
    pub created_at_unix_ms: u64,
    pub diagnostic_session_id: String,
}

impl From<FireSupportBundleExport> for SupportBundleExportState {
    fn from(value: FireSupportBundleExport) -> Self {
        Self {
            file_name: value.file_name,
            relative_path: value.relative_path,
            absolute_path: value.absolute_path,
            size_bytes: value.size_bytes,
            created_at_unix_ms: value.created_at_unix_ms,
            diagnostic_session_id: value.diagnostic_session_id,
        }
    }
}

// --- Profile types ---

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserProfileState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub trust_level: u32,
    pub bio_cooked: Option<String>,
    pub created_at: Option<String>,
    pub last_seen_at: Option<String>,
    pub last_posted_at: Option<String>,
    pub flair_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub profile_background_url: Option<String>,
    pub total_followers: u32,
    pub total_following: u32,
    pub can_follow: bool,
    pub is_followed: bool,
    pub gamification_score: Option<u32>,
    pub trust_level_label: String,
}

impl From<UserProfile> for UserProfileState {
    fn from(value: UserProfile) -> Self {
        let trust_level = value.trust_level.unwrap_or(0);
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            trust_level,
            bio_cooked: value.bio_cooked,
            created_at: value.created_at,
            last_seen_at: value.last_seen_at,
            last_posted_at: value.last_posted_at,
            flair_name: value.flair_name,
            flair_url: value.flair_url,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            profile_background_url: value
                .profile_background_upload_url
                .or(value.card_background_upload_url),
            total_followers: value.total_followers.unwrap_or(0),
            total_following: value.total_following.unwrap_or(0),
            can_follow: value.can_follow.unwrap_or(false),
            is_followed: value.is_followed.unwrap_or(false),
            gamification_score: value.gamification_score,
            trust_level_label: trust_level_label(trust_level),
        }
    }
}

fn trust_level_label(level: u32) -> String {
    match level {
        0 => "新人".to_string(),
        1 => "基本".to_string(),
        2 => "成员".to_string(),
        3 => "老手".to_string(),
        4 => "领导者".to_string(),
        _ => format!("TL{level}"),
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserSummaryStatsState {
    pub days_visited: u32,
    pub likes_received: u32,
    pub likes_given: u32,
    pub topic_count: u32,
    pub post_count: u32,
    pub time_read_seconds: u64,
    pub bookmark_count: u32,
}

impl From<UserSummaryStats> for UserSummaryStatsState {
    fn from(value: UserSummaryStats) -> Self {
        Self {
            days_visited: value.days_visited,
            likes_received: value.likes_received,
            likes_given: value.likes_given,
            topic_count: value.topic_count,
            post_count: value.post_count,
            time_read_seconds: value.time_read,
            bookmark_count: value.bookmark_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryTopicState {
    pub id: u64,
    pub title: String,
    pub slug: Option<String>,
    pub like_count: u32,
    pub category_id: Option<u64>,
    pub created_at: Option<String>,
}

impl From<ProfileSummaryTopic> for ProfileSummaryTopicState {
    fn from(value: ProfileSummaryTopic) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            like_count: value.like_count,
            category_id: value.category_id,
            created_at: value.created_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryReplyState {
    pub id: u64,
    pub topic_id: u64,
    pub title: Option<String>,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub post_number: Option<u32>,
}

impl From<ProfileSummaryReply> for ProfileSummaryReplyState {
    fn from(value: ProfileSummaryReply) -> Self {
        Self {
            id: value.id,
            topic_id: value.topic_id,
            title: value.title,
            like_count: value.like_count,
            created_at: value.created_at,
            post_number: value.post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryTopCategoryState {
    pub id: u64,
    pub name: Option<String>,
    pub topic_count: u32,
    pub post_count: u32,
}

impl From<ProfileSummaryTopCategory> for ProfileSummaryTopCategoryState {
    fn from(value: ProfileSummaryTopCategory) -> Self {
        Self {
            id: value.id,
            name: value.name,
            topic_count: value.topic_count,
            post_count: value.post_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryUserReferenceState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
    pub count: u32,
}

impl From<ProfileSummaryUserReference> for ProfileSummaryUserReferenceState {
    fn from(value: ProfileSummaryUserReference) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
            count: value.count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BadgeState {
    pub id: u64,
    pub name: String,
    pub description: Option<String>,
    pub badge_type_id: u32,
    pub icon: Option<String>,
    pub image_url: Option<String>,
    pub slug: Option<String>,
    pub grant_count: u32,
    pub long_description: Option<String>,
}

impl From<Badge> for BadgeState {
    fn from(value: Badge) -> Self {
        Self {
            id: value.id,
            name: value.name,
            description: value.description,
            badge_type_id: value.badge_type_id,
            icon: value.icon,
            image_url: value.image_url,
            slug: value.slug,
            grant_count: value.grant_count,
            long_description: value.long_description,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserSummaryState {
    pub stats: UserSummaryStatsState,
    pub top_topics: Vec<ProfileSummaryTopicState>,
    pub top_replies: Vec<ProfileSummaryReplyState>,
    pub top_categories: Vec<ProfileSummaryTopCategoryState>,
    pub most_liked_by_users: Vec<ProfileSummaryUserReferenceState>,
    pub badges: Vec<BadgeState>,
}

impl From<UserSummaryResponse> for UserSummaryState {
    fn from(value: UserSummaryResponse) -> Self {
        Self {
            stats: value.stats.into(),
            top_topics: value.top_topics.into_iter().map(Into::into).collect(),
            top_replies: value.top_replies.into_iter().map(Into::into).collect(),
            top_categories: value.top_categories.into_iter().map(Into::into).collect(),
            most_liked_by_users: value
                .most_liked_by_users
                .into_iter()
                .map(Into::into)
                .collect(),
            badges: value.badges.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserActionState {
    pub action_type: i32,
    pub topic_id: Option<u64>,
    pub post_number: Option<u32>,
    pub title: Option<String>,
    pub slug: Option<String>,
    pub excerpt: Option<String>,
    pub category_id: Option<u64>,
    pub acting_username: Option<String>,
    pub acting_avatar_template: Option<String>,
    pub created_at: Option<String>,
}

impl From<UserAction> for UserActionState {
    fn from(value: UserAction) -> Self {
        Self {
            action_type: value.action_type.unwrap_or(0),
            topic_id: value.topic_id,
            post_number: value.post_number,
            title: value.title,
            slug: value.slug,
            excerpt: value.excerpt,
            category_id: value.category_id,
            acting_username: value.acting_username,
            acting_avatar_template: value.acting_avatar_template,
            created_at: value.created_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct FollowUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<FollowUser> for FollowUserState {
    fn from(value: FollowUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct InviteLinkDetailsState {
    pub id: Option<u64>,
    pub invite_key: Option<String>,
    pub max_redemptions_allowed: Option<u32>,
    pub redemption_count: Option<u32>,
    pub expired: Option<bool>,
    pub created_at: Option<String>,
    pub expires_at: Option<String>,
}

impl From<InviteLinkDetails> for InviteLinkDetailsState {
    fn from(value: InviteLinkDetails) -> Self {
        Self {
            id: value.id,
            invite_key: value.invite_key,
            max_redemptions_allowed: value.max_redemptions_allowed,
            redemption_count: value.redemption_count,
            expired: value.expired,
            created_at: value.created_at,
            expires_at: value.expires_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct InviteLinkState {
    pub invite_link: String,
    pub invite: Option<InviteLinkDetailsState>,
}

impl From<InviteLink> for InviteLinkState {
    fn from(value: InviteLink) -> Self {
        Self {
            invite_link: value.invite_link,
            invite: value.invite.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct VotedUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<VotedUser> for VotedUserState {
    fn from(value: VotedUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct VoteResponseState {
    pub can_vote: bool,
    pub vote_limit: u32,
    pub vote_count: i32,
    pub votes_left: i32,
    pub alert: bool,
    pub who_voted: Vec<VotedUserState>,
}

impl From<VoteResponse> for VoteResponseState {
    fn from(value: VoteResponse) -> Self {
        Self {
            can_vote: value.can_vote,
            vote_limit: value.vote_limit,
            vote_count: value.vote_count,
            votes_left: value.votes_left,
            alert: value.alert,
            who_voted: value.who_voted.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Error, thiserror::Error, Debug)]
pub enum FireUniFfiError {
    #[error("configuration error: {details}")]
    Configuration { details: String },
    #[error("validation error: {details}")]
    Validation { details: String },
    #[error("authentication error: {details}")]
    Authentication { details: String },
    #[error("login required: {details}")]
    LoginRequired { details: String },
    #[error("network error: {details}")]
    Network { details: String },
    #[error("request requires Cloudflare challenge verification")]
    CloudflareChallenge,
    #[error("{operation} failed with HTTP {status}: {body}")]
    HttpStatus {
        operation: String,
        status: u16,
        body: String,
    },
    #[error("storage error: {details}")]
    Storage { details: String },
    #[error("serialization error: {details}")]
    Serialization { details: String },
    #[error("runtime error: {details}")]
    Runtime { details: String },
    #[error("internal error: {details}")]
    Internal { details: String },
}

impl From<FireCoreError> for FireUniFfiError {
    fn from(value: FireCoreError) -> Self {
        match value {
            FireCoreError::InvalidUrl(source) => Self::Configuration {
                details: source.to_string(),
            },
            FireCoreError::RequestBuild(source) => Self::Internal {
                details: source.to_string(),
            },
            FireCoreError::ClientBuild { source } | FireCoreError::Network { source } => {
                Self::Network {
                    details: source.to_string(),
                }
            }
            FireCoreError::Logger(source) => Self::Configuration {
                details: source.to_string(),
            },
            FireCoreError::LoginRequired { message, .. } => {
                Self::LoginRequired { details: message }
            }
            FireCoreError::CloudflareChallenge { .. } => Self::CloudflareChallenge,
            FireCoreError::HttpStatus {
                operation,
                status,
                body,
            } => Self::HttpStatus {
                operation: operation.to_string(),
                status,
                body,
            },
            FireCoreError::ResponseDeserialize { source, .. } => Self::Serialization {
                details: source.to_string(),
            },
            FireCoreError::MissingCurrentUsername => Self::Authentication {
                details: "logout requires a current username".to_string(),
            },
            FireCoreError::MissingCurrentUserId => Self::Authentication {
                details: "request requires a current user id".to_string(),
            },
            FireCoreError::MissingLoginSession => Self::Authentication {
                details: "request requires a login session".to_string(),
            },
            FireCoreError::MissingSharedSessionKey => Self::Authentication {
                details: "message bus requires a shared session key".to_string(),
            },
            FireCoreError::MissingMessageBusSubscription => Self::Validation {
                details: "message bus requires at least one subscribed channel".to_string(),
            },
            FireCoreError::MessageBusNotStarted => Self::Validation {
                details: "message bus has not been started".to_string(),
            },
            FireCoreError::MissingCsrfToken => Self::Authentication {
                details: "request requires a csrf token".to_string(),
            },
            FireCoreError::PostEnqueued { pending_count } => Self::Validation {
                details: format!("post is pending review (pending_count={pending_count})"),
            },
            FireCoreError::MissingWorkspacePath => Self::Configuration {
                details: "fire workspace path is not configured".to_string(),
            },
            FireCoreError::InvalidWorkspaceRelativePath { path } => Self::Validation {
                details: format!(
                    "workspace relative path must stay under the configured root: {}",
                    path.display()
                ),
            },
            FireCoreError::WorkspaceIo { path, source }
            | FireCoreError::PersistIo { path, source }
            | FireCoreError::DiagnosticsIo { path, source } => Self::Storage {
                details: format!("{}: {}", path.display(), source),
            },
            FireCoreError::LoggerWorkspaceMismatch { expected, found } => Self::Configuration {
                details: format!(
                    "logger workspace mismatch: expected {}, found {}",
                    expected.display(),
                    found.display()
                ),
            },
            FireCoreError::InvalidCsrfResponse => Self::Validation {
                details: "csrf response did not contain a usable token".to_string(),
            },
            FireCoreError::PersistSerialize(source)
            | FireCoreError::PersistDeserialize(source)
            | FireCoreError::DiagnosticsSerialize(source)
            | FireCoreError::DiagnosticsDeserialize(source) => Self::Serialization {
                details: source.to_string(),
            },
            FireCoreError::DiagnosticsTraceNotFound { trace_id } => Self::Validation {
                details: format!("network request trace not found: {trace_id}"),
            },
            FireCoreError::PersistVersionMismatch { expected, found } => Self::Validation {
                details: format!(
                    "persisted session uses unsupported version {found}, expected {expected}"
                ),
            },
            FireCoreError::PersistBaseUrlMismatch { expected, found } => Self::Validation {
                details: format!(
                    "persisted session base url mismatch: expected {expected}, found {found}"
                ),
            },
        }
    }
}

#[uniffi::export]
pub fn plain_text_from_html(raw_html: String) -> String {
    shared_plain_text_from_html(&raw_html)
}

#[uniffi::export]
pub fn preview_text_from_html(raw_html: Option<String>) -> Option<String> {
    shared_preview_text_from_html(raw_html.as_deref())
}

#[uniffi::export]
pub fn monogram_for_username(username: String) -> String {
    shared_monogram_for_username(&username)
}

#[derive(uniffi::Object)]
pub struct FireCoreHandle {
    inner: Arc<FireCore>,
    panic_state: Arc<PanicState>,
}

#[uniffi::export]
impl FireCoreHandle {
    #[uniffi::constructor]
    pub fn new(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Self, FireUniFfiError> {
        constructor_guard("constructor.new", || {
            Ok(Self {
                inner: Arc::new(FireCore::new(FireCoreConfig {
                    base_url: base_url.unwrap_or_else(|| "https://linux.do".to_string()),
                    workspace_path,
                })?),
                panic_state: Arc::new(PanicState::default()),
            })
        })
    }

    pub fn base_url(&self) -> Result<String, FireUniFfiError> {
        self.run_infallible("base_url", |inner| inner.base_url().to_string())
    }

    pub fn workspace_path(&self) -> Result<Option<String>, FireUniFfiError> {
        self.run_infallible("workspace_path", |inner| {
            inner
                .workspace_path()
                .map(|path| path.display().to_string())
        })
    }

    pub fn resolve_workspace_path(&self, relative_path: String) -> Result<String, FireUniFfiError> {
        self.run_fallible("resolve_workspace_path", move |inner| {
            inner
                .resolve_workspace_path(relative_path)
                .map(|path| path.display().to_string())
        })
    }

    pub fn diagnostic_session_id(&self) -> Result<String, FireUniFfiError> {
        self.run_infallible("diagnostic_session_id", |inner| {
            inner.diagnostic_session_id()
        })
    }

    pub fn export_support_bundle(
        &self,
        host_context: SupportBundleHostContextState,
    ) -> Result<SupportBundleExportState, FireUniFfiError> {
        self.run_fallible("export_support_bundle", move |inner| {
            inner
                .export_support_bundle(host_context.into())
                .map(Into::into)
        })
    }

    pub fn flush_logs(&self, sync: bool) -> Result<(), FireUniFfiError> {
        self.run_infallible("flush_logs", move |inner| inner.flush_logs(sync))
    }

    pub fn log_host(
        &self,
        level: HostLogLevelState,
        target: String,
        message: String,
    ) -> Result<(), FireUniFfiError> {
        self.run_infallible("log_host", move |inner| {
            inner.log_host(level.into(), target, message)
        })
    }

    pub fn list_log_files(&self) -> Result<Vec<LogFileSummaryState>, FireUniFfiError> {
        self.run_fallible("list_log_files", |inner| {
            inner
                .list_log_files()
                .map(|items| items.into_iter().map(Into::into).collect())
        })
    }

    pub fn read_log_file(
        &self,
        relative_path: String,
    ) -> Result<LogFileDetailState, FireUniFfiError> {
        self.run_fallible("read_log_file", move |inner| {
            inner.read_log_file(relative_path).map(Into::into)
        })
    }

    pub fn read_log_file_page(
        &self,
        relative_path: String,
        cursor: Option<u64>,
        max_bytes: Option<u64>,
        direction: DiagnosticsPageDirectionState,
    ) -> Result<LogFilePageState, FireUniFfiError> {
        self.run_fallible("read_log_file_page", move |inner| {
            inner
                .read_log_file_page(
                    relative_path,
                    cursor,
                    max_bytes
                        .and_then(|value| usize::try_from(value).ok())
                        .unwrap_or_default(),
                    direction.into(),
                )
                .map(Into::into)
        })
    }

    pub fn list_network_traces(
        &self,
        limit: u64,
    ) -> Result<Vec<NetworkTraceSummaryState>, FireUniFfiError> {
        self.run_infallible("list_network_traces", move |inner| {
            let limit = usize::try_from(limit).unwrap_or(usize::MAX);
            inner
                .list_network_traces(limit)
                .into_iter()
                .map(Into::into)
                .collect()
        })
    }

    pub fn network_trace_detail(
        &self,
        trace_id: u64,
    ) -> Result<Option<NetworkTraceDetailState>, FireUniFfiError> {
        self.run_infallible("network_trace_detail", move |inner| {
            inner.network_trace_detail(trace_id).map(Into::into)
        })
    }

    pub fn network_trace_body_page(
        &self,
        trace_id: u64,
        cursor: Option<u64>,
        max_bytes: Option<u64>,
        direction: DiagnosticsPageDirectionState,
    ) -> Result<Option<NetworkTraceBodyPageState>, FireUniFfiError> {
        self.run_infallible("network_trace_body_page", move |inner| {
            inner
                .network_trace_body_page(
                    trace_id,
                    cursor,
                    max_bytes
                        .and_then(|value| usize::try_from(value).ok())
                        .unwrap_or_default(),
                    direction.into(),
                )
                .map(Into::into)
        })
    }

    pub fn has_login_session(&self) -> Result<bool, FireUniFfiError> {
        self.run_infallible("has_login_session", |inner| inner.has_login_session())
    }

    pub fn snapshot(&self) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("snapshot", |inner| {
            SessionState::from_snapshot(inner.snapshot())
        })
    }

    pub fn export_session_json(&self) -> Result<String, FireUniFfiError> {
        self.run_fallible("export_session_json", |inner| inner.export_session_json())
    }

    pub fn export_redacted_session_json(&self) -> Result<String, FireUniFfiError> {
        self.run_fallible("export_redacted_session_json", |inner| {
            inner.export_redacted_session_json()
        })
    }

    pub fn restore_session_json(&self, json: String) -> Result<SessionState, FireUniFfiError> {
        self.run_fallible("restore_session_json", move |inner| {
            inner
                .restore_session_json(json)
                .map(SessionState::from_snapshot)
        })
    }

    pub fn save_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.run_fallible("save_session_to_path", move |inner| {
            inner.save_session_to_path(path)
        })
    }

    pub fn save_redacted_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.run_fallible("save_redacted_session_to_path", move |inner| {
            inner.save_redacted_session_to_path(path)
        })
    }

    pub fn load_session_from_path(&self, path: String) -> Result<SessionState, FireUniFfiError> {
        self.run_fallible("load_session_from_path", move |inner| {
            inner
                .load_session_from_path(path)
                .map(SessionState::from_snapshot)
        })
    }

    pub fn clear_session_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.run_fallible("clear_session_path", move |inner| {
            inner.clear_session_path(path)
        })
    }

    pub fn subscribe_channel(
        &self,
        subscription: MessageBusSubscriptionState,
    ) -> Result<(), FireUniFfiError> {
        self.run_fallible("subscribe_channel", move |inner| {
            inner.subscribe_message_bus_channel(subscription.into())
        })
    }

    pub fn unsubscribe_channel(
        &self,
        owner_token: String,
        channel: String,
    ) -> Result<(), FireUniFfiError> {
        self.run_fallible("unsubscribe_channel", move |inner| {
            inner.unsubscribe_message_bus_channel(owner_token, channel)
        })
    }

    pub fn stop_message_bus(&self, clear_subscriptions: bool) -> Result<(), FireUniFfiError> {
        self.run_infallible("stop_message_bus", move |inner| {
            inner.stop_message_bus(clear_subscriptions)
        })
    }

    pub async fn start_message_bus(
        &self,
        mode: MessageBusClientModeState,
        handler: Arc<dyn MessageBusEventHandler>,
    ) -> Result<String, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let (event_sender, mut event_receiver) = tokio::sync::mpsc::unbounded_channel();
        let client_id = run_on_ffi_runtime("start_message_bus", panic_state, async move {
            inner.start_message_bus(mode.into(), event_sender).await
        })
        .await?;

        ffi_runtime().spawn(async move {
            while let Some(event) = event_receiver.recv().await {
                handler.on_message_bus_event(event.into());
            }
        });

        Ok(client_id)
    }

    pub fn topic_reply_presence_state(
        &self,
        topic_id: u64,
    ) -> Result<TopicPresenceState, FireUniFfiError> {
        self.run_infallible("topic_reply_presence_state", move |inner| {
            inner.topic_reply_presence_state(topic_id).into()
        })
    }

    pub async fn bootstrap_topic_reply_presence(
        &self,
        topic_id: u64,
        owner_token: String,
    ) -> Result<TopicPresenceState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let presence =
            run_on_ffi_runtime("bootstrap_topic_reply_presence", panic_state, async move {
                inner
                    .bootstrap_topic_reply_presence(topic_id, owner_token)
                    .await
            })
            .await?;
        Ok(presence.into())
    }

    pub async fn update_topic_reply_presence(
        &self,
        topic_id: u64,
        active: bool,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("update_topic_reply_presence", panic_state, async move {
            inner.update_topic_reply_presence(topic_id, active).await
        })
        .await
    }

    pub async fn poll_notification_alert_once(
        &self,
        last_message_id: i64,
    ) -> Result<NotificationAlertPollResultState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response =
            run_on_ffi_runtime("poll_notification_alert_once", panic_state, async move {
                inner.poll_notification_alert_once(last_message_id).await
            })
            .await?;
        Ok(response.into())
    }

    pub fn notification_state(&self) -> Result<NotificationCenterState, FireUniFfiError> {
        self.run_infallible("notification_state", |inner| {
            inner.notification_state().into()
        })
    }

    pub async fn fetch_recent_notifications(
        &self,
        limit: Option<u32>,
    ) -> Result<NotificationListState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_recent_notifications", panic_state, async move {
            inner.fetch_recent_notifications(limit).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_notifications(
        &self,
        limit: Option<u32>,
        offset: Option<u32>,
    ) -> Result<NotificationListState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_notifications", panic_state, async move {
            inner.fetch_notifications(limit, offset).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn mark_notification_read(
        &self,
        notification_id: u64,
    ) -> Result<NotificationCenterState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("mark_notification_read", panic_state, async move {
            inner.mark_notification_read(notification_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn mark_all_notifications_read(
        &self,
    ) -> Result<NotificationCenterState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("mark_all_notifications_read", panic_state, async move {
            inner.mark_all_notifications_read().await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_bookmarks(
        &self,
        username: String,
        page: Option<u32>,
    ) -> Result<TopicListState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_bookmarks", panic_state, async move {
            inner.fetch_bookmarks(&username, page).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_read_history(
        &self,
        page: Option<u32>,
    ) -> Result<TopicListState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_read_history", panic_state, async move {
            inner.fetch_read_history(page).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_drafts(
        &self,
        offset: Option<u32>,
        limit: Option<u32>,
    ) -> Result<DraftListResponseState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_drafts", panic_state, async move {
            inner.fetch_drafts(offset, limit).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_draft(
        &self,
        draft_key: String,
    ) -> Result<Option<DraftState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_draft", panic_state, async move {
            inner.fetch_draft(&draft_key).await
        })
        .await?;
        Ok(response.map(Into::into))
    }

    pub async fn save_draft(
        &self,
        draft_key: String,
        data: DraftDataState,
        sequence: u32,
    ) -> Result<u32, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("save_draft", panic_state, async move {
            inner.save_draft(&draft_key, data.into(), sequence).await
        })
        .await
    }

    pub async fn delete_draft(
        &self,
        draft_key: String,
        sequence: Option<u32>,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("delete_draft", panic_state, async move {
            inner.delete_draft(&draft_key, sequence).await
        })
        .await
    }

    pub async fn fetch_topic_list(
        &self,
        query: TopicListQueryState,
    ) -> Result<TopicListState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_list", panic_state, async move {
            inner.fetch_topic_list(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn search(
        &self,
        query: SearchQueryState,
    ) -> Result<SearchResultState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("search", panic_state, async move {
            inner.search(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn search_tags(
        &self,
        query: TagSearchQueryState,
    ) -> Result<TagSearchResultState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("search_tags", panic_state, async move {
            inner.search_tags(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn search_users(
        &self,
        query: UserMentionQueryState,
    ) -> Result<UserMentionResultState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("search_users", panic_state, async move {
            inner.search_users(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_detail(
        &self,
        query: TopicDetailQueryState,
    ) -> Result<TopicDetailState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_detail", panic_state, async move {
            inner.fetch_topic_detail(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_detail_initial(
        &self,
        query: TopicDetailQueryState,
    ) -> Result<TopicDetailState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_detail_initial", panic_state, async move {
            inner.fetch_topic_detail_initial(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_posts(
        &self,
        topic_id: u64,
        post_ids: Vec<u64>,
    ) -> Result<Vec<TopicPostState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_posts", panic_state, async move {
            inner.fetch_topic_posts(topic_id, post_ids).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }

    pub async fn create_reply(
        &self,
        input: TopicReplyRequestState,
    ) -> Result<TopicPostState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("create_reply", panic_state, async move {
            inner.create_reply(input.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_post(&self, post_id: u64) -> Result<TopicPostState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_post", panic_state, async move {
            inner.fetch_post(post_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn update_post(
        &self,
        input: PostUpdateRequestState,
    ) -> Result<TopicPostState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("update_post", panic_state, async move {
            inner.update_post(input.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn create_topic(
        &self,
        input: TopicCreateRequestState,
    ) -> Result<u64, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("create_topic", panic_state, async move {
            inner.create_topic(input.into()).await
        })
        .await
    }

    pub async fn update_topic(
        &self,
        input: TopicUpdateRequestState,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("update_topic", panic_state, async move {
            inner.update_topic(input.into()).await
        })
        .await
    }

    pub async fn upload_image(
        &self,
        input: UploadImageRequestState,
    ) -> Result<UploadResultState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("upload_image", panic_state, async move {
            inner
                .upload_image(&input.file_name, input.mime_type.as_deref(), input.bytes)
                .await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn lookup_upload_urls(
        &self,
        short_urls: Vec<String>,
    ) -> Result<Vec<ResolvedUploadUrlState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("lookup_upload_urls", panic_state, async move {
            inner.lookup_upload_urls(short_urls).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }

    pub async fn report_topic_timings(
        &self,
        input: TopicTimingsRequestState,
    ) -> Result<bool, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let accepted = run_on_ffi_runtime("report_topic_timings", panic_state, async move {
            inner.report_topic_timings(input.into()).await
        })
        .await?;
        Ok(accepted)
    }

    pub async fn like_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdateState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("like_post", panic_state, async move {
            inner.like_post(post_id).await
        })
        .await?;
        Ok(response.map(Into::into))
    }

    pub async fn unlike_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdateState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("unlike_post", panic_state, async move {
            inner.unlike_post(post_id).await
        })
        .await?;
        Ok(response.map(Into::into))
    }

    pub async fn toggle_post_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<PostReactionUpdateState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("toggle_post_reaction", panic_state, async move {
            inner.toggle_post_reaction(post_id, reaction_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn vote_poll(
        &self,
        post_id: u64,
        poll_name: String,
        options: Vec<String>,
    ) -> Result<PollState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("vote_poll", panic_state, async move {
            inner.vote_poll(post_id, &poll_name, options).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn unvote_poll(
        &self,
        post_id: u64,
        poll_name: String,
    ) -> Result<PollState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("unvote_poll", panic_state, async move {
            inner.unvote_poll(post_id, &poll_name).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn vote_topic(&self, topic_id: u64) -> Result<VoteResponseState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("vote_topic", panic_state, async move {
            inner.vote_topic(topic_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn unvote_topic(&self, topic_id: u64) -> Result<VoteResponseState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("unvote_topic", panic_state, async move {
            inner.unvote_topic(topic_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_voters(
        &self,
        topic_id: u64,
    ) -> Result<Vec<VotedUserState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_voters", panic_state, async move {
            inner.fetch_topic_voters(topic_id).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }

    pub async fn create_bookmark(
        &self,
        bookmarkable_id: u64,
        bookmarkable_type: String,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<u64, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("create_bookmark", panic_state, async move {
            inner
                .create_bookmark(
                    bookmarkable_id,
                    &bookmarkable_type,
                    name.as_deref(),
                    reminder_at.as_deref(),
                    auto_delete_preference,
                )
                .await
        })
        .await
    }

    pub async fn update_bookmark(
        &self,
        bookmark_id: u64,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("update_bookmark", panic_state, async move {
            inner
                .update_bookmark(bookmark_id, name, reminder_at, auto_delete_preference)
                .await
        })
        .await
    }

    pub async fn delete_bookmark(&self, bookmark_id: u64) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("delete_bookmark", panic_state, async move {
            inner.delete_bookmark(bookmark_id).await
        })
        .await
    }

    pub async fn set_topic_notification_level(
        &self,
        topic_id: u64,
        notification_level: i32,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("set_topic_notification_level", panic_state, async move {
            inner
                .set_topic_notification_level(topic_id, notification_level)
                .await
        })
        .await
    }

    pub fn apply_cookies(&self, cookies: CookieState) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_cookies", move |inner| {
            SessionState::from_snapshot(inner.apply_cookies(cookies.into()))
        })
    }

    pub fn merge_platform_cookies(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("merge_platform_cookies", move |inner| {
            SessionState::from_snapshot(
                inner.merge_platform_cookies(cookies.into_iter().map(Into::into).collect()),
            )
        })
    }

    pub fn apply_platform_cookies(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_platform_cookies", move |inner| {
            SessionState::from_snapshot(
                inner.apply_platform_cookies(cookies.into_iter().map(Into::into).collect()),
            )
        })
    }

    pub fn apply_bootstrap(
        &self,
        bootstrap: BootstrapState,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_bootstrap", move |inner| {
            SessionState::from_snapshot(inner.apply_bootstrap(bootstrap.into()))
        })
    }

    pub fn apply_csrf_token(&self, csrf_token: String) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_csrf_token", move |inner| {
            SessionState::from_snapshot(inner.apply_csrf_token(csrf_token))
        })
    }

    pub fn clear_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("clear_csrf_token", |inner| {
            SessionState::from_snapshot(inner.clear_csrf_token())
        })
    }

    pub fn apply_home_html(&self, html: String) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_home_html", move |inner| {
            SessionState::from_snapshot(inner.apply_home_html(html))
        })
    }

    pub fn sync_login_context(
        &self,
        context: LoginSyncState,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("sync_login_context", move |inner| {
            SessionState::from_snapshot(inner.sync_login_context(context.into()))
        })
    }

    pub fn logout_local(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("logout_local", move |inner| {
            SessionState::from_snapshot(inner.logout_local(preserve_cf_clearance))
        })
    }

    pub async fn refresh_bootstrap(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot = run_on_ffi_runtime("refresh_bootstrap", panic_state, async move {
            inner.refresh_bootstrap().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_bootstrap_if_needed(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot = run_on_ffi_runtime("refresh_bootstrap_if_needed", panic_state, async move {
            inner.refresh_bootstrap_if_needed().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot = run_on_ffi_runtime("refresh_csrf_token", panic_state, async move {
            inner.refresh_csrf_token().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_csrf_token_if_needed(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot =
            run_on_ffi_runtime("refresh_csrf_token_if_needed", panic_state, async move {
                inner.refresh_csrf_token_if_needed().await
            })
            .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot = run_on_ffi_runtime("logout_remote", panic_state, async move {
            inner.logout_remote(preserve_cf_clearance).await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn fetch_user_profile(
        &self,
        username: String,
    ) -> Result<UserProfileState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let profile = run_on_ffi_runtime("fetch_user_profile", panic_state, async move {
            inner.fetch_user_profile(&username).await
        })
        .await?;
        Ok(profile.into())
    }

    pub async fn fetch_user_summary(
        &self,
        username: String,
    ) -> Result<UserSummaryState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let summary = run_on_ffi_runtime("fetch_user_summary", panic_state, async move {
            inner.fetch_user_summary(&username).await
        })
        .await?;
        Ok(summary.into())
    }

    pub async fn fetch_following(
        &self,
        username: String,
    ) -> Result<Vec<FollowUserState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let users = run_on_ffi_runtime("fetch_following", panic_state, async move {
            inner.fetch_following(&username).await
        })
        .await?;
        Ok(users.into_iter().map(Into::into).collect())
    }

    pub async fn fetch_followers(
        &self,
        username: String,
    ) -> Result<Vec<FollowUserState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let users = run_on_ffi_runtime("fetch_followers", panic_state, async move {
            inner.fetch_followers(&username).await
        })
        .await?;
        Ok(users.into_iter().map(Into::into).collect())
    }

    pub async fn follow_user(&self, username: String) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("follow_user", panic_state, async move {
            inner.follow_user(&username).await
        })
        .await
    }

    pub async fn unfollow_user(&self, username: String) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("unfollow_user", panic_state, async move {
            inner.unfollow_user(&username).await
        })
        .await
    }

    pub async fn fetch_badge_detail(&self, badge_id: u64) -> Result<BadgeState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let badge = run_on_ffi_runtime("fetch_badge_detail", panic_state, async move {
            inner.fetch_badge_detail(badge_id).await
        })
        .await?;
        Ok(badge.into())
    }

    pub async fn fetch_user_actions(
        &self,
        username: String,
        offset: Option<u32>,
        filter: Option<String>,
    ) -> Result<Vec<UserActionState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let actions = run_on_ffi_runtime("fetch_user_actions", panic_state, async move {
            inner
                .fetch_user_actions(&username, offset, filter.as_deref())
                .await
        })
        .await?;
        Ok(actions.into_iter().map(Into::into).collect())
    }

    pub async fn fetch_pending_invites(
        &self,
        username: String,
    ) -> Result<Vec<InviteLinkState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let invites = run_on_ffi_runtime("fetch_pending_invites", panic_state, async move {
            inner.fetch_pending_invites(&username).await
        })
        .await?;
        Ok(invites.into_iter().map(Into::into).collect())
    }

    pub async fn create_invite_link(
        &self,
        input: InviteCreateRequestState,
    ) -> Result<InviteLinkState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let invite = run_on_ffi_runtime("create_invite_link", panic_state, async move {
            inner.create_invite_link(input.into()).await
        })
        .await?;
        Ok(invite.into())
    }
}

impl FireCoreHandle {
    fn run_fallible<T, F>(&self, operation: &'static str, f: F) -> Result<T, FireUniFfiError>
    where
        F: FnOnce(&FireCore) -> Result<T, FireCoreError>,
    {
        self.panic_state.ensure_healthy(operation)?;
        match panic::catch_unwind(AssertUnwindSafe(|| f(self.inner.as_ref()))) {
            Ok(Ok(value)) => Ok(value),
            Ok(Err(error)) => Err(error.into()),
            Err(payload) => Err(self.panic_state.capture_panic(operation, payload.as_ref())),
        }
    }

    fn run_infallible<T, F>(&self, operation: &'static str, f: F) -> Result<T, FireUniFfiError>
    where
        F: FnOnce(&FireCore) -> T,
    {
        self.panic_state.ensure_healthy(operation)?;
        match panic::catch_unwind(AssertUnwindSafe(|| f(self.inner.as_ref()))) {
            Ok(value) => Ok(value),
            Err(payload) => Err(self.panic_state.capture_panic(operation, payload.as_ref())),
        }
    }
}

fn constructor_guard<T, F>(operation: &'static str, f: F) -> Result<T, FireUniFfiError>
where
    F: FnOnce() -> Result<T, FireCoreError>,
{
    match panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(error)) => Err(error.into()),
        Err(payload) => {
            let report = CapturedPanic::from_payload(operation, payload.as_ref());
            report.log();
            Err(FireUniFfiError::Internal {
                details: report.user_message(),
            })
        }
    }
}

async fn run_on_ffi_runtime<T, Fut>(
    operation: &'static str,
    panic_state: Arc<PanicState>,
    future: Fut,
) -> Result<T, FireUniFfiError>
where
    T: Send + 'static,
    Fut: Future<Output = Result<T, FireCoreError>> + Send + 'static,
{
    panic_state.ensure_healthy(operation)?;
    ffi_runtime()
        .spawn(AssertUnwindSafe(future).catch_unwind())
        .await
        .map_err(|error| FireUniFfiError::Runtime {
            details: error.to_string(),
        })?
        .map_err(|payload| panic_state.capture_panic(operation, payload.as_ref()))?
        .map_err(Into::into)
}

fn ffi_runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("failed to create ffi runtime")
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io, path::PathBuf};

    #[test]
    fn maps_http_status_errors_without_flattening() {
        let error = FireUniFfiError::from(FireCoreError::HttpStatus {
            operation: "fetch topic list",
            status: 429,
            body: "slow down".to_string(),
        });

        assert!(matches!(
            error,
            FireUniFfiError::HttpStatus {
                operation,
                status: 429,
                body,
            } if operation == "fetch topic list" && body == "slow down"
        ));
    }

    #[test]
    fn maps_cloudflare_challenge_errors_to_dedicated_variant() {
        let error = FireUniFfiError::from(FireCoreError::CloudflareChallenge {
            operation: "create reply",
        });

        assert!(matches!(error, FireUniFfiError::CloudflareChallenge));
    }

    #[test]
    fn maps_login_required_errors_to_dedicated_variant() {
        let error = FireUniFfiError::from(FireCoreError::LoginRequired {
            operation: "report topic timings",
            message: "您需要登录才能执行此操作。".to_string(),
        });

        assert!(matches!(
            error,
            FireUniFfiError::LoginRequired { details }
                if details == "您需要登录才能执行此操作。"
        ));
    }

    #[test]
    fn maps_storage_errors_to_storage_variant() {
        let error = FireUniFfiError::from(FireCoreError::PersistIo {
            path: PathBuf::from("/tmp/session.json"),
            source: io::Error::new(io::ErrorKind::PermissionDenied, "denied"),
        });

        assert!(matches!(
            error,
            FireUniFfiError::Storage { details }
                if details.contains("/tmp/session.json") && details.contains("denied")
        ));
    }

    #[test]
    fn topic_detail_state_carries_interaction_count() {
        let state = TopicDetailState::from(TopicDetail {
            like_count: 8,
            post_stream: TopicPostStream {
                posts: vec![TopicPost {
                    reactions: vec![TopicReaction {
                        id: "clap".into(),
                        count: 2,
                        ..TopicReaction::default()
                    }],
                    ..TopicPost::default()
                }],
                ..TopicPostStream::default()
            },
            ..TopicDetail::default()
        });

        assert_eq!(state.interaction_count, 10);
    }

    #[test]
    fn runs_async_work_on_ffi_runtime() {
        let panic_state = Arc::new(PanicState::default());
        let value = ffi_runtime()
            .block_on(run_on_ffi_runtime(
                "test_async_success",
                Arc::clone(&panic_state),
                async { Ok::<_, FireCoreError>(42_u8) },
            ))
            .expect("ffi runtime should resolve async work");

        assert_eq!(value, 42);
    }

    #[test]
    fn converts_sync_panic_to_internal_error_and_poisoned_handle() {
        let handle = FireCoreHandle::new(None, None).expect("constructor should succeed");

        let error = handle
            .run_infallible("test_sync_panic", |_| {
                panic!("boom");
            })
            .expect_err("panic should map to an internal error");

        assert!(matches!(
            error,
            FireUniFfiError::Internal { details } if details.contains("test_sync_panic panicked: boom")
        ));
        assert!(matches!(
            handle.panic_state.ensure_healthy("snapshot"),
            Err(FireUniFfiError::Internal { details })
                if details.contains("poisoned by a previous panic")
                    && details.contains("test_sync_panic panicked: boom")
        ));
    }

    #[test]
    fn converts_async_panic_to_internal_error_and_poisoned_handle() {
        let panic_state = Arc::new(PanicState::default());

        let error = ffi_runtime()
            .block_on(run_on_ffi_runtime(
                "test_async_panic",
                Arc::clone(&panic_state),
                async {
                    panic!("async boom");
                    #[allow(unreachable_code)]
                    Ok::<(), FireCoreError>(())
                },
            ))
            .expect_err("panic should map to an internal error");

        assert!(matches!(
            error,
            FireUniFfiError::Internal { details }
                if details.contains("test_async_panic panicked: async boom")
        ));
        assert!(matches!(
            panic_state.ensure_healthy("fetch_topic_list"),
            Err(FireUniFfiError::Internal { details })
                if details.contains("poisoned by a previous panic")
                    && details.contains("test_async_panic panicked: async boom")
        ));
    }
}
