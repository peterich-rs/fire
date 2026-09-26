use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
    BootstrapArtifacts, CookieSnapshot, CookieSource, CookieTrust, LoginFinalizationResult,
    LoginSyncInput, PlatformCookie, SessionSnapshot,
};
use tracing::{debug, info};

use super::super::{FireAuthChangeSource, FireCore};
use crate::{parsing::parse_home_state, sync_utils::read_rwlock};

impl FireCore {
    pub fn sync_login_context(&self, input: LoginSyncInput) -> SessionSnapshot {
        info!(
            cookie_count = input.cookies.len(),
            has_username = input.username.is_some(),
            has_csrf = input.csrf_token.is_some(),
            has_home_html = input
                .home_html
                .as_ref()
                .is_some_and(|html| !html.is_empty()),
            "syncing platform login context"
        );
        let parsed_html = input
            .home_html
            .as_deref()
            .map(|html| parse_home_state(self.base_url(), html));
        let has_parsed_html = parsed_html.is_some();
        let cookie_origin_url = input
            .current_url
            .as_deref()
            .and_then(|value| url::Url::parse(value).ok())
            .or_else(|| url::Url::parse(self.base_url()).ok());
        let snapshot = self.update_session_advancing_epoch_if_auth_changed(
            "sync login context",
            FireAuthChangeSource::PlatformSync,
            |session| {
                if let Some(origin_url) = cookie_origin_url.as_ref() {
                    session.cookies.apply_platform_cookies_for_origin(
                        &input.cookies,
                        origin_url,
                        CookieSource::WebViewLogin,
                        CookieTrust::Trusted,
                    );
                } else {
                    session.cookies.apply_platform_cookies(&input.cookies);
                }
                if let Some(browser_user_agent) = input
                    .browser_user_agent
                    .clone()
                    .filter(|value| !value.is_empty())
                {
                    session.browser_user_agent = Some(browser_user_agent);
                }

                if let Some(csrf_token) = input.csrf_token {
                    session.cookies.merge_patch(&CookieSnapshot {
                        csrf_token: Some(csrf_token),
                        last_challenged_cf_clearance: None,
                        ..CookieSnapshot::default()
                    });
                }

                if let Some(username) = input.username {
                    session.bootstrap.merge_patch(&BootstrapArtifacts {
                        current_username: Some(username),
                        ..BootstrapArtifacts::default()
                    });
                }

                if let Some(parsed_html) = parsed_html.as_ref() {
                    session.cookies.merge_patch(&parsed_html.cookies_patch);
                    session.bootstrap.merge_patch(&parsed_html.bootstrap_patch);
                }

                debug!(
                    phase = ?session.login_phase(),
                    readiness = ?session.readiness(),
                    cookie_count = input.cookies.len(),
                    has_home_html = input.home_html.as_ref().is_some_and(|html| !html.is_empty()),
                    "synced platform login context"
                );
            },
        );
        if has_parsed_html {
            self.sync_preloaded_data_cache(&snapshot.bootstrap);
        }
        snapshot
    }

    pub fn finalize_login_from_webview(
        &self,
        username: String,
        csrf_token: Option<String>,
        raw_preloaded_html: Option<String>,
        browser_user_agent: Option<String>,
        cookies: Vec<PlatformCookie>,
        allow_low_confidence_session_cookies: bool,
    ) -> LoginFinalizationResult {
        let base_url = self.base_url();
        let host = url::Url::parse(base_url)
            .ok()
            .and_then(|u| u.host_str().map(|h| h.to_string()))
            .unwrap_or_default();

        let webview_t_token = cookies
            .iter()
            .find(|c| c.name == "_t")
            .map(|c| c.value.clone());

        self.update_session_advancing_epoch_if_auth_changed(
            "finalize login from webview",
            FireAuthChangeSource::PlatformSync,
            |session| {
                if let Ok(origin_url) = url::Url::parse(base_url) {
                    session.cookies.scored_apply_platform_cookies_for_origin(
                        &cookies,
                        &origin_url,
                        CookieSource::WebViewLogin,
                        CookieTrust::Trusted,
                        allow_low_confidence_session_cookies,
                    );
                } else {
                    session.cookies.scored_apply_platform_cookies(
                        &cookies,
                        &host,
                        allow_low_confidence_session_cookies,
                    );
                }
                debug!(
                    phase = ?session.login_phase(),
                    readiness = ?session.readiness(),
                    "applied scored platform cookies"
                );
            },
        );

        let jar_t_after = {
            let state = read_rwlock(&self.session, "session");
            state.snapshot.cookies.t_token.clone()
        };

        let t_token_verified = match (&webview_t_token, &jar_t_after) {
            (Some(wv), Some(jar)) => wv == jar,
            (None, _) => true,
            (_, None) => false,
        };

        {
            let snapshot = self.update_session(|session| {
                if !username.is_empty() {
                    session.bootstrap.current_username = Some(username);
                }
                if let Some(ref csrf) = csrf_token {
                    session.cookies.csrf_token = Some(csrf.clone());
                }
                if let Some(ref ua) = browser_user_agent {
                    session.browser_user_agent = Some(ua.clone());
                }
            });
            debug!(
                phase = ?snapshot.login_phase(),
                readiness = ?snapshot.readiness(),
                "applied username, csrf, and browser UA"
            );
        }

        if let Some(html) = raw_preloaded_html {
            self.apply_home_html(html);
        }

        let snapshot = self.snapshot();
        let success = snapshot.cookies.has_login_session();

        LoginFinalizationResult {
            success,
            session: snapshot,
            t_token_verified,
            fingerprint_wait_needed: true,
        }
    }

    pub fn logout_local(&self, preserve_cf_clearance: bool) -> SessionSnapshot {
        info!(preserve_cf_clearance, "clearing local login state");
        if let Some(handler) = self.user_api_key_crypto.get() {
            (handler.clear_api_key)();
        }
        self.clear_current_auth_scope_list_caches();
        self.stop_message_bus(true);
        self.clear_notification_state();
        self.clear_topic_presence_state();
        self.clear_topic_tracking_state();
        self.clear_chat_list_runtime();
        self.clear_chat_channel_runtime();
        self.reset_session_browser_transport();
        let snapshot = self.update_session_advancing_epoch_if_auth_changed(
            "logout local",
            FireAuthChangeSource::DirectMutation,
            |session| {
                session.clear_login_state(preserve_cf_clearance);
                debug!(
                    phase = ?session.login_phase(),
                    readiness = ?session.readiness(),
                    preserve_cf_clearance,
                    "cleared local login state"
                );
            },
        );
        self.reset_preloaded_data_cache();
        self.reset_current_home_topic_list_scope();
        self.state_observers().notify_session(snapshot.clone());
        snapshot
    }

    fn clear_current_auth_scope_list_caches(&self) {
        let auth_scope_hash = self.current_auth_scope_hash();
        let result = self
            .shared_store
            .lock()
            .expect("shared store mutex poisoned")
            .clear_list_caches(&auth_scope_hash);
        if let Err(error) = result {
            tracing::warn!(error = %error, "failed to clear offline list caches during logout");
        }
    }

    pub fn has_login_session(&self) -> bool {
        read_rwlock(&self.session, "session")
            .snapshot
            .cookies
            .has_login_session()
    }

    pub fn determine_login_state(&self) -> fire_models::LoginStateDetermination {
        let snapshot = self.snapshot();
        let readiness = snapshot.readiness();
        let cached_user = self
            .preloaded_data
            .get()
            .and_then(|service| service.get_cached_user());

        if readiness.has_current_user || readiness.can_read_authenticated_api {
            return fire_models::LoginStateDetermination::LoggedIn {
                username: snapshot
                    .bootstrap
                    .current_username
                    .clone()
                    .or_else(|| cached_user.as_ref().map(|user| user.username.clone()))
                    .unwrap_or_else(|| snapshot.profile_display_name()),
                user_id: snapshot
                    .bootstrap
                    .current_user_id
                    .or_else(|| cached_user.as_ref().map(|user| user.id))
                    .unwrap_or(0),
            };
        }

        if !readiness.has_login_cookie {
            return fire_models::LoginStateDetermination::NotLoggedIn;
        }

        fire_models::LoginStateDetermination::NetworkErrorPreserveState
    }

    pub async fn determine_login_state_with_probe(&self) -> fire_models::LoginStateDetermination {
        let snapshot = self.snapshot();
        let readiness = snapshot.readiness();
        let fresh_current_user = self
            .preloaded_data
            .get()
            .and_then(|service| service.get_current_user());

        if let Some(current_user) = fresh_current_user {
            if readiness.can_read_authenticated_api {
                return fire_models::LoginStateDetermination::LoggedIn {
                    username: current_user.username,
                    user_id: current_user.id,
                };
            }
        }

        if !snapshot.cookies.has_login_session() {
            return fire_models::LoginStateDetermination::NotLoggedIn;
        }

        match self.probe_session().await {
            Ok(probe) => match probe {
                fire_models::ProbeResult::Valid { username } => {
                    self.record_auth_runtime_signal(AuthRuntimeSignal {
                        kind: AuthRuntimeSignalKind::ProbeValid,
                        strength: AuthRuntimeSignalStrength::Terminal,
                        source: AuthRuntimeSignalSource::StartupAuthority,
                        operation: Some("determine_login_state_with_probe".to_string()),
                        status: None,
                    });
                    self.note_native_probe_success();
                    self.update_session(|session| {
                        session.bootstrap.current_username = Some(username.clone());
                    });
                    fire_models::LoginStateDetermination::LoggedIn {
                        username,
                        user_id: snapshot.bootstrap.current_user_id.unwrap_or(0),
                    }
                }
                fire_models::ProbeResult::Invalid => {
                    self.record_auth_runtime_signal(AuthRuntimeSignal {
                        kind: AuthRuntimeSignalKind::ProbeInvalid,
                        strength: AuthRuntimeSignalStrength::Terminal,
                        source: AuthRuntimeSignalSource::StartupAuthority,
                        operation: Some("determine_login_state_with_probe".to_string()),
                        status: None,
                    });
                    let _ = self.logout_local(true);
                    fire_models::LoginStateDetermination::SessionExpired
                }
                fire_models::ProbeResult::Inconclusive => {
                    self.record_auth_runtime_signal(AuthRuntimeSignal {
                        kind: AuthRuntimeSignalKind::ProbeInconclusive,
                        strength: AuthRuntimeSignalStrength::Diagnostic,
                        source: AuthRuntimeSignalSource::StartupAuthority,
                        operation: Some("determine_login_state_with_probe".to_string()),
                        status: None,
                    });
                    fire_models::LoginStateDetermination::NetworkErrorPreserveState
                }
            },
            Err(_) => {
                self.record_auth_runtime_signal(AuthRuntimeSignal {
                    kind: AuthRuntimeSignalKind::ProbeInconclusive,
                    strength: AuthRuntimeSignalStrength::Diagnostic,
                    source: AuthRuntimeSignalSource::StartupAuthority,
                    operation: Some("determine_login_state_with_probe".to_string()),
                    status: None,
                });
                fire_models::LoginStateDetermination::NetworkErrorPreserveState
            }
        }
    }
}
