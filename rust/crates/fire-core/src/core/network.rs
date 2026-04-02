use std::sync::{Arc, RwLock};

use http::{
    header::{HeaderMap, HeaderValue, ACCEPT_LANGUAGE, ORIGIN, REFERER, USER_AGENT},
    Method, Request, Response, StatusCode,
};
use openwire::{
    BoxFuture, Call, CallOptions, Client, Exchange, Interceptor, Next, RequestBody, ResponseBody,
    WireError,
};
use serde::de::DeserializeOwned;
use tracing::{debug, info, warn};
use url::Url;

use super::{
    FireCore, CLIENT_MAX_CONNECTIONS_PER_HOST, CLIENT_POOL_MAX_IDLE_PER_HOST,
    MESSAGE_BUS_CALL_TIMEOUT, MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL, NETWORK_CALL_TIMEOUT,
    NETWORK_CONNECT_TIMEOUT,
};
use crate::{
    cookies::FireSessionCookieJar,
    diagnostics::{FireDiagnosticsStore, FireNetworkTraceEventListenerFactory},
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
const FIRE_JSON_ACCEPT: &str = "application/json;q=0.9, text/plain;q=0.8, */*;q=0.5";

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

#[derive(Clone)]
pub(crate) struct FireNetworkLayer {
    client: Client,
}

#[derive(Clone)]
pub(crate) struct FireCommonHeaderInterceptor {
    origin: String,
    referer: String,
    session: Arc<RwLock<fire_models::SessionSnapshot>>,
}

#[derive(Clone)]
pub(crate) struct FireTraceSnapshotInterceptor {
    diagnostics: Arc<FireDiagnosticsStore>,
}

impl FireTraceSnapshotInterceptor {
    pub(crate) fn new(diagnostics: Arc<FireDiagnosticsStore>) -> Self {
        Self { diagnostics }
    }
}

impl FireCommonHeaderInterceptor {
    pub(crate) fn new(base_url: Url, session: Arc<RwLock<fire_models::SessionSnapshot>>) -> Self {
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
        let snapshot = read_rwlock(&self.session, "session").clone();
        apply_common_profile_headers(
            request.headers_mut(),
            profile,
            &self.origin,
            &self.referer,
            snapshot
                .browser_user_agent
                .as_deref()
                .filter(|value| !value.is_empty())
                .unwrap_or(FIRE_USER_AGENT),
            snapshot.cookies.has_login_session(),
        );
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

pub(crate) struct TracedRequest {
    pub(crate) trace_id: u64,
    pub(crate) request: Request<RequestBody>,
}

impl FireNetworkLayer {
    pub(crate) fn new(
        base_url: &Url,
        session: Arc<RwLock<fire_models::SessionSnapshot>>,
        diagnostics: Arc<FireDiagnosticsStore>,
        cookie_jar: Arc<FireSessionCookieJar>,
    ) -> Result<Self, FireCoreError> {
        let builder = Client::builder()
            .cookie_jar(cookie_jar)
            .application_interceptor(FireCommonHeaderInterceptor::new(base_url.clone(), session))
            .network_interceptor(FireTraceSnapshotInterceptor::new(Arc::clone(&diagnostics)))
            .connect_timeout(NETWORK_CONNECT_TIMEOUT)
            .call_timeout(NETWORK_CALL_TIMEOUT)
            .max_connections_per_host(CLIENT_MAX_CONNECTIONS_PER_HOST)
            .pool_max_idle_per_host(CLIENT_POOL_MAX_IDLE_PER_HOST)
            .http2_keep_alive_interval(MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL)
            .http2_keep_alive_while_idle(true)
            .event_listener_factory(FireNetworkTraceEventListenerFactory::new(diagnostics));
        #[cfg(debug_assertions)]
        let builder = builder.use_system_proxy(true);
        let client = builder
            .build()
            .map_err(|source| FireCoreError::ClientBuild { source })?;
        Ok(Self { client })
    }

    pub(crate) fn client(&self) -> Client {
        self.client.clone()
    }

    pub(crate) async fn execute_traced(
        &self,
        traced: TracedRequest,
        profile: FireCallProfile,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        debug!(
            trace_id = traced.trace_id,
            method = %traced.request.method(),
            uri = %traced.request.uri(),
            profile = ?profile,
            "executing HTTP request"
        );
        let response = apply_call_profile(self.client.new_call(traced.request), profile)
            .execute()
            .await
            .map_err(|source| {
                warn!(
                    trace_id = traced.trace_id,
                    error = %source,
                    profile = ?profile,
                    "HTTP request failed"
                );
                FireCoreError::Network { source }
            })?;
        debug!(
            trace_id = traced.trace_id,
            status = response.status().as_u16(),
            profile = ?profile,
            "HTTP response received"
        );
        Ok((traced.trace_id, response))
    }
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
        let mut request = Request::builder()
            .method(Method::GET)
            .uri(uri.as_str())
            .header("Accept", "text/html")
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)?;
        request
            .extensions_mut()
            .insert(FireRequestProfile::HomeHtml);
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest { trace_id, request })
    }

    pub(crate) fn build_json_get_request(
        &self,
        operation: &'static str,
        path: &str,
        query_params: Vec<(&str, String)>,
        extra_headers: &[(&str, String)],
    ) -> Result<TracedRequest, FireCoreError> {
        let mut uri = self.base_url.join(path)?;
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
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest { trace_id, request })
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
        let snapshot = self.snapshot();

        let mut builder = Request::builder()
            .method(method)
            .uri(uri.as_str())
            .header("Accept", FIRE_JSON_ACCEPT)
            .header(
                "Content-Type",
                "application/x-www-form-urlencoded; charset=utf-8",
            );

        if requires_csrf {
            let csrf_token = snapshot
                .cookies
                .csrf_token
                .ok_or(FireCoreError::MissingCsrfToken)?;
            builder = builder.header("X-CSRF-Token", csrf_token);
        }

        for (name, value) in extra_headers {
            builder = builder.header(name, value);
        }

        let mut request = builder
            .body(RequestBody::from(serializer.finish()))
            .map_err(FireCoreError::RequestBuild)?;
        request.extensions_mut().insert(FireRequestProfile::JsonApi);
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest { trace_id, request })
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
        let snapshot = self.snapshot();

        let mut builder = Request::builder()
            .method(method)
            .uri(uri.as_str())
            .header("Accept", FIRE_JSON_ACCEPT);

        if requires_csrf {
            let csrf_token = snapshot
                .cookies
                .csrf_token
                .ok_or(FireCoreError::MissingCsrfToken)?;
            builder = builder.header("X-CSRF-Token", csrf_token);
        }

        if let Some(content_type) = content_type {
            builder = builder.header("Content-Type", content_type);
        }

        let mut request = builder.body(body).map_err(FireCoreError::RequestBuild)?;
        request.extensions_mut().insert(FireRequestProfile::JsonApi);
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest { trace_id, request })
    }

    pub(crate) async fn execute_request(
        &self,
        traced: TracedRequest,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        self.network
            .execute_traced(traced, FireCallProfile::DefaultApi)
            .await
    }

    pub(crate) async fn read_response_text(
        &self,
        trace_id: u64,
        response: Response<ResponseBody>,
    ) -> Result<String, FireCoreError> {
        let content_type = header_value(response.headers(), "content-type");
        let text = response.into_body().text().await.map_err(|source| {
            self.diagnostics.record_call_failed(trace_id, &source);
            FireCoreError::Network { source }
        })?;
        self.diagnostics
            .record_response_body_text(trace_id, &text, content_type.as_deref());
        Ok(text)
    }

    pub(crate) async fn read_response_json_direct<T>(
        &self,
        trace_id: u64,
        response: Response<ResponseBody>,
    ) -> Result<T, FireCoreError>
    where
        T: DeserializeOwned,
    {
        response.into_body().json().await.map_err(|source| {
            self.diagnostics.record_call_failed(trace_id, &source);
            FireCoreError::Network { source }
        })
    }

    pub(crate) async fn execute_api_request_with_csrf_retry<F>(
        &self,
        operation: &'static str,
        mut make_request: F,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError>
    where
        F: FnMut() -> Result<TracedRequest, FireCoreError>,
    {
        if !self.snapshot().cookies.has_csrf_token() {
            info!(
                operation,
                "no CSRF token available, refreshing before request"
            );
            let _ = self.refresh_csrf_token().await?;
        }

        let traced = make_request()?;
        let (trace_id, response) = self.execute_request(traced).await?;

        if response.status() != StatusCode::FORBIDDEN {
            return Ok((trace_id, response));
        }

        let body = self.read_response_text(trace_id, response).await?;
        self.diagnostics
            .record_http_status_error(trace_id, StatusCode::FORBIDDEN.as_u16(), &body);

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
                body,
            ));
        }

        info!(
            operation,
            trace_id, "received BAD CSRF, refreshing token and retrying"
        );
        let _ = self.clear_csrf_token();
        let _ = self.refresh_csrf_token().await?;

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
}

pub(crate) async fn expect_success(
    core: &FireCore,
    operation: &'static str,
    trace_id: u64,
    response: Response<ResponseBody>,
) -> Result<Response<ResponseBody>, FireCoreError> {
    if response.status().is_success() {
        return Ok(response);
    }

    let status = response.status().as_u16();
    let body = response
        .into_body()
        .text()
        .await
        .unwrap_or_else(|error| format!("<failed to read error body: {error}>"));
    warn!(
        operation,
        trace_id,
        status,
        body_prefix = %body.chars().take(200).collect::<String>(),
        "HTTP request returned non-success status"
    );
    core.diagnostics
        .record_http_status_error(trace_id, status, &body);
    Err(classify_http_status_error(operation, status, body))
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
    body: String,
) -> FireCoreError {
    if status == StatusCode::FORBIDDEN.as_u16() && is_cloudflare_challenge_body(&body) {
        FireCoreError::CloudflareChallenge { operation }
    } else {
        FireCoreError::HttpStatus {
            operation,
            status,
            body,
        }
    }
}

pub(crate) fn is_cloudflare_challenge_body(body: &str) -> bool {
    let normalized = body.to_ascii_lowercase();
    normalized.contains("just a moment")
        || normalized.contains("cf challenge")
        || normalized.contains("__cf_chl_opt")
        || normalized.contains("/cdn-cgi/challenge-platform/")
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
    profile: FireRequestProfile,
    origin: &str,
    referer: &str,
    user_agent: &str,
    has_login_session: bool,
) {
    insert_string_header_if_missing(headers, USER_AGENT.as_str(), user_agent);
    insert_static_header_if_missing(headers, ACCEPT_LANGUAGE.as_str(), FIRE_ACCEPT_LANGUAGE);

    match profile {
        FireRequestProfile::HomeHtml => {}
        FireRequestProfile::JsonApi => {
            insert_string_header_if_missing(headers, ORIGIN.as_str(), origin);
            insert_string_header_if_missing(headers, REFERER.as_str(), referer);
            insert_static_header_if_missing(headers, "X-Requested-With", "XMLHttpRequest");
            apply_login_headers(headers, has_login_session);
        }
        FireRequestProfile::MessageBusPoll => {
            insert_string_header_if_missing(headers, ORIGIN.as_str(), origin);
            insert_string_header_if_missing(headers, REFERER.as_str(), referer);
            apply_login_headers(headers, has_login_session);
        }
    }
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
}
