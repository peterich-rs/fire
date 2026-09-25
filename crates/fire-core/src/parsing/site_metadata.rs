use fire_models::{BootstrapArtifacts, RequiredTagGroup, TopicCategory};
use serde_json::Value;
use tracing::warn;

use crate::json_helpers::{integer_i32, positive_u32, positive_u64};

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
        notification_level: integer_i32(object.get("notification_level")),
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

pub(super) fn optional_scalar_string(value: &Value) -> Option<String> {
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
