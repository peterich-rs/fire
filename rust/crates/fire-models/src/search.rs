use serde::{Deserialize, Serialize};

use crate::topic::RequiredTagGroup;

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
