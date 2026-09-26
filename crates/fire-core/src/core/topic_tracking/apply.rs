use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use fire_models::{
    BootstrapArtifacts, TopicNotificationLevel, TopicTrackingMessageType, TrackedTopicState,
};
use serde_json::Value;

use crate::json_helpers::{boolean, integer_u32, optional_boolean, positive_u64};
use crate::parsing::parse_preloaded_payload;

#[derive(Default)]
pub(crate) struct FireTopicTrackingRuntime {
    pub(crate) auth_scope_hash: String,
    pub(crate) topics: HashMap<u64, TrackedTopicState>,
}

pub(crate) fn hydrate_topic_tracking_states(
    bootstrap: &BootstrapArtifacts,
) -> HashMap<u64, TrackedTopicState> {
    let Some(preloaded_json) = bootstrap.preloaded_json.as_deref() else {
        return HashMap::new();
    };
    let Some(parsed) = parse_preloaded_payload(preloaded_json) else {
        return HashMap::new();
    };
    let Some(states) = parsed.get("topicTrackingStates") else {
        return HashMap::new();
    };
    parse_tracked_topic_states(states)
}

pub(crate) fn parse_tracked_topic_states(value: &Value) -> HashMap<u64, TrackedTopicState> {
    let mut topics = HashMap::new();
    match value {
        Value::Object(object) => {
            for (key, item) in object {
                if let Some(state) = parse_tracked_topic_state(item).or_else(|| {
                    key.parse::<u64>()
                        .ok()
                        .filter(|id| *id > 0)
                        .and_then(|topic_id| {
                            parse_tracked_topic_state(item).map(|mut state| {
                                state.topic_id = topic_id;
                                state
                            })
                        })
                }) {
                    topics.insert(state.topic_id, state);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                if let Some(state) = parse_tracked_topic_state(item) {
                    topics.insert(state.topic_id, state);
                }
            }
        }
        _ => {}
    }
    topics
}

pub(crate) fn parse_tracked_topic_state(value: &Value) -> Option<TrackedTopicState> {
    let object = value.as_object()?;
    let topic_id = positive_u64(object.get("topic_id").or_else(|| object.get("id")))?;
    let last_read_post_number = integer_u32(
        object
            .get("last_read_post_number")
            .or_else(|| object.get("last_read_post_id")),
    );
    let highest_post_number = integer_u32(object.get("highest_post_number")).unwrap_or(0);
    let created_in_new_period = optional_boolean(object.get("created_in_new_period"))
        .unwrap_or(last_read_post_number.is_none());
    Some(TrackedTopicState {
        topic_id,
        last_read_post_number,
        highest_post_number,
        category_id: positive_u64(object.get("category_id")),
        notification_level: TopicNotificationLevel::from_u32(
            integer_u32(object.get("notification_level")).unwrap_or(1),
        ),
        created_in_new_period,
        is_seen: boolean(object.get("is_seen")),
    })
}

pub(crate) fn apply_topic_tracking_event(
    runtime: &Arc<Mutex<FireTopicTrackingRuntime>>,
    channel: &str,
    data: &Value,
) -> Vec<u64> {
    if !is_topic_tracking_channel(channel) {
        return Vec::new();
    }
    let message_type = data
        .get("message_type")
        .and_then(Value::as_str)
        .unwrap_or_default();
    apply_topic_tracking_value(runtime, message_type, data)
}

pub(crate) fn apply_topic_tracking_value(
    runtime: &Arc<Mutex<FireTopicTrackingRuntime>>,
    message_type: &str,
    data: &Value,
) -> Vec<u64> {
    let Some(kind) = TopicTrackingMessageType::parse(message_type) else {
        return Vec::new();
    };
    let mut runtime = runtime
        .lock()
        .expect("topic tracking runtime lock poisoned");
    match kind {
        TopicTrackingMessageType::DismissNew => apply_dismiss_new(&mut runtime, data),
        TopicTrackingMessageType::DismissNewPosts => apply_dismiss_new_posts(&mut runtime, data),
        TopicTrackingMessageType::NewTopic
        | TopicTrackingMessageType::Unread
        | TopicTrackingMessageType::Read => apply_cursor_upsert(&mut runtime, kind, data)
            .into_iter()
            .collect(),
    }
}

pub(crate) fn note_local_topic_read(
    runtime: &Arc<Mutex<FireTopicTrackingRuntime>>,
    topic_id: u64,
    last_read_post_number: Option<u32>,
    highest_post_number: u32,
) {
    if topic_id == 0 {
        return;
    }
    let mut runtime = runtime
        .lock()
        .expect("topic tracking runtime lock poisoned");
    let entry = runtime
        .topics
        .entry(topic_id)
        .or_insert_with(|| TrackedTopicState {
            topic_id,
            last_read_post_number: None,
            highest_post_number: 0,
            category_id: None,
            notification_level: TopicNotificationLevel::Tracking,
            created_in_new_period: last_read_post_number.is_none(),
            is_seen: false,
        });
    merge_cursors(entry, last_read_post_number, Some(highest_post_number));
    if entry.last_read_post_number.is_some() {
        entry.is_seen = true;
        entry.created_in_new_period = false;
    }
}

pub(crate) fn is_topic_tracking_channel(channel: &str) -> bool {
    matches!(channel, "/latest" | "/new" | "/unread")
}

fn apply_cursor_upsert(
    runtime: &mut FireTopicTrackingRuntime,
    kind: TopicTrackingMessageType,
    data: &Value,
) -> Option<u64> {
    let payload = payload_object(data);
    let topic_id = topic_id_from_event(data, payload)?;
    let incoming = parse_tracked_topic_state(payload).unwrap_or_else(|| TrackedTopicState {
        topic_id,
        last_read_post_number: integer_u32(payload.get("last_read_post_number")),
        highest_post_number: integer_u32(payload.get("highest_post_number")).unwrap_or(0),
        category_id: positive_u64(payload.get("category_id")),
        notification_level: TopicNotificationLevel::from_u32(
            integer_u32(payload.get("notification_level")).unwrap_or(1),
        ),
        created_in_new_period: optional_boolean(payload.get("created_in_new_period"))
            .unwrap_or(false),
        is_seen: boolean(payload.get("is_seen")),
    });
    let entry = runtime
        .topics
        .entry(topic_id)
        .or_insert_with(|| TrackedTopicState {
            topic_id,
            last_read_post_number: None,
            highest_post_number: 0,
            category_id: incoming.category_id,
            notification_level: incoming.notification_level,
            created_in_new_period: incoming.created_in_new_period,
            is_seen: incoming.is_seen,
        });

    if payload.get("category_id").is_some() {
        entry.category_id = incoming.category_id;
    }
    if payload.get("notification_level").is_some() {
        entry.notification_level = incoming.notification_level;
    }
    if payload.get("created_in_new_period").is_some() {
        entry.created_in_new_period = incoming.created_in_new_period;
    }
    if payload.get("is_seen").is_some() {
        entry.is_seen = incoming.is_seen;
    }

    let mut last_read = if payload.get("last_read_post_number").is_some() {
        incoming.last_read_post_number
    } else {
        None
    };
    let highest = if payload.get("highest_post_number").is_some() {
        Some(incoming.highest_post_number)
    } else {
        None
    };

    if kind == TopicTrackingMessageType::Unread && last_read.is_none() {
        last_read = Some(entry.last_read_post_number.unwrap_or_else(|| {
            let baseline = if entry.highest_post_number > 0 {
                entry.highest_post_number
            } else {
                incoming.highest_post_number
            };
            baseline.saturating_sub(1).max(1)
        }));
        if payload.get("notification_level").is_none()
            && !entry.notification_level.is_at_least_tracking()
        {
            entry.notification_level = TopicNotificationLevel::Tracking;
        }
    }

    merge_cursors(entry, last_read, highest);
    Some(topic_id)
}

fn apply_dismiss_new(runtime: &mut FireTopicTrackingRuntime, data: &Value) -> Vec<u64> {
    topic_ids_from_dismiss_payload(data)
        .into_iter()
        .filter_map(|topic_id| {
            let entry = runtime.topics.get_mut(&topic_id)?;
            if entry.is_seen {
                return None;
            }
            entry.is_seen = true;
            Some(topic_id)
        })
        .collect()
}

fn apply_dismiss_new_posts(runtime: &mut FireTopicTrackingRuntime, data: &Value) -> Vec<u64> {
    topic_ids_from_dismiss_payload(data)
        .into_iter()
        .filter_map(|topic_id| {
            let entry = runtime.topics.get_mut(&topic_id)?;
            if entry.highest_post_number == 0 {
                return None;
            }
            let before = entry.last_read_post_number;
            merge_cursors(entry, Some(entry.highest_post_number), None);
            (entry.last_read_post_number != before).then_some(topic_id)
        })
        .collect()
}

fn merge_cursors(state: &mut TrackedTopicState, last_read: Option<u32>, highest: Option<u32>) {
    if let Some(highest) = highest {
        state.highest_post_number = state.highest_post_number.max(highest);
    }
    if let Some(last_read) = last_read {
        state.last_read_post_number = Some(state.last_read_post_number.unwrap_or(0).max(last_read));
    }
}

fn payload_object(data: &Value) -> &Value {
    data.get("payload").unwrap_or(data)
}

fn topic_id_from_event(data: &Value, payload: &Value) -> Option<u64> {
    positive_u64(data.get("topic_id"))
        .or_else(|| positive_u64(payload.get("topic_id")))
        .or_else(|| positive_u64(payload.get("id")))
}

fn topic_ids_from_dismiss_payload(data: &Value) -> Vec<u64> {
    let payload = payload_object(data);
    let mut ids = Vec::new();
    if let Some(topic_id) = topic_id_from_event(data, payload) {
        ids.push(topic_id);
    }
    let candidates = [
        payload.get("topic_ids"),
        payload.get("dismissed_topic_ids"),
        data.get("topic_ids"),
    ];
    for candidate in candidates.into_iter().flatten() {
        match candidate {
            Value::Array(items) => {
                for item in items {
                    if let Some(topic_id) = positive_u64(Some(item)) {
                        if !ids.contains(&topic_id) {
                            ids.push(topic_id);
                        }
                    }
                }
            }
            other => {
                if let Some(topic_id) = positive_u64(Some(other)) {
                    if !ids.contains(&topic_id) {
                        ids.push(topic_id);
                    }
                }
            }
        }
    }
    ids
}

#[cfg(test)]
mod tests {
    use super::*;

    fn runtime() -> Arc<Mutex<FireTopicTrackingRuntime>> {
        Arc::new(Mutex::new(FireTopicTrackingRuntime::default()))
    }

    fn tracked(
        topic_id: u64,
        last_read: Option<u32>,
        highest: u32,
        level: TopicNotificationLevel,
    ) -> TrackedTopicState {
        TrackedTopicState {
            topic_id,
            last_read_post_number: last_read,
            highest_post_number: highest,
            category_id: Some(4),
            notification_level: level,
            created_in_new_period: last_read.is_none(),
            is_seen: false,
        }
    }

    #[test]
    fn unread_infers_last_read_and_tracking_level() {
        let runtime = runtime();
        runtime
            .lock()
            .unwrap()
            .topics
            .insert(11, tracked(11, None, 4, TopicNotificationLevel::Regular));
        let changed = apply_topic_tracking_value(
            &runtime,
            "unread",
            &serde_json::json!({
                "topic_id": 11,
                "payload": { "highest_post_number": 8 }
            }),
        );
        assert_eq!(changed, vec![11]);
        let state = runtime.lock().unwrap().topics[&11].clone();
        assert_eq!(state.last_read_post_number, Some(3));
        assert_eq!(state.highest_post_number, 8);
        assert_eq!(state.notification_level, TopicNotificationLevel::Tracking);
        assert!(state.is_unread());
    }

    #[test]
    fn cursors_only_move_forward() {
        let runtime = runtime();
        note_local_topic_read(&runtime, 22, Some(12), 12);
        let changed = apply_topic_tracking_value(
            &runtime,
            "unread",
            &serde_json::json!({
                "topic_id": 22,
                "payload": {
                    "last_read_post_number": 7,
                    "highest_post_number": 9
                }
            }),
        );
        assert_eq!(changed, vec![22]);
        let state = runtime.lock().unwrap().topics[&22].clone();
        assert_eq!(state.last_read_post_number, Some(12));
        assert_eq!(state.highest_post_number, 12);
        assert!(!state.is_unread());
    }

    #[test]
    fn dismiss_new_clears_new_predicate() {
        let runtime = runtime();
        runtime
            .lock()
            .unwrap()
            .topics
            .insert(33, tracked(33, None, 1, TopicNotificationLevel::Regular));
        assert!(runtime.lock().unwrap().topics[&33].is_new());
        let changed = apply_topic_tracking_value(
            &runtime,
            "dismiss_new",
            &serde_json::json!({ "payload": { "topic_ids": [33] } }),
        );
        assert_eq!(changed, vec![33]);
        assert!(!runtime.lock().unwrap().topics[&33].is_new());
    }

    #[test]
    fn dismiss_new_posts_raises_last_read() {
        let runtime = runtime();
        runtime.lock().unwrap().topics.insert(
            44,
            tracked(44, Some(2), 9, TopicNotificationLevel::Tracking),
        );
        let changed = apply_topic_tracking_value(
            &runtime,
            "dismiss_new_posts",
            &serde_json::json!({ "topic_id": 44 }),
        );
        assert_eq!(changed, vec![44]);
        let state = runtime.lock().unwrap().topics[&44].clone();
        assert_eq!(state.last_read_post_number, Some(9));
        assert!(!state.is_unread());
    }

    #[test]
    fn latest_message_type_is_ignored() {
        let runtime = runtime();
        let changed = apply_topic_tracking_value(
            &runtime,
            "latest",
            &serde_json::json!({ "topic_id": 55, "payload": { "highest_post_number": 3 } }),
        );
        assert!(changed.is_empty());
        assert!(runtime.lock().unwrap().topics.is_empty());
    }

    #[test]
    fn new_topic_predicate_and_counts() {
        let state = tracked(1, None, 1, TopicNotificationLevel::Regular);
        assert!(state.is_new());
        assert_eq!(state.unread_posts(), 0);
        assert_eq!(state.new_posts(), 1);
        let unread = tracked(2, Some(3), 8, TopicNotificationLevel::Tracking);
        assert!(unread.is_unread());
        assert_eq!(unread.unread_posts(), 5);
        assert_eq!(unread.new_posts(), 0);
    }
}
