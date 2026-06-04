use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

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
    if !cookie.value.is_empty() {
        score += 100_000;
    }
    if !cookie.is_expired_now() {
        score += 50_000;
    }
    let raw_domain = cookie.domain.as_deref().map(str::trim).filter(|d| !d.is_empty());
    match raw_domain {
        None => {
            score += 40_000;
        }
        Some(domain) if domain.starts_with('.') => {
            let normalized = domain.trim_start_matches('.').to_ascii_lowercase();
            if normalized.eq_ignore_ascii_case(host) {
                score += 20_000;
            } else if host
                .to_ascii_lowercase()
                .ends_with(&format!(".{normalized}"))
            {
                score += 20_000;
            }
        }
        Some(domain) => {
            let normalized = domain.to_ascii_lowercase();
            if normalized.eq_ignore_ascii_case(host) {
                score += 30_000;
            } else if host
                .to_ascii_lowercase()
                .ends_with(&format!(".{normalized}"))
            {
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
}
