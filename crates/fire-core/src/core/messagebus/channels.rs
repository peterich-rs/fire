use std::sync::{Arc, Mutex};

use fire_models::{MessageBusClientMode, NotificationAlert, TopicListKind};
use serde_json::Value;

use super::runtime::client_id_for_mode;
use super::*;
use crate::json_helpers::{integer_u32, positive_u64};

pub(super) fn chat_channel_id_from_channel(channel: &str) -> Option<u64> {
    // /chat/{id}
    // /chat/{id}/new-messages
    // /chat/{id}/thread/{tid}
    let rest = channel.strip_prefix("/chat/")?;
    let first = rest.split('/').next()?;
    first.parse::<u64>().ok().filter(|id| *id > 0)
}

pub(super) fn logout_user_id_from_channel(channel: &str) -> Option<u64> {
    let rest = channel.strip_prefix("/logout/")?;
    if rest.contains('/') {
        return None;
    }
    rest.parse::<u64>().ok().filter(|id| *id > 0)
}

pub(super) fn notification_alert_from_raw(message: &RawMessageBusMessage) -> NotificationAlert {
    NotificationAlert {
        message_id: message.message_id,
        notification_type: message
            .data
            .get("notification_type")
            .and_then(|value| integer_u32(Some(value))),
        topic_id: message
            .data
            .get("topic_id")
            .and_then(|value| positive_u64(Some(value))),
        post_number: message
            .data
            .get("post_number")
            .and_then(|value| integer_u32(Some(value))),
        topic_title: message
            .data
            .get("topic_title")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        excerpt: message
            .data
            .get("excerpt")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        username: message
            .data
            .get("username")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        post_url: message
            .data
            .get("post_url")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        payload_json: serde_json::to_string(&message.data)
            .ok()
            .filter(|value| value != "null"),
    }
}

pub(super) fn topic_list_kind_for_channel(channel: &str) -> Option<TopicListKind> {
    match channel {
        "/latest" => Some(TopicListKind::Latest),
        "/new" => Some(TopicListKind::New),
        _ => None,
    }
}

pub(super) fn topic_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("topic"), Some(topic_id), None, None) => topic_id.parse::<u64>().ok(),
        _ => None,
    }
}

pub(super) fn topic_reaction_topic_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("topic"), Some(topic_id), Some("reactions"), None) => topic_id.parse::<u64>().ok(),
        _ => None,
    }
}

pub(super) fn topic_polls_topic_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next()) {
        (Some("polls"), Some(topic_id), None) => topic_id.parse::<u64>().ok(),
        _ => None,
    }
}

pub(crate) fn presence_topic_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (Some("presence"), Some("discourse-presence"), Some("reply"), Some(topic_id), None) => {
            topic_id.parse::<u64>().ok()
        }
        _ => None,
    }
}

pub(crate) fn message_bus_presence_channel_for_topic(topic_id: u64) -> String {
    format!("/presence/discourse-presence/reply/{topic_id}")
}

pub(super) fn notification_user_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next()) {
        (Some("notification"), Some(user_id), None) => user_id.parse::<u64>().ok(),
        _ => None,
    }
}

pub(super) fn notification_alert_user_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next()) {
        (Some("notification-alert"), Some(user_id), None) => user_id.parse::<u64>().ok(),
        _ => None,
    }
}

pub(crate) fn active_message_bus_client_id(
    runtime: &Arc<Mutex<FireMessageBusRuntime>>,
) -> Option<String> {
    runtime
        .lock()
        .expect("message bus runtime lock poisoned")
        .active_client_id
        .clone()
}

pub(crate) fn upload_client_id(runtime: &Arc<Mutex<FireMessageBusRuntime>>) -> String {
    let mut runtime = runtime.lock().expect("message bus runtime lock poisoned");
    runtime
        .active_client_id
        .clone()
        .unwrap_or_else(|| client_id_for_mode(&mut runtime, MessageBusClientMode::Foreground))
}
