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

use crate::{error::FireCoreError, workspace::validate_workspace_relative_path};

const MAX_NETWORK_TRACES: usize = 200;
const MAX_RESPONSE_BODY_BYTES: usize = 256 * 1024;
const MAX_LOG_CONTENT_BYTES: usize = 512 * 1024;
const REDACTED_HEADER_VALUE: &str = "<redacted>";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkTraceOutcome {
    InProgress,
    Succeeded,
    Failed,
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
    response_body_truncated: bool,
    response_body_bytes: Option<u64>,
    events: Vec<NetworkTraceEvent>,
}

impl NetworkTraceRecord {
    fn duration_ms(&self) -> Option<u64> {
        self.finished_at_unix_ms
            .map(|finished| finished.saturating_sub(self.started_at_unix_ms))
    }

    fn mark_succeeded(&mut self) {
        if self.outcome != NetworkTraceOutcome::Failed {
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
            response_body_truncated: self.response_body_truncated,
        }
    }

    fn to_detail(&self) -> NetworkTraceDetail {
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
            response_body: self.response_body.clone(),
            response_body_truncated: self.response_body_truncated,
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
    next_trace_id: AtomicU64,
    inner: Mutex<FireDiagnosticsState>,
}

impl Default for FireDiagnosticsStore {
    fn default() -> Self {
        Self::new()
    }
}

impl FireDiagnosticsStore {
    pub(crate) fn new() -> Self {
        Self {
            next_trace_id: AtomicU64::new(1),
            inner: Mutex::new(FireDiagnosticsState::default()),
        }
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
            response_body_truncated: false,
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
                format!("Call completed with HTTP {}", response.status().as_u16()),
                None,
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
            let (stored, truncated) = truncate_text(body, MAX_RESPONSE_BODY_BYTES);
            trace.response_body = Some(stored);
            trace.response_body_truncated = truncated;
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
            trace.outcome = NetworkTraceOutcome::Failed;
            trace.status_code = Some(status);
            trace.error_message = Some(format!("HTTP {status}"));
            trace.finished_at_unix_ms = Some(now_unix_ms());
            let (stored, truncated) = truncate_text(body, MAX_RESPONSE_BODY_BYTES);
            trace.response_body = Some(stored);
            trace.response_body_truncated = truncated;
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

    fn record_failure(&self, trace_id: u64, phase: &str, summary: String, details: String) {
        self.with_trace(trace_id, |trace| {
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
        relative_path: relative_path.to_string_lossy().to_string(),
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
            visit_log_files(workspace_path, &path, out)?;
            continue;
        }

        let metadata = entry
            .metadata()
            .map_err(|source| FireCoreError::WorkspaceIo {
                path: path.clone(),
                source,
            })?;
        let relative_path = path.strip_prefix(workspace_path).map_or_else(
            |_| path.to_string_lossy().to_string(),
            |value| value.to_string_lossy().to_string(),
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

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| {
            duration.as_millis().min(u64::MAX as u128) as u64
        })
}

#[cfg(test)]
mod tests {
    use super::{FireDiagnosticsStore, NetworkTraceOutcome, Request, RequestBody};

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
        assert!(detail
            .response_body
            .expect("body")
            .ends_with("<... truncated ...>"));
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
}
