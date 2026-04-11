use std::sync::OnceLock;

use fire_models::{BootstrapArtifacts, CookieSnapshot, RequiredTagGroup, TopicCategory};
use regex::Regex;
use serde_json::Value;
use tracing::warn;

use crate::json_helpers::{integer_i64, positive_u32, positive_u64};

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
        parsed.bootstrap_patch.preloaded_json = Some(preloaded_json.clone());
        parsed.bootstrap_patch.has_preloaded_data = true;
        hydrate_preloaded_fields(&preloaded_json, &mut parsed.bootstrap_patch);
    }

    parsed
}

pub(crate) fn hydrate_preloaded_fields(preloaded_json: &str, bootstrap: &mut BootstrapArtifacts) {
    let Some(preloaded) = parse_preloaded_payload(preloaded_json) else {
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
        .and_then(|value| positive_u64(Some(value)))
    {
        bootstrap.current_user_id = Some(current_user_id);
    }

    if let Some(notification_channel_position) = preloaded
        .get("currentUser")
        .and_then(|value| value.get("notification_channel_position"))
        .and_then(|value| integer_i64(Some(value)))
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

    hydrate_site_metadata_fields(&preloaded, bootstrap);
    hydrate_site_settings_fields(&preloaded, bootstrap);
}

pub(crate) fn parse_preloaded_payload(preloaded_json: &str) -> Option<Value> {
    let Ok(preloaded) = serde_json::from_str::<Value>(preloaded_json) else {
        warn!("failed to parse data-preloaded json");
        return None;
    };
    Some(normalize_preloaded_payload(&preloaded))
}

fn normalize_preloaded_payload(preloaded: &Value) -> Value {
    let Some(object) = preloaded.as_object() else {
        return preloaded.clone();
    };

    let mut normalized = object.clone();
    for key in [
        "currentUser",
        "siteSettings",
        "site",
        "topicTrackingStateMeta",
        "topicTrackingStates",
    ] {
        let Some(value) = normalized.get(key).cloned() else {
            continue;
        };
        let Some(decoded) = decode_embedded_json_payload(&value) else {
            continue;
        };
        normalized.insert(key.to_string(), decoded);
    }

    Value::Object(normalized)
}

fn decode_embedded_json_payload(value: &Value) -> Option<Value> {
    let raw = value.as_str()?.trim();
    let first = raw.chars().next()?;
    if first != '{' && first != '[' {
        return None;
    }
    serde_json::from_str(raw).ok()
}

pub(crate) fn parse_site_metadata_json(base_url: &str, json: &str) -> BootstrapArtifacts {
    let mut bootstrap = BootstrapArtifacts {
        base_url: base_url.to_string(),
        ..BootstrapArtifacts::default()
    };
    let Ok(value) = serde_json::from_str::<Value>(json) else {
        warn!("failed to parse site.json payload");
        return bootstrap;
    };
    hydrate_site_metadata_fields(&value, &mut bootstrap);
    bootstrap
}

pub(crate) fn hydrate_site_metadata_fields(source: &Value, bootstrap: &mut BootstrapArtifacts) {
    bootstrap.has_site_metadata = has_site_metadata(source);
    bootstrap.top_tags = top_tags_from_preloaded(source);
    bootstrap.can_tag_topics = can_tag_topics_from_preloaded(source).unwrap_or(false);
    bootstrap.categories = categories_from_preloaded(source);
}

pub(crate) fn hydrate_site_settings_fields(source: &Value, bootstrap: &mut BootstrapArtifacts) {
    bootstrap.has_site_settings = has_site_settings(source);
    bootstrap.enabled_reaction_ids = enabled_reaction_ids_from_preloaded(source);
    bootstrap.min_post_length = min_post_length_from_preloaded(source);
    bootstrap.min_topic_title_length = min_topic_title_length_from_preloaded(source);
    bootstrap.min_first_post_length = min_first_post_length_from_preloaded(source);
    bootstrap.default_composer_category = default_composer_category_from_preloaded(source);
}

fn find_meta_content(html: &str, target_name: &str) -> Option<String> {
    for tag in all_tags(html) {
        if !tag.starts_with("<meta") && !tag.starts_with("<META") {
            continue;
        }

        let Some(name) = extract_attr(tag, "name") else {
            continue;
        };
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
    // NOTE: This lightweight scanner is intentionally scoped to Discourse bootstrap tags.
    // If parsing expands beyond meta/data-* extraction, switch to a real HTML parser.
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

pub(crate) fn decode_html_entities(raw: &str) -> String {
    let mut decoded = String::with_capacity(raw.len());
    let mut cursor = raw;

    while let Some(start) = cursor.find('&') {
        decoded.push_str(&cursor[..start]);
        let entity_start = &cursor[start..];

        let Some(end) = entity_start.find(';') else {
            decoded.push_str(entity_start);
            return decoded;
        };

        let entity = &entity_start[1..end];
        if let Some(ch) = decode_html_entity(entity) {
            decoded.push(ch);
        } else {
            decoded.push_str(&entity_start[..=end]);
        }

        cursor = &entity_start[end + 1..];
    }

    decoded.push_str(cursor);
    decoded
}

fn decode_html_entity(entity: &str) -> Option<char> {
    match entity {
        "nbsp" | "#160" => Some(' '),
        "quot" => Some('"'),
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "apos" | "#39" => Some('\''),
        _ => decode_numeric_html_entity(entity),
    }
}

fn decode_numeric_html_entity(entity: &str) -> Option<char> {
    let value = if let Some(hex) = entity
        .strip_prefix("#x")
        .or_else(|| entity.strip_prefix("#X"))
    {
        u32::from_str_radix(hex, 16).ok()?
    } else if let Some(decimal) = entity.strip_prefix('#') {
        decimal.parse::<u32>().ok()?
    } else {
        return None;
    };

    char::from_u32(value)
}

fn categories_from_preloaded(preloaded: &Value) -> Vec<TopicCategory> {
    category_candidates(preloaded)
        .find_map(category_values_from_candidate)
        .map(|values| {
            values
                .iter()
                .filter_map(topic_category_from_value)
                .collect()
        })
        .unwrap_or_default()
}

fn category_candidates(preloaded: &Value) -> impl Iterator<Item = &Value> {
    [
        preloaded
            .get("site")
            .and_then(Value::as_object)
            .and_then(|site| site.get("categories")),
        preloaded
            .get("site")
            .and_then(Value::as_object)
            .and_then(|site| site.get("category_list")),
        preloaded.get("categories"),
        preloaded.get("category_list"),
    ]
    .into_iter()
    .flatten()
}

fn has_site_metadata(preloaded: &Value) -> bool {
    category_candidates(preloaded).next().is_some()
        || site_candidates(preloaded, "top_tags").next().is_some()
        || site_candidates(preloaded, "can_tag_topics")
            .next()
            .is_some()
}

fn has_site_settings(preloaded: &Value) -> bool {
    preloaded
        .get("siteSettings")
        .is_some_and(|value| value.is_object())
}

fn site_candidates<'a>(preloaded: &'a Value, key: &'static str) -> impl Iterator<Item = &'a Value> {
    [
        preloaded
            .get("site")
            .and_then(Value::as_object)
            .and_then(|site| site.get(key)),
        preloaded.get(key),
    ]
    .into_iter()
    .flatten()
}

fn category_values_from_candidate(candidate: &Value) -> Option<&Vec<Value>> {
    if let Some(values) = candidate.as_array() {
        return Some(values);
    }

    candidate
        .as_object()
        .and_then(|value| value.get("categories"))
        .and_then(Value::as_array)
}

fn topic_category_from_value(value: &Value) -> Option<TopicCategory> {
    let object = value.as_object()?;
    Some(TopicCategory {
        id: positive_u64(object.get("id"))?,
        name: scalar_string_or_empty(object.get("name")),
        slug: scalar_string_or_empty(object.get("slug")),
        parent_category_id: positive_u64(object.get("parent_category_id")),
        color_hex: object
            .get("color")
            .and_then(optional_scalar_string)
            .filter(|value| !value.is_empty()),
        text_color_hex: object
            .get("text_color")
            .and_then(optional_scalar_string)
            .filter(|value| !value.is_empty()),
        topic_template: object
            .get("topic_template")
            .and_then(optional_scalar_string)
            .filter(|value| !value.is_empty()),
        minimum_required_tags: positive_u32(object.get("minimum_required_tags")).unwrap_or(0),
        required_tag_groups: required_tag_groups_from_value(object.get("required_tag_groups")),
        allowed_tags: string_array_from_value(object.get("allowed_tags")),
        permission: positive_u32(object.get("permission")),
    })
}

fn top_tags_from_preloaded(preloaded: &Value) -> Vec<String> {
    site_candidates(preloaded, "top_tags")
        .find_map(top_tag_names_from_candidate)
        .unwrap_or_default()
}

fn top_tag_names_from_candidate(candidate: &Value) -> Option<Vec<String>> {
    let values = candidate.as_array()?;
    Some(
        values
            .iter()
            .filter_map(top_tag_name_from_value)
            .collect::<Vec<_>>(),
    )
}

fn top_tag_name_from_value(value: &Value) -> Option<String> {
    match value {
        Value::String(value) => {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
        Value::Object(value) => value
            .get("name")
            .and_then(optional_scalar_string)
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        _ => None,
    }
}

fn can_tag_topics_from_preloaded(preloaded: &Value) -> Option<bool> {
    site_candidates(preloaded, "can_tag_topics").find_map(can_tag_topics_from_value)
}

fn can_tag_topics_from_value(value: &Value) -> Option<bool> {
    match value {
        Value::Bool(value) => Some(*value),
        Value::String(value) => match value.trim() {
            "true" => Some(true),
            "false" => Some(false),
            _ => None,
        },
        Value::Number(value) => value.as_u64().map(|value| value > 0),
        _ => None,
    }
}

fn enabled_reaction_ids_from_preloaded(preloaded: &Value) -> Vec<String> {
    let Some(raw) = preloaded
        .get("siteSettings")
        .and_then(Value::as_object)
        .and_then(|settings| settings.get("discourse_reactions_enabled_reactions"))
        .and_then(optional_scalar_string)
    else {
        return vec!["heart".to_string()];
    };

    let mut ids = Vec::new();
    for part in raw
        .split('|')
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        if ids.iter().any(|existing| existing == part) {
            continue;
        }
        ids.push(part.to_string());
    }

    if ids.is_empty() {
        vec!["heart".to_string()]
    } else {
        ids
    }
}

fn min_post_length_from_preloaded(preloaded: &Value) -> u32 {
    site_setting_u32(preloaded, "min_post_length").unwrap_or(1)
}

fn min_topic_title_length_from_preloaded(preloaded: &Value) -> u32 {
    site_setting_u32(preloaded, "min_topic_title_length").unwrap_or(15)
}

fn min_first_post_length_from_preloaded(preloaded: &Value) -> u32 {
    site_setting_u32(preloaded, "min_first_post_length")
        .or_else(|| site_setting_u32(preloaded, "min_post_length"))
        .unwrap_or(20)
}

fn default_composer_category_from_preloaded(preloaded: &Value) -> Option<u64> {
    preloaded
        .get("siteSettings")
        .and_then(Value::as_object)
        .and_then(|settings| settings.get("default_composer_category"))
        .and_then(|value| positive_u64(Some(value)))
}

fn site_setting_u32(preloaded: &Value, key: &str) -> Option<u32> {
    preloaded
        .get("siteSettings")
        .and_then(Value::as_object)
        .and_then(|settings| settings.get(key))
        .and_then(|value| positive_u32(Some(value)))
}

fn string_array_from_value(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(optional_scalar_string)
                .map(|item| item.trim().to_string())
                .filter(|item| !item.is_empty())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn required_tag_groups_from_value(value: Option<&Value>) -> Vec<RequiredTagGroup> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(required_tag_group_from_value)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn required_tag_group_from_value(value: &Value) -> Option<RequiredTagGroup> {
    let object = value.as_object()?;
    let name = object
        .get("name")
        .and_then(optional_scalar_string)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())?;
    Some(RequiredTagGroup {
        name,
        min_count: positive_u32(object.get("min_count")).unwrap_or(0),
    })
}

fn optional_scalar_string(value: &Value) -> Option<String> {
    match value {
        Value::String(value) => Some(value.clone()),
        Value::Bool(value) => Some(value.to_string()),
        Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn scalar_string_or_empty(value: Option<&Value>) -> String {
    value.and_then(optional_scalar_string).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use fire_models::BootstrapArtifacts;

    use super::{
        decode_html_entities, hydrate_preloaded_fields, parse_home_state, parse_site_metadata_json,
    };

    #[test]
    fn parse_home_state_skips_meta_tags_without_name() {
        let html = r#"
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="csrf-token" content="csrf-token">
    <meta name="shared_session_key" content="shared-session">
    <meta name="current-username" content="alice">
    <meta name="discourse-base-uri" content="/">
  </head>
</html>
"#;

        let parsed = parse_home_state("https://linux.do/", html);

        assert_eq!(
            parsed.cookies_patch.csrf_token.as_deref(),
            Some("csrf-token")
        );
        assert_eq!(
            parsed.bootstrap_patch.shared_session_key.as_deref(),
            Some("shared-session")
        );
        assert_eq!(
            parsed.bootstrap_patch.current_username.as_deref(),
            Some("alice")
        );
        assert_eq!(
            parsed.bootstrap_patch.discourse_base_uri.as_deref(),
            Some("/")
        );
    }

    #[test]
    fn parse_home_state_decodes_preloaded_json_once() {
        let html = r#"
<!doctype html>
<html>
  <body>
    <div data-preloaded="{&quot;siteSettings&quot;:{&quot;title&quot;:&quot;A &amp;amp; B&quot;,&quot;min_post_length&quot;:18,&quot;min_topic_title_length&quot;:15,&quot;min_first_post_length&quot;:24,&quot;default_composer_category&quot;:7,&quot;discourse_reactions_enabled_reactions&quot;:&quot;heart|clap&quot;},&quot;site&quot;:{&quot;categories&quot;:[{&quot;id&quot;:7,&quot;name&quot;:&quot;Rust&quot;,&quot;slug&quot;:&quot;rust&quot;,&quot;color&quot;:&quot;FFFFFF&quot;,&quot;text_color&quot;:&quot;000000&quot;,&quot;topic_template&quot;:&quot;## Template&quot;,&quot;minimum_required_tags&quot;:2,&quot;required_tag_groups&quot;:[{&quot;name&quot;:&quot;platform&quot;,&quot;min_count&quot;:1}],&quot;allowed_tags&quot;:[&quot;swift&quot;,&quot;rust&quot;],&quot;permission&quot;:1}],&quot;top_tags&quot;:[{&quot;name&quot;:&quot;swift&quot;},&quot;rust&quot;],&quot;can_tag_topics&quot;:true}}"></div>
  </body>
</html>
"#;

        let parsed = parse_home_state("https://linux.do/", html);

        assert_eq!(
            parsed.bootstrap_patch.preloaded_json.as_deref(),
            Some(
                r###"{"siteSettings":{"title":"A &amp; B","min_post_length":18,"min_topic_title_length":15,"min_first_post_length":24,"default_composer_category":7,"discourse_reactions_enabled_reactions":"heart|clap"},"site":{"categories":[{"id":7,"name":"Rust","slug":"rust","color":"FFFFFF","text_color":"000000","topic_template":"## Template","minimum_required_tags":2,"required_tag_groups":[{"name":"platform","min_count":1}],"allowed_tags":["swift","rust"],"permission":1}],"top_tags":[{"name":"swift"},"rust"],"can_tag_topics":true}}"###
            )
        );
        assert!(parsed.bootstrap_patch.has_site_settings);
        assert_eq!(parsed.bootstrap_patch.min_post_length, 18);
        assert_eq!(parsed.bootstrap_patch.min_topic_title_length, 15);
        assert_eq!(parsed.bootstrap_patch.min_first_post_length, 24);
        assert_eq!(parsed.bootstrap_patch.default_composer_category, Some(7));
        assert_eq!(
            parsed.bootstrap_patch.enabled_reaction_ids,
            vec!["heart", "clap"]
        );
        assert!(parsed.bootstrap_patch.has_site_metadata);
        assert_eq!(parsed.bootstrap_patch.top_tags, vec!["swift", "rust"]);
        assert!(parsed.bootstrap_patch.can_tag_topics);
        assert_eq!(parsed.bootstrap_patch.categories.len(), 1);
        assert_eq!(parsed.bootstrap_patch.categories[0].id, 7);
        assert_eq!(
            parsed.bootstrap_patch.categories[0]
                .topic_template
                .as_deref(),
            Some("## Template")
        );
        assert_eq!(
            parsed.bootstrap_patch.categories[0].minimum_required_tags,
            2
        );
        assert_eq!(
            parsed.bootstrap_patch.categories[0]
                .required_tag_groups
                .len(),
            1
        );
        assert_eq!(
            parsed.bootstrap_patch.categories[0].allowed_tags,
            vec!["swift", "rust"]
        );
        assert_eq!(parsed.bootstrap_patch.categories[0].permission, Some(1));
    }

    #[test]
    fn parse_home_state_marks_partial_preloaded_without_site_as_incomplete() {
        let html = r#"
<!doctype html>
<html>
  <body>
    <div data-preloaded="{&quot;currentUser&quot;:{&quot;username&quot;:&quot;alice&quot;}}"></div>
  </body>
</html>
"#;

        let parsed = parse_home_state("https://linux.do/", html);

        assert!(parsed.bootstrap_patch.has_preloaded_data);
        assert!(!parsed.bootstrap_patch.has_site_metadata);
        assert!(!parsed.bootstrap_patch.has_site_settings);
        assert_eq!(parsed.bootstrap_patch.categories, Vec::new());
        assert_eq!(parsed.bootstrap_patch.top_tags, Vec::<String>::new());
        assert!(!parsed.bootstrap_patch.can_tag_topics);
    }

    #[test]
    fn hydrate_preloaded_fields_unwraps_stringified_root_payloads() {
        let mut bootstrap = BootstrapArtifacts::default();
        hydrate_preloaded_fields(
            r###"{
  "currentUser":"{\"id\":341628,\"username\":\"alice\",\"notification_channel_position\":11}",
  "siteSettings":"{\"long_polling_base_url\":\"https://ping.linux.do\",\"min_post_length\":18,\"min_topic_title_length\":15,\"min_first_post_length\":24,\"default_composer_category\":7,\"discourse_reactions_enabled_reactions\":\"heart|clap\"}",
  "site":"{\"categories\":[{\"id\":7,\"name\":\"Rust\",\"slug\":\"rust\",\"color\":\"FFFFFF\",\"text_color\":\"000000\",\"topic_template\":\"## Template\",\"minimum_required_tags\":2,\"required_tag_groups\":[{\"name\":\"platform\",\"min_count\":1}],\"allowed_tags\":[\"swift\",\"rust\"],\"permission\":1}],\"top_tags\":[{\"name\":\"swift\"},\"rust\"],\"can_tag_topics\":true}",
  "topicTrackingStateMeta":"{\"/latest\":42,\"/new\":8}"
}"###,
            &mut bootstrap,
        );

        assert_eq!(bootstrap.current_username.as_deref(), Some("alice"));
        assert_eq!(bootstrap.current_user_id, Some(341628));
        assert_eq!(bootstrap.notification_channel_position, Some(11));
        assert_eq!(
            bootstrap.long_polling_base_url.as_deref(),
            Some("https://ping.linux.do")
        );
        assert_eq!(
            bootstrap.topic_tracking_state_meta.as_deref(),
            Some(r#"{"/latest":42,"/new":8}"#)
        );
        assert!(bootstrap.has_site_metadata);
        assert_eq!(bootstrap.top_tags, vec!["swift", "rust"]);
        assert!(bootstrap.can_tag_topics);
        assert_eq!(bootstrap.categories.len(), 1);
        assert_eq!(bootstrap.categories[0].id, 7);
        assert!(bootstrap.has_site_settings);
        assert_eq!(bootstrap.enabled_reaction_ids, vec!["heart", "clap"]);
        assert_eq!(bootstrap.min_post_length, 18);
        assert_eq!(bootstrap.min_topic_title_length, 15);
        assert_eq!(bootstrap.min_first_post_length, 24);
        assert_eq!(bootstrap.default_composer_category, Some(7));
        assert_eq!(bootstrap.categories[0].minimum_required_tags, 2);
        assert_eq!(bootstrap.categories[0].permission, Some(1));
    }

    #[test]
    fn parse_site_metadata_json_reads_root_site_json_shape() {
        let parsed = parse_site_metadata_json(
            "https://linux.do/",
            r#"{
                "categories": [
                    {"id": 7, "name": "Rust", "slug": "rust", "color": "FFFFFF", "text_color": "000000"}
                ],
                "top_tags": [{"name": "swift"}, "rust"],
                "can_tag_topics": true
            }"#,
        );

        assert!(parsed.has_site_metadata);
        assert_eq!(parsed.categories.len(), 1);
        assert_eq!(parsed.top_tags, vec!["swift", "rust"]);
        assert!(parsed.can_tag_topics);
        assert_eq!(parsed.base_url, "https://linux.do/");
    }

    #[test]
    fn decode_html_entities_supports_named_and_numeric_forms() {
        assert_eq!(
            decode_html_entities("&quot;&amp;&lt;&gt;&#39;&apos;&#x41;&#65;"),
            "\"&<>''AA"
        );
    }
}
