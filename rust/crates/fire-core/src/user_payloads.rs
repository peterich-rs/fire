use fire_models::{
    Badge, ProfileSummaryLink, ProfileSummaryReply, ProfileSummaryTopCategory, ProfileSummaryTopic,
    ProfileSummaryUserReference, UserAction, UserProfile, UserSummaryResponse, UserSummaryStats,
};
use serde::Deserialize;
use serde_json::Value;

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
}
