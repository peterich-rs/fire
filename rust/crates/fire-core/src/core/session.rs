use fire_models::{
    BootstrapArtifacts, CookieSnapshot, LoginFinalizationResult, LoginSyncInput, PlatformCookie,
    SessionSnapshot,
};
use tracing::{debug, info};

use super::{FireAuthChangeSource, FireCore};
use crate::{parsing::parse_home_state, sync_utils::read_rwlock};

impl FireCore {
    pub fn merge_platform_cookies(&self, cookies: Vec<PlatformCookie>) -> SessionSnapshot {
        info!(
            cookie_count = cookies.len(),
            "merging platform cookies into session"
        );
        self.update_session_advancing_epoch_if_auth_changed(
            "merge platform cookies",
            FireAuthChangeSource::PlatformSync,
            |session| {
                session.cookies.merge_platform_cookies(&cookies);
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
        self.update_session_advancing_epoch_if_auth_changed(
            "apply platform cookies",
            FireAuthChangeSource::PlatformSync,
            |session| {
                session.cookies.apply_platform_cookies(&cookies);
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

    pub fn apply_bootstrap(&self, bootstrap: BootstrapArtifacts) -> SessionSnapshot {
        self.update_session(|session| {
            session.bootstrap.merge_patch(&bootstrap);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "updated bootstrap artifacts"
            );
        })
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
        self.update_session(|session| {
            session.cookies.merge_patch(&parsed.cookies_patch);
            session.bootstrap.merge_patch(&parsed.bootstrap_patch);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "applied home html bootstrap"
            );
        })
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
        self.update_session_advancing_epoch_if_auth_changed(
            "sync login context",
            FireAuthChangeSource::PlatformSync,
            |session| {
                session.cookies.apply_platform_cookies(&input.cookies);
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

                if let Some(parsed_html) = parsed_html {
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
        )
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
                session.cookies.scored_apply_platform_cookies(
                    &cookies,
                    &host,
                    allow_low_confidence_session_cookies,
                );
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
        self.stop_message_bus(true);
        self.clear_notification_state();
        self.clear_topic_presence_state();
        self.update_session_advancing_epoch_if_auth_changed(
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
        )
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

        if readiness.has_current_user {
            if let (Some(username), Some(user_id)) = (
                snapshot.bootstrap.current_username.as_deref(),
                snapshot.bootstrap.current_user_id,
            ) {
                return fire_models::LoginStateDetermination::LoggedIn {
                    username: username.to_string(),
                    user_id,
                };
            }
        }

        if !readiness.has_login_cookie {
            return fire_models::LoginStateDetermination::NotLoggedIn;
        }

        fire_models::LoginStateDetermination::NotLoggedIn
    }

    pub async fn determine_login_state_with_probe(&self) -> fire_models::LoginStateDetermination {
        let initial = self.determine_login_state();
        if !matches!(initial, fire_models::LoginStateDetermination::NotLoggedIn) {
            return initial;
        }

        let snapshot = self.snapshot();
        if !snapshot.cookies.has_login_session() {
            return fire_models::LoginStateDetermination::NotLoggedIn;
        }

        match self.probe_session().await {
            Ok(probe) => match probe {
                fire_models::ProbeResult::Valid { username } => {
                    self.update_session(|session| {
                        session.bootstrap.current_username = Some(username.clone());
                    });
                    fire_models::LoginStateDetermination::LoggedIn {
                        username,
                        user_id: snapshot.bootstrap.current_user_id.unwrap_or(0),
                    }
                }
                fire_models::ProbeResult::Invalid => {
                    let _ = self.logout_local(true);
                    fire_models::LoginStateDetermination::SessionExpired
                }
                fire_models::ProbeResult::Inconclusive => {
                    fire_models::LoginStateDetermination::NetworkErrorPreserveState
                }
            },
            Err(_) => fire_models::LoginStateDetermination::NetworkErrorPreserveState,
        }
    }
}
