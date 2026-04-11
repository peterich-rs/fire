use fire_models::{
    Badge, FollowUser, InviteLink, InviteLinkDetails, ProfileSummaryLink, ProfileSummaryReply,
    ProfileSummaryTopCategory, ProfileSummaryTopic, ProfileSummaryUserReference, UserAction,
    UserProfile, UserSummaryResponse, UserSummaryStats,
};
use serde::Deserialize;
use serde_json::Value;

use crate::json_helpers::{boolean, integer_u32, integer_u64, invalid_json, scalar_string};

pub(crate) fn parse_user_profile_value(value: Value) -> Result<UserProfile, serde_json::Error> {
    let user_value = match value {
        Value::Object(ref obj) if obj.contains_key("user") => {
            obj.get("user").cloned().unwrap_or(value.clone())
        }
        other => other,
    };
    UserProfile::deserialize(user_value)
}

pub(crate) fn parse_user_summary_value(
    value: Value,
) -> Result<UserSummaryResponse, serde_json::Error> {
    let root = match &value {
        Value::Object(obj) => obj,
        _ => return Err(serde::de::Error::custom("expected object")),
    };

    let summary_obj = root
        .get("user_summary")
        .cloned()
        .unwrap_or(Value::Object(serde_json::Map::new()));

    let stats: UserSummaryStats = UserSummaryStats::deserialize(&summary_obj)?;

    let top_replies: Vec<ProfileSummaryReply> = summary_obj
        .get("replies")
        .or_else(|| summary_obj.get("top_replies"))
        .cloned()
        .map(|v| Vec::<ProfileSummaryReply>::deserialize(v).unwrap_or_default())
        .unwrap_or_default();

    let top_links: Vec<ProfileSummaryLink> = summary_obj
        .get("links")
        .or_else(|| summary_obj.get("top_links"))
        .cloned()
        .map(|v| Vec::<ProfileSummaryLink>::deserialize(v).unwrap_or_default())
        .unwrap_or_default();

    let top_categories: Vec<ProfileSummaryTopCategory> = summary_obj
        .get("top_categories")
        .cloned()
        .map(|v| Vec::<ProfileSummaryTopCategory>::deserialize(v).unwrap_or_default())
        .unwrap_or_default();

    let most_replied_to_users: Vec<ProfileSummaryUserReference> = summary_obj
        .get("most_replied_to_users")
        .cloned()
        .map(|v| Vec::<ProfileSummaryUserReference>::deserialize(v).unwrap_or_default())
        .unwrap_or_default();

    let most_liked_by_users: Vec<ProfileSummaryUserReference> = summary_obj
        .get("most_liked_by_users")
        .cloned()
        .map(|v| Vec::<ProfileSummaryUserReference>::deserialize(v).unwrap_or_default())
        .unwrap_or_default();

    let most_liked_users: Vec<ProfileSummaryUserReference> = summary_obj
        .get("most_liked_users")
        .cloned()
        .map(|v| Vec::<ProfileSummaryUserReference>::deserialize(v).unwrap_or_default())
        .unwrap_or_default();

    let top_topics: Vec<ProfileSummaryTopic> = root
        .get("topics")
        .cloned()
        .map(|v| Vec::<ProfileSummaryTopic>::deserialize(v).unwrap_or_default())
        .unwrap_or_default();

    let badges: Vec<Badge> = root
        .get("badges")
        .cloned()
        .map(|v| Vec::<Badge>::deserialize(v).unwrap_or_default())
        .unwrap_or_default();

    Ok(UserSummaryResponse {
        stats,
        top_topics,
        top_replies,
        top_links,
        top_categories,
        most_replied_to_users,
        most_liked_by_users,
        most_liked_users,
        badges,
    })
}

pub(crate) fn parse_user_actions_value(value: Value) -> Result<Vec<UserAction>, serde_json::Error> {
    let actions_value = match value {
        Value::Object(ref obj) if obj.contains_key("user_actions") => obj
            .get("user_actions")
            .cloned()
            .unwrap_or(Value::Array(Vec::new())),
        Value::Array(_) => value,
        _ => Value::Array(Vec::new()),
    };
    Vec::<UserAction>::deserialize(actions_value)
}

pub(crate) fn parse_badge_value(value: Value) -> Result<Badge, serde_json::Error> {
    let badge_value = match value {
        Value::Object(ref obj) if obj.contains_key("badge") => {
            obj.get("badge").cloned().unwrap_or(value.clone())
        }
        other => other,
    };
    Badge::deserialize(badge_value)
}

pub(crate) fn parse_follow_users_value(value: Value) -> Result<Vec<FollowUser>, serde_json::Error> {
    let list_value = match value {
        Value::Array(_) => value,
        Value::Object(ref obj) => obj
            .get("users")
            .or_else(|| obj.get("following"))
            .or_else(|| obj.get("followers"))
            .cloned()
            .unwrap_or(Value::Array(Vec::new())),
        _ => Value::Array(Vec::new()),
    };
    Vec::<FollowUser>::deserialize(list_value)
}

pub(crate) fn parse_invite_links_value(value: Value) -> Result<Vec<InviteLink>, serde_json::Error> {
    let mut items = Vec::new();
    match value {
        Value::Array(values) => items.extend(values),
        Value::Object(object) => {
            let invites = object
                .get("invites")
                .or_else(|| object.get("pending_invites"))
                .or_else(|| object.get("invited"))
                .or_else(|| object.get("pending"))
                .cloned();
            if let Some(Value::Array(values)) = invites {
                items.extend(values);
            } else if object.contains_key("invite")
                || object.contains_key("invite_link")
                || object.contains_key("invite_key")
                || object.contains_key("invite_url")
                || object.contains_key("url")
                || object.contains_key("link")
            {
                items.push(Value::Object(object));
            }
        }
        _ => {}
    }

    items
        .into_iter()
        .map(parse_invite_link_value)
        .collect::<Result<Vec<_>, _>>()
}

pub(crate) fn parse_invite_link_value(value: Value) -> Result<InviteLink, serde_json::Error> {
    let Value::Object(mut object) = value else {
        return Err(invalid_json("invite link response root was not an object"));
    };

    let invite_link = scalar_string(object.get("invite_link"))
        .or_else(|| scalar_string(object.get("invite_url")))
        .or_else(|| scalar_string(object.get("url")))
        .or_else(|| scalar_string(object.get("link")))
        .unwrap_or_default();

    let invite = match object.remove("invite") {
        Some(Value::Object(invite_object)) => {
            Some(parse_invite_link_details_object(&invite_object))
        }
        Some(_) => None,
        None => {
            if object.contains_key("invite_key")
                || object.contains_key("expires_at")
                || object.contains_key("max_redemptions_allowed")
            {
                Some(parse_invite_link_details_object(&object))
            } else {
                None
            }
        }
    };

    Ok(InviteLink {
        invite_link,
        invite,
    })
}

fn parse_invite_link_details_object(object: &serde_json::Map<String, Value>) -> InviteLinkDetails {
    InviteLinkDetails {
        id: integer_u64(object.get("id")),
        invite_key: scalar_string(object.get("invite_key")),
        max_redemptions_allowed: integer_u32(object.get("max_redemptions_allowed")),
        redemption_count: integer_u32(object.get("redemption_count")),
        expired: object.get("expired").map(|value| boolean(Some(value))),
        created_at: scalar_string(object.get("created_at")),
        expires_at: scalar_string(object.get("expires_at")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_parse_user_profile_unwraps_user_envelope() {
        let value = json!({
            "user": {
                "id": 42,
                "username": "alice",
                "trust_level": 3,
                "bio_cooked": "<p>Hello</p>"
            }
        });
        let profile = parse_user_profile_value(value).unwrap();
        assert_eq!(profile.id, 42);
        assert_eq!(profile.username, "alice");
        assert_eq!(profile.trust_level, Some(3));
        assert_eq!(profile.bio_cooked.as_deref(), Some("<p>Hello</p>"));
    }

    #[test]
    fn test_parse_user_profile_bare_fallback() {
        let value = json!({
            "id": 99,
            "username": "bob",
            "name": "Bob Smith"
        });
        let profile = parse_user_profile_value(value).unwrap();
        assert_eq!(profile.id, 99);
        assert_eq!(profile.username, "bob");
        assert_eq!(profile.name.as_deref(), Some("Bob Smith"));
    }

    #[test]
    fn test_parse_user_profile_nullable_follow_fields() {
        let value = json!({
            "user": {
                "id": 1,
                "username": "test"
            }
        });
        let profile = parse_user_profile_value(value).unwrap();
        assert_eq!(profile.can_follow, None);
        assert_eq!(profile.is_followed, None);
        assert_eq!(profile.total_followers, None);
        assert_eq!(profile.total_following, None);
    }

    #[test]
    fn test_parse_user_summary_sideload_structure() {
        let value = json!({
            "user_summary": {
                "days_visited": 100,
                "posts_read_count": 500,
                "likes_received": 200,
                "likes_given": 150,
                "topic_count": 30,
                "post_count": 80,
                "time_read": 36000,
                "bookmark_count": 5,
                "replies": [
                    {"id": 1, "topic_id": 10, "like_count": 5}
                ],
                "top_categories": [
                    {"id": 1, "name": "General", "topic_count": 10, "post_count": 20}
                ]
            },
            "topics": [
                {"id": 100, "title": "My Topic", "like_count": 10}
            ],
            "badges": [
                {"id": 1, "name": "First Post", "badge_type_id": 3, "grant_count": 1}
            ]
        });
        let summary = parse_user_summary_value(value).unwrap();
        assert_eq!(summary.stats.days_visited, 100);
        assert_eq!(summary.stats.likes_received, 200);
        assert_eq!(summary.top_topics.len(), 1);
        assert_eq!(summary.top_topics[0].title, "My Topic");
        assert_eq!(summary.badges.len(), 1);
        assert_eq!(summary.badges[0].name, "First Post");
        assert_eq!(summary.top_replies.len(), 1);
        assert_eq!(summary.top_categories.len(), 1);
    }

    #[test]
    fn test_parse_user_actions_array() {
        let value = json!({
            "user_actions": [
                {
                    "action_type": 4,
                    "topic_id": 100,
                    "title": "My Topic",
                    "slug": "my-topic",
                    "username": "alice",
                    "created_at": "2024-01-01T00:00:00.000Z"
                },
                {
                    "action_type": 5,
                    "topic_id": 200,
                    "title": "Other Topic"
                }
            ]
        });
        let actions = parse_user_actions_value(value).unwrap();
        assert_eq!(actions.len(), 2);
        assert_eq!(actions[0].action_type, Some(4));
        assert_eq!(actions[0].title.as_deref(), Some("My Topic"));
        assert_eq!(actions[1].action_type, Some(5));
    }

    #[test]
    fn test_parse_badge_value_unwraps_badge_envelope() {
        let value = json!({
            "badge": {
                "id": 7,
                "name": "Great Reply",
                "badge_type_id": 1,
                "grant_count": 12,
                "long_description": "<p>Detailed</p>"
            }
        });
        let badge = parse_badge_value(value).unwrap();
        assert_eq!(badge.id, 7);
        assert_eq!(badge.name, "Great Reply");
        assert_eq!(badge.badge_type_id, 1);
        assert_eq!(badge.grant_count, 12);
        assert_eq!(badge.long_description.as_deref(), Some("<p>Detailed</p>"));
    }

    #[test]
    fn test_parse_follow_users_value_accepts_array_payload() {
        let value = json!([
            {
                "id": 1,
                "username": "alice",
                "name": "Alice",
                "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
            }
        ]);
        let users = parse_follow_users_value(value).unwrap();
        assert_eq!(users.len(), 1);
        assert_eq!(users[0].username, "alice");
    }

    #[test]
    fn test_parse_invite_links_value_accepts_pending_wrapper() {
        let value = json!({
            "pending_invites": [
                {
                    "invite_url": "https://linux.do/invites/fire",
                    "invite": {
                        "id": 9,
                        "invite_key": "fire",
                        "max_redemptions_allowed": 5,
                        "redemption_count": 1,
                        "expired": false
                    }
                }
            ]
        });
        let invites = parse_invite_links_value(value).unwrap();
        assert_eq!(invites.len(), 1);
        assert_eq!(invites[0].invite_link, "https://linux.do/invites/fire");
        assert_eq!(
            invites[0].invite.as_ref().and_then(|invite| invite.id),
            Some(9)
        );
    }

    #[test]
    fn test_parse_invite_link_value_promotes_flat_payload() {
        let value = json!({
            "invite_key": "fire",
            "max_redemptions_allowed": 3,
            "redemption_count": 0
        });
        let invite = parse_invite_link_value(value).unwrap();
        assert_eq!(invite.invite_link, "");
        assert_eq!(
            invite
                .invite
                .as_ref()
                .and_then(|details| details.invite_key.as_deref()),
            Some("fire")
        );
    }
}
