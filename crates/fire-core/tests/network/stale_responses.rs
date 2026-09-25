use super::*;

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
