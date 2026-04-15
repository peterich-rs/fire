use fire_models::{
    Badge, FollowUser, InviteLink, InviteLinkDetails, ProfileSummaryReply,
    ProfileSummaryTopCategory, ProfileSummaryTopic, ProfileSummaryUserReference, UserAction,
    UserProfile, UserSummaryResponse, UserSummaryStats, VoteResponse, VotedUser,
};

// --- Profile types ---

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserProfileState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub trust_level: u32,
    pub bio_cooked: Option<String>,
    pub created_at: Option<String>,
    pub last_seen_at: Option<String>,
    pub last_posted_at: Option<String>,
    pub flair_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub profile_background_url: Option<String>,
    pub total_followers: u32,
    pub total_following: u32,
    pub can_follow: bool,
    pub is_followed: bool,
    pub can_send_private_message_to_user: bool,
    pub gamification_score: Option<u32>,
    pub trust_level_label: String,
}

impl From<UserProfile> for UserProfileState {
    fn from(value: UserProfile) -> Self {
        let trust_level = value.trust_level.unwrap_or(0);
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            trust_level,
            bio_cooked: value.bio_cooked,
            created_at: value.created_at,
            last_seen_at: value.last_seen_at,
            last_posted_at: value.last_posted_at,
            flair_name: value.flair_name,
            flair_url: value.flair_url,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            profile_background_url: value
                .profile_background_upload_url
                .or(value.card_background_upload_url),
            total_followers: value.total_followers.unwrap_or(0),
            total_following: value.total_following.unwrap_or(0),
            can_follow: value.can_follow.unwrap_or(false),
            is_followed: value.is_followed.unwrap_or(false),
            can_send_private_message_to_user: value
                .can_send_private_message_to_user
                .unwrap_or(false),
            gamification_score: value.gamification_score,
            trust_level_label: trust_level_label(trust_level),
        }
    }
}

pub(crate) fn trust_level_label(level: u32) -> String {
    match level {
        0 => "新人".to_string(),
        1 => "基本".to_string(),
        2 => "成员".to_string(),
        3 => "老手".to_string(),
        4 => "领导者".to_string(),
        _ => format!("TL{level}"),
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserSummaryStatsState {
    pub days_visited: u32,
    pub likes_received: u32,
    pub likes_given: u32,
    pub topic_count: u32,
    pub post_count: u32,
    pub time_read_seconds: u64,
    pub bookmark_count: u32,
}

impl From<UserSummaryStats> for UserSummaryStatsState {
    fn from(value: UserSummaryStats) -> Self {
        Self {
            days_visited: value.days_visited,
            likes_received: value.likes_received,
            likes_given: value.likes_given,
            topic_count: value.topic_count,
            post_count: value.post_count,
            time_read_seconds: value.time_read,
            bookmark_count: value.bookmark_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryTopicState {
    pub id: u64,
    pub title: String,
    pub slug: Option<String>,
    pub like_count: u32,
    pub category_id: Option<u64>,
    pub created_at: Option<String>,
}

impl From<ProfileSummaryTopic> for ProfileSummaryTopicState {
    fn from(value: ProfileSummaryTopic) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            like_count: value.like_count,
            category_id: value.category_id,
            created_at: value.created_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryReplyState {
    pub id: u64,
    pub topic_id: u64,
    pub title: Option<String>,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub post_number: Option<u32>,
}

impl From<ProfileSummaryReply> for ProfileSummaryReplyState {
    fn from(value: ProfileSummaryReply) -> Self {
        Self {
            id: value.id,
            topic_id: value.topic_id,
            title: value.title,
            like_count: value.like_count,
            created_at: value.created_at,
            post_number: value.post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryTopCategoryState {
    pub id: u64,
    pub name: Option<String>,
    pub topic_count: u32,
    pub post_count: u32,
}

impl From<ProfileSummaryTopCategory> for ProfileSummaryTopCategoryState {
    fn from(value: ProfileSummaryTopCategory) -> Self {
        Self {
            id: value.id,
            name: value.name,
            topic_count: value.topic_count,
            post_count: value.post_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryUserReferenceState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
    pub count: u32,
}

impl From<ProfileSummaryUserReference> for ProfileSummaryUserReferenceState {
    fn from(value: ProfileSummaryUserReference) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
            count: value.count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BadgeState {
    pub id: u64,
    pub name: String,
    pub description: Option<String>,
    pub badge_type_id: u32,
    pub icon: Option<String>,
    pub image_url: Option<String>,
    pub slug: Option<String>,
    pub grant_count: u32,
    pub long_description: Option<String>,
}

impl From<Badge> for BadgeState {
    fn from(value: Badge) -> Self {
        Self {
            id: value.id,
            name: value.name,
            description: value.description,
            badge_type_id: value.badge_type_id,
            icon: value.icon,
            image_url: value.image_url,
            slug: value.slug,
            grant_count: value.grant_count,
            long_description: value.long_description,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserSummaryState {
    pub stats: UserSummaryStatsState,
    pub top_topics: Vec<ProfileSummaryTopicState>,
    pub top_replies: Vec<ProfileSummaryReplyState>,
    pub top_categories: Vec<ProfileSummaryTopCategoryState>,
    pub most_liked_by_users: Vec<ProfileSummaryUserReferenceState>,
    pub badges: Vec<BadgeState>,
}

impl From<UserSummaryResponse> for UserSummaryState {
    fn from(value: UserSummaryResponse) -> Self {
        Self {
            stats: value.stats.into(),
            top_topics: value.top_topics.into_iter().map(Into::into).collect(),
            top_replies: value.top_replies.into_iter().map(Into::into).collect(),
            top_categories: value.top_categories.into_iter().map(Into::into).collect(),
            most_liked_by_users: value
                .most_liked_by_users
                .into_iter()
                .map(Into::into)
                .collect(),
            badges: value.badges.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserActionState {
    pub action_type: i32,
    pub topic_id: Option<u64>,
    pub post_number: Option<u32>,
    pub title: Option<String>,
    pub slug: Option<String>,
    pub excerpt: Option<String>,
    pub category_id: Option<u64>,
    pub acting_username: Option<String>,
    pub acting_avatar_template: Option<String>,
    pub created_at: Option<String>,
}

impl From<UserAction> for UserActionState {
    fn from(value: UserAction) -> Self {
        Self {
            action_type: value.action_type.unwrap_or(0),
            topic_id: value.topic_id,
            post_number: value.post_number,
            title: value.title,
            slug: value.slug,
            excerpt: value.excerpt,
            category_id: value.category_id,
            acting_username: value.acting_username,
            acting_avatar_template: value.acting_avatar_template,
            created_at: value.created_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct FollowUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<FollowUser> for FollowUserState {
    fn from(value: FollowUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct InviteLinkDetailsState {
    pub id: Option<u64>,
    pub invite_key: Option<String>,
    pub max_redemptions_allowed: Option<u32>,
    pub redemption_count: Option<u32>,
    pub expired: Option<bool>,
    pub created_at: Option<String>,
    pub expires_at: Option<String>,
}

impl From<InviteLinkDetails> for InviteLinkDetailsState {
    fn from(value: InviteLinkDetails) -> Self {
        Self {
            id: value.id,
            invite_key: value.invite_key,
            max_redemptions_allowed: value.max_redemptions_allowed,
            redemption_count: value.redemption_count,
            expired: value.expired,
            created_at: value.created_at,
            expires_at: value.expires_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct InviteLinkState {
    pub invite_link: String,
    pub invite: Option<InviteLinkDetailsState>,
}

impl From<InviteLink> for InviteLinkState {
    fn from(value: InviteLink) -> Self {
        Self {
            invite_link: value.invite_link,
            invite: value.invite.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct VotedUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<VotedUser> for VotedUserState {
    fn from(value: VotedUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct VoteResponseState {
    pub can_vote: bool,
    pub vote_limit: u32,
    pub vote_count: i32,
    pub votes_left: i32,
    pub alert: bool,
    pub who_voted: Vec<VotedUserState>,
}

impl From<VoteResponse> for VoteResponseState {
    fn from(value: VoteResponse) -> Self {
        Self {
            can_vote: value.can_vote,
            vote_limit: value.vote_limit,
            vote_count: value.vote_count,
            votes_left: value.votes_left,
            alert: value.alert,
            who_voted: value.who_voted.into_iter().map(Into::into).collect(),
        }
    }
}
