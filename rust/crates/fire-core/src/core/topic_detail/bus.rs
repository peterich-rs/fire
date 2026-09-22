use std::sync::Arc;

use fire_models::{
    MessageBusEvent, MessageBusEventKind, MessageBusSubscription, MessageBusSubscriptionScope,
};
use tokio::sync::mpsc;

use super::super::FireCore;
use super::*;

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
                        let _ = on_event_tx.send(Command::BusRefresh);
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
        self.publish(core, false);
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
