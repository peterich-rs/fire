uniffi::setup_scaffolding!("fire_uniffi_messagebus");

use std::sync::Arc;

use fire_uniffi_types::{
    ffi_runtime, run_fallible, run_infallible, run_on_ffi_runtime, FireUniFfiError, SharedFireCore,
};

pub mod records;

pub use records::{
    MessageBusClientModeState, MessageBusEventHandler, MessageBusEventKindState,
    MessageBusEventState, MessageBusSubscriptionScopeState, MessageBusSubscriptionState,
    NotificationAlertPollResultState, NotificationAlertState, TopicPresenceState,
    TopicPresenceUserState,
};

#[derive(uniffi::Object)]
pub struct FireMessageBusHandle {
    shared: Arc<SharedFireCore>,
}

impl FireMessageBusHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireMessageBusHandle {
    pub fn subscribe_channel(
        &self,
        subscription: MessageBusSubscriptionState,
    ) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "subscribe_channel",
            move |inner| inner.subscribe_message_bus_channel(subscription.into()),
        )
    }

    pub fn unsubscribe_channel(
        &self,
        owner_token: String,
        channel: String,
    ) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "unsubscribe_channel",
            move |inner| inner.unsubscribe_message_bus_channel(owner_token, channel),
        )
    }

    pub fn stop_message_bus(&self, clear_subscriptions: bool) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "stop_message_bus",
            move |inner| inner.stop_message_bus(clear_subscriptions),
        )
    }

    pub async fn start_message_bus(
        &self,
        mode: MessageBusClientModeState,
        handler: Arc<dyn MessageBusEventHandler>,
    ) -> Result<String, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let (event_sender, mut event_receiver) = tokio::sync::mpsc::unbounded_channel();
        let client_id = run_on_ffi_runtime("start_message_bus", panic_state, async move {
            inner.start_message_bus(mode.into(), event_sender).await
        })
        .await?;

        ffi_runtime().spawn(async move {
            while let Some(event) = event_receiver.recv().await {
                handler.on_message_bus_event(event.into());
            }
        });

        Ok(client_id)
    }

    pub fn topic_reply_presence_state(
        &self,
        topic_id: u64,
    ) -> Result<TopicPresenceState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "topic_reply_presence_state",
            move |inner| inner.topic_reply_presence_state(topic_id).into(),
        )
    }

    pub async fn bootstrap_topic_reply_presence(
        &self,
        topic_id: u64,
        owner_token: String,
    ) -> Result<TopicPresenceState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let presence =
            run_on_ffi_runtime("bootstrap_topic_reply_presence", panic_state, async move {
                inner
                    .bootstrap_topic_reply_presence(topic_id, owner_token)
                    .await
            })
            .await?;
        Ok(presence.into())
    }

    pub async fn update_topic_reply_presence(
        &self,
        topic_id: u64,
        active: bool,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("update_topic_reply_presence", panic_state, async move {
            inner.update_topic_reply_presence(topic_id, active).await
        })
        .await
    }

    pub async fn poll_notification_alert_once(
        &self,
        last_message_id: i64,
    ) -> Result<NotificationAlertPollResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response =
            run_on_ffi_runtime("poll_notification_alert_once", panic_state, async move {
                inner.poll_notification_alert_once(last_message_id).await
            })
            .await?;
        Ok(response.into())
    }
}
