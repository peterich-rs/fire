use std::time::Instant;

use fire_models::{
    TopicDetailPage, TopicDetailSourceQuery, TopicDetailSourceSnapshot, TopicTreePresentation,
};
use tracing::{info, warn};

use super::super::super::super::FireCore;
use super::super::super::tree::{
    build_topic_tree_presentation_from_source_snapshot, topic_detail_source_cooked_byte_count,
    topic_tree_needs_unread_root_extension,
};
use super::super::TopicUnreadRootAutoSeekStats;
use super::{load_topic_detail_page, load_topic_detail_source_snapshot};
use crate::error::FireCoreError;

impl FireCore {
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

    pub(in super::super) async fn extend_topic_source_to_unread_root_if_needed(
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
}
