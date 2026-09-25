use std::sync::Arc;

use http::header::{HeaderMap, COOKIE, USER_AGENT};
use http::{Method, Request};
use openwire::{CallOptions, RequestBody};

use super::super::{FireCore, MESSAGE_BUS_CALL_TIMEOUT};
use super::challenge::extract_turnstile_sitekey;
use super::client::FireCommonProfileHeaderContext;
use super::constants::MISSING_CSRF_TOKEN_PLACEHOLDER;
use super::headers::apply_common_profile_headers;
use super::profile::call_options_for_profile;
use super::traced::clone_request_for_retry;
use super::*;
use crate::diagnostics::FireDiagnosticsStore;

#[test]
fn default_api_profile_uses_client_defaults() {
    assert_eq!(
        call_options_for_profile(FireCallProfile::DefaultApi),
        CallOptions::default()
    );
}

#[test]
fn message_bus_profile_only_overrides_call_timeout() {
    assert_eq!(
        call_options_for_profile(FireCallProfile::MessageBusPoll),
        CallOptions::default().call_timeout(MESSAGE_BUS_CALL_TIMEOUT)
    );
}

#[test]
fn build_form_request_sends_undefined_csrf_when_token_missing() {
    let core = FireCore::new(crate::FireCoreConfig {
        base_url: "https://example.com".into(),
        workspace_path: None,
    })
    .expect("core");

    let traced = core
        .build_form_request(
            "test write",
            Method::POST,
            "/posts.json",
            vec![("raw", "hello".into())],
            true,
        )
        .expect("build form request without cached csrf");
    let csrf_header = traced
        .request
        .headers()
        .get("X-CSRF-Token")
        .and_then(|value| value.to_str().ok());
    assert_eq!(csrf_header, Some(MISSING_CSRF_TOKEN_PLACEHOLDER));
}

#[test]
fn build_form_request_uses_cached_csrf_when_present() {
    let core = FireCore::new(crate::FireCoreConfig {
        base_url: "https://example.com".into(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.apply_cookies(fire_models::CookieSnapshot {
        csrf_token: Some("real-csrf".into()),
        last_challenged_cf_clearance: None,
        ..fire_models::CookieSnapshot::default()
    });

    let traced = core
        .build_form_request(
            "test write",
            Method::POST,
            "/posts.json",
            vec![("raw", "hello".into())],
            true,
        )
        .expect("build form request with cached csrf");
    let csrf_header = traced
        .request
        .headers()
        .get("X-CSRF-Token")
        .and_then(|value| value.to_str().ok());
    assert_eq!(csrf_header, Some("real-csrf"));
}

#[test]
fn json_api_profile_can_skip_cached_csrf_header() {
    let mut headers = HeaderMap::new();
    apply_common_profile_headers(
        &mut headers,
        FireCommonProfileHeaderContext {
            profile: FireRequestProfile::JsonApi,
            origin: "https://linux.do",
            referer: "https://linux.do/",
            same_origin: false,
            user_agent: "test-agent",
            has_login_session: true,
            csrf_token: Some("real-csrf"),
            skip_csrf_header: true,
        },
    );

    assert!(headers.get("X-CSRF-Token").is_none());
    assert_eq!(
        headers
            .get("Sec-Fetch-Site")
            .and_then(|value| value.to_str().ok()),
        Some("cross-site")
    );
    assert_eq!(
        headers
            .get("Discourse-Logged-In")
            .and_then(|value| value.to_str().ok()),
        Some("true")
    );
}

#[test]
fn clone_request_for_retry_does_not_create_a_second_trace_until_replayed() {
    let diagnostics = Arc::new(FireDiagnosticsStore::new());
    let mut request = Request::builder()
        .method(Method::GET)
        .uri("https://example.com/latest.json")
        .header("Cookie", "cf_clearance=stale")
        .header("User-Agent", "stale-agent")
        .header("X-CSRF-Token", "stale-csrf")
        .header("Sec-Fetch-Site", "same-origin")
        .header("Discourse-Logged-In", "true")
        .header("Discourse-Track-View", "1")
        .body(RequestBody::empty())
        .expect("request");
    request.extensions_mut().insert(FireRequestProfile::JsonApi);
    request.extensions_mut().insert(FireRequestEpoch(7));
    let original_trace_id = diagnostics.prepare_request_trace("fetch topic list", &mut request);

    let retry_request = clone_request_for_retry(&request).expect("retry request");

    assert_eq!(diagnostics.summaries(10).len(), 1);
    assert_eq!(diagnostics.summaries(10)[0].id, original_trace_id);
    assert!(retry_request
        .extensions()
        .get::<crate::diagnostics::FireRequestTraceMetadata>()
        .is_none());
    assert!(
        retry_request.headers().get(COOKIE).is_none(),
        "retry clone must let the cookie jar rebuild Cookie from current session"
    );
    assert!(retry_request.headers().get(USER_AGENT).is_none());
    assert!(retry_request.headers().get("X-CSRF-Token").is_none());
    assert!(retry_request.headers().get("Sec-Fetch-Site").is_none());
    assert!(retry_request.headers().get("Discourse-Logged-In").is_none());
    assert_eq!(
        retry_request
            .headers()
            .get("Discourse-Track-View")
            .and_then(|value| value.to_str().ok()),
        Some("1")
    );
    assert!(matches!(
        retry_request
            .extensions()
            .get::<FireRequestProfile>()
            .copied(),
        Some(FireRequestProfile::JsonApi)
    ));
    assert!(matches!(
        retry_request
            .extensions()
            .get::<FireRequestEpoch>()
            .copied(),
        Some(FireRequestEpoch(7))
    ));
}

#[test]
fn extract_turnstile_sitekey_reads_data_sitekey_attribute() {
    let body = r#"<div class="cf-turnstile" data-sitekey="0x4AAAAAAAbcdefghijk"></div>"#;
    assert_eq!(
        extract_turnstile_sitekey(body).as_deref(),
        Some("0x4AAAAAAAbcdefghijk")
    );
}
