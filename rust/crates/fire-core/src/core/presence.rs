use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

use fire_models::{SessionSnapshot, TopicPresence, TopicPresenceUser};
use http::Method;
use serde::Deserialize;
use tracing::{debug, info};

use super::{
    messagebus::{active_message_bus_client_id, message_bus_presence_channel_for_topic},
    network::expect_success,
    FireCore,
};
use crate::error::FireCoreError;

const FETCH_TOPIC_PRESENCE_OPERATION: &str = "fetch topic presence";
const UPDATE_TOPIC_REPLY_PRESENCE_OPERATION: &str = "update topic reply presence";

#[derive(Default)]
pub(crate) struct FireTopicPresenceRuntime {
    user_id: Option<u64>,
    topics: BTreeMap<u64, TopicPresence>,
}

#[derive(Debug, Deserialize)]
struct RawTopicPresenceUser {
    id: u64,
    username: String,
    #[serde(default)]
    avatar_template: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RawTopicPresenceChannel {
    #[serde(default)]
    users: Vec<RawTopicPresenceUser>,
    #[serde(default = "default_message_id")]
    message_id: i64,
}

fn default_message_id() -> i64 {
    -1
}

impl FireCore {
    pub fn topic_reply_presence_state(&self, topic_id: u64) -> TopicPresence {
        let runtime = self
            .topic_presence
            .lock()
            .expect("topic presence runtime lock poisoned");
        runtime
            .topics
            .get(&topic_id)
            .cloned()
            .unwrap_or_else(|| TopicPresence::empty(topic_id))
    }

    pub fn clear_topic_presence_state(&self) {
        let mut runtime = self
            .topic_presence
            .lock()
            .expect("topic presence runtime lock poisoned");
        *runtime = FireTopicPresenceRuntime::default();
    }

    pub async fn bootstrap_topic_reply_presence(
        &self,
        topic_id: u64,
        owner_token: String,
    ) -> Result<TopicPresence, FireCoreError> {
        let channel = message_bus_presence_channel_for_topic(topic_id);
        self.subscribe_message_bus_channel(fire_models::MessageBusSubscription {
            owner_token: owner_token.clone(),
            channel,
            last_message_id: Some(-1),
            scope: fire_models::MessageBusSubscriptionScope::Transient,
        })?;

        let presence = self.fetch_topic_reply_presence(topic_id).await?;
        self.subscribe_message_bus_channel(fire_models::MessageBusSubscription {
            owner_token,
            channel: message_bus_presence_channel_for_topic(topic_id),
            last_message_id: Some(presence.message_id),
            scope: fire_models::MessageBusSubscriptionScope::Transient,
        })?;
        Ok(presence)
    }

    pub async fn fetch_topic_reply_presence(
        &self,
        topic_id: u64,
    ) -> Result<TopicPresence, FireCoreError> {
        ensure_presence_session(self)?;
        info!(topic_id, "fetching topic reply presence");
        let traced = self.build_json_get_request(
            FETCH_TOPIC_PRESENCE_OPERATION,
            "/presence/get",
            vec![("channels[]", discourse_presence_channel_for_topic(topic_id))],
            &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response =
            expect_success(self, FETCH_TOPIC_PRESENCE_OPERATION, trace_id, response).await?;
        let value: BTreeMap<String, RawTopicPresenceChannel> =
            self.read_response_json_direct(trace_id, response).await?;

        let presence = value
            .get(&discourse_presence_channel_for_topic(topic_id))
            .map(|channel| TopicPresence {
                topic_id,
                message_id: channel.message_id,
                users: channel
                    .users
                    .iter()
                    .filter_map(topic_presence_user_from_raw)
                    .collect(),
            })
            .unwrap_or_else(|| TopicPresence::empty(topic_id));

        apply_topic_presence_snapshot(&self.topic_presence, presence.clone());
        debug!(
            topic_id,
            user_count = presence.users.len(),
            message_id = presence.message_id,
            "topic reply presence fetched successfully"
        );
        Ok(presence)
    }

    pub async fn update_topic_reply_presence(
        &self,
        topic_id: u64,
        active: bool,
    ) -> Result<(), FireCoreError> {
        ensure_presence_session(self)?;
        let client_id = active_message_bus_client_id(&self.message_bus)
            .ok_or(FireCoreError::MessageBusNotStarted)?;
        let channel = discourse_presence_channel_for_topic(topic_id);

        let mut fields = vec![("client_id".to_string(), client_id)];
        if active {
            fields.push(("present_channels[]".to_string(), channel));
        } else {
            fields.push(("leave_channels[]".to_string(), channel));
        }

        let traced = self.build_form_request_with_headers(
            UPDATE_TOPIC_REPLY_PRESENCE_OPERATION,
            Method::POST,
            "/presence/update",
            fields,
            vec![
                ("X-SILENCE-LOGGER", "true".to_string()),
                ("Discourse-Background", "true".to_string()),
            ],
            true,
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(
            self,
            UPDATE_TOPIC_REPLY_PRESENCE_OPERATION,
            trace_id,
            response,
        )
        .await?;
        let _ = self.read_response_text(trace_id, response).await?;

        if !active {
            remove_current_user_from_topic_presence(
                &self.topic_presence,
                topic_id,
                self.snapshot().bootstrap.current_user_id,
            );
        }

        Ok(())
    }
}

pub(crate) fn merge_topic_presence_event_data(
    runtime: &Arc<Mutex<FireTopicPresenceRuntime>>,
    topic_id: u64,
    message_id: i64,
    data: &serde_json::Value,
) {
    let Some(object) = data.as_object() else {
        return;
    };

    let mut runtime = runtime
        .lock()
        .expect("topic presence runtime lock poisoned");
    let entry = runtime
        .topics
        .entry(topic_id)
        .or_insert_with(|| TopicPresence::empty(topic_id));
    entry.message_id = entry.message_id.max(message_id);

    if let Some(users) = object.get("users").and_then(serde_json::Value::as_array) {
        entry.users = users
            .iter()
            .filter_map(topic_presence_user_from_value)
            .collect();
        return;
    }

    if let Some(users) = object
        .get("entering_users")
        .and_then(serde_json::Value::as_array)
    {
        for user in users.iter().filter_map(topic_presence_user_from_value) {
            if !entry.users.iter().any(|known| known.id == user.id) {
                entry.users.push(user);
            }
        }
    }

    if let Some(leaving_user_ids) = object
        .get("leaving_user_ids")
        .and_then(serde_json::Value::as_array)
    {
        let leaving = leaving_user_ids
            .iter()
            .filter_map(|value| crate::json_helpers::positive_u64(Some(value)))
            .collect::<Vec<_>>();
        if !leaving.is_empty() {
            entry.users.retain(|user| !leaving.contains(&user.id));
        }
    }
}

pub(crate) fn reconcile_topic_presence_runtime(
    runtime: &Arc<Mutex<FireTopicPresenceRuntime>>,
    snapshot: &SessionSnapshot,
) {
    let user_id = snapshot.bootstrap.current_user_id;
    if !snapshot.cookies.can_authenticate_requests() || user_id.is_none() {
        let mut runtime = runtime
            .lock()
            .expect("topic presence runtime lock poisoned");
        *runtime = FireTopicPresenceRuntime::default();
        return;
    }

    let mut runtime = runtime
        .lock()
        .expect("topic presence runtime lock poisoned");
    if runtime.user_id != user_id {
        *runtime = FireTopicPresenceRuntime {
            user_id,
            ..FireTopicPresenceRuntime::default()
        };
    }
}

fn ensure_presence_session(core: &FireCore) -> Result<(), FireCoreError> {
    if core.snapshot().cookies.can_authenticate_requests() {
        Ok(())
    } else {
        Err(FireCoreError::MissingLoginSession)
    }
}

fn discourse_presence_channel_for_topic(topic_id: u64) -> String {
    format!("/discourse-presence/reply/{topic_id}")
}

fn topic_presence_user_from_raw(value: &RawTopicPresenceUser) -> Option<TopicPresenceUser> {
    if value.id == 0 || value.username.trim().is_empty() {
        return None;
    }

    Some(TopicPresenceUser {
        id: value.id,
        username: value.username.clone(),
        avatar_template: value.avatar_template.clone(),
    })
}

fn topic_presence_user_from_value(value: &serde_json::Value) -> Option<TopicPresenceUser> {
    let object = value.as_object()?;
    let id = crate::json_helpers::positive_u64(object.get("id"))?;
    let username = object
        .get("username")
        .and_then(serde_json::Value::as_str)?
        .trim()
        .to_string();
    if username.is_empty() {
        return None;
    }

    Some(TopicPresenceUser {
        id,
        username,
        avatar_template: object
            .get("avatar_template")
            .and_then(serde_json::Value::as_str)
            .map(ToOwned::to_owned),
    })
}

fn apply_topic_presence_snapshot(
    runtime: &Arc<Mutex<FireTopicPresenceRuntime>>,
    presence: TopicPresence,
) {
    let mut runtime = runtime
        .lock()
        .expect("topic presence runtime lock poisoned");
    runtime.topics.insert(presence.topic_id, presence);
}

fn remove_current_user_from_topic_presence(
    runtime: &Arc<Mutex<FireTopicPresenceRuntime>>,
    topic_id: u64,
    current_user_id: Option<u64>,
) {
    let Some(current_user_id) = current_user_id else {
        return;
    };

    let mut runtime = runtime
        .lock()
        .expect("topic presence runtime lock poisoned");
    let Some(entry) = runtime.topics.get_mut(&topic_id) else {
        return;
    };
    entry.users.retain(|user| user.id != current_user_id);
}
