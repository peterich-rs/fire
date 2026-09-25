use fire_models::{
    CookieSnapshot, CookieSource, CookieSweepIntent, CookieSweepPlan, CookieTrust,
    NuclearResetPlan, PlatformCookie, SessionSnapshot, WebViewCookieAction, WebViewCookieInfo,
};
use tracing::{debug, info};

use super::super::{FireAuthChangeSource, FireCore};

impl FireCore {
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
}
