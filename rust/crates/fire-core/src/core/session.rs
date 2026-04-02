use fire_models::{
    BootstrapArtifacts, CookieSnapshot, LoginSyncInput, PlatformCookie, SessionSnapshot,
};
use tracing::{debug, info};

use super::FireCore;
use crate::{parsing::parse_home_state, sync_utils::read_rwlock};

impl FireCore {
    pub fn merge_platform_cookies(&self, cookies: Vec<PlatformCookie>) -> SessionSnapshot {
        info!(
            cookie_count = cookies.len(),
            "merging platform cookies into session"
        );
        self.update_session(|session| {
            session.cookies.merge_platform_cookies(&cookies);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "merged platform cookies"
            );
        })
    }

    pub fn apply_platform_cookies(&self, cookies: Vec<PlatformCookie>) -> SessionSnapshot {
        info!(
            cookie_count = cookies.len(),
            "applying platform cookies into session"
        );
        self.update_session(|session| {
            session.cookies.apply_platform_cookies(&cookies);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "applied platform cookies"
            );
        })
    }

    pub fn apply_cookies(&self, cookies: CookieSnapshot) -> SessionSnapshot {
        info!("applying cookie patch to session");
        self.update_session(|session| {
            session.cookies.merge_patch(&cookies);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "updated session cookies"
            );
        })
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
        self.update_session(|session| {
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
        })
    }

    pub fn logout_local(&self, preserve_cf_clearance: bool) -> SessionSnapshot {
        info!(preserve_cf_clearance, "clearing local login state");
        self.stop_message_bus(true);
        self.clear_notification_state();
        self.clear_topic_presence_state();
        self.update_session(|session| {
            session.clear_login_state(preserve_cf_clearance);
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                preserve_cf_clearance,
                "cleared local login state"
            );
        })
    }

    pub fn has_login_session(&self) -> bool {
        read_rwlock(&self.session, "session")
            .cookies
            .has_login_session()
    }
}
