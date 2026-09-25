mod common;

use common::sample_home_html;
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{
    LoginFailureKind, PlatformCookie, WebViewLoginDecision, WebViewLoginJsResult, WebViewLoginPhase,
};

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

#[test]
fn classify_webview_login_session_success() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let decision = core.classify_webview_login_result(WebViewLoginJsResult {
        phase: WebViewLoginPhase::Session,
        status: 200,
        body: r#"{"user":{"username":"alice"}}"#.into(),
    });

    assert_eq!(decision, WebViewLoginDecision::Success);
}

#[test]
fn classify_webview_login_second_factor_required() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let decision = core.classify_webview_login_result(WebViewLoginJsResult {
        phase: WebViewLoginPhase::Session,
        status: 200,
        body: r#"{"reason":"second_factor","error":"需要验证码","totp_enabled":true,"security_key_enabled":false,"backup_enabled":true}"#.into(),
    });

    match decision {
        WebViewLoginDecision::NeedSecondFactor(requirement) => {
            assert!(requirement.totp_enabled);
            assert!(!requirement.security_key_enabled);
            assert!(requirement.backup_enabled);
            assert_eq!(requirement.message.as_deref(), Some("需要验证码"));
        }
        other => panic!("expected second factor, got {other:?}"),
    }
}

#[test]
fn classify_webview_login_known_failure_reason() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let decision = core.classify_webview_login_result(WebViewLoginJsResult {
        phase: WebViewLoginPhase::Session,
        status: 200,
        body: r#"{"reason":"invalid_credentials","error":"wrong"}"#.into(),
    });

    match decision {
        WebViewLoginDecision::Failure(failure) => {
            assert_eq!(failure.kind, LoginFailureKind::InvalidCredentials);
            assert_eq!(failure.message.as_deref(), Some("wrong"));
        }
        other => panic!("expected failure, got {other:?}"),
    }
}

#[test]
fn classify_webview_login_non_json_body_is_unknown_failure() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let decision = core.classify_webview_login_result(WebViewLoginJsResult {
        phase: WebViewLoginPhase::Session,
        status: 500,
        body: "not json".into(),
    });

    match decision {
        WebViewLoginDecision::Failure(failure) => {
            assert_eq!(failure.kind, LoginFailureKind::Unknown);
            assert_eq!(
                failure.message.as_deref(),
                Some("Discourse returned non-JSON: HTTP 500")
            );
        }
        other => panic!("expected failure, got {other:?}"),
    }
}

#[test]
fn classify_webview_login_csrf_challenge_requests_cloudflare_retry() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let decision = core.classify_webview_login_result(WebViewLoginJsResult {
        phase: WebViewLoginPhase::Csrf,
        status: 403,
        body: "Just a moment... cloudflare challenge-platform".into(),
    });

    assert_eq!(decision, WebViewLoginDecision::RetryCloudflare);
}

#[test]
fn classify_webview_login_csrf_plain_403_is_network_failure() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let decision = core.classify_webview_login_result(WebViewLoginJsResult {
        phase: WebViewLoginPhase::Csrf,
        status: 403,
        body: "Forbidden".into(),
    });

    match decision {
        WebViewLoginDecision::Failure(failure) => {
            assert_eq!(failure.kind, LoginFailureKind::Network);
            assert_eq!(failure.message.as_deref(), Some("Forbidden"));
        }
        other => panic!("expected failure, got {other:?}"),
    }
}

#[test]
fn classify_webview_login_csrf_plain_429_is_network_failure() {
    let core = FireCore::new(FireCoreConfig::default()).expect("core");

    let decision = core.classify_webview_login_result(WebViewLoginJsResult {
        phase: WebViewLoginPhase::Csrf,
        status: 429,
        body: "Too Many Requests".into(),
    });

    match decision {
        WebViewLoginDecision::Failure(failure) => {
            assert_eq!(failure.kind, LoginFailureKind::Network);
            assert_eq!(failure.message.as_deref(), Some("Too Many Requests"));
        }
        other => panic!("expected failure, got {other:?}"),
    }
}
