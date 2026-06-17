mod common;

use std::time::Duration;

use common::{raw_json_response, raw_text_response, sample_home_html, TestServer, TestServerStep};
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{
    BootstrapArtifacts, LoginStateDetermination, PlatformCookie, PreloadedDataState,
};

fn login_cookies() -> Vec<PlatformCookie> {
    vec![
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
    ]
}

#[tokio::test]
async fn preloaded_data_service_waits_for_single_in_flight_request() {
    let server = TestServer::spawn_scripted(vec![TestServerStep::delayed(
        raw_text_response(200, &sample_home_html()),
        Duration::from_millis(50),
    )])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let service_a = core.preloaded_data_service().clone();
    let service_b = core.preloaded_data_service().clone();

    let task_a = tokio::spawn(async move { service_a.ensure_loaded().await });
    tokio::time::sleep(Duration::from_millis(5)).await;
    let task_b = tokio::spawn(async move { service_b.ensure_loaded().await });

    assert_eq!(
        task_a.await.expect("task a").expect("load a"),
        PreloadedDataState::Ready
    );
    assert_eq!(
        task_b.await.expect("task b").expect("load b"),
        PreloadedDataState::Ready
    );

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET / HTTP/1.1"));
    assert_eq!(
        core.preloaded_data_service()
            .get_current_user()
            .as_ref()
            .map(|user| user.username.as_str()),
        Some("alice")
    );
}

#[tokio::test]
async fn determine_login_state_restores_cookie_only_session_without_startup_probe() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let snapshot = core.apply_platform_cookies(login_cookies());
    assert!(snapshot.readiness().can_read_authenticated_api);
    assert!(!snapshot.readiness().has_current_user);

    assert_eq!(
        core.determine_login_state(),
        LoginStateDetermination::LoggedIn {
            username: "会话已连接".into(),
            user_id: 0,
        }
    );
}

#[tokio::test]
async fn determine_login_state_with_probe_marks_invalid_session_and_clears_auth() {
    let server = TestServer::spawn(vec![raw_json_response(200, "application/json", "{}")])
        .await
        .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core.apply_platform_cookies(login_cookies());
    assert!(snapshot.cookies.has_login_session());
    assert!(!snapshot.readiness().has_current_user);

    let result = core.determine_login_state_with_probe().await;
    let requests = server.shutdown_with_requests().await;

    assert_eq!(result, LoginStateDetermination::SessionExpired);
    let snapshot = core.snapshot();
    assert!(!snapshot.cookies.has_login_session());
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /session/current.json"));
}

#[tokio::test]
async fn determine_login_state_with_probe_uses_probe_when_only_cookies_exist() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"{"current_user":{"username":"alice"}}"#,
    )])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core.apply_platform_cookies(login_cookies());
    assert!(snapshot.cookies.has_login_session());
    assert!(!snapshot.readiness().has_current_user);

    let result = core.determine_login_state_with_probe().await;
    let requests = server.shutdown_with_requests().await;

    assert_eq!(
        result,
        LoginStateDetermination::LoggedIn {
            username: "alice".into(),
            user_id: 0,
        }
    );
    assert_eq!(
        core.snapshot().bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /session/current.json"));
}

#[tokio::test]
async fn determine_login_state_with_probe_trusts_fresh_preloaded_current_user() {
    let server = TestServer::spawn(vec![raw_text_response(200, &sample_home_html())])
        .await
        .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core.apply_platform_cookies(login_cookies());
    assert!(snapshot.cookies.has_login_session());

    let preload_state = core
        .preloaded_data_service()
        .ensure_loaded()
        .await
        .expect("preload");
    assert_eq!(preload_state, PreloadedDataState::Ready);

    let result = core.determine_login_state_with_probe().await;
    let requests = server.shutdown_with_requests().await;

    assert_eq!(
        result,
        LoginStateDetermination::LoggedIn {
            username: "alice".into(),
            user_id: 1,
        }
    );
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET / HTTP/1.1"));
}

#[tokio::test]
async fn determine_login_state_with_probe_rejects_stale_persisted_current_user() {
    let server = TestServer::spawn(vec![raw_json_response(200, "application/json", "{}")])
        .await
        .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let snapshot = core.apply_platform_cookies(login_cookies());
    assert!(snapshot.cookies.has_login_session());
    let snapshot = core.apply_bootstrap(BootstrapArtifacts {
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        ..BootstrapArtifacts::default()
    });
    assert!(snapshot.readiness().has_current_user);

    let result = core.determine_login_state_with_probe().await;
    let requests = server.shutdown_with_requests().await;

    assert_eq!(result, LoginStateDetermination::SessionExpired);
    let snapshot = core.snapshot();
    assert!(!snapshot.cookies.has_login_session());
    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(snapshot.bootstrap.current_username, None);
    assert_eq!(requests.len(), 1);
    assert!(requests[0].contains("GET /session/current.json"));
}
