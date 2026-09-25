use std::sync::Arc;

use http::{Request, Response, Uri};
use openwire::{
    CallContext, ConnectionId, EventListener, EventListenerFactory, RequestBody, ResponseBody,
    WireError,
};

use super::models::FireRequestTraceMetadata;
use super::store::FireDiagnosticsStore;

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

    fn call_end(&self, _ctx: &CallContext) {
        self.with_trace(|diagnostics, trace_id| diagnostics.record_call_end(trace_id));
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
