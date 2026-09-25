use std::collections::HashSet;

use fire_models::{
    TopicDetail, TopicDetailQuery, TopicDetailSourceQuery, TopicDetailSourceSnapshot,
};
use tracing::{info, warn};

use super::super::super::super::{network::expect_success, FireCore};
use super::super::super::posts::{merge_topic_posts, missing_post_ids_from_ids};
use super::super::{
    ensure_requested_topic_detail, normalized_topic_auto_batch_limit,
    normalized_topic_auto_post_limit, normalized_topic_initial_batch_size,
    normalized_topic_load_more_batch_size, TopicDetailSourceSession, TopicDetailSourceSessionInit,
    TopicLoadMorePolicy,
};
use super::load_topic_detail_source_snapshot;
use crate::{error::FireCoreError, topic_payloads::RawTopicDetail};

impl FireCore {
    pub async fn fetch_topic_detail_initial(
        &self,
        query: TopicDetailQuery,
    ) -> Result<TopicDetail, FireCoreError> {
        let mut result = self.fetch_topic_detail_base(query, true).await?;
        result.rebuild_timeline_entries();
        info!(
            topic_id = result.id,
            posts_count = result.posts_count,
            post_stream_total = result.post_stream.stream.len(),
            post_stream_len = result.post_stream.posts.len(),
            timeline_entries = result.timeline_entries.len(),
            "topic detail initial payload fetched successfully"
        );
        Ok(result)
    }

    pub async fn fetch_topic_detail(
        &self,
        query: TopicDetailQuery,
    ) -> Result<TopicDetail, FireCoreError> {
        let mut result = self.fetch_topic_detail_base(query, true).await?;
        if let Err(error) = self
            .hydrate_topic_detail_posts(result.id, &mut result)
            .await
        {
            warn!(
                topic_id = result.id,
                error = %error,
                "topic detail hydration fell back to partially loaded posts"
            );
            // Hydration builds timeline entries on success; build from partial data on failure.
            result.rebuild_timeline_entries();
        }
        info!(
            topic_id = result.id,
            posts_count = result.posts_count,
            post_stream_total = result.post_stream.stream.len(),
            post_stream_len = result.post_stream.posts.len(),
            timeline_entries = result.timeline_entries.len(),
            "topic detail fetched successfully"
        );
        Ok(result)
    }

    pub async fn fetch_topic_detail_source_snapshot(
        &self,
        query: TopicDetailSourceQuery,
    ) -> Result<TopicDetailSourceSnapshot, FireCoreError> {
        load_topic_detail_source_snapshot(self, query).await
    }

    pub(crate) async fn load_topic_detail_source_snapshot_impl(
        &self,
        query: TopicDetailSourceQuery,
    ) -> Result<TopicDetailSourceSnapshot, FireCoreError> {
        let focused_post_number = query
            .target_post_number
            .filter(|post_number| *post_number > 1);
        let initial_batch_size = normalized_topic_initial_batch_size(query.initial_batch_size);
        let load_more_policy = TopicLoadMorePolicy {
            batch_size: normalized_topic_load_more_batch_size(query.load_more_batch_size),
            max_auto_batches_per_gesture: normalized_topic_auto_batch_limit(
                query.max_auto_batches_per_gesture,
            ),
            max_auto_posts_per_gesture: normalized_topic_auto_post_limit(
                query.max_auto_posts_per_gesture,
            ),
            require_new_root_progress: true,
        };

        let mut detail = self
            .fetch_topic_detail_base(
                TopicDetailQuery {
                    topic_id: query.topic_id,
                    post_number: focused_post_number,
                    track_visit: query.track_visit,
                    force_load: query.force_load,
                    filter: None,
                    username_filters: None,
                    filter_top_level_replies: false,
                },
                false,
            )
            .await?;

        // Mid-topic opens (`/t/{id}/{N}.json` from notifications) only embed a
        // nearby posts chunk. OP/body is often absent from that chunk on large
        // topics. Resolve body via stream head + post_ids[] first — never hard
        // fail solely on posts.json?post_number=1 missing the OP payload.
        let body_post = self
            .resolve_topic_body_post(query.topic_id, &detail)
            .await?;
        if detail.post_stream.stream.is_empty() && body_post.id > 0 {
            detail.post_stream.stream.push(body_post.id);
        }

        if let Some(target_post_number) = focused_post_number.filter(|post_number| {
            !detail
                .post_stream
                .posts
                .iter()
                .any(|post| post.post_number == *post_number)
        }) {
            detail.post_stream.posts.push(
                self.resolve_topic_post_by_number(
                    query.topic_id,
                    target_post_number,
                    &detail.post_stream.stream,
                )
                .await?,
            );
        }
        if !detail
            .post_stream
            .posts
            .iter()
            .any(|post| post.id == body_post.id)
        {
            detail.post_stream.posts.push(body_post.clone());
        }

        let initial_source_post_ids = detail
            .post_stream
            .stream
            .iter()
            .copied()
            .take(usize::from(initial_batch_size))
            .collect::<Vec<_>>();
        let missing_initial_post_ids =
            missing_post_ids_from_ids(&initial_source_post_ids, &detail.post_stream.posts);
        let fetched_initial_posts = if missing_initial_post_ids.is_empty() {
            Vec::new()
        } else {
            self.fetch_topic_posts(query.topic_id, missing_initial_post_ids.clone())
                .await?
        };
        let fetched_initial_post_ids = fetched_initial_posts
            .iter()
            .map(|post| post.id)
            .collect::<HashSet<_>>();
        let initial_unavailable_post_ids = missing_initial_post_ids
            .into_iter()
            .filter(|post_id| !fetched_initial_post_ids.contains(post_id))
            .collect::<HashSet<_>>();
        detail.post_stream.posts = merge_topic_posts(
            &detail.post_stream.stream,
            std::mem::take(&mut detail.post_stream.posts),
            fetched_initial_posts,
        );

        let header = detail.header();
        let session = TopicDetailSourceSession::new(TopicDetailSourceSessionInit {
            session_epoch: self.current_session_epoch(),
            header,
            body_post,
            focused_post_number,
            raw_stream_ids: detail.post_stream.stream,
            cached_posts: detail.post_stream.posts,
            unavailable_post_ids: initial_unavailable_post_ids,
            load_more_policy,
        });

        let snapshot = {
            let mut runtime = self
                .topic_detail_source
                .lock()
                .expect("topic detail source runtime lock poisoned");
            let next_session_id = runtime.next_session_id.saturating_add(1).max(1);
            runtime.next_session_id = next_session_id;
            let session = session.with_session_id(next_session_id);
            let snapshot = session.source_snapshot();
            runtime.sessions_by_topic_id.insert(query.topic_id, session);
            snapshot
        };

        Ok(snapshot)
    }

    pub(in super::super) async fn fetch_topic_detail_base(
        &self,
        query: TopicDetailQuery,
        include_thread_state: bool,
    ) -> Result<TopicDetail, FireCoreError> {
        info!(
            topic_id = query.topic_id,
            post_number = ?query.post_number,
            track_visit = query.track_visit,
            "fetching topic detail"
        );

        let path = if let Some(post_number) = query.post_number {
            format!("/t/{}/{}.json", query.topic_id, post_number)
        } else {
            format!("/t/{}.json", query.topic_id)
        };

        let mut params = Vec::new();
        if query.track_visit {
            params.push(("track_visit", "true".to_string()));
        }
        if query.force_load {
            params.push(("forceLoad", "true".to_string()));
        }
        if let Some(filter) = query.filter {
            params.push(("filter", filter));
        }
        if let Some(username_filters) = query.username_filters {
            params.push(("username_filters", username_filters));
        }
        if query.filter_top_level_replies {
            params.push(("filter_top_level_replies", "true".to_string()));
        }

        let mut extra_headers = Vec::new();
        if query.track_visit {
            extra_headers.push(("Discourse-Track-View", "1".to_string()));
            extra_headers.push(("Discourse-Track-View-Topic-Id", query.topic_id.to_string()));
        }

        let traced =
            self.build_json_get_request("fetch topic detail", &path, params, &extra_headers)?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch topic detail", trace_id, response).await?;
        let raw: RawTopicDetail = self
            .read_response_json("fetch topic detail", trace_id, response)
            .await?;
        let detail = raw.into_topic_detail(include_thread_state, self.base_url());
        ensure_requested_topic_detail(query.topic_id, detail.id)?;
        Ok(detail)
    }
}
