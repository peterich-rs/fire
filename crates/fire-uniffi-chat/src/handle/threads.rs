#[uniffi::export]
impl FireChatHandle {
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
