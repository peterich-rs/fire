use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use fire_models::{SessionSnapshot, TopicPresence, TopicPresenceUser};
use http::Method;
use serde_json::Value;
use tracing::{debug, info};

use super::{
    messagebus::{active_message_bus_client_id, message_bus_presence_channel_for_topic},
    network::expect_success,
    rate_limit, FireCore,
};
use crate::{
    error::FireCoreError,
    json_helpers::{integer_i64, invalid_json, scalar_string},
};

const FETCH_TOPIC_PRESENCE_OPERATION: &str = "fetch topic presence";
const UPDATE_TOPIC_REPLY_PRESENCE_OPERATION: &str = "update topic reply presence";
const MIN_TOPIC_REPLY_PRESENCE_HEARTBEAT_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Default)]
pub(crate) struct FireTopicPresenceRuntime {
    user_id: Option<u64>,
    topics: BTreeMap<u64, TopicPresence>,
    active_reply_topics: BTreeSet<u64>,
    last_present_update_at: BTreeMap<u64, Instant>,
    update_cooldown_until: Option<Instant>,
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
        let value: Value = self
            .read_response_json(FETCH_TOPIC_PRESENCE_OPERATION, trace_id, response)
            .await?;
        let presence = parse_topic_presence_response_value(topic_id, &value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: FETCH_TOPIC_PRESENCE_OPERATION,
                source,
            }
        })?;

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
        if should_skip_topic_reply_presence_update(&self.topic_presence, topic_id, active) {
            if !active {
                remove_current_user_from_topic_presence(
                    &self.topic_presence,
                    topic_id,
                    self.snapshot().bootstrap.current_user_id,
                );
            }
            return Ok(());
        }
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
        let response = match expect_success(
            self,
            UPDATE_TOPIC_REPLY_PRESENCE_OPERATION,
            trace_id,
            response,
        )
        .await
        {
            Ok(response) => response,
            Err(FireCoreError::HttpStatus {
                status: 429, body, ..
            }) => {
                let cooldown = rate_limit::parse_rate_limit_cooldown(&body)
                    .unwrap_or(rate_limit::RATE_LIMIT_FALLBACK_COOLDOWN);
                apply_topic_reply_presence_rate_limit(
                    &self.topic_presence,
                    topic_id,
                    active,
                    cooldown,
                );
                info!(
                    topic_id,
                    active,
                    cooldown_ms = cooldown.as_millis() as u64,
                    "presence update rate limited; deferring subsequent updates"
                );
                if !active {
                    remove_current_user_from_topic_presence(
                        &self.topic_presence,
                        topic_id,
                        self.snapshot().bootstrap.current_user_id,
                    );
                }
                return Ok(());
            }
            Err(error) => return Err(error),
        };
        let _ = self.read_response_text(trace_id, response).await?;
        record_topic_reply_presence_update_success(&self.topic_presence, topic_id, active);

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

fn parse_topic_presence_response_value(
    topic_id: u64,
    value: &Value,
) -> Result<TopicPresence, serde_json::Error> {
    let Some(object) = value.as_object() else {
        return Err(invalid_json(
            "topic presence response root was not an object",
        ));
    };

    let channel_key = discourse_presence_channel_for_topic(topic_id);
    let Some(channel_value) = object.get(&channel_key) else {
        return Ok(TopicPresence::empty(topic_id));
    };

    if channel_value.is_null() {
        return Ok(TopicPresence::empty(topic_id));
    }

    let Some(channel) = channel_value.as_object() else {
        debug!(
            topic_id,
            "topic presence snapshot channel was not an object; treating as empty"
        );
        return Ok(TopicPresence::empty(topic_id));
    };

    Ok(TopicPresence {
        topic_id,
        message_id: integer_i64(channel.get("last_message_id"))
            .or_else(|| integer_i64(channel.get("message_id")))
            .unwrap_or_else(default_message_id),
        users: channel
            .get("users")
            .and_then(Value::as_array)
            .map(|users| {
                users
                    .iter()
                    .filter_map(topic_presence_user_from_value)
                    .collect()
            })
            .unwrap_or_default(),
    })
}

fn topic_presence_user_from_value(value: &serde_json::Value) -> Option<TopicPresenceUser> {
    let object = value.as_object()?;
    let id = crate::json_helpers::positive_u64(object.get("id"))?;
    let username = object
        .get("username")
        .and_then(|value| scalar_string(Some(value)))?
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
            .and_then(|value| scalar_string(Some(value))),
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

fn should_skip_topic_reply_presence_update(
    runtime: &Arc<Mutex<FireTopicPresenceRuntime>>,
    topic_id: u64,
    active: bool,
) -> bool {
    let now = Instant::now();
    let mut runtime = runtime
        .lock()
        .expect("topic presence runtime lock poisoned");

    if let Some(cooldown_until) = runtime.update_cooldown_until {
        if cooldown_until > now {
            if !active {
                clear_topic_reply_presence_update_state(&mut runtime, topic_id);
            }
            return true;
        }
        runtime.update_cooldown_until = None;
    }

    if active {
        return runtime.active_reply_topics.contains(&topic_id)
            && runtime
                .last_present_update_at
                .get(&topic_id)
                .is_some_and(|last_update| {
                    now.duration_since(*last_update) < MIN_TOPIC_REPLY_PRESENCE_HEARTBEAT_INTERVAL
                });
    }

    if !runtime.active_reply_topics.contains(&topic_id) {
        return true;
    }

    false
}

fn record_topic_reply_presence_update_success(
    runtime: &Arc<Mutex<FireTopicPresenceRuntime>>,
    topic_id: u64,
    active: bool,
) {
    let mut runtime = runtime
        .lock()
        .expect("topic presence runtime lock poisoned");
    if active {
        runtime.active_reply_topics.insert(topic_id);
        runtime
            .last_present_update_at
            .insert(topic_id, Instant::now());
    } else {
        clear_topic_reply_presence_update_state(&mut runtime, topic_id);
    }
}

fn apply_topic_reply_presence_rate_limit(
    runtime: &Arc<Mutex<FireTopicPresenceRuntime>>,
    topic_id: u64,
    active: bool,
    cooldown: Duration,
) {
    let mut runtime = runtime
        .lock()
        .expect("topic presence runtime lock poisoned");
    runtime.update_cooldown_until = Some(Instant::now() + cooldown);
    if !active {
        clear_topic_reply_presence_update_state(&mut runtime, topic_id);
    }
}

fn clear_topic_reply_presence_update_state(runtime: &mut FireTopicPresenceRuntime, topic_id: u64) {
    runtime.active_reply_topics.remove(&topic_id);
    runtime.last_present_update_at.remove(&topic_id);
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
