use std::sync::{Arc, RwLock};

use fire_models::{CookieSnapshot, SessionSnapshot};
use http::header::HeaderValue;
use openwire::CookieJar;
use url::Url;

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
        if !same_cookie_scope(&self.base_url, url) {
            return;
        }

        let mut patch = CookieSnapshot::default();
        for header in cookie_headers {
            let Ok(value) = header.to_str() else {
                continue;
            };
            let Some((name, value)) = parse_set_cookie(value) else {
                continue;
            };

            match name {
                "_t" => patch.t_token = Some(value.to_string()),
                "_forum_session" => patch.forum_session = Some(value.to_string()),
                "cf_clearance" => patch.cf_clearance = Some(value.to_string()),
                _ => {}
            }
        }

        if patch == CookieSnapshot::default() {
            return;
        }

        let mut session = self.session.write().expect("session poisoned");
        session.cookies.merge_patch(&patch);
    }

    fn cookies(&self, url: &Url) -> Option<HeaderValue> {
        if !same_cookie_scope(&self.base_url, url) {
            return None;
        }

        let session = self.session.read().expect("session poisoned");
        let cookies = build_cookie_header(&session.cookies);
        if cookies.is_empty() {
            return None;
        }

        HeaderValue::from_str(&cookies).ok()
    }
}

fn same_cookie_scope(base_url: &Url, request_url: &Url) -> bool {
    base_url.scheme() == request_url.scheme()
        && base_url.host_str() == request_url.host_str()
        && base_url.port_or_known_default() == request_url.port_or_known_default()
}

fn build_cookie_header(cookies: &CookieSnapshot) -> String {
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

fn parse_set_cookie(value: &str) -> Option<(&str, &str)> {
    let first = value.split(';').next()?.trim();
    let (name, value) = first.split_once('=')?;
    let value = if value.is_empty() || value == "del" {
        ""
    } else {
        value
    };
    Some((name.trim(), value))
}
