mod common;

use common::{sample_home_html, temp_session_file, temp_workspace_dir};
use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{BootstrapArtifacts, CookieSnapshot, LoginPhase, LoginSyncInput, PlatformCookie};
use serde_json::Value;

#[test]
fn apply_home_html_extracts_bootstrap_and_readiness() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let snapshot = core.apply_home_html(sample_home_html());

    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert_eq!(
        snapshot.bootstrap.shared_session_key.as_deref(),
        Some("shared-session")
    );
    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert_eq!(snapshot.bootstrap.current_user_id, Some(1));
    assert_eq!(snapshot.bootstrap.notification_channel_position, Some(42));
    assert_eq!(
        snapshot.bootstrap.long_polling_base_url.as_deref(),
        Some("https://linux.do")
    );
    assert_eq!(
        snapshot.bootstrap.turnstile_sitekey.as_deref(),
        Some("turnstile-key")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
    assert_eq!(snapshot.bootstrap.categories.len(), 1);
    assert_eq!(snapshot.bootstrap.categories[0].name, "Rust");
    assert_eq!(
        snapshot.bootstrap.enabled_reaction_ids,
        vec!["heart", "clap", "tada"]
    );
    assert_eq!(snapshot.bootstrap.min_post_length, 20);
}

#[test]
fn sync_login_context_merges_platform_cookies_and_html() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let snapshot = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: None,
        current_url: Some("https://linux.do/".into()),
        browser_user_agent: None,
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

    assert_eq!(snapshot.login_phase(), LoginPhase::Ready);
    assert!(snapshot.readiness().can_write_authenticated_api);
    assert!(snapshot.readiness().can_open_message_bus);
}

#[tokio::test]
async fn refresh_bootstrap_if_needed_skips_for_unauthenticated_session() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let snapshot = core
        .refresh_bootstrap_if_needed()
        .await
        .expect("refresh should be skipped");

    assert_eq!(snapshot, core.snapshot());
    assert!(!snapshot.readiness().can_read_authenticated_api);
}

#[tokio::test]
async fn refresh_bootstrap_if_needed_skips_same_origin_session_without_shared_session_key() {
    let dormant_server = common::TestServer::spawn(Vec::new())
        .await
        .expect("dormant server");
    let core = FireCore::new(FireCoreConfig {
        base_url: dormant_server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        ..CookieSnapshot::default()
    });
    let expected = core.apply_bootstrap(BootstrapArtifacts {
        base_url: dormant_server.base_url(),
        current_username: Some("alice".into()),
        preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
        has_preloaded_data: true,
        ..BootstrapArtifacts::default()
    });

    let snapshot = core
        .refresh_bootstrap_if_needed()
        .await
        .expect("same-origin bootstrap refresh should be skipped");
    let _ = dormant_server.shutdown().await;

    assert_eq!(snapshot, expected);
    assert!(snapshot.readiness().can_open_message_bus);
}

#[tokio::test]
async fn refresh_bootstrap_if_needed_refreshes_when_cross_origin_shared_session_key_is_missing() {
    let poll_base_url = "https://poll.linux.do";
    let response_html = format!(
        r#"
<!doctype html>
<html>
  <head>
    <meta name="csrf-token" content="csrf-token">
    <meta name="shared_session_key" content="shared-session">
    <meta name="current-username" content="alice">
    <meta name="discourse-base-uri" content="/">
  </head>
  <body>
    <div id="data-discourse-setup" data-preloaded="{{&quot;currentUser&quot;:{{&quot;id&quot;:1,&quot;username&quot;:&quot;alice&quot;,&quot;notification_channel_position&quot;:42}},&quot;siteSettings&quot;:{{&quot;long_polling_base_url&quot;:&quot;{poll_base_url}&quot;}}}}"></div>
  </body>
</html>
"#
    );
    let app_server = common::TestServer::spawn(vec![common::raw_text_response(200, &response_html)])
        .await
        .expect("app server");
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
        long_polling_base_url: Some(poll_base_url.into()),
        preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
        has_preloaded_data: true,
        ..BootstrapArtifacts::default()
    });

    let snapshot = core
        .refresh_bootstrap_if_needed()
        .await
        .expect("cross-origin bootstrap refresh should run");
    let _ = app_server.shutdown().await;

    assert_eq!(
        snapshot.bootstrap.shared_session_key.as_deref(),
        Some("shared-session")
    );
    assert!(snapshot.readiness().can_open_message_bus);
}

#[tokio::test]
async fn refresh_csrf_token_if_needed_skips_when_token_exists() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: None,
        csrf_token: Some("csrf-token".into()),
        current_url: Some("https://linux.do/".into()),
        browser_user_agent: None,
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

    let snapshot = core
        .refresh_csrf_token_if_needed()
        .await
        .expect("refresh should be skipped");

    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert_eq!(snapshot, core.snapshot());
}

#[test]
fn session_can_roundtrip_through_json_export_and_restore() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let expected = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: None,
        current_url: Some("https://linux.do/".into()),
        browser_user_agent: None,
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

    let json = core.export_session_json().expect("export");
    let restored_core = FireCore::new(FireCoreConfig::default()).expect("core");
    let restored = restored_core.restore_session_json(json).expect("restore");

    assert_eq!(restored, expected);
}

#[test]
fn redacted_session_export_strips_auth_and_csrf_tokens() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some("https://linux.do/".into()),
        browser_user_agent: None,
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

    let json = core.export_redacted_session_json().expect("export");
    let value: Value = serde_json::from_str(&json).expect("json");

    assert_eq!(value["version"], 2);
    assert_eq!(value["auth_cookies_redacted"], true);
    assert_eq!(value["snapshot"]["cookies"]["t_token"], Value::Null);
    assert_eq!(value["snapshot"]["cookies"]["forum_session"], Value::Null);
    assert_eq!(value["snapshot"]["cookies"]["cf_clearance"], Value::Null);
    assert_eq!(value["snapshot"]["cookies"]["csrf_token"], Value::Null);
    assert_eq!(
        value["snapshot"]["bootstrap"]["current_username"],
        Value::String("alice".into())
    );
}

#[test]
fn restore_accepts_legacy_unversioned_ios_stub_session_json() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let json = r#"
{
  "cookies": {
    "tToken": "token",
    "forumSession": "forum",
    "cfClearance": "clearance",
    "csrfToken": "csrf-token"
  },
  "bootstrap": {
    "baseUrl": "https://linux.do/",
    "discourseBaseUri": "/",
    "sharedSessionKey": "shared-session",
    "currentUsername": "alice",
    "currentUserId": 1,
    "notificationChannelPosition": 42,
    "longPollingBaseUrl": "https://linux.do",
    "turnstileSitekey": "sitekey",
    "topicTrackingStateMeta": "{\"message_bus_last_id\":42}",
    "preloadedJson": "{\"currentUser\":{\"id\":1,\"username\":\"alice\",\"notification_channel_position\":42}}",
    "hasPreloadedData": true
  },
  "readiness": {
    "hasLoginCookie": true,
    "hasForumSession": true,
    "hasCloudflareClearance": true,
    "hasCsrfToken": true,
    "hasCurrentUser": true,
    "hasPreloadedData": true,
    "hasSharedSessionKey": true,
    "canReadAuthenticatedApi": true,
    "canWriteAuthenticatedApi": true,
    "canOpenMessageBus": true
  },
  "loginPhase": "ready",
  "hasLoginSession": true
}
"#;

    let restored = core
        .restore_session_json(json.to_string())
        .expect("restore");

    assert_eq!(restored.cookies.t_token.as_deref(), Some("token"));
    assert_eq!(restored.cookies.forum_session.as_deref(), Some("forum"));
    assert_eq!(restored.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(restored.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert_eq!(restored.bootstrap.base_url, "https://linux.do/");
    assert_eq!(
        restored.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert_eq!(restored.bootstrap.current_user_id, Some(1));
    assert_eq!(restored.bootstrap.notification_channel_position, Some(42));
    assert!(restored.bootstrap.has_preloaded_data);
    assert_eq!(restored.login_phase(), LoginPhase::Ready);
}

#[test]
fn restore_drops_incomplete_login_state_but_keeps_cf_clearance() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let json = r#"
{
  "version": 1,
  "saved_at_unix_ms": 1,
  "snapshot": {
    "cookies": {
      "t_token": "token",
      "forum_session": "",
      "cf_clearance": "clearance",
      "csrf_token": "csrf"
    },
    "bootstrap": {
      "base_url": "https://linux.do/",
      "discourse_base_uri": "/",
      "shared_session_key": "shared",
      "current_username": "alice",
      "current_user_id": 1,
      "notification_channel_position": 42,
      "long_polling_base_url": "https://linux.do",
      "turnstile_sitekey": "sitekey",
      "topic_tracking_state_meta": "{\"message_bus_last_id\":42}",
      "preloaded_json": "{\"currentUser\":{\"id\":1,\"username\":\"alice\",\"notification_channel_position\":42}}",
      "has_preloaded_data": true
    }
  }
}
"#;

    let restored = core
        .restore_session_json(json.to_string())
        .expect("restore");

    assert_eq!(restored.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(restored.cookies.t_token, None);
    assert_eq!(restored.cookies.csrf_token, None);
    assert_eq!(restored.bootstrap.current_username, None);
    assert_eq!(restored.bootstrap.current_user_id, None);
    assert_eq!(restored.bootstrap.notification_channel_position, None);
    assert!(!restored.bootstrap.has_preloaded_data);
}

#[test]
fn restore_preserves_bootstrap_when_auth_cookies_were_redacted() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let json = r#"
{
  "version": 2,
  "saved_at_unix_ms": 1,
  "auth_cookies_redacted": true,
  "snapshot": {
    "cookies": {
      "t_token": null,
      "forum_session": null,
      "cf_clearance": null,
      "csrf_token": null
    },
    "bootstrap": {
      "base_url": "https://linux.do/",
      "discourse_base_uri": "/",
      "shared_session_key": "shared",
      "current_username": "alice",
      "current_user_id": 1,
      "notification_channel_position": 42,
      "long_polling_base_url": "https://linux.do",
      "turnstile_sitekey": "sitekey",
      "topic_tracking_state_meta": "{\"message_bus_last_id\":42}",
      "preloaded_json": "{\"currentUser\":{\"id\":1,\"username\":\"alice\",\"notification_channel_position\":42}}",
      "has_preloaded_data": true
    }
  }
}
"#;

    let restored = core
        .restore_session_json(json.to_string())
        .expect("restore");

    assert_eq!(restored.cookies.t_token, None);
    assert_eq!(
        restored.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert_eq!(restored.bootstrap.current_user_id, Some(1));
    assert_eq!(
        restored.bootstrap.shared_session_key.as_deref(),
        Some("shared")
    );
    assert!(restored.bootstrap.has_preloaded_data);
    assert!(!restored.readiness().can_read_authenticated_api);

    let restored = core.apply_platform_cookies(vec![
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
    ]);

    assert!(restored.readiness().can_read_authenticated_api);
    assert!(restored.readiness().can_open_message_bus);
    assert_eq!(restored.login_phase(), LoginPhase::BootstrapCaptured);
}

#[test]
fn session_can_roundtrip_through_file_persistence() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let expected = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some("https://linux.do/".into()),
        browser_user_agent: None,
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

    let path = temp_session_file("session-roundtrip.json");
    core.save_session_to_path(&path).expect("save");

    let restored_core = FireCore::new(FireCoreConfig::default()).expect("core");
    let restored = restored_core.load_session_from_path(&path).expect("load");
    restored_core.clear_session_path(&path).expect("clear");

    assert_eq!(restored, expected);
    assert!(!path.exists());
}

#[test]
fn redacted_session_can_roundtrip_through_file_persistence() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let _ = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
        current_url: Some("https://linux.do/".into()),
        browser_user_agent: None,
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

    let path = temp_session_file("session-redacted-roundtrip.json");
    core.save_redacted_session_to_path(&path).expect("save");

    let restored_core = FireCore::new(FireCoreConfig::default()).expect("core");
    let restored = restored_core.load_session_from_path(&path).expect("load");
    restored_core.clear_session_path(&path).expect("clear");

    assert_eq!(restored.cookies.t_token, None);
    assert_eq!(restored.cookies.forum_session, None);
    assert_eq!(restored.cookies.cf_clearance, None);
    assert_eq!(restored.cookies.csrf_token, None);
    assert_eq!(
        restored.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(restored.bootstrap.has_preloaded_data);
    assert!(!path.exists());
}

#[test]
fn restore_rejects_base_url_mismatch() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let json = r#"
{
  "version": 1,
  "saved_at_unix_ms": 1,
  "snapshot": {
    "cookies": {
      "t_token": "token",
      "forum_session": "forum",
      "cf_clearance": null,
      "csrf_token": null
    },
    "bootstrap": {
      "base_url": "https://example.com/",
      "discourse_base_uri": null,
      "shared_session_key": null,
      "current_username": null,
      "long_polling_base_url": null,
      "turnstile_sitekey": null,
      "topic_tracking_state_meta": null,
      "preloaded_json": null,
      "has_preloaded_data": false
    }
  }
}
"#;

    match core.restore_session_json(json.to_string()) {
        Err(FireCoreError::PersistBaseUrlMismatch { .. }) => {}
        other => panic!("unexpected restore result: {other:?}"),
    }
}

#[test]
fn resolve_workspace_path_joins_relative_paths_under_root() {
    let workspace_path = temp_workspace_dir("workspace-root");
    let core = FireCore::new(FireCoreConfig {
        base_url: "https://linux.do".to_string(),
        workspace_path: Some(workspace_path.display().to_string()),
    })
    .expect("core");

    let resolved = core
        .resolve_workspace_path("logs/fire-current.xlog")
        .expect("resolved");

    assert_eq!(resolved, workspace_path.join("logs/fire-current.xlog"));
}

#[test]
fn resolve_workspace_path_rejects_parent_segments() {
    let workspace_path = temp_workspace_dir("workspace-root");
    let core = FireCore::new(FireCoreConfig {
        base_url: "https://linux.do".to_string(),
        workspace_path: Some(workspace_path.display().to_string()),
    })
    .expect("core");

    match core.resolve_workspace_path("../outside.log") {
        Err(FireCoreError::InvalidWorkspaceRelativePath { .. }) => {}
        other => panic!("unexpected resolve result: {other:?}"),
    }
}
