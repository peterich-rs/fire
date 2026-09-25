#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn total_unread_badge_matches_official_rules() {
        let response = MyChatChannelsResponse {
            public_channels: vec![ChatChannel {
                id: 1,
                chatable_type: "Category".into(),
                current_user_membership: Some(ChatChannelMembership {
                    muted: false,
                    ..Default::default()
                }),
                ..Default::default()
            }],
            direct_message_channels: vec![
                ChatChannel {
                    id: 2,
                    chatable_type: "DirectMessage".into(),
                    current_user_membership: Some(ChatChannelMembership {
                        muted: false,
                        ..Default::default()
                    }),
                    ..Default::default()
                },
                ChatChannel {
                    id: 3,
                    chatable_type: "DirectMessage".into(),
                    current_user_membership: Some(ChatChannelMembership {
                        muted: true,
                        ..Default::default()
                    }),
                    ..Default::default()
                },
            ],
            channel_tracking: vec![
                ChatChannelTrackingEntry {
                    channel_id: 1,
                    unread_count: 9,
                    mention_count: 2,
                },
                ChatChannelTrackingEntry {
                    channel_id: 2,
                    unread_count: 3,
                    mention_count: 1,
                },
                ChatChannelTrackingEntry {
                    channel_id: 3,
                    unread_count: 100,
                    mention_count: 50,
                },
            ],
            global_bus_last_ids: Vec::new(),
        };

        // public: only mention (2); dm2: 3+1; muted dm3: 0 → 6
        assert_eq!(response.total_unread_badge(), 6);
    }

    #[test]
    fn display_title_prefixes_channel_emoji() {
        let channel = ChatChannel {
            id: 8,
            title: Some("公告".into()),
            emoji: Some("loudspeaker".into()),
            chatable_type: "Category".into(),
            ..Default::default()
        };
        assert_eq!(channel.display_title(), "📢 公告");
        assert_eq!(channel.formatted_emoji().as_deref(), Some("📢"));
    }

    #[test]
    fn display_title_does_not_duplicate_unicode_emoji() {
        let channel = ChatChannel {
            id: 8,
            unicode_title: Some("🔥 热点".into()),
            emoji: Some("fire".into()),
            chatable_type: "Category".into(),
            ..Default::default()
        };
        assert_eq!(channel.display_title(), "🔥 热点");
    }

    #[test]
    fn inbox_channels_sort_by_last_activity() {
        let older = ChatMessage {
            created_at: Some("2026-01-01T00:00:00.000Z".into()),
            ..Default::default()
        };
        let newer = ChatMessage {
            created_at: Some("2026-08-01T00:00:00.000Z".into()),
            ..Default::default()
        };
        let response = MyChatChannelsResponse {
            public_channels: vec![ChatChannel {
                id: 1,
                chatable_type: "Category".into(),
                last_message: Some(older),
                ..Default::default()
            }],
            direct_message_channels: vec![ChatChannel {
                id: 2,
                chatable_type: "DirectMessage".into(),
                last_message: Some(newer),
                ..Default::default()
            }],
            ..Default::default()
        };
        let inbox = response.inbox_channels();
        assert_eq!(
            inbox.iter().map(|channel| channel.id).collect::<Vec<_>>(),
            vec![2, 1]
        );
    }
}
