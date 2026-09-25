use std::io;

use fire_models::{PostActionType, PostReactionUpdate, TopicPost, TopicPostBoost};
use serde_json::Value;
use url::form_urlencoded::byte_serialize;

use crate::{
    error::FireCoreError,
    json_helpers::{
        integer_i32, invalid_json, object_field, optional_boolean, parse_array_items_lossy,
        positive_u32, scalar_string,
    },
    topic_payloads::{
        parse_post_reaction_update_value, parse_topic_post_boost_value, parse_topic_post_value,
    },
};

pub(super) fn parse_bookmark_id(
    operation: &'static str,
    value: Value,
) -> Result<u64, FireCoreError> {
    let Value::Object(object) = value else {
        return Err(FireCoreError::ResponseDeserialize {
            operation,
            source: serde_json::Error::io(io::Error::new(
                io::ErrorKind::InvalidData,
                "bookmark response root was not an object",
            )),
        });
    };
    let bookmark_id = object.get("id").and_then(|value| match value {
        Value::Number(value) => value.as_u64(),
        Value::String(value) => value.parse::<u64>().ok(),
        Value::Bool(value) => Some(u64::from(*value)),
        Value::Array(_) | Value::Object(_) | Value::Null => None,
    });
    bookmark_id.ok_or_else(|| FireCoreError::ResponseDeserialize {
        operation,
        source: serde_json::Error::io(io::Error::new(
            io::ErrorKind::InvalidData,
            "bookmark response did not contain a valid id",
        )),
    })
}

pub(super) fn parse_post_action_types_response(
    value: Value,
) -> Result<Vec<PostActionType>, serde_json::Error> {
    post_action_types_from_value(&value)
        .ok_or_else(|| invalid_json("post action types response did not contain a valid list"))
}

pub(super) fn post_action_types_from_value(value: &Value) -> Option<Vec<PostActionType>> {
    let items = if let Some(items) = value.as_array() {
        items
    } else {
        object_field(value, "post_action_types")
            .or_else(|| {
                object_field(value, "site").and_then(|site| object_field(site, "post_action_types"))
            })?
            .as_array()?
    };
    Some(parse_array_items_lossy(
        items,
        "post action type",
        parse_post_action_type,
    ))
}

fn parse_post_action_type(value: &Value) -> Result<PostActionType, serde_json::Error> {
    let Some(object) = value.as_object() else {
        return Err(invalid_json("post action type item was not an object"));
    };
    let id = positive_u32(object.get("id"))
        .ok_or_else(|| invalid_json("post action type item did not contain a valid id"))?;
    let name_key = scalar_string(object.get("name_key"))
        .or_else(|| scalar_string(object.get("nameKey")))
        .unwrap_or_default();
    let name = scalar_string(object.get("name")).unwrap_or_else(|| name_key.clone());
    let description = scalar_string(object.get("description")).unwrap_or_default();
    let short_description = scalar_string(object.get("short_description"))
        .or_else(|| scalar_string(object.get("shortDescription")));
    let is_flag = optional_boolean(object.get("is_flag"))
        .or_else(|| optional_boolean(object.get("isFlag")))
        .unwrap_or(false);
    let require_message = optional_boolean(object.get("require_message"))
        .or_else(|| optional_boolean(object.get("requireMessage")))
        .unwrap_or(false);
    let enabled = optional_boolean(object.get("enabled")).unwrap_or(true);
    let position = integer_i32(object.get("position")).unwrap_or_default();
    let applies_to =
        post_action_applies_to(object.get("applies_to").or_else(|| object.get("appliesTo")));

    Ok(PostActionType {
        id,
        name_key,
        name,
        description,
        short_description,
        is_flag,
        require_message,
        enabled,
        position,
        applies_to,
    })
}

fn post_action_applies_to(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|item| scalar_string(Some(item)))
            .collect(),
        Some(value) => scalar_string(Some(value)).into_iter().collect(),
        None => Vec::new(),
    }
}

pub(super) fn encode_path_segment(value: &str) -> String {
    byte_serialize(value.as_bytes()).collect()
}

pub(super) fn parse_create_boost_response(value: Value) -> Result<TopicPostBoost, FireCoreError> {
    parse_topic_post_boost_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
        operation: "create boost",
        source,
    })
}

pub(super) fn parse_create_reply_response(
    value: Value,
    base_url: &str,
) -> Result<TopicPost, FireCoreError> {
    let Value::Object(mut object) = value else {
        return Err(invalid_response(
            "create reply",
            "response root was not a JSON object",
        ));
    };

    if object
        .get("action")
        .and_then(Value::as_str)
        .is_some_and(|action| action == "enqueued")
    {
        return Err(FireCoreError::PostEnqueued {
            pending_count: pending_count_from(object.get("pending_count")),
        });
    }

    if let Some(post_value) = object.remove("post") {
        return parse_topic_post_value(post_value, base_url).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "create reply",
                source,
            }
        });
    }

    if object.contains_key("id")
        || object.contains_key("post_number")
        || object.contains_key("cooked")
    {
        return parse_topic_post_value(Value::Object(object), base_url).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "create reply",
                source,
            }
        });
    }

    Err(invalid_response(
        "create reply",
        "response object did not contain a post payload",
    ))
}

pub(super) fn parse_toggle_reaction_response(
    value: Value,
) -> Result<PostReactionUpdate, FireCoreError> {
    let Value::Object(object) = &value else {
        return Err(invalid_response(
            "toggle post reaction",
            "response root was not a JSON object",
        ));
    };

    if !object.contains_key("reactions") && !object.contains_key("current_user_reaction") {
        return Err(invalid_response(
            "toggle post reaction",
            "response object did not contain reaction fields",
        ));
    }

    parse_post_reaction_update_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
        operation: "toggle post reaction",
        source,
    })
}

pub(super) fn parse_optional_post_reaction_update(
    operation: &'static str,
    value: Value,
) -> Result<Option<PostReactionUpdate>, FireCoreError> {
    let Value::Object(object) = &value else {
        return Ok(None);
    };

    if !object.contains_key("reactions") && !object.contains_key("current_user_reaction") {
        return Ok(None);
    }

    parse_post_reaction_update_value(value)
        .map(Some)
        .map_err(|source| FireCoreError::ResponseDeserialize { operation, source })
}

fn pending_count_from(value: Option<&Value>) -> u32 {
    match value {
        Some(Value::Number(value)) => value
            .as_u64()
            .and_then(|value| u32::try_from(value).ok())
            .unwrap_or_default(),
        Some(Value::String(value)) => value.parse::<u32>().unwrap_or_default(),
        Some(Value::Bool(value)) => u32::from(*value),
        _ => 0,
    }
}

fn invalid_response(operation: &'static str, details: &'static str) -> FireCoreError {
    FireCoreError::ResponseDeserialize {
        operation,
        source: serde_json::Error::io(io::Error::new(io::ErrorKind::InvalidData, details)),
    }
}
