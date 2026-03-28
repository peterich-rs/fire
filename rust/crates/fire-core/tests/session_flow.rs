mod common;

use common::{sample_home_html, temp_session_file, temp_workspace_dir};
use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{LoginPhase, LoginSyncInput, PlatformCookie};

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
    assert_eq!(
        snapshot.bootstrap.long_polling_base_url.as_deref(),
        Some("https://linux.do")
    );
    assert_eq!(
        snapshot.bootstrap.turnstile_sitekey.as_deref(),
        Some("turnstile-key")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
}

#[test]
fn sync_login_context_merges_platform_cookies_and_html() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let snapshot = core.sync_login_context(LoginSyncInput {
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

#[test]
fn session_can_roundtrip_through_json_export_and_restore() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let expected = core.sync_login_context(LoginSyncInput {
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

    let json = core.export_session_json().expect("export");
    let restored_core = FireCore::new(FireCoreConfig::default()).expect("core");
    let restored = restored_core.restore_session_json(json).expect("restore");

    assert_eq!(restored, expected);
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
      "long_polling_base_url": "https://linux.do",
      "turnstile_sitekey": "sitekey",
      "topic_tracking_state_meta": "{\"message_bus_last_id\":42}",
      "preloaded_json": "{\"currentUser\":{\"username\":\"alice\"}}",
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
    assert!(!restored.bootstrap.has_preloaded_data);
}

#[test]
fn session_can_roundtrip_through_file_persistence() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let expected = core.sync_login_context(LoginSyncInput {
        username: Some("alice".into()),
        home_html: Some(sample_home_html()),
        csrf_token: Some("csrf-token".into()),
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
