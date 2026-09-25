use fire_models::BootstrapArtifacts;
use serde_json::Value;
use tracing::warn;

use super::{
    site_metadata::hydrate_site_metadata_fields, site_settings::hydrate_site_settings_fields,
};
use crate::json_helpers::{integer_i64, positive_u64};

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
