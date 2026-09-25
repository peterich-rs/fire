use super::*;

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

/// Post-challenge rebuild must force `/session/csrf` after bootstrap when home
/// HTML lacks csrf meta and Set-Cookie rotated the forum session (which clears
/// the cached CSRF via auth rotation). Without this, writes stay blocked on
/// `can_write_authenticated_api == false` until a later opportunistic refresh.
#[tokio::test]
async fn complete_cloudflare_challenge_realigns_csrf_after_bootstrap_without_meta() {
    let home_without_csrf = r#"
<!doctype html>
<html>
  <head>
    <meta name="shared_session_key" content="shared-session">
    <meta name="current-username" content="alice">
    <meta name="discourse-base-uri" content="/">
  </head>
  <body>
    <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;id&quot;:1,&quot;username&quot;:&quot;alice&quot;},&quot;siteSettings&quot;:{&quot;long_polling_base_url&quot;:&quot;https://linux.do&quot;},&quot;site&quot;:{&quot;categories&quot;:[],&quot;top_tags&quot;:[],&quot;can_tag_topics&quot;:false}}"></div>
  </body>
</html>
"#;
    let rotating_home = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: text/html\r\nContent-Length: {}\r\nSet-Cookie: _forum_session=rotated-forum; path=/; SameSite=Lax\r\nConnection: close\r\n\r\n{home_without_csrf}",
        home_without_csrf.len()
    );
    let home_again = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{home_without_csrf}",
        home_without_csrf.len()
    );
    let responses = vec![
        // schedule_post_challenge: refresh_bootstrap
        rotating_home,
        // schedule_post_challenge: forced refresh_csrf_token
        raw_json_response(200, "application/json", r#"{"csrf":"fresh-csrf"}"#),
        // refresh_all_forced core: refresh_bootstrap again
        home_again,
        // refresh_all_forced core: home topic list
        raw_json_response(200, "application/json", &sample_latest_json()),
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
        browser_user_agent: Some("FireTests/1.0".into()),
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
                value: "old-clearance".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
    });
    assert_eq!(
        core.snapshot().cookies.csrf_token.as_deref(),
        Some("stale-csrf")
    );
    assert!(core.snapshot().readiness().can_write_authenticated_api);

    let _ = core.complete_cloudflare_challenge(
        vec![PlatformCookie {
            name: "cf_clearance".into(),
            value: "fresh-clearance".into(),
            domain: Some("linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: Some("None".into()),
        }],
        Some("fresh-clearance".into()),
        Some("FireTests/1.0".into()),
    );

    // Post-challenge task: 30ms + trust settle (~400ms) + bootstrap + csrf.
    let mut realigned = false;
    for _ in 0..80 {
        let snapshot = core.snapshot();
        if snapshot.cookies.csrf_token.as_deref() == Some("fresh-csrf")
            && snapshot.cookies.forum_session.as_deref() == Some("rotated-forum")
            && snapshot.readiness().can_write_authenticated_api
        {
            realigned = true;
            break;
        }
        sleep(Duration::from_millis(50)).await;
    }

    let requests = server.shutdown_with_requests().await;
    let snapshot = core.snapshot();

    assert!(
        realigned,
        "expected post-challenge CSRF realign; csrf={:?} forum={:?} can_write={}",
        snapshot.cookies.csrf_token,
        snapshot.cookies.forum_session,
        snapshot.readiness().can_write_authenticated_api
    );
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("token"));
    assert_eq!(
        snapshot.cookies.cf_clearance.as_deref(),
        Some("fresh-clearance")
    );
    assert!(
        requests
            .iter()
            .any(|request| { request.to_ascii_lowercase().contains("get /session/csrf") }),
        "post-challenge rebuild must call /session/csrf:\n{requests:#?}"
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
            operation: "create reply",
            ..
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
