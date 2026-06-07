use std::sync::{Arc, RwLock};

use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
    CloudflareChallengeRequest,
};
use http::{
    header::{HeaderMap, HeaderName, HeaderValue, ACCEPT_LANGUAGE, ORIGIN, REFERER, USER_AGENT},
    Method, Request, Response, StatusCode,
};
#[cfg(debug_assertions)]
use openwire::ProxyRules;
use openwire::{
    BoxFuture, Call, CallOptions, Client, Exchange, HttpLogger, Interceptor,
    LogLevel as OpenWireLogLevel, LoggerInterceptor, Next, RequestBody, ResponseBody, WireError,
};
use serde::{de::DeserializeOwned, Deserialize};
use tracing::{debug, info, warn};
use url::Url;

use super::{
    FireCore, CLIENT_MAX_CONNECTIONS_PER_HOST, CLIENT_POOL_MAX_IDLE_PER_HOST,
    MESSAGE_BUS_CALL_TIMEOUT, MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL, NETWORK_CALL_TIMEOUT,
    NETWORK_CONNECT_TIMEOUT,
};
use crate::{
    cookies::{FireSessionCookieJar, FIRE_REQUEST_EPOCH, FIRE_REQUEST_TRACE_ID},
    diagnostics::{
        FireDiagnosticsStore, FireNetworkTraceCancellationGuard,
        FireNetworkTraceEventListenerFactory,
    },
    error::FireCoreError,
    sync_utils::read_rwlock,
};

// Discourse strips `data-preloaded` for crawler-style requests, so the shared
// Rust client needs a browser-style fallback UA until hosts pass through an
// exact WebView/browser UA.
#[cfg(target_os = "ios")]
const FIRE_USER_AGENT: &str = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
#[cfg(target_os = "android")]
const FIRE_USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36";
#[cfg(target_os = "macos")]
const FIRE_USER_AGENT: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";
#[cfg(all(
    not(target_os = "ios"),
    not(target_os = "android"),
    not(target_os = "macos")
))]
const FIRE_USER_AGENT: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const FIRE_ACCEPT_LANGUAGE: &str = "zh-CN,zh;q=0.9,en;q=0.8";
const FIRE_JSON_ACCEPT: &str = "application/json, text/javascript, */*; q=0.01";
const FIRE_MESSAGE_BUS_ACCEPT: &str = "text/plain, */*; q=0.01";
const LOGIN_INVALIDATED_MESSAGE: &str = "登录状态已失效，请重新登录。";

/// Placeholder header value used when a write request needs CSRF but Fire's
/// preflight has not yet populated the token. Mirrors Discourse's official web
/// client, which sends `X-CSRF-Token: undefined` so the server can answer with
/// BAD CSRF and let the client refresh + retry. See
/// `execute_api_request_with_csrf_retry`.
const MISSING_CSRF_TOKEN_PLACEHOLDER: &str = "undefined";

#[derive(Debug, Deserialize)]
struct DiscourseErrorEnvelope {
    #[serde(default)]
    errors: Option<DiscourseErrorMessages>,
    #[serde(default)]
    error_type: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum DiscourseErrorMessages {
    One(String),
    Many(Vec<String>),
}

impl DiscourseErrorEnvelope {
    fn first_error_message(&self) -> Option<&str> {
        match &self.errors {
            Some(DiscourseErrorMessages::One(message)) => Some(message.as_str()),
            Some(DiscourseErrorMessages::Many(messages)) => messages
                .iter()
                .map(String::as_str)
                .find(|message| !message.trim().is_empty()),
            None => None,
        }
    }
}

#[derive(Clone, Copy)]
pub(crate) enum FireRequestProfile {
    HomeHtml,
    JsonApi,
    MessageBusPoll,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) enum FireCallProfile {
    #[default]
    DefaultApi,
    MessageBusPoll,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FireRequestEpoch(pub(crate) u64);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FireResponseEpochContext {
    pub(crate) request_epoch: u64,
    pub(crate) operation: &'static str,
}

#[derive(Clone)]
pub(crate) struct FireNetworkLayer {
    client: Client,
    diagnostics: Arc<FireDiagnosticsStore>,
    session: Arc<RwLock<super::FireSessionRuntimeState>>,
}

#[derive(Clone)]
pub(crate) struct FireCommonHeaderInterceptor {
    origin: String,
    referer: String,
    session: Arc<RwLock<super::FireSessionRuntimeState>>,
}

struct FireCommonProfileHeaderContext<'a> {
    profile: FireRequestProfile,
    origin: &'a str,
    referer: &'a str,
    same_origin: bool,
    user_agent: &'a str,
    has_login_session: bool,
    csrf_token: Option<&'a str>,
}

#[derive(Clone)]
pub(crate) struct FireTraceSnapshotInterceptor {
    diagnostics: Arc<FireDiagnosticsStore>,
}

#[derive(Clone, Copy)]
struct FireOpenWireHttpLogger;

impl FireTraceSnapshotInterceptor {
    pub(crate) fn new(diagnostics: Arc<FireDiagnosticsStore>) -> Self {
        Self { diagnostics }
    }
}

impl FireCommonHeaderInterceptor {
    pub(crate) fn new(base_url: Url, session: Arc<RwLock<super::FireSessionRuntimeState>>) -> Self {
        Self {
            origin: request_origin(&base_url),
            referer: request_referer(&base_url),
            session,
        }
    }

    fn apply_headers(&self, request: &mut Request<RequestBody>) {
        let Some(profile) = request.extensions().get::<FireRequestProfile>().copied() else {
            return;
        };
        let snapshot = read_rwlock(&self.session, "session").snapshot.clone();
        let same_origin = request_uri_origin(request)
            .as_deref()
            .is_none_or(|request_origin| request_origin == self.origin);
        let context = FireCommonProfileHeaderContext {
            profile,
            origin: &self.origin,
            referer: &self.referer,
            same_origin,
            user_agent: snapshot
                .browser_user_agent
                .as_deref()
                .filter(|value| !value.is_empty())
                .unwrap_or(FIRE_USER_AGENT),
            has_login_session: snapshot.cookies.has_login_session(),
            csrf_token: snapshot.cookies.csrf_token.as_deref(),
        };
        apply_common_profile_headers(request.headers_mut(), context);
    }
}

impl Interceptor for FireCommonHeaderInterceptor {
    fn intercept(
        &self,
        mut exchange: Exchange,
        next: Next,
    ) -> BoxFuture<Result<Response<ResponseBody>, WireError>> {
        self.apply_headers(exchange.request_mut());
        next.run(exchange)
    }
}

impl Interceptor for FireTraceSnapshotInterceptor {
    fn intercept(
        &self,
        exchange: Exchange,
        next: Next,
    ) -> BoxFuture<Result<Response<ResponseBody>, WireError>> {
        if let Some(metadata) = exchange
            .request()
            .extensions()
            .get::<crate::diagnostics::FireRequestTraceMetadata>()
        {
            self.diagnostics.record_request_headers_snapshot(
                metadata.trace_id,
                exchange.request(),
                exchange.attempt(),
            );
        }
        next.run(exchange)
    }
}

impl HttpLogger for FireOpenWireHttpLogger {
    fn log(&self, message: &str) {
        debug!(target: "openwire::http", "{}", message);
    }
}

fn fire_openwire_logger_interceptor() -> LoggerInterceptor {
    LoggerInterceptor::with_logger(OpenWireLogLevel::Headers, FireOpenWireHttpLogger)
        .redact_header(HeaderName::from_static("x-csrf-token"))
}

#[cfg(target_os = "android")]
fn android_tls_connector() -> openwire::RustlsTlsConnector {
    let roots = rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let root_count = roots.len();
    info!(
        target: "fire.network",
        tls_backend = "rustls",
        verifier_backend = "webpki-roots",
        root_count,
        "configured Android OpenWire TLS verifier"
    );
    let config = rustls::ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    openwire::RustlsTlsConnector::from_config(config)
}

pub(crate) struct TracedRequest {
    pub(crate) trace_id: u64,
    pub(crate) operation: &'static str,
    pub(crate) request: Request<RequestBody>,
}

fn clone_request_for_retry(request: &Request<RequestBody>) -> Option<Request<RequestBody>> {
    let cloned_body = request.body().try_clone()?;
    let request_profile = request.extensions().get::<FireRequestProfile>().copied();
    let request_epoch = request.extensions().get::<FireRequestEpoch>().copied();
    let mut builder = Request::builder()
        .method(request.method().clone())
        .uri(request.uri().clone())
        .version(request.version());
    for (name, value) in request.headers() {
        builder = builder.header(name, value);
    }
    let mut request = builder.body(cloned_body).ok()?;
    if let Some(profile) = request_profile {
        request.extensions_mut().insert(profile);
    }
    if let Some(epoch) = request_epoch {
        request.extensions_mut().insert(epoch);
    }
    Some(request)
}

fn trace_request(
    diagnostics: &Arc<FireDiagnosticsStore>,
    operation: &'static str,
    mut request: Request<RequestBody>,
) -> TracedRequest {
    let trace_id = diagnostics.prepare_request_trace(operation, &mut request);
    TracedRequest {
        trace_id,
        operation,
        request,
    }
}

fn response_from_parts<B>(parts: http::response::Parts, body: B) -> Response<ResponseBody>
where
    ResponseBody: From<B>,
{
    Response::from_parts(parts, body.into())
}

fn request_url_string(request: &Request<RequestBody>) -> String {
    request.uri().to_string()
}

fn request_origin_url(base_url: &Url, request: &Request<RequestBody>) -> Option<String> {
    let request_url = base_url.join(request.uri().path()).ok()?;
    let path = request_url.path();
    let trims_json_route = path.ends_with(".json")
        && (path.starts_with("/c/") || path.starts_with("/tags/") || path.starts_with("/t/"));

    let canonical_path = if path == "/latest.json" {
        Some("/latest".to_string())
    } else if trims_json_route {
        Some(path.trim_end_matches(".json").to_string())
    } else {
        None
    }?;

    let mut url = base_url.clone();
    url.set_path(&canonical_path);
    url.set_query(None);
    url.set_fragment(None);
    Some(url.to_string())
}

fn should_present_foreground_challenge(operation: &'static str, profile: FireCallProfile) -> bool {
    if profile == FireCallProfile::MessageBusPoll {
        return false;
    }

    !matches!(
        operation,
        "refresh bootstrap"
            | "fetch site metadata"
            | "refresh csrf token"
            | "fetch recent notifications"
            | "fetch notifications"
            | "report topic timings"
    ) && !operation.contains("message bus")
}

impl FireNetworkLayer {
    pub(crate) fn new(
        base_url: &Url,
        session: Arc<RwLock<super::FireSessionRuntimeState>>,
        diagnostics: Arc<FireDiagnosticsStore>,
        cookie_jar: Arc<FireSessionCookieJar>,
    ) -> Result<Self, FireCoreError> {
        let builder = Client::builder()
            .cookie_jar(cookie_jar)
            .application_interceptor(FireCommonHeaderInterceptor::new(
                base_url.clone(),
                Arc::clone(&session),
            ))
            .application_interceptor(fire_openwire_logger_interceptor())
            .network_interceptor(FireTraceSnapshotInterceptor::new(Arc::clone(&diagnostics)))
            .connect_timeout(NETWORK_CONNECT_TIMEOUT)
            .call_timeout(NETWORK_CALL_TIMEOUT)
            .max_connections_per_host(CLIENT_MAX_CONNECTIONS_PER_HOST)
            .pool_max_idle_per_host(CLIENT_POOL_MAX_IDLE_PER_HOST)
            .http2_keep_alive_interval(MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL)
            .http2_keep_alive_while_idle(true)
            .event_listener_factory(FireNetworkTraceEventListenerFactory::new(Arc::clone(
                &diagnostics,
            )));
        #[cfg(debug_assertions)]
        let builder = builder.proxy_selector(ProxyRules::new().use_system_proxy(true));
        #[cfg(target_os = "android")]
        let builder = builder.tls_connector(android_tls_connector());
        let client = builder
            .build()
            .map_err(|source| FireCoreError::ClientBuild { source })?;
        Ok(Self {
            client,
            diagnostics,
            session,
        })
    }

    pub(crate) fn client(&self) -> Client {
        self.client.clone()
    }

    pub(crate) async fn execute_traced(
        &self,
        traced: TracedRequest,
        profile: FireCallProfile,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        let trace_id = traced.trace_id;
        let operation = traced.operation;
        let request_epoch = traced
            .request
            .extensions()
            .get::<FireRequestEpoch>()
            .copied()
            .unwrap_or(FireRequestEpoch(0));
        debug!(
            trace_id,
            method = %traced.request.method(),
            uri = %traced.request.uri(),
            profile = ?profile,
            "executing HTTP request"
        );
        let trace_guard = self.diagnostics.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped before the trace reached a terminal state",
        );
        let execute = apply_call_profile(self.client.new_call(traced.request), profile).execute();
        let execute = FIRE_REQUEST_TRACE_ID.scope(trace_id, async move {
            FIRE_REQUEST_EPOCH.scope(request_epoch.0, execute).await
        });
        let mut response = match execute.await {
            Ok(response) => response,
            Err(source) => {
                self.diagnostics
                    .record_call_failed_if_in_progress(trace_id, &source);
                warn!(
                    trace_id,
                    error = %source,
                    profile = ?profile,
                    "HTTP request failed"
                );
                return Err(FireCoreError::Network { source });
            }
        };
        let current_epoch = self.current_epoch();
        let response_epoch = if current_epoch != request_epoch.0 {
            if self.last_response_auth_change().is_some_and(|change| {
                change.request_trace_id == trace_id && change.observed_epoch == current_epoch
            }) {
                current_epoch
            } else {
                trace_guard.cancel(
                    "Session superseded",
                    format!(
                        "Discarded `{operation}` response after session epoch advanced from {} to {}",
                        request_epoch.0, current_epoch
                    ),
                );
                return Err(FireCoreError::StaleSessionResponse { operation });
            }
        } else {
            current_epoch
        };
        response.extensions_mut().insert(trace_guard);
        response.extensions_mut().insert(FireResponseEpochContext {
            request_epoch: response_epoch,
            operation,
        });
        debug!(
            trace_id,
            status = response.status().as_u16(),
            profile = ?profile,
            "HTTP response received"
        );
        Ok((trace_id, response))
    }

    fn current_epoch(&self) -> u64 {
        read_rwlock(&self.session, "session").epoch
    }

    fn last_response_auth_change(&self) -> Option<super::FireResponseAuthChange> {
        read_rwlock(&self.session, "session").last_response_auth_change
    }
}

pub(crate) fn take_trace_cancellation_guard(
    response: &mut Response<ResponseBody>,
) -> Option<FireNetworkTraceCancellationGuard> {
    response
        .extensions_mut()
        .remove::<FireNetworkTraceCancellationGuard>()
}

fn response_epoch_context(response: &Response<ResponseBody>) -> Option<FireResponseEpochContext> {
    response
        .extensions()
        .get::<FireResponseEpochContext>()
        .copied()
}

fn stale_response_error(
    core: &FireCore,
    diagnostics: &Arc<FireDiagnosticsStore>,
    trace_id: u64,
    context: FireResponseEpochContext,
) -> Option<FireCoreError> {
    let current_epoch = core.current_session_epoch();
    if current_epoch == context.request_epoch {
        return None;
    }

    diagnostics.record_cancelled_if_in_progress(
        trace_id,
        "Session superseded",
        Some(&format!(
            "Discarded `{}` response after session epoch advanced from {} to {}",
            context.operation, context.request_epoch, current_epoch
        )),
    );
    Some(FireCoreError::StaleSessionResponse {
        operation: context.operation,
    })
}

fn apply_call_profile(call: Call, profile: FireCallProfile) -> Call {
    call.options(call_options_for_profile(profile))
}

fn call_options_for_profile(profile: FireCallProfile) -> CallOptions {
    match profile {
        FireCallProfile::DefaultApi => CallOptions::default(),
        FireCallProfile::MessageBusPoll => {
            CallOptions::default().call_timeout(MESSAGE_BUS_CALL_TIMEOUT)
        }
    }
}

impl FireCore {
    pub(crate) fn build_home_request(
        &self,
        operation: &'static str,
    ) -> Result<TracedRequest, FireCoreError> {
        let uri = self.base_url.join("/")?;
        let (_, epoch) = self.snapshot_with_epoch();
        let mut request = Request::builder()
            .method(Method::GET)
            .uri(uri.as_str())
            .header("Accept", "text/html")
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)?;
        request
            .extensions_mut()
            .insert(FireRequestProfile::HomeHtml);
        request.extensions_mut().insert(FireRequestEpoch(epoch));
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest {
            trace_id,
            operation,
            request,
        })
    }

    pub(crate) fn build_json_get_request(
        &self,
        operation: &'static str,
        path: &str,
        query_params: Vec<(&str, String)>,
        extra_headers: &[(&str, String)],
    ) -> Result<TracedRequest, FireCoreError> {
        let mut uri = self.base_url.join(path)?;
        let (_, epoch) = self.snapshot_with_epoch();
        if !query_params.is_empty() {
            let mut serializer = uri.query_pairs_mut();
            for (key, value) in query_params {
                serializer.append_pair(key, &value);
            }
        }

        let mut builder = Request::builder()
            .method(Method::GET)
            .uri(uri.as_str())
            .header("Accept", FIRE_JSON_ACCEPT);

        for (name, value) in extra_headers {
            builder = builder.header(*name, value);
        }

        let mut request = builder
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)?;
        request.extensions_mut().insert(FireRequestProfile::JsonApi);
        request.extensions_mut().insert(FireRequestEpoch(epoch));
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest {
            trace_id,
            operation,
            request,
        })
    }

    pub(crate) fn build_api_request(
        &self,
        operation: &'static str,
        method: Method,
        path: &str,
        requires_csrf: bool,
    ) -> Result<TracedRequest, FireCoreError> {
        let body = if matches!(method, Method::GET | Method::HEAD) {
            RequestBody::empty()
        } else {
            RequestBody::explicit_empty()
        };
        self.build_api_request_with_body(operation, method, path, None, body, requires_csrf)
    }

    pub(crate) fn build_form_request(
        &self,
        operation: &'static str,
        method: Method,
        path: &str,
        fields: Vec<(&str, String)>,
        requires_csrf: bool,
    ) -> Result<TracedRequest, FireCoreError> {
        let mut serializer = url::form_urlencoded::Serializer::new(String::new());
        for (key, value) in fields {
            serializer.append_pair(key, &value);
        }

        self.build_api_request_with_body(
            operation,
            method,
            path,
            Some("application/x-www-form-urlencoded; charset=utf-8"),
            RequestBody::from(serializer.finish()),
            requires_csrf,
        )
    }

    pub(crate) fn build_form_request_with_headers(
        &self,
        operation: &'static str,
        method: Method,
        path: &str,
        fields: Vec<(String, String)>,
        extra_headers: Vec<(&str, String)>,
        requires_csrf: bool,
    ) -> Result<TracedRequest, FireCoreError> {
        let mut serializer = url::form_urlencoded::Serializer::new(String::new());
        for (key, value) in fields {
            serializer.append_pair(&key, &value);
        }

        let uri = self.base_url.join(path)?;
        let (snapshot, epoch) = self.snapshot_with_epoch();

        let mut builder = Request::builder()
            .method(method)
            .uri(uri.as_str())
            .header("Accept", FIRE_JSON_ACCEPT)
            .header(
                "Content-Type",
                "application/x-www-form-urlencoded; charset=utf-8",
            );

        if requires_csrf {
            // Match Discourse's official frontend: send the literal "undefined"
            // when the cached token is missing instead of failing fast. Writes
            // are normally guarded by `runAuthenticatedWritePreflight` and
            // `execute_api_request_with_csrf_retry`, but on the rare path where
            // both miss, the BAD CSRF retry (`is_bad_csrf_body`) will refresh
            // and replay just like the web client does.
            let csrf_token = snapshot
                .cookies
                .csrf_token
                .unwrap_or_else(|| MISSING_CSRF_TOKEN_PLACEHOLDER.to_string());
            builder = builder.header("X-CSRF-Token", csrf_token);
        }

        for (name, value) in extra_headers {
            builder = builder.header(name, value);
        }

        let mut request = builder
            .body(RequestBody::from(serializer.finish()))
            .map_err(FireCoreError::RequestBuild)?;
        request.extensions_mut().insert(FireRequestProfile::JsonApi);
        request.extensions_mut().insert(FireRequestEpoch(epoch));
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest {
            trace_id,
            operation,
            request,
        })
    }

    pub(crate) fn build_api_request_with_body(
        &self,
        operation: &'static str,
        method: Method,
        path: &str,
        content_type: Option<&str>,
        body: RequestBody,
        requires_csrf: bool,
    ) -> Result<TracedRequest, FireCoreError> {
        let uri = self.base_url.join(path)?;
        let (snapshot, epoch) = self.snapshot_with_epoch();

        let mut builder = Request::builder()
            .method(method)
            .uri(uri.as_str())
            .header("Accept", FIRE_JSON_ACCEPT);

        if requires_csrf {
            // See `build_form_request_with_headers` for rationale: missing
            // CSRF falls back to "undefined" so writes can still elicit a
            // BAD CSRF response that the retry path refreshes and replays.
            let csrf_token = snapshot
                .cookies
                .csrf_token
                .unwrap_or_else(|| MISSING_CSRF_TOKEN_PLACEHOLDER.to_string());
            builder = builder.header("X-CSRF-Token", csrf_token);
        }

        if let Some(content_type) = content_type {
            builder = builder.header("Content-Type", content_type);
        }

        let mut request = builder.body(body).map_err(FireCoreError::RequestBuild)?;
        request.extensions_mut().insert(FireRequestProfile::JsonApi);
        request.extensions_mut().insert(FireRequestEpoch(epoch));
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest {
            trace_id,
            operation,
            request,
        })
    }

    pub(crate) async fn execute_request(
        &self,
        traced: TracedRequest,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        let has_challenge_handler = self.cloudflare_challenge_handler.get().is_some();
        let retry_request = if has_challenge_handler {
            clone_request_for_retry(&traced.request)
        } else {
            None
        };
        let request_url = request_url_string(&traced.request);
        let origin_url = request_origin_url(&self.base_url, &traced.request);
        let is_foreground =
            should_present_foreground_challenge(traced.operation, FireCallProfile::DefaultApi);
        let operation = traced.operation;
        let (trace_id, response) = self
            .network
            .execute_traced(traced, FireCallProfile::DefaultApi)
            .await?;

        if !has_challenge_handler {
            return Ok((trace_id, response));
        }

        let status = response.status();
        if status != StatusCode::FORBIDDEN && status != StatusCode::TOO_MANY_REQUESTS {
            return Ok((trace_id, response));
        }

        let (parts, body) = response.into_parts();
        let body = body
            .bytes()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let body_text = String::from_utf8_lossy(&body);
        if !is_cloudflare_challenge_response(status.as_u16(), &parts.headers, &body_text) {
            return Ok((trace_id, response_from_parts(parts, body)));
        }

        self.diagnostics
            .record_http_status_error(trace_id, status.as_u16(), &body_text);
        self.record_auth_runtime_signal(AuthRuntimeSignal {
            kind: AuthRuntimeSignalKind::CloudflareChallenge,
            strength: AuthRuntimeSignalStrength::Diagnostic,
            source: AuthRuntimeSignalSource::HttpResponse,
            operation: Some(operation.to_string()),
            status: Some(status.as_u16()),
        });
        let handler = match self.cloudflare_challenge_handler.get() {
            Some(handler) => handler,
            None => {
                return Ok((trace_id, response_from_parts(parts, body)));
            }
        };
        {
            let mut runtime = self
                .cloudflare_challenge_runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned");
            if !runtime.can_start() {
                return Err(FireCoreError::CloudflareChallenge { operation });
            }
            runtime.begin();
        }

        let challenge_result = handler(CloudflareChallengeRequest {
            operation: operation.to_string(),
            request_url,
            origin_url,
            is_foreground,
            session_epoch: self.current_session_epoch(),
        })
        .await;
        let before_clearance = self.snapshot().cookies.cf_clearance.clone();
        let resolved = if !challenge_result.completed || challenge_result.user_cancelled {
            Err(FireCoreError::CloudflareChallenge { operation })
        } else {
            let session = self.complete_cloudflare_challenge(
                challenge_result.cookies,
                challenge_result.browser_user_agent,
            );
            let has_new_clearance = session.cookies.cf_clearance != before_clearance
                && session.cookies.has_cloudflare_clearance();
            if !has_new_clearance {
                Err(FireCoreError::CloudflareChallenge { operation })
            } else if let Some(mut retry_request) = retry_request {
                retry_request
                    .extensions_mut()
                    .insert(FireRequestEpoch(self.current_session_epoch()));
                let retry = trace_request(&self.diagnostics, operation, retry_request);
                self.network
                    .execute_traced(retry, FireCallProfile::DefaultApi)
                    .await
            } else {
                Err(FireCoreError::CloudflareChallenge { operation })
            }
        };
        {
            let mut runtime = self
                .cloudflare_challenge_runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned");
            runtime.finish(resolved.is_ok());
        }
        resolved
    }

    pub(crate) async fn read_response_text(
        &self,
        trace_id: u64,
        response: Response<ResponseBody>,
    ) -> Result<String, FireCoreError> {
        let mut response = response;
        let response_epoch = response_epoch_context(&response);
        let _trace_guard = take_trace_cancellation_guard(&mut response).unwrap_or_else(|| {
            self.diagnostics.cancellation_guard(
                trace_id,
                "Request cancelled",
                "Future dropped while reading the response body",
            )
        });
        let content_type = header_value(response.headers(), "content-type");
        let text = match response.into_body().text().await {
            Ok(text) => text,
            Err(source) => {
                self.diagnostics.record_call_failed(trace_id, &source);
                return Err(FireCoreError::Network { source });
            }
        };
        if let Some(error) = response_epoch
            .and_then(|context| stale_response_error(self, &self.diagnostics, trace_id, context))
        {
            return Err(error);
        }
        self.diagnostics
            .record_response_body_text(trace_id, &text, content_type.as_deref());
        Ok(text)
    }

    pub(crate) async fn execute_api_request_with_csrf_retry<F>(
        &self,
        operation: &'static str,
        mut make_request: F,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError>
    where
        F: FnMut() -> Result<TracedRequest, FireCoreError>,
    {
        if !self.snapshot().cookies.can_authenticate_requests() {
            warn!(
                operation,
                "skipping authenticated write because login cookies are unavailable"
            );
            return Err(FireCoreError::MissingLoginSession);
        }

        if !self.snapshot().cookies.has_csrf_token() {
            info!(
                operation,
                "no CSRF token available, refreshing before request"
            );
            let refreshed = self.refresh_csrf_token_if_needed().await?;
            if !refreshed.cookies.can_authenticate_requests() {
                warn!(
                    operation,
                    "CSRF refresh skipped because login cookies are unavailable"
                );
                return Err(FireCoreError::MissingLoginSession);
            }
            if !refreshed.cookies.has_csrf_token() {
                warn!(operation, "CSRF refresh completed without a token");
                return Err(FireCoreError::MissingCsrfToken);
            }
        }

        let traced = make_request()?;
        let (trace_id, response) = self.execute_request(traced).await?;

        if response.status() != StatusCode::FORBIDDEN {
            return Ok((trace_id, response));
        }

        let invalidation = response_login_invalidation_signal(response.headers());
        let response_headers = response.headers().clone();
        let body = self.read_response_text(trace_id, response).await?;
        self.diagnostics
            .record_http_status_error(trace_id, StatusCode::FORBIDDEN.as_u16(), &body);
        if let Some(error) = response_login_invalidation_error(
            operation,
            trace_id,
            StatusCode::FORBIDDEN,
            invalidation,
            &body,
        ) {
            if let Some(strike_error) = self
                .classify_and_process_auth_strike(
                    StatusCode::FORBIDDEN,
                    &invalidation,
                    &body,
                    operation,
                )
                .await
            {
                return Err(strike_error);
            }
            return Err(error);
        }

        if let Some(signal) = response_auth_runtime_signal(
            StatusCode::FORBIDDEN,
            &response_headers,
            &invalidation,
            &body,
            operation,
        ) {
            let _ = self.process_auth_runtime_signal(signal, operation).await;
        }

        if !is_bad_csrf_body(&body) {
            warn!(
                operation,
                trace_id,
                status = 403u16,
                body_prefix = %body.chars().take(200).collect::<String>(),
                "request rejected with 403 (not a CSRF error)"
            );
            return Err(classify_http_status_error(
                operation,
                StatusCode::FORBIDDEN.as_u16(),
                &response_headers,
                body,
            ));
        }

        info!(
            operation,
            trace_id, "received BAD CSRF, refreshing token and retrying"
        );
        let _ = self.clear_csrf_token();
        let refreshed = self.refresh_csrf_token_if_needed().await?;
        if !refreshed.cookies.can_authenticate_requests() {
            warn!(
                operation,
                trace_id, "skipping BAD CSRF retry because login cookies are unavailable"
            );
            return Err(FireCoreError::MissingLoginSession);
        }
        if !refreshed.cookies.has_csrf_token() {
            warn!(
                operation,
                trace_id, "skipping BAD CSRF retry because refresh did not produce a token"
            );
            return Err(FireCoreError::MissingCsrfToken);
        }

        let retry = make_request()?;
        self.execute_request(retry).await
    }

    pub(crate) async fn read_response_json_with_diagnostics<T>(
        &self,
        operation: &'static str,
        trace_id: u64,
        response: Response<ResponseBody>,
    ) -> Result<T, FireCoreError>
    where
        T: DeserializeOwned,
    {
        let text = self.read_response_text(trace_id, response).await?;
        serde_json::from_str(&text).map_err(|source| {
            warn!(
                operation,
                trace_id,
                error = %source,
                body_prefix = %text.chars().take(200).collect::<String>(),
                "failed to deserialize JSON response"
            );
            self.diagnostics.record_parse_error(
                trace_id,
                format!("Failed to parse {operation} response"),
                source.to_string(),
            );
            FireCoreError::ResponseDeserialize { operation, source }
        })
    }

    pub(crate) async fn read_response_json<T>(
        &self,
        operation: &'static str,
        trace_id: u64,
        response: Response<ResponseBody>,
    ) -> Result<T, FireCoreError>
    where
        T: DeserializeOwned,
    {
        self.read_response_json_with_diagnostics(operation, trace_id, response)
            .await
    }

    async fn classify_and_process_auth_strike(
        &self,
        status: StatusCode,
        invalidation: &LoginInvalidationSignal,
        body: &str,
        operation: &'static str,
    ) -> Option<FireCoreError> {
        let signal = if is_invalid_access_forbidden(status, body) {
            return None;
        } else if not_logged_in_message(status.as_u16(), body).is_some() {
            Some(AuthRuntimeSignal {
                kind: AuthRuntimeSignalKind::NotLoggedInBody,
                strength: AuthRuntimeSignalStrength::Strong,
                source: AuthRuntimeSignalSource::HttpResponse,
                operation: Some(operation.to_string()),
                status: Some(status.as_u16()),
            })
        } else if status.is_client_error() && invalidation.discourse_logged_out {
            Some(AuthRuntimeSignal {
                kind: AuthRuntimeSignalKind::DiscourseLoggedOutHeader,
                strength: AuthRuntimeSignalStrength::Strong,
                source: AuthRuntimeSignalSource::HttpResponse,
                operation: Some(operation.to_string()),
                status: Some(status.as_u16()),
            })
        } else {
            None
        }?;
        self.process_auth_runtime_signal(signal, operation).await
    }
}

pub(crate) async fn expect_success(
    core: &FireCore,
    operation: &'static str,
    trace_id: u64,
    response: Response<ResponseBody>,
) -> Result<Response<ResponseBody>, FireCoreError> {
    if response.status().is_success() {
        let invalidation = response_login_invalidation_signal(response.headers());
        if let Some(signal) =
            success_auth_runtime_signal(response.status(), &invalidation, operation)
        {
            let _ = core.process_auth_runtime_signal(signal, operation).await;
        }
        return Ok(response);
    }

    let mut response = response;
    let response_status = response.status();
    let status = response_status.as_u16();
    let invalidation = response_login_invalidation_signal(response.headers());
    let response_headers = response.headers().clone();
    let response_epoch = response_epoch_context(&response);
    let _trace_guard = take_trace_cancellation_guard(&mut response).unwrap_or_else(|| {
        core.diagnostics.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped while reading the error response body",
        )
    });
    let body = response
        .into_body()
        .text()
        .await
        .unwrap_or_else(|error| format!("<failed to read error body: {error}>"));
    if let Some(error) = response_epoch
        .and_then(|context| stale_response_error(core, &core.diagnostics, trace_id, context))
    {
        return Err(error);
    }
    warn!(
        operation,
        trace_id,
        status,
        body_prefix = %body.chars().take(200).collect::<String>(),
        "HTTP request returned non-success status"
    );
    core.diagnostics
        .record_http_status_error(trace_id, status, &body);
    if let Some(error) =
        response_login_invalidation_error(operation, trace_id, response_status, invalidation, &body)
    {
        if let Some(strike_error) = core
            .classify_and_process_auth_strike(response_status, &invalidation, &body, operation)
            .await
        {
            return Err(strike_error);
        }
        return Err(error);
    }
    if let Some(signal) = response_auth_runtime_signal(
        response_status,
        &response_headers,
        &invalidation,
        &body,
        operation,
    ) {
        let _ = core.process_auth_runtime_signal(signal, operation).await;
    }
    Err(classify_http_status_error(
        operation,
        status,
        &response_headers,
        body,
    ))
}

pub(crate) fn header_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

pub(crate) fn is_bad_csrf_body(body: &str) -> bool {
    body == r#"["BAD CSRF"]"#
}

pub(crate) fn classify_http_status_error(
    operation: &'static str,
    status: u16,
    headers: &HeaderMap,
    body: String,
) -> FireCoreError {
    if is_cloudflare_challenge_response(status, headers, &body) {
        FireCoreError::CloudflareChallenge { operation }
    } else if let Some(message) = not_logged_in_message(status, &body) {
        FireCoreError::LoginRequired { operation, message }
    } else {
        FireCoreError::HttpStatus {
            operation,
            status,
            body,
        }
    }
}

fn discourse_error_envelope(body: &str) -> Option<DiscourseErrorEnvelope> {
    serde_json::from_str(body).ok()
}

fn not_logged_in_message(status: u16, body: &str) -> Option<String> {
    if status != StatusCode::UNAUTHORIZED.as_u16() && status != StatusCode::FORBIDDEN.as_u16() {
        return None;
    }

    let envelope = discourse_error_envelope(body)?;
    if envelope.error_type.as_deref() != Some("not_logged_in") {
        return None;
    }

    Some(
        envelope
            .first_error_message()
            .unwrap_or("需要登录才能执行此操作。")
            .to_string(),
    )
}

fn is_invalid_access_forbidden(status: StatusCode, body: &str) -> bool {
    status == StatusCode::FORBIDDEN
        && discourse_error_envelope(body)
            .and_then(|envelope| envelope.error_type)
            .as_deref()
            == Some("invalid_access")
}

fn success_auth_runtime_signal(
    status: StatusCode,
    invalidation: &LoginInvalidationSignal,
    operation: &'static str,
) -> Option<AuthRuntimeSignal> {
    if !status.is_success() {
        return None;
    }

    if invalidation.discourse_logged_out {
        return Some(AuthRuntimeSignal {
            kind: if invalidation.has_auth_cookie_deletion() {
                AuthRuntimeSignalKind::MixedSignalCookieDeletionBlocked
            } else {
                AuthRuntimeSignalKind::MixedLoggedOutHeader
            },
            strength: AuthRuntimeSignalStrength::Weak,
            source: AuthRuntimeSignalSource::HttpResponse,
            operation: Some(operation.to_string()),
            status: Some(status.as_u16()),
        });
    }

    if invalidation.has_auth_cookie_deletion() {
        return Some(AuthRuntimeSignal {
            kind: AuthRuntimeSignalKind::AuthCookieDeletion,
            strength: AuthRuntimeSignalStrength::Diagnostic,
            source: AuthRuntimeSignalSource::SetCookieIngress,
            operation: Some(operation.to_string()),
            status: Some(status.as_u16()),
        });
    }

    None
}

fn response_auth_runtime_signal(
    status: StatusCode,
    headers: &HeaderMap,
    invalidation: &LoginInvalidationSignal,
    body: &str,
    operation: &'static str,
) -> Option<AuthRuntimeSignal> {
    let signal = if is_cloudflare_challenge_response(status.as_u16(), headers, body) {
        Some((
            AuthRuntimeSignalKind::CloudflareChallenge,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else if is_bad_csrf_body(body) {
        Some((
            AuthRuntimeSignalKind::BadCsrf,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else if is_invalid_access_forbidden(status, body) {
        Some((
            AuthRuntimeSignalKind::InvalidAccessForbidden,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else if not_logged_in_message(status.as_u16(), body).is_some() {
        Some((
            AuthRuntimeSignalKind::NotLoggedInBody,
            AuthRuntimeSignalStrength::Strong,
        ))
    } else if status.is_client_error() && invalidation.discourse_logged_out {
        Some((
            AuthRuntimeSignalKind::DiscourseLoggedOutHeader,
            AuthRuntimeSignalStrength::Strong,
        ))
    } else if invalidation.has_auth_cookie_deletion() {
        Some((
            AuthRuntimeSignalKind::AuthCookieDeletion,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else if status == StatusCode::TOO_MANY_REQUESTS {
        Some((
            AuthRuntimeSignalKind::RateLimit,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else {
        None
    }?;

    Some(AuthRuntimeSignal {
        kind: signal.0,
        strength: signal.1,
        source: AuthRuntimeSignalSource::HttpResponse,
        operation: Some(operation.to_string()),
        status: Some(status.as_u16()),
    })
}

#[derive(Clone, Copy, Debug, Default)]
struct LoginInvalidationSignal {
    discourse_logged_out: bool,
    cleared_t_cookie: bool,
    cleared_forum_session: bool,
}

impl LoginInvalidationSignal {
    fn any(self) -> bool {
        // Deleted auth cookies are useful diagnostics, but only explicit server
        // invalidation signals should force local logout.
        self.discourse_logged_out
    }

    fn has_auth_cookie_deletion(self) -> bool {
        self.cleared_t_cookie || self.cleared_forum_session
    }
}

fn response_login_invalidation_signal(headers: &HeaderMap) -> LoginInvalidationSignal {
    let discourse_logged_out = header_value(headers, "discourse-logged-out").is_some();
    let mut cleared_t_cookie = false;
    let mut cleared_forum_session = false;

    for value in headers.get_all("set-cookie") {
        let Ok(value) = value.to_str() else {
            continue;
        };
        cleared_t_cookie |= clears_cookie(value, "_t");
        cleared_forum_session |= clears_cookie(value, "_forum_session");
    }

    LoginInvalidationSignal {
        discourse_logged_out,
        cleared_t_cookie,
        cleared_forum_session,
    }
}

fn clears_cookie(set_cookie_header: &str, name: &str) -> bool {
    let lower = set_cookie_header.trim().to_ascii_lowercase();
    let prefix = format!("{}=", name.to_ascii_lowercase());
    if !lower.starts_with(&prefix) {
        return false;
    }

    let Some((_, rest)) = lower.split_once('=') else {
        return false;
    };
    let value = rest.split(';').next().map(str::trim).unwrap_or_default();
    if !value.is_empty() && value != "del" {
        return false;
    }

    lower.contains("max-age=0") || lower.contains("expires=thu, 01 jan 1970 00:00:00 gmt")
}

fn response_login_invalidation_error(
    operation: &'static str,
    trace_id: u64,
    status: StatusCode,
    invalidation: LoginInvalidationSignal,
    body: &str,
) -> Option<FireCoreError> {
    if is_invalid_access_forbidden(status, body) {
        return None;
    }
    let login_required_message = not_logged_in_message(status.as_u16(), body);
    let header_invalidates_login = invalidation.any() && status.is_client_error();
    if !header_invalidates_login && login_required_message.is_none() {
        return None;
    }

    warn!(
        operation,
        trace_id,
        status = status.as_u16(),
        discourse_logged_out = invalidation.discourse_logged_out,
        cleared_t_cookie = invalidation.cleared_t_cookie,
        cleared_forum_session = invalidation.cleared_forum_session,
        header_invalidates_login,
        body_prefix = %body.chars().take(200).collect::<String>(),
        "response reported login-required state"
    );
    Some(FireCoreError::LoginRequired {
        operation,
        message: login_required_message.unwrap_or_else(|| LOGIN_INVALIDATED_MESSAGE.to_string()),
    })
}

pub(crate) fn is_cloudflare_challenge_body(body: &str) -> bool {
    let normalized = body.to_ascii_lowercase();
    normalized.contains("cf_chl_opt")
        || (normalized.contains("challenge-platform") && normalized.contains("cloudflare"))
        || (normalized.contains("just a moment")
            && (normalized.contains("cloudflare") || normalized.contains("cf-challenge")))
}

pub(crate) fn is_cloudflare_challenge_response(
    status: u16,
    headers: &HeaderMap,
    body: &str,
) -> bool {
    if status != StatusCode::FORBIDDEN.as_u16() && status != StatusCode::TOO_MANY_REQUESTS.as_u16()
    {
        return false;
    }

    let server = header_value(headers, "server").unwrap_or_default();
    if !server.to_ascii_lowercase().contains("cloudflare") {
        return false;
    }

    let content_type = header_value(headers, "content-type").unwrap_or_default();
    if !content_type.to_ascii_lowercase().contains("text/html") {
        return false;
    }

    let cf_mitigated = header_value(headers, "cf-mitigated").unwrap_or_default();
    if cf_mitigated.to_ascii_lowercase().contains("challenge") {
        return true;
    }

    is_cloudflare_challenge_body(body)
}

pub(crate) fn request_origin(base_url: &Url) -> String {
    let mut origin = base_url.clone();
    origin.set_path("");
    origin.set_query(None);
    origin.set_fragment(None);
    let value = origin.as_str().trim_end_matches('/');
    value.to_string()
}

pub(crate) fn request_referer(base_url: &Url) -> String {
    let mut referer = base_url.clone();
    referer.set_path("/");
    referer.set_query(None);
    referer.set_fragment(None);
    referer.to_string()
}

fn apply_common_profile_headers(
    headers: &mut HeaderMap,
    context: FireCommonProfileHeaderContext<'_>,
) {
    insert_string_header_if_missing(headers, USER_AGENT.as_str(), context.user_agent);
    insert_static_header_if_missing(headers, ACCEPT_LANGUAGE.as_str(), FIRE_ACCEPT_LANGUAGE);

    match context.profile {
        FireRequestProfile::HomeHtml => {}
        FireRequestProfile::JsonApi => {
            insert_string_header_if_missing(headers, REFERER.as_str(), context.referer);
            insert_static_header_if_missing(headers, "X-Requested-With", "XMLHttpRequest");
            insert_static_header_if_missing(headers, "Sec-Fetch-Dest", "empty");
            insert_static_header_if_missing(headers, "Sec-Fetch-Mode", "cors");
            insert_static_header_if_missing(
                headers,
                "Sec-Fetch-Site",
                if context.same_origin {
                    "same-origin"
                } else {
                    "cross-site"
                },
            );
            insert_static_header_if_missing(headers, "Priority", "u=1, i");
            if let Some(csrf_token) = context.csrf_token.filter(|value| !value.is_empty()) {
                insert_string_header_if_missing(headers, "X-CSRF-Token", csrf_token);
            }
            apply_login_headers(headers, context.has_login_session);
        }
        FireRequestProfile::MessageBusPoll => {
            insert_string_header_if_missing(headers, ORIGIN.as_str(), context.origin);
            insert_string_header_if_missing(headers, REFERER.as_str(), context.referer);
            insert_static_header_if_missing(headers, "Accept", FIRE_MESSAGE_BUS_ACCEPT);
            insert_static_header_if_missing(headers, "Sec-Fetch-Dest", "empty");
            insert_static_header_if_missing(headers, "Sec-Fetch-Mode", "cors");
            insert_static_header_if_missing(
                headers,
                "Sec-Fetch-Site",
                if context.same_origin {
                    "same-origin"
                } else {
                    "cross-site"
                },
            );
            insert_static_header_if_missing(headers, "Priority", "u=1, i");
            apply_login_headers(headers, context.has_login_session);
        }
    }
}

fn request_uri_origin(request: &Request<RequestBody>) -> Option<String> {
    let uri = request.uri();
    let scheme = uri.scheme_str()?;
    let authority = uri.authority()?.as_str();
    Some(format!("{scheme}://{authority}"))
}

fn apply_login_headers(headers: &mut HeaderMap, has_login_session: bool) {
    if has_login_session {
        insert_static_header_if_missing(headers, "Discourse-Logged-In", "true");
        insert_static_header_if_missing(headers, "Discourse-Present", "true");
    }
}

fn insert_static_header_if_missing(
    headers: &mut HeaderMap,
    name: &'static str,
    value: &'static str,
) {
    if !headers.contains_key(name) {
        headers.insert(name, HeaderValue::from_static(value));
    }
}

fn insert_string_header_if_missing(headers: &mut HeaderMap, name: &'static str, value: &str) {
    if headers.contains_key(name) {
        return;
    }
    if let Ok(value) = HeaderValue::from_str(value) {
        headers.insert(name, value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn clone_request_for_retry_does_not_create_a_second_trace_until_replayed() {
        let diagnostics = Arc::new(FireDiagnosticsStore::new());
        let mut request = Request::builder()
            .method(Method::GET)
            .uri("https://example.com/latest.json")
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
}
