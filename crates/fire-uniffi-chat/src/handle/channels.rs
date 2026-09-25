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

}
