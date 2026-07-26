use std::future::Future;
use std::sync::OnceLock;

use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
    BootstrapArtifacts, CookieSnapshot, PassiveLogoutTrigger, ProbeResult, SessionSnapshot,
    SignalStrength,
};
use http::{Method, StatusCode};
use serde_json::Value;
use tokio::runtime::{Builder, Handle, Runtime};
use tracing::{debug, info, warn};

use super::{
    auth_strike::StrikeDecision,
    messagebus::message_bus_requires_shared_session_key,
    network::{classify_http_status_error, expect_success, header_value, is_bad_csrf_body},
    FireCore,
};
use crate::parsing::{parse_home_state, parse_site_metadata_json};
use crate::{
    error::FireCoreError,
    json_helpers::{invalid_json, scalar_string},
    sync_utils::{read_rwlock, write_rwlock},
};

impl FireCore {
    /// After cookie handoff during login: try bootstrap refresh with a hard
    /// timeout, but never leave the UI stuck if bootstrap is slow. Cookie auth
    /// alone is enough to enter the app (fluxdo LoginReady finally semantics).
    pub async fn finalize_login_ready(&self) -> Result<SessionSnapshot, FireCoreError> {
        const LOGIN_READY_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(8);

        self.clear_cloudflare_clearance_rejected();

        if !self.snapshot().cookies.has_login_session() {
            return Ok(self.snapshot());
        }

        match tokio::time::timeout(LOGIN_READY_TIMEOUT, self.refresh_bootstrap_if_needed()).await {
            Ok(Ok(snapshot)) => Ok(snapshot),
            Ok(Err(error)) => {
                warn!(error = %error, "login-ready bootstrap refresh failed; continuing with cookies");
                Ok(self.snapshot())
            }
            Err(_) => {
                warn!("login-ready bootstrap refresh timed out; continuing with cookies");
                Ok(self.snapshot())
            }
        }
    }

    /// After CF success: publish resolved generation, force bootstrap + full
    /// app-state refresh when logged in, then notify platform subscribers
    /// (MessageBus restart / banner clear / login continue).
    /// Safe to call from sync UniFFI paths (falls back when no Tokio handle).
    pub(crate) fn schedule_post_challenge_session_rebuild(&self) {
        // Manual path bumps here; network path bumps in finish(true) right after.
        let generation_hint = self.publish_clearance_resolved_if_idle();
        let has_login = self.snapshot().cookies.has_login_session();
        let core = self.clone();
        spawn_post_challenge_task(async move {
            // Allow network finish(true) to publish generation before we notify.
            tokio::time::sleep(std::time::Duration::from_millis(30)).await;

            if !has_login {
                let generation = core
                    .cloudflare_clearance_resolved_generation()
                    .max(generation_hint);
                core.notify_clearance_resolved(generation);
                return;
            }

            // Let cookie merge settle before the rebuild wave.
            let settle = {
                let runtime = core
                    .cloudflare_challenge_runtime
                    .lock()
                    .expect("cloudflare challenge runtime mutex poisoned");
                runtime.trust_settle_remaining()
            };
            if let Some(remaining) = settle {
                tokio::time::sleep(remaining).await;
            }

            match core.refresh_bootstrap().await {
                Ok(_) => {
                    info!("post-challenge bootstrap rebuild complete");
                }
                Err(error) => {
                    warn!(error = %error, "post-challenge bootstrap rebuild failed");
                }
            }
            core.state_observers().notify_session(core.snapshot());

            // Force a full loginCompleted-style batch so CF mid-refresh does not
            // leave home/notifications stuck on a partial failure.
            if let Err(error) = core
                .app_state_refresher()
                .refresh_all_forced(fire_models::RefreshTrigger::CloudflareResolved)
                .await
            {
                warn!(error = %error, "post-challenge app state refresh failed");
            }

            let generation = core
                .cloudflare_clearance_resolved_generation()
                .max(generation_hint);
            core.notify_clearance_resolved(generation);
        });
    }

    pub async fn refresh_bootstrap_if_needed(&self) -> Result<SessionSnapshot, FireCoreError> {
        let current = self.snapshot();
        let readiness = current.readiness();
        let requires_shared_session_key =
            message_bus_requires_shared_session_key(&self.base_url, &current.bootstrap)?;
        let needs_site_metadata = !current.bootstrap.has_site_metadata;
        let needs_bootstrap_refresh = !current.bootstrap.has_preloaded_data
            || !current.bootstrap.has_site_settings
            || !readiness.has_current_user
            || (requires_shared_session_key && !readiness.has_shared_session_key);

        if !readiness.can_read_authenticated_api {
            return Ok(current);
        }

        if needs_site_metadata && !needs_bootstrap_refresh {
            if let Some(site_metadata_patch) = self.fetch_site_metadata_fallback().await {
                let snapshot = self.update_session(|session| {
                    session.bootstrap.merge_patch(&site_metadata_patch);
                    debug!(
                        phase = ?session.login_phase(),
                        readiness = ?session.readiness(),
                        "applied site metadata fallback without home refresh"
                    );
                });
                self.sync_preloaded_data_cache(&snapshot.bootstrap);
                return Ok(snapshot);
            }

            return self.refresh_bootstrap().await;
        }

        if needs_bootstrap_refresh {
            self.refresh_bootstrap().await
        } else {
            Ok(current)
        }
    }

    pub async fn refresh_bootstrap(&self) -> Result<SessionSnapshot, FireCoreError> {
        info!("refreshing bootstrap via home page request");
        let traced = self.build_home_request("refresh bootstrap")?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "refresh bootstrap", trace_id, response).await?;
        let response_username = header_value(response.headers(), "x-discourse-username");
        let html = self.read_response_text(trace_id, response).await?;
        let parsed = parse_home_state(self.base_url(), &html);
        let site_metadata_patch = if parsed.bootstrap_patch.has_site_metadata {
            None
        } else {
            self.fetch_site_metadata_fallback().await
        };

        let result = self.update_session(|session| {
            session.cookies.merge_patch(&parsed.cookies_patch);
            session.bootstrap.merge_patch(&parsed.bootstrap_patch);
            if let Some(site_metadata_patch) = site_metadata_patch.clone() {
                session.bootstrap.merge_patch(&site_metadata_patch);
            }
            if let Some(response_username) = response_username.clone() {
                session.bootstrap.merge_patch(&BootstrapArtifacts {
                    current_username: Some(response_username),
                    ..BootstrapArtifacts::default()
                });
            }
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "refreshed bootstrap over network"
            );
        });
        info!(
            username = ?result.bootstrap.current_username,
            has_preloaded = result.bootstrap.has_preloaded_data,
            has_site_metadata = result.bootstrap.has_site_metadata,
            "bootstrap refresh complete"
        );
        self.sync_preloaded_data_cache(&result.bootstrap);
        Ok(result)
    }

    pub async fn refresh_csrf_token_if_needed(&self) -> Result<SessionSnapshot, FireCoreError> {
        let current = self.snapshot();
        if current.cookies.csrf_token.is_some() {
            return Ok(current);
        }
        if !current.cookies.can_authenticate_requests() {
            debug!("skipping CSRF refresh because authenticated cookies are unavailable");
            return Ok(current);
        }

        let _refresh_guard = self.csrf_refresh.lock().await;
        let current = self.snapshot();
        if current.cookies.csrf_token.is_some() {
            return Ok(current);
        }
        if !current.cookies.can_authenticate_requests() {
            debug!("skipping CSRF refresh because authenticated cookies became unavailable");
            return Ok(current);
        }

        self.refresh_csrf_token_without_dedupe().await
    }

    pub async fn refresh_csrf_token(&self) -> Result<SessionSnapshot, FireCoreError> {
        let _refresh_guard = self.csrf_refresh.lock().await;
        self.refresh_csrf_token_without_dedupe().await
    }

    async fn refresh_csrf_token_without_dedupe(&self) -> Result<SessionSnapshot, FireCoreError> {
        info!("refreshing CSRF token");
        let traced =
            self.build_api_request("refresh csrf token", Method::GET, "/session/csrf", false)?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "refresh csrf token", trace_id, response).await?;
        let payload: Value = self
            .read_response_json("refresh csrf token", trace_id, response)
            .await?;
        let csrf = parse_csrf_token_response(&payload).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "refresh csrf token",
                source,
            }
        })?;
        if csrf.is_empty() {
            self.diagnostics.record_parse_error(
                trace_id,
                "CSRF response did not contain a usable token".to_string(),
                "csrf token was empty".to_string(),
            );
            return Err(FireCoreError::InvalidCsrfResponse);
        }

        let result = self.update_session(|session| {
            session.cookies.merge_patch(&CookieSnapshot {
                csrf_token: Some(csrf.clone()),
                ..CookieSnapshot::default()
            });
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "refreshed csrf token over network"
            );
        });
        self.clear_auth_recovery_hint("refresh csrf token");
        info!("CSRF token refreshed successfully");
        Ok(result)
    }

    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionSnapshot, FireCoreError> {
        let username = self
            .snapshot()
            .bootstrap
            .current_username
            .ok_or(FireCoreError::MissingCurrentUsername)?;
        info!(username = %username, preserve_cf_clearance, "initiating remote logout");

        if !self.snapshot().cookies.has_csrf_token() {
            let _ = self.refresh_csrf_token_if_needed().await?;
        }

        let path = format!("/session/{username}");
        let traced = self.build_api_request("logout", Method::DELETE, &path, true)?;
        let (trace_id, response) = self.execute_request(traced).await?;

        if response.status() == StatusCode::FORBIDDEN {
            let response_headers = response.headers().clone();
            let body = self.read_response_text(trace_id, response).await?;
            self.diagnostics.record_http_status_error(
                trace_id,
                StatusCode::FORBIDDEN.as_u16(),
                &body,
            );
            if is_bad_csrf_body(&body) {
                warn!("logout received BAD CSRF, refreshing token and retrying once");
                let _ = self.clear_csrf_token();
                let _ = self.refresh_csrf_token_if_needed().await?;
                let retry = self.build_api_request("logout", Method::DELETE, &path, true)?;
                let (retry_trace_id, response) = self.execute_request(retry).await?;
                let response = expect_success(self, "logout", retry_trace_id, response).await?;
                let _ = self.read_response_text(retry_trace_id, response).await?;
                return Ok(self.logout_local(preserve_cf_clearance));
            }

            return Err(classify_http_status_error(
                "logout",
                StatusCode::FORBIDDEN.as_u16(),
                &response_headers,
                body,
            ));
        }

        let response = expect_success(self, "logout", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(self.logout_local(preserve_cf_clearance))
    }
}

impl FireCore {
    async fn fetch_site_metadata_fallback(&self) -> Option<BootstrapArtifacts> {
        info!("bootstrap missing site metadata, fetching /site.json fallback");
        let traced =
            match self.build_json_get_request("fetch site metadata", "/site.json", Vec::new(), &[])
            {
                Ok(traced) => traced,
                Err(error) => {
                    warn!(error = %error, "failed to build site metadata fallback request");
                    return None;
                }
            };
        let (trace_id, response) = match self.execute_request(traced).await {
            Ok(result) => result,
            Err(error) => {
                warn!(error = %error, "site metadata fallback request failed");
                return None;
            }
        };
        let response = match expect_success(self, "fetch site metadata", trace_id, response).await {
            Ok(response) => response,
            Err(error) => {
                warn!(error = %error, "site metadata fallback returned non-success status");
                return None;
            }
        };
        let payload: Value = match self
            .read_response_json("fetch site metadata", trace_id, response)
            .await
        {
            Ok(payload) => payload,
            Err(error) => {
                warn!(error = %error, "failed to decode site metadata fallback response");
                return None;
            }
        };
        let payload_json = match serde_json::to_string(&payload) {
            Ok(payload_json) => payload_json,
            Err(error) => {
                warn!(error = %error, "failed to serialize site metadata fallback response");
                return None;
            }
        };
        let patch = parse_site_metadata_json(self.base_url(), &payload_json);
        if !patch.has_site_metadata {
            warn!("site metadata fallback completed but did not contain categories/tag metadata");
            return None;
        }
        Some(patch)
    }
}

fn parse_csrf_token_response(value: &Value) -> Result<String, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("csrf response root was not an object"))?;
    Ok(scalar_string(object.get("csrf")).unwrap_or_default())
}

impl FireCore {
    pub async fn probe_session(&self) -> Result<ProbeResult, FireCoreError> {
        let traced =
            self.build_json_get_request("probe_session", "/session/current.json", Vec::new(), &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let status = response.status();
        if status.as_u16() == 404 {
            return Ok(ProbeResult::Invalid);
        }
        let body = self.read_response_text(trace_id, response).await;
        match body {
            Ok(text) => {
                let json: Value = serde_json::from_str(&text).unwrap_or_default();
                if let Some(user) = json.get("current_user") {
                    let username = user
                        .get("username")
                        .and_then(|u| u.as_str())
                        .unwrap_or("")
                        .to_string();
                    if !username.is_empty() {
                        return Ok(ProbeResult::Valid { username });
                    }
                }
                if status.is_success() {
                    Ok(ProbeResult::Invalid)
                } else {
                    Ok(ProbeResult::Inconclusive)
                }
            }
            Err(_) => Ok(ProbeResult::Inconclusive),
        }
    }

    pub async fn passive_logout(&self, trigger: PassiveLogoutTrigger) -> Result<(), FireCoreError> {
        info!(
            source = %trigger.source,
            signal_strength = ?trigger.signal_strength,
            "initiating passive logout"
        );
        {
            let mut state = write_rwlock(&self.session, "session");
            state.auth_strike.record_passive_logout();
            state.epoch = state.epoch.saturating_add(1);
        }
        self.logout_local(true);
        Ok(())
    }

    pub(crate) fn record_auth_runtime_signal(&self, signal: AuthRuntimeSignal) {
        let signal_kind = signal.kind.clone();
        let signal_strength = signal.strength;
        let signal_source = signal.source;
        let operation = signal.operation.clone();
        let status = signal.status;
        {
            let mut state = write_rwlock(&self.session, "session");
            state.last_auth_runtime_signal = Some(signal);
        }
        info!(
            kind = ?signal_kind,
            strength = ?signal_strength,
            source = ?signal_source,
            operation = ?operation,
            status = ?status,
            "recorded auth runtime signal"
        );
    }

    pub(crate) async fn process_auth_runtime_signal(
        &self,
        signal: AuthRuntimeSignal,
        operation: &'static str,
    ) -> Option<FireCoreError> {
        let strike_strength = match signal.kind {
            AuthRuntimeSignalKind::NotLoggedInBody
            | AuthRuntimeSignalKind::DiscourseLoggedOutHeader => Some(SignalStrength::Strong),
            AuthRuntimeSignalKind::MixedLoggedOutHeader
            | AuthRuntimeSignalKind::MixedSignalCookieDeletionBlocked => Some(SignalStrength::Weak),
            _ => None,
        };
        self.record_auth_runtime_signal(signal);
        match strike_strength {
            Some(strength) => self.process_auth_strike_signal(strength, operation).await,
            None => None,
        }
    }

    pub(crate) async fn process_auth_strike_signal(
        &self,
        strength: SignalStrength,
        operation: &'static str,
    ) -> Option<FireCoreError> {
        let decision = {
            let mut state = write_rwlock(&self.session, "session");
            state.auth_strike.receive_auth_signal(strength.clone())
        };
        match decision {
            StrikeDecision::ProbeNeeded => {
                {
                    let mut state = write_rwlock(&self.session, "session");
                    state.auth_strike.probe_in_progress = true;
                }
                let probe_result = self.probe_session().await;
                {
                    let mut state = write_rwlock(&self.session, "session");
                    state.auth_strike.probe_in_progress = false;
                }
                match probe_result {
                    Ok(ProbeResult::Valid { .. }) => {
                        self.record_auth_runtime_signal(AuthRuntimeSignal {
                            kind: AuthRuntimeSignalKind::ProbeValid,
                            strength: AuthRuntimeSignalStrength::Terminal,
                            source: AuthRuntimeSignalSource::Probe,
                            operation: Some(operation.to_string()),
                            status: None,
                        });
                        info!(
                            operation,
                            "probe confirmed session valid, resetting strikes"
                        );
                        {
                            let mut state = write_rwlock(&self.session, "session");
                            state.auth_strike.reset_strikes();
                        }
                        None
                    }
                    Ok(ProbeResult::Invalid) => {
                        self.record_auth_runtime_signal(AuthRuntimeSignal {
                            kind: AuthRuntimeSignalKind::ProbeInvalid,
                            strength: AuthRuntimeSignalStrength::Terminal,
                            source: AuthRuntimeSignalSource::Probe,
                            operation: Some(operation.to_string()),
                            status: None,
                        });
                        info!(
                            operation,
                            "probe confirmed session invalid, triggering passive logout"
                        );
                        let _ = self
                            .passive_logout(PassiveLogoutTrigger {
                                source: format!("strike_probe_invalid:{operation}"),
                                signal_strength: strength,
                                cookie_diagnostic: String::new(),
                            })
                            .await;
                        Some(FireCoreError::LoginRequired {
                            operation,
                            message: "登录状态已失效，请重新登录。".to_string(),
                        })
                    }
                    Ok(ProbeResult::Inconclusive) => {
                        let strikes = {
                            let state = read_rwlock(&self.session, "session");
                            state.auth_strike.strike_count
                        };
                        if strikes >= 2 {
                            self.record_auth_runtime_signal(AuthRuntimeSignal {
                                kind: AuthRuntimeSignalKind::ProbeInconclusiveEscalated,
                                strength: AuthRuntimeSignalStrength::Terminal,
                                source: AuthRuntimeSignalSource::Probe,
                                operation: Some(operation.to_string()),
                                status: None,
                            });
                            info!(
                                operation,
                                strikes,
                                "probe inconclusive with enough strikes, triggering passive logout"
                            );
                            let _ = self
                                .passive_logout(PassiveLogoutTrigger {
                                    source: format!("strike_probe_inconclusive:{operation}"),
                                    signal_strength: strength,
                                    cookie_diagnostic: String::new(),
                                })
                                .await;
                            Some(FireCoreError::LoginRequired {
                                operation,
                                message: "登录状态已失效，请重新登录。".to_string(),
                            })
                        } else {
                            self.record_auth_runtime_signal(AuthRuntimeSignal {
                                kind: AuthRuntimeSignalKind::ProbeInconclusive,
                                strength: AuthRuntimeSignalStrength::Diagnostic,
                                source: AuthRuntimeSignalSource::Probe,
                                operation: Some(operation.to_string()),
                                status: None,
                            });
                            info!(
                                operation,
                                strikes, "probe inconclusive with few strikes, entering cooldown"
                            );
                            let mut state = write_rwlock(&self.session, "session");
                            state.auth_strike.enter_inconclusive_cooldown();
                            Some(FireCoreError::LoginRequired {
                                operation,
                                message: "登录状态已失效，请重新登录。".to_string(),
                            })
                        }
                    }
                    Err(_) => {
                        let strikes = {
                            let state = read_rwlock(&self.session, "session");
                            state.auth_strike.strike_count
                        };
                        if strikes >= 2 {
                            self.record_auth_runtime_signal(AuthRuntimeSignal {
                                kind: AuthRuntimeSignalKind::ProbeInconclusiveEscalated,
                                strength: AuthRuntimeSignalStrength::Terminal,
                                source: AuthRuntimeSignalSource::Probe,
                                operation: Some(operation.to_string()),
                                status: None,
                            });
                            let _ = self
                                .passive_logout(PassiveLogoutTrigger {
                                    source: format!("strike_probe_error:{operation}"),
                                    signal_strength: strength,
                                    cookie_diagnostic: String::new(),
                                })
                                .await;
                        } else {
                            self.record_auth_runtime_signal(AuthRuntimeSignal {
                                kind: AuthRuntimeSignalKind::ProbeInconclusive,
                                strength: AuthRuntimeSignalStrength::Diagnostic,
                                source: AuthRuntimeSignalSource::Probe,
                                operation: Some(operation.to_string()),
                                status: None,
                            });
                            let mut state = write_rwlock(&self.session, "session");
                            state.auth_strike.enter_inconclusive_cooldown();
                        }
                        Some(FireCoreError::LoginRequired {
                            operation,
                            message: "登录状态已失效，请重新登录。".to_string(),
                        })
                    }
                }
            }
            StrikeDecision::Accumulated { .. } | StrikeDecision::Ignore => None,
        }
    }
}

fn post_challenge_runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .thread_name("fire-post-challenge")
            .build()
            .expect("failed to create post-challenge runtime")
    })
}

fn spawn_post_challenge_task<F>(future: F)
where
    F: Future<Output = ()> + Send + 'static,
{
    if let Ok(handle) = Handle::try_current() {
        handle.spawn(future);
    } else {
        post_challenge_runtime().spawn(future);
    }
}
