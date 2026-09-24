use serde::{Deserialize, Serialize};

use crate::normalize_cf_clearance_value;

use super::canonical::{
    current_unix_ms, normalized_cookie_domain, normalized_cookie_path, origin_url_for_host,
    CanonicalCookie, CookieSameSite,
};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum CookieSweepIntent {
    #[default]
    EnsureUnique,
    Delete,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebViewCookieInfo {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub host_only: Option<bool>,
    pub secure: Option<bool>,
    pub http_only: Option<bool>,
    pub same_site: Option<CookieSameSite>,
    pub expires_at_unix_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum WebViewCookieAction {
    SetRaw {
        url: String,
        set_cookie: String,
    },
    DeleteExact {
        url: String,
        name: String,
        domain: Option<String>,
        path: String,
    },
    DeleteByName {
        url: String,
        name: String,
    },
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookieSweepPlan {
    pub name: String,
    pub intent: CookieSweepIntent,
    pub actions: Vec<WebViewCookieAction>,
    pub selected_winner: Option<CanonicalCookie>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NuclearResetPlan {
    pub actions: Vec<WebViewCookieAction>,
}

pub(super) fn is_critical_cookie_name(name: &str) -> bool {
    matches!(
        name,
        "_t" | "_forum_session" | "cf_clearance" | "_cfuvid" | "h_captcha_temp_id"
    )
}

pub(super) fn is_cloudflare_clearance_cookie_name(name: &str) -> bool {
    name.eq_ignore_ascii_case("cf_clearance")
}

#[allow(dead_code)]
pub(super) fn select_freshest_webview_cookie_info<'a>(
    variants: &[&'a WebViewCookieInfo],
) -> Option<&'a WebViewCookieInfo> {
    variants
        .iter()
        .copied()
        .filter(|cookie| !cookie.value.trim().is_empty())
        .max_by(|left, right| {
            webview_cookie_freshness_score(left).cmp(&webview_cookie_freshness_score(right))
        })
}

fn webview_cookie_freshness_score(cookie: &WebViewCookieInfo) -> (u8, i64, usize) {
    let now_unix_ms = current_unix_ms();
    let unexpired = cookie
        .expires_at_unix_ms
        .is_none_or(|expires_at_unix_ms| expires_at_unix_ms > now_unix_ms)
        as u8;
    // Later expiresDate wins for cf_clearance multi-variant selection.
    let expiry = cookie.expires_at_unix_ms.unwrap_or(0);
    (unexpired, expiry, cookie.value.len())
}

pub(super) fn matching_webview_cookie_infos<'a>(
    cookies: &'a [WebViewCookieInfo],
    name: &str,
) -> Vec<&'a WebViewCookieInfo> {
    cookies
        .iter()
        .filter(|cookie| cookie.name == name)
        .collect::<Vec<_>>()
}

pub(super) fn select_sweep_winner(
    uri: &url::Url,
    canonical: Option<&CanonicalCookie>,
    variants: &[&WebViewCookieInfo],
) -> Option<CanonicalCookie> {
    // A healthy jar incumbent is authoritative for cf_clearance. Do not promote
    // a different WebView variant just because it expires later.
    if canonical.is_some_and(|cookie| is_cloudflare_clearance_cookie_name(&cookie.name))
        || variants
            .first()
            .is_some_and(|cookie| is_cloudflare_clearance_cookie_name(&cookie.name))
    {
        if let Some(canonical) = canonical {
            if let Some(matching) = variants.iter().find(|cookie| {
                normalize_cf_clearance_value(&cookie.value)
                    == normalize_cf_clearance_value(&canonical.value)
            }) {
                return canonical_cookie_from_webview_info(matching, uri, Some(canonical));
            }
            return Some(canonical.clone());
        }
        return variants
            .iter()
            .find(|cookie| !cookie.value.trim().is_empty())
            .and_then(|winner| canonical_cookie_from_webview_info(winner, uri, None));
    }

    let Some(canonical) = canonical else {
        return variants
            .iter()
            .max_by(|left, right| {
                webview_cookie_info_score(left).cmp(&webview_cookie_info_score(right))
            })
            .and_then(|winner| canonical_cookie_from_webview_info(winner, uri, None));
    };

    if variants.is_empty() {
        return Some(canonical.clone());
    }

    let has_canonical_value = variants
        .iter()
        .any(|variant| variant.value == canonical.value);
    if variants.len() > 1 && has_canonical_value {
        return variants
            .iter()
            .filter(|variant| variant.value != canonical.value)
            .max_by(|left, right| {
                webview_cookie_info_score(left).cmp(&webview_cookie_info_score(right))
            })
            .and_then(|winner| canonical_cookie_from_webview_info(winner, uri, Some(canonical)))
            .or_else(|| Some(canonical.clone()));
    }

    Some(canonical.clone())
}

pub(super) fn variants_match_selected_winner(
    variants: &[&WebViewCookieInfo],
    selected_winner: Option<&CanonicalCookie>,
) -> bool {
    match (variants, selected_winner) {
        ([variant], Some(winner)) => {
            variant.value == winner.value
                && variant.path.as_deref().unwrap_or("/") == normalized_cookie_path(&winner.path)
                && webview_info_domain_matches_winner(variant, winner)
        }
        ([], None) => true,
        _ => false,
    }
}

pub(super) fn webview_info_domain_matches_winner(
    variant: &WebViewCookieInfo,
    winner: &CanonicalCookie,
) -> bool {
    match (
        variant.host_only,
        variant.domain.as_deref(),
        winner.host_only,
    ) {
        (Some(true), _, true) => true,
        (Some(false), Some(domain), false) => {
            normalized_cookie_domain(Some(domain)) == winner.normalized_domain()
        }
        (None, None, true) => true,
        (_, Some(domain), _) => {
            normalized_cookie_domain(Some(domain)) == winner.normalized_domain()
        }
        _ => false,
    }
}

pub(super) fn delete_actions_for_variants(
    uri: &url::Url,
    variants: &[&WebViewCookieInfo],
) -> Vec<WebViewCookieAction> {
    if variants.is_empty() {
        return Vec::new();
    }

    let mut actions = Vec::new();
    for variant in variants {
        let name = variant.name.clone();
        if variant.domain.is_some() || variant.path.is_some() || variant.host_only.is_some() {
            actions.push(WebViewCookieAction::DeleteExact {
                url: uri.as_str().to_string(),
                name,
                domain: variant.domain.clone(),
                path: variant.path.clone().unwrap_or_else(|| "/".to_string()),
            });
        } else if !actions.iter().any(|action| {
            matches!(
                action,
                WebViewCookieAction::DeleteByName {
                    name: existing_name,
                    ..
                } if existing_name == &name
            )
        }) {
            actions.push(WebViewCookieAction::DeleteByName {
                url: uri.as_str().to_string(),
                name,
            });
        }
    }
    actions
}

pub(super) fn canonical_cookie_from_webview_info(
    info: &WebViewCookieInfo,
    uri: &url::Url,
    canonical_template: Option<&CanonicalCookie>,
) -> Option<CanonicalCookie> {
    if info.name.trim().is_empty() {
        return None;
    }

    let mut cookie = canonical_template
        .cloned()
        .unwrap_or_else(|| CanonicalCookie::new(info.name.trim(), info.value.trim(), uri.as_str()));
    cookie.name = info.name.trim().to_string();
    cookie.value = info.value.trim().to_string();
    if canonical_template.is_none() {
        cookie.path = info
            .path
            .as_deref()
            .map(str::trim)
            .filter(|path| !path.is_empty())
            .unwrap_or("/")
            .to_string();
        cookie.secure = info.secure.unwrap_or(false);
        cookie.http_only = info.http_only.unwrap_or(false);
        cookie.same_site = info.same_site.unwrap_or_default();
        cookie.expires_at_unix_ms = info.expires_at_unix_ms;
        if let Some(domain) = info
            .domain
            .as_deref()
            .map(str::trim)
            .filter(|domain| !domain.is_empty())
        {
            let normalized = domain.trim_start_matches('.').to_ascii_lowercase();
            if info.host_only == Some(false) || domain.starts_with('.') {
                cookie.host_only = false;
                cookie.domain = Some(format!(".{normalized}"));
            } else {
                cookie.host_only = true;
                cookie.domain = None;
                cookie.origin_url = Some(origin_url_for_host(uri, &normalized));
            }
        }
    }
    Some(cookie)
}

fn webview_cookie_info_score(cookie: &WebViewCookieInfo) -> (u8, u8, u8, i64, usize) {
    let non_empty = (!cookie.value.trim().is_empty()) as u8;
    let now_unix_ms = current_unix_ms();
    let unexpired = cookie
        .expires_at_unix_ms
        .is_none_or(|expires_at_unix_ms| expires_at_unix_ms > now_unix_ms)
        as u8;
    let host_only = (cookie.host_only == Some(true)) as u8;
    let expiry = cookie.expires_at_unix_ms.unwrap_or(i64::MAX);
    (non_empty, unexpired, host_only, expiry, cookie.value.len())
}
