use std::sync::Arc;

use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
    CloudflareChallengeRequest,
};
use http::{header::COOKIE, Response, StatusCode};
use openwire::{CallOptions, ResponseBody};

use super::super::FireCore;
use super::challenge::{
    is_cloudflare_challenge_response, should_present_foreground_challenge,
    CloudflareChallengeFinishGuard,
};
use super::heal::FireCookieSelfHealingTarget;
use super::traced::{
    clone_request_for_retry, request_origin_url, request_url_string, response_from_parts,
    FireSkipCloudflareBlock, FireSkipCookieSelfHeal, TracedRequest,
};
use super::FireCallProfile;
use crate::error::{CloudflareChallengeFailureReason, FireCoreError};

impl FireCore {
    pub(crate) async fn execute_request(
        &self,
        traced: TracedRequest,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        self.execute_request_with_options(traced, CallOptions::default())
            .await
    }

    pub(crate) async fn execute_request_with_options(
        &self,
        traced: TracedRequest,
        options: CallOptions,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        let has_challenge_handler = self.cloudflare_challenge_handler.get().is_some();
        let has_cookie_healing_handler = self.cookie_self_healing_handler.get().is_some();
        let skip_cookie_self_heal = traced
            .request
            .extensions()
            .get::<FireSkipCookieSelfHeal>()
            .is_some();
        let skip_cloudflare_block = traced
            .request
            .extensions()
            .get::<FireSkipCloudflareBlock>()
            .is_some()
            || self
                .cloudflare_challenge_runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned")
                .recovery_http_bypass();
        let sent_cf_clearance = traced
            .request
            .headers()
            .get(COOKIE)
            .and_then(|value| value.to_str().ok())
            .and_then(fire_models::extract_cf_clearance_from_cookie_header);
        let retry_request =
            if has_challenge_handler || (has_cookie_healing_handler && !skip_cookie_self_heal) {
                clone_request_for_retry(&traced.request)
            } else {
                None
            };
        let request_url = request_url_string(&traced.request);
        let origin_url = request_origin_url(&self.base_url, &traced.request);
        let is_foreground = should_present_foreground_challenge(
            traced.operation,
            FireCallProfile::DefaultApi,
            &traced.request,
        );
        let operation = traced.operation;
        let had_login_session_at_send = self.snapshot().cookies.has_login_session();
        let (trace_id, response) = if self.should_use_browser_transport(operation) {
            self.execute_via_browser(traced).await?
        } else {
            self.network
                .execute_traced_with_options(traced, FireCallProfile::DefaultApi, options)
                .await?
        };

        let response = if has_challenge_handler
            && matches!(
                response.status(),
                StatusCode::FORBIDDEN | StatusCode::TOO_MANY_REQUESTS
            ) {
            let status = response.status();
            let (parts, body) = response.into_parts();
            let body = body
                .bytes()
                .await
                .map_err(|source| FireCoreError::Network { source })?;
            let body_text = String::from_utf8_lossy(&body);
            if !is_cloudflare_challenge_response(status.as_u16(), &parts.headers, &body_text) {
                self.complete_pending_clearance_retry_if_needed();
                response_from_parts(parts, body)
            } else {
                self.diagnostics
                    .record_http_status_error(trace_id, status.as_u16(), &body_text);
                self.record_auth_runtime_signal(AuthRuntimeSignal {
                    kind: AuthRuntimeSignalKind::CloudflareChallenge,
                    strength: AuthRuntimeSignalStrength::Diagnostic,
                    source: AuthRuntimeSignalSource::HttpResponse,
                    operation: Some(operation.to_string()),
                    status: Some(status.as_u16()),
                });
                // Local clearance (if any) was just rejected by the edge.
                let challenged = sent_cf_clearance.clone().or_else(|| {
                    self.snapshot()
                        .cookies
                        .cf_clearance
                        .as_deref()
                        .map(fire_models::normalize_cf_clearance_value)
                        .filter(|value| !value.is_empty())
                });
                self.note_cf_clearance_challenged(challenged.as_deref());
                self.note_cloudflare_clearance_rejected();
                if skip_cloudflare_block {
                    self.mark_ineffective_cloudflare_cooldown();
                    self.mark_browser_transport_eligible();
                    if self.should_ask_browser_transport() {
                        self.record_auth_runtime_signal(AuthRuntimeSignal {
                            kind: AuthRuntimeSignalKind::AskEnableBrowserTransport,
                            strength: AuthRuntimeSignalStrength::Diagnostic,
                            source: AuthRuntimeSignalSource::HttpResponse,
                            operation: Some(operation.to_string()),
                            status: Some(status.as_u16()),
                        });
                    }
                    return Ok((trace_id, response_from_parts(parts, body)));
                }
                self.capture_turnstile_sitekey_from_challenge_body(&body_text);
                let handler = match self.cloudflare_challenge_handler.get() {
                    Some(handler) => handler,
                    None => {
                        return Ok((trace_id, response_from_parts(parts, body)));
                    }
                };

                let begin = {
                    let mut runtime = self
                        .cloudflare_challenge_runtime
                        .lock()
                        .expect("cloudflare challenge runtime mutex poisoned");
                    runtime.begin_or_join(
                        is_foreground,
                        self.cloudflare_policy().auto_verify,
                        super::super::cf_challenge::CloudflareChallengeIntent::Auto,
                    )
                };

                match begin {
                    super::super::cf_challenge::CloudflareChallengeBegin::Cooldown => {
                        return Err(FireCoreError::CloudflareChallenge {
                            operation,
                            reason: CloudflareChallengeFailureReason::Cooldown,
                        });
                    }
                    super::super::cf_challenge::CloudflareChallengeBegin::BackgroundSuppressed => {
                        return Err(FireCoreError::CloudflareChallenge {
                            operation,
                            reason: CloudflareChallengeFailureReason::BackgroundSuppressed,
                        });
                    }
                    super::super::cf_challenge::CloudflareChallengeBegin::ManualRequired => {
                        return Err(FireCoreError::CloudflareChallenge {
                            operation,
                            reason: CloudflareChallengeFailureReason::ManualRequired,
                        });
                    }
                    super::super::cf_challenge::CloudflareChallengeBegin::Join(join_rx) => {
                        return self
                            .await_shared_cloudflare_challenge_and_retry(
                                operation,
                                join_rx,
                                retry_request,
                                options,
                            )
                            .await;
                    }
                    super::super::cf_challenge::CloudflareChallengeBegin::Start => {
                        self.sync_cloudflare_recovery_snapshot();
                    }
                }

                let mut finish_guard = CloudflareChallengeFinishGuard {
                    runtime: Arc::clone(&self.cloudflare_challenge_runtime),
                    finished: false,
                };

                let challenge_result = handler(CloudflareChallengeRequest {
                    operation: operation.to_string(),
                    request_url: request_url.clone(),
                    origin_url: origin_url.clone(),
                    is_foreground,
                    session_epoch: self.current_session_epoch(),
                })
                .await;

                let failure_reason = if challenge_result.user_cancelled {
                    Some(CloudflareChallengeFailureReason::Cancelled)
                } else if !challenge_result.completed {
                    Some(CloudflareChallengeFailureReason::Failed)
                } else {
                    None
                };

                let accepted = if failure_reason.is_some() {
                    false
                } else {
                    let fresh_clearance = challenge_result
                        .fresh_cf_clearance
                        .as_deref()
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(str::to_string);
                    let _ = self.complete_cloudflare_challenge(
                        challenge_result.cookies,
                        fresh_clearance,
                        challenge_result.browser_user_agent,
                    );
                    true
                };

                if !accepted {
                    finish_guard.finish(false);
                    self.sync_cloudflare_recovery_snapshot();
                    return Err(FireCoreError::CloudflareChallenge {
                        operation,
                        reason: failure_reason.unwrap_or(CloudflareChallengeFailureReason::Failed),
                    });
                }

                // Page clear is not recovery. Hold the epoch through the proof retry.
                finish_guard.finish_page_clear();
                self.sync_cloudflare_recovery_snapshot();
                let browser_retry = retry_request
                    .as_ref()
                    .and_then(clone_request_for_retry);
                let proved = match self
                    .retry_after_cloudflare_challenge(operation, retry_request, options)
                    .await
                {
                    Ok(response) => response,
                    Err(error) => {
                        finish_guard.finish(false);
                        self.sync_cloudflare_recovery_snapshot();
                        return Err(error);
                    }
                };
                let (still_challenged, proved_response) =
                    match classify_cloudflare_challenge_response(proved.1).await {
                        Ok(classified) => classified,
                        Err(error) => {
                            finish_guard.finish(false);
                            self.sync_cloudflare_recovery_snapshot();
                            return Err(error);
                        }
                    };
                let proved = (proved.0, proved_response);
                if still_challenged {
                    self.mark_ineffective_cloudflare_cooldown();
                    self.mark_browser_transport_eligible();
                    if self.should_ask_browser_transport() {
                        self.record_auth_runtime_signal(AuthRuntimeSignal {
                            kind: AuthRuntimeSignalKind::AskEnableBrowserTransport,
                            strength: AuthRuntimeSignalStrength::Diagnostic,
                            source: AuthRuntimeSignalSource::HttpResponse,
                            operation: Some(operation.to_string()),
                            status: Some(proved.1.status().as_u16()),
                        });
                    }
                    if is_foreground
                        && self.request_can_use_browser_transport(operation)
                        && self.should_use_browser_transport(operation)
                    {
                        match self
                            .retry_current_request_via_browser(operation, browser_retry)
                            .await
                        {
                            Ok(Some(browser_proved)) => {
                                finish_guard.disarm();
                                Self::spawn_proved_challenge_refresh(
                                    self.clone(),
                                    Arc::clone(&self.cloudflare_challenge_runtime),
                                );
                                return Ok(browser_proved);
                            }
                            Ok(None) | Err(_) => {
                                self.reset_session_browser_transport();
                            }
                        }
                    }
                    finish_guard.finish(false);
                    self.sync_cloudflare_recovery_snapshot();
                    return Err(FireCoreError::CloudflareChallenge {
                        operation,
                        reason: CloudflareChallengeFailureReason::Failed,
                    });
                }

                // Refresh calls back into execute_request. Finish the epoch from
                // that task so this future does not recurse, and so joiners stay
                // parked until bootstrap and the forced refresh are done.
                finish_guard.disarm();
                Self::spawn_proved_challenge_refresh(
                    self.clone(),
                    Arc::clone(&self.cloudflare_challenge_runtime),
                );
                return Ok(proved);
            }
        } else {
            self.complete_pending_clearance_retry_if_needed();
            response
        };

        if has_cookie_healing_handler && !skip_cookie_self_heal {
            return self
                .maybe_self_heal_response(
                    operation,
                    FireCookieSelfHealingTarget {
                        request_url,
                        origin_url,
                    },
                    trace_id,
                    response,
                    retry_request,
                    options,
                    had_login_session_at_send,
                )
                .await;
        }

        Ok((trace_id, response))
    }

    async fn retry_current_request_via_browser(
        &self,
        operation: &'static str,
        retry_request: Option<http::Request<openwire::RequestBody>>,
    ) -> Result<Option<(u64, Response<ResponseBody>)>, FireCoreError> {
        let Some(mut retry_request) = retry_request else {
            return Ok(None);
        };
        retry_request
            .extensions_mut()
            .insert(super::FireRequestEpoch(self.current_session_epoch()));
        retry_request
            .extensions_mut()
            .insert(FireSkipCloudflareBlock);
        let retry = super::traced::trace_request(&self.diagnostics, operation, retry_request);
        let proved = self.execute_via_browser(retry).await?;
        let (still_challenged, response) =
            classify_cloudflare_challenge_response(proved.1).await?;
        if still_challenged {
            Ok(None)
        } else {
            Ok(Some((proved.0, response)))
        }
    }
}

async fn classify_cloudflare_challenge_response(
    response: Response<ResponseBody>,
) -> Result<(bool, Response<ResponseBody>), FireCoreError> {
    let status = response.status();
    if status != StatusCode::FORBIDDEN && status != StatusCode::TOO_MANY_REQUESTS {
        return Ok((false, response));
    }
    let (parts, body) = response.into_parts();
    let bytes = body
        .bytes()
        .await
        .map_err(|source| FireCoreError::Network { source })?;
    let text = String::from_utf8_lossy(&bytes);
    let challenged = is_cloudflare_challenge_response(status.as_u16(), &parts.headers, &text);
    Ok((challenged, response_from_parts(parts, bytes)))
}
