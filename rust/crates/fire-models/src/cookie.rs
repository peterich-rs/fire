use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlatformCookie {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub expires_at_unix_ms: Option<i64>,
}

impl PlatformCookie {
    pub fn is_expired_at(&self, now_unix_ms: i64) -> bool {
        self.expires_at_unix_ms
            .is_some_and(|expires_at_unix_ms| expires_at_unix_ms <= now_unix_ms)
    }

    pub fn is_expired_now(&self) -> bool {
        self.is_expired_at(current_unix_ms())
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
        let Some((name, domain, path)) = normalized_platform_cookie_key(cookie) else {
            continue;
        };
        current.retain(|existing| {
            normalized_platform_cookie_key(existing).is_none_or(|existing_key| {
                existing_key != (name.clone(), domain.clone(), path.clone())
            })
        });
        if is_deleted_cookie_value(&cookie.value) || cookie.is_expired_at(now_unix_ms) {
            continue;
        }
        current.push(PlatformCookie {
            name,
            value: cookie.value.trim().to_string(),
            domain,
            path: Some(path),
            expires_at_unix_ms: cookie.expires_at_unix_ms,
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
    let domain = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase());
    let path = cookie
        .path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("/");
    Some((name.to_string(), domain, path.to_string()))
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
