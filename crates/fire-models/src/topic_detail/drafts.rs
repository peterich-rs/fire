use serde::{Deserialize, Serialize};

use crate::cookie::is_non_empty;

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
