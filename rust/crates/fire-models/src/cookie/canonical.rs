use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};
use time::{format_description::well_known::Rfc2822, OffsetDateTime};

use crate::is_cf_clearance_cookie_name;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlatformCookie {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub expires_at_unix_ms: Option<i64>,
    #[serde(default)]
    pub same_site: Option<String>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum CookieSameSite {
    #[default]
    Unspecified,
    Lax,
    Strict,
    None,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum CookieSource {
    #[default]
    Unknown,
    NetworkSetCookie,
    WebViewLogin,
    WebViewChallenge,
    WebViewBulkRead,
    ManualRestore,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum CookieTrust {
    #[default]
    Untrusted,
    Trusted,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CanonicalCookie {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: String,
    pub host_only: bool,
    pub secure: bool,
    pub http_only: bool,
    pub same_site: CookieSameSite,
    pub partition_key: Option<String>,
    pub partitioned: bool,
    pub expires_at_unix_ms: Option<i64>,
    pub max_age_seconds: Option<i64>,
    pub creation_time_unix_ms: i64,
    pub last_access_time_unix_ms: i64,
    pub version: u64,
    pub source: CookieSource,
    pub raw_set_cookie: Option<String>,
    pub origin_url: Option<String>,
}

impl CanonicalCookie {
    pub fn new(name: impl Into<String>, value: impl Into<String>, origin_url: &str) -> Self {
        let now = current_unix_ms();
        Self {
            name: name.into(),
            value: value.into(),
            domain: None,
            path: "/".to_string(),
            host_only: true,
            secure: false,
            http_only: false,
            same_site: CookieSameSite::Unspecified,
            partition_key: None,
            partitioned: false,
            expires_at_unix_ms: None,
            max_age_seconds: None,
            creation_time_unix_ms: now,
            last_access_time_unix_ms: now,
            version: 1,
            source: CookieSource::Unknown,
            raw_set_cookie: None,
            origin_url: Some(origin_url.to_string()),
        }
    }

    pub fn normalized_domain(&self) -> Option<String> {
        let domain = self
            .domain
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|value| value.trim_start_matches('.').to_ascii_lowercase());
        if domain.is_some() {
            return domain;
        }
        if !self.host_only {
            return None;
        }
        self.origin_url
            .as_deref()
            .and_then(|value| url::Url::parse(value).ok())
            .and_then(|url| url.host_str().map(|host| host.to_ascii_lowercase()))
    }

    pub fn storage_key(&self) -> String {
        serde_json::json!([
            &self.name,
            self.normalized_domain(),
            normalized_cookie_path(&self.path),
            self.partition_key.as_deref(),
        ])
        .to_string()
    }

    pub fn is_expired_at(&self, now_unix_ms: i64) -> bool {
        if let Some(max_age_seconds) = self.max_age_seconds {
            return self
                .creation_time_unix_ms
                .saturating_add(max_age_seconds.saturating_mul(1000))
                <= now_unix_ms;
        }
        self.expires_at_unix_ms
            .is_some_and(|expires_at_unix_ms| expires_at_unix_ms <= now_unix_ms)
    }

    pub fn is_expired_now(&self) -> bool {
        self.is_expired_at(current_unix_ms())
    }

    pub fn is_fresher_than(&self, other: &Self) -> bool {
        if self.version != other.version {
            return self.version > other.version;
        }
        match (self.expires_at_unix_ms, other.expires_at_unix_ms) {
            (Some(lhs), Some(rhs)) if lhs != rhs => return lhs > rhs,
            (Some(_), None) => return true,
            (None, Some(_)) => return false,
            _ => {}
        }
        self.creation_time_unix_ms > other.creation_time_unix_ms
    }

    pub fn with_trusted_version_from(mut self, existing: &Self) -> Self {
        self.version = if self.value == existing.value {
            existing.version
        } else {
            existing.version.saturating_add(1)
        };
        self.creation_time_unix_ms = existing.creation_time_unix_ms;
        self.last_access_time_unix_ms = existing.last_access_time_unix_ms;
        self
    }

    pub fn to_set_cookie_header(&self) -> String {
        if let Some(raw) = self
            .raw_set_cookie
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return raw.to_string();
        }

        let mut header = format!("{}={}", self.name, self.value);
        if !self.host_only {
            if let Some(domain) = self.domain.as_deref().filter(|value| !value.is_empty()) {
                header.push_str("; Domain=");
                header.push_str(domain);
            }
        }

        header.push_str("; Path=");
        header.push_str(&normalized_cookie_path(&self.path));

        if let Some(expires_at_unix_ms) = self.expires_at_unix_ms {
            if let Some(formatted) = format_http_date(expires_at_unix_ms) {
                header.push_str("; Expires=");
                header.push_str(&formatted);
            }
        }

        if let Some(max_age_seconds) = self.max_age_seconds {
            header.push_str("; Max-Age=");
            header.push_str(&max_age_seconds.to_string());
        }

        if self.secure {
            header.push_str("; Secure");
        }
        if self.http_only {
            header.push_str("; HttpOnly");
        }
        match self.same_site {
            CookieSameSite::Unspecified => {}
            CookieSameSite::Lax => header.push_str("; SameSite=Lax"),
            CookieSameSite::Strict => header.push_str("; SameSite=Strict"),
            CookieSameSite::None => header.push_str("; SameSite=None"),
        }
        if self.partitioned {
            header.push_str("; Partitioned");
        }
        header
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CanonicalCookieStore {
    cookies: Vec<CanonicalCookie>,
}

impl CanonicalCookieStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from_cookies(cookies: Vec<CanonicalCookie>) -> Self {
        Self { cookies }
    }

    pub fn read_all(&self) -> &[CanonicalCookie] {
        &self.cookies
    }

    pub fn into_cookies(self) -> Vec<CanonicalCookie> {
        self.cookies
    }

    pub fn save_canonical_cookies(
        &mut self,
        uri: &url::Url,
        cookies: impl IntoIterator<Item = CanonicalCookie>,
        trust: CookieTrust,
    ) {
        for cookie in cookies {
            let mut resolved = resolve_canonical_cookie(uri, cookie);
            let Some(idx) = self
                .cookies
                .iter()
                .position(|existing| existing.storage_key() == resolved.storage_key())
            else {
                if !resolved.is_expired_now() {
                    self.cookies.push(resolved);
                }
                continue;
            };

            let existing = self.cookies[idx].clone();
            resolved = match trust {
                CookieTrust::Trusted => resolved.with_trusted_version_from(&existing),
                CookieTrust::Untrusted => {
                    if !resolved.is_fresher_than(&existing) {
                        continue;
                    }
                    resolved.creation_time_unix_ms = existing.creation_time_unix_ms;
                    resolved.last_access_time_unix_ms = existing.last_access_time_unix_ms;
                    resolved
                }
            };

            self.cookies.remove(idx);
            if !resolved.is_expired_now() {
                self.cookies.push(resolved);
            }
        }
    }

    pub fn delete_by_name(&mut self, uri: &url::Url, name: &str) -> usize {
        let before = self.cookies.len();
        if is_cf_clearance_cookie_name(name) {
            self.cookies
                .retain(|cookie| !is_cf_clearance_cookie_name(&cookie.name));
            return before - self.cookies.len();
        }
        let host = uri.host_str().map(|value| value.to_ascii_lowercase());
        self.cookies.retain(|cookie| {
            if cookie.name != name {
                return true;
            }
            let Some(host) = host.as_deref() else {
                return false;
            };
            let Some(domain) = cookie.normalized_domain() else {
                return false;
            };
            !(host == domain
                || host.ends_with(&format!(".{domain}"))
                || domain.ends_with(&format!(".{host}")))
        });
        before - self.cookies.len()
    }

    pub fn load_for_request(&self, uri: &url::Url) -> Vec<CanonicalCookie> {
        let mut matching = self
            .cookies
            .iter()
            .filter(|cookie| canonical_cookie_matches_url(cookie, uri))
            .cloned()
            .collect::<Vec<_>>();
        matching.sort_by(|left, right| {
            right
                .path
                .len()
                .cmp(&left.path.len())
                .then_with(|| {
                    let left_domain_len = left.normalized_domain().map_or(0, |domain| domain.len());
                    let right_domain_len =
                        right.normalized_domain().map_or(0, |domain| domain.len());
                    right_domain_len.cmp(&left_domain_len)
                })
                .then_with(|| right.host_only.cmp(&left.host_only))
                // Do not rotate cf_clearance by later expires. Challenge-page and
                // Turnstile leftovers often outlive the working incumbent.
                .then_with(|| {
                    if is_cf_clearance_cookie_name(&left.name)
                        || is_cf_clearance_cookie_name(&right.name)
                    {
                        std::cmp::Ordering::Equal
                    } else {
                        right.expires_at_unix_ms.cmp(&left.expires_at_unix_ms)
                    }
                })
                .then_with(|| right.version.cmp(&left.version))
                .then_with(|| right.creation_time_unix_ms.cmp(&left.creation_time_unix_ms))
        });
        matching
    }
}

fn resolve_canonical_cookie(uri: &url::Url, cookie: CanonicalCookie) -> CanonicalCookie {
    let origin_url = cookie
        .origin_url
        .clone()
        .or_else(|| Some(uri.as_str().to_string()));
    let mut resolved = cookie;
    resolved.origin_url = origin_url;
    if resolved.path.trim().is_empty() {
        resolved.path = "/".to_string();
    }
    if resolved.domain.is_none() && !resolved.host_only {
        resolved.domain = uri.host_str().map(|host| host.to_ascii_lowercase());
    }
    resolved
}

pub(super) fn canonical_cookie_matches_url(cookie: &CanonicalCookie, uri: &url::Url) -> bool {
    if cookie.is_expired_now() {
        return false;
    }
    if cookie.secure && uri.scheme() != "https" {
        return false;
    }
    let Some(host) = uri.host_str().map(|value| value.to_ascii_lowercase()) else {
        return false;
    };
    let Some(domain) = cookie.normalized_domain() else {
        return false;
    };
    if cookie.host_only {
        if host != domain {
            return false;
        }
    } else if host != domain && !host.ends_with(&format!(".{domain}")) {
        return false;
    }
    let request_path = if uri.path().is_empty() {
        "/"
    } else {
        uri.path()
    };
    request_path.starts_with(&normalized_cookie_path(&cookie.path))
}

pub(super) fn normalized_cookie_path(path: &str) -> String {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        "/".to_string()
    } else {
        trimmed.to_string()
    }
}

fn format_http_date(unix_ms: i64) -> Option<String> {
    let seconds = unix_ms.div_euclid(1000);
    OffsetDateTime::from_unix_timestamp(seconds)
        .ok()
        .and_then(|date| date.format(&Rfc2822).ok())
}

impl PlatformCookie {
    pub fn is_expired_at(&self, now_unix_ms: i64) -> bool {
        self.expires_at_unix_ms
            .is_some_and(|expires_at_unix_ms| expires_at_unix_ms <= now_unix_ms)
    }

    pub fn is_expired_now(&self) -> bool {
        self.is_expired_at(current_unix_ms())
    }

    pub fn is_low_confidence(&self) -> bool {
        self.domain.is_none() && self.path.is_none()
    }
}

pub(super) fn normalized_cookie_domain(domain: Option<&str>) -> Option<String> {
    domain
        .map(str::trim)
        .map(|value| value.trim_start_matches('.'))
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase())
}

pub(super) fn normalized_cookie_domain_for_storage(domain: Option<&str>) -> Option<String> {
    domain
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase())
}

pub fn canonical_cookies_from_platform(
    cookies: &[PlatformCookie],
    origin_url: &url::Url,
    source: CookieSource,
) -> Vec<CanonicalCookie> {
    cookies
        .iter()
        .filter_map(|cookie| canonical_cookie_from_platform(cookie, origin_url, source))
        .collect()
}

pub fn canonical_cookie_from_platform(
    cookie: &PlatformCookie,
    origin_url: &url::Url,
    source: CookieSource,
) -> Option<CanonicalCookie> {
    let name = cookie.name.trim();
    if name.is_empty() {
        return None;
    }

    let mut canonical = CanonicalCookie::new(name, cookie.value.trim(), origin_url.as_str());
    canonical.path = cookie
        .path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("/")
        .to_string();
    canonical.expires_at_unix_ms = cookie.expires_at_unix_ms;
    canonical.same_site = cookie_same_site_from_str(cookie.same_site.as_deref());
    canonical.source = source;

    if let Some(domain) = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        let normalized = domain.trim_start_matches('.').to_ascii_lowercase();
        if normalized.is_empty() {
            return None;
        }
        if domain.starts_with('.') {
            canonical.host_only = false;
            canonical.domain = Some(format!(".{normalized}"));
        } else {
            canonical.host_only = true;
            canonical.domain = None;
            canonical.origin_url = Some(origin_url_for_host(origin_url, &normalized));
        }
    }

    Some(canonical)
}

fn cookie_same_site_from_str(value: Option<&str>) -> CookieSameSite {
    match value.map(str::trim).map(|value| value.to_ascii_lowercase()) {
        Some(value) if value == "lax" => CookieSameSite::Lax,
        Some(value) if value == "strict" => CookieSameSite::Strict,
        Some(value) if value == "none" => CookieSameSite::None,
        _ => CookieSameSite::Unspecified,
    }
}

pub(super) fn origin_url_for_host(origin_url: &url::Url, host: &str) -> String {
    let mut cloned = origin_url.clone();
    if cloned.set_host(Some(host)).is_ok() {
        cloned.set_path("/");
        cloned.set_query(None);
        cloned.set_fragment(None);
        return cloned.as_str().to_string();
    }
    format!("{}://{host}/", origin_url.scheme())
}

pub(super) fn default_linux_do_url() -> Option<url::Url> {
    url::Url::parse("https://linux.do/").ok()
}

pub fn current_unix_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_millis() as i64)
}

pub fn score_platform_cookie(cookie: &PlatformCookie, host: &str) -> i64 {
    let mut score: i64 = 0;
    let normalized_host = host.to_ascii_lowercase();
    if !cookie.value.is_empty() {
        score += 100_000;
    }
    if !cookie.is_expired_now() {
        score += 50_000;
    }
    let raw_domain = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|d| !d.is_empty());
    match raw_domain {
        None => {
            score += 40_000;
        }
        Some(domain) if domain.starts_with('.') => {
            let normalized = domain.trim_start_matches('.').to_ascii_lowercase();
            if normalized == normalized_host || normalized_host.ends_with(&format!(".{normalized}"))
            {
                score += 20_000;
            }
        }
        Some(domain) => {
            let normalized = domain.to_ascii_lowercase();
            if normalized == normalized_host {
                score += 30_000;
            } else if normalized_host.ends_with(&format!(".{normalized}")) {
                score += 20_000;
            }
        }
    }
    score
}
