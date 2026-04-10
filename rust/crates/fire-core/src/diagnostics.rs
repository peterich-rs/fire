use std::{
    collections::{BTreeMap, VecDeque},
    fs,
    path::Path,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::{SystemTime, UNIX_EPOCH},
};

use http::{HeaderMap, Request, Response, Uri};
use mars_xlog::Xlog;
use mars_xlog_core::{
    compress::{decompress_raw_zlib, decompress_zstd_frames},
    protocol::{
        LogHeader, HEADER_LEN, MAGIC_ASYNC_NO_CRYPT_ZLIB_START, MAGIC_ASYNC_NO_CRYPT_ZSTD_START,
        MAGIC_ASYNC_ZLIB_START, MAGIC_ASYNC_ZSTD_START, MAGIC_END, MAGIC_SYNC_ZLIB_START,
        MAGIC_SYNC_ZSTD_START, TAILER_LEN,
    },
};
use openwire::{
    CallContext, ConnectionId, EventListener, EventListenerFactory, RequestBody, ResponseBody,
    WireError,
};
use serde_json::{json, Value};

use crate::{
    error::FireCoreError, session_store::write_atomic, workspace::validate_workspace_relative_path,
};

const MAX_NETWORK_TRACES: usize = 200;
const MAX_RESPONSE_BODY_BYTES: usize = 256 * 1024;
const MAX_RESPONSE_BODY_INLINE_BYTES: usize = 16 * 1024;
const MAX_LOG_CONTENT_BYTES: usize = 512 * 1024;
const DEFAULT_LOG_PAGE_BYTES: usize = 128 * 1024;
const DEFAULT_TRACE_BODY_PAGE_BYTES: usize = 32 * 1024;
const SUPPORT_BUNDLE_LOG_FILE_LIMIT: usize = 4;
const SUPPORT_BUNDLE_TRACE_LIMIT: usize = 20;
const SUPPORT_BUNDLE_LOG_PAGE_BYTES: usize = 96 * 1024;
const SUPPORT_BUNDLE_TRACE_BODY_BYTES: usize = 32 * 1024;
const SUPPORT_BUNDLE_DIR_NAME: &str = "support-bundles";
const REDACTED_HEADER_VALUE: &str = "<redacted>";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkTraceOutcome {
    InProgress,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiagnosticsPageDirection {
    Older,
    Newer,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiagnosticsTextPage {
    pub text: String,
    pub start_offset: u64,
    pub end_offset: u64,
    pub total_bytes: u64,
    pub next_cursor: Option<u64>,
    pub has_more_older: bool,
    pub has_more_newer: bool,
    pub is_head_aligned: bool,
    pub is_tail_aligned: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceHeader {
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceEvent {
    pub sequence: u32,
    pub timestamp_unix_ms: u64,
    pub phase: String,
    pub summary: String,
    pub details: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceSummary {
    pub id: u64,
    pub call_id: Option<u64>,
    pub operation: String,
    pub method: String,
    pub url: String,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub duration_ms: Option<u64>,
    pub outcome: NetworkTraceOutcome,
    pub status_code: Option<u16>,
    pub error_message: Option<String>,
    pub response_content_type: Option<String>,
    pub response_body_truncated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceDetail {
    pub id: u64,
    pub call_id: Option<u64>,
    pub operation: String,
    pub method: String,
    pub url: String,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub duration_ms: Option<u64>,
    pub outcome: NetworkTraceOutcome,
    pub status_code: Option<u16>,
    pub error_message: Option<String>,
    pub request_headers: Vec<NetworkTraceHeader>,
    pub response_headers: Vec<NetworkTraceHeader>,
    pub response_content_type: Option<String>,
    pub response_body: Option<String>,
    pub response_body_truncated: bool,
    pub response_body_storage_truncated: bool,
    pub response_body_stored_bytes: Option<u64>,
    pub response_body_page_available: bool,
    pub response_body_bytes: Option<u64>,
    pub events: Vec<NetworkTraceEvent>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireLogFileSummary {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireLogFileDetail {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub contents: String,
    pub is_truncated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireLogFilePage {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub page: DiagnosticsTextPage,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceBodyPage {
    pub trace_id: u64,
    pub response_content_type: Option<String>,
    pub response_body_storage_truncated: bool,
    pub response_body_stored_bytes: Option<u64>,
    pub page: DiagnosticsTextPage,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireSupportBundleHostContext {
    pub platform: String,
    pub app_version: Option<String>,
    pub build_number: Option<String>,
    pub scene_phase: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireSupportBundleExport {
    pub file_name: String,
    pub relative_path: String,
    pub absolute_path: String,
    pub size_bytes: u64,
    pub created_at_unix_ms: u64,
    pub diagnostic_session_id: String,
}

#[derive(Debug, Clone)]
pub(crate) struct FireRequestTraceMetadata {
    pub(crate) trace_id: u64,
    pub(crate) operation: String,
}

#[derive(Debug, Clone)]
struct NetworkTraceRecord {
    id: u64,
    call_id: Option<u64>,
    operation: String,
    method: String,
    url: String,
    started_at_unix_ms: u64,
    finished_at_unix_ms: Option<u64>,
    outcome: NetworkTraceOutcome,
    status_code: Option<u16>,
    error_message: Option<String>,
    request_headers: Vec<NetworkTraceHeader>,
    response_headers: Vec<NetworkTraceHeader>,
    response_content_type: Option<String>,
    response_body: Option<String>,
    response_body_storage_truncated: bool,
    response_body_bytes: Option<u64>,
    events: Vec<NetworkTraceEvent>,
}

impl NetworkTraceRecord {
    fn duration_ms(&self) -> Option<u64> {
        self.finished_at_unix_ms
            .map(|finished| finished.saturating_sub(self.started_at_unix_ms))
    }

    fn mark_succeeded(&mut self) {
        if !matches!(
            self.outcome,
            NetworkTraceOutcome::Failed | NetworkTraceOutcome::Cancelled
        ) {
            self.outcome = NetworkTraceOutcome::Succeeded;
            self.error_message = None;
        }
        if self.finished_at_unix_ms.is_none() {
            self.finished_at_unix_ms = Some(now_unix_ms());
        }
    }

    fn push_event(&mut self, phase: &str, summary: String, details: Option<String>) {
        let sequence = self.events.len() as u32 + 1;
        self.events.push(NetworkTraceEvent {
            sequence,
            timestamp_unix_ms: now_unix_ms(),
            phase: phase.to_string(),
            summary,
            details,
        });
    }

    fn to_summary(&self) -> NetworkTraceSummary {
        NetworkTraceSummary {
            id: self.id,
            call_id: self.call_id,
            operation: self.operation.clone(),
            method: self.method.clone(),
            url: self.url.clone(),
            started_at_unix_ms: self.started_at_unix_ms,
            finished_at_unix_ms: self.finished_at_unix_ms,
            duration_ms: self.duration_ms(),
            outcome: self.outcome,
            status_code: self.status_code,
            error_message: self.error_message.clone(),
            response_content_type: self.response_content_type.clone(),
            response_body_truncated: self.response_body_storage_truncated,
        }
    }

    fn to_detail(&self) -> NetworkTraceDetail {
        let response_body_page = self.response_body.as_deref().map(|body| {
            paginate_text(
                body,
                None,
                MAX_RESPONSE_BODY_INLINE_BYTES,
                DiagnosticsPageDirection::Newer,
            )
        });
        let response_body_page_available = response_body_page
            .as_ref()
            .is_some_and(|page| page.has_more_newer);
        let response_body_truncated =
            self.response_body_storage_truncated || response_body_page_available;

        NetworkTraceDetail {
            id: self.id,
            call_id: self.call_id,
            operation: self.operation.clone(),
            method: self.method.clone(),
            url: self.url.clone(),
            started_at_unix_ms: self.started_at_unix_ms,
            finished_at_unix_ms: self.finished_at_unix_ms,
            duration_ms: self.duration_ms(),
            outcome: self.outcome,
            status_code: self.status_code,
            error_message: self.error_message.clone(),
            request_headers: self.request_headers.clone(),
            response_headers: self.response_headers.clone(),
            response_content_type: self.response_content_type.clone(),
            response_body: response_body_page.as_ref().map(|page| page.text.clone()),
            response_body_truncated,
            response_body_storage_truncated: self.response_body_storage_truncated,
            response_body_stored_bytes: self.response_body.as_ref().map(|body| body.len() as u64),
            response_body_page_available,
            response_body_bytes: self.response_body_bytes,
            events: self.events.clone(),
        }
    }
}

#[derive(Default)]
struct FireDiagnosticsState {
    order: VecDeque<u64>,
    traces: BTreeMap<u64, NetworkTraceRecord>,
}

pub(crate) struct FireDiagnosticsStore {
    diagnostic_session_id: String,
    next_trace_id: AtomicU64,
    inner: Mutex<FireDiagnosticsState>,
}

pub(crate) struct FireNetworkTraceCancellationGuard {
    inner: Arc<FireNetworkTraceCancellationGuardInner>,
}

struct FireNetworkTraceCancellationGuardInner {
    diagnostics: Arc<FireDiagnosticsStore>,
    trace_id: u64,
    summary: String,
    details: String,
    armed: std::sync::atomic::AtomicBool,
}

impl Drop for FireNetworkTraceCancellationGuard {
    fn drop(&mut self) {
        if !self.inner.armed.swap(false, Ordering::AcqRel) {
            return;
        }

        self.inner.diagnostics.record_cancelled_if_in_progress(
            self.inner.trace_id,
            &self.inner.summary,
            Some(&self.inner.details),
        );
    }
}

impl Clone for FireNetworkTraceCancellationGuard {
    fn clone(&self) -> Self {
        Self {
            inner: Arc::clone(&self.inner),
        }
    }
}

impl Default for FireDiagnosticsStore {
    fn default() -> Self {
        Self::new()
    }
}

impl FireDiagnosticsStore {
    pub(crate) fn new() -> Self {
        Self {
            diagnostic_session_id: new_diagnostic_session_id(),
            next_trace_id: AtomicU64::new(1),
            inner: Mutex::new(FireDiagnosticsState::default()),
        }
    }

    pub(crate) fn diagnostic_session_id(&self) -> &str {
        &self.diagnostic_session_id
    }

    pub(crate) fn prepare_request_trace(
        &self,
        operation: &str,
        request: &mut Request<RequestBody>,
    ) -> u64 {
        let trace_id = self.next_trace_id.fetch_add(1, Ordering::Relaxed);
        let record = NetworkTraceRecord {
            id: trace_id,
            call_id: None,
            operation: operation.to_string(),
            method: request.method().to_string(),
            url: request.uri().to_string(),
            started_at_unix_ms: now_unix_ms(),
            finished_at_unix_ms: None,
            outcome: NetworkTraceOutcome::InProgress,
            status_code: None,
            error_message: None,
            request_headers: Vec::new(),
            response_headers: Vec::new(),
            response_content_type: None,
            response_body: None,
            response_body_storage_truncated: false,
            response_body_bytes: None,
            events: Vec::new(),
        };

        request.extensions_mut().insert(FireRequestTraceMetadata {
            trace_id,
            operation: operation.to_string(),
        });

        let mut state = self.inner.lock().expect("diagnostics store poisoned");
        state.order.push_back(trace_id);
        state.traces.insert(trace_id, record);
        trim_oldest_traces(&mut state);
        trace_id
    }

    pub(crate) fn summaries(&self, limit: usize) -> Vec<NetworkTraceSummary> {
        let state = self.inner.lock().expect("diagnostics store poisoned");
        state
            .order
            .iter()
            .rev()
            .filter_map(|trace_id| {
                state
                    .traces
                    .get(trace_id)
                    .map(NetworkTraceRecord::to_summary)
            })
            .take(limit)
            .collect()
    }

    pub(crate) fn detail(&self, trace_id: u64) -> Option<NetworkTraceDetail> {
        let state = self.inner.lock().expect("diagnostics store poisoned");
        state
            .traces
            .get(&trace_id)
            .map(NetworkTraceRecord::to_detail)
    }

    pub(crate) fn network_trace_body_page(
        &self,
        trace_id: u64,
        cursor: Option<u64>,
        max_bytes: usize,
        direction: DiagnosticsPageDirection,
    ) -> Option<NetworkTraceBodyPage> {
        let state = self.inner.lock().expect("diagnostics store poisoned");
        let trace = state.traces.get(&trace_id)?;
        let body = trace.response_body.as_deref()?;
        let page = paginate_text(
            body,
            cursor,
            normalized_page_bytes(max_bytes, DEFAULT_TRACE_BODY_PAGE_BYTES),
            direction,
        );
        Some(NetworkTraceBodyPage {
            trace_id,
            response_content_type: trace.response_content_type.clone(),
            response_body_storage_truncated: trace.response_body_storage_truncated,
            response_body_stored_bytes: Some(body.len() as u64),
            page,
        })
    }

    pub(crate) fn cancellation_guard(
        self: &Arc<Self>,
        trace_id: u64,
        summary: impl Into<String>,
        details: impl Into<String>,
    ) -> FireNetworkTraceCancellationGuard {
        FireNetworkTraceCancellationGuard {
            inner: Arc::new(FireNetworkTraceCancellationGuardInner {
                diagnostics: Arc::clone(self),
                trace_id,
                summary: summary.into(),
                details: details.into(),
                armed: std::sync::atomic::AtomicBool::new(true),
            }),
        }
    }

    pub(crate) fn record_call_start(&self, trace_id: u64, ctx: &CallContext) {
        self.with_trace(trace_id, |trace| {
            trace.call_id = Some(ctx.call_id().as_u64());
            trace.push_event(
                "call_start",
                format!("Call {} started", ctx.call_id().as_u64()),
                Some(format!("operation: {}", trace.operation)),
            );
        });
    }

    pub(crate) fn record_request_headers_snapshot(
        &self,
        trace_id: u64,
        request: &Request<RequestBody>,
        attempt: u32,
    ) {
        self.with_trace(trace_id, |trace| {
            trace.request_headers = sanitize_headers(request.headers());
            trace.push_event(
                "request_headers_snapshot",
                format!("Captured request headers for attempt {attempt}"),
                Some(format!("header_count: {}", trace.request_headers.len())),
            );
        });
    }

    pub(crate) fn record_call_end(&self, trace_id: u64, response: &Response<ResponseBody>) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "call_end",
                format!("Transport returned HTTP {}", response.status().as_u16()),
                Some("response body may still be in progress".to_string()),
            );
        });
    }

    pub(crate) fn record_call_failed(&self, trace_id: u64, error: &WireError) {
        self.record_failure(
            trace_id,
            "call_failed",
            "Call failed".to_string(),
            error.to_string(),
        );
    }

    pub(crate) fn record_call_failed_if_in_progress(&self, trace_id: u64, error: &WireError) {
        self.record_failure_if_in_progress(
            trace_id,
            "call_failed",
            "Call failed".to_string(),
            error.to_string(),
        );
    }

    pub(crate) fn record_response_headers(&self, trace_id: u64, response: &Response<ResponseBody>) {
        self.with_trace(trace_id, |trace| {
            trace.status_code = Some(response.status().as_u16());
            trace.response_headers = sanitize_headers(response.headers());
            trace.response_content_type = header_value(response.headers(), "content-type");
            trace.push_event(
                "response_headers",
                format!(
                    "Received response headers with HTTP {}",
                    response.status().as_u16()
                ),
                trace
                    .response_content_type
                    .clone()
                    .map(|value| format!("content-type: {value}")),
            );
        });
    }

    pub(crate) fn record_response_body_bytes(&self, trace_id: u64, bytes_read: u64) {
        self.with_trace(trace_id, |trace| {
            trace.response_body_bytes = Some(bytes_read);
            trace.mark_succeeded();
            trace.push_event(
                "response_body_end",
                format!("Read {bytes_read} response bytes"),
                None,
            );
        });
    }

    pub(crate) fn record_response_body_failed(&self, trace_id: u64, error: &WireError) {
        self.record_failure(
            trace_id,
            "response_body_failed",
            "Response body read failed".to_string(),
            error.to_string(),
        );
    }

    pub(crate) fn record_response_body_text(
        &self,
        trace_id: u64,
        body: &str,
        response_content_type: Option<&str>,
    ) {
        self.with_trace(trace_id, |trace| {
            let (stored, truncated) = truncate_text_prefix(body, MAX_RESPONSE_BODY_BYTES);
            trace.response_body = Some(stored);
            trace.response_body_storage_truncated = truncated;
            if let Some(content_type) = response_content_type {
                trace.response_content_type = Some(content_type.to_string());
            }
            trace.mark_succeeded();
            trace.push_event(
                "response_body_captured",
                if truncated {
                    "Stored truncated response body preview".to_string()
                } else {
                    "Stored response body".to_string()
                },
                None,
            );
        });
    }

    pub(crate) fn record_http_status_error(&self, trace_id: u64, status: u16, body: &str) {
        self.with_trace(trace_id, |trace| {
            if trace.outcome == NetworkTraceOutcome::Cancelled {
                return;
            }
            trace.outcome = NetworkTraceOutcome::Failed;
            trace.status_code = Some(status);
            trace.error_message = Some(format!("HTTP {status}"));
            trace.finished_at_unix_ms = Some(now_unix_ms());
            let (stored, truncated) = truncate_text_prefix(body, MAX_RESPONSE_BODY_BYTES);
            trace.response_body = Some(stored);
            trace.response_body_storage_truncated = truncated;
            trace.push_event(
                "http_error",
                format!("Request failed with HTTP {status}"),
                None,
            );
        });
    }

    pub(crate) fn record_parse_error(&self, trace_id: u64, summary: String, details: String) {
        self.record_failure(trace_id, "response_parse_failed", summary, details);
    }

    pub(crate) fn record_pool_lookup(
        &self,
        trace_id: u64,
        hit: bool,
        connection_id: Option<ConnectionId>,
    ) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "pool_lookup",
                if hit {
                    "Connection pool hit".to_string()
                } else {
                    "Connection pool miss".to_string()
                },
                connection_id.map(|value| format!("connection_id: {}", value.as_u64())),
            );
        });
    }

    pub(crate) fn record_connection_acquired(
        &self,
        trace_id: u64,
        connection_id: ConnectionId,
        reused: bool,
    ) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "connection_acquired",
                if reused {
                    format!("Reused connection {}", connection_id.as_u64())
                } else {
                    format!("Acquired new connection {}", connection_id.as_u64())
                },
                None,
            );
        });
    }

    pub(crate) fn record_connection_released(&self, trace_id: u64, connection_id: ConnectionId) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "connection_released",
                format!("Released connection {}", connection_id.as_u64()),
                None,
            );
        });
    }

    pub(crate) fn record_route_plan(
        &self,
        trace_id: u64,
        route_count: usize,
        fast_fallback_enabled: bool,
    ) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "route_plan",
                format!("Planned {route_count} route(s)"),
                Some(format!("fast_fallback_enabled: {fast_fallback_enabled}")),
            );
        });
    }

    pub(crate) fn record_connect_race_start(
        &self,
        trace_id: u64,
        race_id: u64,
        route_index: usize,
        route_count: usize,
        route_family: &str,
    ) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "connect_race_start",
                format!("Connect race {race_id} started"),
                Some(format!(
                    "route_index: {route_index}, route_count: {route_count}, route_family: {route_family}"
                )),
            );
        });
    }

    pub(crate) fn record_connect_race_outcome(
        &self,
        trace_id: u64,
        phase: &str,
        summary: String,
        details: Option<String>,
    ) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(phase, summary, details);
        });
    }

    pub(crate) fn record_retry(&self, trace_id: u64, attempt: u32, reason: &str) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "retry",
                format!("Retry attempt {attempt}"),
                Some(reason.to_string()),
            );
        });
    }

    pub(crate) fn record_redirect(&self, trace_id: u64, attempt: u32, location: &Uri) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "redirect",
                format!("Redirect {attempt}"),
                Some(location.to_string()),
            );
        });
    }

    pub(crate) fn record_dns_start(&self, trace_id: u64, host: &str, port: u16) {
        self.with_trace(trace_id, |trace| {
            trace.push_event("dns_start", format!("Resolving {host}:{port}"), None);
        });
    }

    pub(crate) fn record_dns_end(&self, trace_id: u64, host: &str, addrs: &[std::net::SocketAddr]) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "dns_end",
                format!("Resolved {host}"),
                Some(
                    addrs
                        .iter()
                        .map(std::string::ToString::to_string)
                        .collect::<Vec<_>>()
                        .join(", "),
                ),
            );
        });
    }

    pub(crate) fn record_dns_failed(&self, trace_id: u64, host: &str, error: &WireError) {
        self.record_failure(
            trace_id,
            "dns_failed",
            format!("DNS lookup failed for {host}"),
            error.to_string(),
        );
    }

    pub(crate) fn record_connect_start(&self, trace_id: u64, addr: std::net::SocketAddr) {
        self.with_trace(trace_id, |trace| {
            trace.push_event("connect_start", format!("Connecting to {addr}"), None);
        });
    }

    pub(crate) fn record_connect_end(
        &self,
        trace_id: u64,
        connection_id: ConnectionId,
        addr: std::net::SocketAddr,
    ) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "connect_end",
                format!("Connected to {addr}"),
                Some(format!("connection_id: {}", connection_id.as_u64())),
            );
        });
    }

    pub(crate) fn record_connect_failed(
        &self,
        trace_id: u64,
        addr: std::net::SocketAddr,
        error: &WireError,
    ) {
        self.record_failure(
            trace_id,
            "connect_failed",
            format!("Connect failed for {addr}"),
            error.to_string(),
        );
    }

    pub(crate) fn record_tls_start(&self, trace_id: u64, server_name: &str) {
        self.with_trace(trace_id, |trace| {
            trace.push_event("tls_start", format!("Starting TLS for {server_name}"), None);
        });
    }

    pub(crate) fn record_tls_end(&self, trace_id: u64, server_name: &str) {
        self.with_trace(trace_id, |trace| {
            trace.push_event("tls_end", format!("TLS ready for {server_name}"), None);
        });
    }

    pub(crate) fn record_tls_failed(&self, trace_id: u64, server_name: &str, error: &WireError) {
        self.record_failure(
            trace_id,
            "tls_failed",
            format!("TLS failed for {server_name}"),
            error.to_string(),
        );
    }

    pub(crate) fn record_request_headers_start(&self, trace_id: u64) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "request_headers_start",
                "Sending request headers".to_string(),
                None,
            );
        });
    }

    pub(crate) fn record_request_headers_end(&self, trace_id: u64) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "request_headers_end",
                "Finished sending request headers".to_string(),
                None,
            );
        });
    }

    pub(crate) fn record_request_body_end(&self, trace_id: u64, bytes_sent: u64) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "request_body_end",
                format!("Sent {bytes_sent} request bytes"),
                None,
            );
        });
    }

    pub(crate) fn record_response_headers_start(&self, trace_id: u64) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "response_headers_start",
                "Waiting for response headers".to_string(),
                None,
            );
        });
    }

    fn with_trace(&self, trace_id: u64, mutate: impl FnOnce(&mut NetworkTraceRecord)) {
        let mut state = self.inner.lock().expect("diagnostics store poisoned");
        if let Some(trace) = state.traces.get_mut(&trace_id) {
            mutate(trace);
        }
    }

    fn record_failure_if_in_progress(
        &self,
        trace_id: u64,
        phase: &str,
        summary: String,
        details: String,
    ) {
        self.with_trace(trace_id, |trace| {
            if trace.outcome != NetworkTraceOutcome::InProgress {
                return;
            }
            trace.outcome = NetworkTraceOutcome::Failed;
            trace.error_message = Some(details.clone());
            trace.finished_at_unix_ms = Some(now_unix_ms());
            trace.push_event(phase, summary, Some(details));
        });
    }

    pub(crate) fn record_cancelled_if_in_progress(
        &self,
        trace_id: u64,
        summary: &str,
        details: Option<&str>,
    ) {
        self.with_trace(trace_id, |trace| {
            if trace.outcome != NetworkTraceOutcome::InProgress {
                return;
            }
            trace.outcome = NetworkTraceOutcome::Cancelled;
            trace.error_message = None;
            trace.finished_at_unix_ms = Some(now_unix_ms());
            trace.push_event(
                "cancelled",
                summary.to_string(),
                details.map(ToOwned::to_owned),
            );
        });
    }

    fn record_failure(&self, trace_id: u64, phase: &str, summary: String, details: String) {
        self.with_trace(trace_id, |trace| {
            if trace.outcome == NetworkTraceOutcome::Cancelled {
                return;
            }
            trace.outcome = NetworkTraceOutcome::Failed;
            trace.error_message = Some(details.clone());
            trace.finished_at_unix_ms = Some(now_unix_ms());
            trace.push_event(phase, summary, Some(details));
        });
    }
}

pub(crate) struct FireNetworkTraceEventListenerFactory {
    diagnostics: Arc<FireDiagnosticsStore>,
}

impl FireNetworkTraceEventListenerFactory {
    pub(crate) fn new(diagnostics: Arc<FireDiagnosticsStore>) -> Self {
        Self { diagnostics }
    }
}

impl EventListenerFactory for FireNetworkTraceEventListenerFactory {
    fn create(&self, request: &Request<RequestBody>) -> Arc<dyn EventListener> {
        let trace_id = request
            .extensions()
            .get::<FireRequestTraceMetadata>()
            .map(|metadata| metadata.trace_id);
        let operation = request
            .extensions()
            .get::<FireRequestTraceMetadata>()
            .map(|metadata| metadata.operation.clone())
            .unwrap_or_else(|| "request".to_string());

        Arc::new(FireNetworkTraceEventListener {
            diagnostics: Arc::clone(&self.diagnostics),
            trace_id,
            _operation: operation,
        })
    }
}

struct FireNetworkTraceEventListener {
    diagnostics: Arc<FireDiagnosticsStore>,
    trace_id: Option<u64>,
    _operation: String,
}

impl FireNetworkTraceEventListener {
    fn with_trace(&self, action: impl FnOnce(&FireDiagnosticsStore, u64)) {
        if let Some(trace_id) = self.trace_id {
            action(&self.diagnostics, trace_id);
        }
    }
}

impl EventListener for FireNetworkTraceEventListener {
    fn call_start(&self, ctx: &CallContext, _request: &Request<RequestBody>) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_call_start(trace_id, ctx));
    }

    fn call_end(&self, _ctx: &CallContext, response: &Response<ResponseBody>) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_call_end(trace_id, response));
    }

    fn call_failed(&self, _ctx: &CallContext, error: &WireError) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_call_failed(trace_id, error));
    }

    fn dns_start(&self, _ctx: &CallContext, host: &str, port: u16) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_dns_start(trace_id, host, port));
    }

    fn dns_end(&self, _ctx: &CallContext, host: &str, addrs: &[std::net::SocketAddr]) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_dns_end(trace_id, host, addrs));
    }

    fn dns_failed(&self, _ctx: &CallContext, host: &str, error: &WireError) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_dns_failed(trace_id, host, error)
        });
    }

    fn connect_start(&self, _ctx: &CallContext, addr: std::net::SocketAddr) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_connect_start(trace_id, addr));
    }

    fn connect_end(
        &self,
        _ctx: &CallContext,
        connection_id: ConnectionId,
        addr: std::net::SocketAddr,
    ) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_connect_end(trace_id, connection_id, addr)
        });
    }

    fn connect_failed(&self, _ctx: &CallContext, addr: std::net::SocketAddr, error: &WireError) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_connect_failed(trace_id, addr, error)
        });
    }

    fn tls_start(&self, _ctx: &CallContext, server_name: &str) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_tls_start(trace_id, server_name)
        });
    }

    fn tls_end(&self, _ctx: &CallContext, server_name: &str) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_tls_end(trace_id, server_name));
    }

    fn tls_failed(&self, _ctx: &CallContext, server_name: &str, error: &WireError) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_tls_failed(trace_id, server_name, error)
        });
    }

    fn request_headers_start(&self, _ctx: &CallContext) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_request_headers_start(trace_id));
    }

    fn request_headers_end(&self, _ctx: &CallContext) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_request_headers_end(trace_id));
    }

    fn request_body_end(&self, _ctx: &CallContext, bytes_sent: u64) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_request_body_end(trace_id, bytes_sent)
        });
    }

    fn response_headers_start(&self, _ctx: &CallContext) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_response_headers_start(trace_id)
        });
    }

    fn response_headers_end(&self, _ctx: &CallContext, response: &Response<ResponseBody>) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_response_headers(trace_id, response)
        });
    }

    fn response_body_end(&self, _ctx: &CallContext, bytes_read: u64) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_response_body_bytes(trace_id, bytes_read)
        });
    }

    fn response_body_failed(&self, _ctx: &CallContext, error: &WireError) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_response_body_failed(trace_id, error)
        });
    }

    fn pool_lookup(&self, _ctx: &CallContext, hit: bool, connection_id: Option<ConnectionId>) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_pool_lookup(trace_id, hit, connection_id)
        });
    }

    fn connection_acquired(&self, _ctx: &CallContext, connection_id: ConnectionId, reused: bool) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_connection_acquired(trace_id, connection_id, reused)
        });
    }

    fn connection_released(&self, _ctx: &CallContext, connection_id: ConnectionId) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_connection_released(trace_id, connection_id)
        });
    }

    fn route_plan(&self, _ctx: &CallContext, route_count: usize, fast_fallback_enabled: bool) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_route_plan(trace_id, route_count, fast_fallback_enabled)
        });
    }

    fn connect_race_start(
        &self,
        _ctx: &CallContext,
        race_id: u64,
        route_index: usize,
        route_count: usize,
        route_family: &str,
    ) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_connect_race_start(
                trace_id,
                race_id,
                route_index,
                route_count,
                route_family,
            )
        });
    }

    fn connect_race_won(
        &self,
        _ctx: &CallContext,
        race_id: u64,
        route_index: usize,
        route_count: usize,
    ) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_connect_race_outcome(
                trace_id,
                "connect_race_won",
                format!("Connect race {race_id} won"),
                Some(format!(
                    "route_index: {route_index}, route_count: {route_count}"
                )),
            )
        });
    }

    fn connect_race_lost(
        &self,
        _ctx: &CallContext,
        race_id: u64,
        route_index: usize,
        route_count: usize,
        reason: &str,
    ) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_connect_race_outcome(
                trace_id,
                "connect_race_lost",
                format!("Connect race {race_id} lost"),
                Some(format!(
                    "route_index: {route_index}, route_count: {route_count}, reason: {reason}"
                )),
            )
        });
    }

    fn retry(&self, _ctx: &CallContext, attempt: u32, reason: &str) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_retry(trace_id, attempt, reason)
        });
    }

    fn redirect(&self, _ctx: &CallContext, attempt: u32, location: &Uri) {
        self.with_trace(|diagnostics, trace_id| {
            diagnostics.record_redirect(trace_id, attempt, location)
        });
    }
}

pub(crate) fn list_log_files(
    workspace_path: &Path,
) -> Result<Vec<FireLogFileSummary>, FireCoreError> {
    let log_root = workspace_path.join("logs");
    let mut out = Vec::new();
    if log_root.exists() {
        visit_log_files(workspace_path, &log_root, &mut out)?;
    }
    let diagnostics_root = workspace_path.join("diagnostics");
    if diagnostics_root.exists() {
        visit_log_files(workspace_path, &diagnostics_root, &mut out)?;
    }
    out.sort_by(|left, right| {
        right
            .modified_at_unix_ms
            .cmp(&left.modified_at_unix_ms)
            .then_with(|| right.relative_path.cmp(&left.relative_path))
    });
    Ok(out)
}

pub(crate) fn read_log_file(
    workspace_path: &Path,
    relative_path: impl AsRef<Path>,
) -> Result<FireLogFileDetail, FireCoreError> {
    let relative_path = relative_path.as_ref();
    validate_workspace_relative_path(relative_path)?;

    let resolved_path = workspace_path.join(relative_path);
    let metadata = fs::metadata(&resolved_path).map_err(|source| FireCoreError::WorkspaceIo {
        path: resolved_path.clone(),
        source,
    })?;
    let bytes = fs::read(&resolved_path).map_err(|source| FireCoreError::WorkspaceIo {
        path: resolved_path.clone(),
        source,
    })?;
    let decoded = decode_log_file_contents(&resolved_path, &bytes);
    let (contents, is_truncated) = truncate_text(&decoded, MAX_LOG_CONTENT_BYTES);

    Ok(FireLogFileDetail {
        relative_path: workspace_relative_path_string(relative_path),
        file_name: resolved_path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string(),
        size_bytes: metadata.len(),
        modified_at_unix_ms: metadata
            .modified()
            .ok()
            .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
            .map(|value| value.as_millis().min(u64::MAX as u128) as u64)
            .unwrap_or_default(),
        contents,
        is_truncated,
    })
}

pub(crate) fn read_log_file_page(
    workspace_path: &Path,
    relative_path: impl AsRef<Path>,
    cursor: Option<u64>,
    max_bytes: usize,
    direction: DiagnosticsPageDirection,
) -> Result<FireLogFilePage, FireCoreError> {
    let relative_path = relative_path.as_ref();
    validate_workspace_relative_path(relative_path)?;

    let resolved_path = workspace_path.join(relative_path);
    let metadata = fs::metadata(&resolved_path).map_err(|source| FireCoreError::WorkspaceIo {
        path: resolved_path.clone(),
        source,
    })?;
    let bytes = fs::read(&resolved_path).map_err(|source| FireCoreError::WorkspaceIo {
        path: resolved_path.clone(),
        source,
    })?;
    let decoded = decode_log_file_contents(&resolved_path, &bytes);
    let page = paginate_log_text(
        &decoded,
        cursor,
        normalized_page_bytes(max_bytes, DEFAULT_LOG_PAGE_BYTES),
        direction,
    );

    Ok(FireLogFilePage {
        relative_path: workspace_relative_path_string(relative_path),
        file_name: resolved_path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string(),
        size_bytes: metadata.len(),
        modified_at_unix_ms: metadata
            .modified()
            .ok()
            .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
            .map(|value| value.as_millis().min(u64::MAX as u128) as u64)
            .unwrap_or_default(),
        page,
    })
}

pub(crate) fn export_support_bundle(
    workspace_path: &Path,
    diagnostics: &FireDiagnosticsStore,
    redacted_session_json: &str,
    host_context: &FireSupportBundleHostContext,
) -> Result<FireSupportBundleExport, FireCoreError> {
    let generated_at_unix_ms = now_unix_ms();
    let file_name = format!("fire-support-{generated_at_unix_ms}.json");
    let relative_path = Path::new("diagnostics")
        .join("support-bundles")
        .join(&file_name);
    let absolute_path = workspace_path.join(&relative_path);
    let parent = absolute_path
        .parent()
        .expect("support bundle path should have a parent");
    fs::create_dir_all(parent).map_err(|source| FireCoreError::DiagnosticsIo {
        path: parent.to_path_buf(),
        source,
    })?;

    let session: Value = serde_json::from_str(redacted_session_json)
        .map_err(FireCoreError::DiagnosticsDeserialize)?;
    let log_files = list_log_files(workspace_path)?;
    let log_pages = log_files
        .iter()
        .take(SUPPORT_BUNDLE_LOG_FILE_LIMIT)
        .map(|file| {
            read_log_file_page(
                workspace_path,
                &file.relative_path,
                None,
                SUPPORT_BUNDLE_LOG_PAGE_BYTES,
                DiagnosticsPageDirection::Older,
            )
        })
        .collect::<Result<Vec<_>, _>>()?;
    let trace_summaries = diagnostics.summaries(SUPPORT_BUNDLE_TRACE_LIMIT);
    let trace_payloads = trace_summaries
        .iter()
        .map(|summary| {
            let detail = diagnostics.detail(summary.id).ok_or_else(|| {
                FireCoreError::DiagnosticsTraceNotFound {
                    trace_id: summary.id.to_string(),
                }
            })?;
            let body_page = diagnostics.network_trace_body_page(
                summary.id,
                None,
                SUPPORT_BUNDLE_TRACE_BODY_BYTES,
                DiagnosticsPageDirection::Newer,
            );
            Ok(support_bundle_trace_json(&detail, body_page.as_ref()))
        })
        .collect::<Result<Vec<_>, FireCoreError>>()?;

    let payload = json!({
        "version": 1,
        "generated_at_unix_ms": generated_at_unix_ms,
        "diagnostic_session_id": diagnostics.diagnostic_session_id(),
        "host": {
            "platform": host_context.platform,
            "app_version": host_context.app_version,
            "build_number": host_context.build_number,
            "scene_phase": host_context.scene_phase,
        },
        "session": session,
        "logs": log_pages.iter().map(support_bundle_log_json).collect::<Vec<_>>(),
        "network_traces": trace_payloads,
    });

    let contents =
        serde_json::to_vec_pretty(&payload).map_err(FireCoreError::DiagnosticsSerialize)?;
    write_atomic(&absolute_path, &contents).map_err(|source| FireCoreError::DiagnosticsIo {
        path: absolute_path.clone(),
        source,
    })?;
    let size_bytes = fs::metadata(&absolute_path)
        .map_err(|source| FireCoreError::DiagnosticsIo {
            path: absolute_path.clone(),
            source,
        })?
        .len();

    Ok(FireSupportBundleExport {
        file_name,
        relative_path: workspace_relative_path_string(&relative_path),
        absolute_path: absolute_path.display().to_string(),
        size_bytes,
        created_at_unix_ms: generated_at_unix_ms,
        diagnostic_session_id: diagnostics.diagnostic_session_id().to_string(),
    })
}

fn visit_log_files(
    workspace_path: &Path,
    dir: &Path,
    out: &mut Vec<FireLogFileSummary>,
) -> Result<(), FireCoreError> {
    for entry in fs::read_dir(dir).map_err(|source| FireCoreError::WorkspaceIo {
        path: dir.to_path_buf(),
        source,
    })? {
        let entry = entry.map_err(|source| FireCoreError::WorkspaceIo {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.is_dir() {
            if is_support_bundle_path(workspace_path, &path) {
                continue;
            }
            visit_log_files(workspace_path, &path, out)?;
            continue;
        }

        if is_support_bundle_path(workspace_path, &path) {
            continue;
        }

        let metadata = entry
            .metadata()
            .map_err(|source| FireCoreError::WorkspaceIo {
                path: path.clone(),
                source,
            })?;
        let relative_path = path.strip_prefix(workspace_path).map_or_else(
            |_| workspace_relative_path_string(&path),
            workspace_relative_path_string,
        );

        out.push(FireLogFileSummary {
            relative_path,
            file_name: path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string(),
            size_bytes: metadata.len(),
            modified_at_unix_ms: metadata
                .modified()
                .ok()
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .map(|value| value.as_millis().min(u64::MAX as u128) as u64)
                .unwrap_or_default(),
        });
    }

    Ok(())
}

fn trim_oldest_traces(state: &mut FireDiagnosticsState) {
    while state.order.len() > MAX_NETWORK_TRACES {
        if let Some(trace_id) = state.order.pop_front() {
            state.traces.remove(&trace_id);
        }
    }
}

fn sanitize_headers(headers: &HeaderMap) -> Vec<NetworkTraceHeader> {
    headers
        .iter()
        .map(|(name, value)| {
            let value = if is_sensitive_header(name.as_str()) {
                REDACTED_HEADER_VALUE.to_string()
            } else {
                value.to_str().unwrap_or("<non-utf8>").to_string()
            };
            NetworkTraceHeader {
                name: name.as_str().to_string(),
                value,
            }
        })
        .collect()
}

fn is_sensitive_header(name: &str) -> bool {
    matches!(
        name.to_ascii_lowercase().as_str(),
        "authorization" | "cookie" | "set-cookie" | "x-csrf-token"
    )
}

fn header_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn decode_log_file_contents(path: &Path, bytes: &[u8]) -> String {
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default();

    if extension != "xlog" {
        return String::from_utf8(bytes.to_vec()).unwrap_or_else(|_| Xlog::memory_dump(bytes));
    }

    let blocks = parse_blocks(bytes);
    if blocks.is_empty() {
        return Xlog::memory_dump(bytes);
    }

    let mut out = String::new();
    for (index, (header, payload)) in blocks.into_iter().enumerate() {
        if index > 0 && !out.ends_with('\n') {
            out.push('\n');
        }

        match decode_block_payload(&header, &payload) {
            Ok(plain) => out.push_str(&String::from_utf8_lossy(&plain)),
            Err(message) => {
                out.push('[');
                out.push_str(&message);
                out.push_str("]\n");
            }
        }
    }

    out
}

fn parse_blocks(bytes: &[u8]) -> Vec<(LogHeader, Vec<u8>)> {
    let mut blocks = Vec::new();
    let mut offset = 0usize;

    while offset + HEADER_LEN + TAILER_LEN <= bytes.len() {
        let Ok(header) = LogHeader::decode(&bytes[offset..offset + HEADER_LEN]) else {
            break;
        };
        let payload_len = header.len as usize;
        let payload_start = offset + HEADER_LEN;
        let payload_end = payload_start + payload_len;
        if payload_end + TAILER_LEN > bytes.len() {
            break;
        }
        if bytes[payload_end] != MAGIC_END {
            break;
        }

        blocks.push((header, bytes[payload_start..payload_end].to_vec()));
        offset = payload_end + TAILER_LEN;
    }

    blocks
}

fn decode_block_payload(header: &LogHeader, payload: &[u8]) -> Result<Vec<u8>, String> {
    match header.magic {
        MAGIC_ASYNC_NO_CRYPT_ZLIB_START => {
            decompress_raw_zlib(payload).map_err(|error| error.to_string())
        }
        MAGIC_ASYNC_NO_CRYPT_ZSTD_START => {
            decompress_zstd_frames(payload).map_err(|error| error.to_string())
        }
        MAGIC_ASYNC_ZLIB_START
        | MAGIC_ASYNC_ZSTD_START
        | MAGIC_SYNC_ZLIB_START
        | MAGIC_SYNC_ZSTD_START => Err(format!(
            "encrypted block seq={} len={} cannot be decoded without the private key",
            header.seq, header.len
        )),
        _ => Ok(payload.to_vec()),
    }
}

fn paginate_log_text(
    text: &str,
    cursor: Option<u64>,
    max_bytes: usize,
    direction: DiagnosticsPageDirection,
) -> DiagnosticsTextPage {
    if text.is_empty() {
        return paginate_text(text, cursor, max_bytes, direction);
    }

    let total_bytes = text.len();
    let max_bytes = max_bytes.max(1);

    let (start, end, next_cursor) = match direction {
        DiagnosticsPageDirection::Older => {
            let end = previous_char_boundary(text, cursor.unwrap_or(total_bytes as u64) as usize);
            let raw_start = end.saturating_sub(max_bytes);
            let start = if raw_start == 0 {
                0
            } else {
                line_start_at_or_before(text, raw_start)
            };
            let next_cursor = (start > 0).then_some(start as u64);
            (start, end, next_cursor)
        }
        DiagnosticsPageDirection::Newer => {
            let start = next_char_boundary(text, cursor.unwrap_or(0) as usize);
            let raw_end = start.saturating_add(max_bytes).min(total_bytes);
            let end = if raw_end >= total_bytes {
                total_bytes
            } else {
                line_end_at_or_after(text, raw_end)
            };
            let next_cursor = (end < total_bytes).then_some(end as u64);
            (start, end, next_cursor)
        }
    };

    DiagnosticsTextPage {
        text: text[start..end].to_string(),
        start_offset: start as u64,
        end_offset: end as u64,
        total_bytes: total_bytes as u64,
        next_cursor,
        has_more_older: start > 0,
        has_more_newer: end < total_bytes,
        is_head_aligned: start == 0,
        is_tail_aligned: end == total_bytes,
    }
}

fn paginate_text(
    text: &str,
    cursor: Option<u64>,
    max_bytes: usize,
    direction: DiagnosticsPageDirection,
) -> DiagnosticsTextPage {
    let total_bytes = text.len();
    let max_bytes = max_bytes.max(1);

    if text.is_empty() {
        return DiagnosticsTextPage {
            text: String::new(),
            start_offset: 0,
            end_offset: 0,
            total_bytes: 0,
            next_cursor: None,
            has_more_older: false,
            has_more_newer: false,
            is_head_aligned: true,
            is_tail_aligned: true,
        };
    }

    let (start, end, next_cursor) = match direction {
        DiagnosticsPageDirection::Older => {
            let end = previous_char_boundary(text, cursor.unwrap_or(total_bytes as u64) as usize);
            let mut start = next_char_boundary(text, end.saturating_sub(max_bytes));
            if start == end && end > 0 {
                start = previous_char_boundary(text, end.saturating_sub(1));
            }
            let next_cursor = (start > 0).then_some(start as u64);
            (start, end, next_cursor)
        }
        DiagnosticsPageDirection::Newer => {
            let start = next_char_boundary(text, cursor.unwrap_or(0) as usize);
            let mut end = previous_char_boundary(text, start.saturating_add(max_bytes));
            if end == start && start < total_bytes {
                end = next_char_boundary(text, start.saturating_add(1));
            }
            let next_cursor = (end < total_bytes).then_some(end as u64);
            (start, end, next_cursor)
        }
    };

    DiagnosticsTextPage {
        text: text[start..end].to_string(),
        start_offset: start as u64,
        end_offset: end as u64,
        total_bytes: total_bytes as u64,
        next_cursor,
        has_more_older: start > 0,
        has_more_newer: end < total_bytes,
        is_head_aligned: start == 0,
        is_tail_aligned: end == total_bytes,
    }
}

fn line_start_at_or_before(text: &str, offset: usize) -> usize {
    let offset = previous_char_boundary(text, offset);
    match text[..offset].rfind('\n') {
        Some(index) => index + 1,
        None => 0,
    }
}

fn line_end_at_or_after(text: &str, offset: usize) -> usize {
    let offset = next_char_boundary(text, offset);
    match text[offset..].find('\n') {
        Some(index) => offset + index + 1,
        None => text.len(),
    }
}

fn previous_char_boundary(text: &str, offset: usize) -> usize {
    let mut offset = offset.min(text.len());
    while offset > 0 && !text.is_char_boundary(offset) {
        offset -= 1;
    }
    offset
}

fn next_char_boundary(text: &str, offset: usize) -> usize {
    let mut offset = offset.min(text.len());
    while offset < text.len() && !text.is_char_boundary(offset) {
        offset += 1;
    }
    offset
}

fn normalized_page_bytes(requested: usize, fallback: usize) -> usize {
    match requested {
        0 => fallback,
        value => value,
    }
}

fn is_support_bundle_path(workspace_path: &Path, path: &Path) -> bool {
    let support_bundle_root = Path::new("diagnostics").join(SUPPORT_BUNDLE_DIR_NAME);
    path.strip_prefix(workspace_path)
        .ok()
        .is_some_and(|relative_path| relative_path.starts_with(&support_bundle_root))
}

fn workspace_relative_path_string(path: &Path) -> String {
    path.iter()
        .filter_map(|component| {
            let component = component.to_string_lossy();
            (!component.is_empty() && component != ".").then(|| component.into_owned())
        })
        .collect::<Vec<_>>()
        .join("/")
}

fn support_bundle_log_json(page: &FireLogFilePage) -> Value {
    json!({
        "relative_path": page.relative_path,
        "file_name": page.file_name,
        "size_bytes": page.size_bytes,
        "modified_at_unix_ms": page.modified_at_unix_ms,
        "window": diagnostics_text_page_json(&page.page),
    })
}

fn support_bundle_trace_json(
    detail: &NetworkTraceDetail,
    body_page: Option<&NetworkTraceBodyPage>,
) -> Value {
    json!({
        "summary": {
            "id": detail.id,
            "call_id": detail.call_id,
            "operation": detail.operation,
            "method": detail.method,
            "url": detail.url,
            "started_at_unix_ms": detail.started_at_unix_ms,
            "finished_at_unix_ms": detail.finished_at_unix_ms,
            "duration_ms": detail.duration_ms,
            "outcome": support_bundle_trace_outcome(detail.outcome),
            "status_code": detail.status_code,
            "error_message": detail.error_message,
            "response_content_type": detail.response_content_type,
            "response_body_truncated": detail.response_body_truncated,
            "response_body_storage_truncated": detail.response_body_storage_truncated,
            "response_body_stored_bytes": detail.response_body_stored_bytes,
            "response_body_page_available": detail.response_body_page_available,
            "response_body_bytes": detail.response_body_bytes,
        },
        "request_headers": detail
            .request_headers
            .iter()
            .map(support_bundle_header_json)
            .collect::<Vec<_>>(),
        "response_headers": detail
            .response_headers
            .iter()
            .map(support_bundle_header_json)
            .collect::<Vec<_>>(),
        "events": detail.events.iter().map(support_bundle_event_json).collect::<Vec<_>>(),
        "body_page": body_page.map(|page| {
            json!({
                "response_content_type": page.response_content_type,
                "response_body_storage_truncated": page.response_body_storage_truncated,
                "response_body_stored_bytes": page.response_body_stored_bytes,
                "window": diagnostics_text_page_json(&page.page),
            })
        }),
    })
}

fn diagnostics_text_page_json(page: &DiagnosticsTextPage) -> Value {
    json!({
        "text": page.text,
        "start_offset": page.start_offset,
        "end_offset": page.end_offset,
        "total_bytes": page.total_bytes,
        "next_cursor": page.next_cursor,
        "has_more_older": page.has_more_older,
        "has_more_newer": page.has_more_newer,
        "is_head_aligned": page.is_head_aligned,
        "is_tail_aligned": page.is_tail_aligned,
    })
}

fn support_bundle_header_json(header: &NetworkTraceHeader) -> Value {
    json!({
        "name": header.name,
        "value": header.value,
    })
}

fn support_bundle_event_json(event: &NetworkTraceEvent) -> Value {
    json!({
        "sequence": event.sequence,
        "timestamp_unix_ms": event.timestamp_unix_ms,
        "phase": event.phase,
        "summary": event.summary,
        "details": event.details,
    })
}

fn support_bundle_trace_outcome(outcome: NetworkTraceOutcome) -> &'static str {
    match outcome {
        NetworkTraceOutcome::InProgress => "in_progress",
        NetworkTraceOutcome::Succeeded => "succeeded",
        NetworkTraceOutcome::Failed => "failed",
        NetworkTraceOutcome::Cancelled => "cancelled",
    }
}

fn truncate_text(text: &str, max_bytes: usize) -> (String, bool) {
    if text.len() <= max_bytes {
        return (text.to_string(), false);
    }

    let mut end = max_bytes;
    while end > 0 && !text.is_char_boundary(end) {
        end -= 1;
    }

    let mut out = text[..end].to_string();
    out.push_str("\n\n<... truncated ...>");
    (out, true)
}

fn truncate_text_prefix(text: &str, max_bytes: usize) -> (String, bool) {
    if text.len() <= max_bytes {
        return (text.to_string(), false);
    }

    let mut end = max_bytes;
    while end > 0 && !text.is_char_boundary(end) {
        end -= 1;
    }

    (text[..end].to_string(), true)
}

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| {
            duration.as_millis().min(u64::MAX as u128) as u64
        })
}

fn new_diagnostic_session_id() -> String {
    static NEXT_DIAGNOSTIC_SESSION: AtomicU64 = AtomicU64::new(1);
    let counter = NEXT_DIAGNOSTIC_SESSION.fetch_add(1, Ordering::Relaxed);
    format!("diag-{}-{counter}", now_unix_ms())
}

#[cfg(test)]
mod tests {
    use std::{env, fs, path::Path, sync::Arc};

    use serde_json::Value;

    use super::{
        export_support_bundle, read_log_file_page, DiagnosticsPageDirection, FireDiagnosticsStore,
        FireSupportBundleHostContext, NetworkTraceOutcome, Request, RequestBody, Response,
        ResponseBody,
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
            r#"{"cookies":{"forum_session":"<redacted>"}}"#,
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
            super::REDACTED_HEADER_VALUE
        );
        assert_eq!(
            response_headers
                .iter()
                .find(|header| header["name"] == "set-cookie")
                .expect("set-cookie header")["value"],
            super::REDACTED_HEADER_VALUE
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

    fn temp_workspace_dir(name: &str) -> std::path::PathBuf {
        let mut path = env::temp_dir();
        path.push(format!("fire-diagnostics-tests-{}", std::process::id()));
        path.push(name);
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("temp workspace dir");
        path
    }
}
