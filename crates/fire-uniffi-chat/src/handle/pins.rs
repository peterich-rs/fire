#[uniffi::export]
impl FireChatHandle {
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

}
