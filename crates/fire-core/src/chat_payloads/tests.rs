#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_my_channels_with_tracking_and_dm() {
        let value = json!({
            "public_channels": [{
                "id": 10,
                "title": "general",
                "chatable_type": "Category",
                "chatable": {"name": "General", "color": "0088CC"},
                "current_user_membership": {
                    "following": true,
                    "muted": false,
                    "starred": true,
                    "last_read_message_id": 99
                },
                "meta": {
                    "can_flag": true,
                    "message_bus_last_ids": {
                        "new_messages": 12
                    }
                }
            }],
            "direct_message_channels": [{
                "id": 20,
                "title": "@alice",
                "unicode_title": "@alice",
                "chatable_type": "DirectMessage",
                "chatable": {
                    "group": false,
                    "users": [{
                        "id": 2,
                        "username": "alice",
                        "name": "Alice",
                        "avatar_template": "/user_avatar/alice/{size}.png"
                    }]
                },
                "last_message": {
                    "id": 5,
                    "message": "hello",
                    "cooked": "<p>hello</p>",
                    "user": {"id": 2, "username": "alice"}
                }
            }],
            "tracking": {
                "channel_tracking": {
                    "10": {"unread_count": 0, "mention_count": 1},
                    "20": {"unread_count": 2, "mention_count": 0}
                }
            },
            "meta": {
                "message_bus_last_ids": {
                    "user_tracking_state": 3,
                    "new_channel": 4
                }
            }
        });

        let parsed = parse_my_chat_channels_response_value(value).expect("parse");
        assert_eq!(parsed.public_channels.len(), 1);
        assert_eq!(parsed.direct_message_channels.len(), 1);
        assert!(parsed.direct_message_channels[0].is_direct_message());
        assert_eq!(
            parsed.direct_message_channels[0].dm_users[0].username,
            "alice"
        );
        assert_eq!(
            parsed.direct_message_channels[0]
                .last_message
                .as_ref()
                .map(|m| m.message.as_str()),
            Some("hello")
        );
        assert_eq!(parsed.channel_tracking.len(), 2);
        assert_eq!(parsed.total_unread_badge(), 3); // mention 1 + dm unread 2
        assert_eq!(parsed.global_bus_last_ids.len(), 2);
        assert_eq!(
            parsed.public_channels[0].bus_last_ids.new_messages,
            Some(12)
        );
    }

    #[test]
    fn parses_messages_page_meta() {
        let value = json!({
            "messages": [{
                "id": 1,
                "chat_channel_id": 20,
                "message": "hi",
                "cooked": "<p>hi</p>",
                "edited": false,
                "reactions": [{"emoji": "heart", "count": 1, "reacted": true}],
                "uploads": []
            }],
            "meta": {
                "can_load_more_past": true,
                "can_load_more_future": false,
                "target_message_id": 1
            }
        });
        let parsed =
            parse_chat_messages_response_value(value, 20, "https://linux.do").expect("parse");
        assert_eq!(parsed.messages.len(), 1);
        assert!(parsed.can_load_more_past);
        assert!(!parsed.can_load_more_future);
        assert_eq!(parsed.target_message_id, Some(1));
        assert_eq!(parsed.messages[0].reactions[0].emoji, "heart");
    }

    #[test]
    fn chat_message_from_bus_payload_reads_nested_and_bare_objects() {
        let nested =
            r#"{"chat_message":{"id":7,"chat_channel_id":3,"message":"hi","cooked":"<p>hi</p>"}}"#;
        let nested_message = chat_message_from_bus_payload(nested, Some(9), "https://linux.do")
            .expect("nested chat_message");
        assert_eq!(nested_message.id, 7);
        assert_eq!(nested_message.channel_id, 3);
        assert_eq!(nested_message.cooked, "<p>hi</p>");

        let aliased = r#"{"message":{"id":8,"message":"yo","cooked":"<p>yo</p>"}}"#;
        let aliased_message = chat_message_from_bus_payload(aliased, Some(4), "https://linux.do")
            .expect("message alias");
        assert_eq!(aliased_message.id, 8);
        assert_eq!(aliased_message.channel_id, 4);

        assert!(chat_message_from_bus_payload("[]", None, "https://linux.do").is_none());
        assert!(chat_message_from_bus_payload("not-json", None, "https://linux.do").is_none());
    }

    #[test]
    fn chat_channel_from_bus_payload_reads_last_message() {
        let payload = r#"{
            "channel": {
                "id": 20,
                "title": "@alice",
                "chatable_type": "DirectMessage",
                "last_message": {
                    "id": 5,
                    "message": "hello",
                    "cooked": "<p>hello</p>"
                }
            }
        }"#;
        let channel = chat_channel_from_bus_payload(payload, "https://linux.do").expect("channel");
        assert!(channel.is_direct_message());
        assert_eq!(
            channel.last_message.as_ref().map(|message| message.id),
            Some(5)
        );
        assert_eq!(
            channel
                .last_message
                .as_ref()
                .map(|message| message.cooked.as_str()),
            Some("<p>hello</p>")
        );
    }

    #[test]
    fn chat_bus_event_reads_delete_reaction_and_tracking() {
        let deleted = chat_bus_event_from_payload(
            r#"{"deleted_id":42}"#,
            Some("delete"),
            None,
            "https://linux.do",
        );
        assert!(matches!(
            deleted,
            fire_models::ChatBusEvent::MessageDeleted { id: 42 }
        ));

        let reaction = chat_bus_event_from_payload(
            r#"{"chat_message_id":9,"emoji":"heart","action":"add","user":{"id":3}}"#,
            Some("reaction"),
            None,
            "https://linux.do",
        );
        assert!(matches!(
            reaction,
            fire_models::ChatBusEvent::Reaction {
                message_id: 9,
                actor_id: Some(3),
                ..
            }
        ));

        let tracking = chat_bus_event_from_payload(
            r#"{"channel_id":8,"unread_count":2,"mention_count":1}"#,
            None,
            None,
            "https://linux.do",
        );
        assert!(matches!(
            tracking,
            fire_models::ChatBusEvent::Tracking {
                channel_id: 8,
                unread: 2,
                mention: 1,
                thread_id: None,
            }
        ));
    }
}
