use std::sync::Arc;

use fire_models::{
    MessageBusEvent, MessageBusEventKind, MessageBusSubscription, MessageBusSubscriptionScope,
};
use serde_json::Value;
use tokio::sync::mpsc;
use tracing::debug;

use super::super::FireCore;
use super::*;
use crate::json_helpers::{integer_u32, positive_u64};

impl ActorState {
    pub(super) fn arm_refresh(&mut self, tx: &mpsc::UnboundedSender<Command>) {
        self.refresh_generation = self.refresh_generation.saturating_add(1);
        let generation = self.refresh_generation;
        let tx = tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(TOPIC_DETAIL_REFRESH_DEBOUNCE).await;
            let _ = tx.send(Command::RefreshFired(generation));
        });
    }

    pub(super) fn install_bus_listener(
        &mut self,
        core: &FireCore,
        tx: mpsc::UnboundedSender<Command>,
    ) {
        let topic_id = self.topic_id;
        let on_event_tx = tx.clone();
        let on_started_tx = tx;
        let id = core.add_message_bus_internal_listener(
            Arc::new(move |event: &MessageBusEvent| {
                if !event_matches_topic(event, topic_id) {
                    return;
                }
                match event.kind {
                    MessageBusEventKind::TopicDetail | MessageBusEventKind::TopicReaction => {
                        let action = topic_bus_action_from_event(event);
                        if !matches!(action, TopicBusAction::Ignore | TopicBusAction::Presence) {
                            let _ = on_event_tx.send(Command::BusEvent(action));
                        }
                    }
                    MessageBusEventKind::Presence => {
                        let _ = on_event_tx.send(Command::RefreshPresence);
                    }
                    _ => {}
                }
            }),
            Arc::new(|| {}),
            Arc::new(move || {
                let _ = on_started_tx.send(Command::BusStarted);
            }),
        );
        self.bus_listener_id = Some(id);
    }

    pub(super) fn subscribe_channels(&mut self, core: &FireCore) {
        let Some(header) = self.header.clone() else {
            return;
        };
        let owner = self.bus_owner();
        let topic_id = self.topic_id;
        let _ = core.subscribe_message_bus_channel(MessageBusSubscription {
            owner_token: owner.clone(),
            channel: format!("/topic/{topic_id}"),
            last_message_id: header.message_bus_last_id,
            scope: MessageBusSubscriptionScope::Transient,
        });
        let _ = core.subscribe_message_bus_channel(MessageBusSubscription {
            owner_token: owner.clone(),
            channel: format!("/topic/{topic_id}/reactions"),
            last_message_id: None,
            scope: MessageBusSubscriptionScope::Transient,
        });
        let _ = core.subscribe_message_bus_channel(MessageBusSubscription {
            owner_token: owner,
            channel: format!("/polls/{topic_id}"),
            last_message_id: Some(0),
            scope: MessageBusSubscriptionScope::Transient,
        });
        self.bus_subscribed = true;
    }

    pub(super) fn unsubscribe(&self, core: &FireCore) {
        if !self.bus_subscribed && !self.typing {
            return;
        }
        let owner = self.bus_owner();
        let topic_id = self.topic_id;
        for channel in [
            format!("/topic/{topic_id}"),
            format!("/topic/{topic_id}/reactions"),
            format!("/polls/{topic_id}"),
            presence_channel(topic_id),
        ] {
            let _ = core.unsubscribe_message_bus_channel(owner.clone(), channel);
        }
    }

    pub(super) fn bus_owner(&self) -> String {
        format!("topic-detail-session:{}", self.topic_id)
    }

    pub(super) fn refresh_presence(&mut self, core: &FireCore) {
        self.typing_users = core.topic_reply_presence_state(self.topic_id).users;
        self.publish(core);
    }

    pub(super) fn enqueue_bus_action(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        action: TopicBusAction,
    ) {
        match action {
            TopicBusAction::Ignore => {}
            TopicBusAction::Presence => self.refresh_presence(core),
            TopicBusAction::Stats {
                posts_count,
                like_count,
            } => {
                self.apply_stats(core, posts_count, like_count);
            }
            TopicBusAction::NotificationLevel(level) => {
                self.apply_notification_level(core, level);
            }
            TopicBusAction::ReloadTopic { refresh_stream } => {
                self.pending_reload = Some(self.pending_reload.unwrap_or(false) || refresh_stream);
                if self.scroll_active {
                    self.deferred.refresh = true;
                } else {
                    self.arm_refresh(tx);
                }
            }
            TopicBusAction::Created { post_id, .. } => {
                if post_id == 0 {
                    return;
                }
                if self.has_loaded_post(core, post_id) {
                    return;
                }
                self.pending_created_ids.insert(post_id);
                self.pending_post_ids.insert(post_id);
                self.arm_refresh(tx);
            }
            TopicBusAction::RefreshPost {
                post_id,
                updated_at,
                preserve_cooked: _,
                height_changing,
                likes_count,
            } => {
                if post_id == 0 || !self.has_loaded_post(core, post_id) {
                    return;
                }
                if let Some(likes_count) = likes_count {
                    self.apply_local_like_count(core, post_id, likes_count);
                }
                if self.local_updated_at_is_newer(core, post_id, updated_at.as_deref()) {
                    return;
                }
                if self.inflight_refresh_ids.contains(&post_id) {
                    self.retry_post_ids.insert(post_id);
                    return;
                }
                if height_changing && self.scroll_active {
                    self.pending_height_changing.insert(post_id);
                    self.deferred.refresh = true;
                    return;
                }
                self.pending_post_ids.insert(post_id);
                self.arm_refresh(tx);
            }
        }
    }

    fn apply_stats(&mut self, core: &FireCore, posts_count: Option<u32>, like_count: Option<u32>) {
        let changed = core.with_topic_source_session_mut(self.topic_id, None, |session| {
            let header = session.header_mut();
            let mut changed = false;
            if let Some(posts_count) = posts_count {
                if header.posts_count != posts_count {
                    header.posts_count = posts_count;
                    changed = true;
                }
            }
            if let Some(like_count) = like_count {
                if header.like_count != like_count {
                    header.like_count = like_count;
                    changed = true;
                }
            }
            changed
        });
        if changed == Some(true) {
            if let Some(header) =
                core.with_topic_source_session_mut(self.topic_id, None, |session| {
                    session.header().clone()
                })
            {
                let _ = core.note_local_topic_read(
                    header.topic_id,
                    header.last_read_post_number,
                    header.highest_post_number,
                );
            }
            self.publish(core);
        }
    }

    fn apply_notification_level(&mut self, core: &FireCore, level: u32) {
        let changed = core.with_topic_source_session_mut(self.topic_id, None, |session| {
            let header = session.header_mut();
            let next = Some(level as i32);
            if header.details.notification_level != next {
                header.details.notification_level = next;
                true
            } else {
                false
            }
        });
        if changed == Some(true) {
            self.publish(core);
        }
    }

    fn apply_local_like_count(&mut self, core: &FireCore, post_id: u64, likes_count: u32) {
        let changed = core.with_topic_source_session_mut(self.topic_id, None, |session| {
            let Some(post) = session.post_mut(post_id) else {
                return false;
            };
            if post.like_count == likes_count {
                return false;
            }
            post.like_count = likes_count;
            true
        });
        if changed == Some(true) {
            self.publish(core);
        }
    }

    fn has_loaded_post(&self, core: &FireCore, post_id: u64) -> bool {
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session.post(post_id).is_some()
        })
        .unwrap_or(false)
    }

    fn local_updated_at_is_newer(
        &self,
        core: &FireCore,
        post_id: u64,
        incoming: Option<&str>,
    ) -> bool {
        let Some(incoming) = incoming.filter(|value| !value.is_empty()) else {
            return false;
        };
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session
                .post(post_id)
                .and_then(|post| post.updated_at.as_deref())
                .is_some_and(|local| local >= incoming)
        })
        .unwrap_or(false)
    }
}

pub(super) fn event_matches_topic(event: &MessageBusEvent, topic_id: u64) -> bool {
    if event.topic_id == Some(topic_id) {
        return true;
    }
    event.channel == format!("/topic/{topic_id}")
        || event.channel == format!("/topic/{topic_id}/reactions")
        || event.channel == format!("/polls/{topic_id}")
        || event.channel == presence_channel(topic_id)
        || event.detail_event_type.as_deref() == Some("polls")
            && event.channel.starts_with(&format!("/polls/{topic_id}"))
}

pub(super) fn presence_channel(topic_id: u64) -> String {
    format!("/presence/discourse-presence/reply/{topic_id}")
}

pub(crate) fn topic_bus_action_from_event(event: &MessageBusEvent) -> TopicBusAction {
    if event.channel.contains("/presence/") {
        return TopicBusAction::Presence;
    }
    if event.kind == MessageBusEventKind::TopicReaction {
        return classify_reaction_event(event);
    }
    if event.channel.contains("/polls/") || event.detail_event_type.as_deref() == Some("polls") {
        let payload = parse_payload(event.payload_json.as_deref());
        return if let Some(post_id) = post_id_from_payload(&payload) {
            TopicBusAction::RefreshPost {
                post_id,
                updated_at: scalar_updated_at(&payload),
                preserve_cooked: false,
                height_changing: true,
                likes_count: None,
            }
        } else {
            TopicBusAction::ReloadTopic {
                refresh_stream: true,
            }
        };
    }
    if event.reload_topic {
        return TopicBusAction::ReloadTopic {
            refresh_stream: event.refresh_stream,
        };
    }
    classify_topic_event_type(
        event.detail_event_type.as_deref().unwrap_or_default(),
        event.payload_json.as_deref(),
    )
}

fn classify_reaction_event(event: &MessageBusEvent) -> TopicBusAction {
    let payload = parse_payload(event.payload_json.as_deref());
    if let Some(post_id) = post_id_from_payload(&payload) {
        return TopicBusAction::RefreshPost {
            post_id,
            updated_at: scalar_updated_at(&payload),
            preserve_cooked: false,
            height_changing: false,
            likes_count: integer_u32(
                payload
                    .get("likes_count")
                    .or_else(|| payload.get("like_count")),
            ),
        };
    }
    debug!(channel = %event.channel, "ignoring topic reaction event without post_id");
    TopicBusAction::Ignore
}

fn classify_topic_event_type(event_type: &str, payload_json: Option<&str>) -> TopicBusAction {
    let payload = parse_payload(payload_json);
    match event_type {
        "created" => TopicBusAction::Created {
            post_id: post_id_from_payload(&payload).unwrap_or(0),
            user_id: positive_u64(payload.get("user_id")),
        },
        "revised" | "rebaked" | "deleted" | "destroyed" | "recovered" | "acted"
        | "policy_change" | "boost_created" | "boost_deleted" | "boost_updated" => {
            TopicBusAction::RefreshPost {
                post_id: post_id_from_payload(&payload).unwrap_or(0),
                updated_at: scalar_updated_at(&payload),
                preserve_cooked: false,
                height_changing: matches!(event_type, "revised" | "rebaked" | "recovered"),
                likes_count: None,
            }
        }
        "liked" | "unliked" => TopicBusAction::RefreshPost {
            post_id: post_id_from_payload(&payload).unwrap_or(0),
            updated_at: scalar_updated_at(&payload),
            preserve_cooked: false,
            height_changing: false,
            likes_count: integer_u32(
                payload
                    .get("likes_count")
                    .or_else(|| payload.get("like_count")),
            ),
        },
        "read" => {
            if payload.get("readers_count").is_some() && payload.get("id").is_none() {
                TopicBusAction::Ignore
            } else {
                TopicBusAction::Ignore
            }
        }
        "stats" => TopicBusAction::Stats {
            posts_count: integer_u32(
                payload
                    .get("posts_count")
                    .or_else(|| payload.get("postsCount")),
            ),
            like_count: integer_u32(
                payload
                    .get("like_count")
                    .or_else(|| payload.get("likeCount")),
            ),
        },
        "notification_level_change" => integer_u32(
            payload
                .get("notification_level")
                .or_else(|| payload.get("notificationLevel")),
        )
        .map(TopicBusAction::NotificationLevel)
        .unwrap_or(TopicBusAction::Ignore),
        "shared_issue" => TopicBusAction::Stats {
            posts_count: integer_u32(payload.get("posts_count")),
            like_count: None,
        },
        "reload_topic" => TopicBusAction::ReloadTopic {
            refresh_stream: boolean_refresh_stream(&payload),
        },
        "" => TopicBusAction::Ignore,
        other => {
            debug!(event_type = other, "ignoring unknown topic bus event type");
            TopicBusAction::Ignore
        }
    }
}

fn parse_payload(payload_json: Option<&str>) -> Value {
    payload_json
        .and_then(|value| serde_json::from_str(value).ok())
        .unwrap_or(Value::Null)
}

fn post_id_from_payload(payload: &Value) -> Option<u64> {
    positive_u64(payload.get("id"))
        .or_else(|| positive_u64(payload.get("post_id")))
        .or_else(|| {
            payload
                .get("post")
                .and_then(|post| positive_u64(post.get("id")))
        })
}

fn scalar_updated_at(payload: &Value) -> Option<String> {
    payload
        .get("updated_at")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .or_else(|| {
            payload
                .get("post")
                .and_then(|post| post.get("updated_at"))
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
}

fn boolean_refresh_stream(payload: &Value) -> bool {
    crate::json_helpers::boolean(payload.get("refresh_stream"))
}

#[cfg(test)]
mod tests {
    use fire_models::MessageBusEvent;

    use super::*;

    #[test]
    fn unknown_type_does_not_reload() {
        let event = MessageBusEvent {
            kind: MessageBusEventKind::TopicDetail,
            topic_id: Some(1),
            detail_event_type: Some("mystery".into()),
            ..MessageBusEvent::default()
        };
        assert_eq!(topic_bus_action_from_event(&event), TopicBusAction::Ignore);
    }

    #[test]
    fn created_maps_post_id() {
        let event = MessageBusEvent {
            kind: MessageBusEventKind::TopicDetail,
            topic_id: Some(1),
            detail_event_type: Some("created".into()),
            payload_json: Some(r#"{"id":99,"user_id":7}"#.into()),
            ..MessageBusEvent::default()
        };
        assert_eq!(
            topic_bus_action_from_event(&event),
            TopicBusAction::Created {
                post_id: 99,
                user_id: Some(7)
            }
        );
    }

    #[test]
    fn reaction_without_post_id_is_ignored() {
        let event = MessageBusEvent {
            kind: MessageBusEventKind::TopicReaction,
            topic_id: Some(1),
            payload_json: Some(r#"{"reaction":"heart"}"#.into()),
            ..MessageBusEvent::default()
        };
        assert_eq!(topic_bus_action_from_event(&event), TopicBusAction::Ignore);
    }

    #[test]
    fn presence_channel_maps_to_presence() {
        let event = MessageBusEvent {
            kind: MessageBusEventKind::Presence,
            topic_id: Some(1),
            channel: "/presence/discourse-presence/reply/1".into(),
            ..MessageBusEvent::default()
        };
        assert_eq!(
            topic_bus_action_from_event(&event),
            TopicBusAction::Presence
        );
    }

    #[test]
    fn polls_with_post_id_refresh_that_post() {
        let event = MessageBusEvent {
            kind: MessageBusEventKind::TopicDetail,
            topic_id: Some(1),
            channel: "/polls/1".into(),
            detail_event_type: Some("polls".into()),
            payload_json: Some(r#"{"post_id":44}"#.into()),
            ..MessageBusEvent::default()
        };
        assert_eq!(
            topic_bus_action_from_event(&event),
            TopicBusAction::RefreshPost {
                post_id: 44,
                updated_at: None,
                preserve_cooked: false,
                height_changing: true,
                likes_count: None,
            }
        );
    }

    #[test]
    fn polls_without_post_id_still_reloads() {
        let event = MessageBusEvent {
            kind: MessageBusEventKind::TopicDetail,
            topic_id: Some(1),
            channel: "/polls/1".into(),
            detail_event_type: Some("polls".into()),
            payload_json: Some(r#"{"poll_name":"poll"}"#.into()),
            ..MessageBusEvent::default()
        };
        assert_eq!(
            topic_bus_action_from_event(&event),
            TopicBusAction::ReloadTopic {
                refresh_stream: true
            }
        );
    }

    #[test]
    fn reload_topic_flag_wins() {
        let event = MessageBusEvent {
            kind: MessageBusEventKind::TopicDetail,
            topic_id: Some(1),
            reload_topic: true,
            refresh_stream: true,
            detail_event_type: Some("created".into()),
            ..MessageBusEvent::default()
        };
        assert_eq!(
            topic_bus_action_from_event(&event),
            TopicBusAction::ReloadTopic {
                refresh_stream: true
            }
        );
    }
}
