uniffi::setup_scaffolding!("fire_uniffi_chat");

use std::sync::Arc;

use fire_uniffi_types::{run_infallible, run_on_ffi_runtime, FireUniFfiError, SharedFireCore};

pub mod records;

use records::ChatStateMapper;

pub use records::{
    BrowseChatChannelsQueryState, ChatBusEventState, ChatBusLastIdEntryState,
    ChatChannelBusLastIdsState, ChatChannelMemberState, ChatChannelMembershipState,
    ChatChannelState, ChatChannelTrackingEntryState, ChatMessageBookmarkState,
    ChatMessageReactionState, ChatMessageReplyRefState, ChatMessageState, ChatMessagesQueryState,
    ChatMessagesState, ChatReactionActionState, ChatSearchQueryState, ChatSearchResultState,
    ChatThreadRefState, ChatUploadState, ChatUserState, CreateDirectMessageChannelRequestState,
    MyChatChannelsState, SendChatMessageRequestState, SendChatMessageResultState,
};

#[derive(uniffi::Object)]
pub struct FireChatHandle {
    shared: Arc<SharedFireCore>,
}

impl FireChatHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireChatHandle {
    pub async fn fetch_my_chat_channels(&self) -> Result<MyChatChannelsState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_my_chat_channels", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let channels = inner.fetch_my_chat_channels().await?;
            Ok::<_, fire_core::FireCoreError>((base_url, channels))
        })
        .await?;
        Ok(ChatStateMapper::new(&response.0).my_channels(response.1))
    }

    pub fn cached_my_chat_channels(&self) -> Result<Option<MyChatChannelsState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "cached_my_chat_channels",
            |inner| {
                let base_url = inner.base_url().to_string();
                inner
                    .cached_my_chat_channels()
                    .map(|channels| ChatStateMapper::new(&base_url).my_channels(channels))
            },
        )
    }

    pub async fn fetch_chat_channel(
        &self,
        channel_id: u64,
    ) -> Result<ChatChannelState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_chat_channel", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let channel = inner.fetch_chat_channel(channel_id).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, channel))
        })
        .await?;
        Ok(ChatStateMapper::new(&response.0).channel(response.1))
    }

    pub async fn create_direct_message_channel(
        &self,
        request: CreateDirectMessageChannelRequestState,
    ) -> Result<ChatChannelState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response =
            run_on_ffi_runtime("create_direct_message_channel", panic_state, async move {
                let base_url = inner.base_url().to_string();
                let channel = inner.create_direct_message_channel(request.into()).await?;
                Ok::<_, fire_core::FireCoreError>((base_url, channel))
            })
            .await?;
        Ok(ChatStateMapper::new(&response.0).channel(response.1))
    }

    pub async fn fetch_chat_messages(
        &self,
        query: ChatMessagesQueryState,
    ) -> Result<ChatMessagesState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_chat_messages", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let messages = inner.fetch_chat_messages(query.into()).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, messages))
        })
        .await?;
        Ok(ChatStateMapper::new(&response.0).messages(response.1))
    }

    pub fn cached_chat_messages(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
    ) -> Result<Option<ChatMessagesState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "cached_chat_messages",
            move |inner| {
                let base_url = inner.base_url().to_string();
                inner
                    .cached_chat_messages(channel_id, thread_id.unwrap_or(0))
                    .map(|messages| ChatStateMapper::new(&base_url).messages(messages))
            },
        )
    }

    pub async fn send_chat_message(
        &self,
        request: SendChatMessageRequestState,
    ) -> Result<SendChatMessageResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("send_chat_message", panic_state, async move {
            inner.send_chat_message(request.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn mark_chat_channel_read(
        &self,
        channel_id: u64,
        message_id: Option<u64>,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("mark_chat_channel_read", panic_state, async move {
            inner.mark_chat_channel_read(channel_id, message_id).await
        })
        .await
    }

    pub async fn browse_chat_channels(
        &self,
        query: BrowseChatChannelsQueryState,
    ) -> Result<Vec<ChatChannelState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("browse_chat_channels", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let channels = inner.browse_chat_channels(query.into()).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, channels))
        })
        .await?;
        Ok(response
            .1
            .into_iter()
            .map(|channel| ChatStateMapper::new(&response.0).channel(channel))
            .collect())
    }

    pub async fn join_chat_channel(&self, channel_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("join_chat_channel", panic_state, async move {
            inner.join_chat_channel(channel_id).await
        })
        .await
    }

    pub async fn leave_chat_channel(&self, channel_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("leave_chat_channel", panic_state, async move {
            inner.leave_chat_channel(channel_id).await
        })
        .await
    }

    pub async fn star_chat_channel(
        &self,
        channel_id: u64,
        starred: bool,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("star_chat_channel", panic_state, async move {
            inner.star_chat_channel(channel_id, starred).await
        })
        .await
    }

    pub async fn update_chat_channel_notifications(
        &self,
        channel_id: u64,
        muted: Option<bool>,
        notification_level: Option<String>,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime(
            "update_chat_channel_notifications",
            panic_state,
            async move {
                inner
                    .update_chat_channel_notifications(channel_id, muted, notification_level)
                    .await
            },
        )
        .await
    }

    pub async fn edit_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
        message: String,
        upload_ids: Option<Vec<u64>>,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("edit_chat_message", panic_state, async move {
            inner
                .edit_chat_message(channel_id, message_id, message, upload_ids)
                .await
        })
        .await
    }

    pub async fn delete_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("delete_chat_message", panic_state, async move {
            inner.delete_chat_message(channel_id, message_id).await
        })
        .await
    }

    pub async fn react_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
        emoji: String,
        react_action: String,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("react_chat_message", panic_state, async move {
            inner
                .react_chat_message(channel_id, message_id, emoji, react_action)
                .await
        })
        .await
    }

    pub async fn fetch_chat_channel_members(
        &self,
        channel_id: u64,
        offset: Option<u32>,
        limit: Option<u32>,
        username: Option<String>,
    ) -> Result<Vec<ChatChannelMemberState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_chat_channel_members", panic_state, async move {
            inner
                .fetch_chat_channel_members(channel_id, offset, limit, username)
                .await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }

    pub async fn search_chat_messages(
        &self,
        query: ChatSearchQueryState,
    ) -> Result<ChatSearchResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("search_chat_messages", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let result = inner.search_chat_messages(query.into()).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, result))
        })
        .await?;
        Ok(ChatStateMapper::new(&response.0).search_result(response.1))
    }

    pub async fn fetch_chat_channel_pins(
        &self,
        channel_id: u64,
    ) -> Result<Vec<ChatMessageState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_chat_channel_pins", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let messages = inner.fetch_chat_channel_pins(channel_id).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, messages))
        })
        .await?;
        Ok(response
            .1
            .into_iter()
            .map(|message| ChatStateMapper::new(&response.0).message(message))
            .collect())
    }

    pub async fn pin_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("pin_chat_message", panic_state, async move {
            inner.pin_chat_message(channel_id, message_id).await
        })
        .await
    }

    pub async fn unpin_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("unpin_chat_message", panic_state, async move {
            inner.unpin_chat_message(channel_id, message_id).await
        })
        .await
    }

    pub async fn mark_chat_channel_pins_read(
        &self,
        channel_id: u64,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("mark_chat_channel_pins_read", panic_state, async move {
            inner.mark_chat_channel_pins_read(channel_id).await
        })
        .await
    }

    pub async fn create_chat_thread(
        &self,
        channel_id: u64,
        original_message_id: u64,
    ) -> Result<u64, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("create_chat_thread", panic_state, async move {
            inner
                .create_chat_thread(channel_id, original_message_id)
                .await
        })
        .await
    }

    pub async fn fetch_chat_thread_messages(
        &self,
        channel_id: u64,
        thread_id: u64,
        query: ChatMessagesQueryState,
    ) -> Result<ChatMessagesState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_chat_thread_messages", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let messages = inner
                .fetch_chat_thread_messages(channel_id, thread_id, query.into())
                .await?;
            Ok::<_, fire_core::FireCoreError>((base_url, messages))
        })
        .await?;
        Ok(ChatStateMapper::new(&response.0).messages(response.1))
    }

    pub async fn mark_chat_thread_read(
        &self,
        channel_id: u64,
        thread_id: u64,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("mark_chat_thread_read", panic_state, async move {
            inner.mark_chat_thread_read(channel_id, thread_id).await
        })
        .await
    }
}

/// Lift a live chat MessageBus payload into a UI-ready message.
///
/// Hosts must not parse cooked HTML or synthesize presentation themselves.
/// Missing or malformed payloads are absence, not an error.
#[uniffi::export]
pub fn chat_message_from_bus_payload(
    payload_json: String,
    fallback_channel_id: Option<u64>,
    base_url: String,
) -> Option<ChatMessageState> {
    fire_core::chat_message_from_bus_payload(&payload_json, fallback_channel_id, &base_url)
        .map(|message| ChatStateMapper::new(&base_url).message(message))
}

/// Lift a live chat MessageBus payload into a UI-ready channel.
#[uniffi::export]
pub fn chat_channel_from_bus_payload(
    payload_json: String,
    base_url: String,
) -> Option<ChatChannelState> {
    fire_core::chat_channel_from_bus_payload(&payload_json, &base_url)
        .map(|channel| ChatStateMapper::new(&base_url).channel(channel))
}

#[uniffi::export]
pub fn chat_bus_event_from_payload(
    payload_json: String,
    event_type: Option<String>,
    fallback_channel_id: Option<u64>,
    base_url: String,
) -> ChatBusEventState {
    ChatStateMapper::new(&base_url).bus_event(fire_core::chat_bus_event_from_payload(
        &payload_json,
        event_type.as_deref(),
        fallback_channel_id,
        &base_url,
    ))
}

#[cfg(test)]
mod tests {
    use super::{chat_channel_from_bus_payload, chat_message_from_bus_payload};

    #[test]
    fn bus_message_payload_carries_presentation() {
        let message = chat_message_from_bus_payload(
            r#"{"chat_message":{"id":7,"chat_channel_id":3,"message":"hi","cooked":"<p>hi</p>","user":{"id":2,"username":"alice"}}}"#
                .to_string(),
            Some(3),
            "https://linux.do".to_string(),
        )
        .expect("message");
        assert_eq!(message.id, 7);
        assert_eq!(message.channel_id, 3);
        let presentation = message.presentation.expect("presentation");
        assert!(presentation.plain_text().contains("hi"));
        assert!(presentation.segment_count() > 0);
    }

    #[test]
    fn bus_channel_payload_presents_last_message() {
        let channel = chat_channel_from_bus_payload(
            r#"{"channel":{"id":20,"title":"@alice","chatable_type":"DirectMessage","last_message":{"id":5,"message":"hello","cooked":"<p>hello</p>"}}}"#
                .to_string(),
            "https://linux.do".to_string(),
        )
        .expect("channel");
        assert!(channel.is_direct_message);
        let last_message = channel.last_message.expect("last message");
        assert_eq!(last_message.id, 5);
        assert!(last_message.presentation.is_some());
    }
}
