use serde::{Deserialize, Serialize};

use crate::rich_text::AttachedPresentation;

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
    #[serde(default)]
    pub plain_text: String,
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
pub struct PostReactionUpdate {
    pub reactions: Vec<TopicReaction>,
    pub current_user_reaction: Option<TopicReaction>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReactionUser {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReactionUsersGroup {
    pub id: String,
    pub count: u32,
    pub users: Vec<ReactionUser>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicReplyToUser {
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPostBoostUser {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPostBoost {
    pub id: u64,
    pub cooked: String,
    pub display_text: String,
    pub user: TopicPostBoostUser,
    pub can_delete: bool,
    pub can_flag: bool,
    pub user_flag_status: Option<i32>,
    pub available_flags: Vec<String>,
    #[serde(default)]
    pub presented: AttachedPresentation,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPostAuthorMetadata {
    pub user_id: Option<u64>,
    pub user_title: Option<String>,
    pub primary_group_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_name: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub flair_group_id: Option<u64>,
    pub moderator: bool,
    pub admin: bool,
    pub group_moderator: bool,
    pub user_status_emoji: Option<String>,
    pub user_status_description: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPost {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub author_metadata: TopicPostAuthorMetadata,
    pub cooked: String,
    pub raw: Option<String>,
    pub post_number: u32,
    pub post_type: i32,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub like_count: u32,
    pub reply_count: u32,
    pub reply_to_post_number: Option<u32>,
    pub reply_to_user: Option<TopicReplyToUser>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub reactions: Vec<TopicReaction>,
    pub current_user_reaction: Option<TopicReaction>,
    pub boosts: Vec<TopicPostBoost>,
    pub can_boost: bool,
    pub polls: Vec<Poll>,
    pub accepted_answer: bool,
    pub can_accept_answer: bool,
    pub can_unaccept_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub hidden: bool,
    #[serde(default)]
    pub presented: AttachedPresentation,
}

impl TopicPost {
    pub fn reuse_presentation_from(&mut self, previous: &Self) {
        if self.cooked == previous.cooked {
            if let Some(presented) = previous.presented.arc() {
                self.presented = AttachedPresentation::some(presented);
            }
        }
        for boost in &mut self.boosts {
            if let Some(previous_boost) = previous.boosts.iter().find(|item| item.id == boost.id) {
                boost.reuse_presentation_from(previous_boost);
            }
        }
    }
}

impl TopicPostBoost {
    pub fn reuse_presentation_from(&mut self, previous: &Self) {
        if self.cooked == previous.cooked {
            if let Some(presented) = previous.presented.arc() {
                self.presented = AttachedPresentation::some(presented);
            }
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPostStream {
    pub posts: Vec<TopicPost>,
    pub stream: Vec<u64>,
}
