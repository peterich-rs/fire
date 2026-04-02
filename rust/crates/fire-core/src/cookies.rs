use std::sync::{Arc, RwLock};

use fire_models::{CookieSnapshot, SessionSnapshot};
use http::header::HeaderValue;
use openwire::CookieJar;
use url::Url;

use crate::sync_utils::{read_rwlock, write_rwlock};

#[derive(Clone)]
pub(crate) struct FireSessionCookieJar {
    base_url: Url,
    session: Arc<RwLock<SessionSnapshot>>,
}

impl FireSessionCookieJar {
    pub(crate) fn new(base_url: Url, session: Arc<RwLock<SessionSnapshot>>) -> Self {
        Self { base_url, session }
    }
}

impl CookieJar for FireSessionCookieJar {
    fn set_cookies(&self, cookie_headers: &mut dyn Iterator<Item = &HeaderValue>, url: &Url) {
        if !same_site_scope(&self.base_url, url) {
            return;
        }

        let mut patch = CookieSnapshot::default();
        for header in cookie_headers {
            let Ok(value) = header.to_str() else {
                continue;
            };
            let Some(cookie) = parse_set_cookie(value, url) else {
                continue;
            };

            match cookie.name.as_str() {
                "_t" => patch.t_token = Some(cookie.value.clone()),
                "_forum_session" => patch.forum_session = Some(cookie.value.clone()),
                "cf_clearance" => patch.cf_clearance = Some(cookie.value.clone()),
                _ => {}
            }
            patch.platform_cookies.push(cookie);
        }

        if patch == CookieSnapshot::default() {
            return;
        }

        let mut session = write_rwlock(&self.session, "session");
        session.cookies.merge_patch(&patch);
    }

    fn cookies(&self, url: &Url) -> Option<HeaderValue> {
        let session = read_rwlock(&self.session, "session");
        if session.cookies.platform_cookies.is_empty() {
            if !same_origin_scope(&self.base_url, url) {
                return None;
            }
        } else if !same_site_scope(&self.base_url, url) {
            return None;
        }

        let cookies = build_cookie_header(&session.cookies, &self.base_url, url);
        if cookies.is_empty() {
            return None;
        }

        HeaderValue::from_str(&cookies).ok()
    }
}

fn same_origin_scope(base_url: &Url, request_url: &Url) -> bool {
    base_url.scheme() == request_url.scheme()
        && base_url.host_str() == request_url.host_str()
        && base_url.port_or_known_default() == request_url.port_or_known_default()
}

fn same_site_scope(base_url: &Url, request_url: &Url) -> bool {
    base_url.scheme() == request_url.scheme()
        && hosts_share_base_domain(base_url.host_str(), request_url.host_str())
}

fn hosts_share_base_domain(base_host: Option<&str>, request_host: Option<&str>) -> bool {
    let Some(base_host) = base_host.map(|value| value.trim_start_matches('.').to_ascii_lowercase())
    else {
        return false;
    };
    let Some(request_host) =
        request_host.map(|value| value.trim_start_matches('.').to_ascii_lowercase())
    else {
        return false;
    };
    request_host == base_host || request_host.ends_with(&format!(".{base_host}"))
}

fn build_cookie_header(cookies: &CookieSnapshot, base_url: &Url, request_url: &Url) -> String {
    if !cookies.platform_cookies.is_empty() {
        let mut matching = cookies
            .platform_cookies
            .iter()
            .filter(|cookie| cookie_matches_url(cookie, base_url, request_url))
            .cloned()
            .collect::<Vec<_>>();
        matching.sort_by(|left, right| {
            let left_path_len = left.path.as_deref().unwrap_or("/").len();
            let right_path_len = right.path.as_deref().unwrap_or("/").len();
            right_path_len.cmp(&left_path_len)
        });

        let joined = matching
            .into_iter()
            .filter_map(|cookie| {
                let value = cookie.value.trim();
                if value.is_empty() {
                    None
                } else {
                    Some(format!("{}={}", cookie.name, value))
                }
            })
            .collect::<Vec<_>>()
            .join("; ");
        if !joined.is_empty() {
            return joined;
        }
    }

    let mut pairs = Vec::new();
    push_cookie_pair(&mut pairs, "_t", cookies.t_token.as_deref());
    push_cookie_pair(
        &mut pairs,
        "_forum_session",
        cookies.forum_session.as_deref(),
    );
    push_cookie_pair(&mut pairs, "cf_clearance", cookies.cf_clearance.as_deref());
    pairs.join("; ")
}

fn push_cookie_pair(pairs: &mut Vec<String>, name: &str, value: Option<&str>) {
    let Some(value) = value.filter(|value| !value.is_empty()) else {
        return;
    };
    pairs.push(format!("{name}={value}"));
}

fn cookie_matches_url(
    cookie: &fire_models::PlatformCookie,
    base_url: &Url,
    request_url: &Url,
) -> bool {
    if request_url.scheme() != base_url.scheme() {
        return false;
    }

    let Some(request_host) = request_url
        .host_str()
        .map(|value| value.to_ascii_lowercase())
    else {
        return false;
    };
    let base_host = base_url.host_str().map(|value| value.to_ascii_lowercase());
    let cookie_domain = cookie
        .domain
        .as_deref()
        .map(|value| value.trim_start_matches('.').to_ascii_lowercase())
        .or(base_host);

    let Some(cookie_domain) = cookie_domain else {
        return false;
    };
    if request_host != cookie_domain && !request_host.ends_with(&format!(".{cookie_domain}")) {
        return false;
    }

    let request_path = request_url.path();
    let cookie_path = cookie.path.as_deref().unwrap_or("/");
    request_path.starts_with(cookie_path)
}

fn parse_set_cookie(value: &str, url: &Url) -> Option<fire_models::PlatformCookie> {
    let mut parts = value.split(';');
    let first = parts.next()?.trim();
    let (name, value) = first.split_once('=')?;
    let mut domain = url.host_str().map(ToOwned::to_owned);
    let mut path = Some(default_cookie_path(url.path()));

    for attribute in parts {
        let attribute = attribute.trim();
        if let Some((key, raw_value)) = attribute.split_once('=') {
            let key = key.trim();
            let raw_value = raw_value.trim();
            if key.eq_ignore_ascii_case("domain") && !raw_value.is_empty() {
                domain = Some(raw_value.trim_start_matches('.').to_ascii_lowercase());
            } else if key.eq_ignore_ascii_case("path") && !raw_value.is_empty() {
                path = Some(raw_value.to_string());
            }
        }
    }

    let value = if value.trim().is_empty() || value.eq_ignore_ascii_case("del") {
        String::new()
    } else {
        value.trim().to_string()
    };

    Some(fire_models::PlatformCookie {
        name: name.trim().to_string(),
        value,
        domain,
        path,
    })
}

fn default_cookie_path(request_path: &str) -> String {
    if request_path.is_empty() || request_path == "/" {
        return "/".to_string();
    }
    match request_path.rsplit_once('/') {
        Some(("", _)) | None => "/".to_string(),
        Some((prefix, _)) => format!("{prefix}/"),
    }
}
