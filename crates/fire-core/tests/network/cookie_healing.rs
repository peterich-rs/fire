use super::*;

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
