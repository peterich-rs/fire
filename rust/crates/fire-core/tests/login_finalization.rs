mod common;

use fire_core::{FireCore, FireCoreConfig};
use fire_models::PlatformCookie;
use common::sample_home_html;

#[test]
fn finalize_login_from_webview_applies_scored_cookies_and_advances_epoch() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");
    let before_epoch = core.session_epoch();

    let result = core.finalize_login_from_webview(
        "alice".into(),
        None,
        None,
        None,
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
        ],
        true,
    );

    assert!(result.success);
    assert!(result.t_token_verified);
    assert!(core.session_epoch() > before_epoch);
    let snapshot = core.snapshot();
    assert!(snapshot.cookies.has_login_session());
}

#[test]
fn finalize_login_from_webview_verifies_t_token_consistency() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let result = core.finalize_login_from_webview(
        "alice".into(),
        Some("csrf-token".into()),
        Some(sample_home_html()),
        Some("TestBrowser/1.0".into()),
        vec![
            PlatformCookie {
                name: "_t".into(),
                value: "webview-token".into(),
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
        ],
        true,
    );

    assert!(result.success);
    assert!(result.t_token_verified);
    assert!(result.fingerprint_wait_needed);

    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.t_token.as_deref(), Some("webview-token"));
    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert_eq!(
        snapshot.browser_user_agent.as_deref(),
        Some("TestBrowser/1.0")
    );
}

#[test]
fn finalize_login_from_webview_returns_false_t_token_verified_when_jar_has_no_t() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let result = core.finalize_login_from_webview(
        "alice".into(),
        None,
        None,
        None,
        vec![PlatformCookie {
            name: "_t".into(),
            value: String::new(),
            domain: None,
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        }],
        true,
    );

    assert!(!result.success);
    assert!(!result.t_token_verified);
}

#[test]
fn finalize_login_from_webview_hydrates_from_preloaded_html() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let result = core.finalize_login_from_webview(
        "alice".into(),
        None,
        Some(sample_home_html()),
        None,
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
        ],
        true,
    );

    assert!(result.success);
    let snapshot = core.snapshot();
    assert_eq!(snapshot.cookies.csrf_token.as_deref(), Some("csrf-token"));
    assert!(snapshot.bootstrap.has_preloaded_data);
}

#[test]
fn finalize_login_from_webview_rejects_low_confidence_session_cookies_when_not_allowed() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let result = core.finalize_login_from_webview(
        String::new(),
        None,
        None,
        None,
        vec![
            PlatformCookie {
                name: "_t".into(),
                value: "low-conf-token".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "low-conf-forum".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
        false,
    );

    assert!(!result.success);
}
