use fire_models::{CookieSelfHealingPhase, CookieSelfHealingRequest};
use http::header::HeaderMap;
use http::{Request, Response, StatusCode};
use openwire::{CallOptions, RequestBody, ResponseBody};

use super::super::FireCore;
use super::auth_signals::{
    is_invalid_access_forbidden, not_logged_in_message, response_login_invalidation_signal,
};
use super::body::is_bad_csrf_body;
use super::challenge::is_cloudflare_challenge_response;
use super::constants::COOKIE_SELF_HEALING_NAMES;
use super::traced::{
    clone_request_for_retry, response_from_parts, trace_request, FireSkipCookieSelfHeal,
};
use super::FireRequestEpoch;
use crate::error::FireCoreError;

pub(super) struct FireCookieSelfHealingTarget {
    pub(super) request_url: String,
    pub(super) origin_url: Option<String>,
}

impl FireCore {
    pub(super) async fn maybe_self_heal_response(
        &self,
        operation: &'static str,
        target: FireCookieSelfHealingTarget,
        trace_id: u64,
        response: Response<ResponseBody>,
        retry_request: Option<Request<RequestBody>>,
        options: CallOptions,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        let Some(handler) = self.cookie_self_healing_handler.get() else {
            return Ok((trace_id, response));
        };
        if self.is_logging_out() || operation == "logout" {
            return Ok((trace_id, response));
        }
        if !cookie_self_healing_precheck(response.status(), response.headers()) {
            return Ok((trace_id, response));
        }

        let mut current_trace_id = trace_id;
        let (mut parts, body) = response.into_parts();
        let mut body = body
            .bytes()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let mut body_text = String::from_utf8_lossy(&body).to_string();
        if !is_cookie_self_healing_response(parts.status, &parts.headers, &body_text) {
            return Ok((current_trace_id, response_from_parts(parts, body)));
        }

        let Some(original_retry_request) = retry_request else {
            return Ok((current_trace_id, response_from_parts(parts, body)));
        };
        let FireCookieSelfHealingTarget {
            request_url,
            origin_url,
        } = target;
        let target_url = origin_url.unwrap_or_else(|| self.base_url.as_str().to_string());
        let cookie_names = COOKIE_SELF_HEALING_NAMES
            .iter()
            .map(|name| (*name).to_string())
            .collect::<Vec<_>>();
        let attempts = [
            (CookieSelfHealingPhase::Sweep, 1u8),
            (CookieSelfHealingPhase::Sweep, 2u8),
            (CookieSelfHealingPhase::NuclearReset, 1u8),
        ];

        for (phase, attempt) in attempts {
            let result = handler(CookieSelfHealingRequest {
                operation: operation.to_string(),
                request_url: request_url.clone(),
                target_url: target_url.clone(),
                phase,
                attempt,
                cookie_names: cookie_names.clone(),
                session_epoch: self.current_session_epoch(),
            })
            .await;
            if !result.completed {
                continue;
            }

            let Some(mut request) = clone_request_for_retry(&original_retry_request) else {
                break;
            };
            request
                .extensions_mut()
                .insert(FireRequestEpoch(self.current_session_epoch()));
            request.extensions_mut().insert(FireSkipCookieSelfHeal);
            let retry = trace_request(&self.diagnostics, operation, request);
            let (retry_trace_id, retry_response) =
                Box::pin(self.execute_request_with_options(retry, options)).await?;

            if !cookie_self_healing_precheck(retry_response.status(), retry_response.headers()) {
                return Ok((retry_trace_id, retry_response));
            }
            current_trace_id = retry_trace_id;
            let (retry_parts, retry_body) = retry_response.into_parts();
            parts = retry_parts;
            body = retry_body
                .bytes()
                .await
                .map_err(|source| FireCoreError::Network { source })?;
            body_text = String::from_utf8_lossy(&body).to_string();
            if !is_cookie_self_healing_response(parts.status, &parts.headers, &body_text) {
                return Ok((current_trace_id, response_from_parts(parts, body)));
            }
        }

        Ok((current_trace_id, response_from_parts(parts, body)))
    }
}

pub(super) fn cookie_self_healing_precheck(status: StatusCode, headers: &HeaderMap) -> bool {
    matches!(status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN)
        || status.as_u16() == 419
        || response_login_invalidation_signal(headers).discourse_logged_out
}

pub(super) fn is_cookie_self_healing_response(
    status: StatusCode,
    headers: &HeaderMap,
    body: &str,
) -> bool {
    if is_invalid_access_forbidden(status, body)
        || is_cloudflare_challenge_response(status.as_u16(), headers, body)
        || is_bad_csrf_body(body)
        || not_logged_in_message(status.as_u16(), body).is_some()
    {
        return false;
    }
    if status == StatusCode::UNAUTHORIZED || status.as_u16() == 419 {
        return true;
    }
    let invalidation = response_login_invalidation_signal(headers);
    status.is_client_error() && invalidation.discourse_logged_out
}
