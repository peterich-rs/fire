#[uniffi::export]
impl FireChatHandle {
    pub fn chat_list_snapshot(&self) -> Result<Option<MyChatChannelsState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "chat_list_snapshot",
            |inner| {
                let base_url = inner.base_url().to_string();
                inner
                    .chat_list_snapshot()
                    .map(|channels| ChatStateMapper::new(&base_url).my_channels(channels))
            },
        )
    }

    pub fn apply_chat_list_tracking(
        &self,
        channel_id: u64,
        unread: u32,
        mention: u32,
        explicit_mark_read: bool,
    ) -> Result<MyChatChannelsState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_chat_list_tracking",
            |inner| {
                let base_url = inner.base_url().to_string();
                let snapshot = inner.apply_chat_list_tracking(
                    channel_id,
                    unread,
                    mention,
                    explicit_mark_read,
                );
                ChatStateMapper::new(&base_url).my_channels(snapshot)
            },
        )
    }

    pub fn apply_chat_list_bus_event(
        &self,
        payload_json: String,
        event_type: Option<String>,
        fallback_channel_id: Option<u64>,
    ) -> Result<MyChatChannelsState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_chat_list_bus_event",
            |inner| {
                let base_url = inner.base_url().to_string();
                let event = fire_core::chat_bus_event_from_payload(
                    &payload_json,
                    event_type.as_deref(),
                    fallback_channel_id,
                    &base_url,
                );
                let snapshot = inner.apply_chat_list_bus_event(event);
                ChatStateMapper::new(&base_url).my_channels(snapshot)
            },
        )
    }

    pub fn chat_channel_runtime_snapshot(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
    ) -> Result<Option<ChatChannelRuntimeState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "chat_channel_runtime_snapshot",
            |inner| {
                let base_url = inner.base_url().to_string();
                inner
                    .chat_channel_runtime_snapshot(channel_id, thread_id)
                    .map(|snapshot| ChatStateMapper::new(&base_url).channel_runtime(snapshot))
            },
        )
    }

    pub fn apply_chat_channel_bus_event(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
        payload_json: String,
        event_type: Option<String>,
    ) -> Result<ChatChannelRuntimeState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_chat_channel_bus_event",
            |inner| {
                let base_url = inner.base_url().to_string();
                let event = fire_core::chat_bus_event_from_payload(
                    &payload_json,
                    event_type.as_deref(),
                    Some(channel_id),
                    &base_url,
                );
                let snapshot = inner.apply_chat_channel_bus_event(
                    channel_id,
                    thread_id,
                    event,
                    event_type.as_deref(),
                );
                ChatStateMapper::new(&base_url).channel_runtime(snapshot)
            },
        )
    }

    pub fn close_chat_channel_runtime(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
    ) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "close_chat_channel_runtime",
            |inner| inner.close_chat_channel_runtime(channel_id, thread_id),
        )
    }
}
