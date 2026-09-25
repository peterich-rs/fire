use http::header::HeaderMap;
use http::Response;
use openwire::ResponseBody;
use serde::de::DeserializeOwned;
use tracing::warn;

use super::super::FireCore;
use super::auth_signals::{
    not_logged_in_message, response_auth_runtime_signal, response_login_invalidation_error,
    response_login_invalidation_signal, success_auth_runtime_signal,
};
use super::challenge::is_cloudflare_challenge_response;
use super::execute::{response_epoch_context, stale_response_error, take_trace_cancellation_guard};
use crate::error::{CloudflareChallengeFailureReason, FireCoreError};

impl FireCore {
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
        FireCoreError::CloudflareChallenge {
            operation,
            reason: CloudflareChallengeFailureReason::Required,
        }
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
