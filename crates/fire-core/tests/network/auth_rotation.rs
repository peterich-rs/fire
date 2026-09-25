use super::*;

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
