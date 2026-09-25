use fire_models::{
    Badge, FollowUser, InviteCreateRequest, InviteLink, TopicListResponse, UserAction, UserProfile,
    UserReactionsResponse, UserSummaryResponse,
};
use http::Method;
use openwire::RequestBody;
use serde_json::{json, Value};
use tracing::info;

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    topic_payloads::RawTopicListResponse,
    user_payloads::{
        parse_badge_value, parse_follow_users_value, parse_invite_link_value,
        parse_invite_links_value, parse_user_actions_value, parse_user_profile_value,
        parse_user_reactions_value, parse_user_summary_value,
    },
};

include!("history.rs");
include!("social.rs");
include!("invites.rs");
include!("profile.rs");
include!("badges.rs");
include!("activity.rs");
fn normalized_user_notification_level(level: &str) -> Result<&'static str, FireCoreError> {
    match level.trim().to_ascii_lowercase().as_str() {
        "normal" => Ok("normal"),
        "mute" => Ok("mute"),
        "ignore" => Ok("ignore"),
        other => Err(FireCoreError::InvalidUserNotificationLevel {
            level: other.to_string(),
        }),
    }
}
