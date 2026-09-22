use std::collections::HashSet;
use std::time::Instant;

use fire_models::{
    LoadMoreTopicPostsQuery, TopicDetail, TopicDetailPage, TopicDetailQuery,
    TopicDetailSourceAppend, TopicDetailSourceQuery, TopicDetailSourceSnapshot,
    TopicLoadMoreOutcome, TopicLoadMoreStopReason, TopicSourceCursor, TopicTreePresentation,
};
use tracing::{info, warn};

use super::super::super::{network::expect_success, FireCore};
use super::super::posts::{merge_topic_posts, missing_post_ids_from_ids};
use super::super::tree::{
    build_topic_tree_presentation_from_source_snapshot, topic_detail_source_cooked_byte_count,
    topic_tree_needs_unread_root_extension,
};
use super::*;
use crate::{error::FireCoreError, topic_payloads::RawTopicDetail};
pub(crate) async fn load_topic_detail_source_snapshot(
    core: &FireCore,
    query: TopicDetailSourceQuery,
) -> Result<TopicDetailSourceSnapshot, FireCoreError> {
    core.load_topic_detail_source_snapshot_impl(query).await
}

pub(crate) async fn load_topic_detail_page(
    core: &FireCore,
    query: TopicDetailSourceQuery,
) -> Result<TopicDetailPage, FireCoreError> {
    core.load_topic_detail_page_impl(query).await
}

pub(crate) async fn load_more_topic_detail_posts(
    core: &FireCore,
    query: LoadMoreTopicPostsQuery,
) -> Result<TopicLoadMoreOutcome, FireCoreError> {
    core.load_more_topic_posts_impl(query).await
}

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

    pub async fn fetch_topic_detail_page(
        &self,
        query: TopicDetailSourceQuery,
    ) -> Result<TopicDetailPage, FireCoreError> {
        load_topic_detail_page(self, query).await
    }

    pub(crate) async fn load_topic_detail_page_impl(
        &self,
        query: TopicDetailSourceQuery,
    ) -> Result<TopicDetailPage, FireCoreError> {
        let topic_id = query.topic_id;
        let should_seek_unread_root =
            query.allow_suggested_unread_root && query.target_post_number.is_none();
        let source_started_at = Instant::now();
        let mut source_snapshot = load_topic_detail_source_snapshot(self, query).await?;
        let source_fetch_ms = source_started_at.elapsed().as_millis();
        let tree_started_at = Instant::now();
        let mut tree_presentation =
            build_topic_tree_presentation_from_source_snapshot(&source_snapshot);
        let tree_presentation_ms = tree_started_at.elapsed().as_millis();
        let auto_seek_started_at = Instant::now();
        let auto_seek = if should_seek_unread_root {
            self.extend_topic_source_to_unread_root_if_needed(
                &mut source_snapshot,
                &mut tree_presentation,
            )
            .await?
        } else {
            TopicUnreadRootAutoSeekStats::default()
        };
        let auto_seek_ms = auto_seek_started_at.elapsed().as_millis();
        info!(
            topic_id,
            source_fetch_ms,
            tree_presentation_ms,
            auto_unread_root_ms = auto_seek_ms,
            auto_unread_root_batches = auto_seek.chained_batches,
            auto_unread_root_posts = auto_seek.chained_posts,
            source_loaded_posts = source_snapshot.loaded_posts.len(),
            body_post_included = true,
            cooked_byte_count = topic_detail_source_cooked_byte_count(&source_snapshot),
            reply_rows = tree_presentation.reply_rows.len(),
            visible_root_count = tree_presentation.visible_root_post_numbers.len(),
            first_unread_root_post_number = ?tree_presentation.first_unread_root_post_number,
            total_loaded_post_count = tree_presentation.total_loaded_post_count,
            "topic detail page built"
        );
        Ok(TopicDetailPage {
            source_snapshot,
            tree_presentation,
        })
    }

    pub(super) async fn extend_topic_source_to_unread_root_if_needed(
        &self,
        source_snapshot: &mut TopicDetailSourceSnapshot,
        tree_presentation: &mut TopicTreePresentation,
    ) -> Result<TopicUnreadRootAutoSeekStats, FireCoreError> {
        let mut stats = TopicUnreadRootAutoSeekStats::default();
        if !topic_tree_needs_unread_root_extension(source_snapshot, tree_presentation) {
            return Ok(stats);
        }

        let Some(initial_cursor) = source_snapshot.source_cursor.clone() else {
            return Ok(stats);
        };
        let policy = self
            .clone_active_source_session(
                initial_cursor.topic_id,
                initial_cursor.session_id,
                None,
                None,
            )?
            .load_more_policy;
        let mut current_cursor = initial_cursor;

        while topic_tree_needs_unread_root_extension(source_snapshot, tree_presentation) {
            let append_result = self.append_topic_source_batch(current_cursor.clone()).await;
            let append = match append_result {
                Ok(append) => append,
                Err(error) => {
                    warn!(
                        topic_id = current_cursor.topic_id,
                        session_id = current_cursor.session_id,
                        batches = stats.chained_batches,
                        posts = stats.chained_posts,
                        error = %error,
                        "topic unread root auto seek stopped after source append failure"
                    );
                    return Ok(stats);
                }
            };

            stats.chained_batches = stats.chained_batches.saturating_add(1);
            stats.chained_posts = stats
                .chained_posts
                .saturating_add(u16::try_from(append.appended_posts.len()).unwrap_or(u16::MAX));
            let session = self.clone_active_source_session(
                current_cursor.topic_id,
                current_cursor.session_id,
                None,
                None,
            )?;
            *source_snapshot = session.source_snapshot();
            *tree_presentation =
                build_topic_tree_presentation_from_source_snapshot(source_snapshot);

            if !topic_tree_needs_unread_root_extension(source_snapshot, tree_presentation)
                || source_snapshot.source_exhausted
                || stats.chained_batches >= policy.max_auto_batches_per_gesture
                || stats.chained_posts >= policy.max_auto_posts_per_gesture
            {
                return Ok(stats);
            }

            let Some(next_cursor) = source_snapshot.source_cursor.clone() else {
                return Ok(stats);
            };
            current_cursor = next_cursor;
        }

        Ok(stats)
    }

    pub async fn append_topic_detail_source(
        &self,
        query: LoadMoreTopicPostsQuery,
    ) -> Result<TopicDetailSourceAppend, FireCoreError> {
        self.append_topic_source_batch(query.cursor).await
    }

    pub async fn load_more_topic_posts(
        &self,
        query: LoadMoreTopicPostsQuery,
    ) -> Result<TopicLoadMoreOutcome, FireCoreError> {
        load_more_topic_detail_posts(self, query).await
    }

    pub(crate) async fn load_more_topic_posts_impl(
        &self,
        query: LoadMoreTopicPostsQuery,
    ) -> Result<TopicLoadMoreOutcome, FireCoreError> {
        let initial_session = self.clone_active_source_session(
            query.cursor.topic_id,
            query.cursor.session_id,
            None,
            None,
        )?;
        let initial_snapshot = initial_session.source_snapshot();
        let baseline_tree = build_topic_tree_presentation_from_source_snapshot(&initial_snapshot);
        let baseline_visible_roots = baseline_tree.visible_root_post_numbers.clone();
        let policy = initial_session.load_more_policy;

        let mut current_cursor = query.cursor;
        let mut latest_snapshot = initial_snapshot;
        let mut latest_tree = baseline_tree;
        let mut appended_posts = Vec::new();
        let mut chained_batches: u8 = 0;
        let mut chained_posts: u16 = 0;

        loop {
            let append_result = self.append_topic_source_batch(current_cursor.clone()).await;
            let append = match append_result {
                Ok(append) => append,
                Err(error) if chained_batches == 0 => return Err(error),
                Err(error) => {
                    warn!(
                        topic_id = current_cursor.topic_id,
                        session_id = current_cursor.session_id,
                        batches = chained_batches,
                        posts = chained_posts,
                        error = %error,
                        "{TOPIC_LOAD_MORE_FAILURE_MESSAGE}"
                    );
                    latest_tree.gained_new_root_progress = gained_visible_root_progress(
                        &baseline_visible_roots,
                        &latest_tree.visible_root_post_numbers,
                    );
                    return Ok(topic_load_more_outcome(
                        latest_snapshot,
                        appended_posts,
                        latest_tree,
                        chained_batches,
                        chained_posts,
                        TopicLoadMoreStopReason::RequestFailed,
                    ));
                }
            };

            chained_batches = chained_batches.saturating_add(1);
            chained_posts = chained_posts
                .saturating_add(u16::try_from(append.appended_posts.len()).unwrap_or(u16::MAX));
            appended_posts.extend(append.appended_posts);
            let session = self.clone_active_source_session(
                current_cursor.topic_id,
                current_cursor.session_id,
                None,
                None,
            )?;
            latest_snapshot = session.source_snapshot();
            latest_tree = build_topic_tree_presentation_from_source_snapshot(&latest_snapshot);
            latest_tree.gained_new_root_progress = gained_visible_root_progress(
                &baseline_visible_roots,
                &latest_tree.visible_root_post_numbers,
            );

            if policy.require_new_root_progress && latest_tree.gained_new_root_progress {
                return Ok(topic_load_more_outcome(
                    latest_snapshot,
                    appended_posts,
                    latest_tree,
                    chained_batches,
                    chained_posts,
                    TopicLoadMoreStopReason::GainedVisibleRootProgress,
                ));
            }
            if latest_snapshot.source_exhausted {
                return Ok(topic_load_more_outcome(
                    latest_snapshot,
                    appended_posts,
                    latest_tree,
                    chained_batches,
                    chained_posts,
                    TopicLoadMoreStopReason::SourceExhausted,
                ));
            }
            if chained_batches >= policy.max_auto_batches_per_gesture {
                return Ok(topic_load_more_outcome(
                    latest_snapshot,
                    appended_posts,
                    latest_tree,
                    chained_batches,
                    chained_posts,
                    TopicLoadMoreStopReason::MaxAutoBatchesReached,
                ));
            }
            if chained_posts >= policy.max_auto_posts_per_gesture {
                return Ok(topic_load_more_outcome(
                    latest_snapshot,
                    appended_posts,
                    latest_tree,
                    chained_batches,
                    chained_posts,
                    TopicLoadMoreStopReason::MaxAutoPostsReached,
                ));
            }

            let Some(next_cursor) = latest_snapshot.source_cursor.clone() else {
                return Ok(topic_load_more_outcome(
                    latest_snapshot,
                    appended_posts,
                    latest_tree,
                    chained_batches,
                    chained_posts,
                    TopicLoadMoreStopReason::SourceExhausted,
                ));
            };
            current_cursor = next_cursor;
        }
    }

    pub(super) fn clone_active_source_session(
        &self,
        topic_id: u64,
        session_id: u64,
        expected_next_stream_offset: Option<u32>,
        expected_last_loaded_post_id: Option<u64>,
    ) -> Result<TopicDetailSourceSession, FireCoreError> {
        let current_epoch = self.current_session_epoch();
        let runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
            return Err(FireCoreError::InvalidTopicSourceCursor {
                topic_id,
                session_id,
            });
        };
        if session.session_id != session_id || session.session_epoch != current_epoch {
            return Err(FireCoreError::InvalidTopicSourceCursor {
                topic_id,
                session_id,
            });
        }
        if let Some(expected_next_stream_offset) = expected_next_stream_offset {
            if session.next_stream_offset != expected_next_stream_offset as usize
                || session.last_loaded_post_id != expected_last_loaded_post_id
            {
                return Err(FireCoreError::InvalidTopicSourceCursor {
                    topic_id,
                    session_id,
                });
            }
        }
        Ok(session.clone())
    }

    pub(super) async fn append_topic_source_batch(
        &self,
        cursor: TopicSourceCursor,
    ) -> Result<TopicDetailSourceAppend, FireCoreError> {
        let batch_size = normalized_topic_load_more_batch_size(cursor.batch_size);
        let session = self.clone_active_source_session(
            cursor.topic_id,
            cursor.session_id,
            Some(cursor.next_stream_offset),
            cursor.last_loaded_post_id,
        )?;
        if session.source_exhausted {
            return Ok(TopicDetailSourceAppend {
                appended_posts: Vec::new(),
                loaded_ranges: session.loaded_ranges,
                source_cursor: None,
                source_exhausted: true,
            });
        }

        let batch_start_offset = session.next_stream_offset;
        let batch_end_offset = session
            .next_stream_offset
            .saturating_add(usize::from(batch_size))
            .min(session.raw_stream_ids.len());
        let batch_post_ids = session.raw_stream_ids[batch_start_offset..batch_end_offset].to_vec();
        let previously_loaded_post_ids = batch_post_ids
            .iter()
            .copied()
            .filter(|post_id| session.posts_by_id.contains_key(post_id))
            .collect::<HashSet<_>>();
        let missing_post_ids = batch_post_ids
            .iter()
            .copied()
            .filter(|post_id| !previously_loaded_post_ids.contains(post_id))
            .collect::<Vec<_>>();
        let mut fetched_posts = Vec::new();
        for post_ids in missing_post_ids.chunks(TOPIC_POST_BATCH_SIZE) {
            fetched_posts.extend(
                self.fetch_topic_posts(cursor.topic_id, post_ids.to_vec())
                    .await?,
            );
        }
        let fetched_post_ids = fetched_posts
            .iter()
            .map(|post| post.id)
            .collect::<HashSet<_>>();
        let unavailable_post_ids = missing_post_ids
            .into_iter()
            .filter(|post_id| !fetched_post_ids.contains(post_id))
            .collect::<HashSet<_>>();

        let mut runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get_mut(&cursor.topic_id) else {
            return Err(FireCoreError::InvalidTopicSourceCursor {
                topic_id: cursor.topic_id,
                session_id: cursor.session_id,
            });
        };
        if session.session_id != cursor.session_id
            || session.session_epoch != self.current_session_epoch()
            || session.next_stream_offset != cursor.next_stream_offset as usize
            || session.last_loaded_post_id != cursor.last_loaded_post_id
        {
            return Err(FireCoreError::InvalidTopicSourceCursor {
                topic_id: cursor.topic_id,
                session_id: cursor.session_id,
            });
        }

        session.merge_posts(fetched_posts);
        session.mark_unavailable(unavailable_post_ids);
        session.recompute_loaded_state();
        let appended_posts = batch_post_ids
            .iter()
            .filter(|post_id| !previously_loaded_post_ids.contains(post_id))
            .filter_map(|post_id| session.posts_by_id.get(post_id).cloned())
            .collect::<Vec<_>>();
        Ok(TopicDetailSourceAppend {
            appended_posts,
            loaded_ranges: session.loaded_ranges.clone(),
            source_cursor: session.source_cursor(),
            source_exhausted: session.source_exhausted,
        })
    }

    pub(super) async fn fetch_topic_detail_base(
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
