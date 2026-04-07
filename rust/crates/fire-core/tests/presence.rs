mod common;

use std::time::Duration;

use common::{raw_json_response, TestServer};
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{
    BootstrapArtifacts, CookieSnapshot, MessageBusClientMode, MessageBusEventKind,
    MessageBusSubscription, MessageBusSubscriptionScope,
};
use tokio::{sync::mpsc::unbounded_channel, time::timeout};

#[tokio::test]
async fn bootstrap_topic_reply_presence_updates_state_and_poll_checkpoint() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"{
  "/discourse-presence/reply/123": {
    "users": [
      {
        "id": 2,
        "username": "bob",
        "avatar_template": "/user_avatar/linux.do/bob/{size}/1_2.png"
      }
    ],
    "message_id": 1000
  }
}"#,
        ),
        raw_json_response(200, "application/json", "[]"),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let presence = core
        .bootstrap_topic_reply_presence(123, "presence-bootstrap-owner".into())
        .await
        .expect("bootstrap topic reply presence");
    assert_eq!(presence.topic_id, 123);
    assert_eq!(presence.message_id, 1000);
    assert_eq!(presence.users.len(), 1);
    assert_eq!(presence.users[0].username, "bob");

    let (sender, _receiver) = unbounded_channel();
    core.start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");
    tokio::time::sleep(Duration::from_millis(50)).await;
    core.stop_message_bus(true);

    let requests = server.shutdown_with_requests().await;
    assert!(requests[0]
        .contains("GET /presence/get?channels%5B%5D=%2Fdiscourse-presence%2Freply%2F123"));
    assert!(requests[1].contains("POST /message-bus/"));
    assert!(requests[1].contains("%2Fpresence%2Fdiscourse-presence%2Freply%2F123=1000"));
}

#[tokio::test]
async fn message_bus_presence_reactions_and_alerts_emit_expected_event_kinds() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"[
  {
    "channel": "/topic/123/reactions",
    "message_id": 12,
    "data": { "post_id": 9001 }
  },
  {
    "channel": "/presence/discourse-presence/reply/123",
    "message_id": 13,
    "data": {
      "entering_users": [
        {
          "id": 2,
          "username": "bob",
          "avatar_template": "/user_avatar/linux.do/bob/{size}/1_2.png"
        }
      ]
    }
  },
  {
    "channel": "/notification-alert/1",
    "message_id": 14,
    "data": { "topic_title": "Alert topic" }
  }
]"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "reaction-owner".into(),
        channel: "/topic/123/reactions".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe reactions");
    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "presence-owner".into(),
        channel: "/presence/discourse-presence/reply/123".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe presence");
    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "alert-owner".into(),
        channel: "/notification-alert/1".into(),
        last_message_id: Some(-1),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe alert");

    let (sender, mut receiver) = unbounded_channel();
    core.start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");

    let reactions = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("reaction event timeout")
        .expect("reaction event missing");
    let presence = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("presence event timeout")
        .expect("presence event missing");
    let alert = timeout(Duration::from_secs(2), receiver.recv())
        .await
        .expect("alert event timeout")
        .expect("alert event missing");

    assert_eq!(reactions.kind, MessageBusEventKind::TopicReaction);
    assert_eq!(reactions.topic_id, Some(123));

    assert_eq!(presence.kind, MessageBusEventKind::Presence);
    assert_eq!(presence.topic_id, Some(123));

    assert_eq!(alert.kind, MessageBusEventKind::NotificationAlert);
    assert_eq!(alert.notification_user_id, Some(1));

    let merged_presence = core.topic_reply_presence_state(123);
    assert_eq!(merged_presence.message_id, 13);
    assert_eq!(merged_presence.users.len(), 1);
    assert_eq!(merged_presence.users[0].username, "bob");

    core.stop_message_bus(true);
    let _ = server.shutdown().await;
}

#[tokio::test]
async fn update_topic_reply_presence_reuses_active_message_bus_client_id() {
    let app_server = TestServer::spawn(vec![
        raw_json_response(200, "application/json", "{}"),
        raw_json_response(200, "application/json", "{}"),
    ])
    .await
    .expect("app server");
    let poll_server = TestServer::spawn(vec![raw_json_response(200, "application/json", "[]")])
        .await
        .expect("poll server");
    let core = authenticated_core(&app_server.base_url());
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: app_server.base_url(),
        current_username: Some("alice".into()),
        shared_session_key: Some("shared-session".into()),
        long_polling_base_url: Some(poll_server.base_url()),
        topic_tracking_state_meta: Some(r#"{"/latest":-1}"#.to_string()),
        ..BootstrapArtifacts::default()
    });

    let (sender, _receiver) = unbounded_channel();
    let client_id = core
        .start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");
    tokio::time::sleep(Duration::from_millis(50)).await;

    core.update_topic_reply_presence(123, true)
        .await
        .expect("enter presence");
    core.update_topic_reply_presence(123, false)
        .await
        .expect("leave presence");
    core.stop_message_bus(true);

    let poll_requests = poll_server.shutdown_with_requests().await;
    let app_requests = app_server.shutdown_with_requests().await;
    assert!(poll_requests
        .iter()
        .any(|request| request.contains(&format!("POST /message-bus/{client_id}/poll"))));
    assert!(app_requests
        .iter()
        .any(|request| request
            .contains("present_channels%5B%5D=%2Fdiscourse-presence%2Freply%2F123")));
    assert!(app_requests.iter().any(
        |request| request.contains("leave_channels%5B%5D=%2Fdiscourse-presence%2Freply%2F123")
    ));
    assert!(app_requests
        .iter()
        .filter(|request| request.contains("POST /presence/update"))
        .all(|request| request.contains(&format!("client_id={client_id}"))));
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
    let _ = core.apply_bootstrap(BootstrapArtifacts {
        base_url: base_url.to_string(),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        shared_session_key: Some("shared-session".into()),
        notification_channel_position: Some(42),
        ..BootstrapArtifacts::default()
    });
    core
}
