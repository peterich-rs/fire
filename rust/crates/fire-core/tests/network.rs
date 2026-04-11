mod common;

use std::sync::atomic::Ordering;

use common::{
    raw_json_response, raw_text_response, sample_home_html, sample_latest_json,
    sample_topic_detail_json, TestServer,
};
use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{
    LoginSyncInput, PlatformCookie, TopicDetailQuery, TopicListKind, TopicListQuery,
    TopicReplyRequest, TopicTag,
};
use serde_json::{json, Value};

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
async fn fetch_topic_list_surfaces_cloudflare_challenge_error() {
    let responses = vec![raw_text_response(
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
async fn fetch_topic_list_surfaces_login_required_when_success_response_invalidates_auth() {
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
        ],
    });

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            page: Some(1),
            ..TopicListQuery::default()
        })
        .await
        .expect_err("auth invalidation should surface");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::LoginRequired { message, .. }
            if message == "登录状态已失效，请重新登录。"
    ));

    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.t_token, None);
    assert_eq!(snapshot.cookies.forum_session, None);
    assert_eq!(snapshot.cookies.csrf_token, None);
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(snapshot.bootstrap.current_username, None);
    assert!(!snapshot.bootstrap.has_preloaded_data);
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
            filter: None,
            username_filters: None,
            filter_top_level_replies: false,
        })
        .await
        .expect("detail");
    let _ = server.shutdown().await;

    assert_eq!(detail.id, 123);
    assert_eq!(detail.title, "Fire topic");
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
        .contains("GET /t/123/posts.json?post_ids%5B%5D=9002&post_ids%5B%5D=9003 HTTP/1.1"));
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
        .contains("GET /t/123/posts.json?post_ids%5B%5D=9002&post_ids%5B%5D=9003 HTTP/1.1"));
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: Some("/".into()),
                expires_at_unix_ms: None,
            },
            PlatformCookie {
                name: "__cf_bm".into(),
                value: "browser-context".into(),
                domain: None,
                path: Some("/".into()),
                expires_at_unix_ms: None,
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
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
    let responses = vec![raw_text_response(
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
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
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
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
