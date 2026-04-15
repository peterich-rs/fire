use serde::{Deserialize, Serialize};

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
