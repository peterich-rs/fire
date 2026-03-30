mod common;

use std::sync::atomic::Ordering;

use common::{raw_json_response, sample_home_html, TestServer};
use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{
    BootstrapArtifacts, CookieSnapshot, LoginSyncInput, MessageBusSubscription, PlatformCookie,
};
use serde_json::Value;

#[test]
fn message_bus_context_derives_default_client_id_and_bootstrap_subscriptions() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: None,
        current_url: Some("https://linux.do/".into()),
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
        ],
    });

    let context = core.message_bus_context(None).expect("message bus context");

    assert_eq!(context.client_id, "fire_linux.do_alice");
    assert_eq!(context.poll_base_url, "https://linux.do/");
    assert_eq!(
        context.poll_url,
        "https://linux.do/message-bus/fire_linux.do_alice/poll"
    );
    assert!(!context.requires_shared_session_key_header);
    assert_eq!(context.shared_session_key, "shared-session");
    assert_eq!(context.current_username.as_deref(), Some("alice"));
    assert_eq!(context.current_user_id, Some(1));
    assert_eq!(context.notification_channel_position, Some(7));
    assert_eq!(
        context.subscriptions,
        vec![
            MessageBusSubscription {
                channel: "/notification/1".into(),
                last_message_id: 7,
            },
            MessageBusSubscription {
                channel: "/topic/123".into(),
                last_message_id: 42,
            },
        ]
    );
}

#[test]
fn message_bus_context_prefers_custom_client_id_and_cross_origin_poll_base() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        ..CookieSnapshot::default()
    });
    core.apply_bootstrap(BootstrapArtifacts {
        shared_session_key: Some("shared".into()),
        current_username: Some("Alice Example".into()),
        current_user_id: Some(42),
        notification_channel_position: Some(11),
        long_polling_base_url: Some("https://poll.linux.do".into()),
        topic_tracking_state_meta: Some(r#"{"/topic/9":{"last_message_id":101}}"#.into()),
        ..BootstrapArtifacts::default()
    });

    let context = core
        .message_bus_context(Some("ios foreground/1".into()))
        .expect("message bus context");

    assert_eq!(context.client_id, "ios_foreground_1");
    assert_eq!(context.poll_base_url, "https://poll.linux.do/");
    assert_eq!(
        context.poll_url,
        "https://poll.linux.do/message-bus/ios_foreground_1/poll"
    );
    assert!(context.requires_shared_session_key_header);
    assert_eq!(
        context.subscriptions,
        vec![
            MessageBusSubscription {
                channel: "/notification/42".into(),
                last_message_id: 11,
            },
            MessageBusSubscription {
                channel: "/topic/9".into(),
                last_message_id: 101,
            },
        ]
    );
}

#[test]
fn message_bus_context_requires_shared_session_key() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        ..CookieSnapshot::default()
    });

    let error = core
        .message_bus_context(None)
        .expect_err("missing shared session key");
    assert!(matches!(error, FireCoreError::MissingSharedSessionKey));
}

#[test]
fn apply_message_bus_status_updates_updates_persisted_cursors_only() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    core.apply_bootstrap(BootstrapArtifacts {
        current_user_id: Some(1),
        notification_channel_position: Some(7),
        topic_tracking_state_meta: Some(r#"{"/topic/123":42}"#.into()),
        ..BootstrapArtifacts::default()
    });

    let snapshot = core.apply_message_bus_status_updates(vec![
        MessageBusSubscription {
            channel: "/notification/1".into(),
            last_message_id: 9,
        },
        MessageBusSubscription {
            channel: "/topic/123".into(),
            last_message_id: 50,
        },
        MessageBusSubscription {
            channel: "/latest".into(),
            last_message_id: 88,
        },
    ]);

    assert_eq!(snapshot.bootstrap.notification_channel_position, Some(9));
    let parsed = serde_json::from_str::<Value>(
        snapshot
            .bootstrap
            .topic_tracking_state_meta
            .as_deref()
            .expect("tracking meta"),
    )
    .expect("tracking json");
    assert_eq!(parsed.get("/topic/123").and_then(Value::as_i64), Some(50));
    assert_eq!(parsed.get("/latest"), None);
}

#[tokio::test]
async fn poll_message_bus_parses_segmented_response_and_applies_status_updates() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"[{"channel":"/topic/123","message_id":43,"data":{"type":"created"}}]|[{"channel":"/__status","message_id":44,"data":{"/topic/123":44,"/notification/1":"8","/latest":100}}]"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        ..CookieSnapshot::default()
    });
    core.apply_bootstrap(BootstrapArtifacts {
        shared_session_key: Some("shared".into()),
        current_username: Some("alice".into()),
        current_user_id: Some(1),
        notification_channel_position: Some(7),
        long_polling_base_url: Some(server.base_url()),
        topic_tracking_state_meta: Some(r#"{"/topic/123":42}"#.into()),
        ..BootstrapArtifacts::default()
    });

    let result = core
        .poll_message_bus(
            None,
            vec![MessageBusSubscription {
                channel: "/latest".into(),
                last_message_id: -1,
            }],
        )
        .await
        .expect("poll message bus");
    let requests = server.shutdown().await;

    assert_eq!(requests.load(Ordering::SeqCst), 1);
    assert_eq!(result.messages.len(), 2);
    assert_eq!(result.messages[0].channel, "/topic/123");
    assert_eq!(
        result.status_updates,
        vec![
            MessageBusSubscription {
                channel: "/latest".into(),
                last_message_id: 100,
            },
            MessageBusSubscription {
                channel: "/notification/1".into(),
                last_message_id: 8,
            },
            MessageBusSubscription {
                channel: "/topic/123".into(),
                last_message_id: 44,
            },
        ]
    );

    let snapshot = core.snapshot();
    assert_eq!(snapshot.bootstrap.notification_channel_position, Some(8));
    let parsed = serde_json::from_str::<Value>(
        snapshot
            .bootstrap
            .topic_tracking_state_meta
            .as_deref()
            .expect("tracking meta"),
    )
    .expect("tracking json");
    assert_eq!(parsed.get("/topic/123").and_then(Value::as_i64), Some(44));
    assert_eq!(parsed.get("/latest"), None);
}
