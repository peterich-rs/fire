use std::io;

use fire_models::{NotificationData, NotificationItem, NotificationListResponse};
use serde_json::{Map, Value};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use url::Url;

use crate::json_helpers::{boolean, integer_i32, integer_u32, integer_u64};

pub(crate) fn parse_notification_list_response_value(
    value: Value,
) -> Result<NotificationListResponse, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json(
            "notification list response root was not an object",
        ));
    };

    let notifications = object
        .get("notifications")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .cloned()
                .map(parse_notification_item_value)
                .collect::<Result<Vec<_>, _>>()
        })
        .transpose()?
        .unwrap_or_default();

    let load_more_notifications = scalar_string(object.get("load_more_notifications"));

    Ok(NotificationListResponse {
        notifications,
        total_rows_notifications: integer_u32(object.get("total_rows_notifications")).unwrap_or(0),
        seen_notification_id: integer_u64(object.get("seen_notification_id")),
        next_offset: next_offset_from_load_more(load_more_notifications.as_deref()),
        load_more_notifications,
    })
}

pub(crate) fn parse_notification_item_value(
    value: Value,
) -> Result<NotificationItem, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("notification item was not an object"));
    };

    let id = integer_u64(object.get("id"))
        .ok_or_else(|| invalid_json("notification item did not contain an id"))?;

    let data = object
        .get("data")
        .and_then(Value::as_object)
        .map(notification_data_from_object)
        .unwrap_or_default();

    Ok(NotificationItem {
        id,
        user_id: integer_u64(object.get("user_id")),
        notification_type: integer_i32(object.get("notification_type")).unwrap_or_default(),
        read: boolean(object.get("read")),
        high_priority: boolean(object.get("high_priority")),
        created_at: scalar_string(object.get("created_at")),
        created_timestamp_unix_ms: timestamp_unix_ms(object.get("created_at")),
        post_number: integer_u32(object.get("post_number")),
        topic_id: integer_u64(object.get("topic_id")),
        slug: scalar_string(object.get("slug")),
        fancy_title: scalar_string(object.get("fancy_title")),
        acting_user_avatar_template: scalar_string(object.get("acting_user_avatar_template")),
        data,
    })
}

fn notification_data_from_object(object: &Map<String, Value>) -> NotificationData {
    NotificationData {
        display_username: scalar_string(object.get("display_username")),
        original_post_id: scalar_string(object.get("original_post_id")),
        original_post_type: integer_i32(object.get("original_post_type")),
        original_username: scalar_string(object.get("original_username")),
        revision_number: integer_u32(object.get("revision_number")),
        topic_title: scalar_string(object.get("topic_title")),
        badge_name: scalar_string(object.get("badge_name")),
        badge_id: integer_u64(object.get("badge_id")),
        badge_slug: scalar_string(object.get("badge_slug")),
        group_name: scalar_string(object.get("group_name")),
        inbox_count: scalar_string(object.get("inbox_count")),
        count: integer_u32(object.get("count")),
        username: scalar_string(object.get("username")),
        username2: scalar_string(object.get("username2")),
        avatar_template: scalar_string(object.get("acting_user_avatar_template"))
            .or_else(|| scalar_string(object.get("avatar_template"))),
        excerpt: scalar_string(object.get("excerpt")),
        payload_json: serde_json::to_string(object)
            .ok()
            .filter(|value| value != "{}"),
    }
}

pub(crate) fn scalar_string(value: Option<&Value>) -> Option<String> {
    match value? {
        Value::String(value) => normalized_scalar(value),
        Value::Number(value) => normalized_scalar(&value.to_string()),
        Value::Bool(value) => Some(value.to_string()),
        _ => None,
    }
}

pub(crate) fn timestamp_unix_ms(value: Option<&Value>) -> Option<u64> {
    let raw_value = scalar_string(value)?;
    let timestamp_ms = OffsetDateTime::parse(&raw_value, &Rfc3339)
        .ok()?
        .unix_timestamp_nanos()
        / 1_000_000;
    u64::try_from(timestamp_ms).ok()
}

pub(crate) fn next_offset_from_load_more(value: Option<&str>) -> Option<u32> {
    let value = value?.trim();
    if value.is_empty() {
        return None;
    }

    let parsed = if value.starts_with("http://") || value.starts_with("https://") {
        Url::parse(value).ok()?
    } else {
        Url::parse(&format!("https://fire.invalid{value}")).ok()?
    };

    parsed
        .query_pairs()
        .find_map(|(key, value)| (key == "offset").then_some(value))
        .and_then(|value| value.parse::<u32>().ok())
}

fn normalized_scalar(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn invalid_json(details: &'static str) -> serde_json::Error {
    serde_json::Error::io(io::Error::new(io::ErrorKind::InvalidData, details))
}
