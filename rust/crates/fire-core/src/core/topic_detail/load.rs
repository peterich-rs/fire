use std::collections::HashSet;

use fire_models::{
    LoadMoreTopicPostsQuery, TopicDetailLoadError, TopicDetailPhase, TopicDetailSourceQuery,
};
use tokio::sync::mpsc;

use super::super::topics::{load_more_topic_detail_posts, load_topic_detail_page};
use super::super::FireCore;
use super::*;
use crate::error::FireCoreError;

impl ActorState {
    pub(super) async fn open(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        request: TopicDetailOpenRequest,
    ) {
        self.scroll_target = request.target_post_number;
        self.scroll_exhausted = false;
        self.track_visit = request.track_visit;
        if !request.bypass_cache
            && core.topic_source_contains_target(self.topic_id, request.target_post_number)
        {
            self.phase = TopicDetailPhase::Ready;
            self.load_error = None;
            self.capture_header(core);
            self.reset_window(core);
            self.publish(core, false);
            self.maybe_fetch_summary(core).await;
            return;
        }
        self.load_http(
            core,
            tx,
            request.target_post_number,
            request.force_load,
            request.track_visit,
            request.allow_suggested_unread_root,
            false,
        )
        .await;
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) async fn load_http(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        target_post_number: Option<u32>,
        force_load: bool,
        track_visit: bool,
        allow_suggested_unread_root: bool,
        from_bus: bool,
    ) {
        if self.published.is_none() {
            self.phase = TopicDetailPhase::Loading;
            self.load_error = None;
            self.publish(core, false);
        }
        self.track_visit = track_visit;
        self.refresh_inflight = from_bus || self.refresh_inflight;
        let epoch = self.http_epoch;
        let query = actor_query(
            self.topic_id,
            target_post_number,
            force_load,
            track_visit,
            allow_suggested_unread_root,
        );
        let core_for_load = core.clone();
        let loaded = tokio::time::timeout(TOPIC_DETAIL_REQUEST_TIMEOUT, async move {
            load_page_with_stale_retry(&core_for_load, query).await
        })
        .await;
        if epoch != self.http_epoch || !self.alive {
            self.refresh_inflight = false;
            return;
        }
        self.refresh_inflight = false;
        match loaded {
            Ok(Ok(_)) => {
                self.restore_inflight_posts(core);
                self.phase = TopicDetailPhase::Ready;
                self.load_error = None;
                self.capture_header(core);
                self.reset_window(core);
                self.subscribe_channels(core);
                if self.defer_publish && self.scroll_active {
                    let snapshot = self.make_snapshot(core);
                    self.deferred = DeferredRefresh::Ready(Box::new(snapshot));
                    self.defer_publish = false;
                } else {
                    self.defer_publish = false;
                    self.publish(core, false);
                }
                if self.scroll_target.is_some() && !self.scroll_exhausted {
                    let posts = self.pending_visible.clone();
                    self.hydrate_visible(core, &posts).await;
                }
                self.maybe_fetch_summary(core).await;
            }
            Ok(Err(error)) => self.fail_load(core, &error),
            Err(_) => {
                self.load_error = Some(TopicDetailLoadError::Network);
                self.phase = TopicDetailPhase::Failed;
                self.publish(core, true);
            }
        }
        let _ = tx;
    }

    pub(super) fn fail_load(&mut self, core: &FireCore, error: &FireCoreError) {
        if let FireCoreError::LoginRequired { operation, .. } = error {
            let generation = core.request_read_path_login(operation);
            core.topic_detail_sessions
                .register_waiter(generation, self.topic_id, self.track_visit);
            self.load_error = Some(TopicDetailLoadError::LoginRequired);
        } else if matches!(
            error,
            FireCoreError::Network { .. }
                | FireCoreError::HttpStatus { .. }
                | FireCoreError::CloudflareChallenge { .. }
                | FireCoreError::CloudflareChallengeInProgress { .. }
        ) {
            self.load_error = Some(TopicDetailLoadError::Network);
        } else {
            self.load_error = Some(TopicDetailLoadError::Unrecoverable {
                message: error.to_string(),
            });
        }
        self.phase = TopicDetailPhase::Failed;
        self.publish(core, true);
    }

    pub(super) async fn load_more(&mut self, core: &FireCore) {
        if self.loading_more {
            return;
        }
        let Some(snapshot) = core.clone_topic_source_snapshot(self.topic_id) else {
            return;
        };
        let Some(cursor) = snapshot.source_cursor.clone() else {
            return;
        };
        self.loading_more = true;
        self.load_more_error = None;
        self.publish(core, true);
        let epoch = self.http_epoch;
        let result = tokio::time::timeout(
            TOPIC_DETAIL_REQUEST_TIMEOUT,
            load_more_topic_detail_posts(core, LoadMoreTopicPostsQuery { cursor }),
        )
        .await;
        if epoch != self.http_epoch {
            self.loading_more = false;
            return;
        }
        self.loading_more = false;
        match result {
            Ok(Ok(_)) => {
                self.restore_inflight_posts(core);
                self.load_more_error = None;
                self.capture_header(core);
                self.extend_window_to_loaded(core);
                self.publish(core, true);
            }
            Ok(Err(error)) => {
                self.load_more_error = Some(error.to_string());
                self.publish(core, true);
            }
            Err(_) => {
                self.load_more_error = Some("topic detail load more timed out".to_string());
                self.publish(core, true);
            }
        }
    }

    pub(super) async fn hydrate_visible(&mut self, core: &FireCore, visible: &[u32]) {
        self.expand_window_for_visible(core, visible);
        if let Some(target) = self.scroll_target {
            if !core.topic_source_contains_target(self.topic_id, Some(target)) {
                self.advance_toward_target(core, target);
            }
        }
        for _ in 0..TOPIC_DETAIL_HYDRATION_ITERS {
            let missing = core
                .with_topic_source_session_mut(self.topic_id, None, |session| {
                    session.missing_ids_in_range(self.window.requested.clone())
                })
                .unwrap_or_default();
            if missing.is_empty() {
                if let Some(target) = self.scroll_target {
                    if core.topic_source_contains_target(self.topic_id, Some(target)) {
                        break;
                    }
                    if !self.advance_toward_target(core, target) {
                        self.scroll_exhausted = true;
                        break;
                    }
                    continue;
                }
                break;
            }
            let batch = missing
                .into_iter()
                .take(TOPIC_DETAIL_HYDRATION_PAGE)
                .collect::<Vec<_>>();
            let fetched = match core.fetch_topic_posts(self.topic_id, batch.clone()).await {
                Ok(posts) => posts,
                Err(_) => break,
            };
            let fetched_ids = fetched.iter().map(|post| post.id).collect::<HashSet<_>>();
            let missing_ids = batch
                .into_iter()
                .filter(|post_id| !fetched_ids.contains(post_id))
                .collect::<HashSet<_>>();
            core.with_topic_source_session_mut(self.topic_id, None, |session| {
                session.mark_unavailable(missing_ids);
                session.recompute_loaded_state();
            });
        }
        self.publish(core, false);
    }
}

fn actor_query(
    topic_id: u64,
    target_post_number: Option<u32>,
    force_load: bool,
    track_visit: bool,
    allow_suggested_unread_root: bool,
) -> TopicDetailSourceQuery {
    TopicDetailSourceQuery {
        topic_id,
        target_post_number,
        allow_suggested_unread_root,
        track_visit,
        force_load,
        initial_batch_size: TOPIC_DETAIL_INITIAL_BATCH,
        load_more_batch_size: TOPIC_DETAIL_LOAD_MORE_BATCH,
        max_auto_batches_per_gesture: TOPIC_DETAIL_MAX_AUTO_BATCHES,
        max_auto_posts_per_gesture: TOPIC_DETAIL_MAX_AUTO_POSTS,
    }
}

async fn load_page_with_stale_retry(
    core: &FireCore,
    mut query: TopicDetailSourceQuery,
) -> Result<fire_models::TopicDetailPage, FireCoreError> {
    let track_visit = query.track_visit;
    match load_topic_detail_page(core, query.clone()).await {
        Err(FireCoreError::StaleSessionResponse { .. }) => {
            query.force_load = true;
            query.track_visit = track_visit;
            load_topic_detail_page(core, query).await
        }
        other => other,
    }
}
