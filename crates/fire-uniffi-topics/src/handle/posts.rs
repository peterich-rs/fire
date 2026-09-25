#[uniffi::export]
impl FireTopicsHandle {
    pub async fn fetch_topic_posts(
        &self,
        topic_id: u64,
        post_ids: Vec<u64>,
    ) -> Result<Vec<TopicPostState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_posts", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let posts = inner.fetch_topic_posts(topic_id, post_ids).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, posts))
        })
        .await?;
        Ok(response
            .1
            .into_iter()
            .map(|post| records::topic_post_state_from_model(post, &response.0))
            .collect())
    }

    pub async fn fetch_topic_ai_summary(
        &self,
        topic_id: u64,
        skip_age_check: bool,
    ) -> Result<Option<TopicAiSummaryState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_ai_summary", panic_state, async move {
            inner.fetch_topic_ai_summary(topic_id, skip_age_check).await
        })
        .await?;
        Ok(response.map(Into::into))
    }

    pub async fn create_reply(
        &self,
        input: TopicReplyRequestState,
    ) -> Result<TopicPostState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("create_reply", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let post = inner.create_reply(input.into()).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, post))
        })
        .await?;
        Ok(records::topic_post_state_from_model(
            response.1,
            &response.0,
        ))
    }

    pub async fn create_boost(
        &self,
        post_id: u64,
        raw: String,
    ) -> Result<TopicPostBoostState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("create_boost", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let boost = inner.create_boost(post_id, raw).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, boost))
        })
        .await?;
        Ok(records::topic_post_boost_state_from_model(
            response.1,
            &response.0,
        ))
    }

    pub async fn delete_boost(&self, boost_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("delete_boost", panic_state, async move {
            inner.delete_boost(boost_id).await
        })
        .await
    }

    pub async fn fetch_post(&self, post_id: u64) -> Result<TopicPostState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_post", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let post = inner.fetch_post(post_id).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, post))
        })
        .await?;
        Ok(records::topic_post_state_from_model_with_raw(
            response.1,
            &response.0,
        ))
    }

    pub async fn fetch_post_replies(
        &self,
        post_id: u64,
        after: Option<u32>,
    ) -> Result<Vec<TopicPostState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_post_replies", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let posts = inner.fetch_post_replies(post_id, after).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, posts))
        })
        .await?;
        Ok(response
            .1
            .into_iter()
            .map(|post| records::topic_post_state_from_model(post, &response.0))
            .collect())
    }

    pub async fn fetch_post_reply_ids(&self, post_id: u64) -> Result<Vec<u64>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("fetch_post_reply_ids", panic_state, async move {
            inner.fetch_post_reply_ids(post_id).await
        })
        .await
    }

    pub async fn fetch_post_reply_history(
        &self,
        post_id: u64,
    ) -> Result<Vec<TopicPostState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_post_reply_history", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let posts = inner.fetch_post_reply_history(post_id).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, posts))
        })
        .await?;
        Ok(response
            .1
            .into_iter()
            .map(|post| records::topic_post_state_from_model(post, &response.0))
            .collect())
    }

    pub async fn update_post(
        &self,
        input: PostUpdateRequestState,
    ) -> Result<TopicPostState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("update_post", panic_state, async move {
            let base_url = inner.base_url().to_string();
            let post = inner.update_post(input.into()).await?;
            Ok::<_, fire_core::FireCoreError>((base_url, post))
        })
        .await?;
        Ok(records::topic_post_state_from_model(
            response.1,
            &response.0,
        ))
    }

    pub async fn delete_post(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("delete_post", panic_state, async move {
            inner.delete_post(post_id).await
        })
        .await
    }

    pub async fn recover_post(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("recover_post", panic_state, async move {
            inner.recover_post(post_id).await
        })
        .await
    }

    pub async fn flag_post(&self, input: PostFlagRequestState) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("flag_post", panic_state, async move {
            inner.flag_post(input.into()).await
        })
        .await
    }

    pub async fn fetch_post_action_types(
        &self,
    ) -> Result<Vec<PostActionTypeState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_post_action_types", panic_state, async move {
            inner.fetch_post_action_types().await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }

}
