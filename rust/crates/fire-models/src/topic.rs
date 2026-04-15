use serde::{Deserialize, Serialize};

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
pub struct RequiredTagGroup {
    pub name: String,
    pub min_count: u32,
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
