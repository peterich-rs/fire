use fire_models::{
    Badge, FollowUser, InviteLink, InviteLinkDetails, ProfileSummaryLink, ProfileSummaryReply,
    ProfileSummaryTopCategory, ProfileSummaryTopic, ProfileSummaryUserReference, UserAction,
    UserProfile, UserReaction, UserReactionsResponse, UserSummaryResponse, UserSummaryStats,
};
use serde_json::{Map, Value};

use crate::json_helpers::{
    boolean, integer_i32, integer_u32, integer_u64, invalid_json, optional_boolean,
    parse_array_items_lossy, scalar_string,
};

include!("profile.rs");
include!("summary.rs");
include!("activity.rs");
include!("reactions.rs");
include!("badges.rs");
include!("social.rs");
include!("invites.rs");
include!("helpers.rs");
include!("tests.rs");
