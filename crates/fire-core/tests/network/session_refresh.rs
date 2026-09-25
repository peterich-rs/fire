use super::*;

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
