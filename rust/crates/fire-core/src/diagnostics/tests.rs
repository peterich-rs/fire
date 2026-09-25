use std::{env, fs, path::Path, sync::Arc};

use http::{Request, Response};
use openwire::{RequestBody, ResponseBody};
use serde_json::Value;

use super::{
    export_feedback_bundle, export_support_bundle, read_log_file_page, DiagnosticsPageDirection,
    FireDiagnosticsStore, FireSupportBundleHostContext, NetworkTraceOutcome,
};

#[test]
fn summaries_are_returned_in_reverse_creation_order() {
    let store = FireDiagnosticsStore::new();

    let mut first = Request::builder()
        .method("GET")
        .uri("https://linux.do/latest.json")
        .body(RequestBody::empty())
        .expect("request");
    let first_id = store.prepare_request_trace("first", &mut first);

    let mut second = Request::builder()
        .method("GET")
        .uri("https://linux.do/t/1.json")
        .body(RequestBody::empty())
        .expect("request");
    let second_id = store.prepare_request_trace("second", &mut second);

    let summaries = store.summaries(10);
    assert_eq!(summaries.len(), 2);
    assert_eq!(summaries[0].id, second_id);
    assert_eq!(summaries[1].id, first_id);
    assert_eq!(summaries[0].outcome, NetworkTraceOutcome::InProgress);
}

#[test]
fn response_body_preview_is_truncated_to_bounded_size() {
    let store = FireDiagnosticsStore::new();
    let mut request = Request::builder()
        .method("GET")
        .uri("https://linux.do/latest.json")
        .body(RequestBody::empty())
        .expect("request");
    let trace_id = store.prepare_request_trace("fetch", &mut request);
    let body = "a".repeat(super::MAX_RESPONSE_BODY_BYTES + 16);

    store.record_response_body_text(trace_id, &body, Some("application/json"));

    let detail = store.detail(trace_id).expect("detail");
    assert!(detail.response_body_truncated);
    assert!(detail.response_body_storage_truncated);
    assert!(detail.response_body_page_available);
    assert_eq!(
        detail.response_body.expect("body").len(),
        super::MAX_RESPONSE_BODY_INLINE_BYTES
    );
    assert_eq!(
        detail.response_body_stored_bytes,
        Some(super::MAX_RESPONSE_BODY_BYTES as u64)
    );

    let tail_page = store
        .network_trace_body_page(trace_id, None, 512, DiagnosticsPageDirection::Older)
        .expect("tail page");
    assert!(tail_page.page.is_tail_aligned);
    assert_eq!(
        tail_page.response_body_stored_bytes,
        Some(super::MAX_RESPONSE_BODY_BYTES as u64)
    );
    assert!(!tail_page.page.text.contains("<... truncated ...>"));
}

#[test]
fn response_body_end_marks_trace_as_succeeded_without_preview() {
    let store = FireDiagnosticsStore::new();
    let mut request = Request::builder()
        .method("GET")
        .uri("https://linux.do/session/csrf")
        .body(RequestBody::empty())
        .expect("request");
    let trace_id = store.prepare_request_trace("refresh csrf token", &mut request);

    store.record_response_body_bytes(trace_id, 97);

    let detail = store.detail(trace_id).expect("detail");
    assert_eq!(detail.outcome, NetworkTraceOutcome::Succeeded);
    assert_eq!(detail.response_body_bytes, Some(97));
    assert!(detail.finished_at_unix_ms.is_some());
    assert_eq!(detail.response_body, None);
}

#[test]
fn cancellation_guard_marks_in_progress_trace_as_cancelled() {
    let store = Arc::new(FireDiagnosticsStore::new());
    let mut request = Request::builder()
        .method("GET")
        .uri("https://linux.do/message-bus/1/poll")
        .body(RequestBody::empty())
        .expect("request");
    let trace_id = store.prepare_request_trace("message bus poll", &mut request);

    {
        let _guard = store.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped before the trace reached a terminal state",
        );
    }

    let detail = store.detail(trace_id).expect("detail");
    assert_eq!(detail.outcome, NetworkTraceOutcome::Cancelled);
    assert!(detail.finished_at_unix_ms.is_some());
    assert_eq!(detail.error_message, None);
    assert_eq!(detail.events.last().expect("event").phase, "cancelled");
}

#[test]
fn cancellation_guard_does_not_override_succeeded_trace() {
    let store = Arc::new(FireDiagnosticsStore::new());
    let mut request = Request::builder()
        .method("GET")
        .uri("https://linux.do/latest.json")
        .body(RequestBody::empty())
        .expect("request");
    let trace_id = store.prepare_request_trace("fetch", &mut request);

    {
        let _guard = store.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped before the trace reached a terminal state",
        );
        store.record_response_body_text(trace_id, "{\"ok\":true}", Some("application/json"));
    }

    let detail = store.detail(trace_id).expect("detail");
    assert_eq!(detail.outcome, NetworkTraceOutcome::Succeeded);
}

#[test]
fn failure_events_do_not_override_cancelled_trace() {
    let store = Arc::new(FireDiagnosticsStore::new());
    let mut request = Request::builder()
        .method("GET")
        .uri("https://linux.do/latest.json")
        .body(RequestBody::empty())
        .expect("request");
    let trace_id = store.prepare_request_trace("fetch", &mut request);

    {
        let _guard = store.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped before the trace reached a terminal state",
        );
    }
    store.record_parse_error(
        trace_id,
        "Failed to parse response".to_string(),
        "unexpected payload".to_string(),
    );

    let detail = store.detail(trace_id).expect("detail");
    assert_eq!(detail.outcome, NetworkTraceOutcome::Cancelled);
    assert_eq!(detail.events.last().expect("event").phase, "cancelled");
}

#[test]
fn network_trace_detail_only_inlines_first_body_preview_page() {
    let store = FireDiagnosticsStore::new();
    let mut request = Request::builder()
        .method("GET")
        .uri("https://linux.do/latest.json")
        .body(RequestBody::empty())
        .expect("request");
    let trace_id = store.prepare_request_trace("fetch", &mut request);
    let body = "abcd".repeat((super::MAX_RESPONSE_BODY_INLINE_BYTES / 4) + 256);

    store.record_response_body_text(trace_id, &body, Some("application/json"));

    let detail = store.detail(trace_id).expect("detail");
    let inline_preview = detail.response_body.expect("inline preview");
    assert_eq!(inline_preview.len(), super::MAX_RESPONSE_BODY_INLINE_BYTES);
    assert!(detail.response_body_page_available);
    assert_eq!(
        detail.response_body_stored_bytes,
        Some(body.len().min(super::MAX_RESPONSE_BODY_BYTES) as u64)
    );
    assert!(!detail.response_body_storage_truncated);

    let next_page = store
        .network_trace_body_page(
            trace_id,
            Some(inline_preview.len() as u64),
            super::MAX_RESPONSE_BODY_INLINE_BYTES,
            DiagnosticsPageDirection::Newer,
        )
        .expect("body page");
    assert_eq!(next_page.page.start_offset, inline_preview.len() as u64);
    assert_eq!(
        next_page.page.text,
        body[inline_preview.len()..next_page.page.end_offset as usize]
    );
}

#[test]
fn log_file_pages_default_to_tail_and_can_load_older_windows() {
    let workspace_dir = temp_workspace_dir("diagnostics-log-page-tail");
    let log_path = workspace_dir.join("diagnostics").join("tail.log");
    fs::create_dir_all(log_path.parent().expect("parent")).expect("log dir");
    fs::write(&log_path, "line-01\nline-02\nline-03\nline-04\nline-05\n").expect("log file");

    let latest_page = read_log_file_page(
        &workspace_dir,
        "diagnostics/tail.log",
        None,
        14,
        DiagnosticsPageDirection::Older,
    )
    .expect("latest page");

    assert!(latest_page.page.is_tail_aligned);
    assert!(latest_page.page.has_more_older);
    assert_eq!(latest_page.page.text, "line-04\nline-05\n");

    let older_page = read_log_file_page(
        &workspace_dir,
        "diagnostics/tail.log",
        Some(latest_page.page.start_offset),
        14,
        DiagnosticsPageDirection::Older,
    )
    .expect("older page");

    assert_eq!(older_page.page.text, "line-02\nline-03\n");
    assert!(older_page.page.has_more_older);
    assert!(older_page.page.has_more_newer);
}

#[test]
fn log_file_pages_respect_utf8_boundaries() {
    let workspace_dir = temp_workspace_dir("diagnostics-log-page-utf8");
    let log_path = workspace_dir.join("diagnostics").join("utf8.log");
    fs::create_dir_all(log_path.parent().expect("parent")).expect("log dir");
    fs::write(&log_path, "🙂🙂🙂").expect("log file");

    let latest_page = read_log_file_page(
        &workspace_dir,
        "diagnostics/utf8.log",
        None,
        5,
        DiagnosticsPageDirection::Older,
    )
    .expect("latest page");

    assert_eq!(latest_page.page.text, "🙂🙂🙂");
    assert_eq!(latest_page.page.text.chars().count(), 3);
    assert!(latest_page.page.is_tail_aligned);
}

#[test]
fn support_bundle_export_contains_recent_windows_and_skips_bundle_dir() {
    let workspace_dir = temp_workspace_dir("diagnostics-support-bundle");
    let diagnostics_dir = workspace_dir.join("diagnostics");
    let logs_dir = workspace_dir.join("logs");
    fs::create_dir_all(&diagnostics_dir).expect("diagnostics dir");
    fs::create_dir_all(&logs_dir).expect("logs dir");
    fs::create_dir_all(diagnostics_dir.join(super::SUPPORT_BUNDLE_DIR_NAME))
        .expect("support bundle dir");

    fs::write(
        diagnostics_dir.join("fire-readable.log"),
        "line-01\nline-02\nline-03\nline-04\n",
    )
    .expect("readable log");
    fs::write(
        diagnostics_dir
            .join(super::SUPPORT_BUNDLE_DIR_NAME)
            .join("old-export.json"),
        "{}",
    )
    .expect("old support bundle");

    let store = FireDiagnosticsStore::new();
    let mut request = Request::builder()
        .method("GET")
        .uri("https://linux.do/latest.json")
        .header("cookie", "session=secret")
        .body(RequestBody::empty())
        .expect("request");
    let trace_id = store.prepare_request_trace("fetch latest", &mut request);
    store.record_request_headers_snapshot(trace_id, &request, 1);

    let response = Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .header("set-cookie", "session=secret")
        .body(ResponseBody::empty())
        .expect("response");
    store.record_response_headers(trace_id, &response);
    store.record_response_body_text(trace_id, "{\"ok\":true}", Some("application/json"));

    let export = export_support_bundle(
        &workspace_dir,
        &store,
        r#"{"cookies":{"forum_session":"forum"}}"#,
        &FireSupportBundleHostContext {
            platform: "ios".to_string(),
            app_version: Some("1.0".to_string()),
            build_number: Some("100".to_string()),
            scene_phase: Some("active".to_string()),
        },
    )
    .expect("export support bundle");

    assert_eq!(
        Path::new(&export.absolute_path),
        workspace_dir.join(Path::new(&export.relative_path))
    );
    assert!(export
        .relative_path
        .starts_with("diagnostics/support-bundles/"));

    let payload: Value =
        serde_json::from_slice(&fs::read(&export.absolute_path).expect("support bundle file"))
            .expect("support bundle json");

    assert_eq!(payload["host"]["platform"], "ios");
    assert_eq!(
        payload["diagnostic_session_id"],
        export.diagnostic_session_id
    );
    assert_eq!(
        payload["logs"][0]["relative_path"],
        Value::String("diagnostics/fire-readable.log".to_string())
    );
    let request_headers = payload["network_traces"][0]["request_headers"]
        .as_array()
        .expect("request headers");
    let response_headers = payload["network_traces"][0]["response_headers"]
        .as_array()
        .expect("response headers");
    assert_eq!(
        request_headers
            .iter()
            .find(|header| header["name"] == "cookie")
            .expect("cookie header")["value"],
        "session=secret"
    );
    assert_eq!(
        response_headers
            .iter()
            .find(|header| header["name"] == "set-cookie")
            .expect("set-cookie header")["value"],
        "session=secret"
    );

    let listed_logs = super::list_log_files(&workspace_dir).expect("list logs");
    assert_eq!(
        listed_logs[0].relative_path,
        "diagnostics/fire-readable.log"
    );
    assert!(listed_logs.iter().all(|file| {
        !file
            .relative_path
            .starts_with("diagnostics/support-bundles/")
    }));
}

#[test]
fn feedback_bundle_export_redacts_session_and_sensitive_headers() {
    let workspace_dir = temp_workspace_dir("diagnostics-feedback-bundle");
    let diagnostics_dir = workspace_dir.join("diagnostics");
    fs::create_dir_all(&diagnostics_dir).expect("diagnostics dir");
    fs::write(
        diagnostics_dir.join("fire-readable.log"),
        "feedback-line-01\nfeedback-line-02\n",
    )
    .expect("readable log");

    let store = FireDiagnosticsStore::new();
    let mut request = Request::builder()
        .method("GET")
        .uri("https://linux.do/latest.json")
        .header("cookie", "session=secret")
        .header("x-csrf-token", "csrf-secret")
        .header("accept", "application/json")
        .body(RequestBody::empty())
        .expect("request");
    let trace_id = store.prepare_request_trace("fetch latest", &mut request);
    store.record_request_headers_snapshot(trace_id, &request, 1);

    let response = Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .header("set-cookie", "session=secret")
        .body(ResponseBody::empty())
        .expect("response");
    store.record_response_headers(trace_id, &response);
    store.record_response_body_text(trace_id, "{\"ok\":true}", Some("application/json"));

    let export = export_feedback_bundle(
        &workspace_dir,
        &store,
        r#"{"auth_cookies_redacted":true,"snapshot":{"username":"alice"}}"#,
        &FireSupportBundleHostContext {
            platform: "ios".to_string(),
            app_version: Some("1.0".to_string()),
            build_number: Some("100".to_string()),
            scene_phase: Some("active".to_string()),
        },
    )
    .expect("export feedback bundle");

    assert!(export
        .relative_path
        .starts_with("diagnostics/feedback-bundles/"));
    assert!(export.file_name.starts_with("fire-feedback-"));

    let payload: Value =
        serde_json::from_slice(&fs::read(&export.absolute_path).expect("feedback bundle file"))
            .expect("feedback bundle json");

    assert_eq!(payload["kind"], "feedback");
    assert_eq!(payload["session_redacted"], true);
    assert_eq!(payload["session"]["auth_cookies_redacted"], true);
    assert_eq!(payload["session"]["snapshot"]["username"], "alice");

    let request_headers = payload["network_traces"][0]["request_headers"]
        .as_array()
        .expect("request headers");
    let response_headers = payload["network_traces"][0]["response_headers"]
        .as_array()
        .expect("response headers");

    assert_eq!(
        request_headers
            .iter()
            .find(|header| header["name"] == "cookie")
            .expect("cookie header")["value"],
        "[redacted]"
    );
    assert_eq!(
        request_headers
            .iter()
            .find(|header| header["name"] == "x-csrf-token")
            .expect("csrf header")["value"],
        "[redacted]"
    );
    assert_eq!(
        request_headers
            .iter()
            .find(|header| header["name"] == "accept")
            .expect("accept header")["value"],
        "application/json"
    );
    assert_eq!(
        response_headers
            .iter()
            .find(|header| header["name"] == "set-cookie")
            .expect("set-cookie header")["value"],
        "[redacted]"
    );

    let listed_logs = super::list_log_files(&workspace_dir).expect("list logs");
    assert!(listed_logs.iter().all(|file| {
        !file
            .relative_path
            .starts_with("diagnostics/feedback-bundles/")
    }));
}

fn temp_workspace_dir(name: &str) -> std::path::PathBuf {
    let mut path = env::temp_dir();
    path.push(format!("fire-diagnostics-tests-{}", std::process::id()));
    path.push(name);
    let _ = fs::remove_dir_all(&path);
    fs::create_dir_all(&path).expect("temp workspace dir");
    path
}
