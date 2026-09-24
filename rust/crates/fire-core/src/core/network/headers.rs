use http::header::{HeaderMap, HeaderValue, ACCEPT_LANGUAGE, ORIGIN, REFERER, USER_AGENT};
use http::Request;
use openwire::RequestBody;
use url::Url;

use super::client::FireCommonProfileHeaderContext;
use super::constants::{FIRE_ACCEPT_LANGUAGE, FIRE_MESSAGE_BUS_ACCEPT};
use super::FireRequestProfile;

pub(crate) fn request_origin(base_url: &Url) -> String {
    let mut origin = base_url.clone();
    origin.set_path("");
    origin.set_query(None);
    origin.set_fragment(None);
    let value = origin.as_str().trim_end_matches('/');
    value.to_string()
}

pub(crate) fn request_referer(base_url: &Url) -> String {
    let mut referer = base_url.clone();
    referer.set_path("/");
    referer.set_query(None);
    referer.set_fragment(None);
    referer.to_string()
}

pub(super) fn apply_common_profile_headers(
    headers: &mut HeaderMap,
    context: FireCommonProfileHeaderContext<'_>,
) {
    insert_string_header_if_missing(headers, USER_AGENT.as_str(), context.user_agent);
    insert_static_header_if_missing(headers, ACCEPT_LANGUAGE.as_str(), FIRE_ACCEPT_LANGUAGE);

    match context.profile {
        FireRequestProfile::HomeHtml => {}
        FireRequestProfile::JsonApi => {
            insert_string_header_if_missing(headers, REFERER.as_str(), context.referer);
            insert_static_header_if_missing(headers, "X-Requested-With", "XMLHttpRequest");
            insert_static_header_if_missing(headers, "Sec-Fetch-Dest", "empty");
            insert_static_header_if_missing(headers, "Sec-Fetch-Mode", "cors");
            insert_static_header_if_missing(
                headers,
                "Sec-Fetch-Site",
                if context.same_origin {
                    "same-origin"
                } else {
                    "cross-site"
                },
            );
            insert_static_header_if_missing(headers, "Priority", "u=1, i");
            if !context.skip_csrf_header {
                if let Some(csrf_token) = context.csrf_token.filter(|value| !value.is_empty()) {
                    insert_string_header_if_missing(headers, "X-CSRF-Token", csrf_token);
                }
            }
            apply_login_headers(headers, context.has_login_session);
        }
        FireRequestProfile::MessageBusPoll => {
            insert_string_header_if_missing(headers, ORIGIN.as_str(), context.origin);
            insert_string_header_if_missing(headers, REFERER.as_str(), context.referer);
            insert_static_header_if_missing(headers, "Accept", FIRE_MESSAGE_BUS_ACCEPT);
            insert_static_header_if_missing(headers, "Sec-Fetch-Dest", "empty");
            insert_static_header_if_missing(headers, "Sec-Fetch-Mode", "cors");
            insert_static_header_if_missing(
                headers,
                "Sec-Fetch-Site",
                if context.same_origin {
                    "same-origin"
                } else {
                    "cross-site"
                },
            );
            insert_static_header_if_missing(headers, "Priority", "u=1, i");
            apply_login_headers(headers, context.has_login_session);
        }
    }
}

pub(super) fn request_uri_origin(request: &Request<RequestBody>) -> Option<String> {
    let uri = request.uri();
    let scheme = uri.scheme_str()?;
    let authority = uri.authority()?.as_str();
    Some(format!("{scheme}://{authority}"))
}

pub(super) fn apply_login_headers(headers: &mut HeaderMap, has_login_session: bool) {
    if has_login_session {
        insert_static_header_if_missing(headers, "Discourse-Logged-In", "true");
        insert_static_header_if_missing(headers, "Discourse-Present", "true");
    }
}

pub(super) fn insert_static_header_if_missing(
    headers: &mut HeaderMap,
    name: &'static str,
    value: &'static str,
) {
    if !headers.contains_key(name) {
        headers.insert(name, HeaderValue::from_static(value));
    }
}

pub(super) fn insert_string_header_if_missing(
    headers: &mut HeaderMap,
    name: &'static str,
    value: &str,
) {
    if headers.contains_key(name) {
        return;
    }
    if let Ok(value) = HeaderValue::from_str(value) {
        headers.insert(name, value);
    }
}
