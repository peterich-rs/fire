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
        assert_eq!(profile.bio_plain_text.as_deref(), Some("Hello"));
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
                "is_followed": 0,
                "muted": "1",
                "ignored": false,
                "can_mute_user": true,
                "can_ignore_user": "0"
            }
        });
        let profile = parse_user_profile_value(value).unwrap();
        assert_eq!(profile.id, 7);
        assert_eq!(profile.trust_level, Some(3));
        assert_eq!(profile.total_followers, Some(12));
        assert_eq!(profile.total_following, Some(5));
        assert_eq!(profile.can_follow, Some(true));
        assert_eq!(profile.is_followed, Some(false));
        assert_eq!(profile.muted, Some(true));
        assert_eq!(profile.ignored, Some(false));
        assert_eq!(profile.can_mute_user, Some(true));
        assert_eq!(profile.can_ignore_user, Some(false));
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
    fn test_parse_user_reactions_accepts_wrapper_payload() {
        let value = json!({
            "reactions": [
                {
                    "id": "77",
                    "post_id": "9001",
                    "post": {
                        "topic_id": "123",
                        "post_number": "4",
                        "topic_title": "Fire topic",
                        "excerpt": "<p>Hello Fire</p>"
                    },
                    "reaction": {
                        "reaction_value": "heart"
                    },
                    "created_at": "2026-05-01T00:00:00Z"
                }
            ]
        });

        let response = parse_user_reactions_value(value).unwrap();
        assert_eq!(response.reactions.len(), 1);
        let reaction = &response.reactions[0];
        assert_eq!(reaction.id, 77);
        assert_eq!(reaction.post_id, 9001);
        assert_eq!(reaction.topic_id, 123);
        assert_eq!(reaction.post_number, Some(4));
        assert_eq!(reaction.topic_title.as_deref(), Some("Fire topic"));
        assert_eq!(reaction.excerpt.as_deref(), Some("<p>Hello Fire</p>"));
        assert_eq!(reaction.reaction_value.as_deref(), Some("heart"));
        assert_eq!(reaction.created_at.as_deref(), Some("2026-05-01T00:00:00Z"));
    }

    #[test]
    fn test_parse_user_reactions_accepts_array_and_skips_malformed_items() {
        let value = json!([
            1,
            {
                "id": 78,
                "post_id": 9002,
                "topic_id": 124,
                "post_number": 2,
                "topic_title": "Flat topic",
                "excerpt": "flat excerpt",
                "reaction_value": "clap"
            }
        ]);

        let response = parse_user_reactions_value(value).unwrap();
        assert_eq!(response.reactions.len(), 1);
        let reaction = &response.reactions[0];
        assert_eq!(reaction.id, 78);
        assert_eq!(reaction.post_id, 9002);
        assert_eq!(reaction.topic_id, 124);
        assert_eq!(reaction.post_number, Some(2));
        assert_eq!(reaction.topic_title.as_deref(), Some("Flat topic"));
        assert_eq!(reaction.reaction_value.as_deref(), Some("clap"));
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
