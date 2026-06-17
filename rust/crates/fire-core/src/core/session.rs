use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
    BootstrapArtifacts, CookieSnapshot, CookieSource, CookieSweepIntent, CookieSweepPlan,
    CookieTrust, LoginFailure, LoginFailureKind, LoginFinalizationResult, LoginSyncInput,
    NuclearResetPlan, PlatformCookie, SecondFactorRequirement, SessionSnapshot,
    WebViewCookieAction, WebViewCookieInfo, WebViewLoginDecision, WebViewLoginJsResult,
    WebViewLoginPhase,
};
use serde_json::Value;
use tracing::{debug, info};

use super::{FireAuthChangeSource, FireCore};
use crate::{parsing::parse_home_state, sync_utils::read_rwlock};

pub(crate) fn classify_webview_login_result(result: WebViewLoginJsResult) -> WebViewLoginDecision {
    match result.phase {
        WebViewLoginPhase::Csrf => classify_csrf_phase(result.status, &result.body),
        WebViewLoginPhase::Hcaptcha => WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Network,
            message: Some(
                non_empty_string(result.body)
                    .unwrap_or_else(|| format!("hCaptcha create failed: HTTP {}", result.status)),
            ),
            sent_to_email: None,
            current_email: None,
        }),
        WebViewLoginPhase::Exception => WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Network,
            message: Some(
                non_empty_string(result.body)
                    .unwrap_or_else(|| "WebView login exception".to_string()),
            ),
            sent_to_email: None,
            current_email: None,
        }),
        WebViewLoginPhase::Session => classify_session_phase(result.status, &result.body),
    }
}

fn classify_csrf_phase(status: u16, body: &str) -> WebViewLoginDecision {
    if matches!(status, 403 | 429) && looks_like_cloudflare_challenge(body) {
        return WebViewLoginDecision::RetryCloudflare;
    }
    WebViewLoginDecision::Failure(LoginFailure {
        kind: LoginFailureKind::Network,
        message: Some(
            non_empty_string(body).unwrap_or_else(|| format!("CSRF request failed: HTTP {status}")),
        ),
        sent_to_email: None,
        current_email: None,
    })
}

fn classify_session_phase(status: u16, body: &str) -> WebViewLoginDecision {
    let Ok(value) = serde_json::from_str::<Value>(body) else {
        return WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Unknown,
            message: Some(format!("Discourse returned non-JSON: HTTP {status}")),
            sent_to_email: None,
            current_email: None,
        });
    };
    let Some(object) = value.as_object() else {
        return WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Unknown,
            message: Some(format!("Discourse returned non-object JSON: HTTP {status}")),
            sent_to_email: None,
            current_email: None,
        });
    };

    if let Some(reason) = object.get("reason").and_then(Value::as_str) {
        return classify_login_reason(reason, object);
    }

    if object.get("error").is_some() && object.get("user").is_none() {
        return WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Unknown,
            message: optional_string_field(object, "error"),
            sent_to_email: None,
            current_email: None,
        });
    }

    WebViewLoginDecision::Success
}

fn classify_login_reason(
    reason: &str,
    object: &serde_json::Map<String, Value>,
) -> WebViewLoginDecision {
    match reason {
        "invalid_second_factor" | "second_factor" => {
            WebViewLoginDecision::NeedSecondFactor(SecondFactorRequirement {
                totp_enabled: bool_field(object, "totp_enabled"),
                security_key_enabled: bool_field(object, "security_key_enabled"),
                backup_enabled: bool_field(object, "backup_enabled"),
                message: optional_string_field(object, "error"),
            })
        }
        "invalid_credentials" => failure(LoginFailureKind::InvalidCredentials, object, None),
        "not_activated" => failure(
            LoginFailureKind::NotActivated,
            object,
            Some((
                optional_string_field(object, "sent_to_email"),
                optional_string_field(object, "current_email"),
            )),
        ),
        "not_approved" => failure(LoginFailureKind::NotApproved, object, None),
        "expired" => failure(LoginFailureKind::PasswordExpired, object, None),
        _ => WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Unknown,
            message: optional_string_field(object, "error")
                .or_else(|| Some(format!("reason={reason}"))),
            sent_to_email: None,
            current_email: None,
        }),
    }
}

fn failure(
    kind: LoginFailureKind,
    object: &serde_json::Map<String, Value>,
    email_fields: Option<(Option<String>, Option<String>)>,
) -> WebViewLoginDecision {
    let (sent_to_email, current_email) = email_fields.unwrap_or_default();
    WebViewLoginDecision::Failure(LoginFailure {
        kind,
        message: optional_string_field(object, "error"),
        sent_to_email,
        current_email,
    })
}

fn optional_string_field(object: &serde_json::Map<String, Value>, key: &str) -> Option<String> {
    object
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn bool_field(object: &serde_json::Map<String, Value>, key: &str) -> bool {
    object.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn non_empty_string(value: impl AsRef<str>) -> Option<String> {
    let trimmed = value.as_ref().trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn looks_like_cloudflare_challenge(body: &str) -> bool {
    let lower = body.to_ascii_lowercase();
    lower.contains("cf_chl_opt")
        || (lower.contains("challenge-platform") && lower.contains("cloudflare"))
        || (lower.contains("just a moment") && lower.contains("cloudflare"))
        || lower.contains("cf-mitigated")
}

impl FireCore {
    pub fn classify_webview_login_result(
        &self,
        result: WebViewLoginJsResult,
    ) -> WebViewLoginDecision {
        classify_webview_login_result(result)
    }

    pub fn complete_cloudflare_challenge(
        &self,
        cookies: Vec<PlatformCookie>,
        fresh_cf_clearance: Option<String>,
        browser_user_agent: Option<String>,
    ) -> SessionSnapshot {
        let origin_url = url::Url::parse(self.base_url()).ok();
        let cookies = filter_cloudflare_challenge_cookies(
            cookies,
            fresh_cf_clearance.as_deref(),
            origin_url.as_ref(),
        );
        info!(
            cookie_count = cookies.len(),
            fresh_clearance = fresh_cf_clearance
                .as_deref()
                .is_some_and(|value| !value.trim().is_empty()),
            "completing cloudflare challenge via platform cookie sync"
        );
        self.update_session_advancing_epoch_if_auth_changed(
            "complete cloudflare challenge",
            FireAuthChangeSource::PlatformSync,
            |session| {
                if let Some(origin_url) = origin_url.as_ref() {
                    session.cookies.merge_platform_cookies_for_origin(
                        &cookies,
                        origin_url,
                        CookieSource::WebViewChallenge,
                        CookieTrust::Trusted,
                    );
                } else {
                    session.cookies.merge_platform_cookies(&cookies);
                }
                if let Some(browser_user_agent) =
                    browser_user_agent.clone().filter(|value| !value.is_empty())
                {
                    session.browser_user_agent = Some(browser_user_agent);
                }
                debug!(
                    phase = ?session.login_phase(),
                    readiness = ?session.readiness(),
                    "applied cloudflare challenge result"
                );
            },
        )
    }

    pub fn merge_platform_cookies(&self, cookies: Vec<PlatformCookie>) -> SessionSnapshot {
        info!(
            cookie_count = cookies.len(),
            "merging platform cookies into session"
        );
        let origin_url = url::Url::parse(self.base_url()).ok();
        self.update_session_advancing_epoch_if_auth_changed(
            "merge platform cookies",
            FireAuthChangeSource::PlatformSync,
            |session| {
                if let Some(origin_url) = origin_url.as_ref() {
                    session.cookies.merge_platform_cookies_for_origin(
                        &cookies,
                        origin_url,
                        CookieSource::WebViewBulkRead,
                        CookieTrust::Untrusted,
                    );
                } else {
                    session.cookies.merge_platform_cookies(&cookies);
                }
                debug!(
                    phase = ?session.login_phase(),
                    readiness = ?session.readiness(),
                    "merged platform cookies"
                );
            },
        )
    }

    pub fn apply_platform_cookies(&self, cookies: Vec<PlatformCookie>) -> SessionSnapshot {
        info!(
            cookie_count = cookies.len(),
            "applying platform cookies into session"
        );
        let origin_url = url::Url::parse(self.base_url()).ok();
        self.update_session_advancing_epoch_if_auth_changed(
            "apply platform cookies",
            FireAuthChangeSource::PlatformSync,
            |session| {
                if let Some(origin_url) = origin_url.as_ref() {
                    session.cookies.apply_platform_cookies_for_origin(
                        &cookies,
                        origin_url,
                        CookieSource::WebViewBulkRead,
                        CookieTrust::Untrusted,
                    );
                } else {
                    session.cookies.apply_platform_cookies(&cookies);
                }
                debug!(
                    phase = ?session.login_phase(),
                    readiness = ?session.readiness(),
                    "applied platform cookies"
                );
            },
        )
    }

    pub fn apply_cookies(&self, cookies: CookieSnapshot) -> SessionSnapshot {
        info!("applying cookie patch to session");
        self.update_session_advancing_epoch_if_auth_changed(
            "apply cookie patch",
            FireAuthChangeSource::DirectMutation,
            |session| {
                session.cookies.merge_patch(&cookies);
                debug!(
                    phase = ?session.login_phase(),
                    readiness = ?session.readiness(),
                    "updated session cookies"
                );
            },
        )
    }

    pub fn webview_priming_payload(&self, target_url: Option<String>) -> Vec<WebViewCookieAction> {
        let uri = target_url
            .as_deref()
            .and_then(|value| url::Url::parse(value).ok())
            .or_else(|| url::Url::parse(self.base_url()).ok());
        let Some(uri) = uri else {
            return Vec::new();
        };

        let snapshot = self.snapshot();
        snapshot.cookies.webview_priming_payload(&uri)
    }

    pub fn cookie_sweep_plan(
        &self,
        target_url: Option<String>,
        name: String,
        webview_cookies: Vec<WebViewCookieInfo>,
    ) -> CookieSweepPlan {
        let uri = target_url
            .as_deref()
            .and_then(|value| url::Url::parse(value).ok())
            .or_else(|| url::Url::parse(self.base_url()).ok());
        let Some(uri) = uri else {
            return CookieSweepPlan {
                name,
                ..CookieSweepPlan::default()
            };
        };

        let snapshot = self.snapshot();
        snapshot
            .cookies
            .cookie_sweep_plan(&uri, &name, &webview_cookies)
    }

    pub fn cookie_nuclear_reset_plan(
        &self,
        target_url: Option<String>,
        webview_cookies: Vec<WebViewCookieInfo>,
    ) -> NuclearResetPlan {
        let uri = target_url
            .as_deref()
            .and_then(|value| url::Url::parse(value).ok())
            .or_else(|| url::Url::parse(self.base_url()).ok());
        let Some(uri) = uri else {
            return NuclearResetPlan::default();
        };

        let snapshot = self.snapshot();
        snapshot
            .cookies
            .cookie_nuclear_reset_plan(&uri, &webview_cookies)
    }

    pub fn commit_cookie_sweep_result(
        &self,
        target_url: Option<String>,
        name: String,
        intent: CookieSweepIntent,
        webview_cookies: Vec<WebViewCookieInfo>,
    ) -> SessionSnapshot {
        let uri = target_url
            .as_deref()
            .and_then(|value| url::Url::parse(value).ok())
            .or_else(|| url::Url::parse(self.base_url()).ok());
        let Some(uri) = uri else {
            return self.snapshot();
        };

        self.update_session_advancing_epoch_if_auth_changed(
            "commit cookie sweep result",
            FireAuthChangeSource::PlatformSync,
            |session| {
                session
                    .cookies
                    .commit_cookie_sweep_result(&uri, &name, intent, &webview_cookies);
            },
        )
    }

    pub fn apply_bootstrap(&self, bootstrap: BootstrapArtifacts) -> SessionSnapshot {
        let snapshot = self.update_session(|session| {
            session.bootstrap.merge_patch(&bootstrap);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "updated bootstrap artifacts"
            );
        });
        if bootstrap.preloaded_json.is_some() || bootstrap.has_preloaded_data {
            self.sync_preloaded_data_cache(&snapshot.bootstrap);
        }
        snapshot
    }

    pub fn apply_csrf_token(&self, csrf_token: String) -> SessionSnapshot {
        self.update_session(|session| {
            session.cookies.merge_patch(&CookieSnapshot {
                csrf_token: Some(csrf_token),
                ..CookieSnapshot::default()
            });
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "updated csrf token"
            );
        })
    }

    pub fn clear_csrf_token(&self) -> SessionSnapshot {
        self.update_session(|session| {
            session.cookies.csrf_token = None;
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "cleared csrf token"
            );
        })
    }

    pub fn apply_home_html(&self, html: String) -> SessionSnapshot {
        let parsed = parse_home_state(self.base_url(), &html);
        let snapshot = self.update_session(|session| {
            session.cookies.merge_patch(&parsed.cookies_patch);
            session.bootstrap.merge_patch(&parsed.bootstrap_patch);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "applied home html bootstrap"
            );
        });
        self.sync_preloaded_data_cache(&snapshot.bootstrap);
        snapshot
    }

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
        self.clear_current_auth_scope_list_caches();
        self.stop_message_bus(true);
        self.clear_notification_state();
        self.clear_topic_presence_state();
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

        if readiness.has_current_user || readiness.can_read_authenticated_api {
            return fire_models::LoginStateDetermination::LoggedIn {
                username: snapshot
                    .bootstrap
                    .current_username
                    .clone()
                    .unwrap_or_else(|| snapshot.profile_display_name()),
                user_id: snapshot.bootstrap.current_user_id.unwrap_or(0),
            };
        }

        if !readiness.has_login_cookie {
            return fire_models::LoginStateDetermination::NotLoggedIn;
        }

        fire_models::LoginStateDetermination::NotLoggedIn
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

fn filter_cloudflare_challenge_cookies(
    cookies: Vec<PlatformCookie>,
    fresh_cf_clearance: Option<&str>,
    origin_url: Option<&url::Url>,
) -> Vec<PlatformCookie> {
    let fresh_cf_clearance = fresh_cf_clearance
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let mut filtered = cookies
        .into_iter()
        .filter(|cookie| {
            if cookie.name.eq_ignore_ascii_case("cf_clearance") {
                return fresh_cf_clearance.is_some_and(|fresh| cookie.value.trim() == fresh);
            }
            true
        })
        .collect::<Vec<_>>();

    let Some(fresh_cf_clearance) = fresh_cf_clearance else {
        return filtered;
    };
    let Some(origin_url) = origin_url else {
        return filtered;
    };

    let has_origin_scoped_clearance = filtered.iter().any(|cookie| {
        cookie.name.eq_ignore_ascii_case("cf_clearance")
            && cookie.value.trim() == fresh_cf_clearance
            && platform_cookie_matches_origin(cookie, origin_url)
    });
    if has_origin_scoped_clearance {
        return filtered;
    }

    filtered.retain(|cookie| !cookie.name.eq_ignore_ascii_case("cf_clearance"));
    if let Some(host) = origin_url.host_str() {
        filtered.push(PlatformCookie {
            name: "cf_clearance".to_string(),
            value: fresh_cf_clearance.to_string(),
            domain: Some(host.to_ascii_lowercase()),
            path: Some("/".to_string()),
            expires_at_unix_ms: None,
            same_site: Some("None".to_string()),
        });
    }
    filtered
}

fn platform_cookie_matches_origin(cookie: &PlatformCookie, origin_url: &url::Url) -> bool {
    if cookie.is_expired_now() || cookie.value.trim().is_empty() {
        return false;
    }
    let Some(request_host) = origin_url
        .host_str()
        .map(|value| value.to_ascii_lowercase())
    else {
        return false;
    };
    let Some(raw_domain) = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return true;
    };
    let domain = raw_domain.trim_start_matches('.').to_ascii_lowercase();
    if domain.is_empty() {
        return false;
    }
    if raw_domain.starts_with('.') {
        if request_host != domain && !request_host.ends_with(&format!(".{domain}")) {
            return false;
        }
    } else if request_host != domain {
        return false;
    }

    let cookie_path = cookie
        .path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("/");
    cookie_path == "/"
}
