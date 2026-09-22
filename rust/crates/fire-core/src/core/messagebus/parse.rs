use std::sync::{Arc, Mutex};

use fire_models::{MessageBusEvent, MessageBusEventKind};
use serde_json::Value;
use tracing::warn;

use super::channels::*;
use super::*;
use crate::json_helpers::{boolean, integer_i64, integer_u32, positive_u64, scalar_string};

pub(super) fn parse_message_bus_messages(
    chunk: &str,
    client_id: &str,
    chunk_kind: &str,
) -> Option<Vec<RawMessageBusMessage>> {
    let value: Value = match serde_json::from_str(chunk) {
        Ok(value) => value,
        Err(error) => {
            warn!(
                client_id = %client_id,
                error = %error,
                chunk = %chunk,
                chunk_kind,
                "failed to parse message bus chunk"
            );
            return None;
        }
    };

    let Some(messages) = value.as_array() else {
        warn!(
            client_id = %client_id,
            chunk = %chunk,
            chunk_kind,
            "message bus chunk root was not an array"
        );
        return None;
    };

    let mut parsed = Vec::with_capacity(messages.len());
    for (index, value) in messages.iter().enumerate() {
        let Some(message) = raw_message_bus_message_from_value(value) else {
            warn!(
                client_id = %client_id,
                chunk_kind,
                index,
                message = %value,
                "skipping malformed message bus item"
            );
            continue;
        };
        parsed.push(message);
    }
    Some(parsed)
}

pub(super) fn raw_message_bus_message_from_value(value: &Value) -> Option<RawMessageBusMessage> {
    let object = value.as_object()?;
    let channel = scalar_string(object.get("channel"))?.trim().to_string();
    if channel.is_empty() {
        return None;
    }

    Some(RawMessageBusMessage {
        channel,
        message_id: integer_i64(object.get("message_id"))?,
        data: object.get("data").cloned().unwrap_or(Value::Null),
    })
}

pub(super) fn apply_status_message(runtime: &Arc<Mutex<FireMessageBusRuntime>>, data: &Value) {
    let Some(object) = data.as_object() else {
        return;
    };
    let mut runtime = runtime.lock().expect("message bus runtime lock poisoned");
    for (channel, value) in object {
        let Some(last_message_id) = integer_i64(Some(value)) else {
            continue;
        };
        if let Some(subscription) = runtime.subscriptions.get_mut(channel) {
            subscription.last_message_id = subscription.last_message_id.max(last_message_id);
        }
    }
}

pub(super) fn update_channel_checkpoint(
    runtime: &Arc<Mutex<FireMessageBusRuntime>>,
    channel: &str,
    message_id: i64,
) {
    let mut runtime = runtime.lock().expect("message bus runtime lock poisoned");
    if let Some(subscription) = runtime.subscriptions.get_mut(channel) {
        subscription.last_message_id = subscription.last_message_id.max(message_id);
    }
}

pub(super) fn message_bus_event_from_raw(message: &RawMessageBusMessage) -> MessageBusEvent {
    let payload_json = serde_json::to_string(&message.data)
        .ok()
        .filter(|value| value != "null");

    if let Some(topic_list_kind) = topic_list_kind_for_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::TopicList,
            topic_list_kind: Some(topic_list_kind),
            topic_id: message
                .data
                .get("topic_id")
                .and_then(|value| positive_u64(Some(value)))
                .or_else(|| {
                    message
                        .data
                        .get("payload")
                        .and_then(|value| value.get("topic_id"))
                        .and_then(|value| positive_u64(Some(value)))
                }),
            message_type: message
                .data
                .get("message_type")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(topic_id) = topic_reaction_topic_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::TopicReaction,
            topic_id: Some(topic_id),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(topic_id) = topic_polls_topic_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::TopicDetail,
            topic_id: Some(topic_id),
            detail_event_type: Some("polls".to_string()),
            refresh_stream: true,
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(topic_id) = topic_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::TopicDetail,
            topic_id: Some(topic_id),
            detail_event_type: message
                .data
                .get("type")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            reload_topic: boolean(message.data.get("reload_topic")),
            refresh_stream: boolean(message.data.get("refresh_stream")),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(topic_id) = presence_topic_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::Presence,
            topic_id: Some(topic_id),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(notification_user_id) = notification_user_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::Notification,
            notification_user_id: Some(notification_user_id),
            all_unread_notifications_count: message
                .data
                .get("all_unread_notifications_count")
                .and_then(|value| integer_u32(Some(value))),
            unread_notifications: message
                .data
                .get("unread_notifications")
                .and_then(|value| integer_u32(Some(value))),
            unread_high_priority_notifications: message
                .data
                .get("unread_high_priority_notifications")
                .and_then(|value| integer_u32(Some(value))),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(notification_user_id) = notification_alert_user_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::NotificationAlert,
            notification_user_id: Some(notification_user_id),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if message.channel.starts_with("/chat/") || message.channel == "/chat" {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::Chat,
            // Reuse topic_id slot for chat channel id when the path encodes one
            // (`/chat/{id}`, `/chat/{id}/new-messages`, `/chat/{id}/thread/{tid}`).
            topic_id: chat_channel_id_from_channel(&message.channel),
            detail_event_type: message
                .data
                .get("type")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            message_type: message
                .data
                .get("type")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    MessageBusEvent {
        channel: message.channel.clone(),
        message_id: message.message_id,
        kind: MessageBusEventKind::Unknown,
        payload_json,
        ..MessageBusEvent::default()
    }
}
