use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};
use time::{format_description::well_known::Rfc2822, OffsetDateTime};

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

fn normalized_cookie_path(path: &str) -> String {
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookieSnapshot {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
    pub cf_clearance: Option<String>,
    pub csrf_token: Option<String>,
    #[serde(default)]
    pub platform_cookies: Vec<PlatformCookie>,
}

impl CookieSnapshot {
    pub fn has_login_session(&self) -> bool {
        if self.platform_cookies.is_empty() {
            is_non_empty(self.t_token.as_deref())
        } else {
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "_t").is_some()
        }
    }

    pub fn has_forum_session(&self) -> bool {
        if self.platform_cookies.is_empty() {
            is_non_empty(self.forum_session.as_deref())
        } else {
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "_forum_session")
                .is_some()
        }
    }

    pub fn has_cloudflare_clearance(&self) -> bool {
        if self.platform_cookies.is_empty() {
            is_non_empty(self.cf_clearance.as_deref())
        } else {
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "cf_clearance").is_some()
        }
    }

    pub fn has_csrf_token(&self) -> bool {
        is_non_empty(self.csrf_token.as_deref())
    }

    pub fn can_authenticate_requests(&self) -> bool {
        self.has_login_session() && self.has_forum_session()
    }

    pub fn merge_patch(&mut self, patch: &Self) {
        merge_string_patch(&mut self.t_token, patch.t_token.clone());
        merge_string_patch(&mut self.forum_session, patch.forum_session.clone());
        merge_string_patch(&mut self.cf_clearance, patch.cf_clearance.clone());
        merge_string_patch(&mut self.csrf_token, patch.csrf_token.clone());
        if !patch.platform_cookies.is_empty() {
            merge_platform_cookie_batch(&mut self.platform_cookies, &patch.platform_cookies);
            self.refresh_known_platform_cookie_fields();
        }
    }

    pub fn merge_platform_cookies(&mut self, cookies: &[PlatformCookie]) {
        merge_string_patch(
            &mut self.t_token,
            latest_non_empty_platform_cookie_value(cookies, "_t"),
        );
        merge_string_patch(
            &mut self.forum_session,
            latest_non_empty_platform_cookie_value(cookies, "_forum_session"),
        );
        merge_string_patch(
            &mut self.cf_clearance,
            latest_non_empty_platform_cookie_value(cookies, "cf_clearance"),
        );
        merge_platform_cookie_batch(&mut self.platform_cookies, cookies);
        self.refresh_known_platform_cookie_fields();
    }

    pub fn apply_platform_cookies(&mut self, cookies: &[PlatformCookie]) {
        self.t_token = latest_non_empty_platform_cookie_value(cookies, "_t");
        self.forum_session = latest_non_empty_platform_cookie_value(cookies, "_forum_session");
        self.cf_clearance = latest_non_empty_platform_cookie_value(cookies, "cf_clearance");
        self.platform_cookies = normalized_platform_cookies(cookies);
        self.refresh_known_platform_cookie_fields();
    }

    pub fn scored_apply_platform_cookies(
        &mut self,
        cookies: &[PlatformCookie],
        host: &str,
        allow_low_confidence_session_cookies: bool,
    ) {
        let mut best_by_name: HashMap<String, (i64, &PlatformCookie)> = HashMap::new();
        for cookie in cookies {
            let lower_name = cookie.name.to_ascii_lowercase();
            let is_session_cookie = lower_name == "_t" || lower_name == "_forum_session";
            if is_session_cookie
                && cookie.is_low_confidence()
                && !allow_low_confidence_session_cookies
            {
                continue;
            }
            let score = score_platform_cookie(cookie, host);
            match best_by_name.get(&lower_name) {
                Some((existing_score, _)) => {
                    if score > *existing_score {
                        best_by_name.insert(lower_name, (score, cookie));
                    }
                }
                None => {
                    best_by_name.insert(lower_name, (score, cookie));
                }
            }
        }
        let winners: Vec<PlatformCookie> = best_by_name
            .into_values()
            .map(|(_, cookie)| cookie.clone())
            .collect();
        self.apply_platform_cookies(&winners);
    }

    pub fn clear_login_state(&mut self, preserve_cf_clearance: bool) {
        self.t_token = None;
        self.forum_session = None;
        self.csrf_token = None;
        if !preserve_cf_clearance {
            self.cf_clearance = None;
        }
        self.platform_cookies.retain(|cookie| {
            let lower_name = cookie.name.to_ascii_lowercase();
            if lower_name == "_t" || lower_name == "_forum_session" {
                return false;
            }
            preserve_cf_clearance || lower_name != "cf_clearance"
        });
    }

    pub fn refresh_known_platform_cookie_fields(&mut self) {
        let had_platform_cookies = !self.platform_cookies.is_empty();
        self.platform_cookies = normalized_platform_cookies(&self.platform_cookies);
        if self.platform_cookies.is_empty() {
            if had_platform_cookies {
                self.t_token = None;
                self.forum_session = None;
                self.cf_clearance = None;
            }
            return;
        }

        self.t_token = latest_non_empty_platform_cookie_value(&self.platform_cookies, "_t");
        self.forum_session =
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "_forum_session");
        self.cf_clearance =
            latest_non_empty_platform_cookie_value(&self.platform_cookies, "cf_clearance");
    }
}

pub(crate) fn merge_string_patch(slot: &mut Option<String>, patch: Option<String>) {
    if let Some(value) = patch {
        if value.is_empty() {
            *slot = None;
        } else {
            *slot = Some(value);
        }
    }
}

pub(crate) fn is_non_empty(value: Option<&str>) -> bool {
    value.is_some_and(|value| !value.is_empty())
}

fn normalized_platform_cookies(cookies: &[PlatformCookie]) -> Vec<PlatformCookie> {
    let mut merged = Vec::new();
    merge_platform_cookie_batch(&mut merged, cookies);
    merged
}

fn merge_platform_cookie_batch(current: &mut Vec<PlatformCookie>, incoming: &[PlatformCookie]) {
    let now_unix_ms = current_unix_ms();
    current.retain(|cookie| !cookie.is_expired_at(now_unix_ms));
    for cookie in incoming {
        let Some((name, domain_key, path)) = normalized_platform_cookie_key(cookie) else {
            continue;
        };
        current.retain(|existing| {
            normalized_platform_cookie_key(existing).is_none_or(|existing_key| {
                existing_key != (name.clone(), domain_key.clone(), path.clone())
            })
        });
        if is_deleted_cookie_value(&cookie.value) || cookie.is_expired_at(now_unix_ms) {
            continue;
        }
        current.push(PlatformCookie {
            name,
            value: cookie.value.trim().to_string(),
            domain: normalized_cookie_domain_for_storage(cookie.domain.as_deref()),
            path: Some(path),
            expires_at_unix_ms: cookie.expires_at_unix_ms,
            same_site: cookie.same_site.clone(),
        });
    }
}

fn normalized_platform_cookie_key(
    cookie: &PlatformCookie,
) -> Option<(String, Option<String>, String)> {
    let name = cookie.name.trim();
    if name.is_empty() {
        return None;
    }
    let domain = normalized_cookie_domain(cookie.domain.as_deref());
    let path = cookie
        .path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("/");
    Some((name.to_string(), domain, path.to_string()))
}

fn normalized_cookie_domain(domain: Option<&str>) -> Option<String> {
    domain
        .map(str::trim)
        .map(|value| value.trim_start_matches('.'))
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase())
}

fn normalized_cookie_domain_for_storage(domain: Option<&str>) -> Option<String> {
    domain
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase())
}

fn is_deleted_cookie_value(value: &str) -> bool {
    let value = value.trim();
    value.is_empty() || value.eq_ignore_ascii_case("del")
}

fn latest_non_empty_platform_cookie_value(
    cookies: &[PlatformCookie],
    name: &str,
) -> Option<String> {
    let now_unix_ms = current_unix_ms();
    cookies
        .iter()
        .rev()
        .find(|cookie| {
            cookie.name == name && !cookie.value.is_empty() && !cookie.is_expired_at(now_unix_ms)
        })
        .map(|cookie| cookie.value.clone())
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn low_confidence_when_domain_and_path_both_none() {
        let cookie = PlatformCookie {
            name: "_t".into(),
            value: "token".into(),
            domain: None,
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        };
        assert!(cookie.is_low_confidence());
    }

    #[test]
    fn not_low_confidence_when_domain_is_some() {
        let cookie = PlatformCookie {
            name: "_t".into(),
            value: "token".into(),
            domain: Some("linux.do".into()),
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        };
        assert!(!cookie.is_low_confidence());
    }

    #[test]
    fn not_low_confidence_when_path_is_some() {
        let cookie = PlatformCookie {
            name: "_t".into(),
            value: "token".into(),
            domain: None,
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };
        assert!(!cookie.is_low_confidence());
    }

    #[test]
    fn host_only_scores_higher_than_subdomain() {
        let host_only = PlatformCookie {
            name: "_t".into(),
            value: "v".into(),
            domain: None,
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        };
        let subdomain = PlatformCookie {
            name: "_t".into(),
            value: "v".into(),
            domain: Some(".linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };
        let host_only_score = score_platform_cookie(&host_only, "linux.do");
        let subdomain_score = score_platform_cookie(&subdomain, "linux.do");
        assert!(host_only_score > subdomain_score);
    }

    #[test]
    fn exact_host_match_scores_higher_than_subdomain() {
        let exact = PlatformCookie {
            name: "_t".into(),
            value: "v".into(),
            domain: Some("linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };
        let subdomain = PlatformCookie {
            name: "_t".into(),
            value: "v".into(),
            domain: Some(".linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };
        let exact_score = score_platform_cookie(&exact, "linux.do");
        let subdomain_score = score_platform_cookie(&subdomain, "linux.do");
        assert!(exact_score > subdomain_score);
    }

    #[test]
    fn host_only_scores_higher_than_exact_match() {
        let host_only = PlatformCookie {
            name: "_t".into(),
            value: "v".into(),
            domain: None,
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        };
        let exact = PlatformCookie {
            name: "_t".into(),
            value: "v".into(),
            domain: Some("linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };
        let host_only_score = score_platform_cookie(&host_only, "linux.do");
        let exact_score = score_platform_cookie(&exact, "linux.do");
        assert!(host_only_score > exact_score);
    }

    #[test]
    fn empty_value_scores_lower_than_non_empty() {
        let empty = PlatformCookie {
            name: "_t".into(),
            value: String::new(),
            domain: None,
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        };
        let non_empty = PlatformCookie {
            name: "_t".into(),
            value: "v".into(),
            domain: None,
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        };
        let empty_score = score_platform_cookie(&empty, "linux.do");
        let non_empty_score = score_platform_cookie(&non_empty, "linux.do");
        assert!(non_empty_score > empty_score);
    }

    #[test]
    fn scored_apply_picks_host_only_over_subdomain_for_same_name() {
        let mut snapshot = CookieSnapshot::default();
        snapshot.scored_apply_platform_cookies(
            &[
                PlatformCookie {
                    name: "_t".into(),
                    value: "subdomain-value".into(),
                    domain: Some(".linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
                PlatformCookie {
                    name: "_t".into(),
                    value: "host-only-value".into(),
                    domain: None,
                    path: None,
                    expires_at_unix_ms: None,
                    same_site: None,
                },
            ],
            "linux.do",
            true,
        );
        assert_eq!(snapshot.t_token.as_deref(), Some("host-only-value"));
    }

    #[test]
    fn canonical_storage_key_excludes_host_only_flag() {
        let mut host_only = CanonicalCookie::new("_t", "host", "https://linux.do/");
        host_only.host_only = true;
        host_only.domain = None;

        let mut domain_cookie = CanonicalCookie::new("_t", "domain", "https://linux.do/");
        domain_cookie.host_only = false;
        domain_cookie.domain = Some(".linux.do".into());

        assert_eq!(host_only.storage_key(), domain_cookie.storage_key());
    }

    #[test]
    fn canonical_freshness_prefers_version_then_expiry_then_creation_time() {
        let mut existing = CanonicalCookie::new("cf_clearance", "old", "https://linux.do/");
        existing.version = 2;
        existing.expires_at_unix_ms = Some(1000);
        existing.creation_time_unix_ms = 1000;

        let mut lower_version = existing.clone();
        lower_version.version = 1;
        lower_version.expires_at_unix_ms = Some(9999);
        assert!(!lower_version.is_fresher_than(&existing));

        let mut later_expiry = existing.clone();
        later_expiry.expires_at_unix_ms = Some(2000);
        assert!(later_expiry.is_fresher_than(&existing));

        let mut later_creation = existing.clone();
        later_creation.expires_at_unix_ms = existing.expires_at_unix_ms;
        later_creation.creation_time_unix_ms = 2000;
        assert!(later_creation.is_fresher_than(&existing));
    }

    #[test]
    fn trusted_replacement_bumps_version_when_value_changes() {
        let mut existing = CanonicalCookie::new("_t", "old", "https://linux.do/");
        existing.version = 7;
        existing.creation_time_unix_ms = 100;
        existing.last_access_time_unix_ms = 200;

        let replacement = CanonicalCookie::new("_t", "new", "https://linux.do/")
            .with_trusted_version_from(&existing);

        assert_eq!(replacement.version, 8);
        assert_eq!(replacement.creation_time_unix_ms, 100);
        assert_eq!(replacement.last_access_time_unix_ms, 200);
    }

    #[test]
    fn canonical_set_cookie_header_preserves_metadata() {
        let mut cookie = CanonicalCookie::new("cf_clearance", "value", "https://linux.do/");
        cookie.host_only = false;
        cookie.domain = Some(".linux.do".into());
        cookie.path = "/".into();
        cookie.secure = true;
        cookie.http_only = true;
        cookie.same_site = CookieSameSite::None;
        cookie.partitioned = true;
        cookie.max_age_seconds = Some(120);

        let header = cookie.to_set_cookie_header();

        assert!(header.contains("cf_clearance=value"));
        assert!(header.contains("Domain=.linux.do"));
        assert!(header.contains("Path=/"));
        assert!(header.contains("Secure"));
        assert!(header.contains("HttpOnly"));
        assert!(header.contains("SameSite=None"));
        assert!(header.contains("Partitioned"));
        assert!(header.contains("Max-Age=120"));
    }
}
