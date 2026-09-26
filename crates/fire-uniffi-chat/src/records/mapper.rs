#[derive(Clone, Copy)]
pub(crate) struct ChatStateMapper<'a> {
    base_url: &'a str,
}

impl<'a> ChatStateMapper<'a> {
    pub(crate) fn new(base_url: &'a str) -> Self {
        Self { base_url }
    }

    pub(crate) fn message(&self, value: ChatMessage) -> ChatMessageState {
        chat_message_state_from_model(value, self.base_url)
    }

    pub(crate) fn channel(&self, value: ChatChannel) -> ChatChannelState {
        chat_channel_state_from_model(value, self.base_url)
    }

    pub(crate) fn channel_runtime(
        &self,
        value: fire_core::ChatChannelRuntimeSnapshot,
    ) -> ChatChannelRuntimeState {
        ChatChannelRuntimeState {
            messages: value
                .messages
                .into_iter()
                .map(|message| self.message(message))
                .collect(),
            pins: value
                .pins
                .into_iter()
                .map(|message| self.message(message))
                .collect(),
            can_load_more_past: value.can_load_more_past,
        }
    }

    pub(crate) fn messages(&self, value: ChatMessagesResponse) -> ChatMessagesState {
        ChatMessagesState {
            messages: value
                .messages
                .into_iter()
                .map(|message| self.message(message))
                .collect(),
            can_load_more_past: value.can_load_more_past,
            can_load_more_future: value.can_load_more_future,
            target_message_id: value.target_message_id,
        }
    }

    pub(crate) fn my_channels(&self, value: MyChatChannelsResponse) -> MyChatChannelsState {
        let total_unread_badge = value.total_unread_badge();
        let tracking_entries = value.channel_tracking.clone();
        let tracking_for = |channel_id: u64| {
            tracking_entries
                .iter()
                .find(|entry| entry.channel_id == channel_id)
                .map(|entry| fire_models::ChatChannelTracking {
                    unread_count: entry.unread_count,
                    mention_count: entry.mention_count,
                })
                .unwrap_or_default()
        };
        let map_channel = |channel: ChatChannel| {
            let tracking = tracking_for(channel.id);
            let unread_badge = fire_models::chat_channel_badge(&channel, &tracking);
            let mut state = self.channel(channel);
            state.unread_badge = unread_badge;
            state
        };
        let inbox_channels = value
            .inbox_channels()
            .into_iter()
            .cloned()
            .map(map_channel)
            .collect();
        MyChatChannelsState {
            public_channels: value
                .public_channels
                .into_iter()
                .map(map_channel)
                .collect(),
            direct_message_channels: value
                .direct_message_channels
                .into_iter()
                .map(map_channel)
                .collect(),
            inbox_channels,
            channel_tracking: value.channel_tracking.into_iter().map(Into::into).collect(),
            global_bus_last_ids: value
                .global_bus_last_ids
                .into_iter()
                .map(Into::into)
                .collect(),
            total_unread_badge,
        }
    }

    pub(crate) fn search_result(&self, value: ChatSearchResult) -> ChatSearchResultState {
        ChatSearchResultState {
            messages: value
                .messages
                .into_iter()
                .map(|message| self.message(message))
                .collect(),
            has_more: value.has_more,
        }
    }
}

