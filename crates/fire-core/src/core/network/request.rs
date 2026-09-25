use http::{Method, Request};
use openwire::RequestBody;

use super::super::FireCore;
use super::constants::{FIRE_JSON_ACCEPT, MISSING_CSRF_TOKEN_PLACEHOLDER};
use super::traced::TracedRequest;
use super::{FireRequestEpoch, FireRequestProfile};
use crate::error::FireCoreError;

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

    pub(crate) fn build_html_get_request(
        &self,
        operation: &'static str,
        url: &str,
    ) -> Result<TracedRequest, FireCoreError> {
        let uri = self.base_url.join(url)?;
        let (_, epoch) = self.snapshot_with_epoch();
        let mut request = Request::builder()
            .method(Method::GET)
            .uri(uri.as_str())
            .header(
                "Accept",
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            )
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
}
