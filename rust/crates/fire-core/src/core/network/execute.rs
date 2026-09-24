use std::sync::{Arc, Mutex, RwLock};

use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
    CloudflareChallengeRequest,
};
use http::header::COOKIE;
use http::{Response, StatusCode};
#[cfg(debug_assertions)]
use openwire::ProxyRules;
use openwire::{Call, CallOptions, Client, DnsResolver, ResponseBody};
use tracing::{debug, warn};
use url::Url;

use super::super::{
    FireCore, CLIENT_MAX_CONNECTIONS_PER_HOST, CLIENT_POOL_MAX_IDLE_PER_HOST,
    MESSAGE_BUS_CALL_TIMEOUT, MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL, NETWORK_CALL_TIMEOUT,
    NETWORK_CONNECT_TIMEOUT,
};
use super::challenge::{
    is_cloudflare_challenge_response, should_present_foreground_challenge,
    CloudflareChallengeFinishGuard,
};
use super::client::{
    apply_platform_tls, fire_openwire_logger_interceptor, FireCommonHeaderInterceptor,
    FireTraceSnapshotInterceptor,
};
use super::heal::FireCookieSelfHealingTarget;
use super::traced::{
    clone_request_for_retry, request_origin_url, request_url_string, response_from_parts,
    FireSkipCloudflareBlock, FireSkipCookieSelfHeal, TracedRequest,
};
use super::{FireCallProfile, FireNetworkLayer, FireRequestEpoch, FireResponseEpochContext};
use crate::cookies::{FireSessionCookieJar, FIRE_REQUEST_EPOCH, FIRE_REQUEST_TRACE_ID};
use crate::diagnostics::{
    FireDiagnosticsStore, FireNetworkTraceCancellationGuard, FireNetworkTraceEventListenerFactory,
};
use crate::error::{CloudflareChallengeFailureReason, FireCoreError};
use crate::sync_utils::read_rwlock;

impl FireNetworkLayer {
    pub(crate) fn new(
        base_url: &Url,
        session: Arc<RwLock<super::super::FireSessionRuntimeState>>,
        diagnostics: Arc<FireDiagnosticsStore>,
        cookie_jar: Arc<FireSessionCookieJar>,
        cloudflare_challenge_runtime: Arc<
            Mutex<super::super::cf_challenge::FireCloudflareChallengeRuntime>,
        >,
        dns_resolver: impl DnsResolver,
    ) -> Result<Self, FireCoreError> {
        let builder = Client::builder()
            .cookie_jar(cookie_jar)
            .dns_resolver(dns_resolver)
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
        let builder = apply_platform_tls(builder);
        let client = builder
            .build()
            .map_err(|source| FireCoreError::ClientBuild { source })?;
        Ok(Self {
            client,
            diagnostics,
            session,
            cloudflare_challenge_runtime,
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
        self.execute_traced_with_options(traced, profile, CallOptions::default())
            .await
    }

    pub(crate) async fn execute_traced_with_options(
        &self,
        traced: TracedRequest,
        profile: FireCallProfile,
        options: CallOptions,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        let trace_id = traced.trace_id;
        let operation = traced.operation;
        let skip_cloudflare_block = traced
            .request
            .extensions()
            .get::<FireSkipCloudflareBlock>()
            .is_some();
        if !skip_cloudflare_block {
            let settle = self
                .cloudflare_challenge_runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned")
                .trust_settle_remaining();
            if let Some(remaining) = settle {
                // Let jar merges become visible before the first post-challenge wave.
                tokio::time::sleep(remaining).await;
            }
        }
        if !skip_cloudflare_block
            && self
                .cloudflare_challenge_runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned")
                .in_progress
        {
            self.diagnostics.record_cancelled_if_in_progress(
                trace_id,
                "Blocked during Cloudflare challenge",
                Some("Request was not dispatched because Cloudflare verification is in progress"),
            );
            return Err(FireCoreError::CloudflareChallengeInProgress { operation });
        }
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
        let execute = apply_call_profile(self.client.new_call(traced.request), profile)
            .options(options)
            .execute();
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

    fn last_response_auth_change(&self) -> Option<super::super::FireResponseAuthChange> {
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

pub(super) fn response_epoch_context(
    response: &Response<ResponseBody>,
) -> Option<FireResponseEpochContext> {
    response
        .extensions()
        .get::<FireResponseEpochContext>()
        .copied()
}

pub(super) fn stale_response_error(
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

pub(super) fn apply_call_profile(call: Call, profile: FireCallProfile) -> Call {
    call.options(call_options_for_profile(profile))
}

pub(super) fn call_options_for_profile(profile: FireCallProfile) -> CallOptions {
    match profile {
        FireCallProfile::DefaultApi => CallOptions::default(),
        FireCallProfile::MessageBusPoll => {
            CallOptions::default().call_timeout(MESSAGE_BUS_CALL_TIMEOUT)
        }
    }
}

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
            .is_some();
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
        let (trace_id, response) = self
            .network
            .execute_traced_with_options(traced, FireCallProfile::DefaultApi, options)
            .await?;

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
                    runtime.begin_or_join(is_foreground)
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
                    super::super::cf_challenge::CloudflareChallengeBegin::Start => {}
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
                    {
                        let mut runtime = self
                            .cloudflare_challenge_runtime
                            .lock()
                            .expect("cloudflare challenge runtime mutex poisoned");
                        runtime.mark_pending_retry();
                    }
                    let _ = self.complete_cloudflare_challenge(
                        challenge_result.cookies,
                        fresh_clearance,
                        challenge_result.browser_user_agent,
                    );
                    true
                };

                // Joiners may retry now. Recovery is published only after the
                // original request retry proves the page-clear was usable.
                if accepted {
                    finish_guard.finish_page_clear();
                    // Don't wait for the API retry to hydrate identity. Profile
                    // and MessageBus need current_username even when the retry
                    // is still proving recovery or later hits cooldown.
                    let snapshot = self.snapshot();
                    if snapshot.cookies.has_login_session()
                        && (!snapshot.readiness().has_current_user
                            || !snapshot.bootstrap.has_preloaded_data)
                    {
                        self.schedule_post_challenge_session_rebuild();
                    }
                } else {
                    finish_guard.finish(false);
                }

                if !accepted {
                    return Err(FireCoreError::CloudflareChallenge {
                        operation,
                        reason: failure_reason.unwrap_or(CloudflareChallengeFailureReason::Failed),
                    });
                }

                // complete_cloudflare_challenge already schedules post-challenge
                // bootstrap rebuild when a login session is present.

                return self
                    .retry_after_cloudflare_challenge(operation, retry_request, options)
                    .await;
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
                )
                .await;
        }

        Ok((trace_id, response))
    }
}
