#[uniffi::export]
impl FireChatHandle {
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

}
