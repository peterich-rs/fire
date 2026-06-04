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
    pub muted: Option<bool>,
    pub ignored: Option<bool>,
    pub can_mute_user: Option<bool>,
    pub can_ignore_user: Option<bool>,
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
pub struct UserReaction {
    pub id: u64,
    pub post_id: u64,
    pub topic_id: u64,
    pub post_number: Option<u32>,
    pub topic_title: Option<String>,
    pub excerpt: Option<String>,
    pub reaction_value: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserReactionsResponse {
    pub reactions: Vec<UserReaction>,
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserStatus {
    pub description: Option<String>,
    pub emoji: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CurrentUserSnapshot {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub animated_avatar: Option<String>,
    pub trust_level: u8,
    #[serde(default)]
    pub status: Option<UserStatus>,
    pub flair_url: Option<String>,
    pub flair_name: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub flair_group_id: Option<u64>,
    pub gamification_score: Option<i64>,
    #[serde(default)]
    pub unread_notifications: u32,
    #[serde(default)]
    pub unread_high_priority_notifications: u32,
    #[serde(default)]
    pub all_unread_notifications_count: u32,
    #[serde(default)]
    pub seen_notification_id: u64,
    #[serde(default = "default_notification_channel_position")]
    pub notification_channel_position: i64,
    pub last_posted_at: Option<String>,
    pub last_seen_at: Option<String>,
    pub created_at: Option<String>,
    pub location: Option<String>,
    pub website: Option<String>,
    pub website_name: Option<String>,
    pub can_follow: Option<bool>,
    pub is_followed: Option<bool>,
    pub total_followers: Option<u32>,
    pub total_following: Option<u32>,
    pub can_send_private_messages: Option<bool>,
    pub can_send_private_message_to_user: Option<bool>,
    pub muted: Option<bool>,
    pub ignored: Option<bool>,
    pub can_mute_user: Option<bool>,
    pub can_ignore_user: Option<bool>,
    pub suspend_reason: Option<String>,
    pub suspended_till: Option<String>,
    pub silence_reason: Option<String>,
    pub silenced_till: Option<String>,
}

impl Default for CurrentUserSnapshot {
    fn default() -> Self {
        Self {
            id: 0,
            username: String::new(),
            name: None,
            avatar_template: None,
            animated_avatar: None,
            trust_level: 0,
            status: None,
            flair_url: None,
            flair_name: None,
            flair_bg_color: None,
            flair_color: None,
            flair_group_id: None,
            gamification_score: None,
            unread_notifications: 0,
            unread_high_priority_notifications: 0,
            all_unread_notifications_count: 0,
            seen_notification_id: 0,
            notification_channel_position: default_notification_channel_position(),
            last_posted_at: None,
            last_seen_at: None,
            created_at: None,
            location: None,
            website: None,
            website_name: None,
            can_follow: None,
            is_followed: None,
            total_followers: None,
            total_following: None,
            can_send_private_messages: None,
            can_send_private_message_to_user: None,
            muted: None,
            ignored: None,
            can_mute_user: None,
            can_ignore_user: None,
            suspend_reason: None,
            suspended_till: None,
            silence_reason: None,
            silenced_till: None,
        }
    }
}

fn default_notification_channel_position() -> i64 {
    -1
}
