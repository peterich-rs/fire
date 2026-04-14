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
    "last_message_id": 1000
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
async fn bootstrap_topic_reply_presence_accepts_legacy_message_id_field() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"{
  "/discourse-presence/reply/123": {
    "users": [
      {
        "id": 2,
        "username": "bob"
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
    assert_eq!(presence.message_id, 1000);

    let (sender, _receiver) = unbounded_channel();
    core.start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");
    tokio::time::sleep(Duration::from_millis(50)).await;
    core.stop_message_bus(true);

    let requests = server.shutdown_with_requests().await;
    assert!(requests[1].contains("%2Fpresence%2Fdiscourse-presence%2Freply%2F123=1000"));
}

#[tokio::test]
async fn fetch_topic_reply_presence_treats_null_channel_as_empty_presence() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"{
  "/discourse-presence/reply/123": null
}"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let presence = core
        .fetch_topic_reply_presence(123)
        .await
        .expect("fetch topic reply presence");

    assert_eq!(presence.topic_id, 123);
    assert_eq!(presence.message_id, -1);
    assert!(presence.users.is_empty());
    assert_eq!(core.topic_reply_presence_state(123), presence);

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 1);
    assert!(requests[0]
        .contains("GET /presence/get?channels%5B%5D=%2Fdiscourse-presence%2Freply%2F123"));
}

#[tokio::test]
async fn fetch_topic_reply_presence_tolerates_nullable_message_ids_and_malformed_users() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"{
  "/discourse-presence/reply/123": {
    "users": [
      {
        "id": "2",
        "username": "bob",
        "avatar_template": "/user_avatar/linux.do/bob/{size}/1_2.png"
      },
      {
        "id": 0,
        "username": "nobody"
      },
      {
        "id": 3,
        "username": "   "
      },
      {
        "id": "oops",
        "username": "bad"
      }
    ],
    "last_message_id": null
  }
}"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let presence = core
        .fetch_topic_reply_presence(123)
        .await
        .expect("fetch topic reply presence");

    assert_eq!(presence.topic_id, 123);
    assert_eq!(presence.message_id, -1);
    assert_eq!(presence.users.len(), 1);
    assert_eq!(presence.users[0].id, 2);
    assert_eq!(presence.users[0].username, "bob");
    assert_eq!(
        presence.users[0].avatar_template.as_deref(),
        Some("/user_avatar/linux.do/bob/{size}/1_2.png")
    );
}

#[tokio::test]
async fn bootstrap_topic_reply_presence_accepts_string_last_message_id() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"{
  "/discourse-presence/reply/123": {
    "users": [
      {
        "id": 2,
        "username": "bob"
      }
    ],
    "last_message_id": "1000"
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
    assert_eq!(presence.message_id, 1000);

    let (sender, _receiver) = unbounded_channel();
    core.start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");
    tokio::time::sleep(Duration::from_millis(50)).await;
    core.stop_message_bus(true);

    let requests = server.shutdown_with_requests().await;
    assert!(requests[1].contains("%2Fpresence%2Fdiscourse-presence%2Freply%2F123=1000"));
}

#[tokio::test]
async fn unsubscribing_last_presence_owner_clears_cached_topic_snapshot() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"{
  "/discourse-presence/reply/123": {
    "users": [
      {
        "id": 2,
        "username": "bob"
      }
    ],
    "last_message_id": 1000
  }
}"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let presence = core
        .bootstrap_topic_reply_presence(123, "presence-owner-a".into())
        .await
        .expect("bootstrap topic reply presence");
    assert_eq!(presence.users.len(), 1);

    core.subscribe_message_bus_channel(MessageBusSubscription {
        owner_token: "presence-owner-b".into(),
        channel: "/presence/discourse-presence/reply/123".into(),
        last_message_id: Some(presence.message_id),
        scope: MessageBusSubscriptionScope::Transient,
    })
    .expect("subscribe second presence owner");

    core.unsubscribe_message_bus_channel(
        "presence-owner-a".into(),
        "/presence/discourse-presence/reply/123".into(),
    )
    .expect("unsubscribe first presence owner");
    let retained_presence = core.topic_reply_presence_state(123);
    assert_eq!(retained_presence.message_id, 1000);
    assert_eq!(retained_presence.users.len(), 1);

    core.unsubscribe_message_bus_channel(
        "presence-owner-b".into(),
        "/presence/discourse-presence/reply/123".into(),
    )
    .expect("unsubscribe last presence owner");
    let cleared_presence = core.topic_reply_presence_state(123);
    assert_eq!(cleared_presence.topic_id, 123);
    assert_eq!(cleared_presence.message_id, -1);
    assert!(cleared_presence.users.is_empty());

    let _ = server.shutdown().await;
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

#[tokio::test]
async fn update_topic_reply_presence_refreshes_csrf_when_missing() {
    let app_server = TestServer::spawn(vec![
        raw_json_response(200, "application/json", r#"{"csrf":"fresh-csrf"}"#),
        raw_json_response(200, "application/json", "{}"),
    ])
    .await
    .expect("app server");
    let poll_server = TestServer::spawn(vec![raw_json_response(200, "application/json", "[]")])
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
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        shared_session_key: Some("shared-session".into()),
        long_polling_base_url: Some(poll_server.base_url()),
        topic_tracking_state_meta: Some(r#"{"/latest":-1}"#.to_string()),
        ..BootstrapArtifacts::default()
    });

    let (sender, _receiver) = unbounded_channel();
    core.start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");
    tokio::time::sleep(Duration::from_millis(50)).await;

    core.update_topic_reply_presence(123, true)
        .await
        .expect("presence heartbeat");
    core.stop_message_bus(true);

    let _ = poll_server.shutdown().await;
    let app_requests = app_server.shutdown_with_requests().await;
    assert_eq!(app_requests.len(), 2);
    assert!(app_requests[0].contains("GET /session/csrf HTTP/1.1"));
    assert!(app_requests[1].contains("POST /presence/update HTTP/1.1"));
    assert!(app_requests[1]
        .to_ascii_lowercase()
        .contains("x-csrf-token: fresh-csrf"));
    assert_eq!(
        core.snapshot().cookies.csrf_token.as_deref(),
        Some("fresh-csrf")
    );
}

#[tokio::test]
async fn update_topic_reply_presence_throttles_duplicate_active_heartbeats() {
    let app_server = TestServer::spawn(vec![raw_json_response(200, "application/json", "{}")])
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
    core.start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");
    tokio::time::sleep(Duration::from_millis(50)).await;

    core.update_topic_reply_presence(123, true)
        .await
        .expect("first active heartbeat");
    core.update_topic_reply_presence(123, true)
        .await
        .expect("duplicate active heartbeat");
    core.stop_message_bus(true);

    let _ = poll_server.shutdown().await;
    let app_requests = app_server.shutdown_with_requests().await;
    assert_eq!(
        app_requests
            .iter()
            .filter(|request| request.contains("POST /presence/update"))
            .count(),
        1
    );
}

#[tokio::test]
async fn update_topic_reply_presence_uses_rate_limit_wait_seconds_for_cooldown() {
    let app_server = TestServer::spawn(vec![
        raw_json_response(
            429,
            "application/json",
            r#"{"errors":"You have performed this action too many times.","extras":{"wait_seconds":0.05}}"#,
        ),
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
    core.start_message_bus(MessageBusClientMode::Foreground, sender)
        .await
        .expect("start message bus");
    tokio::time::sleep(Duration::from_millis(50)).await;

    core.update_topic_reply_presence(123, true)
        .await
        .expect("rate-limited active heartbeat should be swallowed");
    core.update_topic_reply_presence(123, true)
        .await
        .expect("cooldown should suppress immediate retry");
    tokio::time::sleep(Duration::from_millis(70)).await;
    core.update_topic_reply_presence(123, true)
        .await
        .expect("post-cooldown active heartbeat");
    core.stop_message_bus(true);

    let _ = poll_server.shutdown().await;
    let app_requests = app_server.shutdown_with_requests().await;
    assert_eq!(
        app_requests
            .iter()
            .filter(|request| request.contains("POST /presence/update"))
            .count(),
        2
    );
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
