mod common;

use std::time::Duration;

use common::{raw_json_response, TestServer};
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{BootstrapArtifacts, CookieSnapshot, MessageBusClientMode};
use tokio::{sync::mpsc::unbounded_channel, time::timeout};

#[tokio::test]
async fn fetch_recent_notifications_parses_payload_and_updates_state() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        &notification_page_json(
            &[
                notification_json(100, false, false, "Topic A"),
                notification_json(99, true, false, "Topic B"),
            ],
            2,
            Some(100),
            Some("/notifications?offset=60"),
        ),
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let page = core
        .fetch_recent_notifications(None)
        .await
        .expect("fetch recent notifications");
    let state = core.notification_state();
    let requests = server.shutdown_with_requests().await;

    assert_eq!(page.notifications.len(), 2);
    assert_eq!(page.notifications[0].id, 100);
    assert_eq!(page.total_rows_notifications, 2);
    assert_eq!(page.next_offset, Some(60));
    assert!(state.has_loaded_recent);
    assert_eq!(state.recent.len(), 2);
    assert_eq!(state.recent_seen_notification_id, Some(100));
    assert_eq!(state.recent[1].fancy_title.as_deref(), Some("Topic B"));

    let request = &requests[0];
    assert!(
        request.contains("GET /notifications?recent=true&limit=30&bump_last_seen_reviewable=true")
    );
}

#[tokio::test]
async fn fetch_notifications_reconciles_full_list_with_recent_list() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            &notification_page_json(
                &[notification_json(100, false, false, "Topic A")],
                1,
                Some(100),
                Some("/notifications?offset=60"),
            ),
        ),
        raw_json_response(
            200,
            "application/json",
            &notification_page_json(
                &[
                    notification_json(101, false, true, "Urgent Topic"),
                    notification_json(100, true, false, "Topic A"),
                ],
                2,
                Some(101),
                None,
            ),
        ),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let _ = core
        .fetch_notifications(None, None)
        .await
        .expect("fetch notifications");
    let _ = core
        .fetch_recent_notifications(None)
        .await
        .expect("fetch recent notifications");
    let state = core.notification_state();
    let _ = server.shutdown().await;

    assert!(state.has_loaded_full);
    assert!(state.has_loaded_recent);
    assert_eq!(state.full.len(), 2);
    assert_eq!(state.full[0].id, 101);
    assert_eq!(state.full[1].id, 100);
    assert!(state.full[1].read);
    assert_eq!(state.recent[0].id, 101);
    assert_eq!(state.recent[0].fancy_title.as_deref(), Some("Urgent Topic"));
}

#[tokio::test]
async fn fetch_recent_notifications_skips_malformed_items() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"{
  "notifications": [
    1,
    {"fancy_title": "missing id"},
    {
      "id": "100",
      "user_id": "1",
      "notification_type": "5",
      "read": "0",
      "high_priority": "1",
      "created_at": "2026-03-30T00:00:00Z",
      "topic_id": "200",
      "fancy_title": "Topic A",
      "data": {"topic_title": "Topic A"}
    }
  ],
  "total_rows_notifications": "1",
  "seen_notification_id": "100"
}"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let page = core
        .fetch_recent_notifications(None)
        .await
        .expect("fetch recent notifications");

    let _ = server.shutdown().await;
    assert_eq!(page.notifications.len(), 1);
    assert_eq!(page.notifications[0].id, 100);
    assert!(!page.notifications[0].read);
    assert!(page.notifications[0].high_priority);
    assert_eq!(page.total_rows_notifications, 1);
    assert_eq!(page.seen_notification_id, Some(100));
}

#[tokio::test]
async fn mark_notification_read_and_message_bus_merge_update_shared_state() {
    let app_server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            &notification_page_json(
                &[notification_json(10, false, true, "Existing Topic")],
                1,
                Some(10),
                None,
            ),
        ),
        raw_json_response(200, "application/json", "{}"),
    ])
    .await
    .expect("app server");
    let poll_server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            &format!(
                r#"[{{"channel":"/notification/1","message_id":43,"data":{{"all_unread_notifications_count":5,"unread_notifications":4,"unread_high_priority_notifications":2,"recent":[[10,true]],"last_notification":{{"notification":{}}}}}}}]"#,
                notification_json(11, false, true, "Live Topic"),
            ),
        ),
        raw_json_response(200, "application/json", "[]"),
    ])
    .await
    .expect("poll server");

    let core = authenticated_core(&app_server.base_url());
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: app_server.base_url(),
        shared_session_key: Some("shared-session".into()),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        notification_channel_position: Some(42),
        long_polling_base_url: Some(poll_server.base_url()),
        preloaded_json: Some(
            r#"{"currentUser":{"id":1,"username":"alice","all_unread_notifications_count":3,"unread_notifications":3,"unread_high_priority_notifications":1}}"#
                .to_string(),
        ),
        has_preloaded_data: true,
        ..BootstrapArtifacts::default()
    });

    let _ = core
        .fetch_recent_notifications(None)
        .await
        .expect("fetch recent notifications");

    let state = core
        .mark_notification_read(10)
        .await
        .expect("mark notification read");
    assert_eq!(state.counters.all_unread, 2);
    assert_eq!(state.counters.unread, 2);
    assert_eq!(state.counters.high_priority, 0);
    assert!(state.recent[0].read);

    let (sender, mut receiver) = unbounded_channel();
    let _client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");

    let _ = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("message bus event should arrive")
        .expect("message bus event should be present");
    let merged_state = core.notification_state();

    core.stop_message_bus(true);
    let app_requests = app_server.shutdown_with_requests().await;
    let poll_requests = poll_server.shutdown_with_requests().await;

    assert_eq!(merged_state.counters.all_unread, 5);
    assert_eq!(merged_state.counters.unread, 4);
    assert_eq!(merged_state.counters.high_priority, 2);
    assert_eq!(merged_state.recent.len(), 2);
    assert_eq!(merged_state.recent[0].id, 11);
    assert_eq!(merged_state.recent[1].id, 10);
    assert!(merged_state.recent[1].read);

    assert!(app_requests[0]
        .contains("GET /notifications?recent=true&limit=30&bump_last_seen_reviewable=true"));
    assert!(app_requests[1].contains("PUT /notifications/mark-read"));
    assert!(poll_requests[0]
        .to_ascii_lowercase()
        .contains("x-shared-session-key: shared-session"));
}

#[tokio::test]
async fn live_notification_merge_keeps_recent_cache_bounded_to_default_limit() {
    let default_recent_limit: u32 = 30; // Mirrors notifications::DEFAULT_RECENT_LIMIT.
    let initial_notifications = (1..=u64::from(default_recent_limit))
        .rev()
        .map(|id| notification_json(id, false, false, &format!("Topic {id}")))
        .collect::<Vec<_>>();
    let app_server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        &notification_page_json(
            &initial_notifications,
            default_recent_limit,
            Some(u64::from(default_recent_limit)),
            None,
        ),
    )])
    .await
    .expect("app server");
    let poll_server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            &format!(
                r#"[{{"channel":"/notification/1","message_id":43,"data":{{"all_unread_notifications_count":31,"unread_notifications":31,"unread_high_priority_notifications":0,"last_notification":{{"notification":{}}}}}}}]"#,
                notification_json(31, false, false, "Topic 31"),
            ),
        ),
        raw_json_response(200, "application/json", "[]"),
    ])
    .await
    .expect("poll server");

    let core = authenticated_core(&app_server.base_url());
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: app_server.base_url(),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        notification_channel_position: Some(42),
        shared_session_key: Some("shared-session".into()),
        long_polling_base_url: Some(poll_server.base_url()),
        ..BootstrapArtifacts::default()
    });

    let _ = core
        .fetch_recent_notifications(None)
        .await
        .expect("fetch recent notifications");
    assert_eq!(
        core.notification_state().recent.len(),
        default_recent_limit as usize
    );

    let (sender, mut receiver) = unbounded_channel();
    let _client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");

    let _ = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("message bus event should arrive")
        .expect("message bus event should be present");
    let merged_state = core.notification_state();

    core.stop_message_bus(true);
    let _ = app_server.shutdown().await;
    let _ = poll_server.shutdown().await;

    assert_eq!(merged_state.recent.len(), default_recent_limit as usize);
    assert_eq!(merged_state.recent[0].id, 31);
    assert_eq!(
        merged_state
            .recent
            .last()
            .map(|notification| notification.id),
        Some(2)
    );
}

#[tokio::test]
async fn logout_clears_notification_runtime_state() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        &notification_page_json(
            &[notification_json(100, false, false, "Topic A")],
            1,
            Some(100),
            None,
        ),
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: server.base_url(),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        preloaded_json: Some(
            r#"{"currentUser":{"id":1,"username":"alice","all_unread_notifications_count":2,"unread_notifications":2,"unread_high_priority_notifications":0}}"#
                .to_string(),
        ),
        has_preloaded_data: true,
        ..BootstrapArtifacts::default()
    });

    let _ = core
        .fetch_recent_notifications(None)
        .await
        .expect("fetch recent notifications");
    let before_logout = core.notification_state();
    assert_eq!(before_logout.recent.len(), 1);
    assert_eq!(before_logout.counters.unread, 2);

    let _ = core.logout_local(true);
    let after_logout = core.notification_state();
    let _ = server.shutdown().await;

    assert!(after_logout.recent.is_empty());
    assert!(after_logout.full.is_empty());
    assert!(!after_logout.has_loaded_recent);
    assert!(!after_logout.has_loaded_full);
    assert_eq!(after_logout.counters.all_unread, 0);
    assert_eq!(after_logout.counters.unread, 0);
    assert_eq!(after_logout.counters.high_priority, 0);
}

#[test]
fn notification_state_reads_counters_from_stringified_current_user_payload() {
    let core = authenticated_core("https://linux.do");
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: "https://linux.do".into(),
        current_username: Some("alice".into()),
        preloaded_json: Some(
            r#"{"currentUser":"{\"id\":1,\"username\":\"alice\",\"all_unread_notifications_count\":5,\"unread_notifications\":4,\"unread_high_priority_notifications\":2}"}"#
                .to_string(),
        ),
        has_preloaded_data: true,
        ..BootstrapArtifacts::default()
    });

    let state = core.notification_state();

    assert_eq!(state.counters.all_unread, 5);
    assert_eq!(state.counters.unread, 4);
    assert_eq!(state.counters.high_priority, 2);
}

fn authenticated_core(base_url: &str) -> FireCore {
    let core = FireCore::new(FireCoreConfig {
        base_url: base_url.to_string(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        csrf_token: Some("csrf-token".into()),
        ..CookieSnapshot::default()
    });
    core
}

fn notification_page_json(
    notifications: &[String],
    total_rows_notifications: u32,
    seen_notification_id: Option<u64>,
    load_more_notifications: Option<&str>,
) -> String {
    let seen_notification_id = seen_notification_id
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string());
    let load_more_notifications = load_more_notifications
        .map(|value| format!(r#""{value}""#))
        .unwrap_or_else(|| "null".to_string());
    format!(
        r#"{{
  "notifications": [{}],
  "total_rows_notifications": {total_rows_notifications},
  "seen_notification_id": {seen_notification_id},
  "load_more_notifications": {load_more_notifications}
}}"#,
        notifications.join(","),
    )
}

fn notification_json(id: u64, read: bool, high_priority: bool, title: &str) -> String {
    format!(
        r#"{{
  "id": {id},
  "user_id": 1,
  "notification_type": 5,
  "read": {read},
  "high_priority": {high_priority},
  "created_at": "2026-03-30T00:00:00Z",
  "post_number": 2,
  "topic_id": 200,
  "slug": "topic-{id}",
  "fancy_title": "{title}",
  "acting_user_avatar_template": "/user_avatar/linux.do/alice/{{size}}/1_2.png",
  "data": {{
    "display_username": "alice",
    "topic_title": "{title}",
    "excerpt": "hello"
  }}
}}"#,
    )
}
