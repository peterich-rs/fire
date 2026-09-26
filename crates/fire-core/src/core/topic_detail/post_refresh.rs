use tokio::sync::mpsc;

use super::super::FireCore;
use super::*;

impl ActorState {
    pub(super) async fn flush_post_refreshes(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
    ) {
        if let Some(refresh_stream) = self.pending_reload.take() {
            self.pending_post_ids.clear();
            self.pending_created_ids.clear();
            self.pending_height_changing.clear();
            self.load_http(core, tx, None, refresh_stream, false, false, true)
                .await;
            return;
        }

        if !self.pending_height_changing.is_empty() && !self.scroll_active {
            self.pending_post_ids
                .extend(self.pending_height_changing.drain());
        }

        let pending: Vec<u64> = self.pending_post_ids.drain().collect();
        if pending.is_empty() {
            return;
        }
        if pending.len() > TOPIC_DETAIL_POST_REFRESH_COLLAPSE {
            self.load_http(core, tx, None, false, false, false, true)
                .await;
            return;
        }

        let mut created_at_tail = Vec::new();
        let mut refresh_ids = Vec::new();
        for post_id in pending {
            if self.pending_created_ids.remove(&post_id) {
                match self.created_destination(core, post_id) {
                    CreatedDestination::Echo => {}
                    CreatedDestination::FetchTail => created_at_tail.push(post_id),
                    CreatedDestination::AppendIdOnly => {
                        self.append_stream_id_only(core, post_id);
                    }
                }
            } else {
                refresh_ids.push(post_id);
            }
        }

        let mut fetch_ids = created_at_tail;
        fetch_ids.extend(refresh_ids);
        self.fetch_and_merge_posts(core, fetch_ids).await;
    }

    fn created_destination(&self, core: &FireCore, post_id: u64) -> CreatedDestination {
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if session.post(post_id).is_some() && session.raw_stream_ids().contains(&post_id) {
                CreatedDestination::Echo
            } else if session.source_cursor().is_none() || session.source_exhausted() {
                CreatedDestination::FetchTail
            } else {
                CreatedDestination::AppendIdOnly
            }
        })
        .unwrap_or(CreatedDestination::AppendIdOnly)
    }

    fn append_stream_id_only(&self, core: &FireCore, post_id: u64) {
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session.append_stream_id(post_id);
        });
    }

    async fn fetch_and_merge_posts(&mut self, core: &FireCore, post_ids: Vec<u64>) {
        if post_ids.is_empty() {
            return;
        }
        for chunk in post_ids.chunks(TOPIC_DETAIL_POST_REFRESH_CONCURRENCY) {
            let mut tasks = Vec::new();
            for post_id in chunk {
                if !self.inflight_refresh_ids.insert(*post_id) {
                    self.retry_post_ids.insert(*post_id);
                    continue;
                }
                let core = core.clone();
                let post_id = *post_id;
                tasks.push(async move { (post_id, core.fetch_post(post_id).await) });
            }
            let results = futures_util::future::join_all(tasks).await;
            for (post_id, result) in results {
                self.inflight_refresh_ids.remove(&post_id);
                match result {
                    Ok(post) => {
                        core.with_topic_source_session_mut(self.topic_id, None, |session| {
                            session.append_stream_post(post);
                        });
                    }
                    Err(error) => {
                        if matches!(
                            error,
                            crate::error::FireCoreError::HttpStatus { status: 404, .. }
                        ) {
                            core.with_topic_source_session_mut(self.topic_id, None, |session| {
                                session.mark_deleted(post_id);
                            });
                        } else if self.retry_post_ids.remove(&post_id) {
                            self.pending_post_ids.insert(post_id);
                        } else {
                            self.retry_post_ids.insert(post_id);
                            let tx_needed = post_id;
                            let _ = tx_needed;
                        }
                    }
                }
            }
            self.publish(core);
        }

        if !self.retry_post_ids.is_empty() {
            let retry: Vec<u64> = self.retry_post_ids.drain().collect();
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
            for post_id in retry {
                if let Ok(post) = core.fetch_post(post_id).await {
                    core.with_topic_source_session_mut(self.topic_id, None, |session| {
                        session.append_stream_post(post);
                    });
                    self.publish(core);
                }
            }
        }
    }
}

enum CreatedDestination {
    Echo,
    FetchTail,
    AppendIdOnly,
}
