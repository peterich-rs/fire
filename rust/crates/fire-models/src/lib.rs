mod cookie;
mod messagebus;
mod notification;
mod search;
mod session;
mod topic;
mod topic_detail;
mod user;

pub use cookie::*;
pub use messagebus::*;
pub use notification::*;
pub use search::*;
pub use session::*;
pub use topic::*;
pub use topic_detail::*;
pub use user::*;

#[cfg(test)]
mod tests {
    use super::{
        BootstrapArtifacts, CookieSnapshot, LoginPhase, PlatformCookie, SessionSnapshot,
        TopicCategory, TopicDetail, TopicListKind, TopicListQuery, TopicPost, TopicPostStream,
        TopicReaction, TopicThread, TopicThreadFlatPost,
    };

    #[test]
    fn platform_cookie_merge_updates_known_auth_fields() {
        let mut cookies = CookieSnapshot::default();
        cookies.merge_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
        ]);

        assert!(cookies.has_login_session());
        assert!(cookies.has_forum_session());
        assert!(cookies.has_cloudflare_clearance());
    }

    #[test]
    fn platform_cookie_merge_keeps_existing_values_when_batch_has_only_empty_values() {
        let mut cookies = CookieSnapshot {
            t_token: Some("token".into()),
            forum_session: Some("forum".into()),
            cf_clearance: Some("clearance".into()),
            csrf_token: None,
            platform_cookies: Vec::new(),
        };

        cookies.merge_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: String::new(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: String::new(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.t_token.as_deref(), Some("token"));
        assert_eq!(cookies.forum_session.as_deref(), Some("forum"));
        assert_eq!(cookies.cf_clearance.as_deref(), Some("clearance"));
    }

    #[test]
    fn platform_cookie_merge_uses_latest_non_empty_value_per_cookie_name() {
        let mut cookies = CookieSnapshot::default();

        cookies.merge_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "stale".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_t".into(),
                value: String::new(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_t".into(),
                value: "fresh".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.t_token.as_deref(), Some("fresh"));
    }

    #[test]
    fn platform_cookie_apply_replaces_known_auth_fields() {
        let mut cookies = CookieSnapshot {
            t_token: Some("stale-token".into()),
            forum_session: Some("stale-forum".into()),
            cf_clearance: Some("stale-clearance".into()),
            csrf_token: Some("csrf".into()),
            platform_cookies: Vec::new(),
        };

        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "fresh-token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "fresh-clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.t_token.as_deref(), Some("fresh-token"));
        assert_eq!(cookies.forum_session, None);
        assert_eq!(cookies.cf_clearance.as_deref(), Some("fresh-clearance"));
        assert_eq!(cookies.csrf_token.as_deref(), Some("csrf"));
    }

    #[test]
    fn platform_cookie_apply_preserves_full_browser_cookie_batch() {
        let mut cookies = CookieSnapshot::default();

        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "__cf_bm".into(),
                value: "browser-context".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.platform_cookies.len(), 2);
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.name == "__cf_bm" && cookie.value == "browser-context"));
    }

    #[test]
    fn empty_patch_clears_cookie_fields() {
        let mut cookies = CookieSnapshot {
            t_token: Some("token".into()),
            forum_session: Some("forum".into()),
            cf_clearance: Some("clearance".into()),
            csrf_token: Some("csrf".into()),
            platform_cookies: Vec::new(),
        };

        cookies.merge_patch(&CookieSnapshot {
            forum_session: Some(String::new()),
            csrf_token: Some(String::new()),
            ..CookieSnapshot::default()
        });

        assert_eq!(cookies.t_token.as_deref(), Some("token"));
        assert_eq!(cookies.forum_session, None);
        assert_eq!(cookies.csrf_token, None);
        assert_eq!(cookies.cf_clearance.as_deref(), Some("clearance"));
    }

    #[test]
    fn clear_login_state_keeps_non_auth_platform_cookies() {
        let mut cookies = CookieSnapshot::default();
        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "__cf_bm".into(),
                value: "browser-context".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
        ]);

        cookies.clear_login_state(true);

        assert_eq!(cookies.t_token, None);
        assert_eq!(cookies.forum_session, None);
        assert_eq!(cookies.cf_clearance.as_deref(), Some("clearance"));
        assert!(cookies
            .platform_cookies
            .iter()
            .all(|cookie| cookie.name != "_t" && cookie.name != "_forum_session"));
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.name == "cf_clearance"));
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.name == "__cf_bm"));
    }

    #[test]
    fn platform_cookie_apply_drops_expired_cookie_entries() {
        let mut cookies = CookieSnapshot::default();

        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "expired-token".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: Some(1),
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.t_token, None);
        assert_eq!(cookies.forum_session.as_deref(), Some("forum"));
        assert_eq!(cookies.platform_cookies.len(), 1);
        assert_eq!(cookies.platform_cookies[0].name, "_forum_session");
    }

    #[test]
    fn platform_cookie_apply_keeps_host_and_domain_variants_separate() {
        let mut cookies = CookieSnapshot::default();

        cookies.apply_platform_cookies(&[
            PlatformCookie {
                name: "_t".into(),
                value: "host-only".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "_t".into(),
                value: "domain-scope".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
        ]);

        assert_eq!(cookies.platform_cookies.len(), 2);
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.domain.as_deref() == Some("linux.do")
                && cookie.value == "host-only"));
        assert!(cookies
            .platform_cookies
            .iter()
            .any(|cookie| cookie.domain.as_deref() == Some(".linux.do")
                && cookie.value == "domain-scope"));
    }

    #[test]
    fn readiness_ignores_expired_platform_auth_cookies() {
        let cookies = CookieSnapshot {
            t_token: Some("stale-token".into()),
            forum_session: Some("stale-forum".into()),
            cf_clearance: Some("stale-clearance".into()),
            csrf_token: None,
            platform_cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "expired-token".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "expired-forum".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                },
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "expired-clearance".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                },
            ],
        };

        assert!(!cookies.has_login_session());
        assert!(!cookies.has_forum_session());
        assert!(!cookies.has_cloudflare_clearance());
        assert!(!cookies.can_authenticate_requests());
    }

    #[test]
    fn login_phase_advances_with_bootstrap_and_csrf() {
        let mut snapshot = SessionSnapshot::default();
        assert_eq!(snapshot.login_phase(), LoginPhase::Anonymous);

        snapshot.cookies.t_token = Some("token".into());
        assert_eq!(snapshot.login_phase(), LoginPhase::CookiesCaptured);

        snapshot.cookies.forum_session = Some("forum".into());
        snapshot.bootstrap.current_username = Some("alice".into());
        assert_eq!(snapshot.login_phase(), LoginPhase::BootstrapCaptured);

        snapshot.cookies.csrf_token = Some("csrf".into());
        snapshot.bootstrap.preloaded_json =
            Some("{\"currentUser\":{\"username\":\"alice\"}}".into());
        snapshot.bootstrap.has_preloaded_data = true;
        snapshot.bootstrap.has_site_metadata = true;
        snapshot.bootstrap.has_site_settings = true;
        assert_eq!(snapshot.login_phase(), LoginPhase::Ready);
    }

    #[test]
    fn merge_patch_keeps_existing_site_metadata_when_partial_preloaded_lacks_site() {
        let mut bootstrap = BootstrapArtifacts {
            preloaded_json: Some("{\"site\":{\"categories\":[{\"id\":2}]}}".into()),
            has_preloaded_data: true,
            has_site_metadata: true,
            top_tags: vec!["swift".into()],
            can_tag_topics: true,
            categories: vec![TopicCategory {
                id: 2,
                name: "Rust".into(),
                slug: "rust".into(),
                parent_category_id: None,
                color_hex: Some("FFFFFF".into()),
                text_color_hex: Some("000000".into()),
                ..TopicCategory::default()
            }],
            has_site_settings: true,
            enabled_reaction_ids: vec!["heart".into(), "clap".into()],
            min_post_length: 20,
            min_topic_title_length: 15,
            min_first_post_length: 20,
            default_composer_category: Some(2),
            ..BootstrapArtifacts::default()
        };

        bootstrap.merge_patch(&BootstrapArtifacts {
            preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
            has_preloaded_data: true,
            ..BootstrapArtifacts::default()
        });

        assert!(bootstrap.has_site_metadata);
        assert_eq!(bootstrap.top_tags, vec!["swift"]);
        assert!(bootstrap.can_tag_topics);
        assert_eq!(bootstrap.categories.len(), 1);
        assert!(bootstrap.has_site_settings);
        assert_eq!(bootstrap.enabled_reaction_ids, vec!["heart", "clap"]);
        assert_eq!(bootstrap.min_post_length, 20);
        assert_eq!(bootstrap.min_topic_title_length, 15);
        assert_eq!(bootstrap.min_first_post_length, 20);
        assert_eq!(bootstrap.default_composer_category, Some(2));
    }

    #[test]
    fn merge_patch_updates_site_metadata_and_settings_when_present() {
        let mut bootstrap = BootstrapArtifacts::default();

        bootstrap.merge_patch(&BootstrapArtifacts {
            preloaded_json: Some("{\"site\":{},\"siteSettings\":{}}".into()),
            has_preloaded_data: true,
            has_site_metadata: true,
            top_tags: vec!["rust".into(), "swift".into(), "rust".into()],
            can_tag_topics: true,
            categories: vec![TopicCategory {
                id: 2,
                name: "Rust".into(),
                slug: "rust".into(),
                parent_category_id: None,
                color_hex: None,
                text_color_hex: None,
                ..TopicCategory::default()
            }],
            has_site_settings: true,
            enabled_reaction_ids: vec!["heart".into(), "clap".into(), "heart".into()],
            min_post_length: 18,
            min_topic_title_length: 16,
            min_first_post_length: 24,
            default_composer_category: Some(2),
            ..BootstrapArtifacts::default()
        });

        assert!(bootstrap.has_site_metadata);
        assert_eq!(bootstrap.top_tags, vec!["rust", "swift"]);
        assert!(bootstrap.can_tag_topics);
        assert_eq!(bootstrap.categories.len(), 1);
        assert!(bootstrap.has_site_settings);
        assert_eq!(bootstrap.enabled_reaction_ids, vec!["heart", "clap"]);
        assert_eq!(bootstrap.min_post_length, 18);
        assert_eq!(bootstrap.min_topic_title_length, 16);
        assert_eq!(bootstrap.min_first_post_length, 24);
        assert_eq!(bootstrap.default_composer_category, Some(2));
    }

    #[test]
    fn merge_patch_applies_site_metadata_without_preloaded_payload() {
        let mut bootstrap = BootstrapArtifacts {
            preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
            has_preloaded_data: true,
            ..BootstrapArtifacts::default()
        };

        bootstrap.merge_patch(&BootstrapArtifacts {
            has_site_metadata: true,
            top_tags: vec!["rust".into(), "swift".into()],
            can_tag_topics: true,
            categories: vec![TopicCategory {
                id: 2,
                name: "Rust".into(),
                slug: "rust".into(),
                parent_category_id: None,
                color_hex: None,
                text_color_hex: None,
                ..TopicCategory::default()
            }],
            ..BootstrapArtifacts::default()
        });

        assert!(bootstrap.has_site_metadata);
        assert_eq!(bootstrap.top_tags, vec!["rust", "swift"]);
        assert!(bootstrap.can_tag_topics);
        assert_eq!(bootstrap.categories.len(), 1);
        assert!(bootstrap.has_preloaded_data);
    }

    #[test]
    fn topic_detail_interaction_count_adds_non_heart_reactions_to_topic_likes() {
        let detail = TopicDetail {
            like_count: 21,
            post_stream: TopicPostStream {
                posts: vec![
                    TopicPost {
                        reactions: vec![
                            TopicReaction {
                                id: "heart".into(),
                                count: 5,
                                ..TopicReaction::default()
                            },
                            TopicReaction {
                                id: "clap".into(),
                                count: 2,
                                ..TopicReaction::default()
                            },
                        ],
                        ..TopicPost::default()
                    },
                    TopicPost {
                        reactions: vec![TopicReaction {
                            id: "TADA".into(),
                            count: 3,
                            ..TopicReaction::default()
                        }],
                        ..TopicPost::default()
                    },
                ],
                ..TopicPostStream::default()
            },
            ..TopicDetail::default()
        };

        assert_eq!(detail.interaction_count(), 26);
    }

    #[test]
    fn same_origin_message_bus_does_not_require_shared_session_key() {
        let snapshot = SessionSnapshot {
            cookies: CookieSnapshot {
                t_token: Some("token".into()),
                forum_session: Some("forum".into()),
                ..CookieSnapshot::default()
            },
            bootstrap: BootstrapArtifacts {
                base_url: "https://linux.do".into(),
                long_polling_base_url: Some("https://linux.do".into()),
                current_username: Some("alice".into()),
                preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
                has_preloaded_data: true,
                ..BootstrapArtifacts::default()
            },
            browser_user_agent: None,
        };

        let readiness = snapshot.readiness();

        assert!(!readiness.has_shared_session_key);
        assert!(readiness.can_open_message_bus);
    }

    #[test]
    fn cross_origin_message_bus_requires_shared_session_key() {
        let snapshot = SessionSnapshot {
            cookies: CookieSnapshot {
                t_token: Some("token".into()),
                forum_session: Some("forum".into()),
                ..CookieSnapshot::default()
            },
            bootstrap: BootstrapArtifacts {
                base_url: "https://linux.do".into(),
                long_polling_base_url: Some("https://poll.linux.do".into()),
                current_username: Some("alice".into()),
                preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
                has_preloaded_data: true,
                ..BootstrapArtifacts::default()
            },
            browser_user_agent: None,
        };

        let readiness = snapshot.readiness();

        assert!(!readiness.has_shared_session_key);
        assert!(!readiness.can_open_message_bus);
    }

    #[test]
    fn clear_login_state_preserves_cf_when_requested() {
        let mut snapshot = SessionSnapshot {
            cookies: CookieSnapshot {
                t_token: Some("token".into()),
                forum_session: Some("forum".into()),
                cf_clearance: Some("clearance".into()),
                csrf_token: Some("csrf".into()),
                platform_cookies: Vec::new(),
            },
            bootstrap: BootstrapArtifacts {
                base_url: "https://linux.do".into(),
                discourse_base_uri: Some("/".into()),
                shared_session_key: Some("shared".into()),
                current_username: Some("alice".into()),
                current_user_id: Some(1),
                notification_channel_position: Some(42),
                long_polling_base_url: Some("https://linux.do".into()),
                turnstile_sitekey: Some("sitekey".into()),
                topic_tracking_state_meta: Some("{\"seq\":1}".into()),
                preloaded_json: Some("{\"ok\":true}".into()),
                has_preloaded_data: true,
                has_site_metadata: true,
                top_tags: vec!["rust".into()],
                can_tag_topics: true,
                categories: Vec::new(),
                has_site_settings: true,
                enabled_reaction_ids: vec!["heart".into(), "clap".into()],
                min_post_length: 20,
                min_topic_title_length: 15,
                min_first_post_length: 20,
                min_personal_message_title_length: 2,
                min_personal_message_post_length: 10,
                default_composer_category: Some(2),
            },
            browser_user_agent: None,
        };

        snapshot.clear_login_state(true);

        assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
        assert_eq!(snapshot.cookies.t_token, None);
        assert_eq!(snapshot.bootstrap.current_username, None);
        assert_eq!(snapshot.bootstrap.current_user_id, None);
        assert_eq!(snapshot.bootstrap.notification_channel_position, None);
        assert_eq!(snapshot.bootstrap.shared_session_key, None);
        assert_eq!(snapshot.bootstrap.preloaded_json, None);
        assert!(!snapshot.bootstrap.has_preloaded_data);
        assert_eq!(
            snapshot.bootstrap.turnstile_sitekey.as_deref(),
            Some("sitekey")
        );
        assert!(!snapshot.bootstrap.has_site_metadata);
        assert_eq!(snapshot.bootstrap.top_tags, Vec::<String>::new());
        assert!(!snapshot.bootstrap.can_tag_topics);
        assert_eq!(snapshot.bootstrap.categories, Vec::new());
        assert!(!snapshot.bootstrap.has_site_settings);
        assert_eq!(snapshot.bootstrap.enabled_reaction_ids, vec!["heart"]);
        assert_eq!(snapshot.bootstrap.min_post_length, 1);
        assert_eq!(snapshot.bootstrap.min_topic_title_length, 15);
        assert_eq!(snapshot.bootstrap.min_first_post_length, 20);
        assert_eq!(snapshot.bootstrap.default_composer_category, None);
    }

    #[test]
    fn topic_thread_groups_nested_replies_without_duplication() {
        let thread = TopicThread::from_posts(&[
            topic_post(1, None),
            topic_post(2, Some(1)),
            topic_post(3, Some(2)),
            topic_post(4, Some(3)),
            topic_post(5, Some(1)),
            topic_post(6, Some(99)),
        ]);

        assert_eq!(thread.original_post_number, Some(1));
        assert_eq!(
            thread
                .reply_sections
                .iter()
                .map(|section| section.anchor_post_number)
                .collect::<Vec<_>>(),
            vec![2, 5, 6]
        );
        assert_eq!(
            thread.reply_sections[0]
                .replies
                .iter()
                .map(|reply| reply.post_number)
                .collect::<Vec<_>>(),
            vec![3, 4]
        );
        assert_eq!(
            thread.reply_sections[0]
                .replies
                .iter()
                .map(|reply| reply.depth)
                .collect::<Vec<_>>(),
            vec![1, 2]
        );
    }

    #[test]
    fn topic_thread_flattens_to_display_order_posts() {
        let posts = vec![
            topic_post(1, None),
            topic_post(2, Some(1)),
            topic_post(3, Some(2)),
            topic_post(4, Some(3)),
            topic_post(5, Some(1)),
            topic_post(6, Some(99)),
        ];
        let thread = TopicThread::from_posts(&posts);

        assert_eq!(
            thread
                .flatten(&posts)
                .into_iter()
                .map(|flat_post: TopicThreadFlatPost| (
                    flat_post.post.post_number,
                    flat_post.depth,
                    flat_post.parent_post_number,
                    flat_post.shows_thread_line,
                    flat_post.is_original_post,
                ))
                .collect::<Vec<_>>(),
            vec![
                (1, 0, None, true, true),
                (2, 0, None, true, false),
                (3, 1, Some(2), true, false),
                (4, 2, Some(3), true, false),
                (5, 0, None, true, false),
                (6, 0, None, false, false),
            ]
        );
    }

    #[test]
    fn topic_list_query_api_path_global() {
        let query = TopicListQuery {
            kind: TopicListKind::Latest,
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/latest.json");

        let query = TopicListQuery {
            kind: TopicListKind::Hot,
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/hot.json");
    }

    #[test]
    fn topic_list_query_api_path_category() {
        let query = TopicListQuery {
            kind: TopicListKind::Latest,
            category_slug: Some("dev".into()),
            category_id: Some(42),
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/c/dev/42/l/latest.json");
    }

    #[test]
    fn topic_list_query_api_path_subcategory() {
        let query = TopicListQuery {
            kind: TopicListKind::New,
            category_slug: Some("rust".into()),
            category_id: Some(99),
            parent_category_slug: Some("dev".into()),
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/c/dev/rust/99/l/new.json");
    }

    #[test]
    fn topic_list_query_api_path_tag() {
        let query = TopicListQuery {
            kind: TopicListKind::Top,
            tag: Some("swift".into()),
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/tag/swift/l/top.json");
    }

    #[test]
    fn topic_list_query_api_path_category_slug_only() {
        let query = TopicListQuery {
            kind: TopicListKind::Latest,
            category_slug: Some("dev".into()),
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/c/dev.json");
    }

    #[test]
    fn topic_list_query_api_path_topic_ids_override() {
        let query = TopicListQuery {
            kind: TopicListKind::New,
            topic_ids: vec![1, 2, 3],
            ..Default::default()
        };
        assert_eq!(query.api_path(), "/latest.json");
    }

    fn topic_post(post_number: u32, reply_to_post_number: Option<u32>) -> TopicPost {
        TopicPost {
            id: u64::from(post_number),
            username: format!("user-{post_number}"),
            name: None,
            avatar_template: None,
            cooked: format!("<p>{post_number}</p>"),
            raw: None,
            post_number,
            post_type: 1,
            created_at: None,
            updated_at: None,
            like_count: 0,
            reply_count: 0,
            reply_to_post_number,
            bookmarked: false,
            bookmark_id: None,
            bookmark_name: None,
            bookmark_reminder_at: None,
            reactions: Vec::new(),
            current_user_reaction: None,
            polls: Vec::new(),
            accepted_answer: false,
            can_edit: false,
            can_delete: false,
            can_recover: false,
            hidden: false,
        }
    }
}
