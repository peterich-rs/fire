use std::collections::HashSet;

use fire_models::{
    LoadMoreTopicPostsQuery, TopicDetailSourceAppend, TopicLoadMoreOutcome,
    TopicLoadMoreStopReason, TopicSourceCursor,
};
use tracing::warn;

use super::super::super::super::FireCore;
use super::super::super::tree::build_topic_tree_presentation_from_source_snapshot;
use super::super::{
    gained_visible_root_progress, normalized_topic_load_more_batch_size, topic_load_more_outcome,
    TopicDetailSourceSession, TOPIC_LOAD_MORE_FAILURE_MESSAGE, TOPIC_POST_BATCH_SIZE,
};
use super::load_more_topic_detail_posts;
use crate::error::FireCoreError;

impl FireCore {
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

    pub(in super::super) fn clone_active_source_session(
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

    pub(in super::super) async fn append_topic_source_batch(
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
}
