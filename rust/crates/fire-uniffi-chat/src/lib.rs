uniffi::setup_scaffolding!("fire_uniffi_chat");

use std::sync::Arc;

use fire_uniffi_types::{run_on_ffi_runtime, FireUniFfiError, SharedFireCore};

pub mod records;

pub use records::{
    BrowseChatChannelsQueryState, ChatBusLastIdEntryState, ChatChannelBusLastIdsState,
    ChatChannelMemberState, ChatChannelMembershipState, ChatChannelState,
    ChatChannelTrackingEntryState, ChatMessageBookmarkState, ChatMessageReactionState,
    ChatMessageReplyRefState, ChatMessageState, ChatMessagesQueryState, ChatMessagesState,
    ChatSearchQueryState, ChatSearchResultState, ChatThreadRefState, ChatUploadState,
    ChatUserState, CreateDirectMessageChannelRequestState, MyChatChannelsState,
    SendChatMessageRequestState, SendChatMessageResultState,
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
            inner.fetch_my_chat_channels().await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_chat_channel(
        &self,
        channel_id: u64,
    ) -> Result<ChatChannelState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_chat_channel", panic_state, async move {
            inner.fetch_chat_channel(channel_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn create_direct_message_channel(
        &self,
        request: CreateDirectMessageChannelRequestState,
    ) -> Result<ChatChannelState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response =
            run_on_ffi_runtime("create_direct_message_channel", panic_state, async move {
                inner.create_direct_message_channel(request.into()).await
            })
            .await?;
        Ok(response.into())
    }

    pub async fn fetch_chat_messages(
        &self,
        query: ChatMessagesQueryState,
    ) -> Result<ChatMessagesState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_chat_messages", panic_state, async move {
            inner.fetch_chat_messages(query.into()).await
        })
        .await?;
        Ok(response.into())
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
            inner.browse_chat_channels(query.into()).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
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
            inner.search_chat_messages(query.into()).await
        })
        .await?;
        Ok(response.into())
    }
}
