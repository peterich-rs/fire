use fire_models::{
    Badge, FollowUser, InviteLink, InviteLinkDetails, ProfileSummaryLink, ProfileSummaryReply,
    ProfileSummaryTopCategory, ProfileSummaryTopic, ProfileSummaryUserReference, UserAction,
    UserProfile, UserSummaryResponse, UserSummaryStats,
};
use serde_json::{Map, Value};

use crate::json_helpers::{
    boolean, integer_i32, integer_u32, integer_u64, invalid_json, optional_boolean,
    parse_array_items_lossy, scalar_string,
};

pub(crate) fn parse_user_profile_value(value: Value) -> Result<UserProfile, serde_json::Error> {
    let user_value = match value {
        Value::Object(ref obj) if obj.contains_key("user") => {
            obj.get("user").cloned().unwrap_or(value.clone())
        }
        other => other,
    };
    let Value::Object(object) = user_value else {
        return Err(invalid_json("user profile response root was not an object"));
    };

    Ok(UserProfile {
        id: integer_u64(object.get("id")).unwrap_or_default(),
        username: scalar_string(object.get("username")).unwrap_or_default(),
        name: scalar_string(object.get("name")),
        avatar_template: scalar_string(object.get("avatar_template")),
        trust_level: integer_u32(object.get("trust_level")),
        bio_cooked: scalar_string(object.get("bio_cooked")),
        created_at: scalar_string(object.get("created_at")),
        last_seen_at: scalar_string(object.get("last_seen_at")),
        last_posted_at: scalar_string(object.get("last_posted_at")),
        flair_name: scalar_string(object.get("flair_name")),
        flair_url: scalar_string(object.get("flair_url")),
        flair_bg_color: scalar_string(object.get("flair_bg_color")),
        flair_color: scalar_string(object.get("flair_color")),
        profile_background_upload_url: scalar_string(object.get("profile_background_upload_url")),
        card_background_upload_url: scalar_string(object.get("card_background_upload_url")),
        total_followers: integer_u32(object.get("total_followers")),
        total_following: integer_u32(object.get("total_following")),
        can_follow: optional_boolean(object.get("can_follow")),
        is_followed: optional_boolean(object.get("is_followed")),
        gamification_score: integer_u32(object.get("gamification_score")),
        suspended_till: scalar_string(object.get("suspended_till")),
        silenced_till: scalar_string(object.get("silenced_till")),
    })
}

pub(crate) fn parse_user_summary_value(
    value: Value,
) -> Result<UserSummaryResponse, serde_json::Error> {
    let root = match &value {
        Value::Object(obj) => obj,
        _ => return Err(invalid_json("user summary response root was not an object")),
    };

    let empty = Map::new();
    let summary_obj = root
        .get("user_summary")
        .and_then(Value::as_object)
        .unwrap_or(&empty);
    let stats = parse_user_summary_stats_object(summary_obj);
    let top_replies = parse_array_items_lossy(
        array_items(
            summary_obj
                .get("replies")
                .or_else(|| summary_obj.get("top_replies")),
        ),
        "profile summary reply",
        parse_profile_summary_reply_value,
    );
    let top_links = parse_array_items_lossy(
        array_items(
            summary_obj
                .get("links")
                .or_else(|| summary_obj.get("top_links")),
        ),
        "profile summary link",
        parse_profile_summary_link_value,
    );
    let top_categories = parse_array_items_lossy(
        array_items(summary_obj.get("top_categories")),
        "profile summary top category",
        parse_profile_summary_top_category_value,
    );
    let most_replied_to_users = parse_array_items_lossy(
        array_items(summary_obj.get("most_replied_to_users")),
        "profile summary user reference",
        parse_profile_summary_user_reference_value,
    );
    let most_liked_by_users = parse_array_items_lossy(
        array_items(summary_obj.get("most_liked_by_users")),
        "profile summary user reference",
        parse_profile_summary_user_reference_value,
    );
    let most_liked_users = parse_array_items_lossy(
        array_items(summary_obj.get("most_liked_users")),
        "profile summary user reference",
        parse_profile_summary_user_reference_value,
    );
    let top_topics = parse_array_items_lossy(
        array_items(root.get("topics")),
        "profile summary topic",
        parse_profile_summary_topic_value,
    );
    let badges =
        parse_array_items_lossy(array_items(root.get("badges")), "badge", parse_badge_item);

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
    Ok(parse_array_items_lossy(
        array_items(Some(&actions_value)),
        "user action item",
        parse_user_action_value,
    ))
}

pub(crate) fn parse_badge_value(value: Value) -> Result<Badge, serde_json::Error> {
    let badge_value = match value {
        Value::Object(ref obj) if obj.contains_key("badge") => {
            obj.get("badge").cloned().unwrap_or(value.clone())
        }
        other => other,
    };
    parse_badge_item(&badge_value)
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
    Ok(parse_array_items_lossy(
        array_items(Some(&list_value)),
        "follow user item",
        parse_follow_user_value,
    ))
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

    Ok(parse_array_items_lossy(
        &items,
        "invite link item",
        |item| parse_invite_link_value(item.clone()),
    ))
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

fn parse_user_summary_stats_object(object: &Map<String, Value>) -> UserSummaryStats {
    UserSummaryStats {
        days_visited: integer_u32(object.get("days_visited")).unwrap_or_default(),
        posts_read_count: integer_u32(object.get("posts_read_count")).unwrap_or_default(),
        likes_received: integer_u32(object.get("likes_received")).unwrap_or_default(),
        likes_given: integer_u32(object.get("likes_given")).unwrap_or_default(),
        topic_count: integer_u32(object.get("topic_count")).unwrap_or_default(),
        post_count: integer_u32(object.get("post_count")).unwrap_or_default(),
        time_read: integer_u64(object.get("time_read")).unwrap_or_default(),
        bookmark_count: integer_u32(object.get("bookmark_count")).unwrap_or_default(),
    }
}

fn parse_profile_summary_topic_value(
    value: &Value,
) -> Result<ProfileSummaryTopic, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary topic item was not an object"))?;
    let id = integer_u64(object.get("id"))
        .ok_or_else(|| invalid_json("profile summary topic item did not contain an id"))?;
    Ok(ProfileSummaryTopic {
        id,
        title: scalar_string(object.get("title")).unwrap_or_default(),
        slug: scalar_string(object.get("slug")),
        like_count: integer_u32(object.get("like_count")).unwrap_or_default(),
        category_id: integer_u64(object.get("category_id")),
        created_at: scalar_string(object.get("created_at")),
    })
}

fn parse_profile_summary_reply_value(
    value: &Value,
) -> Result<ProfileSummaryReply, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary reply item was not an object"))?;
    let id = integer_u64(object.get("id"))
        .ok_or_else(|| invalid_json("profile summary reply item did not contain an id"))?;
    let topic_id = integer_u64(object.get("topic_id"))
        .ok_or_else(|| invalid_json("profile summary reply item did not contain a topic_id"))?;
    Ok(ProfileSummaryReply {
        id,
        topic_id,
        title: scalar_string(object.get("title")),
        like_count: integer_u32(object.get("like_count")).unwrap_or_default(),
        created_at: scalar_string(object.get("created_at")),
        post_number: integer_u32(object.get("post_number")),
    })
}

fn parse_profile_summary_link_value(
    value: &Value,
) -> Result<ProfileSummaryLink, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary link item was not an object"))?;
    let url = scalar_string(object.get("url"))
        .ok_or_else(|| invalid_json("profile summary link item did not contain a url"))?;
    Ok(ProfileSummaryLink {
        url,
        title: scalar_string(object.get("title")),
        clicks: integer_u32(object.get("clicks")).unwrap_or_default(),
        topic_id: integer_u64(object.get("topic_id")),
        post_number: integer_u32(object.get("post_number")),
    })
}

fn parse_profile_summary_top_category_value(
    value: &Value,
) -> Result<ProfileSummaryTopCategory, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary top category item was not an object"))?;
    let id = integer_u64(object.get("id"))
        .ok_or_else(|| invalid_json("profile summary top category item did not contain an id"))?;
    Ok(ProfileSummaryTopCategory {
        id,
        name: scalar_string(object.get("name")),
        topic_count: integer_u32(object.get("topic_count")).unwrap_or_default(),
        post_count: integer_u32(object.get("post_count")).unwrap_or_default(),
    })
}

fn parse_profile_summary_user_reference_value(
    value: &Value,
) -> Result<ProfileSummaryUserReference, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary user reference item was not an object"))?;
    let id = integer_u64(object.get("id")).unwrap_or_default();
    let username = scalar_string(object.get("username")).unwrap_or_default();
    if id == 0 && username.is_empty() {
        return Err(invalid_json(
            "profile summary user reference item did not contain an id or username",
        ));
    }
    Ok(ProfileSummaryUserReference {
        id,
        username,
        avatar_template: scalar_string(object.get("avatar_template")),
        count: integer_u32(object.get("count")).unwrap_or_default(),
    })
}

fn parse_badge_item(value: &Value) -> Result<Badge, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("badge response root was not an object"))?;
    Ok(Badge {
        id: integer_u64(object.get("id")).unwrap_or_default(),
        name: scalar_string(object.get("name")).unwrap_or_default(),
        description: scalar_string(object.get("description")),
        badge_type_id: integer_u32(object.get("badge_type_id")).unwrap_or_default(),
        image_url: scalar_string(object.get("image_url")),
        icon: scalar_string(object.get("icon")),
        slug: scalar_string(object.get("slug")),
        grant_count: integer_u32(object.get("grant_count")).unwrap_or_default(),
        long_description: scalar_string(object.get("long_description")),
    })
}

fn parse_user_action_value(value: &Value) -> Result<UserAction, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("user action item was not an object"))?;
    Ok(UserAction {
        action_type: integer_i32(object.get("action_type")),
        topic_id: integer_u64(object.get("topic_id")),
        post_id: integer_u64(object.get("post_id")),
        post_number: integer_u32(object.get("post_number")),
        title: scalar_string(object.get("title")),
        slug: scalar_string(object.get("slug")),
        username: scalar_string(object.get("username")),
        acting_username: scalar_string(object.get("acting_username")),
        acting_avatar_template: scalar_string(object.get("acting_avatar_template")),
        category_id: integer_u64(object.get("category_id")),
        excerpt: scalar_string(object.get("excerpt")),
        created_at: scalar_string(object.get("created_at")),
    })
}

fn parse_follow_user_value(value: &Value) -> Result<FollowUser, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("follow user item was not an object"))?;
    let id = integer_u64(object.get("id")).unwrap_or_default();
    let username = scalar_string(object.get("username")).unwrap_or_default();
    if id == 0 && username.is_empty() {
        return Err(invalid_json(
            "follow user item did not contain an id or username",
        ));
    }
    Ok(FollowUser {
        id,
        username,
        name: scalar_string(object.get("name")),
        avatar_template: scalar_string(object.get("avatar_template")),
    })
}

fn array_items(value: Option<&Value>) -> &[Value] {
    match value {
        Some(Value::Array(items)) => items.as_slice(),
        _ => &[],
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
    fn test_parse_user_profile_coerces_scalar_fields() {
        let value = json!({
            "user": {
                "id": "7",
                "username": "alice",
                "trust_level": "3",
                "total_followers": "12",
                "total_following": 5,
                "can_follow": "1",
                "is_followed": 0
            }
        });
        let profile = parse_user_profile_value(value).unwrap();
        assert_eq!(profile.id, 7);
        assert_eq!(profile.trust_level, Some(3));
        assert_eq!(profile.total_followers, Some(12));
        assert_eq!(profile.total_following, Some(5));
        assert_eq!(profile.can_follow, Some(true));
        assert_eq!(profile.is_followed, Some(false));
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
    fn test_parse_user_summary_skips_malformed_items_and_coerces_stats() {
        let value = json!({
            "user_summary": {
                "days_visited": "100",
                "posts_read_count": "500",
                "likes_received": "200",
                "likes_given": 150,
                "topic_count": "30",
                "post_count": "80",
                "time_read": "36000",
                "bookmark_count": "5",
                "replies": [
                    1,
                    {"id": "1", "topic_id": "10", "like_count": "5"}
                ],
                "top_categories": [
                    {"name": "missing id"},
                    {"id": "1", "name": "General", "topic_count": "10", "post_count": "20"}
                ],
                "most_liked_users": [
                    {"username": "alice", "count": "3"}
                ]
            },
            "topics": [
                {"title": "missing id"},
                {"id": "100", "title": "My Topic", "like_count": "10"}
            ],
            "badges": [
                1,
                {"id": "1", "name": "First Post", "badge_type_id": "3", "grant_count": "1"}
            ]
        });
        let summary = parse_user_summary_value(value).unwrap();
        assert_eq!(summary.stats.days_visited, 100);
        assert_eq!(summary.stats.time_read, 36_000);
        assert_eq!(summary.top_topics.len(), 1);
        assert_eq!(summary.top_topics[0].id, 100);
        assert_eq!(summary.top_replies.len(), 1);
        assert_eq!(summary.top_replies[0].topic_id, 10);
        assert_eq!(summary.top_categories.len(), 1);
        assert_eq!(summary.top_categories[0].id, 1);
        assert_eq!(summary.most_liked_users.len(), 1);
        assert_eq!(summary.most_liked_users[0].username, "alice");
        assert_eq!(summary.badges.len(), 1);
        assert_eq!(summary.badges[0].badge_type_id, 3);
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
    fn test_parse_user_actions_skip_malformed_items() {
        let value = json!({
            "user_actions": [
                1,
                {
                    "action_type": "4",
                    "topic_id": "100",
                    "title": "My Topic"
                }
            ]
        });
        let actions = parse_user_actions_value(value).unwrap();
        assert_eq!(actions.len(), 1);
        assert_eq!(actions[0].action_type, Some(4));
        assert_eq!(actions[0].topic_id, Some(100));
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
    fn test_parse_follow_users_value_skips_malformed_items_and_coerces_scalars() {
        let value = json!({
            "users": [
                1,
                {
                    "id": "1",
                    "username": "alice",
                    "name": "Alice"
                }
            ]
        });
        let users = parse_follow_users_value(value).unwrap();
        assert_eq!(users.len(), 1);
        assert_eq!(users[0].id, 1);
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
    fn test_parse_invite_links_value_skips_malformed_items() {
        let value = json!({
            "pending_invites": [
                1,
                {
                    "invite_url": "https://linux.do/invites/fire",
                    "invite": {
                        "id": "9",
                        "invite_key": "fire"
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
