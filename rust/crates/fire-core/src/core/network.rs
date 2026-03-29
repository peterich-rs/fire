use http::{header::HeaderMap, Method, Request, Response, StatusCode};
use openwire::{RequestBody, ResponseBody};
use serde::de::DeserializeOwned;
use tracing::{debug, info, warn};
use url::Url;

use super::FireCore;
use crate::error::FireCoreError;

pub(crate) struct TracedRequest {
    pub(crate) trace_id: u64,
    pub(crate) request: Request<RequestBody>,
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
            .header("User-Agent", "Fire/0.1")
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)?;
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

        let origin = request_origin(&self.base_url);
        let referer = request_referer(&self.base_url);
        let snapshot = self.snapshot();

        let mut builder = Request::builder()
            .method(Method::GET)
            .uri(uri.as_str())
            .header(
                "Accept",
                "application/json;q=0.9, text/plain;q=0.8, */*;q=0.5",
            )
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
            .header("X-Requested-With", "XMLHttpRequest")
            .header("User-Agent", "Fire/0.1")
            .header("Origin", origin)
            .header("Referer", referer);

        if snapshot.cookies.has_login_session() {
            builder = builder
                .header("Discourse-Logged-In", "true")
                .header("Discourse-Present", "true");
        }

        for (name, value) in extra_headers {
            builder = builder.header(*name, value);
        }

        let mut request = builder
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)?;
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
        let origin = request_origin(&self.base_url);
        let referer = request_referer(&self.base_url);
        let snapshot = self.snapshot();

        let mut builder = Request::builder()
            .method(method)
            .uri(uri.as_str())
            .header(
                "Accept",
                "application/json;q=0.9, text/plain;q=0.8, */*;q=0.5",
            )
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
            .header("X-Requested-With", "XMLHttpRequest")
            .header("User-Agent", "Fire/0.1")
            .header("Origin", origin)
            .header("Referer", referer);

        if snapshot.cookies.has_login_session() {
            builder = builder
                .header("Discourse-Logged-In", "true")
                .header("Discourse-Present", "true");
        }

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
        let trace_id = self
            .diagnostics
            .prepare_request_trace(operation, &mut request);
        Ok(TracedRequest { trace_id, request })
    }

    pub(crate) async fn execute_request(
        &self,
        traced: TracedRequest,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        debug!(
            trace_id = traced.trace_id,
            method = %traced.request.method(),
            uri = %traced.request.uri(),
            "executing HTTP request"
        );
        let response = self
            .client
            .execute(traced.request)
            .await
            .map_err(|source| {
                warn!(
                    trace_id = traced.trace_id,
                    error = %source,
                    "HTTP request failed"
                );
                FireCoreError::Network { source }
            })?;
        debug!(
            trace_id = traced.trace_id,
            status = response.status().as_u16(),
            "HTTP response received"
        );
        Ok((traced.trace_id, response))
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
            return Err(FireCoreError::HttpStatus {
                operation,
                status: StatusCode::FORBIDDEN.as_u16(),
                body,
            });
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

    pub(crate) async fn read_response_json<T>(
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
    Err(FireCoreError::HttpStatus {
        operation,
        status,
        body,
    })
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

fn request_origin(base_url: &Url) -> String {
    let mut origin = base_url.clone();
    origin.set_path("");
    origin.set_query(None);
    origin.set_fragment(None);
    let value = origin.as_str().trim_end_matches('/');
    value.to_string()
}

fn request_referer(base_url: &Url) -> String {
    let mut referer = base_url.clone();
    referer.set_path("/");
    referer.set_query(None);
    referer.set_fragment(None);
    referer.to_string()
}
