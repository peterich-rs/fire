mod common;

use common::{raw_json_response, sample_home_html, TestServer};
use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{LoginSyncInput, PlatformCookie, TopicListKind, TopicListQuery};

fn login_sync_input(server_url: &str) -> LoginSyncInput {
    LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some(server_url.into()),
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
    }
}

#[tokio::test]
async fn probe_session_returns_valid_when_user_exists() {
    let probe_body = r#"{"current_user":{"username":"alice"}}"#;
    let responses = vec![raw_json_response(200, "application/json", probe_body)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let result = core.probe_session().await.expect("probe");
    let _ = server.shutdown().await;

    assert_eq!(
        result,
        fire_models::ProbeResult::Valid {
            username: "alice".into()
        }
    );
}

#[tokio::test]
async fn probe_session_returns_invalid_on_404() {
    let responses = vec![raw_json_response(404, "application/json", "{}")];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let result = core.probe_session().await.expect("probe");
    let _ = server.shutdown().await;

    assert_eq!(result, fire_models::ProbeResult::Invalid);
}

#[tokio::test]
async fn strike_system_probes_on_strong_signal_and_logout_on_invalid_probe() {
    let not_logged_in_body =
        r#"{"errors":["需要登录才能执行此操作。"],"error_type":"not_logged_in"}"#;
    let probe_body = r#"{}"#;
    let responses = vec![
        raw_json_response(403, "application/json", not_logged_in_body),
        raw_json_response(200, "application/json", probe_body),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.sync_login_context(login_sync_input(&server.base_url()));
    let before_epoch = core.session_epoch();

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("should get LoginRequired after strike + invalid probe");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(error, FireCoreError::LoginRequired { .. }));
    assert!(core.session_epoch() > before_epoch);
    let snapshot = core.snapshot();
    assert!(!snapshot.cookies.has_login_session());
    assert_eq!(requests.len(), 2);
    assert!(requests[1].contains("GET /session/current.json"));
}

#[tokio::test]
async fn strike_system_resets_on_valid_probe() {
    let not_logged_in_body =
        r#"{"errors":["需要登录才能执行此操作。"],"error_type":"not_logged_in"}"#;
    let probe_body = r#"{"current_user":{"username":"alice"}}"#;
    let responses = vec![
        raw_json_response(403, "application/json", not_logged_in_body),
        raw_json_response(200, "application/json", probe_body),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.sync_login_context(login_sync_input(&server.base_url()));

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("should still return LoginRequired even though probe is valid");
    let _ = server.shutdown_with_requests().await;

    assert!(matches!(error, FireCoreError::LoginRequired { .. }));
    let snapshot = core.snapshot();
    assert!(snapshot.cookies.has_login_session());
}

#[tokio::test]
async fn strike_system_accumulates_weak_signals_before_probing() {
    let logged_out_200_body = common::sample_latest_json();
    let response1 = format!(
        "HTTP/1.1 200 TEST\r\nContent-Type: application/json\r\nContent-Length: {}\r\nDiscourse-Logged-Out: 1\r\nConnection: close\r\n\r\n{logged_out_200_body}",
        logged_out_200_body.len()
    );
    let not_logged_in_body =
        r#"{"errors":["需要登录才能执行此操作。"],"error_type":"not_logged_in"}"#;
    let probe_body = r#"{"current_user":{"username":"alice"}}"#;
    let responses = vec![
        response1,
        raw_json_response(403, "application/json", not_logged_in_body),
        raw_json_response(200, "application/json", probe_body),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.sync_login_context(login_sync_input(&server.base_url()));

    let _ = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await;

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("second request should trigger strike + probe");
    let _ = server.shutdown_with_requests().await;

    assert!(matches!(error, FireCoreError::LoginRequired { .. }));
}
