uniffi::setup_scaffolding!("fire_uniffi_topics");

use std::sync::Arc;

use fire_uniffi_types::{run_on_ffi_runtime, FireUniFfiError, SharedFireCore, TopicListState};

pub mod records;

pub use records::{
    PollOptionState, PollState, PostReactionUpdateState, PostUpdateRequestState,
    PrivateMessageCreateRequestState, ResolvedUploadUrlState, TopicCreateRequestState,
    TopicDetailCreatedByState, TopicDetailMetaState, TopicDetailQueryState, TopicDetailState,
    TopicListQueryState, TopicPostState, TopicPostStreamState, TopicReactionState,
    TopicReplyRequestState, TopicTimelineEntryState, TopicTimingEntryState, TopicTimingsRequestState,
    TopicUpdateRequestState, UploadImageRequestState, UploadResultState, VoteResponseState,
    VotedUserState,
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

#[uniffi::export]
pub fn rebuild_timeline_entries(posts: Vec<TopicPostState>) -> Vec<TopicTimelineEntryState> {
    if posts.is_empty() {
        return vec![];
    }

    let min_pn = posts.iter().map(|p| p.post_number).min().unwrap_or(0);

    let mut post_map = std::collections::HashMap::new();
    for post in &posts {
        post_map.insert(post.post_number, post.clone());
    }

    let mut children_map: std::collections::HashMap<u32, Vec<TopicPostState>> = std::collections::HashMap::new();
    let mut roots = Vec::new();

    let mut sorted_posts = posts.clone();
    sorted_posts.sort_by(|a, b| {
        if a.post_number != b.post_number {
            a.post_number.cmp(&b.post_number)
        } else {
            a.id.cmp(&b.id)
        }
    });

    for post in sorted_posts.iter() {
        let parent = post.reply_to_post_number;
        if let Some(p) = parent {
            if p != post.post_number && post_map.contains_key(&p) {
                children_map.entry(p).or_default().push(post.clone());
                continue;
            }
        }
        roots.push(post.clone());
    }

    let mut result = Vec::new();
    let mut visited = std::collections::HashSet::new();

    fn dfs(
        post: &TopicPostState,
        depth: u32,
        min_pn: u32,
        children_map: &std::collections::HashMap<u32, Vec<TopicPostState>>,
        post_map: &std::collections::HashMap<u32, TopicPostState>,
        visited: &mut std::collections::HashSet<u32>,
        result: &mut Vec<TopicTimelineEntryState>,
    ) {
        if visited.contains(&post.post_number) {
            return;
        }
        visited.insert(post.post_number);

        let parent = post.reply_to_post_number;

        let parent_post_number = if depth == 0 {
            None
        } else {
            parent.filter(|&p| post_map.contains_key(&p))
        };

        result.push(TopicTimelineEntryState {
            post_id: post.id,
            post_number: post.post_number,
            parent_post_number,
            depth,
            is_original_post: post.post_number == min_pn,
        });

        if let Some(children) = children_map.get(&post.post_number) {
            for child in children {
                dfs(child, depth + 1, min_pn, children_map, post_map, visited, result);
            }
        }
    }

    for root in roots {
        dfs(&root, 0, min_pn, &children_map, &post_map, &mut visited, &mut result);
    }

    for post in sorted_posts.iter() {
        if !visited.contains(&post.post_number) {
            dfs(post, 0, min_pn, &children_map, &post_map, &mut visited, &mut result);
        }
    }

    result
}
