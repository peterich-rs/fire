use std::collections::HashSet;

use fire_models::{
    TopicAiSummary, TopicDetail, TopicDetailQuery, TopicDetailSourceSnapshot, TopicPost,
    TopicThread,
};
use http::StatusCode;
use serde_json::Value;
use tracing::{info, warn};

use super::super::super::{network::expect_success, FireCore};
use super::super::posts::{
    merge_topic_posts, missing_topic_post_ids, ordered_unique_post_ids,
    topic_posts_for_requested_ids,
};
use super::*;
use crate::{
    error::FireCoreError,
    json_helpers::invalid_json,
    topic_payloads::{parse_topic_ai_summary_value, parse_topic_post_stream_value},
};
impl FireCore {
    pub async fn fetch_topic_posts(
        &self,
        topic_id: u64,
        post_ids: Vec<u64>,
    ) -> Result<Vec<TopicPost>, FireCoreError> {
        let requested_post_ids = ordered_unique_post_ids(post_ids);
        if requested_post_ids.is_empty() {
            return Ok(Vec::new());
        }

        let cached_posts =
            self.cached_topic_posts_for_active_source_session(topic_id, &requested_post_ids);
        let cached_post_ids = cached_posts
            .iter()
            .map(|post| post.id)
            .collect::<HashSet<_>>();
        let missing_post_ids = requested_post_ids
            .iter()
            .copied()
            .filter(|post_id| !cached_post_ids.contains(post_id))
            .collect::<Vec<_>>();
        if missing_post_ids.is_empty() {
            return Ok(topic_posts_for_requested_ids(
                &requested_post_ids,
                cached_posts,
                Vec::new(),
            ));
        }

        let path = format!("/t/{topic_id}/posts.json");
        let params = missing_post_ids
            .iter()
            .copied()
            .map(|post_id| ("post_ids[]", post_id.to_string()))
            .chain(std::iter::once(("include_suggested", "false".to_string())))
            .collect::<Vec<_>>();
        let traced = self.build_json_get_request("fetch topic posts", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch topic posts", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch topic posts", trace_id, response)
            .await?;
        let post_stream =
            parse_topic_post_stream_value(value, self.base_url()).map_err(|source| {
                FireCoreError::ResponseDeserialize {
                    operation: "fetch topic posts",
                    source,
                }
            })?;
        let fetched_posts = post_stream.posts;
        self.cache_topic_posts_for_active_source_session(topic_id, &fetched_posts);
        if cached_posts.is_empty() {
            return Ok(fetched_posts);
        }
        Ok(topic_posts_for_requested_ids(
            &requested_post_ids,
            cached_posts,
            fetched_posts,
        ))
    }

    pub(super) fn cached_topic_posts_for_active_source_session(
        &self,
        topic_id: u64,
        post_ids: &[u64],
    ) -> Vec<TopicPost> {
        let current_epoch = self.current_session_epoch();
        let runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
            return Vec::new();
        };
        if session.session_epoch != current_epoch {
            return Vec::new();
        }
        session.posts_for_ids(post_ids)
    }

    pub(super) fn cache_topic_posts_for_active_source_session(
        &self,
        topic_id: u64,
        posts: &[TopicPost],
    ) {
        if posts.is_empty() {
            return;
        }
        let current_epoch = self.current_session_epoch();
        let mut runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get_mut(&topic_id) else {
            return;
        };
        if session.session_epoch != current_epoch {
            return;
        }
        session.merge_posts(posts.iter().cloned());
    }

    pub(crate) fn topic_source_contains_target(
        &self,
        topic_id: u64,
        target_post_number: Option<u32>,
    ) -> bool {
        let current_epoch = self.current_session_epoch();
        let runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
            return false;
        };
        if session.session_epoch != current_epoch {
            return false;
        }
        match target_post_number {
            Some(post_number) => session.contains_post_number(post_number),
            None => true,
        }
    }

    pub(crate) fn clone_topic_source_snapshot(
        &self,
        topic_id: u64,
    ) -> Option<TopicDetailSourceSnapshot> {
        let current_epoch = self.current_session_epoch();
        let runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let session = runtime.sessions_by_topic_id.get(&topic_id)?;
        (session.session_epoch == current_epoch).then(|| session.source_snapshot())
    }

    pub(crate) fn with_topic_source_session_mut<R>(
        &self,
        topic_id: u64,
        session_id: Option<u64>,
        mutate: impl FnOnce(&mut TopicDetailSourceSession) -> R,
    ) -> Option<R> {
        let current_epoch = self.current_session_epoch();
        let mut runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let session = runtime.sessions_by_topic_id.get_mut(&topic_id)?;
        if session.session_epoch != current_epoch {
            return None;
        }
        if let Some(session_id) = session_id {
            if session.session_id != session_id {
                return None;
            }
        }
        Some(mutate(session))
    }

    #[cfg(test)]
    pub(crate) fn seed_topic_detail_source_for_test(
        &self,
        header: TopicHeader,
        body_post: TopicPost,
        posts: Vec<TopicPost>,
        raw_stream_ids: Vec<u64>,
    ) -> u64 {
        let session = TopicDetailSourceSession::new(TopicDetailSourceSessionInit {
            session_epoch: self.current_session_epoch(),
            header,
            body_post,
            focused_post_number: None,
            raw_stream_ids,
            cached_posts: posts,
            unavailable_post_ids: HashSet::new(),
            load_more_policy: TopicLoadMorePolicy {
                batch_size: DEFAULT_TOPIC_LOAD_MORE_BATCH_SIZE,
                max_auto_batches_per_gesture: DEFAULT_TOPIC_MAX_AUTO_BATCHES_PER_GESTURE,
                max_auto_posts_per_gesture: DEFAULT_TOPIC_MAX_AUTO_POSTS_PER_GESTURE,
                require_new_root_progress: true,
            },
        });
        let mut runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let next_session_id = runtime.next_session_id.saturating_add(1).max(1);
        runtime.next_session_id = next_session_id;
        let topic_id = session.header.topic_id;
        runtime
            .sessions_by_topic_id
            .insert(topic_id, session.with_session_id(next_session_id));
        next_session_id
    }

    /// Resolve the topic body/OP used as tree root.
    ///
    /// Prefer payloads already in the detail chunk, then stream-head via
    /// `post_ids[]`, then number-based / root-detail fallbacks.
    pub(super) async fn resolve_topic_body_post(
        &self,
        topic_id: u64,
        detail: &TopicDetail,
    ) -> Result<TopicPost, FireCoreError> {
        if let Some(post) = detail
            .post_stream
            .posts
            .iter()
            .find(|post| post.post_number == 1)
            .cloned()
        {
            return Ok(post);
        }

        if let Some(first_id) = detail
            .post_stream
            .stream
            .first()
            .copied()
            .filter(|post_id| *post_id > 0)
        {
            let posts = self.fetch_topic_posts(topic_id, vec![first_id]).await?;
            if let Some(post) = posts.into_iter().find(|post| post.id == first_id) {
                return Ok(post);
            }
        }

        if let Ok(post) = self
            .resolve_topic_post_by_number(topic_id, 1, &detail.post_stream.stream)
            .await
        {
            return Ok(post);
        }

        // Last resort: unanchored topic detail always starts near the beginning.
        let root = self
            .fetch_topic_detail_base(
                TopicDetailQuery {
                    topic_id,
                    post_number: None,
                    track_visit: false,
                    force_load: true,
                    filter: None,
                    username_filters: None,
                    filter_top_level_replies: false,
                },
                false,
            )
            .await?;
        if let Some(post) = root
            .post_stream
            .posts
            .iter()
            .find(|post| post.post_number == 1)
            .cloned()
        {
            return Ok(post);
        }
        root.post_stream
            .posts
            .into_iter()
            .min_by_key(|post| post.post_number)
            .ok_or_else(|| FireCoreError::ResponseDeserialize {
                operation: "resolve topic body post",
                source: invalid_json(
                    "topic detail did not include a body/original post payload".to_string(),
                ),
            })
    }

    pub(super) async fn resolve_topic_post_by_number(
        &self,
        topic_id: u64,
        post_number: u32,
        stream_ids: &[u64],
    ) -> Result<TopicPost, FireCoreError> {
        // 1) Number-window posts.json (fast path when Discourse returns the floor).
        if let Ok(post) = self.fetch_post_by_number(topic_id, post_number).await {
            return Ok(post);
        }

        // 2) Anchored topic detail around the floor — more reliable than posts.json
        // for some large/complex topics where the number window omits the exact post.
        let anchored = self
            .fetch_topic_detail_base(
                TopicDetailQuery {
                    topic_id,
                    post_number: Some(post_number),
                    track_visit: false,
                    force_load: true,
                    filter: None,
                    username_filters: None,
                    filter_top_level_replies: false,
                },
                false,
            )
            .await?;
        if let Some(post) = anchored
            .post_stream
            .posts
            .into_iter()
            .find(|post| post.post_number == post_number)
        {
            return Ok(post);
        }

        // 3) If stream is known and dense enough that index ~= post_number-1, try id.
        // This is best-effort only (deleted posts create gaps).
        if post_number > 0 {
            let index = usize::try_from(post_number.saturating_sub(1)).unwrap_or(usize::MAX);
            if let Some(post_id) = stream_ids.get(index).copied().filter(|id| *id > 0) {
                let posts = self.fetch_topic_posts(topic_id, vec![post_id]).await?;
                if let Some(post) = posts
                    .into_iter()
                    .find(|post| post.id == post_id || post.post_number == post_number)
                {
                    return Ok(post);
                }
            }
        }

        Err(FireCoreError::ResponseDeserialize {
            operation: "resolve topic post by number",
            source: invalid_json(format!(
                "topic post stream did not contain post number {post_number}"
            )),
        })
    }

    pub(super) async fn fetch_post_by_number(
        &self,
        topic_id: u64,
        post_number: u32,
    ) -> Result<TopicPost, FireCoreError> {
        let path = format!("/t/{topic_id}/posts.json");
        let params = vec![
            ("post_number", post_number.to_string()),
            ("asc", "true".to_string()),
            ("include_suggested", "false".to_string()),
        ];
        let traced = self.build_json_get_request("fetch post by number", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch post by number", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch post by number", trace_id, response)
            .await?;
        let post_stream =
            parse_topic_post_stream_value(value, self.base_url()).map_err(|source| {
                FireCoreError::ResponseDeserialize {
                    operation: "fetch post by number",
                    source,
                }
            })?;
        post_stream
            .posts
            .into_iter()
            .find(|post| post.post_number == post_number)
            .ok_or_else(|| FireCoreError::ResponseDeserialize {
                operation: "fetch post by number",
                source: invalid_json(format!(
                    "topic post stream did not contain post number {post_number}"
                )),
            })
    }

    pub async fn fetch_topic_ai_summary(
        &self,
        topic_id: u64,
        skip_age_check: bool,
    ) -> Result<Option<TopicAiSummary>, FireCoreError> {
        info!(topic_id, skip_age_check, "fetching topic AI summary");

        let path = format!("/discourse-ai/summarization/t/{topic_id}");
        let mut params = Vec::new();
        if skip_age_check {
            params.push(("skip_age_check", "true".to_string()));
        }

        let traced =
            self.build_json_get_request(FETCH_TOPIC_AI_SUMMARY_OPERATION, &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = match expect_success(
            self,
            FETCH_TOPIC_AI_SUMMARY_OPERATION,
            trace_id,
            response,
        )
        .await
        {
            Ok(response) => response,
            Err(FireCoreError::HttpStatus {
                status,
                body: _,
                operation: FETCH_TOPIC_AI_SUMMARY_OPERATION,
            }) if status == StatusCode::NOT_FOUND.as_u16()
                || status == StatusCode::FORBIDDEN.as_u16() =>
            {
                info!(topic_id, status, "topic AI summary is unavailable");
                return Ok(None);
            }
            Err(error) => return Err(error),
        };
        let value: Value = self
            .read_response_json(FETCH_TOPIC_AI_SUMMARY_OPERATION, trace_id, response)
            .await?;
        let summary = parse_topic_ai_summary_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: FETCH_TOPIC_AI_SUMMARY_OPERATION,
                source,
            }
        })?;
        info!(
            topic_id,
            has_summary = summary.is_some(),
            "topic AI summary fetched successfully"
        );
        Ok(summary)
    }

    pub(super) async fn hydrate_topic_detail_posts(
        &self,
        topic_id: u64,
        detail: &mut TopicDetail,
    ) -> Result<(), FireCoreError> {
        let missing_post_ids = missing_topic_post_ids(&detail.post_stream);
        if missing_post_ids.is_empty() {
            return Ok(());
        }

        info!(
            topic_id,
            loaded_posts = detail.post_stream.posts.len(),
            total_posts = detail.post_stream.stream.len(),
            missing_posts = missing_post_ids.len(),
            "hydrating missing topic posts"
        );

        let mut fetched_posts = Vec::with_capacity(missing_post_ids.len());
        for post_ids in missing_post_ids.chunks(TOPIC_POST_BATCH_SIZE) {
            fetched_posts.extend(self.fetch_topic_posts(topic_id, post_ids.to_vec()).await?);
        }

        if fetched_posts.is_empty() {
            return Ok(());
        }

        detail.post_stream.posts = merge_topic_posts(
            &detail.post_stream.stream,
            std::mem::take(&mut detail.post_stream.posts),
            fetched_posts,
        );
        detail.thread = TopicThread::from_posts(&detail.post_stream.posts);
        detail.flat_posts = detail.thread.flatten(&detail.post_stream.posts);
        detail.rebuild_timeline_entries();

        let remaining_missing = missing_topic_post_ids(&detail.post_stream);
        if !remaining_missing.is_empty() {
            warn!(
                topic_id,
                missing_posts = remaining_missing.len(),
                loaded_posts = detail.post_stream.posts.len(),
                total_posts = detail.post_stream.stream.len(),
                "topic detail hydration completed with unresolved missing posts"
            );
        }

        Ok(())
    }
}
