use super::*;

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
