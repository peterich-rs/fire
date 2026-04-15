use serde::{Deserialize, Serialize};
use url::Url;

use crate::cookie::{is_non_empty, merge_string_patch, CookieSnapshot, PlatformCookie};
use crate::topic::TopicCategory;

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

fn merge_number_patch<T>(slot: &mut Option<T>, patch: Option<T>)
where
    T: Copy,
{
    if let Some(value) = patch {
        *slot = Some(value);
    }
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
