mod common;

use std::sync::atomic::Ordering;

use common::{
    raw_json_response, raw_text_response, sample_home_html, sample_latest_json,
    sample_topic_detail_json, TestServer,
};
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{
    LoginSyncInput, PlatformCookie, TopicDetailQuery, TopicListKind, TopicListQuery,
};

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
            page: None,
            topic_ids: Vec::new(),
            order: None,
            ascending: None,
        })
        .await
        .expect("topic list");
    let _ = server.shutdown().await;

    assert_eq!(response.topics.len(), 1);
    assert_eq!(response.topics[0].id, 123);
    assert_eq!(response.topics[0].title, "Fire topic");
    assert_eq!(response.users[0].username, "alice");
    assert_eq!(response.more_topics_url.as_deref(), Some("/latest?page=1"));
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
    assert_eq!(detail.post_stream.posts.len(), 1);
    assert_eq!(detail.post_stream.posts[0].username, "alice");
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
        cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "token".into(),
                domain: None,
                path: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "forum".into(),
                domain: None,
                path: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "clearance".into(),
                domain: None,
                path: None,
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
    let _ = server.shutdown().await;

    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
}
