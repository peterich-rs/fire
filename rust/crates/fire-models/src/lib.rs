use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlatformCookie {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookieSnapshot {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
    pub cf_clearance: Option<String>,
    pub csrf_token: Option<String>,
}

impl CookieSnapshot {
    pub fn has_login_session(&self) -> bool {
        is_non_empty(self.t_token.as_deref())
    }

    pub fn has_forum_session(&self) -> bool {
        is_non_empty(self.forum_session.as_deref())
    }

    pub fn has_cloudflare_clearance(&self) -> bool {
        is_non_empty(self.cf_clearance.as_deref())
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
    }

    pub fn clear_login_state(&mut self, preserve_cf_clearance: bool) {
        self.t_token = None;
        self.forum_session = None;
        self.csrf_token = None;
        if !preserve_cf_clearance {
            self.cf_clearance = None;
        }
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
    pub categories: Vec<TopicCategory>,
    #[serde(default = "default_enabled_reaction_ids")]
    pub enabled_reaction_ids: Vec<String>,
    #[serde(default = "default_min_post_length")]
    pub min_post_length: u32,
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
            categories: Vec::new(),
            enabled_reaction_ids: default_enabled_reaction_ids(),
            min_post_length: default_min_post_length(),
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
                self.categories = Vec::new();
                self.enabled_reaction_ids = default_enabled_reaction_ids();
                self.min_post_length = default_min_post_length();
            } else {
                self.preloaded_json = Some(preloaded_json);
                self.has_preloaded_data = true;
                self.categories = patch.categories.clone();
                self.enabled_reaction_ids =
                    normalized_enabled_reaction_ids(patch.enabled_reaction_ids.clone());
                self.min_post_length = patch.min_post_length.max(1);
            }
        } else if patch.has_preloaded_data {
            self.has_preloaded_data = true;
            self.categories = patch.categories.clone();
            self.enabled_reaction_ids =
                normalized_enabled_reaction_ids(patch.enabled_reaction_ids.clone());
            self.min_post_length = patch.min_post_length.max(1);
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
        self.categories = Vec::new();
        self.enabled_reaction_ids = default_enabled_reaction_ids();
        self.min_post_length = default_min_post_length();
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
    pub cookies: Vec<PlatformCookie>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionSnapshot {
    pub cookies: CookieSnapshot,
    pub bootstrap: BootstrapArtifacts,
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
        let can_open_message_bus = can_read_authenticated_api && has_shared_session_key;

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
        if !readiness.can_write_authenticated_api || !readiness.has_preloaded_data {
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
    pub channel: String,
    pub last_message_id: Option<i64>,
    pub scope: MessageBusSubscriptionScope,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageBusEventKind {
    TopicList,
    TopicDetail,
    Notification,
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
    pub unseen: bool,
    pub unread_posts: u32,
    pub new_posts: u32,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
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
pub struct TopicReplyRequest {
    pub topic_id: u64,
    pub raw: String,
    pub reply_to_post_number: Option<u32>,
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
    pub post_number: u32,
    pub post_type: i32,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub like_count: u32,
    pub reply_count: u32,
    pub reply_to_post_number: Option<u32>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub reactions: Vec<TopicReaction>,
    pub current_user_reaction: Option<TopicReaction>,
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

fn latest_non_empty_platform_cookie_value(
    cookies: &[PlatformCookie],
    name: &str,
) -> Option<String> {
    cookies
        .iter()
        .rev()
        .find(|cookie| cookie.name == name && !cookie.value.is_empty())
        .map(|cookie| cookie.value.clone())
}

fn default_enabled_reaction_ids() -> Vec<String> {
    vec!["heart".to_string()]
}

fn default_min_post_length() -> u32 {
    1
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

#[cfg(test)]
mod tests {
    use super::{
        BootstrapArtifacts, CookieSnapshot, LoginPhase, PlatformCookie, SessionSnapshot, TopicPost,
        TopicThread, TopicThreadFlatPost,
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
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
        };

        cookies.merge_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: String::new(),
                domain: None,
                path: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: String::new(),
                domain: None,
                path: None,
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
            },
            PlatformCookie {
                name: "_t".into(),
                value: String::new(),
                domain: None,
                path: None,
            },
            PlatformCookie {
                name: "_t".into(),
                value: "fresh".into(),
                domain: None,
                path: None,
            },
        ]);

        assert_eq!(cookies.t_token.as_deref(), Some("fresh"));
    }

    #[test]
    fn empty_patch_clears_cookie_fields() {
        let mut cookies = CookieSnapshot {
            t_token: Some("token".into()),
            forum_session: Some("forum".into()),
            cf_clearance: Some("clearance".into()),
            csrf_token: Some("csrf".into()),
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
        assert_eq!(snapshot.login_phase(), LoginPhase::Ready);
    }

    #[test]
    fn clear_login_state_preserves_cf_when_requested() {
        let mut snapshot = SessionSnapshot {
            cookies: CookieSnapshot {
                t_token: Some("token".into()),
                forum_session: Some("forum".into()),
                cf_clearance: Some("clearance".into()),
                csrf_token: Some("csrf".into()),
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
                categories: Vec::new(),
                enabled_reaction_ids: vec!["heart".into(), "clap".into()],
                min_post_length: 20,
            },
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
        assert_eq!(snapshot.bootstrap.categories, Vec::new());
        assert_eq!(snapshot.bootstrap.enabled_reaction_ids, vec!["heart"]);
        assert_eq!(snapshot.bootstrap.min_post_length, 1);
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

    fn topic_post(post_number: u32, reply_to_post_number: Option<u32>) -> TopicPost {
        TopicPost {
            id: u64::from(post_number),
            username: format!("user-{post_number}"),
            name: None,
            avatar_template: None,
            cooked: format!("<p>{post_number}</p>"),
            post_number,
            post_type: 1,
            created_at: None,
            updated_at: None,
            like_count: 0,
            reply_count: 0,
            reply_to_post_number,
            bookmarked: false,
            bookmark_id: None,
            reactions: Vec::new(),
            current_user_reaction: None,
            accepted_answer: false,
            can_edit: false,
            can_delete: false,
            can_recover: false,
            hidden: false,
        }
    }
}
