use std::sync::OnceLock;

use fire_models::{BootstrapArtifacts, CookieSnapshot};
use regex::Regex;
use serde_json::Value;
use tracing::warn;

#[derive(Debug, Default)]
pub(crate) struct ParsedHomeState {
    pub(crate) cookies_patch: CookieSnapshot,
    pub(crate) bootstrap_patch: BootstrapArtifacts,
}

pub(crate) fn parse_home_state(base_url: &str, html: &str) -> ParsedHomeState {
    let mut parsed = ParsedHomeState {
        bootstrap_patch: BootstrapArtifacts {
            base_url: base_url.to_string(),
            ..BootstrapArtifacts::default()
        },
        ..ParsedHomeState::default()
    };

    parsed.cookies_patch.csrf_token = find_meta_content(html, "csrf-token");
    parsed.bootstrap_patch.shared_session_key = find_meta_content(html, "shared_session_key");
    parsed.bootstrap_patch.current_username = find_meta_content(html, "current-username");
    parsed.bootstrap_patch.discourse_base_uri = find_meta_content(html, "discourse-base-uri");
    parsed.bootstrap_patch.turnstile_sitekey = find_first_attr(html, "data-sitekey");

    if let Some(preloaded_json) = find_first_attr(html, "data-preloaded") {
        let decoded = decode_html_entities(&preloaded_json);
        parsed.bootstrap_patch.preloaded_json = Some(decoded.clone());
        parsed.bootstrap_patch.has_preloaded_data = true;
        hydrate_preloaded_fields(&decoded, &mut parsed.bootstrap_patch);
    }

    parsed
}

pub(crate) fn hydrate_preloaded_fields(preloaded_json: &str, bootstrap: &mut BootstrapArtifacts) {
    let Ok(preloaded) = serde_json::from_str::<Value>(preloaded_json) else {
        warn!("failed to parse data-preloaded json");
        return;
    };

    if let Some(username) = preloaded
        .get("currentUser")
        .and_then(|value| value.get("username"))
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
    {
        bootstrap.current_username = Some(username.to_string());
    }

    if let Some(current_user_id) = preloaded
        .get("currentUser")
        .and_then(|value| value.get("id"))
        .and_then(Value::as_u64)
    {
        bootstrap.current_user_id = Some(current_user_id);
    }

    if let Some(notification_channel_position) = preloaded
        .get("currentUser")
        .and_then(|value| value.get("notification_channel_position"))
        .and_then(|value| {
            value
                .as_i64()
                .or_else(|| value.as_u64().map(|id| id as i64))
        })
    {
        bootstrap.notification_channel_position = Some(notification_channel_position);
    }

    if let Some(long_polling_base_url) = preloaded
        .get("siteSettings")
        .and_then(|value| value.get("long_polling_base_url"))
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
    {
        bootstrap.long_polling_base_url = Some(long_polling_base_url.to_string());
    }

    if let Some(meta) = preloaded.get("topicTrackingStateMeta") {
        if !meta.is_null() {
            bootstrap.topic_tracking_state_meta = serde_json::to_string(meta).ok();
        }
    }
}

fn find_meta_content(html: &str, target_name: &str) -> Option<String> {
    for tag in all_tags(html) {
        if !tag.starts_with("<meta") && !tag.starts_with("<META") {
            continue;
        }

        let name = extract_attr(tag, "name")?;
        if !name.eq_ignore_ascii_case(target_name) {
            continue;
        }

        if let Some(content) = extract_attr(tag, "content") {
            return Some(decode_html_entities(&content));
        }
    }

    None
}

fn find_first_attr(html: &str, attribute_name: &str) -> Option<String> {
    for tag in all_tags(html) {
        if let Some(value) = extract_attr(tag, attribute_name) {
            return Some(decode_html_entities(&value));
        }
    }

    None
}

fn all_tags(html: &str) -> impl Iterator<Item = &str> {
    static TAG_RE: OnceLock<Regex> = OnceLock::new();
    let regex = TAG_RE.get_or_init(|| Regex::new(r"(?is)<[^>]+>").expect("tag regex"));
    regex.find_iter(html).map(|matched| matched.as_str())
}

fn extract_attr(tag: &str, attribute_name: &str) -> Option<String> {
    static ATTR_RE: OnceLock<Regex> = OnceLock::new();
    let regex = ATTR_RE.get_or_init(|| {
        Regex::new(
            r#"(?is)\b([a-zA-Z0-9:_-]+)\s*=\s*"([^"]*)"|\b([a-zA-Z0-9:_-]+)\s*=\s*'([^']*)'"#,
        )
        .expect("attr regex")
    });

    for captures in regex.captures_iter(tag) {
        let (name, value) = if let (Some(name), Some(value)) = (captures.get(1), captures.get(2)) {
            (name.as_str(), value.as_str())
        } else if let (Some(name), Some(value)) = (captures.get(3), captures.get(4)) {
            (name.as_str(), value.as_str())
        } else {
            continue;
        };

        if !name.eq_ignore_ascii_case(attribute_name) {
            continue;
        }
        return Some(value.to_string());
    }

    None
}

fn decode_html_entities(raw: &str) -> String {
    raw.replace("&quot;", "\"")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&#39;", "'")
}
