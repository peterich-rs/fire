use super::*;

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
async fn fetch_topic_detail_source_snapshot_recovers_missing_body_via_stream_head_post_ids() {
    // Notification deep-links open `/t/{id}/{N}.json`. Large topics return a
    // nearby posts chunk without OP/post #1. Body must be recovered from
    // stream[0] via post_ids[] instead of hard-failing posts.json?post_number=1.
    let target_post_number = 200_u32;
    let body_post = json!({
        "id": 1001,
        "username": "op",
        "cooked": "<p>Original post</p>",
        "post_number": 1,
        "reply_to_post_number": null,
        "reply_count": 5
    });
    let target_post = json!({
        "id": 1200,
        "username": "replier",
        "cooked": "<p>Deep reply</p>",
        "post_number": target_post_number,
        "reply_to_post_number": 1,
        "reply_count": 0
    });
    let stream = (1_u64..=220).map(|n| 1000 + n).collect::<Vec<_>>();
    let mid_topic_payload = json!({
        "id": 123,
        "title": "Large topic",
        "slug": "large-topic",
        "posts_count": 220,
        "post_stream": {
            "posts": [target_post.clone()],
            "stream": stream
        }
    });
    let body_by_ids = json!({
        "post_stream": {
            "posts": [body_post.clone()],
            "stream": [1001]
        }
    });
    // Remaining initial stream ids (1002..1010) after body recovery.
    let initial_batch_posts = (2_u32..=10)
        .map(|post_number| {
            json!({
                "id": 1000 + u64::from(post_number),
                "username": format!("u{post_number}"),
                "cooked": format!("<p>r{post_number}</p>"),
                "post_number": post_number,
                "reply_to_post_number": 1,
                "reply_count": 0
            })
        })
        .collect::<Vec<_>>();
    let initial_batch = json!({
        "post_stream": {
            "posts": initial_batch_posts,
            "stream": (1002_u64..=1010).collect::<Vec<_>>()
        }
    });

    let server = TestServer::spawn(vec![
        raw_json_response(200, "application/json", &mid_topic_payload.to_string()),
        // resolve_topic_body_post: stream head via post_ids[]
        raw_json_response(200, "application/json", &body_by_ids.to_string()),
        // initial batch hydration for missing stream ids
        raw_json_response(200, "application/json", &initial_batch.to_string()),
    ])
    .await
    .expect("server");
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
        .expect("topic source snapshot should recover missing body");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(snapshot.body.post.post_number, 1);
    assert_eq!(snapshot.body.post.id, 1001);
    assert!(snapshot
        .loaded_posts
        .iter()
        .any(|post| post.post_number == target_post_number));
    assert!(requests[0].contains("GET /t/123/200.json"));
    assert!(
        requests.iter().any(|request| {
            request.contains("GET /t/123/posts.json") && request.contains("post_ids%5B%5D=1001")
                || request.contains("post_ids[]=1001")
        }),
        "expected OP recovery via post_ids[] stream head, requests={requests:?}"
    );
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
            operation: "fetch topic ai summary",
            ..
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
