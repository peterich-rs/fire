mod common;

use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc, Mutex,
};

use common::{
    raw_cloudflare_challenge_response, raw_json_response, raw_text_response, sample_home_html,
    sample_latest_json, sample_topic_detail_json, TestServer, TestServerStep,
};
use fire_core::{
    FireAuthRecoveryHint, FireAuthRecoveryHintReason, FireCore, FireCoreConfig, FireCoreError,
};
use fire_models::{
    CookieSelfHealingPhase, CookieSelfHealingResult, LoginSyncInput, PlatformCookie,
    TopicDetailQuery, TopicDetailSourceQuery, TopicListKind, TopicListQuery, TopicReplyRequest,
    TopicTag,
};
use serde_json::{json, Value};
use tokio::{
    sync::Notify,
    time::{sleep, Duration},
};

#[tokio::test]
async fn fetch_topic_list_parses_latest_payload() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        &sample_latest_json(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("topic list");
    let _ = server.shutdown().await;

    assert_eq!(response.topics.len(), 1);
    assert_eq!(response.topics[0].id, 123);
    assert_eq!(response.topics[0].title, "Fire topic");
    assert_eq!(
        response.topics[0].tags,
        vec![
            TopicTag {
                id: None,
                name: "rust".into(),
                slug: None,
            },
            TopicTag {
                id: None,
                name: "linuxdo".into(),
                slug: None,
            },
        ]
    );
    assert_eq!(response.users[0].username, "alice");
    assert_eq!(response.more_topics_url.as_deref(), Some("/latest?page=1"));
    assert_eq!(response.next_page, Some(1));
    assert_eq!(response.rows.len(), 1);
    assert_eq!(response.rows[0].topic.id, 123);
    assert_eq!(
        response.rows[0].excerpt_text.as_deref(),
        Some("topic excerpt")
    );
    assert_eq!(
        response.rows[0].original_poster_username.as_deref(),
        Some("alice")
    );
    assert_eq!(
        response.rows[0].original_poster_avatar_template.as_deref(),
        Some("/user_avatar/linux.do/alice/{size}/1_2.png")
    );
    assert_eq!(response.rows[0].tag_names, vec!["rust", "linuxdo"]);
    assert_eq!(
        response.rows[0].status_labels,
        vec!["Unread 2".to_string(), "New 1".to_string()]
    );
    assert!(!response.rows[0].is_pinned);
    assert!(!response.rows[0].is_closed);
    assert!(!response.rows[0].is_archived);
    assert!(!response.rows[0].has_accepted_answer);
    assert!(response.rows[0].has_unread_posts);
    assert_eq!(
        response.rows[0].created_timestamp_unix_ms,
        Some(1_774_656_000_000)
    );
    assert_eq!(
        response.rows[0].activity_timestamp_unix_ms,
        Some(1_774_659_600_000)
    );
    assert_eq!(
        response.rows[0].last_poster_username.as_deref(),
        Some("alice")
    );
    assert!(!response.is_cached);
}

#[tokio::test]
async fn fetch_topic_list_returns_cached_page_on_network_error() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        &sample_latest_json(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let live = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("live topic list");
    assert!(!live.is_cached);

    let cached = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("cached topic list");
    let _ = server.shutdown().await;

    assert!(cached.is_cached);
    assert_eq!(cached.rows.len(), 1);
    assert_eq!(cached.rows[0].topic.id, live.rows[0].topic.id);
}

#[tokio::test]
async fn fetch_topic_list_category_scope_sends_primary_and_additional_tags() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        &sample_latest_json(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            page: Some(2),
            category_slug: Some("rust".into()),
            category_id: Some(2),
            parent_category_slug: Some("dev".into()),
            tag: Some("swift".into()),
            additional_tags: vec!["ios".into()],
            match_all_tags: true,
            ..TopicListQuery::default()
        })
        .await
        .expect("topic list");
    let requests = server.shutdown_with_requests().await;

    assert!(requests[0].contains(
        "GET /c/dev/rust/2/l/latest.json?no_definitions=true&page=2&tags%5B%5D=swift&tags%5B%5D=ios&match_all_tags=true HTTP/1.1"
    ));
}

#[tokio::test]
async fn fetch_private_message_mailboxes_use_username_routes_and_parse_participants() {
    let payload = r#"{
  "topic_list": {
    "topics": [
      {
        "id": 456,
        "title": "Fire private message",
        "slug": "fire-private-message",
        "posts_count": 3,
        "reply_count": 2,
        "views": 12,
        "like_count": 1,
        "excerpt": "hello from bob",
        "created_at": "2026-04-11T00:00:00Z",
        "last_posted_at": "2026-04-11T00:05:00Z",
        "last_poster_username": "bob",
        "pinned": false,
        "visible": true,
        "closed": false,
        "archived": false,
        "tags": [],
        "posters": [],
        "participants": [
          {
            "id": 1,
            "username": "alice",
            "name": "Alice",
            "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
          },
          {
            "id": 2,
            "username": "bob",
            "name": "Bob",
            "avatar_template": "/user_avatar/linux.do/bob/{size}/1_2.png"
          }
        ],
        "unseen": false,
        "unread_posts": 1,
        "new_posts": 0,
        "highest_post_number": 3
      }
    ],
    "more_topics_url": "/topics/private-messages/alice?page=2"
  },
  "users": [
    {
      "id": 2,
      "username": "bob",
      "avatar_template": "/user_avatar/linux.do/bob/{size}/1_2.png"
    }
  ]
}"#;
    let server = TestServer::spawn(vec![
        raw_json_response(200, "application/json", payload),
        raw_json_response(200, "application/json", payload),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let inbox = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::PrivateMessagesInbox,
            page: Some(2),
            ..TopicListQuery::default()
        })
        .await
        .expect("pm inbox");
    let sent = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::PrivateMessagesSent,
            page: Some(3),
            ..TopicListQuery::default()
        })
        .await
        .expect("pm sent");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(inbox.topics.len(), 1);
    assert_eq!(inbox.topics[0].participants.len(), 2);
    assert_eq!(
        inbox.topics[0].participants[0].username.as_deref(),
        Some("alice")
    );
    assert_eq!(inbox.topics[0].participants[1].name.as_deref(), Some("Bob"));
    assert_eq!(
        inbox.rows[0].topic.participants[1]
            .avatar_template
            .as_deref(),
        Some("/user_avatar/linux.do/bob/{size}/1_2.png")
    );
    assert_eq!(inbox.next_page, Some(2));
    assert_eq!(sent.topics[0].id, 456);
    assert_eq!(requests.len(), 2);
    assert!(requests[0]
        .contains("GET /topics/private-messages/alice.json?no_definitions=true&page=2 HTTP/1.1"));
    assert!(requests[1].contains(
        "GET /topics/private-messages-sent/alice.json?no_definitions=true&page=3 HTTP/1.1"
    ));
}

#[tokio::test]
async fn fetch_topic_list_tolerates_object_poster_metadata_fields() {
    let payload = sample_latest_json()
        .replace(
            r#""description": "Original Poster""#,
            r#""description": {"localized": "Original Poster"}"#,
        )
        .replace(r#""extras": "latest""#, r#""extras": {"role": "latest"}"#);
    let responses = vec![raw_json_response(200, "application/json", &payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("topic list");
    let _ = server.shutdown().await;

    assert_eq!(response.topics.len(), 1);
    assert_eq!(response.topics[0].posters.len(), 1);
    assert_eq!(response.topics[0].posters[0].description, None);
    assert_eq!(response.topics[0].posters[0].extras, None);
}

#[tokio::test]
async fn fetch_topic_list_tolerates_object_tags_and_null_counters() {
    let payload = sample_latest_json()
        .replace(
            r#""tags": ["rust", "linuxdo"]"#,
            r#""tags": [{"id": 1451, "name": "Rust", "slug": "rust"}, {"id": 99, "name": "LinuxDo", "slug": "linuxdo"}]"#,
        )
        .replace(r#""unread_posts": 2"#, r#""unread_posts": null"#)
        .replace(r#""new_posts": 1"#, r#""new_posts": null"#)
        .replace(r#""can_have_answer": true"#, r#""can_have_answer": null"#);
    let responses = vec![raw_json_response(200, "application/json", &payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("topic list");
    let _ = server.shutdown().await;

    assert_eq!(response.topics.len(), 1);
    assert_eq!(
        response.topics[0].tags,
        vec![
            TopicTag {
                id: Some(1451),
                name: "Rust".into(),
                slug: Some("rust".into()),
            },
            TopicTag {
                id: Some(99),
                name: "LinuxDo".into(),
                slug: Some("linuxdo".into()),
            },
        ]
    );
    assert_eq!(response.topics[0].unread_posts, 0);
    assert_eq!(response.topics[0].new_posts, 0);
    assert!(!response.topics[0].can_have_answer);
    assert_eq!(response.rows[0].tag_names, vec!["Rust", "LinuxDo"]);
}

#[tokio::test]
async fn fetch_topic_list_builds_plain_text_excerpt_for_rows() {
    let payload = sample_latest_json().replace(
        r#""excerpt": "topic excerpt""#,
        r#""excerpt": "<p>Hello&nbsp;<strong>Fire</strong></p>""#,
    );
    let responses = vec![raw_json_response(200, "application/json", &payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("topic list");
    let _ = server.shutdown().await;

    assert_eq!(response.rows[0].excerpt_text.as_deref(), Some("Hello Fire"));
}

#[tokio::test]
async fn fetch_bookmarks_parses_bookmark_metadata_fields() {
    let payload = sample_latest_json()
        .replace(
            r#""highest_post_number": 12,"#,
            r#""highest_post_number": 12, "_bookmarked_post_number": 7, "_bookmark_id": 901, "_bookmark_name": "稍后细读", "_bookmark_reminder_at": "2026-03-29T09:00:00Z", "_bookmarkable_type": "Post","#,
        );
    let responses = vec![raw_json_response(200, "application/json", &payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .fetch_bookmarks("alice", Some(2))
        .await
        .expect("bookmarks");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.topics.len(), 1);
    assert_eq!(response.topics[0].bookmarked_post_number, Some(7));
    assert_eq!(response.topics[0].bookmark_id, Some(901));
    assert_eq!(
        response.topics[0].bookmark_name.as_deref(),
        Some("稍后细读")
    );
    assert_eq!(
        response.topics[0].bookmark_reminder_at.as_deref(),
        Some("2026-03-29T09:00:00Z")
    );
    assert_eq!(
        response.topics[0].bookmarkable_type.as_deref(),
        Some("Post")
    );
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /u/alice/bookmarks.json?page=2 HTTP/1.1"));
}

#[tokio::test]
async fn fetch_bookmarks_parses_user_bookmark_list_payload() {
    let payload = r#"{
  "user_bookmark_list": {
    "more_bookmarks_url": "/u/alice/bookmarks.json?page=2",
    "bookmarks": [
      {
        "id": 901,
        "name": "稍后细读",
        "reminder_at": "2026-03-29T09:00:00Z",
        "bookmarkable_type": "Post",
        "bookmarkable_id": 7007,
        "topic_id": 1001,
        "linked_post_number": 7,
        "title": "真实书签响应",
        "slug": "real-bookmark",
        "excerpt": "<p>Hello&nbsp;<strong>Fire</strong></p>",
        "created_at": "2026-03-28T00:00:00Z",
        "bumped_at": "2026-03-28T01:00:00Z",
        "category_id": 42,
        "highest_post_number": 12,
        "views": 88,
        "user": {
          "id": 12,
          "username": "alice",
          "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
        }
      }
    ]
  }
}"#;
    let responses = vec![raw_json_response(200, "application/json", payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .fetch_bookmarks("alice", None)
        .await
        .expect("bookmarks");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.topics.len(), 1);
    assert_eq!(response.rows.len(), 1);
    assert_eq!(response.next_page, Some(2));
    assert_eq!(response.topics[0].id, 1001);
    assert_eq!(response.topics[0].title, "真实书签响应");
    assert_eq!(response.topics[0].reply_count, 11);
    assert_eq!(response.topics[0].bookmarked_post_number, Some(7));
    assert_eq!(response.topics[0].bookmark_id, Some(901));
    assert_eq!(
        response.topics[0].bookmark_name.as_deref(),
        Some("稍后细读")
    );
    assert_eq!(
        response.topics[0].bookmark_reminder_at.as_deref(),
        Some("2026-03-29T09:00:00Z")
    );
    assert_eq!(response.rows[0].excerpt_text.as_deref(), Some("Hello Fire"));
    assert_eq!(
        response.rows[0].original_poster_username.as_deref(),
        Some("alice")
    );
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /u/alice/bookmarks.json HTTP/1.1"));
}

#[tokio::test]
async fn fetch_topic_list_surfaces_cloudflare_challenge_error() {
    let responses = vec![raw_cloudflare_challenge_response(
        403,
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("cloudflare challenge should surface as an error");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list"
        }
    ));
}

#[tokio::test]
async fn fetch_topic_list_retries_once_after_cloudflare_challenge_completion() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.set_cloudflare_challenge_handler(|request| async move {
        assert_eq!(request.operation, "fetch topic list");
        assert!(request.request_url.contains("/latest.json"));
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: Some("new-clearance".into()),
            cookies: vec![
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "new-clearance".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "stale-clearance".into(),
                    domain: Some(".linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
            ],
            browser_user_agent: Some("FireBrowser/1.0".into()),
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("cloudflare challenge should retry once");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    let retry_request = &requests[1];
    let retry_request_lower = retry_request.to_ascii_lowercase();
    assert!(
        retry_request_lower.contains("cookie: cf_clearance=new-clearance"),
        "retry request should send fresh cf_clearance:\n{retry_request}"
    );
    assert!(
        !retry_request.contains("stale-clearance"),
        "retry request must not send stale cf_clearance:\n{retry_request}"
    );
    assert!(
        retry_request_lower.contains("user-agent: firebrowser/1.0"),
        "retry request should use challenge WebView user agent:\n{retry_request}"
    );
    let snapshot = core.snapshot();
    assert_eq!(
        snapshot.cookies.cf_clearance.as_deref(),
        Some("new-clearance")
    );
    assert_eq!(
        snapshot.browser_user_agent.as_deref(),
        Some("FireBrowser/1.0")
    );
}

#[tokio::test]
async fn cloudflare_challenge_retry_synthesizes_confirmed_clearance_when_snapshot_missing() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.set_cloudflare_challenge_handler(|_| async move {
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: Some("confirmed-clearance".into()),
            cookies: vec![],
            browser_user_agent: None,
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("confirmed clearance should be synthesized for retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    assert!(
        requests[1]
            .to_ascii_lowercase()
            .contains("cookie: cf_clearance=confirmed-clearance"),
        "retry request should send synthesized cf_clearance:\n{}",
        requests[1]
    );
    assert_eq!(
        core.snapshot().cookies.cf_clearance.as_deref(),
        Some("confirmed-clearance")
    );
}

#[tokio::test]
async fn cloudflare_challenge_retry_synthesizes_confirmed_clearance_when_snapshot_scope_is_wrong() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.set_cloudflare_challenge_handler(|_| async move {
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: Some("wrong-scope-clearance".into()),
            cookies: vec![PlatformCookie {
                name: "cf_clearance".into(),
                value: "wrong-scope-clearance".into(),
                domain: Some("unrelated.example".into()),
                path: Some("/challenge".into()),
                expires_at_unix_ms: None,
                same_site: None,
            }],
            browser_user_agent: None,
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("confirmed wrong-scope clearance should be synthesized for retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    assert!(
        requests[1]
            .to_ascii_lowercase()
            .contains("cookie: cf_clearance=wrong-scope-clearance"),
        "retry request should send synthesized cf_clearance:\n{}",
        requests[1]
    );
    let snapshot = core.snapshot();
    let clearance_cookie = snapshot
        .cookies
        .platform_cookies
        .iter()
        .find(|cookie| cookie.name == "cf_clearance")
        .expect("cf_clearance platform cookie");
    assert_eq!(clearance_cookie.path.as_deref(), Some("/"));
    assert_ne!(
        clearance_cookie.domain.as_deref(),
        Some("unrelated.example")
    );
}

#[tokio::test]
async fn cloudflare_challenge_retry_accepts_platform_confirmed_existing_clearance() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let snapshot = core.apply_platform_cookies(vec![PlatformCookie {
        name: "cf_clearance".into(),
        value: "stable-clearance".into(),
        domain: Some("linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    }]);
    assert_eq!(
        snapshot.cookies.cf_clearance.as_deref(),
        Some("stable-clearance")
    );
    core.set_cloudflare_challenge_handler(|_| async move {
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: Some("stable-clearance".into()),
            cookies: vec![PlatformCookie {
                name: "cf_clearance".into(),
                value: "stable-clearance".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
                same_site: None,
            }],
            browser_user_agent: None,
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("platform-confirmed clearance should unblock retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    assert_eq!(
        core.snapshot().cookies.cf_clearance.as_deref(),
        Some("stable-clearance")
    );
}

#[tokio::test]
async fn business_request_is_blocked_while_cloudflare_challenge_is_in_progress() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let challenge_started = Arc::new(Notify::new());
    let release_challenge = Arc::new(Notify::new());
    {
        let challenge_started = Arc::clone(&challenge_started);
        let release_challenge = Arc::clone(&release_challenge);
        core.set_cloudflare_challenge_handler(move |_| {
            let challenge_started = Arc::clone(&challenge_started);
            let release_challenge = Arc::clone(&release_challenge);
            async move {
                challenge_started.notify_waiters();
                release_challenge.notified().await;
                fire_models::CloudflareChallengeResult {
                    completed: true,
                    user_cancelled: false,
                    fresh_cf_clearance: Some("new-clearance".into()),
                    cookies: vec![PlatformCookie {
                        name: "cf_clearance".into(),
                        value: "new-clearance".into(),
                        domain: Some("linux.do".into()),
                        path: Some("/".into()),
                        expires_at_unix_ms: None,
                        same_site: None,
                    }],
                    browser_user_agent: None,
                }
            }
        });
    }

    let first_core = core.clone();
    let first = tokio::spawn(async move {
        first_core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
    });
    challenge_started.notified().await;

    let blocked = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("business request should be blocked locally");

    assert!(matches!(
        blocked,
        FireCoreError::CloudflareChallengeInProgress {
            operation: "fetch topic list"
        }
    ));

    release_challenge.notify_waiters();
    let response = first
        .await
        .expect("task should finish")
        .expect("first request should retry after challenge");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
}

#[tokio::test]
async fn foreground_retry_bypasses_cloudflare_failure_cooldown() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let challenge_calls = Arc::new(AtomicUsize::new(0));
    {
        let challenge_calls = Arc::clone(&challenge_calls);
        core.set_cloudflare_challenge_handler(move |_| {
            challenge_calls.fetch_add(1, Ordering::SeqCst);
            async move {
                fire_models::CloudflareChallengeResult {
                    completed: false,
                    user_cancelled: false,
                    fresh_cf_clearance: None,
                    cookies: vec![],
                    browser_user_agent: None,
                }
            }
        });
    }

    for _ in 0..2 {
        let error = core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
            .expect_err("challenge should remain unresolved");
        assert!(matches!(
            error,
            FireCoreError::CloudflareChallenge {
                operation: "fetch topic list"
            }
        ));
    }
    let requests = server.shutdown_with_requests().await;

    assert_eq!(requests.len(), 2);
    assert_eq!(challenge_calls.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn fetch_topic_list_self_heals_unauthorized_with_sweep_retry() {
    let responses = vec![
        raw_json_response(
            401,
            "application/json",
            r#"{"errors":["session cookie state is stale"]}"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let calls = Arc::new(Mutex::new(Vec::new()));
    {
        let calls = Arc::clone(&calls);
        core.set_cookie_self_healing_handler(move |request| {
            let calls = Arc::clone(&calls);
            async move {
                calls
                    .lock()
                    .expect("calls mutex")
                    .push((request.phase, request.attempt));
                CookieSelfHealingResult {
                    completed: true,
                    session_epoch: request.session_epoch,
                }
            }
        });
    }

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("self-healed request should retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    assert_eq!(
        calls.lock().expect("calls mutex").as_slice(),
        &[(CookieSelfHealingPhase::Sweep, 1)]
    );
}

#[tokio::test]
async fn fetch_topic_list_does_not_self_heal_cloudflare_challenge_without_handler() {
    let responses = vec![raw_cloudflare_challenge_response(
        403,
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let calls = Arc::new(AtomicUsize::new(0));
    {
        let calls = Arc::clone(&calls);
        core.set_cookie_self_healing_handler(move |request| {
            calls.fetch_add(1, Ordering::SeqCst);
            async move {
                CookieSelfHealingResult {
                    completed: true,
                    session_epoch: request.session_epoch,
                }
            }
        });
    }

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("cloudflare challenge must not trigger cookie healing");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list"
        }
    ));
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert_eq!(requests.len(), 1);
}

#[tokio::test]
async fn fetch_topic_list_does_not_self_heal_explicit_not_logged_in() {
    let body = r#"{"errors":["You need to log in."],"error_type":"not_logged_in"}"#;
    let responses = vec![raw_json_response(401, "application/json", body)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let calls = Arc::new(AtomicUsize::new(0));
    {
        let calls = Arc::clone(&calls);
        core.set_cookie_self_healing_handler(move |request| {
            calls.fetch_add(1, Ordering::SeqCst);
            async move {
                CookieSelfHealingResult {
                    completed: true,
                    session_epoch: request.session_epoch,
                }
            }
        });
    }

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("explicit not_logged_in must surface as login required");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(error, FireCoreError::LoginRequired { .. }));
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert_eq!(requests.len(), 1);
}

#[tokio::test]
async fn fetch_topic_list_self_healing_escalates_to_nuclear_reset() {
    let unauthorized = raw_json_response(
        401,
        "application/json",
        r#"{"errors":["session cookie state is stale"]}"#,
    );
    let responses = vec![
        unauthorized.clone(),
        unauthorized.clone(),
        unauthorized,
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let calls = Arc::new(Mutex::new(Vec::new()));
    {
        let calls = Arc::clone(&calls);
        core.set_cookie_self_healing_handler(move |request| {
            let calls = Arc::clone(&calls);
            async move {
                calls
                    .lock()
                    .expect("calls mutex")
                    .push((request.phase, request.attempt));
                CookieSelfHealingResult {
                    completed: true,
                    session_epoch: request.session_epoch,
                }
            }
        });
    }

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("nuclear reset should retry once");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 4);
    assert_eq!(
        calls.lock().expect("calls mutex").as_slice(),
        &[
            (CookieSelfHealingPhase::Sweep, 1),
            (CookieSelfHealingPhase::Sweep, 2),
            (CookieSelfHealingPhase::NuclearReset, 1),
        ]
    );
}

#[tokio::test]
async fn fetch_topic_list_surfaces_rate_limited_cloudflare_challenge_error() {
    let responses = vec![raw_cloudflare_challenge_response(
        429,
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("429 Cloudflare challenge should surface as a challenge error");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list"
        }
    ));
}

#[tokio::test]
async fn fetch_topic_list_accepts_cf_mitigated_challenge_without_html_content_type() {
    let body = "managed challenge";
    let responses = vec![format!(
        "HTTP/1.1 429 TEST\r\nServer: cloudflare\r\nContent-Type: text/plain; charset=utf-8\r\nCf-Mitigated: challenge\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("cf-mitigated challenge should not require HTML content type");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list"
        }
    ));
}

#[tokio::test]
async fn fetch_topic_list_does_not_treat_non_cloudflare_403_body_as_challenge() {
    let responses = vec![raw_json_response(
        403,
        "text/html; charset=utf-8",
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("non-cloudflare 403 should surface as a plain HTTP error");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::HttpStatus {
            operation: "fetch topic list",
            status: 403,
            ..
        }
    ));
}

#[tokio::test]
async fn fetch_topic_list_keeps_local_login_when_success_response_only_clears_auth_cookies() {
    let body = sample_latest_json();
    let response = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: application/json\r\nContent-Length: {}\r\nSet-Cookie: _t=; path=/; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax\r\nSet-Cookie: _forum_session=; path=/; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let server = TestServer::spawn(vec![response]).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let _response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            page: Some(1),
            ..TopicListQuery::default()
        })
        .await
        .expect("auth-cookie deletion alone should not invalidate login");
    let _ = server.shutdown().await;

    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("token"));
    assert_eq!(snapshot.cookies.forum_session.as_deref(), Some("forum"));
    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
}

#[tokio::test]
async fn fetch_topic_posts_keeps_local_login_when_forbidden_invalid_access_sets_logged_out_header()
{
    let body = r#"{"errors":["您没有权限查看请求的资源。"],"error_type":"invalid_access"}"#;
    let response = format!(
        "HTTP/1.1 403 TEST\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nDiscourse-Logged-Out: 1\r\nSet-Cookie: _t=; path=/; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let server = TestServer::spawn(vec![response]).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });
    let before_epoch = core.session_epoch();

    let error = core
        .fetch_topic_posts(2_270_621, vec![18_408_024])
        .await
        .expect_err("ordinary invalid_access 403 should not invalidate login");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(
        error,
        FireCoreError::HttpStatus {
            operation: "fetch topic posts",
            status: 403,
            body,
        } if body.contains("\"error_type\":\"invalid_access\"")
    ));
    assert_eq!(core.session_epoch(), before_epoch);

    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("token"));
    assert_eq!(snapshot.cookies.forum_session.as_deref(), Some("forum"));
    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains(
        "GET /t/2270621/posts.json?post_ids%5B%5D=18408024&include_suggested=false HTTP/1.1"
    ));
}

#[tokio::test]
async fn fetch_topic_detail_partial_auth_rotation_advances_epoch_and_clears_csrf() {
    let body = sample_topic_detail_json();
    let response = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: application/json\r\nContent-Length: {}\r\nSet-Cookie: _forum_session=rotated-forum; path=/; SameSite=Lax\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let server = TestServer::spawn(vec![response]).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });
    let before_epoch = core.session_epoch();

    let detail = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: true,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let requests = server.shutdown_with_requests().await;

    let snapshot = core.snapshot();
    let after_epoch = core.session_epoch();
    assert_eq!(detail.id, 123);
    assert_eq!(after_epoch, before_epoch + 1);
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("token"));
    assert_eq!(
        snapshot.cookies.forum_session.as_deref(),
        Some("rotated-forum")
    );
    assert_eq!(snapshot.cookies.csrf_token, None);
    assert!(!snapshot.readiness().can_write_authenticated_api);
    assert_eq!(
        core.auth_recovery_hint(),
        Some(FireAuthRecoveryHint {
            observed_epoch: after_epoch,
            reason: FireAuthRecoveryHintReason::ForumSessionOnlyRotation,
        })
    );
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /t/123.json?track_visit=true HTTP/1.1"));
}

#[tokio::test]
async fn fetch_topic_list_preserves_local_login_when_success_response_reports_logged_out() {
    let body = sample_latest_json();
    let response = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: application/json\r\nContent-Length: {}\r\nDiscourse-Logged-Out: 1\r\nSet-Cookie: _t=; path=/; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let server = TestServer::spawn(vec![response]).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            page: Some(1),
            ..TopicListQuery::default()
        })
        .await
        .expect("successful response should not force login invalidation");
    let _ = server.shutdown().await;

    assert_eq!(response.rows.len(), 1);

    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("token"));
    assert_eq!(snapshot.cookies.forum_session.as_deref(), Some("forum"));
    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
}

#[tokio::test]
async fn fetch_topic_list_surfaces_login_required_and_preserves_local_state_for_not_logged_in_error(
) {
    let body = r#"{"errors":["需要登录才能执行此操作。"],"error_type":"not_logged_in"}"#;
    let probe_body = r#"{"current_user":{"username":"alice"}}"#;
    let server = TestServer::spawn(vec![
        raw_json_response(403, "application/json", body),
        raw_json_response(200, "application/json", probe_body),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("login-required error should surface");
    let _ = server.shutdown().await;

    assert!(matches!(error, FireCoreError::LoginRequired { .. }));

    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("token"));
    assert_eq!(snapshot.cookies.forum_session.as_deref(), Some("forum"));
    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
}

#[tokio::test]
async fn stale_response_is_discarded_after_local_logout() {
    let body = sample_latest_json();
    let response = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: application/json\r\nContent-Length: {}\r\nSet-Cookie: _t=stale-token; path=/; SameSite=Lax\r\nSet-Cookie: _forum_session=stale-forum; path=/; SameSite=Lax\r\nSet-Cookie: __cf_bm=stale-browser-context; path=/; SameSite=Lax\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let server = TestServer::spawn_scripted(vec![TestServerStep::delayed(
        response,
        Duration::from_millis(150),
    )])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let request_core = core.clone();
    let task = tokio::spawn(async move {
        request_core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
    });

    sleep(Duration::from_millis(40)).await;
    let cleared = core.logout_local(true);
    assert!(!cleared.cookies.has_login_session());

    let error = task
        .await
        .expect("task join")
        .expect_err("stale response should be discarded");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::StaleSessionResponse {
            operation: "fetch topic list"
        }
    ));
    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.t_token, None);
    assert_eq!(snapshot.cookies.forum_session, None);
    assert_eq!(snapshot.cookies.cf_clearance, None);
    assert!(!snapshot
        .cookies
        .platform_cookies
        .iter()
        .any(|cookie| cookie.name == "__cf_bm"));
}

#[tokio::test]
async fn stale_response_is_discarded_after_session_rotation() {
    let body = sample_latest_json();
    let response = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: application/json\r\nContent-Length: {}\r\nSet-Cookie: _t=stale-token; path=/; SameSite=Lax\r\nSet-Cookie: _forum_session=stale-forum; path=/; SameSite=Lax\r\nSet-Cookie: __cf_bm=stale-browser-context; path=/; SameSite=Lax\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let server = TestServer::spawn_scripted(vec![TestServerStep::delayed(
        response,
        Duration::from_millis(150),
    )])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "old-token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "old-forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let request_core = core.clone();
    let task = tokio::spawn(async move {
        request_core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
    });

    sleep(Duration::from_millis(40)).await;
    let rotated = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "fresh-token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "fresh-forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });
    assert_eq!(rotated.cookies.t_token.as_deref(), Some("fresh-token"));

    let error = task
        .await
        .expect("task join")
        .expect_err("stale response should be discarded");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::StaleSessionResponse {
            operation: "fetch topic list"
        }
    ));
    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("fresh-token"));
    assert_eq!(
        snapshot.cookies.forum_session.as_deref(),
        Some("fresh-forum")
    );
    assert!(!snapshot
        .cookies
        .platform_cookies
        .iter()
        .any(|cookie| cookie.name == "__cf_bm"));
}

#[tokio::test]
async fn fetch_topic_detail_parses_detail_payload() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        &sample_topic_detail_json(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let detail = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: true,
            force_load: true,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(detail.id, 123);
    assert_eq!(detail.title, "Fire topic");
    assert!(requests[0].contains("GET /t/123.json?track_visit=true&forceLoad=true HTTP/1.1"));
    assert_eq!(
        detail.tags,
        vec![
            TopicTag {
                id: None,
                name: "rust".into(),
                slug: None,
            },
            TopicTag {
                id: None,
                name: "linuxdo".into(),
                slug: None,
            },
        ]
    );
    assert_eq!(detail.post_stream.posts.len(), 1);
    assert_eq!(detail.post_stream.posts[0].username, "alice");
    assert_eq!(detail.thread.original_post_number, Some(1));
    assert_eq!(detail.thread.reply_sections.len(), 0);
    assert_eq!(detail.flat_posts.len(), 1);
    assert!(detail.flat_posts[0].is_original_post);
    assert_eq!(detail.flat_posts[0].post.post_number, 1);
    assert!(!detail.flat_posts[0].shows_thread_line);
    assert_eq!(
        detail
            .details
            .created_by
            .as_ref()
            .map(|value| value.username.as_str()),
        Some("alice")
    );
}

#[tokio::test]
async fn fetch_topic_detail_parses_post_author_metadata() {
    let mut payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail payload json");
    let post = payload
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .and_then(|stream| stream.get_mut("posts"))
        .and_then(Value::as_array_mut)
        .and_then(|posts| posts.first_mut())
        .and_then(Value::as_object_mut)
        .expect("first post");
    post.insert("user_id".into(), json!(42));
    post.insert("user_title".into(), json!("Core Team"));
    post.insert("primary_group_name".into(), json!("staff"));
    post.insert("flair_url".into(), json!("/images/flair/staff.svg"));
    post.insert("flair_name".into(), json!("Staff"));
    post.insert("flair_bg_color".into(), json!("0057ff"));
    post.insert("flair_color".into(), json!("ffffff"));
    post.insert("flair_group_id".into(), json!("7"));
    post.insert("moderator".into(), json!(true));
    post.insert("admin".into(), json!(false));
    post.insert("group_moderator".into(), json!(true));
    post.insert(
        "user_status".into(),
        json!({
            "emoji": "coffee",
            "description": "Reviewing patches"
        }),
    );

    let responses = vec![raw_json_response(
        200,
        "application/json",
        &payload.to_string(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let detail = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: true,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let _ = server.shutdown().await;

    let metadata = &detail.post_stream.posts[0].author_metadata;
    assert_eq!(metadata.user_id, Some(42));
    assert_eq!(metadata.user_title.as_deref(), Some("Core Team"));
    assert_eq!(metadata.primary_group_name.as_deref(), Some("staff"));
    assert_eq!(
        metadata.flair_url.as_deref(),
        Some("/images/flair/staff.svg")
    );
    assert_eq!(metadata.flair_name.as_deref(), Some("Staff"));
    assert_eq!(metadata.flair_bg_color.as_deref(), Some("0057ff"));
    assert_eq!(metadata.flair_color.as_deref(), Some("ffffff"));
    assert_eq!(metadata.flair_group_id, Some(7));
    assert!(metadata.moderator);
    assert!(!metadata.admin);
    assert!(metadata.group_moderator);
    assert_eq!(metadata.user_status_emoji.as_deref(), Some("coffee"));
    assert_eq!(
        metadata.user_status_description.as_deref(),
        Some("Reviewing patches")
    );
}

#[tokio::test]
async fn fetch_topic_detail_rejects_mismatched_topic_identity() {
    let payload = sample_topic_detail_json().replace("\"id\": 123", "\"id\": 999");
    let responses = vec![raw_json_response(200, "application/json", &payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: false,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect_err("mismatched topic id should fail");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::UnexpectedTopicDetail {
            requested_topic_id: 123,
            actual_topic_id: 999,
        }
    ));
}

#[tokio::test]
async fn fetch_topic_detail_source_snapshot_tracks_visit_headers_and_force_load_query() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        &sample_topic_detail_json(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core
        .fetch_topic_detail_source_snapshot(TopicDetailSourceQuery {
            topic_id: 123,
            target_post_number: None,
            allow_suggested_unread_root: false,
            track_visit: true,
            force_load: true,
            initial_batch_size: 40,
            load_more_batch_size: 40,
            max_auto_batches_per_gesture: 3,
            max_auto_posts_per_gesture: 120,
        })
        .await
        .expect("topic source snapshot");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(snapshot.body.post.post_number, 1);
    assert_eq!(snapshot.loaded_posts.len(), 1);
    assert_eq!(requests.len(), 1);
    let first_request_headers = requests[0].to_ascii_lowercase();
    assert!(requests[0].contains("GET /t/123.json?track_visit=true&forceLoad=true HTTP/1.1"));
    assert!(first_request_headers.contains("discourse-track-view: 1"));
    assert!(first_request_headers.contains("discourse-track-view-topic-id: 123"));
}

#[tokio::test]
async fn fetch_topic_detail_source_snapshot_preserves_target_anchor_and_source_cursor() {
    let target_post_number = 14_u32;
    let mut detail_payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    detail_payload
        .as_object_mut()
        .expect("detail fixture object")
        .insert("posts_count".into(), json!(26));

    let root_posts = (2_u32..=26)
        .map(|post_number| {
            json!({
                "id": 9000 + u64::from(post_number),
                "username": format!("user-{post_number}"),
                "cooked": format!("<p>Reply {post_number}</p>"),
                "post_number": post_number,
                "reply_to_post_number": 1,
                "reply_count": 0
            })
        })
        .collect::<Vec<_>>();
    let root_stream = root_posts
        .iter()
        .map(|post| {
            post.get("id")
                .and_then(Value::as_u64)
                .expect("root post id")
        })
        .collect::<Vec<_>>();
    let target_root = root_posts
        .iter()
        .find(|post| {
            post.get("post_number").and_then(Value::as_u64) == Some(u64::from(target_post_number))
        })
        .cloned()
        .expect("target root post");
    let body_post = detail_payload
        .get("post_stream")
        .and_then(Value::as_object)
        .and_then(|post_stream| post_stream.get("posts"))
        .and_then(Value::as_array)
        .and_then(|posts| posts.first())
        .cloned()
        .expect("body post");
    let mut top_level_payload = detail_payload.clone();
    top_level_payload
        .as_object_mut()
        .expect("top-level fixture object")
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .expect("top-level post stream object")
        .extend([
            ("posts".into(), Value::Array(vec![body_post])),
            ("stream".into(), json!(root_stream.clone())),
        ]);

    let responses = vec![
        raw_json_response(200, "application/json", &top_level_payload.to_string()),
        raw_json_response(
            200,
            "application/json",
            &json!({
                "post_stream": {
                    "posts": [target_root],
                    "stream": [9014]
                }
            })
            .to_string(),
        ),
        raw_json_response(
            200,
            "application/json",
            &json!({
                "post_stream": {
                    "posts": root_posts.iter().take(10).cloned().collect::<Vec<_>>(),
                    "stream": root_stream.iter().take(10).copied().collect::<Vec<_>>()
                }
            })
            .to_string(),
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core
        .fetch_topic_detail_source_snapshot(TopicDetailSourceQuery {
            topic_id: 123,
            target_post_number: Some(target_post_number),
            allow_suggested_unread_root: false,
            track_visit: true,
            force_load: true,
            initial_batch_size: 10,
            load_more_batch_size: 10,
            max_auto_batches_per_gesture: 3,
            max_auto_posts_per_gesture: 120,
        })
        .await
        .expect("topic source snapshot");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(snapshot.focused_post_number, Some(target_post_number));
    assert!(snapshot
        .loaded_posts
        .iter()
        .any(|post| post.post_number == target_post_number));
    let next_cursor = snapshot.source_cursor.expect("next source cursor");
    assert_eq!(next_cursor.topic_id, 123);
    assert_eq!(next_cursor.next_stream_offset, 10);
    assert_eq!(next_cursor.batch_size, 10);
    assert_eq!(requests.len(), 3);
    assert!(requests[0].contains("GET /t/123/14.json?track_visit=true&forceLoad=true HTTP/1.1"));
    assert!(requests[1].contains("GET /t/123/posts.json"));
    assert!(requests[1].contains("post_number=14"));
    assert!(requests[1].contains("asc=true"));
    assert!(requests[2].contains("GET /t/123/posts.json"));
}

#[tokio::test]
async fn fetch_topic_detail_page_auto_extends_to_first_unread_root() {
    let mut detail_payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    detail_payload
        .as_object_mut()
        .expect("detail fixture object")
        .extend([
            ("posts_count".into(), json!(12)),
            ("last_read_post_number".into(), json!(6)),
        ]);

    let root_posts = (2_u32..=12)
        .map(|post_number| {
            json!({
                "id": 9000 + u64::from(post_number),
                "username": format!("user-{post_number}"),
                "cooked": format!("<p>Reply {post_number}</p>"),
                "post_number": post_number,
                "reply_to_post_number": 1,
                "reply_count": 0
            })
        })
        .collect::<Vec<_>>();
    let root_stream = root_posts
        .iter()
        .map(|post| {
            post.get("id")
                .and_then(Value::as_u64)
                .expect("root post id")
        })
        .collect::<Vec<_>>();
    let body_post = detail_payload
        .get("post_stream")
        .and_then(Value::as_object)
        .and_then(|post_stream| post_stream.get("posts"))
        .and_then(Value::as_array)
        .and_then(|posts| posts.first())
        .cloned()
        .expect("body post");
    detail_payload
        .as_object_mut()
        .expect("detail fixture object")
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .expect("post stream object")
        .extend([
            ("posts".into(), Value::Array(vec![body_post])),
            ("stream".into(), json!(root_stream)),
        ]);

    let responses = vec![
        raw_json_response(200, "application/json", &detail_payload.to_string()),
        raw_json_response(
            200,
            "application/json",
            &json!({
                "post_stream": {
                    "posts": root_posts.iter().take(3).cloned().collect::<Vec<_>>(),
                    "stream": root_posts
                        .iter()
                        .take(3)
                        .filter_map(|post| post.get("id").and_then(Value::as_u64))
                        .collect::<Vec<_>>()
                }
            })
            .to_string(),
        ),
        raw_json_response(
            200,
            "application/json",
            &json!({
                "post_stream": {
                    "posts": root_posts.iter().skip(3).take(3).cloned().collect::<Vec<_>>(),
                    "stream": root_posts
                        .iter()
                        .skip(3)
                        .take(3)
                        .filter_map(|post| post.get("id").and_then(Value::as_u64))
                        .collect::<Vec<_>>()
                }
            })
            .to_string(),
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let page = core
        .fetch_topic_detail_page(TopicDetailSourceQuery {
            topic_id: 123,
            target_post_number: None,
            allow_suggested_unread_root: true,
            track_visit: true,
            force_load: true,
            initial_batch_size: 3,
            load_more_batch_size: 3,
            max_auto_batches_per_gesture: 3,
            max_auto_posts_per_gesture: 120,
        })
        .await
        .expect("topic detail page");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(
        page.tree_presentation.first_unread_root_post_number,
        Some(7)
    );
    assert!(page
        .source_snapshot
        .loaded_posts
        .iter()
        .any(|post| post.post_number == 7));
    assert_eq!(
        page.source_snapshot
            .source_cursor
            .expect("next source cursor")
            .next_stream_offset,
        6
    );
    assert_eq!(requests.len(), 3);
    assert!(requests[0].contains("GET /t/123.json?track_visit=true&forceLoad=true HTTP/1.1"));
    assert!(requests[1].contains("post_ids%5B%5D=9002"));
    assert!(requests[1].contains("post_ids%5B%5D=9004"));
    assert!(requests[2].contains("post_ids%5B%5D=9005"));
    assert!(requests[2].contains("post_ids%5B%5D=9007"));
}

#[tokio::test]
async fn fetch_topic_detail_page_skips_unread_root_auto_extend_when_not_allowed() {
    let mut detail_payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    detail_payload
        .as_object_mut()
        .expect("detail fixture object")
        .extend([
            ("posts_count".into(), json!(12)),
            ("last_read_post_number".into(), json!(6)),
        ]);

    let root_posts = (2_u32..=12)
        .map(|post_number| {
            json!({
                "id": 9000 + u64::from(post_number),
                "username": format!("user-{post_number}"),
                "cooked": format!("<p>Reply {post_number}</p>"),
                "post_number": post_number,
                "reply_to_post_number": 1,
                "reply_count": 0
            })
        })
        .collect::<Vec<_>>();
    let root_stream = root_posts
        .iter()
        .map(|post| {
            post.get("id")
                .and_then(Value::as_u64)
                .expect("root post id")
        })
        .collect::<Vec<_>>();
    let body_post = detail_payload
        .get("post_stream")
        .and_then(Value::as_object)
        .and_then(|post_stream| post_stream.get("posts"))
        .and_then(Value::as_array)
        .and_then(|posts| posts.first())
        .cloned()
        .expect("body post");
    detail_payload
        .as_object_mut()
        .expect("detail fixture object")
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .expect("post stream object")
        .extend([
            ("posts".into(), Value::Array(vec![body_post])),
            ("stream".into(), json!(root_stream)),
        ]);

    let responses = vec![
        raw_json_response(200, "application/json", &detail_payload.to_string()),
        raw_json_response(
            200,
            "application/json",
            &json!({
                "post_stream": {
                    "posts": root_posts.iter().take(3).cloned().collect::<Vec<_>>(),
                    "stream": root_posts
                        .iter()
                        .take(3)
                        .filter_map(|post| post.get("id").and_then(Value::as_u64))
                        .collect::<Vec<_>>()
                }
            })
            .to_string(),
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let page = core
        .fetch_topic_detail_page(TopicDetailSourceQuery {
            topic_id: 123,
            target_post_number: None,
            allow_suggested_unread_root: false,
            track_visit: true,
            force_load: true,
            initial_batch_size: 3,
            load_more_batch_size: 3,
            max_auto_batches_per_gesture: 3,
            max_auto_posts_per_gesture: 120,
        })
        .await
        .expect("topic detail page");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(page.tree_presentation.first_unread_root_post_number, None);
    assert!(!page
        .source_snapshot
        .loaded_posts
        .iter()
        .any(|post| post.post_number == 7));
    assert_eq!(requests.len(), 2);
    assert!(requests[0].contains("GET /t/123.json?track_visit=true&forceLoad=true HTTP/1.1"));
    assert!(requests[1].contains("post_ids%5B%5D=9002"));
    assert!(requests[1].contains("post_ids%5B%5D=9004"));
}

#[tokio::test]
async fn fetch_topic_ai_summary_parses_payload_and_query_params() {
    let body = r#"{
  "ai_topic_summary": {
    "summarized_text": "Fire summary",
    "algorithm": "linuxdo-ai",
    "outdated": "true",
    "can_regenerate": false,
    "new_posts_since_summary": "3",
    "updated_at": "2026-03-26T00:00:00Z"
  }
}"#;
    let responses = vec![raw_json_response(200, "application/json", body)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let summary = core
        .fetch_topic_ai_summary(123, true)
        .await
        .expect("topic ai summary")
        .expect("summary payload");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(summary.summarized_text, "Fire summary");
    assert_eq!(summary.algorithm.as_deref(), Some("linuxdo-ai"));
    assert!(summary.outdated);
    assert!(!summary.can_regenerate);
    assert_eq!(summary.new_posts_since_summary, 3);
    assert_eq!(summary.updated_at.as_deref(), Some("2026-03-26T00:00:00Z"));
    assert_eq!(requests.len(), 1);
    assert!(
        requests[0].contains("GET /discourse-ai/summarization/t/123?skip_age_check=true HTTP/1.1")
    );
}

#[tokio::test]
async fn fetch_topic_ai_summary_returns_none_for_unavailable_statuses() {
    for status in [403, 404] {
        let responses = vec![raw_json_response(
            status,
            "application/json",
            r#"{"errors":["no summary"]}"#,
        )];
        let server = TestServer::spawn(responses).await.expect("server");
        let core = FireCore::new(FireCoreConfig {
            base_url: server.base_url(),
            workspace_path: None,
        })
        .expect("core");

        let summary = core
            .fetch_topic_ai_summary(123, false)
            .await
            .expect("topic ai summary");
        let requests = server.shutdown_with_requests().await;

        assert_eq!(summary, None);
        assert_eq!(requests.len(), 1);
        assert!(requests[0].contains("GET /discourse-ai/summarization/t/123 HTTP/1.1"));
    }
}

#[tokio::test]
async fn fetch_topic_ai_summary_surfaces_cloudflare_challenge() {
    let responses = vec![raw_cloudflare_challenge_response(
        403,
        "<html><title>Just a moment</title><script>window._cf_chl_opt={}</script></html>",
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_ai_summary(123, false)
        .await
        .expect_err("cloudflare challenge");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic ai summary"
        }
    ));
}

#[tokio::test]
async fn fetch_private_message_detail_parses_detail_participants() {
    let mut payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    let object = payload.as_object_mut().expect("detail fixture object");
    object.insert("archetype".into(), json!("private_message"));
    object
        .get_mut("details")
        .and_then(Value::as_object_mut)
        .expect("detail metadata")
        .insert(
            "participants".into(),
            json!([
                {
                    "id": 1,
                    "username": "alice",
                    "name": "Alice",
                    "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
                },
                {
                    "id": 2,
                    "username": "bob",
                    "name": "Bob",
                    "avatar_template": "/user_avatar/linux.do/bob/{size}/1_2.png"
                }
            ]),
        );

    let responses = vec![raw_json_response(
        200,
        "application/json",
        &payload.to_string(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let detail = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: false,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let _ = server.shutdown().await;

    assert_eq!(detail.archetype.as_deref(), Some("private_message"));
    assert_eq!(detail.details.participants.len(), 2);
    assert_eq!(
        detail.details.participants[1].username.as_deref(),
        Some("bob")
    );
    assert_eq!(detail.details.participants[1].name.as_deref(), Some("Bob"));
}

#[tokio::test]
async fn fetch_topic_detail_hydrates_missing_posts_from_stream() {
    let mut detail_payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    let object = detail_payload
        .as_object_mut()
        .expect("detail fixture object");
    object.insert("posts_count".into(), json!(3));
    object
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .expect("post stream object")
        .insert("stream".into(), json!([9001, 9002, 9003]));

    let extra_posts_payload = json!({
        "post_stream": {
            "posts": [
                {
                    "id": 9003,
                    "username": "carol",
                    "cooked": "<p>Nested reply</p>",
                    "post_number": 3,
                    "reply_to_post_number": 2
                },
                {
                    "id": 9002,
                    "username": "bob",
                    "cooked": "<p>First reply</p>",
                    "post_number": 2,
                    "reply_to_post_number": 1
                }
            ],
            "stream": [9002, 9003]
        }
    })
    .to_string();

    let responses = vec![
        raw_json_response(200, "application/json", &detail_payload.to_string()),
        raw_json_response(200, "application/json", &extra_posts_payload),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let detail = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: false,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(detail.post_stream.stream, vec![9001, 9002, 9003]);
    assert_eq!(
        detail
            .post_stream
            .posts
            .iter()
            .map(|post| post.post_number)
            .collect::<Vec<_>>(),
        vec![1, 2, 3]
    );
    assert_eq!(
        detail
            .flat_posts
            .iter()
            .map(|post| post.post.post_number)
            .collect::<Vec<_>>(),
        vec![1, 2, 3]
    );
    assert_eq!(detail.flat_posts[1].depth, 0);
    assert_eq!(detail.flat_posts[2].depth, 1);
    assert_eq!(detail.flat_posts[2].parent_post_number, Some(2));
    assert_eq!(requests.len(), 2);
    assert!(requests[0].contains("GET /t/123.json HTTP/1.1"));
    assert!(requests[1]
        .contains("GET /t/123/posts.json?post_ids%5B%5D=9002&post_ids%5B%5D=9003&include_suggested=false HTTP/1.1"));
}

#[tokio::test]
async fn fetch_topic_detail_initial_keeps_partial_post_stream() {
    let mut detail_payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    detail_payload
        .as_object_mut()
        .expect("detail fixture object")
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .expect("post stream object")
        .insert("stream".into(), json!([9001, 9002, 9003]));

    let responses = vec![raw_json_response(
        200,
        "application/json",
        &detail_payload.to_string(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let detail = core
        .fetch_topic_detail_initial(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: false,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(detail.post_stream.posts.len(), 1);
    assert_eq!(detail.post_stream.stream, vec![9001, 9002, 9003]);
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /t/123.json HTTP/1.1"));
}

#[tokio::test]
async fn fetch_topic_posts_parses_batch_response() {
    let payload = json!({
        "post_stream": {
            "posts": [
                {
                    "id": 9003,
                    "username": "carol",
                    "cooked": "<p>Nested reply</p>",
                    "post_number": 3,
                    "reply_to_post_number": 2
                },
                {
                    "id": 9002,
                    "username": "bob",
                    "cooked": "<p>First reply</p>",
                    "post_number": 2,
                    "reply_to_post_number": 1
                }
            ],
            "stream": [9002, 9003]
        }
    })
    .to_string();

    let responses = vec![raw_json_response(200, "application/json", &payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let posts = core
        .fetch_topic_posts(123, vec![9002, 9003])
        .await
        .expect("posts");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(posts.len(), 2);
    assert_eq!(posts[0].id, 9003);
    assert_eq!(posts[1].reply_to_post_number, Some(1));
    assert_eq!(requests.len(), 1);
    assert!(requests[0]
        .contains("GET /t/123/posts.json?post_ids%5B%5D=9002&post_ids%5B%5D=9003&include_suggested=false HTTP/1.1"));
}

#[tokio::test]
async fn fetch_topic_posts_reuses_active_topic_response_session_cache() {
    let mut top_level_payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    let body_post = top_level_payload
        .as_object()
        .expect("detail fixture object")
        .get("post_stream")
        .and_then(Value::as_object)
        .and_then(|post_stream| post_stream.get("posts"))
        .and_then(Value::as_array)
        .and_then(|posts| posts.first())
        .cloned()
        .expect("body post");
    top_level_payload
        .as_object_mut()
        .expect("detail fixture object")
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .expect("post stream object")
        .extend([
            ("stream".into(), json!([9002])),
            (
                "posts".into(),
                json!([
                    body_post,
                    {
                        "id": 9002,
                        "username": "bob",
                        "cooked": "<p>First reply</p>",
                        "post_number": 2,
                        "reply_to_post_number": 1,
                        "reply_count": 0
                    }
                ]),
            ),
        ]);
    let post_payload = json!({
        "post_stream": {
            "posts": [
                {
                    "id": 9003,
                    "username": "carol",
                    "cooked": "<p>Nested reply</p>",
                    "post_number": 3,
                    "reply_to_post_number": 2
                }
            ],
            "stream": [9003]
        }
    })
    .to_string();
    let responses = vec![
        raw_json_response(200, "application/json", &top_level_payload.to_string()),
        raw_json_response(200, "application/json", &post_payload),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _snapshot = core
        .fetch_topic_detail_source_snapshot(TopicDetailSourceQuery {
            topic_id: 123,
            target_post_number: None,
            allow_suggested_unread_root: false,
            track_visit: true,
            force_load: true,
            initial_batch_size: 1,
            load_more_batch_size: 40,
            max_auto_batches_per_gesture: 3,
            max_auto_posts_per_gesture: 120,
        })
        .await
        .expect("topic source snapshot");
    let posts = core
        .fetch_topic_posts(123, vec![9002, 9003])
        .await
        .expect("posts");
    let cached_posts = core
        .fetch_topic_posts(123, vec![9002, 9003])
        .await
        .expect("cached posts");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(
        posts.iter().map(|post| post.id).collect::<Vec<_>>(),
        vec![9002, 9003]
    );
    assert_eq!(
        cached_posts.iter().map(|post| post.id).collect::<Vec<_>>(),
        vec![9002, 9003]
    );
    assert_eq!(requests.len(), 2);
    assert!(requests[1]
        .contains("GET /t/123/posts.json?post_ids%5B%5D=9003&include_suggested=false HTTP/1.1"));
    assert!(!requests[1].contains("post_ids%5B%5D=9002"));
}

#[tokio::test]
async fn fetch_topic_detail_tolerates_object_bookmarks_and_accepted_answer_metadata() {
    let mut payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    let object = payload.as_object_mut().expect("detail fixture object");
    object.insert(
        "bookmarks".into(),
        json!([
            {
                "id": 1240,
                "bookmarkable_type": "Topic",
                "bookmarkable_id": 123
            },
            {
                "id": 1241,
                "bookmarkable_type": "Post",
                "bookmarkable_id": 9001
            }
        ]),
    );
    object.insert(
        "accepted_answer".into(),
        json!({
            "post_number": 5,
            "username": "alice"
        }),
    );
    object.insert("has_accepted_answer".into(), json!(true));
    let payload = payload.to_string();

    let responses = vec![raw_json_response(200, "application/json", &payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let detail = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: true,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let _ = server.shutdown().await;

    assert_eq!(detail.bookmarks, vec![1240, 1241]);
    assert!(detail.bookmarked);
    assert_eq!(detail.bookmark_id, Some(1240));
    assert!(detail.post_stream.posts[0].bookmarked);
    assert_eq!(detail.post_stream.posts[0].bookmark_id, Some(1241));
    assert!(detail.accepted_answer);
    assert!(detail.has_accepted_answer);
}

#[tokio::test]
async fn fetch_badge_detail_parses_badge_envelope() {
    let payload = r#"{
      "badge": {
        "id": 7,
        "name": "Great Reply",
        "description": "<p>Short</p>",
        "badge_type_id": 1,
        "grant_count": 12,
        "long_description": "<p>Long</p>",
        "slug": "great-reply"
      }
    }"#;
    let responses = vec![raw_json_response(200, "application/json", payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let badge = core.fetch_badge_detail(7).await.expect("badge detail");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(badge.id, 7);
    assert_eq!(badge.name, "Great Reply");
    assert_eq!(badge.grant_count, 12);
    assert_eq!(badge.long_description.as_deref(), Some("<p>Long</p>"));
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /badges/7.json HTTP/1.1"));
}

#[tokio::test]
async fn fetch_topic_detail_tolerates_null_scalars_and_null_details() {
    let mut payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail fixture json");
    let object = payload.as_object_mut().expect("detail fixture object");
    object.insert("title".into(), Value::Null);
    object.insert("category_id".into(), json!("2"));
    object.insert("details".into(), Value::Null);

    let post = object
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .and_then(|stream| stream.get_mut("posts"))
        .and_then(Value::as_array_mut)
        .and_then(|posts| posts.first_mut())
        .and_then(Value::as_object_mut)
        .expect("first post");
    post.insert("username".into(), Value::Null);
    post.insert("cooked".into(), Value::Null);
    post.insert("post_type".into(), json!("1"));
    post.insert("like_count".into(), Value::Null);
    post.insert("reply_count".into(), Value::Null);
    post.insert("reply_to_post_number".into(), json!("12"));
    post.insert("bookmarked".into(), Value::Null);
    post.insert("accepted_answer".into(), Value::Null);
    post.insert("can_edit".into(), Value::Null);
    post.insert("can_delete".into(), Value::Null);
    post.insert("can_recover".into(), Value::Null);
    post.insert("hidden".into(), Value::Null);
    post.insert("reactions".into(), Value::Null);

    let payload = payload.to_string();

    let responses = vec![raw_json_response(200, "application/json", &payload)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let detail = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: true,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let _ = server.shutdown().await;

    assert_eq!(detail.title, "");
    assert_eq!(detail.category_id, Some(2));
    assert_eq!(detail.details.notification_level, None);
    assert_eq!(detail.details.created_by, None);
    assert!(!detail.details.can_edit);
    assert_eq!(detail.post_stream.posts[0].username, "");
    assert_eq!(detail.post_stream.posts[0].cooked, "");
    assert_eq!(detail.post_stream.posts[0].reply_to_post_number, Some(12));
    assert_eq!(detail.post_stream.posts[0].reactions.len(), 0);
    assert_eq!(detail.post_stream.posts[0].like_count, 0);
    assert_eq!(detail.post_stream.posts[0].reply_count, 0);
}

#[tokio::test]
async fn fetch_topic_detail_tolerates_malformed_optional_nested_records() {
    let mut payload: Value =
        serde_json::from_str(&sample_topic_detail_json()).expect("detail payload json");
    let object = payload.as_object_mut().expect("detail fixture object");
    object.insert(
        "details".into(),
        json!({
            "notification_level": "1",
            "can_edit": "1",
            "created_by": "unexpected"
        }),
    );

    let post = object
        .get_mut("post_stream")
        .and_then(Value::as_object_mut)
        .and_then(|stream| stream.get_mut("posts"))
        .and_then(Value::as_array_mut)
        .and_then(|posts| posts.first_mut())
        .and_then(Value::as_object_mut)
        .expect("first post");
    post.insert(
        "current_user_reaction".into(),
        Value::String("unexpected".into()),
    );

    let responses = vec![raw_json_response(
        200,
        "application/json",
        &payload.to_string(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let detail = core
        .fetch_topic_detail(TopicDetailQuery {
            topic_id: 123,
            post_number: None,
            track_visit: true,
            force_load: false,
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let _ = server.shutdown().await;

    assert_eq!(detail.details.notification_level, Some(1));
    assert!(detail.details.can_edit);
    assert_eq!(detail.details.created_by, None);
    assert_eq!(detail.post_stream.posts[0].current_user_reaction, None);
}

#[tokio::test]
async fn refresh_csrf_token_updates_session_from_network() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{"csrf":"fresh-csrf"}"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core.refresh_csrf_token().await.expect("csrf refresh");
    server.shutdown().await;

    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("fresh-csrf"));
}

#[tokio::test]
async fn refresh_csrf_token_preserves_login_when_success_response_reports_logged_out() {
    let body = r#"{"csrf":"fresh-csrf"}"#;
    let response = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: application/json\r\nContent-Length: {}\r\nDiscourse-Logged-Out: 1\r\nSet-Cookie: _t=; path=/; max-age=0; expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let server = TestServer::spawn(vec![response]).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: None,
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let snapshot = core
        .refresh_csrf_token_if_needed()
        .await
        .expect("successful csrf response should be usable");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("fresh-csrf"));
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("token"));
    assert_eq!(snapshot.cookies.forum_session.as_deref(), Some("forum"));
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(requests.len(), 1);
    let request = requests[0].to_ascii_lowercase();
    assert!(request.contains("get /session/csrf http/1.1"));
    assert!(request.contains("discourse-logged-in: true"));
    assert!(request.contains("_t=token"));
    assert!(request.contains("_forum_session=forum"));
}

#[tokio::test]
async fn refresh_csrf_token_accepts_scalar_tokens() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{"csrf":12345}"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core.refresh_csrf_token().await.expect("csrf refresh");
    server.shutdown().await;

    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("12345"));
}

#[tokio::test]
async fn concurrent_csrf_refresh_if_needed_shares_in_flight_request() {
    let server = TestServer::spawn_scripted(vec![TestServerStep::delayed(
        raw_json_response(200, "application/json", r#"{"csrf":"fresh-csrf"}"#),
        Duration::from_millis(50),
    )])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: None,
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let (first, second) = tokio::join!(
        core.refresh_csrf_token_if_needed(),
        core.refresh_csrf_token_if_needed()
    );
    let first = first.expect("first csrf refresh");
    let second = second.expect("second csrf refresh");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(first.cookies.csrf_token.as_deref(), Some("fresh-csrf"));
    assert_eq!(second.cookies.csrf_token.as_deref(), Some("fresh-csrf"));
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /session/csrf HTTP/1.1"));
}

#[tokio::test]
async fn queued_csrf_refresh_if_needed_does_not_retry_after_session_logout() {
    let server = TestServer::spawn_scripted(vec![TestServerStep::delayed(
        raw_json_response(200, "application/json", r#"{"csrf":"fresh-csrf"}"#),
        Duration::from_millis(120),
    )])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: None,
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let first_core = core.clone();
    let first = tokio::spawn(async move { first_core.refresh_csrf_token_if_needed().await });
    sleep(Duration::from_millis(20)).await;

    let second_core = core.clone();
    let second = tokio::spawn(async move { second_core.refresh_csrf_token_if_needed().await });
    sleep(Duration::from_millis(20)).await;

    let logged_out = core.logout_local(true);
    assert!(!logged_out.cookies.can_authenticate_requests());

    let first = first.await.expect("first task");
    let second = second.await.expect("second task");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(
        first,
        Err(FireCoreError::StaleSessionResponse {
            operation: "refresh csrf token"
        })
    ));
    let second = second.expect("queued csrf refresh should skip after logout");
    assert_eq!(second.cookies.csrf_token, None);
    assert!(!second.cookies.can_authenticate_requests());
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /session/csrf HTTP/1.1"));
}

#[tokio::test]
async fn logout_remote_retries_after_bad_csrf() {
    let responses = vec![
        raw_text_response(403, r#"["BAD CSRF"]"#),
        raw_json_response(200, "application/json", r#"{"csrf":"retry-csrf"}"#),
        raw_text_response(200, "{}"),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("stale-csrf".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let snapshot = core.logout_remote(true).await.expect("logout");
    let requests = server.shutdown().await;

    assert!(!snapshot.cookies.has_login_session());
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(requests.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn refresh_bootstrap_fetches_home_html() {
    let responses = vec![raw_text_response(200, &sample_home_html())];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core.refresh_bootstrap().await.expect("bootstrap refresh");
    let requests = server.shutdown_with_requests().await;
    let trace = core.network_trace_detail(1).expect("network trace detail");

    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
    assert_eq!(requests.len(), 1);

    let wire_request = requests[0].to_ascii_lowercase();
    assert!(wire_request.contains("get / http/1.1"));
    assert!(wire_request.contains("accept: text/html"));
    assert!(wire_request.contains("accept-language: zh-cn,zh;q=0.9,en;q=0.8"));
    assert!(wire_request.contains("user-agent: mozilla/5.0"));

    assert!(trace
        .request_headers
        .iter()
        .any(|header| header.name == "user-agent" && header.value.starts_with("Mozilla/5.0")));
    assert!(trace.request_headers.iter().any(|header| {
        header.name == "accept-language" && header.value == "zh-CN,zh;q=0.9,en;q=0.8"
    }));
}

#[tokio::test]
async fn refresh_bootstrap_falls_back_to_site_json_when_home_lacks_site_metadata() {
    let home_html = r#"
<!doctype html>
<html>
  <head>
    <meta name="csrf-token" content="csrf-token">
    <meta name="current-username" content="alice">
    <meta name="discourse-base-uri" content="/">
  </head>
  <body>
    <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;id&quot;:1,&quot;username&quot;:&quot;alice&quot;,&quot;notification_channel_position&quot;:42},&quot;siteSettings&quot;:{&quot;long_polling_base_url&quot;:&quot;https://linux.do&quot;,&quot;min_post_length&quot;:20,&quot;discourse_reactions_enabled_reactions&quot;:&quot;heart|clap|tada&quot;},&quot;topicTrackingStateMeta&quot;:{&quot;message_bus_last_id&quot;:42}}"></div>
  </body>
</html>
"#;
    let site_json = r#"{
  "categories": [
    {
      "id": 2,
      "name": "Rust",
      "slug": "rust",
      "parent_category_id": 1,
      "color": "FFFFFF",
      "text_color": "000000"
    }
  ],
  "top_tags": [
    {"name": "swift"},
    "rust"
  ],
  "can_tag_topics": true
}"#;
    let responses = vec![
        raw_text_response(200, home_html),
        raw_json_response(200, "application/json", site_json),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core.refresh_bootstrap().await.expect("bootstrap refresh");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
    assert!(snapshot.bootstrap.has_site_settings);
    assert!(snapshot.bootstrap.has_site_metadata);
    assert_eq!(snapshot.bootstrap.categories.len(), 1);
    assert_eq!(snapshot.bootstrap.top_tags, vec!["swift", "rust"]);
    assert!(snapshot.bootstrap.can_tag_topics);
    assert_eq!(requests.len(), 2);
    assert!(requests[0].to_ascii_lowercase().contains("get / http/1.1"));
    assert!(requests[1]
        .to_ascii_lowercase()
        .contains("get /site.json http/1.1"));
}

#[tokio::test]
async fn refresh_bootstrap_uses_browser_user_agent_and_full_platform_cookies() {
    let responses = vec![raw_text_response(200, &sample_home_html())];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: None,
        current_url: Some(server.base_url()),
        browser_user_agent: Some("Mozilla/5.0 Exact WKWebView".into()),
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: Some("/".into()),
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: Some("/".into()),
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "__cf_bm".into(),
                value: "browser-context".into(),
                domain: None,
                path: Some("/".into()),
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let _ = core.refresh_bootstrap().await.expect("bootstrap refresh");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(requests.len(), 1);
    let wire_request = requests[0].to_ascii_lowercase();
    assert!(wire_request.contains("user-agent: mozilla/5.0 exact wkwebview"));
    let cookie_header = wire_request
        .lines()
        .find(|line| line.starts_with("cookie: "))
        .expect("cookie header");
    assert!(cookie_header.contains("_t=token"));
    assert!(cookie_header.contains("_forum_session=forum"));
    assert!(cookie_header.contains("__cf_bm=browser-context"));
}

#[tokio::test]
async fn create_reply_refreshes_csrf_and_parses_wrapped_post_payload() {
    let responses = vec![
        raw_json_response(200, "application/json", r#"{"csrf":"fresh-csrf"}"#),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "post": {
                "id": 9010,
                "username": "alice",
                "name": "Alice",
                "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
                "cooked": "<p>Reply body</p>",
                "post_number": 2,
                "post_type": 1,
                "created_at": "2026-03-28T00:10:00Z",
                "updated_at": "2026-03-28T00:10:00Z",
                "like_count": 0,
                "reply_count": 0,
                "reply_to_post_number": 1,
                "bookmarked": false,
                "bookmark_id": null,
                "reactions": [],
                "current_user_reaction": null,
                "accepted_answer": false,
                "can_edit": true,
                "can_delete": true,
                "can_recover": false,
                "hidden": false
              }
            }"#,
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: None,
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let post = core
        .create_reply(TopicReplyRequest {
            topic_id: 123,
            raw: "Reply body".into(),
            reply_to_post_number: Some(1),
        })
        .await
        .expect("create reply");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(post.id, 9010);
    assert_eq!(post.post_number, 2);
    assert_eq!(post.reply_to_post_number, Some(1));
    assert_eq!(requests.len(), 2);
    assert!(requests[0].contains("GET /session/csrf HTTP/1.1"));
    assert!(requests[1].contains("POST /posts.json HTTP/1.1"));
    assert!(requests[1]
        .to_ascii_lowercase()
        .contains("x-csrf-token: fresh-csrf"));
    assert!(requests[1].contains("topic_id=123&raw=Reply+body&reply_to_post_number=1"));
    assert_eq!(
        core.snapshot().cookies.csrf_token.as_deref(),
        Some("fresh-csrf")
    );
}

#[tokio::test]
async fn create_reply_refreshes_csrf_before_logged_out_header_handling() {
    let bad_csrf_body = r#"["BAD CSRF"]"#;
    let bad_csrf_response = format!(
        "HTTP/1.1 403 TEST\r\nContent-Type: application/json; charset=utf-8\r\nDiscourse-Logged-Out: 1\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{bad_csrf_body}",
        bad_csrf_body.len()
    );
    let responses = vec![
        bad_csrf_response,
        raw_json_response(200, "application/json", r#"{"csrf":"fresh-csrf"}"#),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "post": {
                "id": 9010,
                "username": "alice",
                "name": "Alice",
                "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
                "cooked": "<p>Reply body</p>",
                "post_number": 2,
                "post_type": 1,
                "created_at": "2026-03-28T00:10:00Z",
                "updated_at": "2026-03-28T00:10:00Z",
                "like_count": 0,
                "reply_count": 0,
                "reply_to_post_number": 1,
                "bookmarked": false,
                "bookmark_id": null,
                "reactions": [],
                "current_user_reaction": null,
                "accepted_answer": false,
                "can_edit": true,
                "can_delete": true,
                "can_recover": false,
                "hidden": false
              }
            }"#,
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: Some("stale-csrf".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let post = core
        .create_reply(TopicReplyRequest {
            topic_id: 123,
            raw: "Reply body".into(),
            reply_to_post_number: Some(1),
        })
        .await
        .expect("create reply after BAD CSRF refresh");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(post.id, 9010);
    assert_eq!(requests.len(), 3);
    assert!(requests[0].contains("POST /posts.json HTTP/1.1"));
    assert!(requests[1].contains("GET /session/csrf HTTP/1.1"));
    assert!(requests[2].contains("POST /posts.json HTTP/1.1"));
    assert!(requests[2]
        .to_ascii_lowercase()
        .contains("x-csrf-token: fresh-csrf"));
    assert_eq!(
        core.snapshot().cookies.csrf_token.as_deref(),
        Some("fresh-csrf")
    );
}

#[tokio::test]
async fn create_reply_cloudflare_retry_rebuilds_stale_csrf_header() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "post": {
                "id": 9010,
                "username": "alice",
                "name": "Alice",
                "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
                "cooked": "<p>Reply body</p>",
                "post_number": 2,
                "post_type": 1,
                "created_at": "2026-03-28T00:10:00Z",
                "updated_at": "2026-03-28T00:10:00Z",
                "like_count": 0,
                "reply_count": 0,
                "reply_to_post_number": 1,
                "bookmarked": false,
                "bookmark_id": null,
                "reactions": [],
                "current_user_reaction": null,
                "accepted_answer": false,
                "can_edit": true,
                "can_delete": true,
                "can_recover": false,
                "hidden": false
              }
            }"#,
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: Some("stale-csrf".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });
    {
        let handler_core = core.clone();
        core.set_cloudflare_challenge_handler(move |_| {
            let core = handler_core.clone();
            async move {
                let _ = core.apply_csrf_token("fresh-csrf".into());
                fire_models::CloudflareChallengeResult {
                    completed: true,
                    user_cancelled: false,
                    fresh_cf_clearance: Some("new-clearance".into()),
                    cookies: vec![PlatformCookie {
                        name: "cf_clearance".into(),
                        value: "new-clearance".into(),
                        domain: Some("linux.do".into()),
                        path: Some("/".into()),
                        expires_at_unix_ms: None,
                        same_site: None,
                    }],
                    browser_user_agent: None,
                }
            }
        });
    }

    let post = core
        .create_reply(TopicReplyRequest {
            topic_id: 123,
            raw: "Reply body".into(),
            reply_to_post_number: Some(1),
        })
        .await
        .expect("create reply after challenge");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(post.id, 9010);
    assert_eq!(requests.len(), 2);
    assert!(requests[0]
        .to_ascii_lowercase()
        .contains("x-csrf-token: stale-csrf"));
    assert!(requests[1]
        .to_ascii_lowercase()
        .contains("x-csrf-token: fresh-csrf"));
    assert!(
        !requests[1]
            .to_ascii_lowercase()
            .contains("x-csrf-token: stale-csrf"),
        "retry must not replay stale CSRF header:\n{}",
        requests[1]
    );
}

#[tokio::test]
async fn create_reply_surfaces_pending_review_state() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{"action":"enqueued","pending_count":2}"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let error = core
        .create_reply(TopicReplyRequest {
            topic_id: 123,
            raw: "Reply body".into(),
            reply_to_post_number: None,
        })
        .await
        .expect_err("create reply should enqueue");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::PostEnqueued { pending_count: 2 }
    ));
}

#[tokio::test]
async fn create_reply_surfaces_cloudflare_challenge_error() {
    let responses = vec![raw_cloudflare_challenge_response(
        403,
        r#"<html><body><h1>Just a moment</h1><script src="/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1"></script></body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: Some("csrf".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let error = core
        .create_reply(TopicReplyRequest {
            topic_id: 123,
            raw: "Reply body".into(),
            reply_to_post_number: Some(1),
        })
        .await
        .expect_err("cloudflare challenge should surface as an error");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "create reply"
        }
    ));
}

#[tokio::test]
async fn toggle_post_reaction_parses_reaction_update_payload() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{
          "reactions": [
            { "id": "heart", "type": "emoji", "count": 4 },
            { "id": "laughing", "type": "emoji", "count": 1 }
          ],
          "current_user_reaction": { "id": "laughing", "type": "emoji", "count": 1, "can_undo": true }
        }"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let update = core
        .toggle_post_reaction(9001, "laughing".into())
        .await
        .expect("toggle post reaction");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(update.reactions.len(), 2);
    assert_eq!(update.reactions[0].id, "heart");
    assert_eq!(
        update
            .current_user_reaction
            .as_ref()
            .map(|reaction| reaction.id.as_str()),
        Some("laughing")
    );
    assert_eq!(
        update
            .current_user_reaction
            .as_ref()
            .and_then(|reaction| reaction.can_undo),
        Some(true)
    );
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains(
        "PUT /discourse-reactions/posts/9001/custom-reactions/laughing/toggle.json HTTP/1.1"
    ));
    assert!(requests[0]
        .to_ascii_lowercase()
        .contains("x-csrf-token: csrf-token"));
    assert!(requests[0]
        .to_ascii_lowercase()
        .contains("content-length: 0"));
}

#[tokio::test]
async fn toggle_post_reaction_tolerates_malformed_current_user_reaction() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{
          "reactions": [
            { "id": "heart", "type": "emoji", "count": 4 }
          ],
          "current_user_reaction": "unexpected"
        }"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let update = core
        .toggle_post_reaction(9001, "laughing".into())
        .await
        .expect("toggle post reaction");

    let _ = server.shutdown().await;
    assert_eq!(update.reactions.len(), 1);
    assert_eq!(update.current_user_reaction, None);
}

#[tokio::test]
async fn toggle_post_reaction_encodes_reaction_path_segment() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{
          "reactions": [
            { "id": "+1", "type": "emoji", "count": 1 }
          ],
          "current_user_reaction": { "id": "+1", "type": "emoji", "count": 1, "can_undo": true }
        }"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let update = core
        .toggle_post_reaction(9001, "+1".into())
        .await
        .expect("toggle post reaction");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(
        update
            .current_user_reaction
            .as_ref()
            .map(|reaction| reaction.id.as_str()),
        Some("+1")
    );
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains(
        "PUT /discourse-reactions/posts/9001/custom-reactions/%2B1/toggle.json HTTP/1.1"
    ));
}

#[tokio::test]
async fn fetch_reaction_users_uses_reactions_users_endpoint_and_skips_malformed_items() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{
          "reaction_users": [
            {
              "id": "heart",
              "count": "2",
              "users": [
                {
                  "id": "1",
                  "username": "alice",
                  "name": "Alice",
                  "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
                },
                { "bad": "ignored" }
              ]
            },
            1,
            {
              "id": "clap",
              "users": [
                { "username": "bob" }
              ]
            }
          ]
        }"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let groups = core
        .fetch_reaction_users(9001)
        .await
        .expect("reaction users");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0].id, "heart");
    assert_eq!(groups[0].count, 2);
    assert_eq!(groups[0].users.len(), 1);
    assert_eq!(groups[0].users[0].id, 1);
    assert_eq!(groups[0].users[0].username, "alice");
    assert_eq!(groups[0].users[0].name.as_deref(), Some("Alice"));
    assert_eq!(
        groups[0].users[0].avatar_template.as_deref(),
        Some("/user_avatar/linux.do/alice/{size}/1_2.png")
    );
    assert_eq!(groups[1].id, "clap");
    assert_eq!(groups[1].count, 1);
    assert_eq!(groups[1].users.len(), 1);
    assert_eq!(groups[1].users[0].id, 0);
    assert_eq!(groups[1].users[0].username, "bob");
    assert_eq!(requests.len(), 1);
    assert!(
        requests[0].contains("GET /discourse-reactions/posts/9001/reactions-users.json HTTP/1.1")
    );
}

#[tokio::test]
async fn like_post_uses_post_actions_endpoint() {
    let responses = vec![raw_text_response(200, "{}")];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let update = core.like_post(9001).await.expect("like post");
    let requests = server.shutdown_with_requests().await;

    assert!(update.is_none());
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("POST /post_actions HTTP/1.1"));
    assert!(requests[0]
        .to_ascii_lowercase()
        .contains("x-csrf-token: csrf-token"));
    assert!(requests[0].contains("id=9001&post_action_type_id=2"));
}

#[tokio::test]
async fn like_post_without_auth_session_does_not_send_undefined_csrf_request() {
    let server = TestServer::spawn(Vec::new()).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .like_post(9001)
        .await
        .expect_err("write without an auth session should fail before network");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(error, FireCoreError::MissingLoginSession));
    assert!(requests.is_empty());
}

#[tokio::test]
async fn like_post_parses_reaction_update_when_response_includes_reaction_fields() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{
          "id": 9001,
          "post_number": 1,
          "like_count": 15,
          "reactions": [
            { "id": "heart", "type": "emoji", "count": 15 }
          ],
          "current_user_reaction": { "id": "heart", "type": "emoji", "count": 15, "can_undo": true }
        }"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server.base_url()),
        browser_user_agent: None,
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });

    let update = core
        .like_post(9001)
        .await
        .expect("like post")
        .expect("reaction update");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(update.reactions.len(), 1);
    assert_eq!(update.reactions[0].id, "heart");
    assert_eq!(update.reactions[0].count, 15);
    assert_eq!(
        update
            .current_user_reaction
            .as_ref()
            .map(|reaction| reaction.id.as_str()),
        Some("heart")
    );
    assert_eq!(
        update
            .current_user_reaction
            .as_ref()
            .and_then(|reaction| reaction.can_undo),
        Some(true)
    );
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("POST /post_actions HTTP/1.1"));
}
