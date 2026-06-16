use std::collections::HashSet;
use std::sync::{Arc, Mutex, RwLock};

use fire_models::{
    CanonicalCookie, CanonicalCookieStore, CookieSameSite, CookieSnapshot, CookieSource,
    CookieTrust,
};
use http::header::HeaderValue;
use openwire::CookieJar;
use time::{format_description::well_known::Rfc2822, OffsetDateTime};
use tracing::warn;
use url::Url;

use crate::core::{
    mutate_runtime_session_tracking_auth_change, FireAuthChangeSource, FireSessionRuntimeState,
};
use crate::sync_utils::{read_rwlock, write_rwlock};

#[derive(Clone)]
pub(crate) struct FireSessionCookieJar {
    base_url: Url,
    session: Arc<RwLock<FireSessionRuntimeState>>,
    store: Option<Arc<Mutex<fire_store::FireStore>>>,
}

impl FireSessionCookieJar {
    pub(crate) fn new(
        base_url: Url,
        session: Arc<RwLock<FireSessionRuntimeState>>,
        store: Option<Arc<Mutex<fire_store::FireStore>>>,
    ) -> Self {
        Self {
            base_url,
            session,
            store,
        }
    }
}

tokio::task_local! {
    pub(crate) static FIRE_REQUEST_EPOCH: u64;
}

tokio::task_local! {
    pub(crate) static FIRE_REQUEST_TRACE_ID: u64;
}

impl CookieJar for FireSessionCookieJar {
    fn set_cookies(&self, cookie_headers: &mut dyn Iterator<Item = &HeaderValue>, url: &Url) {
        if !same_site_scope(&self.base_url, url) {
            return;
        }

        let request_epoch = FIRE_REQUEST_EPOCH.try_with(|epoch| *epoch).ok();
        if is_stale_request_epoch(&self.session, request_epoch) {
            return;
        }

        let mut patch = CookieSnapshot::default();
        let mut canonical_writes = Vec::new();
        let mut canonical_deletes = Vec::new();
        let mut replay_entries: Vec<(String, String, String)> = Vec::new();
        for header in cookie_headers {
            let Ok(value) = header.to_str() else {
                continue;
            };
            let Some(cookie) = parse_set_cookie(value, url) else {
                continue;
            };
            let canonical_cookie = parse_set_cookie_canonical(value, url);

            if should_ignore_network_auth_cookie_deletion(&cookie) {
                continue;
            }

            if cookie.value.is_empty() || cookie.is_expired_now() {
                canonical_deletes.push(cookie.name.clone());
            } else if let Some(canonical_cookie) = canonical_cookie {
                canonical_writes.push(canonical_cookie);
            }

            match cookie.name.as_str() {
                "_t" => patch.t_token = Some(cookie.value.clone()),
                "_forum_session" => patch.forum_session = Some(cookie.value.clone()),
                "cf_clearance" => patch.cf_clearance = Some(cookie.value.clone()),
                _ => {}
            }
            let replay_domain = cookie
                .domain
                .as_deref()
                .map(|d| d.trim_start_matches('.').to_string())
                .unwrap_or_default();
            replay_entries.push((value.to_string(), cookie.name.clone(), replay_domain));
            patch.platform_cookies.push(cookie);
        }

        if patch == CookieSnapshot::default()
            && canonical_writes.is_empty()
            && canonical_deletes.is_empty()
        {
            return;
        }

        let mut session = write_rwlock(&self.session, "session");
        mutate_runtime_session_tracking_auth_change(
            &mut session,
            FireAuthChangeSource::NetworkIngress,
            "network set-cookie ingress",
            |snapshot| {
                snapshot.cookies.merge_patch(&patch);
                for name in &canonical_deletes {
                    snapshot.cookies.delete_canonical_cookie_by_name(url, name);
                }
                if !canonical_writes.is_empty() {
                    snapshot.cookies.merge_canonical_cookies(
                        url,
                        &canonical_writes,
                        CookieTrust::Trusted,
                    );
                }
            },
        );

        if let Some(store) = self.store.as_ref() {
            let Ok(store) = store.lock() else {
                return;
            };
            for (raw_set_cookie, cookie_name, domain) in replay_entries {
                let url = self.base_url.as_str();
                if let Err(error) = store.cookie_replay_enqueue(
                    url,
                    &raw_set_cookie,
                    &cookie_name,
                    &domain,
                    fire_models::current_unix_ms() as u64,
                ) {
                    warn!(
                        cookie_name = %cookie_name,
                        %error,
                        "failed to enqueue Set-Cookie into replay queue"
                    );
                }
            }
        }
    }

    fn cookies(&self, url: &Url) -> Option<HeaderValue> {
        let session = read_rwlock(&self.session, "session");
        let snapshot = &session.snapshot;
        if snapshot.cookies.platform_cookies.is_empty()
            && snapshot.cookies.canonical_cookies.is_empty()
        {
            if !same_origin_scope(&self.base_url, url) {
                return None;
            }
        } else if !same_site_scope(&self.base_url, url) {
            return None;
        }

        let cookies = build_cookie_header(&snapshot.cookies, &self.base_url, url);
        if cookies.is_empty() {
            return None;
        }

        HeaderValue::from_str(&cookies).ok()
    }
}

fn should_ignore_network_auth_cookie_deletion(cookie: &fire_models::PlatformCookie) -> bool {
    cookie.value.is_empty() && matches!(cookie.name.as_str(), "_t" | "_forum_session")
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
    let canonical_known_names = canonical_cookie_names(cookies);
    let canonical_header = build_canonical_cookie_header(cookies, request_url);
    if !canonical_header.is_empty() && cookies.platform_cookies.is_empty() {
        return canonical_header;
    }

    if !cookies.platform_cookies.is_empty() {
        let request_host = request_url
            .host_str()
            .map(|value| value.to_ascii_lowercase());
        let mut matching = cookies
            .platform_cookies
            .iter()
            .enumerate()
            .filter(|(_, cookie)| {
                !canonical_known_names.contains(&cookie.name)
                    && cookie_matches_url(cookie, base_url, request_url)
            })
            .collect::<Vec<_>>();
        matching.sort_by(|(left_index, left), (right_index, right)| {
            let left_path_len = left.path.as_deref().unwrap_or("/").len();
            let right_path_len = right.path.as_deref().unwrap_or("/").len();
            right_path_len
                .cmp(&left_path_len)
                .then_with(|| {
                    cookie_send_precedence(right, request_host.as_deref())
                        .cmp(&cookie_send_precedence(left, request_host.as_deref()))
                })
                .then_with(|| right_index.cmp(left_index))
        });

        let mut seen = HashSet::new();
        let joined = matching
            .into_iter()
            .filter_map(|(_, cookie)| {
                let value = cookie.value.trim();
                if value.is_empty() {
                    return None;
                }

                let dedupe_key = (
                    cookie.name.clone(),
                    cookie.path.as_deref().unwrap_or("/").to_string(),
                );
                if !seen.insert(dedupe_key) {
                    return None;
                }

                Some(format!("{}={}", cookie.name, value))
            })
            .collect::<Vec<_>>()
            .join("; ");
        return join_cookie_headers(&canonical_header, &joined);
    }

    if !canonical_header.is_empty() {
        return canonical_header;
    }

    let mut pairs = Vec::new();
    if !canonical_known_names.contains("_t") {
        push_cookie_pair(&mut pairs, "_t", cookies.t_token.as_deref());
    }
    if !canonical_known_names.contains("_forum_session") {
        push_cookie_pair(
            &mut pairs,
            "_forum_session",
            cookies.forum_session.as_deref(),
        );
    }
    if !canonical_known_names.contains("cf_clearance") {
        push_cookie_pair(&mut pairs, "cf_clearance", cookies.cf_clearance.as_deref());
    }
    pairs.join("; ")
}

fn build_canonical_cookie_header(cookies: &CookieSnapshot, request_url: &Url) -> String {
    if cookies.canonical_cookies.is_empty() {
        return String::new();
    }

    let store = CanonicalCookieStore::from_cookies(cookies.canonical_cookies.clone());
    let mut seen_critical_names = HashSet::new();
    store
        .load_for_request(request_url)
        .into_iter()
        .filter_map(|cookie| {
            let value = cookie.value.trim();
            if value.is_empty() {
                return None;
            }
            if is_critical_cookie_name(&cookie.name)
                && !seen_critical_names.insert(cookie.name.clone())
            {
                return None;
            }
            Some(format!("{}={}", cookie.name, value))
        })
        .collect::<Vec<_>>()
        .join("; ")
}

fn canonical_cookie_names(cookies: &CookieSnapshot) -> HashSet<String> {
    cookies
        .canonical_cookies
        .iter()
        .filter(|cookie| !cookie.is_expired_now() && !cookie.value.trim().is_empty())
        .map(|cookie| cookie.name.clone())
        .collect()
}

fn join_cookie_headers(left: &str, right: &str) -> String {
    match (left.is_empty(), right.is_empty()) {
        (true, true) => String::new(),
        (false, true) => left.to_string(),
        (true, false) => right.to_string(),
        (false, false) => format!("{left}; {right}"),
    }
}

fn is_critical_cookie_name(name: &str) -> bool {
    matches!(
        name,
        "_t" | "_forum_session" | "cf_clearance" | "_cfuvid" | "h_captcha_temp_id"
    )
}

fn push_cookie_pair(pairs: &mut Vec<String>, name: &str, value: Option<&str>) {
    let Some(value) = value.filter(|value| !value.is_empty()) else {
        return;
    };
    pairs.push(format!("{name}={value}"));
}

fn is_stale_request_epoch(
    session: &Arc<RwLock<FireSessionRuntimeState>>,
    request_epoch: Option<u64>,
) -> bool {
    let Some(request_epoch) = request_epoch else {
        return false;
    };
    let current_epoch = read_rwlock(session, "session").epoch;
    current_epoch != request_epoch
}

fn cookie_send_precedence(
    cookie: &fire_models::PlatformCookie,
    request_host: Option<&str>,
) -> (u8, usize) {
    let Some(domain) = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return (3, request_host.map_or(0, str::len));
    };

    let normalized_domain = domain.trim_start_matches('.');
    let exact_host_match = request_host
        .is_some_and(|request_host| request_host.eq_ignore_ascii_case(normalized_domain));
    let rank = if domain.starts_with('.') {
        if exact_host_match {
            2
        } else {
            1
        }
    } else if exact_host_match {
        3
    } else {
        2
    };
    (rank, normalized_domain.len())
}

fn cookie_matches_url(
    cookie: &fire_models::PlatformCookie,
    base_url: &Url,
    request_url: &Url,
) -> bool {
    if cookie.is_expired_now() {
        return false;
    }

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
    let raw_cookie_domain = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase());
    let allows_subdomains = raw_cookie_domain
        .as_deref()
        .is_some_and(|value| value.starts_with('.'));
    let cookie_domain = raw_cookie_domain
        .as_deref()
        .map(|value| value.trim_start_matches('.').to_string())
        .or(base_host);

    let Some(cookie_domain) = cookie_domain else {
        return false;
    };
    if allows_subdomains {
        if request_host != cookie_domain && !request_host.ends_with(&format!(".{cookie_domain}")) {
            return false;
        }
    } else if request_host != cookie_domain {
        return false;
    }

    let request_path = request_url.path();
    let cookie_path = cookie.path.as_deref().unwrap_or("/");
    request_path.starts_with(cookie_path)
}

fn parse_set_cookie(value: &str, url: &Url) -> Option<fire_models::PlatformCookie> {
    let now_unix_ms = now_unix_ms();
    let mut parts = value.split(';');
    let first = parts.next()?.trim();
    let (name, value) = first.split_once('=')?;
    let mut domain = url.host_str().map(|value| value.to_ascii_lowercase());
    let mut path = Some(default_cookie_path(url.path()));
    let mut expires_at_unix_ms = None;
    let mut max_age_expires_at_unix_ms = None;
    let mut has_domain_attribute = false;

    for attribute in parts {
        let attribute = attribute.trim();
        if let Some((key, raw_value)) = attribute.split_once('=') {
            let key = key.trim();
            let raw_value = raw_value.trim();
            if key.eq_ignore_ascii_case("domain") && !raw_value.is_empty() {
                has_domain_attribute = true;
                let normalized = raw_value.trim_start_matches('.').to_ascii_lowercase();
                if !normalized.is_empty() {
                    domain = Some(format!(".{normalized}"));
                }
            } else if key.eq_ignore_ascii_case("path") && !raw_value.is_empty() {
                path = Some(raw_value.to_string());
            } else if key.eq_ignore_ascii_case("expires") && !raw_value.is_empty() {
                expires_at_unix_ms = parse_cookie_expires_at_unix_ms(raw_value);
            } else if key.eq_ignore_ascii_case("max-age") && !raw_value.is_empty() {
                max_age_expires_at_unix_ms =
                    parse_cookie_max_age_expires_at_unix_ms(raw_value, now_unix_ms);
            }
        }
    }

    if let Some(max_age_expires_at_unix_ms) = max_age_expires_at_unix_ms {
        expires_at_unix_ms = Some(max_age_expires_at_unix_ms);
    }

    if !has_domain_attribute {
        domain = url.host_str().map(|value| value.to_ascii_lowercase());
    }

    let value = if value.trim().is_empty()
        || value.eq_ignore_ascii_case("del")
        || expires_at_unix_ms.is_some_and(|expires_at_unix_ms| expires_at_unix_ms <= now_unix_ms)
    {
        String::new()
    } else {
        value.trim().to_string()
    };

    Some(fire_models::PlatformCookie {
        name: name.trim().to_string(),
        value,
        domain,
        path,
        expires_at_unix_ms,
        same_site: None,
    })
}

fn parse_set_cookie_canonical(value: &str, url: &Url) -> Option<CanonicalCookie> {
    let now_unix_ms = now_unix_ms();
    let mut parts = value.split(';');
    let first = parts.next()?.trim();
    let (name, raw_cookie_value) = first.split_once('=')?;
    let name = name.trim();
    if name.is_empty() {
        return None;
    }

    let mut cookie = CanonicalCookie::new(name, raw_cookie_value.trim(), url.as_str());
    cookie.path = default_cookie_path(url.path());
    cookie.creation_time_unix_ms = now_unix_ms;
    cookie.last_access_time_unix_ms = now_unix_ms;
    cookie.source = CookieSource::NetworkSetCookie;
    cookie.raw_set_cookie = Some(value.to_string());
    let mut max_age_expires_at_unix_ms = None;

    for attribute in parts {
        let attribute = attribute.trim();
        if attribute.eq_ignore_ascii_case("secure") {
            cookie.secure = true;
            continue;
        }
        if attribute.eq_ignore_ascii_case("httponly") {
            cookie.http_only = true;
            continue;
        }
        if attribute.eq_ignore_ascii_case("partitioned") {
            cookie.partitioned = true;
            continue;
        }

        let Some((key, raw_value)) = attribute.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let raw_value = raw_value.trim();
        if key.eq_ignore_ascii_case("domain") && !raw_value.is_empty() {
            let normalized = raw_value.trim_start_matches('.').to_ascii_lowercase();
            if !normalized.is_empty() {
                cookie.host_only = false;
                cookie.domain = Some(format!(".{normalized}"));
            }
        } else if key.eq_ignore_ascii_case("path") && !raw_value.is_empty() {
            cookie.path = raw_value.to_string();
        } else if key.eq_ignore_ascii_case("expires") && !raw_value.is_empty() {
            cookie.expires_at_unix_ms = parse_cookie_expires_at_unix_ms(raw_value);
        } else if key.eq_ignore_ascii_case("max-age") && !raw_value.is_empty() {
            if let Ok(max_age_seconds) = raw_value.parse::<i64>() {
                cookie.max_age_seconds = Some(max_age_seconds);
                max_age_expires_at_unix_ms =
                    parse_cookie_max_age_expires_at_unix_ms(raw_value, now_unix_ms);
            }
        } else if key.eq_ignore_ascii_case("samesite") && !raw_value.is_empty() {
            cookie.same_site = parse_cookie_same_site(raw_value);
        }
    }

    if let Some(max_age_expires_at_unix_ms) = max_age_expires_at_unix_ms {
        cookie.expires_at_unix_ms = Some(max_age_expires_at_unix_ms);
    }

    if raw_cookie_value.trim().is_empty()
        || raw_cookie_value.eq_ignore_ascii_case("del")
        || cookie.is_expired_at(now_unix_ms)
    {
        cookie.value.clear();
    }

    Some(cookie)
}

fn parse_cookie_same_site(value: &str) -> CookieSameSite {
    if value.eq_ignore_ascii_case("lax") {
        CookieSameSite::Lax
    } else if value.eq_ignore_ascii_case("strict") {
        CookieSameSite::Strict
    } else if value.eq_ignore_ascii_case("none") {
        CookieSameSite::None
    } else {
        CookieSameSite::Unspecified
    }
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

fn parse_cookie_expires_at_unix_ms(value: &str) -> Option<i64> {
    let expires_at = OffsetDateTime::parse(value, &Rfc2822).ok()?;
    Some(expires_at.unix_timestamp().saturating_mul(1000))
}

fn parse_cookie_max_age_expires_at_unix_ms(value: &str, now_unix_ms: i64) -> Option<i64> {
    let seconds = value.parse::<i64>().ok()?;
    if seconds <= 0 {
        return Some(now_unix_ms.saturating_sub(1));
    }

    Some(now_unix_ms.saturating_add(seconds.saturating_mul(1000)))
}

fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| duration.as_millis() as i64)
}

#[cfg(test)]
mod tests {
    use url::Url;

    use super::{
        build_cookie_header, cookie_matches_url, now_unix_ms, parse_set_cookie,
        parse_set_cookie_canonical,
    };
    use fire_models::{CanonicalCookie, CookieSameSite, CookieSnapshot, PlatformCookie};

    #[test]
    fn parse_set_cookie_preserves_leading_dot_and_expiry() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie(
            "_t=fresh; Domain=.linux.do; Path=/; Expires=Tue, 01 Jan 2030 00:00:00 GMT",
            &url,
        )
        .expect("cookie");

        assert_eq!(cookie.domain.as_deref(), Some(".linux.do"));
        assert_eq!(cookie.path.as_deref(), Some("/"));
        assert!(cookie.expires_at_unix_ms.is_some());
    }

    #[test]
    fn parse_set_cookie_prefers_max_age_over_expires() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie(
            "_t=fresh; Expires=Tue, 01 Jan 2030 00:00:00 GMT; Max-Age=1",
            &url,
        )
        .expect("cookie");

        let expires_at_unix_ms = cookie.expires_at_unix_ms.expect("max-age expiry");
        let now_unix_ms = super::now_unix_ms();
        assert!(expires_at_unix_ms >= now_unix_ms);
        assert!(expires_at_unix_ms <= now_unix_ms + 5_000);
    }

    #[test]
    fn parse_set_cookie_canonicalizes_domain_attribute_without_leading_dot() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie("_t=fresh; Domain=linux.do; Path=/", &url).expect("cookie");

        assert_eq!(cookie.domain.as_deref(), Some(".linux.do"));
    }

    #[test]
    fn parse_set_cookie_clears_immediately_expired_auth_values() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie("_t=fresh; Max-Age=0; Path=/", &url).expect("cookie");

        assert!(cookie.value.is_empty());
        assert!(cookie
            .expires_at_unix_ms
            .is_some_and(|expires_at_unix_ms| expires_at_unix_ms < now_unix_ms()));
    }

    #[test]
    fn parse_set_cookie_canonical_preserves_browser_metadata() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie_canonical(
            "cf_clearance=fresh; Domain=.linux.do; Path=/; Max-Age=120; Secure; HttpOnly; SameSite=None; Partitioned",
            &url,
        )
        .expect("cookie");

        assert_eq!(cookie.name, "cf_clearance");
        assert_eq!(cookie.value, "fresh");
        assert_eq!(cookie.domain.as_deref(), Some(".linux.do"));
        assert!(!cookie.host_only);
        assert!(cookie.secure);
        assert!(cookie.http_only);
        assert_eq!(cookie.same_site, CookieSameSite::None);
        assert!(cookie.partitioned);
        assert_eq!(cookie.max_age_seconds, Some(120));
        assert!(cookie.expires_at_unix_ms.is_some());
        assert_eq!(
            cookie.raw_set_cookie.as_deref(),
            Some("cf_clearance=fresh; Domain=.linux.do; Path=/; Max-Age=120; Secure; HttpOnly; SameSite=None; Partitioned")
        );
    }

    #[test]
    fn cookie_matching_distinguishes_host_only_and_domain_scope() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let request_url = Url::parse("https://meta.linux.do/latest").expect("request url");
        let host_only_cookie = PlatformCookie {
            name: "_t".into(),
            value: "host-only".into(),
            domain: Some("linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };
        let domain_cookie = PlatformCookie {
            name: "_t".into(),
            value: "domain-scope".into(),
            domain: Some(".linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };

        assert!(!cookie_matches_url(
            &host_only_cookie,
            &base_url,
            &request_url
        ));
        assert!(cookie_matches_url(&domain_cookie, &base_url, &request_url));
    }

    #[test]
    fn build_cookie_header_skips_expired_platform_cookies() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let request_url = Url::parse("https://linux.do/latest").expect("request url");
        let cookies = CookieSnapshot {
            platform_cookies: vec![
                fire_models::PlatformCookie {
                    name: "_t".into(),
                    value: "expired".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                    same_site: None,
                },
                fire_models::PlatformCookie {
                    name: "_forum_session".into(),
                    value: "forum".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
            ],
            ..CookieSnapshot::default()
        };

        assert_eq!(
            build_cookie_header(&cookies, &base_url, &request_url),
            "_forum_session=forum"
        );
    }

    #[test]
    fn build_cookie_header_does_not_fallback_to_stale_scalar_auth_fields() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let request_url = Url::parse("https://linux.do/latest").expect("request url");
        let cookies = CookieSnapshot {
            t_token: Some("stale-token".into()),
            forum_session: Some("stale-forum".into()),
            platform_cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "expired".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                    same_site: None,
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "expired".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                    same_site: None,
                },
            ],
            ..CookieSnapshot::default()
        };

        assert!(build_cookie_header(&cookies, &base_url, &request_url).is_empty());
    }

    #[test]
    fn build_cookie_header_prefers_host_only_cookie_over_domain_variant_with_same_name_and_path() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let request_url = Url::parse("https://linux.do/latest").expect("request url");
        let cookies = CookieSnapshot {
            platform_cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "fresh-host".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
                PlatformCookie {
                    name: "_t".into(),
                    value: "stale-domain".into(),
                    domain: Some(".linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "forum".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
            ],
            ..CookieSnapshot::default()
        };

        let header = build_cookie_header(&cookies, &base_url, &request_url);
        let t_pairs = header
            .split("; ")
            .filter(|pair| pair.starts_with("_t="))
            .collect::<Vec<_>>();

        assert_eq!(t_pairs, vec!["_t=fresh-host"]);
        assert!(!header.contains("stale-domain"));
        assert!(header
            .split("; ")
            .any(|pair| pair == "_forum_session=forum"));
    }

    #[test]
    fn build_cookie_header_prefers_canonical_and_blocks_legacy_same_name_leak() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let main_url = Url::parse("https://linux.do/latest").expect("request url");
        let subdomain_url = Url::parse("https://connect.linux.do/latest").expect("request url");

        let mut canonical_t = CanonicalCookie::new("_t", "fresh-host", "https://linux.do/");
        canonical_t.host_only = true;
        canonical_t.path = "/".into();
        let mut canonical_cf = CanonicalCookie::new("cf_clearance", "clear", "https://linux.do/");
        canonical_cf.host_only = false;
        canonical_cf.domain = Some(".linux.do".into());
        canonical_cf.path = "/".into();

        let cookies = CookieSnapshot {
            platform_cookies: vec![PlatformCookie {
                name: "_t".into(),
                value: "legacy-domain".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
                same_site: None,
            }],
            canonical_cookies: vec![canonical_t, canonical_cf],
            ..CookieSnapshot::default()
        };

        let main_header = build_cookie_header(&cookies, &base_url, &main_url);
        assert!(main_header.contains("_t=fresh-host"));
        assert!(main_header.contains("cf_clearance=clear"));
        assert!(!main_header.contains("legacy-domain"));

        let subdomain_header = build_cookie_header(&cookies, &base_url, &subdomain_url);
        assert_eq!(subdomain_header, "cf_clearance=clear");
    }
}
