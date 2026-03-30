use std::collections::BTreeMap;

use fire_models::{
    MessageBusContext, MessageBusMessage, MessageBusPollResult, MessageBusSubscription,
    SessionSnapshot,
};
use http::{Method, Request};
use openwire::RequestBody;
use serde_json::Value;
use tracing::debug;
use url::{form_urlencoded, Url};

use super::{network::expect_success, FireCore};
use crate::error::FireCoreError;

impl FireCore {
    pub fn default_message_bus_client_id(&self) -> String {
        default_message_bus_client_id(
            &self.base_url,
            self.snapshot().bootstrap.current_username.as_deref(),
        )
    }

    pub fn message_bus_context(
        &self,
        client_id: Option<String>,
    ) -> Result<MessageBusContext, FireCoreError> {
        let snapshot = self.snapshot();
        if !snapshot.cookies.can_authenticate_requests() {
            return Err(FireCoreError::MissingLoginSession);
        }

        let shared_session_key = snapshot
            .bootstrap
            .shared_session_key
            .clone()
            .filter(|value| !value.is_empty())
            .ok_or(FireCoreError::MissingSharedSessionKey)?;

        let poll_base_url = resolve_poll_base_url(
            &self.base_url,
            snapshot.bootstrap.long_polling_base_url.as_deref(),
        )?;
        let client_id = normalize_client_id(client_id.as_deref()).unwrap_or_else(|| {
            default_message_bus_client_id(
                &self.base_url,
                snapshot.bootstrap.current_username.as_deref(),
            )
        });
        let poll_url = build_poll_url(&poll_base_url, &client_id)?;

        Ok(MessageBusContext {
            client_id,
            poll_base_url: poll_base_url.to_string(),
            poll_url,
            requires_shared_session_key_header: !same_origin(&self.base_url, &poll_base_url),
            shared_session_key,
            current_username: snapshot.bootstrap.current_username.clone(),
            current_user_id: snapshot.bootstrap.current_user_id,
            notification_channel_position: snapshot.bootstrap.notification_channel_position,
            topic_tracking_state_meta: snapshot.bootstrap.topic_tracking_state_meta.clone(),
            subscriptions: snapshot.bootstrap.message_bus_subscriptions(),
        })
    }

    pub fn apply_message_bus_status_updates(
        &self,
        updates: Vec<MessageBusSubscription>,
    ) -> SessionSnapshot {
        self.update_session(|session| {
            let notification_channel = session
                .bootstrap
                .current_user_id
                .map(|user_id| format!("/notification/{user_id}"));

            if let Some(notification_channel) = notification_channel.as_deref() {
                for update in &updates {
                    if update.channel == notification_channel {
                        session.bootstrap.notification_channel_position =
                            Some(update.last_message_id);
                    }
                }
            }

            let Some(raw_meta) = session.bootstrap.topic_tracking_state_meta.clone() else {
                return;
            };

            let Ok(mut parsed_meta) = serde_json::from_str::<Value>(&raw_meta) else {
                return;
            };

            let mut changed = false;
            if let Value::Object(map) = &mut parsed_meta {
                for update in &updates {
                    if map.contains_key(&update.channel) {
                        map.insert(update.channel.clone(), Value::from(update.last_message_id));
                        changed = true;
                    }
                }
            }

            if changed {
                session.bootstrap.topic_tracking_state_meta =
                    serde_json::to_string(&parsed_meta).ok();
            }

            debug!(
                update_count = updates.len(),
                "applied message bus status cursor updates"
            );
        })
    }

    pub async fn poll_message_bus(
        &self,
        client_id: Option<String>,
        extra_subscriptions: Vec<MessageBusSubscription>,
    ) -> Result<MessageBusPollResult, FireCoreError> {
        let context = self.message_bus_context(client_id)?;
        let subscriptions = merge_subscriptions(context.subscriptions.clone(), extra_subscriptions);
        let request = build_message_bus_poll_request(&context, &subscriptions)?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let response = expect_success("poll message bus", response).await?;
        let body = response
            .into_body()
            .text()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let result = parse_message_bus_poll_response(&body)?;
        if !result.status_updates.is_empty() {
            let _ = self.apply_message_bus_status_updates(result.status_updates.clone());
        }
        debug!(
            message_count = result.messages.len(),
            status_update_count = result.status_updates.len(),
            "polled message bus once"
        );
        Ok(result)
    }
}

fn resolve_poll_base_url(
    base_url: &Url,
    long_polling_base_url: Option<&str>,
) -> Result<Url, FireCoreError> {
    let Some(long_polling_base_url) = long_polling_base_url.filter(|value| !value.is_empty())
    else {
        return Ok(base_url.clone());
    };

    Url::parse(long_polling_base_url)
        .or_else(|_| base_url.join(long_polling_base_url))
        .map_err(Into::into)
}

fn build_poll_url(poll_base_url: &Url, client_id: &str) -> Result<String, FireCoreError> {
    let poll_path = format!("message-bus/{client_id}/poll");
    let mut poll_url = poll_base_url.join(&poll_path)?;
    poll_url.set_query(None);
    poll_url.set_fragment(None);
    Ok(poll_url.to_string())
}

fn default_message_bus_client_id(base_url: &Url, username: Option<&str>) -> String {
    let host = sanitize_client_id_component(base_url.host_str().unwrap_or("linuxdo"));
    let username = sanitize_client_id_component(username.unwrap_or("foreground"));
    format!("fire_{host}_{username}")
}

fn normalize_client_id(client_id: Option<&str>) -> Option<String> {
    let client_id = client_id?.trim();
    if client_id.is_empty() {
        return None;
    }

    Some(sanitize_client_id_component(client_id))
}

fn sanitize_client_id_component(raw: &str) -> String {
    let mut sanitized = String::with_capacity(raw.len());
    let mut last_was_separator = false;

    for ch in raw.chars() {
        let mapped = if ch.is_ascii_alphanumeric() {
            Some(ch.to_ascii_lowercase())
        } else if matches!(ch, '-' | '_' | '.') {
            Some(ch)
        } else {
            None
        };

        match mapped {
            Some(ch) => {
                sanitized.push(ch);
                last_was_separator = false;
            }
            None if !last_was_separator => {
                sanitized.push('_');
                last_was_separator = true;
            }
            None => {}
        }
    }

    let sanitized = sanitized.trim_matches('_');
    if sanitized.is_empty() {
        "fire_client".to_string()
    } else {
        sanitized.to_string()
    }
}

fn same_origin(left: &Url, right: &Url) -> bool {
    left.scheme() == right.scheme()
        && left.host_str() == right.host_str()
        && left.port_or_known_default() == right.port_or_known_default()
}

fn merge_subscriptions(
    base: Vec<MessageBusSubscription>,
    extra: Vec<MessageBusSubscription>,
) -> Vec<MessageBusSubscription> {
    let mut merged = BTreeMap::new();
    for subscription in base.into_iter().chain(extra) {
        merged.insert(subscription.channel, subscription.last_message_id);
    }

    merged
        .into_iter()
        .map(|(channel, last_message_id)| MessageBusSubscription {
            channel,
            last_message_id,
        })
        .collect()
}

fn build_message_bus_poll_request(
    context: &MessageBusContext,
    subscriptions: &[MessageBusSubscription],
) -> Result<Request<RequestBody>, FireCoreError> {
    if subscriptions.is_empty() {
        return Err(FireCoreError::MissingMessageBusSubscriptions);
    }

    let body = encode_message_bus_poll_body(subscriptions);

    let mut builder = Request::builder()
        .method(Method::POST)
        .uri(&context.poll_url)
        .header("Accept", "application/json")
        .header("Content-Type", "application/x-www-form-urlencoded")
        .header("User-Agent", "Fire/0.1")
        .header("X-SILENCE-LOGGER", "true")
        .header("Discourse-Background", "true")
        .header("Content-Length", body.len().to_string());

    if context.requires_shared_session_key_header {
        builder = builder.header("X-Shared-Session-Key", &context.shared_session_key);
    }

    builder
        .body(RequestBody::from(body))
        .map_err(FireCoreError::RequestBuild)
}

fn encode_message_bus_poll_body(subscriptions: &[MessageBusSubscription]) -> String {
    let mut serializer = form_urlencoded::Serializer::new(String::new());
    for subscription in subscriptions {
        serializer.append_pair(
            &subscription.channel,
            &subscription.last_message_id.to_string(),
        );
    }
    serializer.finish()
}

fn parse_message_bus_poll_response(body: &str) -> Result<MessageBusPollResult, FireCoreError> {
    let segments = body
        .split('|')
        .map(str::trim)
        .filter(|segment| !segment.is_empty())
        .collect::<Vec<_>>();

    if segments.is_empty() {
        return Ok(MessageBusPollResult::default());
    }

    let mut result = MessageBusPollResult::default();
    for segment in segments {
        let value = serde_json::from_str::<Value>(segment).map_err(|error| {
            FireCoreError::InvalidMessageBusResponse {
                details: format!("failed to parse segment as json: {error}"),
            }
        })?;

        let items = match value {
            Value::Array(items) => items,
            other => vec![other],
        };

        for item in items {
            let message = parse_message_bus_message(&item)?;
            if message.channel == "/__status" {
                if let Some(data_json) = message.data_json.as_deref() {
                    result
                        .status_updates
                        .extend(parse_status_updates(data_json)?);
                }
            }
            result.messages.push(message);
        }
    }

    Ok(result)
}

fn parse_message_bus_message(value: &Value) -> Result<MessageBusMessage, FireCoreError> {
    let channel = value
        .get("channel")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| FireCoreError::InvalidMessageBusResponse {
            details: "message bus item is missing channel".to_string(),
        })?;
    let message_id = value.get("message_id").and_then(as_i64).ok_or_else(|| {
        FireCoreError::InvalidMessageBusResponse {
            details: format!("message bus item for channel {channel} is missing message_id"),
        }
    })?;
    let data_json = value.get("data").and_then(|data| {
        if data.is_null() {
            None
        } else {
            serde_json::to_string(data).ok()
        }
    });

    Ok(MessageBusMessage {
        channel: channel.to_string(),
        message_id,
        data_json,
    })
}

fn parse_status_updates(data_json: &str) -> Result<Vec<MessageBusSubscription>, FireCoreError> {
    let value = serde_json::from_str::<Value>(data_json).map_err(|error| {
        FireCoreError::InvalidMessageBusResponse {
            details: format!("failed to parse __status payload as json: {error}"),
        }
    })?;

    let mut updates = BTreeMap::new();
    collect_status_updates(&value, &mut updates);
    Ok(updates
        .into_iter()
        .map(|(channel, last_message_id)| MessageBusSubscription {
            channel,
            last_message_id,
        })
        .collect())
}

fn collect_status_updates(value: &Value, updates: &mut BTreeMap<String, i64>) {
    match value {
        Value::Object(map) => {
            for (channel, candidate) in map {
                if let Some(last_message_id) = parse_status_update_message_id(channel, candidate) {
                    updates.insert(channel.clone(), last_message_id);
                    continue;
                }

                collect_status_updates(candidate, updates);
            }
        }
        Value::Array(items) => {
            for item in items {
                collect_status_updates(item, updates);
            }
        }
        _ => {}
    }
}

fn parse_status_update_message_id(channel: &str, value: &Value) -> Option<i64> {
    if !channel.starts_with('/') {
        return None;
    }

    match value {
        Value::Number(number) => number
            .as_i64()
            .or_else(|| number.as_u64().map(|id| id as i64)),
        Value::String(raw) => raw.parse::<i64>().ok(),
        Value::Object(map) => {
            for key in ["message_id", "last_message_id"] {
                if let Some(candidate) = map.get(key) {
                    if let Some(id) = parse_status_update_message_id(channel, candidate) {
                        return Some(id);
                    }
                }
            }
            None
        }
        _ => None,
    }
}

fn as_i64(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_u64().map(|id| id as i64))
        .or_else(|| value.as_str().and_then(|raw| raw.parse::<i64>().ok()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use fire_models::MessageBusSubscription;

    #[test]
    fn parse_message_bus_poll_response_handles_segmented_arrays_and_status_updates() {
        let body = r#"[{"channel":"/topic/1","message_id":3,"data":{"type":"created"}}]|[{"channel":"/__status","message_id":4,"data":{"/topic/1":5,"/notification/1":"6"}}]"#;

        let result = parse_message_bus_poll_response(body).expect("poll parse");

        assert_eq!(result.messages.len(), 2);
        assert_eq!(
            result.status_updates,
            vec![
                MessageBusSubscription {
                    channel: "/notification/1".into(),
                    last_message_id: 6,
                },
                MessageBusSubscription {
                    channel: "/topic/1".into(),
                    last_message_id: 5,
                },
            ]
        );
    }

    #[test]
    fn build_message_bus_poll_request_serializes_channel_cursors() {
        let subscriptions = vec![
            MessageBusSubscription {
                channel: "/notification/1".into(),
                last_message_id: 7,
            },
            MessageBusSubscription {
                channel: "/topic/123".into(),
                last_message_id: 42,
            },
        ];

        let body = encode_message_bus_poll_body(&subscriptions);
        assert!(body.contains("%2Fnotification%2F1=7"));
        assert!(body.contains("%2Ftopic%2F123=42"));
    }
}
