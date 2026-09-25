use http::{Response, StatusCode};
use openwire::ResponseBody;
use tracing::{info, warn};

use super::super::FireCore;
use super::auth_signals::{
    response_auth_runtime_signal, response_login_invalidation_error,
    response_login_invalidation_signal,
};
use super::body::{classify_http_status_error, is_bad_csrf_body};
use super::traced::TracedRequest;
use crate::error::FireCoreError;

impl FireCore {
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

        if is_bad_csrf_body(&body) {
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
            return self.execute_request(retry).await;
        }

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

        warn!(
            operation,
            trace_id,
            status = 403u16,
            body_prefix = %body.chars().take(200).collect::<String>(),
            "request rejected with 403 (not a CSRF error)"
        );
        Err(classify_http_status_error(
            operation,
            StatusCode::FORBIDDEN.as_u16(),
            &response_headers,
            body,
        ))
    }
}
