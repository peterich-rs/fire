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
        for cookie in cookies {
            match cookie.name.as_str() {
                "_t" => merge_string_patch(&mut self.t_token, Some(cookie.value.clone())),
                "_forum_session" => {
                    merge_string_patch(&mut self.forum_session, Some(cookie.value.clone()));
                }
                "cf_clearance" => {
                    merge_string_patch(&mut self.cf_clearance, Some(cookie.value.clone()));
                }
                _ => {}
            }
        }
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct BootstrapArtifacts {
    pub base_url: String,
    pub discourse_base_uri: Option<String>,
    pub shared_session_key: Option<String>,
    pub current_username: Option<String>,
    pub long_polling_base_url: Option<String>,
    pub turnstile_sitekey: Option<String>,
    pub topic_tracking_state_meta: Option<String>,
    pub preloaded_json: Option<String>,
    pub has_preloaded_data: bool,
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
            } else {
                self.preloaded_json = Some(preloaded_json);
                self.has_preloaded_data = true;
            }
        } else if patch.has_preloaded_data {
            self.has_preloaded_data = true;
        }
    }

    pub fn clear_login_state(&mut self) {
        self.shared_session_key = None;
        self.current_username = None;
        self.long_polling_base_url = None;
        self.topic_tracking_state_meta = None;
        self.preloaded_json = None;
        self.has_preloaded_data = false;
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

    pub fn clear_login_state(&mut self, preserve_cf_clearance: bool) {
        self.cookies.clear_login_state(preserve_cf_clearance);
        self.bootstrap.clear_login_state();
    }
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
pub struct TopicListResponse {
    pub topics: Vec<TopicSummary>,
    pub users: Vec<TopicUser>,
    pub more_topics_url: Option<String>,
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
    pub kind: Option<String>,
    pub count: u32,
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

fn is_non_empty(value: Option<&str>) -> bool {
    value.is_some_and(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::{BootstrapArtifacts, CookieSnapshot, LoginPhase, PlatformCookie, SessionSnapshot};

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
                long_polling_base_url: Some("https://linux.do".into()),
                turnstile_sitekey: Some("sitekey".into()),
                topic_tracking_state_meta: Some("{\"seq\":1}".into()),
                preloaded_json: Some("{\"ok\":true}".into()),
                has_preloaded_data: true,
            },
        };

        snapshot.clear_login_state(true);

        assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
        assert_eq!(snapshot.cookies.t_token, None);
        assert_eq!(snapshot.bootstrap.current_username, None);
        assert_eq!(snapshot.bootstrap.shared_session_key, None);
        assert_eq!(snapshot.bootstrap.preloaded_json, None);
        assert!(!snapshot.bootstrap.has_preloaded_data);
        assert_eq!(
            snapshot.bootstrap.turnstile_sitekey.as_deref(),
            Some("sitekey")
        );
    }
}
