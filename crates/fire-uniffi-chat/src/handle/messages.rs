#[uniffi::export]
impl FireChatHandle {
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

}
