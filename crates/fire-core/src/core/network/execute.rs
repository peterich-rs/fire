use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex, RwLock,
};

use http::Response;
#[cfg(debug_assertions)]
use openwire::ProxyRules;
use openwire::{CallOptions, Client, DnsResolver, ResponseBody, WireErrorKind};
use tracing::{debug, warn};
use url::Url;

use super::super::{
    CLIENT_MAX_CONNECTIONS_PER_HOST, CLIENT_POOL_MAX_IDLE_PER_HOST,
    MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL, NETWORK_CALL_TIMEOUT, NETWORK_CONNECT_TIMEOUT,
};
use super::client::{
    apply_platform_tls, fire_openwire_logger_interceptor, FireCommonHeaderInterceptor,
    FireTraceSnapshotInterceptor,
};
use super::profile::apply_call_profile;
use super::traced::{FireSkipCloudflareBlock, TracedRequest};
use super::{FireCallProfile, FireNetworkLayer, FireRequestEpoch, FireResponseEpochContext};
use crate::cookies::{FireSessionCookieJar, FIRE_REQUEST_EPOCH, FIRE_REQUEST_TRACE_ID};
use crate::diagnostics::{FireDiagnosticsStore, FireNetworkTraceEventListenerFactory};
use crate::error::FireCoreError;
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
            in_flight: Arc::new(Mutex::new(Vec::new())),
            next_in_flight_id: Arc::new(AtomicU64::new(1)),
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
        if !skip_cloudflare_block {
            // One recovery epoch parks every later call before it touches the network.
            self.await_dispatch_gate(operation).await?;
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
        let call =
            apply_call_profile(self.client.new_call(traced.request), profile).options(options);
        let handle = call.handle();
        let in_flight_id = if profile == FireCallProfile::DefaultApi {
            Some(self.register_in_flight(request_epoch.0, profile, handle.clone()))
        } else {
            None
        };
        let execute = call.execute();
        let execute = FIRE_REQUEST_TRACE_ID.scope(trace_id, async move {
            FIRE_REQUEST_EPOCH.scope(request_epoch.0, execute).await
        });
        let mut response = match execute.await {
            Ok(response) => response,
            Err(source) => {
                if let Some(in_flight_id) = in_flight_id {
                    self.unregister_in_flight(in_flight_id);
                }
                if handle.is_canceled() || source.kind() == WireErrorKind::Canceled {
                    trace_guard.cancel(
                        "Session superseded",
                        format!("Canceled `{operation}` after session epoch advanced"),
                    );
                    return Err(FireCoreError::StaleSessionResponse { operation });
                }
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
        if let Some(in_flight_id) = in_flight_id {
            self.unregister_in_flight(in_flight_id);
        }
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

    async fn await_dispatch_gate(&self, operation: &'static str) -> Result<(), FireCoreError> {
        let (challenge, login) = {
            let runtime = self
                .cloudflare_challenge_runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned");
            (runtime.challenge_wait(), runtime.login_wait())
        };
        if let Some(mut challenge) = challenge {
            loop {
                if let Some(outcome) = *challenge.borrow() {
                    if outcome == super::super::cf_challenge::CloudflareChallengeJoinOutcome::Failed
                    {
                        return Err(FireCoreError::CloudflareChallenge {
                            operation,
                            reason: crate::error::CloudflareChallengeFailureReason::Failed,
                        });
                    }
                    break;
                }
                if challenge.changed().await.is_err() {
                    return Err(FireCoreError::CloudflareChallenge {
                        operation,
                        reason: crate::error::CloudflareChallengeFailureReason::Failed,
                    });
                }
            }
        }
        if let Some(mut login) = login {
            loop {
                if let Some(succeeded) = *login.borrow() {
                    if !succeeded {
                        return Err(FireCoreError::LoginRequired {
                            operation,
                            message: "登录状态已失效，请重新登录。".to_string(),
                        });
                    }
                    break;
                }
                if login.changed().await.is_err() {
                    return Err(FireCoreError::LoginRequired {
                        operation,
                        message: "登录状态已失效，请重新登录。".to_string(),
                    });
                }
            }
        }
        Ok(())
    }

    fn current_epoch(&self) -> u64 {
        read_rwlock(&self.session, "session").epoch
    }

    fn last_response_auth_change(&self) -> Option<super::super::FireResponseAuthChange> {
        read_rwlock(&self.session, "session").last_response_auth_change
    }

    fn register_in_flight(
        &self,
        epoch: u64,
        profile: FireCallProfile,
        handle: openwire::CallHandle,
    ) -> u64 {
        let id = self.next_in_flight_id.fetch_add(1, Ordering::Relaxed);
        self.in_flight
            .lock()
            .expect("in-flight call mutex poisoned")
            .push(super::InFlightCall {
                id,
                epoch,
                profile,
                handle,
            });
        id
    }

    fn unregister_in_flight(&self, id: u64) {
        self.in_flight
            .lock()
            .expect("in-flight call mutex poisoned")
            .retain(|call| call.id != id);
    }

    pub(crate) fn cancel_stale_default_api(&self, current_epoch: u64) {
        let mut in_flight = self
            .in_flight
            .lock()
            .expect("in-flight call mutex poisoned");
        in_flight.retain(|call| {
            let stale = call.profile == FireCallProfile::DefaultApi && call.epoch < current_epoch;
            if stale {
                call.handle.cancel();
            }
            !stale
        });
    }
}
