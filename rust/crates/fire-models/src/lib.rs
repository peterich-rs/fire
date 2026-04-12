use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use url::Url;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlatformCookie {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub expires_at_unix_ms: Option<i64>,
}

impl PlatformCookie {
    pub fn is_expired_at(&self, now_unix_ms: i64) -> bool {
        self.expires_at_unix_ms
            .is_some_and(|expires_at_unix_ms| expires_at_unix_ms <= now_unix_ms)
    }

    pub fn is_expired_now(&self) -> bool {
        self.is_expired_at(current_unix_ms())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookieSnapshot {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
    pub cf_clearance: Option<String>,
    pub csrf_token: Option<String>,
    #[serde(default)]
    pub platform_cookies: Vec<PlatformCookie>,
}

impl CookieSnapshot {
    pub fn has_login_session(&self) -> bool {
        if self.platform_cookies.is_empty() {
            is_non_empty(self.t_token.as_deref())
        } else {
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "_t").is_some()
        }
    }

    pub fn has_forum_session(&self) -> bool {
        if self.platform_cookies.is_empty() {
            is_non_empty(self.forum_session.as_deref())
        } else {
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "_forum_session")
                .is_some()
        }
    }

    pub fn has_cloudflare_clearance(&self) -> bool {
        if self.platform_cookies.is_empty() {
            is_non_empty(self.cf_clearance.as_deref())
        } else {
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "cf_clearance").is_some()
        }
    }

    pub fn has_csrf_token(&self) -> bool {
        is_non_empty(self.csrf_token.as_deref())
    }

    pub fn can_authenticate_requests(&self) -> bool {
        self.has_login_session() && self.has_forum_session()
    }

    pub fn merge_patch(&mut self, patch: &Self) {
        merge_string_patch(&mut self.t_token, patch.t_token.clone());
        merge_string_patch(&mut self.forum_session, patch.forum_session.clone());
        merge_string_patch(&mut self.cf_clearance, patch.cf_clearance.clone());
        merge_string_patch(&mut self.csrf_token, patch.csrf_token.clone());
        if !patch.platform_cookies.is_empty() {
            merge_platform_cookie_batch(&mut self.platform_cookies, &patch.platform_cookies);
            self.refresh_known_platform_cookie_fields();
        }
    }

    pub fn merge_platform_cookies(&mut self, cookies: &[PlatformCookie]) {
        merge_string_patch(
            &mut self.t_token,
            latest_non_empty_platform_cookie_value(cookies, "_t"),
        );
        merge_string_patch(
            &mut self.forum_session,
            latest_non_empty_platform_cookie_value(cookies, "_forum_session"),
        );
        merge_string_patch(
            &mut self.cf_clearance,
            latest_non_empty_platform_cookie_value(cookies, "cf_clearance"),
        );
        merge_platform_cookie_batch(&mut self.platform_cookies, cookies);
        self.refresh_known_platform_cookie_fields();
    }

    pub fn apply_platform_cookies(&mut self, cookies: &[PlatformCookie]) {
        self.t_token = latest_non_empty_platform_cookie_value(cookies, "_t");
        self.forum_session = latest_non_empty_platform_cookie_value(cookies, "_forum_session");
        self.cf_clearance = latest_non_empty_platform_cookie_value(cookies, "cf_clearance");
        self.platform_cookies = normalized_platform_cookies(cookies);
        self.refresh_known_platform_cookie_fields();
    }

    pub fn clear_login_state(&mut self, preserve_cf_clearance: bool) {
        self.t_token = None;
        self.forum_session = None;
        self.csrf_token = None;
        if !preserve_cf_clearance {
            self.cf_clearance = None;
        }
        self.platform_cookies.retain(|cookie| {
            let lower_name = cookie.name.to_ascii_lowercase();
            if lower_name == "_t" || lower_name == "_forum_session" {
                return false;
            }
            preserve_cf_clearance || lower_name != "cf_clearance"
        });
    }

    pub fn refresh_known_platform_cookie_fields(&mut self) {
        let had_platform_cookies = !self.platform_cookies.is_empty();
        self.platform_cookies = normalized_platform_cookies(&self.platform_cookies);
        if self.platform_cookies.is_empty() {
            if had_platform_cookies {
                self.t_token = None;
                self.forum_session = None;
                self.cf_clearance = None;
            }
            return;
        }

        self.t_token = latest_non_empty_platform_cookie_value(&self.platform_cookies, "_t");
        self.forum_session =
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "_forum_session");
        self.cf_clearance =
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "cf_clearance");
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BootstrapArtifacts {
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
    #[serde(default)]
    pub has_site_metadata: bool,
    #[serde(default)]
    pub top_tags: Vec<String>,
    #[serde(default)]
    pub can_tag_topics: bool,
    #[serde(default)]
    pub categories: Vec<TopicCategory>,
    #[serde(default)]
    pub has_site_settings: bool,
    #[serde(default = "default_enabled_reaction_ids")]
    pub enabled_reaction_ids: Vec<String>,
    #[serde(default = "default_min_post_length")]
    pub min_post_length: u32,
    #[serde(default = "default_min_topic_title_length")]
    pub min_topic_title_length: u32,
    #[serde(default = "default_min_first_post_length")]
    pub min_first_post_length: u32,
    #[serde(default = "default_min_personal_message_title_length")]
    pub min_personal_message_title_length: u32,
    #[serde(default = "default_min_personal_message_post_length")]
    pub min_personal_message_post_length: u32,
    pub default_composer_category: Option<u64>,
}

impl Default for BootstrapArtifacts {
    fn default() -> Self {
        Self {
            base_url: String::new(),
            discourse_base_uri: None,
            shared_session_key: None,
            current_username: None,
            current_user_id: None,
            notification_channel_position: None,
            long_polling_base_url: None,
            turnstile_sitekey: None,
            topic_tracking_state_meta: None,
            preloaded_json: None,
            has_preloaded_data: false,
            has_site_metadata: false,
            top_tags: Vec::new(),
            can_tag_topics: false,
            categories: Vec::new(),
            has_site_settings: false,
            enabled_reaction_ids: default_enabled_reaction_ids(),
            min_post_length: default_min_post_length(),
            min_topic_title_length: default_min_topic_title_length(),
            min_first_post_length: default_min_first_post_length(),
            min_personal_message_title_length: default_min_personal_message_title_length(),
            min_personal_message_post_length: default_min_personal_message_post_length(),
            default_composer_category: None,
        }
    }
}

impl BootstrapArtifacts {
    pub fn has_identity(&self) -> bool {
        is_non_empty(self.current_username.as_deref())
    }

    pub fn merge_patch(&mut self, patch: &Self) {
        if !patch.base_url.is_empty() {
            self.base_url = patch.base_url.clone();
        }

        merge_string_patch(
            &mut self.discourse_base_uri,
            patch.discourse_base_uri.clone(),
        );
        merge_string_patch(
            &mut self.shared_session_key,
            patch.shared_session_key.clone(),
        );
        merge_string_patch(&mut self.current_username, patch.current_username.clone());
        merge_number_patch(&mut self.current_user_id, patch.current_user_id);
        merge_number_patch(
            &mut self.notification_channel_position,
            patch.notification_channel_position,
        );
        merge_string_patch(
            &mut self.long_polling_base_url,
            patch.long_polling_base_url.clone(),
        );
        merge_string_patch(&mut self.turnstile_sitekey, patch.turnstile_sitekey.clone());
        merge_string_patch(
            &mut self.topic_tracking_state_meta,
            patch.topic_tracking_state_meta.clone(),
        );

        if let Some(preloaded_json) = patch.preloaded_json.clone() {
            if preloaded_json.is_empty() {
                self.preloaded_json = None;
                self.has_preloaded_data = false;
                self.has_site_metadata = false;
                self.top_tags = Vec::new();
                self.can_tag_topics = false;
                self.categories = Vec::new();
                self.has_site_settings = false;
                self.enabled_reaction_ids = default_enabled_reaction_ids();
                self.min_post_length = default_min_post_length();
                self.min_topic_title_length = default_min_topic_title_length();
                self.min_first_post_length = default_min_first_post_length();
                self.min_personal_message_title_length =
                    default_min_personal_message_title_length();
                self.min_personal_message_post_length = default_min_personal_message_post_length();
                self.default_composer_category = None;
            } else {
                self.preloaded_json = Some(preloaded_json);
                self.has_preloaded_data = true;
                if patch.has_site_metadata {
                    self.has_site_metadata = true;
                    self.top_tags = normalized_top_tags(patch.top_tags.clone());
                    self.can_tag_topics = patch.can_tag_topics;
                    self.categories = patch.categories.clone();
                }
                if patch.has_site_settings {
                    self.has_site_settings = true;
                    self.enabled_reaction_ids =
                        normalized_enabled_reaction_ids(patch.enabled_reaction_ids.clone());
                    self.min_post_length = patch.min_post_length.max(1);
                    self.min_topic_title_length = patch.min_topic_title_length.max(1);
                    self.min_first_post_length = patch.min_first_post_length.max(1);
                    self.min_personal_message_title_length =
                        patch.min_personal_message_title_length.max(1);
                    self.min_personal_message_post_length =
                        patch.min_personal_message_post_length.max(1);
                    self.default_composer_category = patch.default_composer_category;
                }
            }
        } else if patch.has_preloaded_data {
            self.has_preloaded_data = true;
            if patch.has_site_metadata {
                self.has_site_metadata = true;
                self.top_tags = normalized_top_tags(patch.top_tags.clone());
                self.can_tag_topics = patch.can_tag_topics;
                self.categories = patch.categories.clone();
            }
            if patch.has_site_settings {
                self.has_site_settings = true;
                self.enabled_reaction_ids =
                    normalized_enabled_reaction_ids(patch.enabled_reaction_ids.clone());
                self.min_post_length = patch.min_post_length.max(1);
                self.min_topic_title_length = patch.min_topic_title_length.max(1);
                self.min_first_post_length = patch.min_first_post_length.max(1);
                self.min_personal_message_title_length =
                    patch.min_personal_message_title_length.max(1);
                self.min_personal_message_post_length =
                    patch.min_personal_message_post_length.max(1);
                self.default_composer_category = patch.default_composer_category;
            }
        }

        if patch.preloaded_json.is_none() && !patch.has_preloaded_data {
            if patch.has_site_metadata {
                self.has_site_metadata = true;
                self.top_tags = normalized_top_tags(patch.top_tags.clone());
                self.can_tag_topics = patch.can_tag_topics;
                self.categories = patch.categories.clone();
            }
            if patch.has_site_settings {
                self.has_site_settings = true;
                self.enabled_reaction_ids =
                    normalized_enabled_reaction_ids(patch.enabled_reaction_ids.clone());
                self.min_post_length = patch.min_post_length.max(1);
                self.min_topic_title_length = patch.min_topic_title_length.max(1);
                self.min_first_post_length = patch.min_first_post_length.max(1);
                self.min_personal_message_title_length =
                    patch.min_personal_message_title_length.max(1);
                self.min_personal_message_post_length =
                    patch.min_personal_message_post_length.max(1);
                self.default_composer_category = patch.default_composer_category;
            }
        }
    }

    pub fn clear_login_state(&mut self) {
        self.shared_session_key = None;
        self.current_username = None;
        self.current_user_id = None;
        self.notification_channel_position = None;
        self.long_polling_base_url = None;
        self.topic_tracking_state_meta = None;
        self.preloaded_json = None;
        self.has_preloaded_data = false;
        self.has_site_metadata = false;
        self.top_tags = Vec::new();
        self.can_tag_topics = false;
        self.categories = Vec::new();
        self.has_site_settings = false;
        self.enabled_reaction_ids = default_enabled_reaction_ids();
        self.min_post_length = default_min_post_length();
        self.min_topic_title_length = default_min_topic_title_length();
        self.min_first_post_length = default_min_first_post_length();
        self.min_personal_message_title_length = default_min_personal_message_title_length();
        self.min_personal_message_post_length = default_min_personal_message_post_length();
        self.default_composer_category = None;
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum LoginPhase {
    #[default]
    Anonymous,
    CookiesCaptured,
    BootstrapCaptured,
    Ready,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionReadiness {
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionSnapshot {
    pub cookies: CookieSnapshot,
    pub bootstrap: BootstrapArtifacts,
    #[serde(default)]
    pub browser_user_agent: Option<String>,
}

impl SessionSnapshot {
    pub fn readiness(&self) -> SessionReadiness {
        let has_login_cookie = self.cookies.has_login_session();
        let has_forum_session = self.cookies.has_forum_session();
        let has_cloudflare_clearance = self.cookies.has_cloudflare_clearance();
        let has_csrf_token = self.cookies.has_csrf_token();
        let has_current_user = self.bootstrap.has_identity();
        let has_preloaded_data = self.bootstrap.has_preloaded_data;
        let has_shared_session_key = is_non_empty(self.bootstrap.shared_session_key.as_deref());
        let can_read_authenticated_api = self.cookies.can_authenticate_requests();
        let can_write_authenticated_api = can_read_authenticated_api && has_csrf_token;
        let can_open_message_bus = can_read_authenticated_api
            && (!message_bus_requires_shared_session_key(&self.bootstrap)
                || has_shared_session_key);

        SessionReadiness {
            has_login_cookie,
            has_forum_session,
            has_cloudflare_clearance,
            has_csrf_token,
            has_current_user,
            has_preloaded_data,
            has_shared_session_key,
            can_read_authenticated_api,
            can_write_authenticated_api,
            can_open_message_bus,
        }
    }

    pub fn login_phase(&self) -> LoginPhase {
        let readiness = self.readiness();
        if !readiness.has_login_cookie {
            return LoginPhase::Anonymous;
        }
        if !readiness.can_read_authenticated_api || !readiness.has_current_user {
            return LoginPhase::CookiesCaptured;
        }
        if !readiness.can_write_authenticated_api
            || !readiness.has_preloaded_data
            || !self.bootstrap.has_site_metadata
            || !self.bootstrap.has_site_settings
        {
            return LoginPhase::BootstrapCaptured;
        }
        LoginPhase::Ready
    }

    pub fn profile_display_name(&self) -> String {
        if let Some(current_username) = self
            .bootstrap
            .current_username
            .as_deref()
            .filter(|value| !value.is_empty())
        {
            return current_username.to_string();
        }

        let readiness = self.readiness();
        if readiness.can_read_authenticated_api || self.cookies.has_login_session() {
            "会话已连接".to_string()
        } else {
            "未登录".to_string()
        }
    }

    pub fn login_phase_label(&self) -> String {
        let readiness = self.readiness();
        if readiness.can_read_authenticated_api && !readiness.has_current_user {
            "账号信息同步中".to_string()
        } else {
            self.login_phase().title().to_string()
        }
    }

    pub fn clear_login_state(&mut self, preserve_cf_clearance: bool) {
        self.cookies.clear_login_state(preserve_cf_clearance);
        self.bootstrap.clear_login_state();
    }
}

impl LoginPhase {
    pub fn title(self) -> &'static str {
        match self {
            Self::Anonymous => "未登录",
            Self::CookiesCaptured => "Cookie 已同步",
            Self::BootstrapCaptured => "会话初始化中",
            Self::Ready => "已就绪",
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageBusClientMode {
    #[default]
    Foreground,
    IosBackground,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageBusSubscriptionScope {
    #[default]
    Durable,
    Transient,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageBusSubscription {
    pub owner_token: String,
    pub channel: String,
    pub last_message_id: Option<i64>,
    pub scope: MessageBusSubscriptionScope,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageBusEventKind {
    TopicList,
    TopicDetail,
    TopicReaction,
    Presence,
    Notification,
    NotificationAlert,
    #[default]
    Unknown,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageBusEvent {
    pub channel: String,
    pub message_id: i64,
    pub kind: MessageBusEventKind,
    pub topic_list_kind: Option<TopicListKind>,
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPresenceUser {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPresence {
    pub topic_id: u64,
    pub message_id: i64,
    pub users: Vec<TopicPresenceUser>,
}

impl TopicPresence {
    pub fn empty(topic_id: u64) -> Self {
        Self {
            topic_id,
            message_id: -1,
            users: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationAlert {
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationAlertPollResult {
    pub notification_user_id: u64,
    pub client_id: String,
    pub last_message_id: i64,
    pub alerts: Vec<NotificationAlert>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationCounters {
    pub all_unread: u32,
    pub unread: u32,
    pub high_priority: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationData {
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationItem {
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
    pub data: NotificationData,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationListResponse {
    pub notifications: Vec<NotificationItem>,
    pub total_rows_notifications: u32,
    pub seen_notification_id: Option<u64>,
    pub load_more_notifications: Option<String>,
    pub next_offset: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationState {
    pub counters: NotificationCounters,
    pub recent: Vec<NotificationItem>,
    pub has_loaded_recent: bool,
    pub recent_seen_notification_id: Option<u64>,
    pub full: Vec<NotificationItem>,
    pub has_loaded_full: bool,
    pub total_rows_notifications: u32,
    pub full_seen_notification_id: Option<u64>,
    pub full_load_more_notifications: Option<String>,
    pub full_next_offset: Option<u32>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum TopicListKind {
    #[default]
    Latest,
    New,
    Unread,
    Unseen,
    Hot,
    Top,
    PrivateMessagesInbox,
    PrivateMessagesSent,
}

impl TopicListKind {
    pub fn path(self) -> &'static str {
        match self {
            Self::Latest => "/latest.json",
            Self::New => "/new.json",
            Self::Unread => "/unread.json",
            Self::Unseen => "/unseen.json",
            Self::Hot => "/hot.json",
            Self::Top => "/top.json",
            Self::PrivateMessagesInbox => "/topics/private-messages/{username}.json",
            Self::PrivateMessagesSent => "/topics/private-messages-sent/{username}.json",
        }
    }

    pub fn filter_name(self) -> &'static str {
        match self {
            Self::Latest => "latest",
            Self::New => "new",
            Self::Unread => "unread",
            Self::Unseen => "unseen",
            Self::Hot => "hot",
            Self::Top => "top",
            Self::PrivateMessagesInbox => "private-messages",
            Self::PrivateMessagesSent => "private-messages-sent",
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicListQuery {
    pub kind: TopicListKind,
    pub page: Option<u32>,
    pub topic_ids: Vec<u64>,
    pub order: Option<String>,
    pub ascending: Option<bool>,
    pub category_slug: Option<String>,
    pub category_id: Option<u64>,
    pub parent_category_slug: Option<String>,
    pub tag: Option<String>,
    #[serde(default)]
    pub additional_tags: Vec<String>,
    #[serde(default)]
    pub match_all_tags: bool,
}

impl TopicListQuery {
    /// Builds the API path for this query.
    /// Category scope: `/c/{slug}/{id}/l/{filter}.json` (with optional parent prefix)
    /// Tag scope: `/tag/{tag}/l/{filter}.json`
    /// Global: `/{filter}.json`
    pub fn api_path(&self) -> String {
        let filter = self.kind.filter_name();

        if let Some(category_slug) = &self.category_slug {
            if let Some(category_id) = self.category_id {
                return if let Some(parent_slug) = &self.parent_category_slug {
                    format!("/c/{parent_slug}/{category_slug}/{category_id}/l/{filter}.json")
                } else {
                    format!("/c/{category_slug}/{category_id}/l/{filter}.json")
                };
            }
            return format!("/c/{category_slug}.json");
        }

        if let Some(tag) = &self.tag {
            return format!("/tag/{tag}/l/{filter}.json");
        }

        if !self.topic_ids.is_empty() {
            return TopicListKind::Latest.path().to_string();
        }

        self.kind.path().to_string()
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicUser {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPoster {
    pub user_id: u64,
    pub description: Option<String>,
    pub extras: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicParticipant {
    pub user_id: u64,
    pub username: Option<String>,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTag {
    pub id: Option<u64>,
    pub name: String,
    pub slug: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicCategory {
    pub id: u64,
    pub name: String,
    pub slug: String,
    pub parent_category_id: Option<u64>,
    pub color_hex: Option<String>,
    pub text_color_hex: Option<String>,
    pub topic_template: Option<String>,
    pub minimum_required_tags: u32,
    #[serde(default)]
    pub required_tag_groups: Vec<RequiredTagGroup>,
    #[serde(default)]
    pub allowed_tags: Vec<String>,
    pub permission: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicSummary {
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
    pub tags: Vec<TopicTag>,
    pub posters: Vec<TopicPoster>,
    #[serde(default)]
    pub participants: Vec<TopicParticipant>,
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicRow {
    pub topic: TopicSummary,
    pub excerpt_text: Option<String>,
    pub original_poster_username: Option<String>,
    pub original_poster_avatar_template: Option<String>,
    pub tag_names: Vec<String>,
    #[serde(default)]
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicListResponse {
    pub topics: Vec<TopicSummary>,
    pub users: Vec<TopicUser>,
    #[serde(default)]
    pub rows: Vec<TopicRow>,
    pub more_topics_url: Option<String>,
    pub next_page: Option<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SearchTypeFilter {
    Topic,
    Post,
    User,
    Category,
    Tag,
}

impl SearchTypeFilter {
    pub fn query_value(self) -> &'static str {
        match self {
            Self::Topic => "topic",
            Self::Post => "post",
            Self::User => "user",
            Self::Category => "category",
            Self::Tag => "tag",
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchQuery {
    pub q: String,
    pub page: Option<u32>,
    pub type_filter: Option<SearchTypeFilter>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchTopic {
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchPost {
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchUser {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct GroupedSearchResult {
    pub term: String,
    pub more_posts: bool,
    pub more_users: bool,
    pub more_categories: bool,
    pub more_full_page_results: bool,
    pub search_log_id: Option<u64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SearchResult {
    pub posts: Vec<SearchPost>,
    pub topics: Vec<SearchTopic>,
    pub users: Vec<SearchUser>,
    pub grouped_result: GroupedSearchResult,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TagSearchQuery {
    pub q: Option<String>,
    pub filter_for_input: bool,
    pub limit: Option<u32>,
    pub category_id: Option<u64>,
    pub selected_tags: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TagSearchItem {
    pub name: String,
    pub text: String,
    pub count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RequiredTagGroup {
    pub name: String,
    pub min_count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TagSearchResult {
    pub results: Vec<TagSearchItem>,
    pub required_tag_group: Option<RequiredTagGroup>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserMentionQuery {
    pub term: String,
    pub include_groups: bool,
    pub limit: u32,
    pub topic_id: Option<u64>,
    pub category_id: Option<u64>,
}

impl Default for UserMentionQuery {
    fn default() -> Self {
        Self {
            term: String::new(),
            include_groups: true,
            limit: 6,
            topic_id: None,
            category_id: None,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserMentionUser {
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub priority_group: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserMentionGroup {
    pub name: String,
    pub full_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub user_count: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserMentionResult {
    pub users: Vec<UserMentionUser>,
    pub groups: Vec<UserMentionGroup>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailQuery {
    pub topic_id: u64,
    pub post_number: Option<u32>,
    pub track_visit: bool,
    pub filter: Option<String>,
    pub username_filters: Option<String>,
    pub filter_top_level_replies: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicReaction {
    pub id: String,
    #[serde(default, alias = "type")]
    pub kind: Option<String>,
    pub count: u32,
    #[serde(default)]
    pub can_undo: Option<bool>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PollOption {
    pub id: String,
    pub html: String,
    pub votes: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Poll {
    pub id: u64,
    pub name: String,
    #[serde(default, alias = "type")]
    pub kind: String,
    pub status: String,
    pub results: String,
    #[serde(default)]
    pub options: Vec<PollOption>,
    pub voters: u32,
    #[serde(default)]
    pub user_votes: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicReplyRequest {
    pub topic_id: u64,
    pub raw: String,
    pub reply_to_post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicCreateRequest {
    pub title: String,
    pub raw: String,
    pub category_id: u64,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PrivateMessageCreateRequest {
    pub title: String,
    pub raw: String,
    #[serde(default)]
    pub target_recipients: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicUpdateRequest {
    pub topic_id: u64,
    pub title: String,
    pub category_id: u64,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PostUpdateRequest {
    pub post_id: u64,
    pub raw: String,
    pub edit_reason: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct InviteCreateRequest {
    pub max_redemptions_allowed: u32,
    pub expires_at: Option<String>,
    pub description: Option<String>,
    pub email: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DraftData {
    pub reply: Option<String>,
    pub title: Option<String>,
    #[serde(rename = "categoryId", alias = "category_id")]
    pub category_id: Option<u64>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(rename = "replyToPostNumber", alias = "reply_to_post_number")]
    pub reply_to_post_number: Option<u32>,
    pub action: Option<String>,
    #[serde(default)]
    pub recipients: Vec<String>,
    #[serde(rename = "archetypeId", alias = "archetype_id")]
    pub archetype_id: Option<String>,
    #[serde(rename = "composerTime", alias = "composer_time")]
    pub composer_time: Option<u32>,
    #[serde(rename = "typingTime", alias = "typing_time")]
    pub typing_time: Option<u32>,
}

impl DraftData {
    pub fn has_content(&self) -> bool {
        is_non_empty(self.reply.as_deref()) || is_non_empty(self.title.as_deref())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Draft {
    pub draft_key: String,
    pub data: DraftData,
    pub sequence: u32,
    pub title: Option<String>,
    pub excerpt: Option<String>,
    pub updated_at: Option<String>,
    pub username: Option<String>,
    pub avatar_template: Option<String>,
    pub topic_id: Option<u64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DraftListResponse {
    #[serde(default)]
    pub drafts: Vec<Draft>,
    #[serde(default)]
    pub has_more: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UploadResult {
    pub short_url: String,
    pub url: Option<String>,
    pub original_filename: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedUploadUrl {
    pub short_url: String,
    pub short_path: Option<String>,
    pub url: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTimingEntry {
    pub post_number: u32,
    pub milliseconds: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTimingsRequest {
    pub topic_id: u64,
    pub topic_time_ms: u32,
    pub timings: Vec<TopicTimingEntry>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PostReactionUpdate {
    pub reactions: Vec<TopicReaction>,
    pub current_user_reaction: Option<TopicReaction>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPost {
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
    pub reactions: Vec<TopicReaction>,
    pub current_user_reaction: Option<TopicReaction>,
    pub polls: Vec<Poll>,
    pub accepted_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub hidden: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPostStream {
    pub posts: Vec<TopicPost>,
    pub stream: Vec<u64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicThreadReply {
    pub post_number: u32,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicThreadSection {
    pub anchor_post_number: u32,
    pub replies: Vec<TopicThreadReply>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicThread {
    pub original_post_number: Option<u32>,
    pub reply_sections: Vec<TopicThreadSection>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicThreadFlatPost {
    pub post: TopicPost,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
    pub shows_thread_line: bool,
    pub is_original_post: bool,
}

impl TopicThread {
    pub fn from_posts(posts: &[TopicPost]) -> Self {
        let Some(original_post) = posts.iter().min_by_key(|post| post.post_number) else {
            return Self::default();
        };

        let root_post_number = original_post.post_number;
        let post_numbers: std::collections::HashSet<u32> =
            posts.iter().map(|post| post.post_number).collect();
        let mut children_by_parent: std::collections::BTreeMap<u32, Vec<&TopicPost>> =
            std::collections::BTreeMap::new();

        for post in posts
            .iter()
            .filter(|post| post.post_number != root_post_number)
        {
            let Some(parent_post_number) = normalized_reply_target(post.reply_to_post_number)
            else {
                continue;
            };
            if parent_post_number == post.post_number {
                continue;
            }
            children_by_parent
                .entry(parent_post_number)
                .or_default()
                .push(post);
        }

        let mut consumed_post_numbers = std::collections::HashSet::from([root_post_number]);
        let mut reply_sections = Vec::new();

        for post in posts
            .iter()
            .filter(|post| post.post_number != root_post_number)
        {
            if consumed_post_numbers.contains(&post.post_number) {
                continue;
            }

            let normalized_parent = normalized_reply_target(post.reply_to_post_number);
            let should_start_section = normalized_parent.is_none()
                || normalized_parent == Some(root_post_number)
                || normalized_parent.is_some_and(|parent| !post_numbers.contains(&parent));
            if !should_start_section {
                continue;
            }

            consumed_post_numbers.insert(post.post_number);
            let mut branch_visited = std::collections::HashSet::from([post.post_number]);
            let replies = flatten_thread_replies(
                post.post_number,
                1,
                &children_by_parent,
                &mut consumed_post_numbers,
                &mut branch_visited,
            );
            reply_sections.push(TopicThreadSection {
                anchor_post_number: post.post_number,
                replies,
            });
        }

        let remaining_post_numbers: Vec<u32> = posts
            .iter()
            .filter(|post| post.post_number != root_post_number)
            .map(|post| post.post_number)
            .filter(|post_number| !consumed_post_numbers.contains(post_number))
            .collect();

        for post_number in remaining_post_numbers {
            let Some(post) = posts.iter().find(|post| post.post_number == post_number) else {
                continue;
            };
            consumed_post_numbers.insert(post.post_number);
            let mut branch_visited = std::collections::HashSet::from([post.post_number]);
            let replies = flatten_thread_replies(
                post.post_number,
                1,
                &children_by_parent,
                &mut consumed_post_numbers,
                &mut branch_visited,
            );
            reply_sections.push(TopicThreadSection {
                anchor_post_number: post.post_number,
                replies,
            });
        }

        Self {
            original_post_number: Some(root_post_number),
            reply_sections,
        }
    }

    pub fn flatten(&self, posts: &[TopicPost]) -> Vec<TopicThreadFlatPost> {
        let posts_by_number: std::collections::HashMap<u32, &TopicPost> =
            posts.iter().map(|post| (post.post_number, post)).collect();
        let mut result = Vec::new();

        if let Some(original_post) = self
            .original_post_number
            .and_then(|post_number| posts_by_number.get(&post_number))
        {
            result.push(TopicThreadFlatPost {
                post: (*original_post).clone(),
                depth: 0,
                parent_post_number: None,
                shows_thread_line: !self.reply_sections.is_empty(),
                is_original_post: true,
            });
        }

        for (section_index, section) in self.reply_sections.iter().enumerate() {
            let is_last_section = section_index == self.reply_sections.len() - 1;
            let has_nested_replies = !section.replies.is_empty();

            let Some(anchor_post) = posts_by_number.get(&section.anchor_post_number) else {
                continue;
            };

            result.push(TopicThreadFlatPost {
                post: (*anchor_post).clone(),
                depth: 0,
                parent_post_number: None,
                shows_thread_line: has_nested_replies || !is_last_section,
                is_original_post: false,
            });

            for (reply_index, reply) in section.replies.iter().enumerate() {
                let Some(reply_post) = posts_by_number.get(&reply.post_number) else {
                    continue;
                };
                let is_last_reply = reply_index == section.replies.len() - 1;
                result.push(TopicThreadFlatPost {
                    post: (*reply_post).clone(),
                    depth: reply.depth,
                    parent_post_number: reply.parent_post_number,
                    shows_thread_line: !is_last_reply || !is_last_section,
                    is_original_post: false,
                });
            }
        }

        result
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailCreatedBy {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailMeta {
    pub notification_level: Option<i32>,
    pub can_edit: bool,
    pub created_by: Option<TopicDetailCreatedBy>,
    #[serde(default)]
    pub participants: Vec<TopicParticipant>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetail {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTag>,
    pub views: u32,
    pub like_count: u32,
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
    pub post_stream: TopicPostStream,
    #[serde(default)]
    pub thread: TopicThread,
    #[serde(default)]
    pub flat_posts: Vec<TopicThreadFlatPost>,
    pub details: TopicDetailMeta,
}

impl TopicDetail {
    pub fn interaction_count(&self) -> u32 {
        self.like_count.saturating_add(
            self.post_stream
                .posts
                .iter()
                .flat_map(|post| post.reactions.iter())
                .filter(|reaction| !reaction.id.eq_ignore_ascii_case("heart"))
                .fold(0_u32, |total, reaction| {
                    total.saturating_add(reaction.count)
                }),
        )
    }
}

fn merge_string_patch(slot: &mut Option<String>, patch: Option<String>) {
    if let Some(value) = patch {
        if value.is_empty() {
            *slot = None;
        } else {
            *slot = Some(value);
        }
    }
}

fn merge_number_patch<T>(slot: &mut Option<T>, patch: Option<T>)
where
    T: Copy,
{
    if let Some(value) = patch {
        *slot = Some(value);
    }
}

fn is_non_empty(value: Option<&str>) -> bool {
    value.is_some_and(|value| !value.is_empty())
}

fn normalized_platform_cookies(cookies: &[PlatformCookie]) -> Vec<PlatformCookie> {
    let mut merged = Vec::new();
    merge_platform_cookie_batch(&mut merged, cookies);
    merged
}

fn merge_platform_cookie_batch(current: &mut Vec<PlatformCookie>, incoming: &[PlatformCookie]) {
    let now_unix_ms = current_unix_ms();
    current.retain(|cookie| !cookie.is_expired_at(now_unix_ms));
    for cookie in incoming {
        let Some((name, domain, path)) = normalized_platform_cookie_key(cookie) else {
            continue;
        };
        current.retain(|existing| {
            normalized_platform_cookie_key(existing).is_none_or(|existing_key| {
                existing_key != (name.clone(), domain.clone(), path.clone())
            })
        });
        if is_deleted_cookie_value(&cookie.value) || cookie.is_expired_at(now_unix_ms) {
            continue;
        }
        current.push(PlatformCookie {
            name,
            value: cookie.value.trim().to_string(),
            domain,
            path: Some(path),
            expires_at_unix_ms: cookie.expires_at_unix_ms,
        });
    }
}

fn normalized_platform_cookie_key(
    cookie: &PlatformCookie,
) -> Option<(String, Option<String>, String)> {
    let name = cookie.name.trim();
    if name.is_empty() {
        return None;
    }
    let domain = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase());
    let path = cookie
        .path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("/");
    Some((name.to_string(), domain, path.to_string()))
}

fn is_deleted_cookie_value(value: &str) -> bool {
    let value = value.trim();
    value.is_empty() || value.eq_ignore_ascii_case("del")
}

fn message_bus_requires_shared_session_key(bootstrap: &BootstrapArtifacts) -> bool {
    let Some(base_origin) = request_origin(&bootstrap.base_url) else {
        return false;
    };
    let Some(long_polling_base_url) = bootstrap
        .long_polling_base_url
        .as_deref()
        .filter(|value| !value.is_empty())
    else {
        return false;
    };
    let Some(poll_origin) = request_origin(long_polling_base_url) else {
        return false;
    };

    base_origin != poll_origin
}

fn request_origin(value: &str) -> Option<String> {
    let mut url = Url::parse(value).ok()?;
    url.set_path("");
    url.set_query(None);
    url.set_fragment(None);
    Some(url.as_str().trim_end_matches('/').to_string())
}

fn latest_non_empty_platform_cookie_value(
    cookies: &[PlatformCookie],
    name: &str,
) -> Option<String> {
    let now_unix_ms = current_unix_ms();
    cookies
        .iter()
        .rev()
        .find(|cookie| {
            cookie.name == name && !cookie.value.is_empty() && !cookie.is_expired_at(now_unix_ms)
        })
        .map(|cookie| cookie.value.clone())
}

fn current_unix_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_millis() as i64)
}

fn default_enabled_reaction_ids() -> Vec<String> {
    vec!["heart".to_string()]
}

fn default_min_post_length() -> u32 {
    1
}

fn default_min_topic_title_length() -> u32 {
    15
}

fn default_min_first_post_length() -> u32 {
    20
}

fn default_min_personal_message_title_length() -> u32 {
    2
}

fn default_min_personal_message_post_length() -> u32 {
    10
}

fn normalized_enabled_reaction_ids(ids: Vec<String>) -> Vec<String> {
    let mut normalized = Vec::new();
    for id in ids {
        let trimmed = id.trim();
        if trimmed.is_empty() || normalized.iter().any(|existing| existing == trimmed) {
            continue;
        }
        normalized.push(trimmed.to_string());
    }

    if normalized.is_empty() {
        default_enabled_reaction_ids()
    } else {
        normalized
    }
}

fn normalized_top_tags(tags: Vec<String>) -> Vec<String> {
    let mut normalized = Vec::new();
    for tag in tags {
        let trimmed = tag.trim();
        if trimmed.is_empty() || normalized.iter().any(|existing| existing == trimmed) {
            continue;
        }
        normalized.push(trimmed.to_string());
    }
    normalized
}

fn normalized_reply_target(reply_to_post_number: Option<u32>) -> Option<u32> {
    reply_to_post_number.filter(|post_number| *post_number > 0)
}

fn flatten_thread_replies(
    parent_post_number: u32,
    depth: u32,
    children_by_parent: &std::collections::BTreeMap<u32, Vec<&TopicPost>>,
    consumed_post_numbers: &mut std::collections::HashSet<u32>,
    branch_visited: &mut std::collections::HashSet<u32>,
) -> Vec<TopicThreadReply> {
    let Some(children) = children_by_parent.get(&parent_post_number) else {
        return Vec::new();
    };

    let mut replies = Vec::new();
    for child in children {
        if branch_visited.contains(&child.post_number) {
            continue;
        }

        consumed_post_numbers.insert(child.post_number);
        replies.push(TopicThreadReply {
            post_number: child.post_number,
            depth,
            parent_post_number: normalized_reply_target(child.reply_to_post_number),
        });

        branch_visited.insert(child.post_number);
        replies.extend(flatten_thread_replies(
            child.post_number,
            depth + 1,
            children_by_parent,
            consumed_post_numbers,
            branch_visited,
        ));
        branch_visited.remove(&child.post_number);
    }

    replies
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserProfile {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub trust_level: Option<u32>,
    pub bio_cooked: Option<String>,
    pub created_at: Option<String>,
    pub last_seen_at: Option<String>,
    pub last_posted_at: Option<String>,
    pub flair_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub profile_background_upload_url: Option<String>,
    pub card_background_upload_url: Option<String>,
    pub total_followers: Option<u32>,
    pub total_following: Option<u32>,
    pub can_follow: Option<bool>,
    pub is_followed: Option<bool>,
    pub can_send_private_message_to_user: Option<bool>,
    pub gamification_score: Option<u32>,
    pub suspended_till: Option<String>,
    pub silenced_till: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserSummaryStats {
    pub days_visited: u32,
    pub posts_read_count: u32,
    pub likes_received: u32,
    pub likes_given: u32,
    pub topic_count: u32,
    pub post_count: u32,
    pub time_read: u64,
    pub bookmark_count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryTopic {
    pub id: u64,
    pub title: String,
    pub slug: Option<String>,
    pub like_count: u32,
    pub category_id: Option<u64>,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryReply {
    pub id: u64,
    pub topic_id: u64,
    pub title: Option<String>,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryLink {
    pub url: String,
    pub title: Option<String>,
    pub clicks: u32,
    pub topic_id: Option<u64>,
    pub post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryTopCategory {
    pub id: u64,
    pub name: Option<String>,
    pub topic_count: u32,
    pub post_count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryUserReference {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
    pub count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserSummaryResponse {
    pub stats: UserSummaryStats,
    pub top_topics: Vec<ProfileSummaryTopic>,
    pub top_replies: Vec<ProfileSummaryReply>,
    pub top_links: Vec<ProfileSummaryLink>,
    pub top_categories: Vec<ProfileSummaryTopCategory>,
    pub most_replied_to_users: Vec<ProfileSummaryUserReference>,
    pub most_liked_by_users: Vec<ProfileSummaryUserReference>,
    pub most_liked_users: Vec<ProfileSummaryUserReference>,
    pub badges: Vec<Badge>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Badge {
    pub id: u64,
    pub name: String,
    pub description: Option<String>,
    pub badge_type_id: u32,
    pub image_url: Option<String>,
    pub icon: Option<String>,
    pub slug: Option<String>,
    pub grant_count: u32,
    pub long_description: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserAction {
    pub action_type: Option<i32>,
    pub topic_id: Option<u64>,
    pub post_id: Option<u64>,
    pub post_number: Option<u32>,
    pub title: Option<String>,
    pub slug: Option<String>,
    pub username: Option<String>,
    pub acting_username: Option<String>,
    pub acting_avatar_template: Option<String>,
    pub category_id: Option<u64>,
    pub excerpt: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserActionResponse {
    pub user_actions: Vec<UserAction>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct FollowUser {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct InviteLinkDetails {
    pub id: Option<u64>,
    pub invite_key: Option<String>,
    pub max_redemptions_allowed: Option<u32>,
    pub redemption_count: Option<u32>,
    pub expired: Option<bool>,
    pub created_at: Option<String>,
    pub expires_at: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct InviteLink {
    pub invite_link: String,
    pub invite: Option<InviteLinkDetails>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct VotedUser {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoteResponse {
    pub can_vote: bool,
    pub vote_limit: u32,
    pub vote_count: i32,
    pub votes_left: i32,
    pub alert: bool,
    #[serde(default)]
    pub who_voted: Vec<VotedUser>,
}

#[cfg(test)]
mod tests {
    use super::{
        BootstrapArtifacts, CookieSnapshot, LoginPhase, PlatformCookie, SessionSnapshot,
        TopicCategory, TopicDetail, TopicListKind, TopicListQuery, TopicPost, TopicPostStream,
        TopicReaction, TopicThread, TopicThreadFlatPost,
    };

    #[test]
    fn platform_cookie_merge_updates_known_auth_fields() {
        let mut cookies = CookieSnapshot::default();
        cookies.merge_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
        ]);

        assert!(cookies.has_login_session());
        assert!(cookies.has_forum_session());
        assert!(cookies.has_cloudflare_clearance());
    }

    #[test]
    fn platform_cookie_merge_keeps_existing_values_when_batch_has_only_empty_values() {
        let mut cookies = CookieSnapshot {
            t_token: Some("token".into()),
            forum_session: Some("forum".into()),
            cf_clearance: Some("clearance".into()),
            csrf_token: None,
            platform_cookies: Vec::new(),
        };

        cookies.merge_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: String::new(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: String::new(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.t_token.as_deref(), Some("token"));
        assert_eq!(cookies.forum_session.as_deref(), Some("forum"));
        assert_eq!(cookies.cf_clearance.as_deref(), Some("clearance"));
    }

    #[test]
    fn platform_cookie_merge_uses_latest_non_empty_value_per_cookie_name() {
        let mut cookies = CookieSnapshot::default();

        cookies.merge_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "stale".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_t".into(),
                value: String::new(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_t".into(),
                value: "fresh".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.t_token.as_deref(), Some("fresh"));
    }

    #[test]
    fn platform_cookie_apply_replaces_known_auth_fields() {
        let mut cookies = CookieSnapshot {
            t_token: Some("stale-token".into()),
            forum_session: Some("stale-forum".into()),
            cf_clearance: Some("stale-clearance".into()),
            csrf_token: Some("csrf".into()),
            platform_cookies: Vec::new(),
        };

        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "fresh-token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "fresh-clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.t_token.as_deref(), Some("fresh-token"));
        assert_eq!(cookies.forum_session, None);
        assert_eq!(cookies.cf_clearance.as_deref(), Some("fresh-clearance"));
        assert_eq!(cookies.csrf_token.as_deref(), Some("csrf"));
    }

    #[test]
    fn platform_cookie_apply_preserves_full_browser_cookie_batch() {
        let mut cookies = CookieSnapshot::default();

        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "__cf_bm".into(),
                value: "browser-context".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.platform_cookies.len(), 2);
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.name == "__cf_bm" && cookie.value == "browser-context"));
    }

    #[test]
    fn empty_patch_clears_cookie_fields() {
        let mut cookies = CookieSnapshot {
            t_token: Some("token".into()),
            forum_session: Some("forum".into()),
            cf_clearance: Some("clearance".into()),
            csrf_token: Some("csrf".into()),
            platform_cookies: Vec::new(),
        };

        cookies.merge_patch(&CookieSnapshot {
            forum_session: Some(String::new()),
            csrf_token: Some(String::new()),
            ..CookieSnapshot::default()
        });

        assert_eq!(cookies.t_token.as_deref(), Some("token"));
        assert_eq!(cookies.forum_session, None);
        assert_eq!(cookies.csrf_token, None);
        assert_eq!(cookies.cf_clearance.as_deref(), Some("clearance"));
    }

    #[test]
    fn clear_login_state_keeps_non_auth_platform_cookies() {
        let mut cookies = CookieSnapshot::default();
        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "__cf_bm".into(),
                value: "browser-context".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
        ]);

        cookies.clear_login_state(true);

        assert_eq!(cookies.t_token, None);
        assert_eq!(cookies.forum_session, None);
        assert_eq!(cookies.cf_clearance.as_deref(), Some("clearance"));
        assert!(cookies
            .platform_cookies
            .iter()
            .all(|cookie| cookie.name != "_t" && cookie.name != "_forum_session"));
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.name == "cf_clearance"));
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.name == "__cf_bm"));
    }

    #[test]
    fn platform_cookie_apply_drops_expired_cookie_entries() {
        let mut cookies = CookieSnapshot::default();

        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "expired-token".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: Some(1),
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.t_token, None);
        assert_eq!(cookies.forum_session.as_deref(), Some("forum"));
        assert_eq!(cookies.platform_cookies.len(), 1);
        assert_eq!(cookies.platform_cookies[0].name, "_forum_session");
    }

    #[test]
    fn platform_cookie_apply_keeps_host_and_domain_variants_separate() {
        let mut cookies = CookieSnapshot::default();

        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "host-only".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_t".into(),
                value: "domain-scope".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.platform_cookies.len(), 2);
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.domain.as_deref() == Some("linux.do")
                && cookie.value == "host-only"));
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.domain.as_deref() == Some(".linux.do")
                && cookie.value == "domain-scope"));
    }

    #[test]
    fn readiness_ignores_expired_platform_auth_cookies() {
        let cookies = CookieSnapshot {
            t_token: Some("stale-token".into()),
            forum_session: Some("stale-forum".into()),
            cf_clearance: Some("stale-clearance".into()),
            csrf_token: None,
            platform_cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "expired-token".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "expired-forum".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                },
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "expired-clearance".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                },
            ],
        };

        assert!(!cookies.has_login_session());
        assert!(!cookies.has_forum_session());
        assert!(!cookies.has_cloudflare_clearance());
        assert!(!cookies.can_authenticate_requests());
    }

    #[test]
    fn login_phase_advances_with_bootstrap_and_csrf() {
        let mut snapshot = SessionSnapshot::default();
        assert_eq!(snapshot.login_phase(), LoginPhase::Anonymous);

        snapshot.cookies.t_token = Some("token".into());
        assert_eq!(snapshot.login_phase(), LoginPhase::CookiesCaptured);

        snapshot.cookies.forum_session = Some("forum".into());
        snapshot.bootstrap.current_username = Some("alice".into());
        assert_eq!(snapshot.login_phase(), LoginPhase::BootstrapCaptured);

        snapshot.cookies.csrf_token = Some("csrf".into());
        snapshot.bootstrap.preloaded_json =
            Some("{\"currentUser\":{\"username\":\"alice\"}}".into());
        snapshot.bootstrap.has_preloaded_data = true;
        snapshot.bootstrap.has_site_metadata = true;
        snapshot.bootstrap.has_site_settings = true;
        assert_eq!(snapshot.login_phase(), LoginPhase::Ready);
    }

    #[test]
    fn merge_patch_keeps_existing_site_metadata_when_partial_preloaded_lacks_site() {
        let mut bootstrap = BootstrapArtifacts {
            preloaded_json: Some("{\"site\":{\"categories\":[{\"id\":2}]}}".into()),
            has_preloaded_data: true,
            has_site_metadata: true,
            top_tags: vec!["swift".into()],
            can_tag_topics: true,
            categories: vec![TopicCategory {
                id: 2,
                name: "Rust".into(),
                slug: "rust".into(),
                parent_category_id: None,
                color_hex: Some("FFFFFF".into()),
                text_color_hex: Some("000000".into()),
                ..TopicCategory::default()
            }],
            has_site_settings: true,
            enabled_reaction_ids: vec!["heart".into(), "clap".into()],
            min_post_length: 20,
            min_topic_title_length: 15,
            min_first_post_length: 20,
            default_composer_category: Some(2),
            ..BootstrapArtifacts::default()
        };

        bootstrap.merge_patch(&BootstrapArtifacts {
            preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
            has_preloaded_data: true,
            ..BootstrapArtifacts::default()
        });

        assert!(bootstrap.has_site_metadata);
        assert_eq!(bootstrap.top_tags, vec!["swift"]);
        assert!(bootstrap.can_tag_topics);
        assert_eq!(bootstrap.categories.len(), 1);
        assert!(bootstrap.has_site_settings);
        assert_eq!(bootstrap.enabled_reaction_ids, vec!["heart", "clap"]);
        assert_eq!(bootstrap.min_post_length, 20);
        assert_eq!(bootstrap.min_topic_title_length, 15);
        assert_eq!(bootstrap.min_first_post_length, 20);
        assert_eq!(bootstrap.default_composer_category, Some(2));
    }

    #[test]
    fn merge_patch_updates_site_metadata_and_settings_when_present() {
        let mut bootstrap = BootstrapArtifacts::default();

        bootstrap.merge_patch(&BootstrapArtifacts {
            preloaded_json: Some("{\"site\":{},\"siteSettings\":{}}".into()),
            has_preloaded_data: true,
            has_site_metadata: true,
            top_tags: vec!["rust".into(), "swift".into(), "rust".into()],
            can_tag_topics: true,
            categories: vec![TopicCategory {
                id: 2,
                name: "Rust".into(),
                slug: "rust".into(),
                parent_category_id: None,
                color_hex: None,
                text_color_hex: None,
                ..TopicCategory::default()
            }],
            has_site_settings: true,
            enabled_reaction_ids: vec!["heart".into(), "clap".into(), "heart".into()],
            min_post_length: 18,
            min_topic_title_length: 16,
            min_first_post_length: 24,
            default_composer_category: Some(2),
            ..BootstrapArtifacts::default()
        });

        assert!(bootstrap.has_site_metadata);
        assert_eq!(bootstrap.top_tags, vec!["rust", "swift"]);
        assert!(bootstrap.can_tag_topics);
        assert_eq!(bootstrap.categories.len(), 1);
        assert!(bootstrap.has_site_settings);
        assert_eq!(bootstrap.enabled_reaction_ids, vec!["heart", "clap"]);
        assert_eq!(bootstrap.min_post_length, 18);
        assert_eq!(bootstrap.min_topic_title_length, 16);
        assert_eq!(bootstrap.min_first_post_length, 24);
        assert_eq!(bootstrap.default_composer_category, Some(2));
    }

    #[test]
    fn merge_patch_applies_site_metadata_without_preloaded_payload() {
        let mut bootstrap = BootstrapArtifacts {
            preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
            has_preloaded_data: true,
            ..BootstrapArtifacts::default()
        };

        bootstrap.merge_patch(&BootstrapArtifacts {
            has_site_metadata: true,
            top_tags: vec!["rust".into(), "swift".into()],
            can_tag_topics: true,
            categories: vec![TopicCategory {
                id: 2,
                name: "Rust".into(),
                slug: "rust".into(),
                parent_category_id: None,
                color_hex: None,
                text_color_hex: None,
                ..TopicCategory::default()
            }],
            ..BootstrapArtifacts::default()
        });

        assert!(bootstrap.has_site_metadata);
        assert_eq!(bootstrap.top_tags, vec!["rust", "swift"]);
        assert!(bootstrap.can_tag_topics);
        assert_eq!(bootstrap.categories.len(), 1);
        assert!(bootstrap.has_preloaded_data);
    }

    #[test]
    fn topic_detail_interaction_count_adds_non_heart_reactions_to_topic_likes() {
        let detail = TopicDetail {
            like_count: 21,
            post_stream: TopicPostStream {
                posts: vec![
                    TopicPost {
                        reactions: vec![
                            TopicReaction {
                                id: "heart".into(),
                                count: 5,
                                ..TopicReaction::default()
                            },
                            TopicReaction {
                                id: "clap".into(),
                                count: 2,
                                ..TopicReaction::default()
                            },
                        ],
                        ..TopicPost::default()
                    },
                    TopicPost {
                        reactions: vec![TopicReaction {
                            id: "TADA".into(),
                            count: 3,
                            ..TopicReaction::default()
                        }],
                        ..TopicPost::default()
                    },
                ],
                ..TopicPostStream::default()
            },
            ..TopicDetail::default()
        };

        assert_eq!(detail.interaction_count(), 26);
    }

    #[test]
    fn same_origin_message_bus_does_not_require_shared_session_key() {
        let snapshot = SessionSnapshot {
            cookies: CookieSnapshot {
                t_token: Some("token".into()),
                forum_session: Some("forum".into()),
                ..CookieSnapshot::default()
            },
            bootstrap: BootstrapArtifacts {
                base_url: "https://linux.do".into(),
                long_polling_base_url: Some("https://linux.do".into()),
                current_username: Some("alice".into()),
                preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
                has_preloaded_data: true,
                ..BootstrapArtifacts::default()
            },
            browser_user_agent: None,
        };

        let readiness = snapshot.readiness();

        assert!(!readiness.has_shared_session_key);
        assert!(readiness.can_open_message_bus);
    }

    #[test]
    fn cross_origin_message_bus_requires_shared_session_key() {
        let snapshot = SessionSnapshot {
            cookies: CookieSnapshot {
                t_token: Some("token".into()),
                forum_session: Some("forum".into()),
                ..CookieSnapshot::default()
            },
            bootstrap: BootstrapArtifacts {
                base_url: "https://linux.do".into(),
                long_polling_base_url: Some("https://poll.linux.do".into()),
                current_username: Some("alice".into()),
                preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
                has_preloaded_data: true,
                ..BootstrapArtifacts::default()
            },
            browser_user_agent: None,
        };

        let readiness = snapshot.readiness();

        assert!(!readiness.has_shared_session_key);
        assert!(!readiness.can_open_message_bus);
    }

    #[test]
    fn clear_login_state_preserves_cf_when_requested() {
        let mut snapshot = SessionSnapshot {
            cookies: CookieSnapshot {
                t_token: Some("token".into()),
                forum_session: Some("forum".into()),
                cf_clearance: Some("clearance".into()),
                csrf_token: Some("csrf".into()),
                platform_cookies: Vec::new(),
            },
            bootstrap: BootstrapArtifacts {
                base_url: "https://linux.do".into(),
                discourse_base_uri: Some("/".into()),
                shared_session_key: Some("shared".into()),
                current_username: Some("alice".into()),
                current_user_id: Some(1),
                notification_channel_position: Some(42),
                long_polling_base_url: Some("https://linux.do".into()),
                turnstile_sitekey: Some("sitekey".into()),
                topic_tracking_state_meta: Some("{\"seq\":1}".into()),
                preloaded_json: Some("{\"ok\":true}".into()),
                has_preloaded_data: true,
                has_site_metadata: true,
                top_tags: vec!["rust".into()],
                can_tag_topics: true,
                categories: Vec::new(),
                has_site_settings: true,
                enabled_reaction_ids: vec!["heart".into(), "clap".into()],
                min_post_length: 20,
                min_topic_title_length: 15,
                min_first_post_length: 20,
                min_personal_message_title_length: 2,
                min_personal_message_post_length: 10,
                default_composer_category: Some(2),
            },
            browser_user_agent: None,
        };

        snapshot.clear_login_state(true);

        assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
        assert_eq!(snapshot.cookies.t_token, None);
        assert_eq!(snapshot.bootstrap.current_username, None);
        assert_eq!(snapshot.bootstrap.current_user_id, None);
        assert_eq!(snapshot.bootstrap.notification_channel_position, None);
        assert_eq!(snapshot.bootstrap.shared_session_key, None);
        assert_eq!(snapshot.bootstrap.preloaded_json, None);
        assert!(!snapshot.bootstrap.has_preloaded_data);
        assert_eq!(
            snapshot.bootstrap.turnstile_sitekey.as_deref(),
            Some("sitekey")
        );
        assert!(!snapshot.bootstrap.has_site_metadata);
        assert_eq!(snapshot.bootstrap.top_tags, Vec::<String>::new());
        assert!(!snapshot.bootstrap.can_tag_topics);
        assert_eq!(snapshot.bootstrap.categories, Vec::new());
        assert!(!snapshot.bootstrap.has_site_settings);
        assert_eq!(snapshot.bootstrap.enabled_reaction_ids, vec!["heart"]);
        assert_eq!(snapshot.bootstrap.min_post_length, 1);
        assert_eq!(snapshot.bootstrap.min_topic_title_length, 15);
        assert_eq!(snapshot.bootstrap.min_first_post_length, 20);
        assert_eq!(snapshot.bootstrap.default_composer_category, None);
    }

    #[test]
    fn topic_thread_groups_nested_replies_without_duplication() {
        let thread = TopicThread::from_posts(&[
            topic_post(1, None),
            topic_post(2, Some(1)),
            topic_post(3, Some(2)),
            topic_post(4, Some(3)),
            topic_post(5, Some(1)),
            topic_post(6, Some(99)),
        ]);

        assert_eq!(thread.original_post_number, Some(1));
        assert_eq!(
            thread
                .reply_sections
                .iter()
                .map(|section| section.anchor_post_number)
                .collect::<Vec<_>>(),
            vec![2, 5, 6]
        );
        assert_eq!(
            thread.reply_sections[0]
                .replies
                .iter()
                .map(|reply| reply.post_number)
                .collect::<Vec<_>>(),
            vec![3, 4]
        );
        assert_eq!(
            thread.reply_sections[0]
                .replies
                .iter()
                .map(|reply| reply.depth)
                .collect::<Vec<_>>(),
            vec![1, 2]
        );
    }

    #[test]
    fn topic_thread_flattens_to_display_order_posts() {
        let posts = vec![
            topic_post(1, None),
            topic_post(2, Some(1)),
            topic_post(3, Some(2)),
            topic_post(4, Some(3)),
            topic_post(5, Some(1)),
            topic_post(6, Some(99)),
        ];
        let thread = TopicThread::from_posts(&posts);

        assert_eq!(
            thread
                .flatten(&posts)
                .into_iter()
                .map(|flat_post: TopicThreadFlatPost| (
                    flat_post.post.post_number,
                    flat_post.depth,
                    flat_post.parent_post_number,
                    flat_post.shows_thread_line,
                    flat_post.is_original_post,
                ))
                .collect::<Vec<_>>(),
            vec![
                (1, 0, None, true, true),
                (2, 0, None, true, false),
                (3, 1, Some(2), true, false),
                (4, 2, Some(3), true, false),
                (5, 0, None, true, false),
                (6, 0, None, false, false),
            ]
        );
    }

    #[test]
    fn topic_list_query_api_path_global() {
        let query = TopicListQuery {
            kind: TopicListKind::Latest,
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/latest.json");

        let query = TopicListQuery {
            kind: TopicListKind::Hot,
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/hot.json");
    }

    #[test]
    fn topic_list_query_api_path_category() {
        let query = TopicListQuery {
            kind: TopicListKind::Latest,
            category_slug: Some("dev".into()),
            category_id: Some(42),
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/c/dev/42/l/latest.json");
    }

    #[test]
    fn topic_list_query_api_path_subcategory() {
        let query = TopicListQuery {
            kind: TopicListKind::New,
            category_slug: Some("rust".into()),
            category_id: Some(99),
            parent_category_slug: Some("dev".into()),
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/c/dev/rust/99/l/new.json");
    }

    #[test]
    fn topic_list_query_api_path_tag() {
        let query = TopicListQuery {
            kind: TopicListKind::Top,
            tag: Some("swift".into()),
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/tag/swift/l/top.json");
    }

    #[test]
    fn topic_list_query_api_path_category_slug_only() {
        let query = TopicListQuery {
            kind: TopicListKind::Latest,
            category_slug: Some("dev".into()),
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/c/dev.json");
    }

    #[test]
    fn topic_list_query_api_path_topic_ids_override() {
        let query = TopicListQuery {
            kind: TopicListKind::New,
            topic_ids: vec![1, 2, 3],
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/latest.json");
    }

    fn topic_post(post_number: u32, reply_to_post_number: Option<u32>) -> TopicPost {
        TopicPost {
            id: u64::from(post_number),
            username: format!("user-{post_number}"),
            name: None,
            avatar_template: None,
            cooked: format!("<p>{post_number}</p>"),
            raw: None,
            post_number,
            post_type: 1,
            created_at: None,
            updated_at: None,
            like_count: 0,
            reply_count: 0,
            reply_to_post_number,
            bookmarked: false,
            bookmark_id: None,
            bookmark_name: None,
            bookmark_reminder_at: None,
            reactions: Vec::new(),
            current_user_reaction: None,
            polls: Vec::new(),
            accepted_answer: false,
            can_edit: false,
            can_delete: false,
            can_recover: false,
            hidden: false,
        }
    }
}
