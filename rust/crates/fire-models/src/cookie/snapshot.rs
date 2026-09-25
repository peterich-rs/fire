use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::{
    evaluate_cf_clearance_replacement, is_cf_clearance_cookie_name, normalize_cf_clearance_value,
    CfClearanceReplaceDecision,
};

use super::canonical::{
    canonical_cookie_matches_url, canonical_cookies_from_platform, current_unix_ms,
    default_linux_do_url, normalized_cookie_domain, normalized_cookie_domain_for_storage,
    score_platform_cookie, CanonicalCookie, CanonicalCookieStore, CookieSameSite, CookieSource,
    CookieTrust, PlatformCookie,
};
use super::sweep::{
    canonical_cookie_from_webview_info, delete_actions_for_variants,
    is_cloudflare_clearance_cookie_name, is_critical_cookie_name, matching_webview_cookie_infos,
    select_sweep_winner, variants_match_selected_winner, CookieSweepIntent, CookieSweepPlan,
    NuclearResetPlan, WebViewCookieAction, WebViewCookieInfo,
};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookieSnapshot {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
    pub cf_clearance: Option<String>,
    pub csrf_token: Option<String>,
    #[serde(default)]
    pub last_challenged_cf_clearance: Option<String>,
    #[serde(default)]
    pub platform_cookies: Vec<PlatformCookie>,
    #[serde(default)]
    pub canonical_cookies: Vec<CanonicalCookie>,
}

impl CookieSnapshot {
    pub fn has_login_session(&self) -> bool {
        if self.has_canonical_cookie_name("_t") {
            return latest_non_empty_canonical_cookie_value(&self.canonical_cookies, "_t")
                .is_some();
        }
        if !self.platform_cookies.is_empty() {
            return latest_non_empty_platform_cookie_value(&self.platform_cookies, "_t").is_some();
        }
        is_non_empty(self.t_token.as_deref())
    }

    pub fn has_forum_session(&self) -> bool {
        if self.has_canonical_cookie_name("_forum_session") {
            return latest_non_empty_canonical_cookie_value(
                &self.canonical_cookies,
                "_forum_session",
            )
            .is_some();
        }
        if !self.platform_cookies.is_empty() {
            return latest_non_empty_platform_cookie_value(
                &self.platform_cookies,
                "_forum_session",
            )
            .is_some();
        }
        is_non_empty(self.forum_session.as_deref())
    }

    pub fn has_cloudflare_clearance(&self) -> bool {
        if self.has_canonical_cookie_name("cf_clearance") {
            return latest_non_empty_canonical_cookie_value(
                &self.canonical_cookies,
                "cf_clearance",
            )
            .is_some();
        }
        if !self.platform_cookies.is_empty() {
            return latest_non_empty_platform_cookie_value(&self.platform_cookies, "cf_clearance")
                .is_some();
        }
        is_non_empty(self.cf_clearance.as_deref())
    }

    pub fn has_csrf_token(&self) -> bool {
        is_non_empty(self.csrf_token.as_deref())
    }

    pub fn can_authenticate_requests(&self) -> bool {
        self.has_login_session() && self.has_forum_session()
    }

    pub fn note_cf_clearance_challenged(&mut self, value: Option<&str>) {
        let normalized = value
            .map(normalize_cf_clearance_value)
            .filter(|value| !value.is_empty());
        if let Some(value) = normalized {
            self.last_challenged_cf_clearance = Some(value);
        }
    }

    pub fn reset_cf_clearance_authority(&mut self) {
        self.last_challenged_cf_clearance = None;
    }

    pub fn should_write_cf_clearance(&self, candidate: &str, verified: bool) -> bool {
        matches!(
            evaluate_cf_clearance_replacement(
                self.incumbent_cf_clearance_value().as_deref(),
                self.incumbent_cf_clearance_expires_at(),
                self.last_challenged_cf_clearance.as_deref(),
                candidate,
                verified,
                current_unix_ms(),
            ),
            CfClearanceReplaceDecision::Allow
        )
    }

    fn incumbent_cf_clearance_value(&self) -> Option<String> {
        latest_non_empty_canonical_cookie_value(&self.canonical_cookies, "cf_clearance")
            .or_else(|| {
                latest_non_empty_platform_cookie_value(&self.platform_cookies, "cf_clearance")
            })
            .or_else(|| {
                self.cf_clearance
                    .as_deref()
                    .map(normalize_cf_clearance_value)
                    .filter(|value| !value.is_empty())
            })
    }

    fn incumbent_cf_clearance_expires_at(&self) -> Option<i64> {
        let incumbent = self.incumbent_cf_clearance_value()?;
        self.canonical_cookies
            .iter()
            .find(|cookie| {
                is_cf_clearance_cookie_name(&cookie.name)
                    && normalize_cf_clearance_value(&cookie.value) == incumbent
            })
            .and_then(|cookie| cookie.expires_at_unix_ms)
            .or_else(|| {
                self.platform_cookies.iter().find_map(|cookie| {
                    (is_cf_clearance_cookie_name(&cookie.name)
                        && normalize_cf_clearance_value(&cookie.value) == incumbent)
                        .then_some(cookie.expires_at_unix_ms)
                        .flatten()
                })
            })
    }

    fn filter_cf_clearance_platform_cookies(
        &self,
        cookies: &[PlatformCookie],
        verified: bool,
    ) -> Vec<PlatformCookie> {
        cookies
            .iter()
            .filter(|cookie| {
                !is_cf_clearance_cookie_name(&cookie.name)
                    || self.should_write_cf_clearance(&cookie.value, verified)
            })
            .cloned()
            .collect()
    }

    fn filter_cf_clearance_canonical_cookies(
        &self,
        cookies: &[CanonicalCookie],
        verified: bool,
    ) -> Vec<CanonicalCookie> {
        cookies
            .iter()
            .filter(|cookie| {
                !is_cf_clearance_cookie_name(&cookie.name)
                    || self.should_write_cf_clearance(&cookie.value, verified)
            })
            .cloned()
            .collect()
    }

    pub fn replace_verified_cf_clearance(&mut self, uri: &url::Url, cookie: CanonicalCookie) {
        self.delete_canonical_cookie_by_name(uri, "cf_clearance");
        self.platform_cookies
            .retain(|item| !is_cf_clearance_cookie_name(&item.name));
        let platform = PlatformCookie {
            name: cookie.name.clone(),
            value: cookie.value.clone(),
            domain: cookie.domain.clone().or_else(|| {
                uri.host_str()
                    .map(|host| host.trim_start_matches('.').to_ascii_lowercase())
            }),
            path: Some(cookie.path.clone()),
            expires_at_unix_ms: cookie.expires_at_unix_ms,
            same_site: match cookie.same_site {
                CookieSameSite::None => Some("None".into()),
                CookieSameSite::Lax => Some("Lax".into()),
                CookieSameSite::Strict => Some("Strict".into()),
                CookieSameSite::Unspecified => None,
            },
        };
        self.merge_canonical_cookies_internal(uri, &[cookie], CookieTrust::Trusted, true);
        merge_platform_cookie_batch(&mut self.platform_cookies, std::slice::from_ref(&platform));
        self.refresh_known_platform_cookie_fields();
        self.last_challenged_cf_clearance = None;
    }

    pub fn merge_patch(&mut self, patch: &Self) {
        merge_string_patch(&mut self.t_token, patch.t_token.clone());
        merge_string_patch(&mut self.forum_session, patch.forum_session.clone());
        if let Some(clearance) = patch.cf_clearance.as_deref() {
            if self.should_write_cf_clearance(clearance, false) {
                merge_string_patch(&mut self.cf_clearance, patch.cf_clearance.clone());
            }
        }
        merge_string_patch(&mut self.csrf_token, patch.csrf_token.clone());
        if let Some(challenged) = patch.last_challenged_cf_clearance.as_deref() {
            self.note_cf_clearance_challenged(Some(challenged));
        }
        if !patch.platform_cookies.is_empty() {
            let cookies = self.filter_cf_clearance_platform_cookies(&patch.platform_cookies, false);
            merge_platform_cookie_batch(&mut self.platform_cookies, &cookies);
            self.refresh_known_platform_cookie_fields();
        }
        if !patch.canonical_cookies.is_empty() {
            let cookies =
                self.filter_cf_clearance_canonical_cookies(&patch.canonical_cookies, false);
            merge_canonical_cookie_batch(
                &mut self.canonical_cookies,
                &cookies,
                CookieTrust::Trusted,
            );
            self.refresh_known_canonical_cookie_fields();
        }
    }

    pub fn merge_platform_cookies(&mut self, cookies: &[PlatformCookie]) {
        let cookies = self.filter_cf_clearance_platform_cookies(cookies, false);
        merge_string_patch(
            &mut self.t_token,
            latest_non_empty_platform_cookie_value(&cookies, "_t"),
        );
        merge_string_patch(
            &mut self.forum_session,
            latest_non_empty_platform_cookie_value(&cookies, "_forum_session"),
        );
        if let Some(clearance) = latest_non_empty_platform_cookie_value(&cookies, "cf_clearance") {
            if self.should_write_cf_clearance(&clearance, false) {
                merge_string_patch(&mut self.cf_clearance, Some(clearance));
            }
        }
        merge_platform_cookie_batch(&mut self.platform_cookies, &cookies);
        self.refresh_known_platform_cookie_fields();
    }

    pub fn merge_platform_cookies_for_origin(
        &mut self,
        cookies: &[PlatformCookie],
        origin_url: &url::Url,
        source: CookieSource,
        trust: CookieTrust,
    ) {
        self.merge_platform_cookies(cookies);
        let canonical_cookies = canonical_cookies_from_platform(cookies, origin_url, source);
        if !canonical_cookies.is_empty() {
            self.merge_canonical_cookies(origin_url, &canonical_cookies, trust);
        }
    }

    pub fn apply_platform_cookies(&mut self, cookies: &[PlatformCookie]) {
        let incoming_clearance = latest_non_empty_platform_cookie_value(cookies, "cf_clearance");
        let keep_incumbent = incoming_clearance
            .as_deref()
            .is_some_and(|value| !self.should_write_cf_clearance(value, false));
        let preserved_clearance = if keep_incumbent {
            self.cf_clearance.clone()
        } else {
            None
        };
        let preserved_platform = if keep_incumbent {
            self.platform_cookies
                .iter()
                .filter(|cookie| is_cf_clearance_cookie_name(&cookie.name))
                .cloned()
                .collect()
        } else {
            Vec::new()
        };
        let cookies = self.filter_cf_clearance_platform_cookies(cookies, false);
        self.t_token = latest_non_empty_platform_cookie_value(&cookies, "_t");
        self.forum_session = latest_non_empty_platform_cookie_value(&cookies, "_forum_session");
        self.cf_clearance = if keep_incumbent {
            preserved_clearance.clone()
        } else {
            latest_non_empty_platform_cookie_value(&cookies, "cf_clearance")
        };
        self.platform_cookies = normalized_platform_cookies(&cookies);
        if keep_incumbent {
            merge_platform_cookie_batch(&mut self.platform_cookies, &preserved_platform);
        }
        self.refresh_known_platform_cookie_fields();
        if keep_incumbent && self.cf_clearance.is_none() {
            self.cf_clearance = preserved_clearance;
        }
    }

    pub fn apply_platform_cookies_for_origin(
        &mut self,
        cookies: &[PlatformCookie],
        origin_url: &url::Url,
        source: CookieSource,
        trust: CookieTrust,
    ) {
        let incoming_clearance = latest_non_empty_platform_cookie_value(cookies, "cf_clearance");
        let keep_incumbent = incoming_clearance
            .as_deref()
            .is_some_and(|value| !self.should_write_cf_clearance(value, false));
        let preserved_canonical = if keep_incumbent {
            self.canonical_cookies
                .iter()
                .filter(|cookie| is_cf_clearance_cookie_name(&cookie.name))
                .cloned()
                .collect()
        } else {
            Vec::new()
        };
        self.apply_platform_cookies(cookies);
        let cookies = self.filter_cf_clearance_platform_cookies(cookies, false);
        let canonical_cookies = canonical_cookies_from_platform(&cookies, origin_url, source);
        let mut store = CanonicalCookieStore::new();
        store.save_canonical_cookies(origin_url, canonical_cookies, trust);
        self.canonical_cookies = store.into_cookies();
        if keep_incumbent && !preserved_canonical.is_empty() {
            let mut store =
                CanonicalCookieStore::from_cookies(std::mem::take(&mut self.canonical_cookies));
            store.save_canonical_cookies(origin_url, preserved_canonical, CookieTrust::Trusted);
            self.canonical_cookies = store.into_cookies();
        }
        self.refresh_known_canonical_cookie_fields();
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

    pub fn scored_apply_platform_cookies_for_origin(
        &mut self,
        cookies: &[PlatformCookie],
        origin_url: &url::Url,
        source: CookieSource,
        trust: CookieTrust,
        allow_low_confidence_session_cookies: bool,
    ) {
        let host = origin_url.host_str().unwrap_or_default();
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
        self.apply_platform_cookies_for_origin(&winners, origin_url, source, trust);
    }

    pub fn merge_canonical_cookies(
        &mut self,
        uri: &url::Url,
        cookies: &[CanonicalCookie],
        trust: CookieTrust,
    ) {
        self.merge_canonical_cookies_internal(uri, cookies, trust, false);
    }

    fn merge_canonical_cookies_internal(
        &mut self,
        uri: &url::Url,
        cookies: &[CanonicalCookie],
        trust: CookieTrust,
        verified: bool,
    ) {
        let cookies = self.filter_cf_clearance_canonical_cookies(cookies, verified);
        let mut store =
            CanonicalCookieStore::from_cookies(std::mem::take(&mut self.canonical_cookies));
        store.save_canonical_cookies(uri, cookies, trust);
        self.canonical_cookies = store.into_cookies();
        self.refresh_known_canonical_cookie_fields();
    }

    pub fn apply_canonical_cookies(
        &mut self,
        uri: &url::Url,
        cookies: &[CanonicalCookie],
        trust: CookieTrust,
    ) {
        let cookies = self.filter_cf_clearance_canonical_cookies(cookies, false);
        let mut store = CanonicalCookieStore::new();
        store.save_canonical_cookies(uri, cookies, trust);
        self.canonical_cookies = store.into_cookies();
        self.refresh_known_canonical_cookie_fields();
    }

    pub fn delete_canonical_cookie_by_name(&mut self, uri: &url::Url, name: &str) -> usize {
        let mut store =
            CanonicalCookieStore::from_cookies(std::mem::take(&mut self.canonical_cookies));
        let removed = store.delete_by_name(uri, name);
        self.canonical_cookies = store.into_cookies();
        match name {
            "_t" => self.t_token = None,
            "_forum_session" => self.forum_session = None,
            "cf_clearance" => self.cf_clearance = None,
            _ => {}
        }
        self.refresh_known_canonical_cookie_fields();
        removed
    }

    pub fn webview_priming_payload(&self, uri: &url::Url) -> Vec<WebViewCookieAction> {
        let store = CanonicalCookieStore::from_cookies(self.canonical_cookies.clone());
        let mut seen_critical_names = Vec::<String>::new();
        let mut actions = Vec::new();
        for cookie in store.load_for_request(uri) {
            if cookie.value.trim().is_empty() {
                continue;
            }
            // cf_clearance is WebView-authored only. Never prime jar copies back into
            // the browser store — Set-Cookie replay can drop Partitioned and create a
            // ghost variant that native traffic may send forever.
            if is_cloudflare_clearance_cookie_name(&cookie.name) {
                continue;
            }
            if is_critical_cookie_name(&cookie.name)
                && seen_critical_names
                    .iter()
                    .any(|name| name.eq_ignore_ascii_case(&cookie.name))
            {
                continue;
            }
            if is_critical_cookie_name(&cookie.name) {
                seen_critical_names.push(cookie.name.clone());
                actions.push(WebViewCookieAction::DeleteByName {
                    url: uri.as_str().to_string(),
                    name: cookie.name.clone(),
                });
            }
            actions.push(WebViewCookieAction::SetRaw {
                url: uri.as_str().to_string(),
                set_cookie: cookie.to_set_cookie_header(),
            });
        }
        actions
    }

    pub fn cookie_sweep_plan(
        &self,
        uri: &url::Url,
        name: &str,
        webview_cookies: &[WebViewCookieInfo],
    ) -> CookieSweepPlan {
        let variants = matching_webview_cookie_infos(webview_cookies, name);
        let canonical = self.canonical_cookie_for_request(uri, name);
        let selected_winner = select_sweep_winner(uri, canonical.as_ref(), &variants);

        // cf_clearance sweep is read-only against WebView. A healthy jar
        // incumbent stays; the browser store is never rewritten from jar.
        let actions = if is_cloudflare_clearance_cookie_name(name)
            || (variants.len() <= 1
                && variants_match_selected_winner(&variants, selected_winner.as_ref()))
        {
            Vec::new()
        } else {
            let mut actions = delete_actions_for_variants(uri, &variants);
            if let Some(winner) = selected_winner.as_ref() {
                actions.push(WebViewCookieAction::SetRaw {
                    url: uri.as_str().to_string(),
                    set_cookie: winner.to_set_cookie_header(),
                });
            }
            actions
        };

        CookieSweepPlan {
            name: name.to_string(),
            intent: CookieSweepIntent::EnsureUnique,
            actions,
            selected_winner,
        }
    }

    pub fn cookie_delete_plan(
        &self,
        uri: &url::Url,
        name: &str,
        webview_cookies: &[WebViewCookieInfo],
    ) -> CookieSweepPlan {
        let variants = matching_webview_cookie_infos(webview_cookies, name);
        CookieSweepPlan {
            name: name.to_string(),
            intent: CookieSweepIntent::Delete,
            actions: delete_actions_for_variants(uri, &variants),
            selected_winner: None,
        }
    }

    pub fn cookie_nuclear_reset_plan(
        &self,
        uri: &url::Url,
        webview_cookies: &[WebViewCookieInfo],
    ) -> NuclearResetPlan {
        let mut names = Vec::<String>::new();
        for cookie in &self.canonical_cookies {
            if canonical_cookie_matches_url(cookie, uri)
                && !names.iter().any(|name| name == &cookie.name)
            {
                names.push(cookie.name.clone());
            }
        }
        for cookie in webview_cookies {
            if !cookie.name.trim().is_empty() && !names.iter().any(|name| name == &cookie.name) {
                names.push(cookie.name.clone());
            }
        }

        let mut actions = Vec::new();
        for name in names {
            // Leave browser-authored cf_clearance alone during nuclear reset.
            if is_cloudflare_clearance_cookie_name(&name) {
                continue;
            }
            let variants = matching_webview_cookie_infos(webview_cookies, &name);
            actions.extend(delete_actions_for_variants(uri, &variants));
        }
        actions.extend(self.webview_priming_payload(uri));
        NuclearResetPlan { actions }
    }

    pub fn commit_cookie_sweep_result(
        &mut self,
        uri: &url::Url,
        name: &str,
        intent: CookieSweepIntent,
        webview_cookies: &[WebViewCookieInfo],
    ) {
        match intent {
            CookieSweepIntent::Delete => {
                self.delete_canonical_cookie_by_name(uri, name);
            }
            CookieSweepIntent::EnsureUnique => {
                let variants = matching_webview_cookie_infos(webview_cookies, name);
                let winner_info = if is_cloudflare_clearance_cookie_name(name) {
                    self.select_cf_clearance_sweep_variant(&variants)
                } else {
                    match variants.as_slice() {
                        [variant] => Some(*variant),
                        _ => None,
                    }
                };
                let Some(variant) = winner_info else {
                    return;
                };
                let canonical_template = self.canonical_cookie_for_request(uri, name);
                let Some(cookie) =
                    canonical_cookie_from_webview_info(variant, uri, canonical_template.as_ref())
                else {
                    return;
                };
                self.merge_canonical_cookies(uri, &[cookie], CookieTrust::Trusted);
            }
        }
    }

    fn select_cf_clearance_sweep_variant<'a>(
        &self,
        variants: &[&'a WebViewCookieInfo],
    ) -> Option<&'a WebViewCookieInfo> {
        let incumbent = self.incumbent_cf_clearance_value();
        if let Some(incumbent) = incumbent.as_deref() {
            if let Some(matching) = variants.iter().copied().find(|cookie| {
                normalize_cf_clearance_value(&cookie.value) == incumbent
                    && !cookie.value.trim().is_empty()
            }) {
                return Some(matching);
            }
            if !self.should_write_cf_clearance(
                variants
                    .iter()
                    .find(|cookie| !cookie.value.trim().is_empty())
                    .map(|cookie| cookie.value.as_str())
                    .unwrap_or_default(),
                false,
            ) {
                return None;
            }
        }
        variants.iter().copied().find(|cookie| {
            !cookie.value.trim().is_empty() && self.should_write_cf_clearance(&cookie.value, false)
        })
    }

    fn canonical_cookie_for_request(&self, uri: &url::Url, name: &str) -> Option<CanonicalCookie> {
        let store = CanonicalCookieStore::from_cookies(self.canonical_cookies.clone());
        store
            .load_for_request(uri)
            .into_iter()
            .find(|cookie| cookie.name == name && !cookie.value.trim().is_empty())
    }

    pub fn clear_login_state(&mut self, preserve_cf_clearance: bool) {
        self.t_token = None;
        self.forum_session = None;
        self.csrf_token = None;
        self.reset_cf_clearance_authority();
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
        self.canonical_cookies.retain(|cookie| {
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

    pub fn refresh_known_canonical_cookie_fields(&mut self) {
        let now_unix_ms = current_unix_ms();
        self.canonical_cookies.retain(|cookie| {
            !cookie.is_expired_at(now_unix_ms) && !is_deleted_cookie_value(&cookie.value)
        });
        if self.has_canonical_cookie_name("_t") {
            self.t_token = latest_non_empty_canonical_cookie_value(&self.canonical_cookies, "_t");
        }
        if self.has_canonical_cookie_name("_forum_session") {
            self.forum_session =
                latest_non_empty_canonical_cookie_value(&self.canonical_cookies, "_forum_session");
        }
        if self.has_canonical_cookie_name("cf_clearance") {
            self.cf_clearance =
                latest_non_empty_canonical_cookie_value(&self.canonical_cookies, "cf_clearance");
        }
    }

    fn has_canonical_cookie_name(&self, name: &str) -> bool {
        let now_unix_ms = current_unix_ms();
        self.canonical_cookies.iter().any(|cookie| {
            cookie.name == name
                && !cookie.is_expired_at(now_unix_ms)
                && !is_deleted_cookie_value(&cookie.value)
        })
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
        .filter(|cookie| {
            cookie.name == name && !cookie.value.is_empty() && !cookie.is_expired_at(now_unix_ms)
        })
        .max_by(|left, right| {
            if is_cf_clearance_cookie_name(name) {
                std::cmp::Ordering::Equal
            } else {
                left.expires_at_unix_ms
                    .unwrap_or(0)
                    .cmp(&right.expires_at_unix_ms.unwrap_or(0))
            }
        })
        .map(|cookie| cookie.value.clone())
}

fn merge_canonical_cookie_batch(
    current: &mut Vec<CanonicalCookie>,
    incoming: &[CanonicalCookie],
    trust: CookieTrust,
) {
    let mut store = CanonicalCookieStore::from_cookies(std::mem::take(current));
    for cookie in incoming {
        let uri = cookie
            .origin_url
            .as_deref()
            .and_then(|value| url::Url::parse(value).ok())
            .or_else(default_linux_do_url);
        let Some(uri) = uri else {
            continue;
        };
        store.save_canonical_cookies(&uri, [cookie.clone()], trust);
    }
    *current = store.into_cookies();
}

fn latest_non_empty_canonical_cookie_value(
    cookies: &[CanonicalCookie],
    name: &str,
) -> Option<String> {
    let now_unix_ms = current_unix_ms();
    cookies
        .iter()
        .filter(|cookie| {
            cookie.name == name
                && !cookie.value.is_empty()
                && !cookie.is_expired_at(now_unix_ms)
                && !is_deleted_cookie_value(&cookie.value)
        })
        .max_by(|left, right| {
            left.version.cmp(&right.version).then_with(|| {
                if is_cf_clearance_cookie_name(name) {
                    left.creation_time_unix_ms.cmp(&right.creation_time_unix_ms)
                } else {
                    left.expires_at_unix_ms
                        .cmp(&right.expires_at_unix_ms)
                        .then_with(|| left.creation_time_unix_ms.cmp(&right.creation_time_unix_ms))
                }
            })
        })
        .map(|cookie| cookie.value.clone())
}
