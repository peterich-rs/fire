use std::{
    collections::{BTreeMap, VecDeque},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::{SystemTime, UNIX_EPOCH},
};

use http::{HeaderMap, Request, Response, Uri};
use openwire::{CallContext, ConnectionId, RequestBody, ResponseBody, WireError};

use super::logs::{normalized_page_bytes, paginate_text, truncate_text_prefix};
use super::models::{
    DiagnosticsPageDirection, FireRequestTraceMetadata, NetworkTraceBodyPage, NetworkTraceDetail,
    NetworkTraceEvent, NetworkTraceHeader, NetworkTraceOutcome, NetworkTraceSummary,
    DEFAULT_TRACE_BODY_PAGE_BYTES, MAX_NETWORK_TRACES, MAX_RESPONSE_BODY_BYTES,
    MAX_RESPONSE_BODY_INLINE_BYTES,
};

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

impl FireNetworkTraceCancellationGuard {
    pub(crate) fn cancel(self, summary: impl Into<String>, details: impl Into<String>) {
        let summary = summary.into();
        let details = details.into();
        if !self.inner.armed.swap(false, Ordering::AcqRel) {
            return;
        }

        self.inner.diagnostics.record_cancelled_if_in_progress(
            self.inner.trace_id,
            &summary,
            Some(&details),
        );
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

    pub(crate) fn record_call_end(&self, trace_id: u64) {
        self.with_trace(trace_id, |trace| {
            trace.push_event(
                "call_end",
                "Call completed".to_string(),
                Some("response body lifecycle already finished".to_string()),
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
        .map(|(name, value)| NetworkTraceHeader {
            name: name.as_str().to_string(),
            value: value.to_str().unwrap_or("<non-utf8>").to_string(),
        })
        .collect()
}

fn header_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

pub(super) fn now_unix_ms() -> u64 {
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
