#[uniffi::export]
impl FireTopicsHandle {
    pub async fn fetch_topic_list(
        &self,
        query: TopicListQueryState,
    ) -> Result<TopicListState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_list", panic_state, async move {
            inner.fetch_topic_list(query.into()).await
        })
        .await?;
        // Hosts apply direct topic-list fetch results themselves. Broadcasting
        // every page through the global observer causes home feeds to treat
        // paginated slices as authoritative full-list snapshots.
        Ok(response.into())
    }

}
