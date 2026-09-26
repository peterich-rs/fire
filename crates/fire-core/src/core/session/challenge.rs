use fire_models::{
    CanonicalCookie, CookieSameSite, CookieSource, CookieTrust, PlatformCookie, SessionSnapshot,
};
use tracing::{debug, info};

use super::super::{FireAuthChangeSource, FireCore};

impl FireCore {
    pub fn complete_cloudflare_challenge(
        &self,
        cookies: Vec<PlatformCookie>,
        fresh_cf_clearance: Option<String>,
        browser_user_agent: Option<String>,
    ) -> SessionSnapshot {
        let origin_url = url::Url::parse(self.base_url()).ok();
        let fresh_cf_clearance = fresh_cf_clearance
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string);
        let cookies = filter_cloudflare_challenge_cookies(
            cookies,
            fresh_cf_clearance.as_deref(),
            origin_url.as_ref(),
        );
        info!(
            cookie_count = cookies.len(),
            fresh_clearance = fresh_cf_clearance.is_some(),
            "completing cloudflare challenge via platform cookie sync"
        );
        let snapshot = self.update_session_advancing_epoch_if_auth_changed(
            "complete cloudflare challenge",
            FireAuthChangeSource::PlatformSync,
            |session| {
                let (clearance_cookies, other_cookies): (Vec<_>, Vec<_>) = cookies
                    .into_iter()
                    .partition(|cookie| cookie.name.eq_ignore_ascii_case("cf_clearance"));
                if let Some(origin_url) = origin_url.as_ref() {
                    session.cookies.merge_platform_cookies_for_origin(
                        &other_cookies,
                        origin_url,
                        CookieSource::WebViewChallenge,
                        CookieTrust::Trusted,
                    );
                    if let Some(fresh) = fresh_cf_clearance.as_deref() {
                        session.cookies.replace_verified_cf_clearance(
                            origin_url,
                            verified_cf_clearance_cookie(
                                fresh,
                                origin_url,
                                clearance_cookies.first(),
                            ),
                        );
                    }
                } else {
                    session.cookies.merge_platform_cookies(&other_cookies);
                    if let Some(fresh) = fresh_cf_clearance.clone() {
                        if session.cookies.should_write_cf_clearance(&fresh, true) {
                            session.cookies.cf_clearance = Some(fresh);
                        }
                    }
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
        );
        // Network-owned challenges publish recovery after the retry, not here.
        let should_rebuild = {
            let runtime = self
                .cloudflare_challenge_runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned");
            !runtime.in_progress() && !runtime.has_pending_retry()
        };
        if should_rebuild {
            // Idle / platform-owned completion publishes immediately so hosts
            // can observe the generation before the async rebuild finishes.
            self.publish_clearance_resolved_if_idle();
            self.schedule_post_challenge_session_rebuild();
        }
        snapshot
    }
}

fn verified_cf_clearance_cookie(
    fresh: &str,
    origin_url: &url::Url,
    platform: Option<&PlatformCookie>,
) -> CanonicalCookie {
    let mut canonical = CanonicalCookie::new("cf_clearance", fresh, origin_url.as_str());
    canonical.secure = origin_url.scheme() == "https";
    canonical.same_site = if canonical.secure {
        CookieSameSite::None
    } else {
        CookieSameSite::Lax
    };
    canonical.source = CookieSource::WebViewChallenge;
    if let Some(platform) = platform {
        canonical.expires_at_unix_ms = platform.expires_at_unix_ms;
        if let Some(domain) = platform
            .domain
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let normalized = domain.trim_start_matches('.').to_ascii_lowercase();
            if domain.starts_with('.') {
                canonical.host_only = false;
                canonical.domain = Some(format!(".{normalized}"));
            } else {
                canonical.host_only = true;
                canonical.domain = None;
            }
        }
    } else if let Some(host) = origin_url.host_str() {
        canonical.host_only = false;
        canonical.domain = Some(format!(
            ".{}",
            host.trim_start_matches('.').to_ascii_lowercase()
        ));
    }
    canonical
}

fn is_cloudflare_related_cookie_name(name: &str) -> bool {
    let lower = name.trim().to_ascii_lowercase();
    lower == "cf_clearance"
        || lower == "_cfuvid"
        || lower.starts_with("cf_")
        || lower.starts_with("__cf")
}

fn filter_cloudflare_challenge_cookies(
    cookies: Vec<PlatformCookie>,
    fresh_cf_clearance: Option<&str>,
    origin_url: Option<&url::Url>,
) -> Vec<PlatformCookie> {
    let fresh_cf_clearance = fresh_cf_clearance
        .map(str::trim)
        .filter(|value| !value.is_empty());
    // Challenge completion must never rewrite Discourse identity cookies.
    // Only CF edge cookies flow WV → jar on this path (fluxdo excludes auth).
    let mut filtered = cookies
        .into_iter()
        .filter(|cookie| {
            if !is_cloudflare_related_cookie_name(&cookie.name) {
                return false;
            }
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
