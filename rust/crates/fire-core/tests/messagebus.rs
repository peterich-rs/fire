mod common;

use std::time::Duration;

use common::{raw_json_response, TestServer, TestServerStep};
use fire_core::{FireCore, FireCoreConfig, NetworkTraceOutcome};
use fire_models::{
    BootstrapArtifacts, CookieSnapshot, MessageBusClientMode, MessageBusEventKind,
    MessageBusSubscription, MessageBusSubscriptionScope,
};
use tokio::{sync::mpsc::unbounded_channel, time::timeout};

#[tokio::test]
async fn start_message_bus_polls_cross_origin_and_updates_checkpoints() {
    let app_server = TestServer::spawn(Vec::new()).await.expect("app server");
    let poll_server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"[{"channel":"/latest","message_id":6,"data":{"message_type":"latest","payload":{"topic_id":321}}}]|[{"channel":"/__status","message_id":0,"data":{"/latest":6,"/notification/1":42}}]"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"[{"channel":"/notification/1","message_id":43,"data":{"all_unread_notifications_count":3}}]"#,
        ),
        raw_json_response(200, "application/json", "[]"),
    ])
    .await
    .expect("poll server");

    let core = FireCore::new(FireCoreConfig {
        base_url: app_server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        ..CookieSnapshot::default()
    });
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: app_server.base_url(),
        shared_session_key: Some("shared-session".into()),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        notification_channel_position: Some(42),
        long_polling_base_url: Some(poll_server.base_url()),
        topic_tracking_state_meta: Some(r#"{"/latest":5}"#.to_string()),
        ..BootstrapArtifacts::default()
    });

    let (sender, mut receiver) = unbounded_channel();
    let client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");

    let event = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("event should arrive")
        .expect("event should be present");
    assert_eq!(event.kind, MessageBusEventKind::TopicList);
    assert_eq!(event.message_id, 6);
    assert_eq!(event.topic_id, Some(321));

    let notification_event = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("notification event should arrive")
        .expect("notification event should be present");
    assert_eq!(notification_event.kind, MessageBusEventKind::Notification);
    assert_eq!(notification_event.message_id, 43);

    core.stop_message_bus(true);

    let requests = poll_server.shutdown_with_requests().await;
    assert!(
        requests.len() >= 2,
        "expected at least two polls, got {requests:?}"
    );

    let first = requests[0].to_ascii_lowercase();
    assert!(first.contains(&format!("post /message-bus/{client_id}/poll")));
    assert!(first.contains("x-shared-session-key: shared-session"));
    assert!(first.contains("%2flatest=5"));
    assert!(first.contains("%2fnotification%2f1=42"));

    let second = requests[1].to_ascii_lowercase();
    assert!(second.contains("%2flatest=6"));
}

#[tokio::test]
async fn foreground_client_id_is_reused_and_ios_background_gets_temporary_id() {
    let server = TestServer::spawn(vec![
        raw_json_response(200, "application/json", "[]"),
        raw_json_response(200, "application/json", "[]"),
        raw_json_response(200, "application/json", "[]"),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        ..CookieSnapshot::default()
    });
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: server.base_url(),
        current_username: Some("alice".into()),
        topic_tracking_state_meta: Some(r#"{"/latest":-1}"#.to_string()),
        ..BootstrapArtifacts::default()
    });

    let (sender, _receiver) = unbounded_channel();
    let foreground_client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender.clone())
        .await
        .expect("start foreground");
    core.stop_message_bus(false);

    let restarted_foreground_client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender.clone())
        .await
        .expect("restart foreground");
    core.stop_message_bus(false);

    let background_client_id = core
        .start_message_bus(MessageBusClientMode::IosBackground, sender)
        .await
        .expect("start background");
    core.stop_message_bus(true);

    assert_eq!(foreground_client_id, restarted_foreground_client_id);
    assert!(background_client_id.starts_with("ios_bg_"));
    assert_ne!(foreground_client_id, background_client_id);
}

#[tokio::test]
async fn start_message_bus_without_subscriptions_waits_for_later_subscribe() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"[{"channel":"/topic/123","message_id":9,"data":{"type":"append","reload_topic":true}}]"#,
        ),
        raw_json_response(200, "application/json", "[]"),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let (sender, mut receiver) = unbounded_channel();
    let client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start idle message bus");

    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "test-topic-detail-owner".into(),
        channel: "/topic/123".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe topic detail");

    let event = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("topic detail event timeout")
        .expect("topic detail event missing");

    assert_eq!(event.kind, MessageBusEventKind::TopicDetail);
    assert_eq!(event.topic_id, Some(123));
    assert_eq!(event.message_id, 9);

    core.stop_message_bus(true);

    let requests = server.shutdown_with_requests().await;
    assert!(
        !requests.is_empty(),
        "expected a poll request after subscribe"
    );
    let first = requests[0].to_ascii_lowercase();
    assert!(first.contains(&format!("post /message-bus/{client_id}/poll")));
    assert!(first.contains("%2ftopic%2f123=-1"));
}

#[tokio::test]
async fn active_message_bus_coalesces_subscription_changes_into_single_restart() {
    let server = TestServer::spawn_scripted(vec![
        TestServerStep::delayed(
            raw_json_response(200, "application/json", "[]"),
            Duration::from_secs(1),
        ),
        TestServerStep::delayed(
            raw_json_response(200, "application/json", "[]"),
            Duration::from_secs(1),
        ),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        ..CookieSnapshot::default()
    });
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: server.base_url(),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        topic_tracking_state_meta: Some(r#"{"/latest":-1}"#.to_string()),
        ..BootstrapArtifacts::default()
    });

    let (sender, _receiver) = unbounded_channel();
    let client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");

    tokio::time::sleep(Duration::from_millis(50)).await;

    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "test-topic-detail-owner".into(),
        channel: "/topic/123".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe topic detail");
    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "test-topic-reaction-owner".into(),
        channel: "/topic/123/reactions".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe topic reactions");
    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "test-topic-presence-owner".into(),
        channel: "/presence/discourse-presence/reply/123".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe topic presence");

    tokio::time::sleep(Duration::from_millis(400)).await;
    core.stop_message_bus(true);
    tokio::time::sleep(Duration::from_millis(50)).await;

    let traces = core.list_network_traces(10);
    assert!(
        traces
            .iter()
            .filter(|trace| trace.operation == "message bus poll")
            .all(|trace| trace.outcome != NetworkTraceOutcome::InProgress),
        "expected restarted/stopped poll traces to reach a terminal state: {traces:?}"
    );
    assert!(
        traces
            .iter()
            .any(|trace| trace.outcome == NetworkTraceOutcome::Cancelled),
        "expected at least one cancelled message bus trace after restart: {traces:?}"
    );

    let requests = server.shutdown_with_requests().await;
    assert_eq!(
        requests.len(),
        2,
        "expected a single coalesced restart, got {requests:?}"
    );

    let first = requests[0].to_ascii_lowercase();
    assert!(first.contains(&format!("post /message-bus/{client_id}/poll")));
    assert!(first.contains("%2flatest=-1"));
    assert!(!first.contains("%2ftopic%2f123=-1"));

    let second = requests[1].to_ascii_lowercase();
    assert!(second.contains("%2flatest=-1"));
    assert!(second.contains("%2ftopic%2f123=-1"));
    assert!(second.contains("%2ftopic%2f123%2freactions=-1"));
    assert!(second.contains("%2fpresence%2fdiscourse-presence%2freply%2f123=-1"));
}

#[tokio::test]
async fn overlapping_subscription_owners_do_not_remove_shared_channel_until_last_owner_leaves() {
    let server = TestServer::spawn_scripted(vec![
        TestServerStep::delayed(
            raw_json_response(200, "application/json", "[]"),
            Duration::from_secs(1),
        ),
        TestServerStep::delayed(
            raw_json_response(200, "application/json", "[]"),
            Duration::from_secs(1),
        ),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let _ = core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        ..CookieSnapshot::default()
    });
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: server.base_url(),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        topic_tracking_state_meta: Some(r#"{"/latest":-1}"#.to_string()),
        ..BootstrapArtifacts::default()
    });

    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "owner-a".into(),
        channel: "/topic/123".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe owner a");

    let (sender, _receiver) = unbounded_channel();
    let client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");

    tokio::time::sleep(Duration::from_millis(50)).await;

    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "owner-b".into(),
        channel: "/topic/123".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe owner b");
    core.unsubscribe_message_bus_channel("owner-a".into(), "/topic/123".into())
        .expect("unsubscribe owner a");
    tokio::time::sleep(Duration::from_millis(250)).await;
    core.unsubscribe_message_bus_channel("owner-b".into(), "/topic/123".into())
        .expect("unsubscribe owner b");

    tokio::time::sleep(Duration::from_millis(250)).await;
    core.stop_message_bus(true);

    let requests = server.shutdown_with_requests().await;
    assert_eq!(
        requests.len(),
        2,
        "expected only the final owner removal to change poll inputs: {requests:?}"
    );

    let first = requests[0].to_ascii_lowercase();
    assert!(first.contains(&format!("post /message-bus/{client_id}/poll")));
    assert!(first.contains("%2flatest=-1"));
    assert!(first.contains("%2ftopic%2f123=-1"));

    let second = requests[1].to_ascii_lowercase();
    assert!(second.contains("%2flatest=-1"));
    assert!(!second.contains("%2ftopic%2f123=-1"));
}

#[tokio::test]
async fn poll_notification_alert_once_returns_alerts_and_checkpoint() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"[{"channel":"/notification-alert/1","message_id":14,"data":{"notification_type":2,"topic_id":123,"post_number":4,"topic_title":"Fire alert","excerpt":"New reply","username":"bob","post_url":"/t/fire/123/4"}}]|[{"channel":"/__status","message_id":0,"data":{"/notification-alert/1":16}}]"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let result = core
        .poll_notification_alert_once(10)
        .await
        .expect("poll notification alert");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(result.notification_user_id, 1);
    assert!(result.client_id.starts_with("ios_bg_"));
    assert_eq!(result.last_message_id, 16);
    assert_eq!(result.alerts.len(), 1);
    assert_eq!(result.alerts[0].message_id, 14);
    assert_eq!(result.alerts[0].notification_type, Some(2));
    assert_eq!(result.alerts[0].topic_id, Some(123));
    assert_eq!(result.alerts[0].post_number, Some(4));
    assert_eq!(result.alerts[0].topic_title.as_deref(), Some("Fire alert"));

    let request = requests[0].to_ascii_lowercase();
    assert!(request.contains(&format!("post /message-bus/{}/poll", result.client_id)));
    assert!(request.contains("%2fnotification-alert%2f1=10"));
    assert!(request.contains("discourse-background: true"));
}

#[tokio::test]
async fn message_bus_skips_malformed_items_without_dropping_valid_messages() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"[
  {"channel":"/topic/123","message_id":"9","data":{"type":"append","reload_topic":true}},
  {"channel":"/topic/123/reactions","message_id":null,"data":{"post_id":9001}},
  {"channel":"/presence/discourse-presence/reply/123","message_id":13,"data":{"users":[{"id":"2","username":"bob"}]}}
]"#,
        ),
        raw_json_response(200, "application/json", "[]"),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "topic-owner".into(),
        channel: "/topic/123".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe topic");
    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "presence-owner".into(),
        channel: "/presence/discourse-presence/reply/123".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe presence");

    let (sender, mut receiver) = unbounded_channel();
    core.start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");

    let topic_event = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("topic event timeout")
        .expect("topic event missing");
    let presence_event = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("presence event timeout")
        .expect("presence event missing");

    assert_eq!(topic_event.kind, MessageBusEventKind::TopicDetail);
    assert_eq!(topic_event.message_id, 9);
    assert_eq!(presence_event.kind, MessageBusEventKind::Presence);
    assert_eq!(presence_event.message_id, 13);

    let merged_presence = core.topic_reply_presence_state(123);
    assert_eq!(merged_presence.message_id, 13);
    assert_eq!(merged_presence.users.len(), 1);
    assert_eq!(merged_presence.users[0].username, "bob");

    core.stop_message_bus(true);
    let _ = server.shutdown().await;
}

#[tokio::test]
async fn poll_notification_alert_once_skips_malformed_items_and_accepts_string_checkpoints() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"[
  {"channel":"/notification-alert/1","message_id":null,"data":{"notification_type":2}},
  {"channel":"/notification-alert/1","message_id":"15","data":{"notification_type":2,"topic_id":123,"post_number":4,"topic_title":"Fire alert","excerpt":"New reply","username":"bob","post_url":"/t/fire/123/4"}},
  {"channel":"/__status","message_id":0,"data":{"/notification-alert/1":"16"}}
]"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let result = core
        .poll_notification_alert_once(10)
        .await
        .expect("poll notification alert");

    assert_eq!(result.last_message_id, 16);
    assert_eq!(result.alerts.len(), 1);
    assert_eq!(result.alerts[0].message_id, 15);
    assert_eq!(result.alerts[0].topic_id, Some(123));

    let _ = server.shutdown().await;
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
        ..CookieSnapshot::default()
    });
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: base_url.to_string(),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        ..BootstrapArtifacts::default()
    });
    core
}
