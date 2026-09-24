mod deser;
mod detail;
mod list;
mod poll;
mod post;

pub(crate) use detail::{
    parse_topic_ai_summary_value, parse_topic_post_stream_value, RawTopicDetail,
};
pub(crate) use list::RawTopicListResponse;
pub(crate) use poll::{
    parse_poll_response_value, parse_vote_response_value, parse_voted_users_value,
};
pub(crate) use post::{
    parse_post_reaction_update_value, parse_post_reply_ids_value,
    parse_reaction_users_groups_value, parse_topic_post_boost_value, parse_topic_post_list_value,
    parse_topic_post_value,
};

#[cfg(test)]
mod tests {
    use super::*;
    use fire_models::TopicThread;
    use serde_json::json;

    fn sample_raw_topic_detail() -> RawTopicDetail {
        serde_json::from_value(json!({
            "id": 42,
            "title": "Topic",
            "slug": "topic",
            "posts_count": 2,
            "post_stream": {
                "posts": [
                    {
                        "id": 101,
                        "username": "alice",
                        "cooked": "<p>root</p>",
                        "post_number": 1,
                        "reply_count": 1,
                        "can_boost": true,
                        "boosts": [
                            {
                                "id": 501,
                                "cooked": "<p>Hello <img class=\"emoji\" title=\":wave:\" alt=\":wave:\" src=\"/images/emoji/twitter/wave.png?v=12\"></p>",
                                "user": {
                                    "id": 7,
                                    "username": "carol",
                                    "name": "Carol",
                                    "avatar_template": "/user_avatar/linux.do/carol/{size}/1.png"
                                },
                                "can_delete": true,
                                "can_flag": true,
                                "user_flag_status": 0,
                                "available_flags": ["off_topic", 9]
                            }
                        ]
                    },
                    {
                        "id": 102,
                        "username": "bob",
                        "cooked": "<p>reply</p>",
                        "post_number": 2,
                        "reply_to_post_number": 1
                    }
                ],
                "stream": [101, 102]
            },
            "details": {}
        }))
        .expect("sample topic detail should deserialize")
    }

    #[test]
    fn lightweight_topic_detail_skips_thread_state() {
        let detail = sample_raw_topic_detail().into_topic_detail(false, "https://linux.do");

        assert_eq!(detail.thread, TopicThread::default());
        assert!(detail.flat_posts.is_empty());
        assert!(detail.timeline_entries.is_empty());
        assert_eq!(detail.post_stream.posts.len(), 2);
    }

    #[test]
    fn full_topic_detail_preserves_thread_state() {
        let detail = sample_raw_topic_detail().into_topic_detail(true, "https://linux.do");

        assert_eq!(detail.thread.original_post_number, Some(1));
        assert_eq!(detail.flat_posts.len(), 2);
        assert!(detail.timeline_entries.is_empty());
    }

    #[test]
    fn parse_topic_post_boost_value_accepts_wrapped_and_flat_payloads() {
        let wrapped = serde_json::json!({
            "boost": {
                "id": 42,
                "cooked": "<p>nice</p>",
                "user": { "id": 7, "username": "alice", "name": "Alice" },
                "can_delete": true,
                "can_flag": false
            }
        });
        let boost = parse_topic_post_boost_value(wrapped).expect("wrapped boost");
        assert_eq!(boost.id, 42);
        assert_eq!(boost.user.username, "alice");
        assert!(boost.can_delete);

        let flat = serde_json::json!({
            "id": 43,
            "cooked": "<p>🔥</p>",
            "user": { "id": 8, "username": "bob" }
        });
        let boost = parse_topic_post_boost_value(flat).expect("flat boost");
        assert_eq!(boost.id, 43);
        assert_eq!(boost.user.username, "bob");
    }

    #[test]
    fn topic_post_boosts_parse_display_text_and_permissions() {
        let detail = sample_raw_topic_detail().into_topic_detail(false, "https://linux.do");
        let post = detail
            .post_stream
            .posts
            .iter()
            .find(|post| post.id == 101)
            .expect("root post");

        assert!(post.can_boost);
        assert_eq!(post.boosts.len(), 1);
        let boost = &post.boosts[0];
        assert_eq!(boost.id, 501);
        assert_eq!(boost.display_text, "Hello :wave:");
        assert_eq!(boost.user.username, "carol");
        assert_eq!(boost.user.name.as_deref(), Some("Carol"));
        assert!(boost.can_delete);
        assert!(boost.can_flag);
        assert_eq!(boost.user_flag_status, Some(0));
        assert_eq!(boost.available_flags, ["off_topic", "9"]);
    }

    #[test]
    fn topic_post_boost_display_text_normalizes_emoji_images_without_alt() {
        let detail = serde_json::from_value::<RawTopicDetail>(json!({
            "id": 42,
            "title": "Topic",
            "slug": "topic",
            "post_stream": {
                "posts": [
                    {
                        "id": 101,
                        "username": "alice",
                        "cooked": "<p>root</p>",
                        "post_number": 1,
                        "boosts": [
                            {
                                "id": 501,
                                "cooked": "<p><img class=\"emoji\" title=\"smile\" src=\"/images/emoji/twitter/smile.png?v=12\"><img class=\"emoji\" src=\"/images/emoji/twitter/wave/t3.png?v=12\"> 🎉</p>",
                                "user": {"id": 7, "username": "carol"}
                            }
                        ]
                    }
                ],
                "stream": [101]
            },
            "details": {}
        }))
        .expect("sample topic detail should deserialize")
        .into_topic_detail(false, "https://linux.do");
        let boost = &detail.post_stream.posts[0].boosts[0];

        assert_eq!(boost.display_text, ":smile: :wave:t3: 🎉");
    }

    #[test]
    fn topic_post_boost_display_text_strips_leading_attribution() {
        let detail = serde_json::from_value::<RawTopicDetail>(json!({
            "id": 42,
            "title": "Topic",
            "slug": "topic",
            "post_stream": {
                "posts": [
                    {
                        "id": 101,
                        "username": "alice",
                        "cooked": "<p>root</p>",
                        "post_number": 1,
                        "boosts": [
                            {
                                "id": 501,
                                "cooked": "<p>@carol: Thanks for the detail</p>",
                                "user": {"id": 7, "username": "carol", "name": "Carol"}
                            }
                        ]
                    }
                ],
                "stream": [101]
            },
            "details": {}
        }))
        .expect("sample topic detail should deserialize")
        .into_topic_detail(false, "https://linux.do");
        let boost = &detail.post_stream.posts[0].boosts[0];

        assert_eq!(boost.display_text, "Thanks for the detail");
    }
}
