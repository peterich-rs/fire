uniffi::setup_scaffolding!("fire_uniffi_topics");

use std::sync::Arc;

use fire_uniffi_types::{run_on_ffi_runtime, FireUniFfiError, SharedFireCore, TopicListState};

pub mod records;

pub use records::{
    PollOptionState, PollState, PostActionTypeState, PostFlagRequestState, PostReactionUpdateState,
    PostUpdateRequestState, PrivateMessageCreateRequestState, ReactionUserState,
    ReactionUsersGroupState, ResolvedUploadUrlState, TopicAiSummaryState, TopicBodyState,
    TopicCreateRequestState, TopicDetailCreatedByState, TopicDetailMetaState,
    TopicDetailQueryState, TopicDetailState, TopicHeaderState, TopicListQueryState, TopicPostState,
    TopicPostStreamState, TopicReactionState, TopicReplyRequestState, TopicReplyToUserState,
    TopicResponseCursorState, TopicResponsePageQueryState, TopicResponsePageState,
    TopicResponseRowState, TopicScreenQueryState, TopicScreenState, TopicTimingEntryState,
    TopicTimingsRequestState, TopicUpdateRequestState, UploadImageRequestState, UploadResultState,
    VoteResponseState, VotedUserState,
};

#[derive(uniffi::Object)]
pub struct FireTopicsHandle {
    shared: Arc<SharedFireCore>,
}

impl FireTopicsHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

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
        Ok(response.into())
    }

    pub async fn fetch_topic_detail(
        &self,
        query: TopicDetailQueryState,
    ) -> Result<TopicDetailState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_detail", panic_state, async move {
            inner.fetch_topic_detail(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_detail_initial(
        &self,
        query: TopicDetailQueryState,
    ) -> Result<TopicDetailState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_detail_initial", panic_state, async move {
            inner.fetch_topic_detail_initial(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_screen(
        &self,
        query: TopicScreenQueryState,
    ) -> Result<TopicScreenState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_screen", panic_state, async move {
            inner.fetch_topic_screen(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_response_page(
        &self,
        query: TopicResponsePageQueryState,
    ) -> Result<TopicResponsePageState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_response_page", panic_state, async move {
            inner.fetch_topic_response_page(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_posts(
        &self,
        topic_id: u64,
        post_ids: Vec<u64>,
    ) -> Result<Vec<TopicPostState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_posts", panic_state, async move {
            inner.fetch_topic_posts(topic_id, post_ids).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
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
            inner.create_reply(input.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_post(&self, post_id: u64) -> Result<TopicPostState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_post", panic_state, async move {
            inner.fetch_post(post_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_post_replies(
        &self,
        post_id: u64,
        after: Option<u32>,
    ) -> Result<Vec<TopicPostState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_post_replies", panic_state, async move {
            inner.fetch_post_replies(post_id, after).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
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
            inner.fetch_post_reply_history(post_id).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }

    pub async fn update_post(
        &self,
        input: PostUpdateRequestState,
    ) -> Result<TopicPostState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("update_post", panic_state, async move {
            inner.update_post(input.into()).await
        })
        .await?;
        Ok(response.into())
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

    pub async fn create_topic(
        &self,
        input: TopicCreateRequestState,
    ) -> Result<u64, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("create_topic", panic_state, async move {
            inner.create_topic(input.into()).await
        })
        .await
    }

    pub async fn create_private_message(
        &self,
        input: PrivateMessageCreateRequestState,
    ) -> Result<u64, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("create_private_message", panic_state, async move {
            inner.create_private_message(input.into()).await
        })
        .await
    }

    pub async fn update_topic(
        &self,
        input: TopicUpdateRequestState,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("update_topic", panic_state, async move {
            inner.update_topic(input.into()).await
        })
        .await
    }

    pub async fn upload_image(
        &self,
        input: UploadImageRequestState,
    ) -> Result<UploadResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("upload_image", panic_state, async move {
            inner
                .upload_image(&input.file_name, input.mime_type.as_deref(), input.bytes)
                .await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn lookup_upload_urls(
        &self,
        short_urls: Vec<String>,
    ) -> Result<Vec<ResolvedUploadUrlState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("lookup_upload_urls", panic_state, async move {
            inner.lookup_upload_urls(short_urls).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }

    pub async fn report_topic_timings(
        &self,
        input: TopicTimingsRequestState,
    ) -> Result<bool, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let accepted = run_on_ffi_runtime("report_topic_timings", panic_state, async move {
            inner.report_topic_timings(input.into()).await
        })
        .await?;
        Ok(accepted)
    }

    pub async fn like_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdateState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("like_post", panic_state, async move {
            inner.like_post(post_id).await
        })
        .await?;
        Ok(response.map(Into::into))
    }

    pub async fn unlike_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdateState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("unlike_post", panic_state, async move {
            inner.unlike_post(post_id).await
        })
        .await?;
        Ok(response.map(Into::into))
    }

    pub async fn toggle_post_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<PostReactionUpdateState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("toggle_post_reaction", panic_state, async move {
            inner.toggle_post_reaction(post_id, reaction_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_reaction_users(
        &self,
        post_id: u64,
    ) -> Result<Vec<ReactionUsersGroupState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let groups = run_on_ffi_runtime("fetch_reaction_users", panic_state, async move {
            inner.fetch_reaction_users(post_id).await
        })
        .await?;
        Ok(groups.into_iter().map(Into::into).collect())
    }

    pub async fn accept_solution(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("accept_solution", panic_state, async move {
            inner.accept_solution(post_id).await
        })
        .await
    }

    pub async fn unaccept_solution(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("unaccept_solution", panic_state, async move {
            inner.unaccept_solution(post_id).await
        })
        .await
    }

    pub async fn vote_poll(
        &self,
        post_id: u64,
        poll_name: String,
        options: Vec<String>,
    ) -> Result<PollState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("vote_poll", panic_state, async move {
            inner.vote_poll(post_id, &poll_name, options).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn unvote_poll(
        &self,
        post_id: u64,
        poll_name: String,
    ) -> Result<PollState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("unvote_poll", panic_state, async move {
            inner.unvote_poll(post_id, &poll_name).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn vote_topic(&self, topic_id: u64) -> Result<VoteResponseState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("vote_topic", panic_state, async move {
            inner.vote_topic(topic_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn unvote_topic(&self, topic_id: u64) -> Result<VoteResponseState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("unvote_topic", panic_state, async move {
            inner.unvote_topic(topic_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_voters(
        &self,
        topic_id: u64,
    ) -> Result<Vec<VotedUserState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_topic_voters", panic_state, async move {
            inner.fetch_topic_voters(topic_id).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }
}
