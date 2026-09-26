use fire_models::BootstrapArtifacts;
use serde_json::Value;

use super::site_metadata::optional_scalar_string;
use crate::json_helpers::{optional_boolean, positive_u32, positive_u64};

pub(crate) fn hydrate_site_settings_fields(source: &Value, bootstrap: &mut BootstrapArtifacts) {
    bootstrap.has_site_settings = has_site_settings(source);
    bootstrap.enabled_reaction_ids = enabled_reaction_ids_from_preloaded(source);
    bootstrap.min_post_length = min_post_length_from_preloaded(source);
    bootstrap.min_topic_title_length = min_topic_title_length_from_preloaded(source);
    bootstrap.min_first_post_length = min_first_post_length_from_preloaded(source);
    bootstrap.min_personal_message_title_length =
        min_personal_message_title_length_from_preloaded(source);
    bootstrap.min_personal_message_post_length =
        min_personal_message_post_length_from_preloaded(source);
    bootstrap.default_composer_category = default_composer_category_from_preloaded(source);
    bootstrap.polling_interval_ms = polling_interval_ms_from_preloaded(source);
    bootstrap.background_polling_interval_ms =
        background_polling_interval_ms_from_preloaded(source);
    bootstrap.enable_chunked_encoding = enable_chunked_encoding_from_preloaded(source);
}
fn has_site_settings(preloaded: &Value) -> bool {
    preloaded
        .get("siteSettings")
        .is_some_and(|value| value.is_object())
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

fn min_personal_message_title_length_from_preloaded(preloaded: &Value) -> u32 {
    site_setting_u32(preloaded, "min_personal_message_title_length").unwrap_or(2)
}

fn min_personal_message_post_length_from_preloaded(preloaded: &Value) -> u32 {
    site_setting_u32(preloaded, "min_personal_message_post_length").unwrap_or(10)
}

fn polling_interval_ms_from_preloaded(preloaded: &Value) -> u32 {
    site_setting_u32(preloaded, "polling_interval")
        .unwrap_or(3000)
        .max(1)
}

fn background_polling_interval_ms_from_preloaded(preloaded: &Value) -> u32 {
    site_setting_u32(preloaded, "background_polling_interval")
        .unwrap_or(60_000)
        .max(1)
}

fn enable_chunked_encoding_from_preloaded(preloaded: &Value) -> bool {
    preloaded
        .get("siteSettings")
        .and_then(Value::as_object)
        .and_then(|settings| settings.get("enable_chunked_encoding"))
        .and_then(|value| optional_boolean(Some(value)))
        .unwrap_or(true)
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
