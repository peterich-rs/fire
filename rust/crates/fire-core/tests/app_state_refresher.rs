mod common;

use std::sync::{Arc, Mutex};
use std::time::Duration;

use common::{
    raw_json_response, raw_text_response, sample_home_html, sample_latest_json, TestServer,
};
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{
    HomeTopicListScope, PlatformCookie, RefreshBatch, RefreshTrigger, TopicListKind,
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
    ]
}

fn notification_page_json() -> String {
    r#"{
  "notifications": [
    {
      "id": 100,
      "user_id": 1,
      "notification_type": 5,
      "read": false,
      "high_priority": true,
      "created_at": "2026-03-30T00:00:00Z",
      "post_number": 2,
      "topic_id": 200,
      "slug": "topic-100",
      "fancy_title": "Notification title",
      "data": {
        "topic_title": "Notification title"
      }
    }
  ],
  "total_rows_notifications": 1,
  "seen_notification_id": 100,
  "load_more_notifications": null
}"#
    .to_string()
}

#[tokio::test]
async fn refresh_all_runs_core_immediately_and_secondary_after_delay() {
    let server = TestServer::spawn(vec![
        raw_text_response(200, &sample_home_html()),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", "{}"),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", &notification_page_json()),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.apply_platform_cookies(login_cookies());
    let events = Arc::new(Mutex::new(Vec::new()));
    let observer_events = events.clone();

    core.app_state_refresher()
        .refresh_all_with_handler(
            RefreshTrigger::LoginCompleted,
            Some(Arc::new(move |event| {
                observer_events
                    .lock()
                    .expect("observer events lock")
                    .push((event.batch, event.trigger));
            })),
        )
        .await
        .expect("refresh");

    assert_eq!(server.request_count(), 2);
    assert_eq!(
        events.lock().expect("events lock").as_slice(),
        &[(RefreshBatch::Core, RefreshTrigger::LoginCompleted)]
    );
    tokio::time::sleep(Duration::from_millis(900)).await;
    assert_eq!(server.request_count(), 2);
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(server.request_count(), 6);
    assert_eq!(
        events.lock().expect("events lock").as_slice(),
        &[
            (RefreshBatch::Core, RefreshTrigger::LoginCompleted),
            (RefreshBatch::Secondary, RefreshTrigger::LoginCompleted),
        ]
    );

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 6);
    assert!(requests[0].contains("GET / HTTP/1.1"));
    assert!(requests[1].contains("GET /latest.json HTTP/1.1"));
    assert!(requests[2].contains("GET /u/alice/summary.json HTTP/1.1"));
    assert!(requests[3].contains("GET /u/alice/bookmarks.json HTTP/1.1"));
    assert!(requests[4].contains("GET /read.json HTTP/1.1"));
    assert!(requests[5]
        .contains("GET /notifications?recent=true&limit=30&bump_last_seen_reviewable=true"));
}

#[tokio::test]
async fn refresh_all_debounces_repeated_auth_refreshes_within_two_seconds() {
    let server = TestServer::spawn(vec![
        raw_text_response(200, &sample_home_html()),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", "{}"),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", &notification_page_json()),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.apply_platform_cookies(login_cookies());

    core.app_state_refresher()
        .refresh_all(RefreshTrigger::LoginCompleted)
        .await
        .expect("first refresh");
    core.app_state_refresher()
        .refresh_all(RefreshTrigger::SessionRestored)
        .await
        .expect("second refresh");

    tokio::time::sleep(Duration::from_millis(1400)).await;
    assert_eq!(server.request_count(), 6);

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 6);
    assert_eq!(
        requests
            .iter()
            .filter(|request| request.contains("GET / HTTP/1.1"))
            .count(),
        1
    );
    assert_eq!(
        requests
            .iter()
            .filter(|request| request.contains("GET /latest.json HTTP/1.1"))
            .count(),
        1
    );
}

#[tokio::test]
async fn refresh_all_uses_rust_owned_current_home_topic_list_scope() {
    let server = TestServer::spawn(vec![
        raw_text_response(200, &sample_home_html()),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", "{}"),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_json_response(200, "application/json", &notification_page_json()),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.apply_platform_cookies(login_cookies());
    core.set_current_home_topic_list_scope(HomeTopicListScope {
        kind: TopicListKind::Top,
        category_id: Some(2),
        tags: vec!["swift".into(), "ios".into()],
    });

    core.app_state_refresher()
        .refresh_all(RefreshTrigger::SessionRestored)
        .await
        .expect("refresh");

    tokio::time::sleep(Duration::from_millis(1400)).await;

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 6);
    assert!(requests[1].contains("GET /c/rust/2/l/top.json"));
    assert!(requests[1].contains("tags%5B%5D=swift"));
    assert!(requests[1].contains("tags%5B%5D=ios"));
    assert!(requests[1].contains("match_all_tags=true"));
}
