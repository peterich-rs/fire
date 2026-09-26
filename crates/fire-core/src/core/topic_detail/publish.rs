use std::panic::{self, AssertUnwindSafe};
use std::sync::Arc;

use fire_models::{
    TopicDetailSourceSnapshot, TopicDetailUiSnapshot, TopicHeader, TopicTreePresentation,
};
use tracing::debug;

use super::super::topics::build_topic_tree_presentation_from_posts_by_id;
use super::super::FireCore;
use super::project::{
    build_published_index, chrome_fields_changed, diff_snapshots, header_counts_changed,
    home_row_patch_for_header, interaction_checksums_changed, layout_checksums_changed,
    project_topic_detail_snapshot, project_topic_detail_snapshot_from_posts, sidecar_changed,
    snapshot_change, structure_changed, ProjectedPostSource, ProjectionChrome,
};
use super::*;

impl ActorState {
    /// Publishes the current state, or marks it for publishing while the host
    /// scrolls. A deferred publish waits at most
    /// `TOPIC_DETAIL_DEFER_PUBLISH_TIMEOUT` and is rebuilt from live state when
    /// it fires, so it always carries fresh revisions.
    pub(super) fn publish(&mut self, core: &FireCore) {
        if self.scroll_active {
            self.defer_publish();
            return;
        }
        self.publish_now(core);
    }

    pub(super) fn flush_deferred(
        &mut self,
        core: &FireCore,
        tx: &tokio::sync::mpsc::UnboundedSender<Command>,
    ) {
        self.flush_deferred_publish(core);
        if std::mem::take(&mut self.deferred.refresh) {
            self.arm_refresh(tx);
        }
    }

    pub(super) fn flush_deferred_publish(&mut self, core: &FireCore) {
        self.defer_publish_generation = self.defer_publish_generation.saturating_add(1);
        if std::mem::take(&mut self.deferred.publish) {
            self.publish_now(core);
        }
    }

    fn defer_publish(&mut self) {
        if self.deferred.publish {
            return;
        }
        self.deferred.publish = true;
        self.defer_publish_generation = self.defer_publish_generation.saturating_add(1);
        let generation = self.defer_publish_generation;
        let tx = self.tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(TOPIC_DETAIL_DEFER_PUBLISH_TIMEOUT).await;
            let _ = tx.send(Command::DeferredPublishTimeout(generation));
        });
    }

    fn publish_now(&mut self, core: &FireCore) {
        let mut snapshot = self.make_snapshot(core);
        let previous = self.published.as_deref();
        let Some(diff) = diff_snapshots(previous, self.published_index.as_ref(), &snapshot) else {
            debug!(
                topic_id = self.topic_id,
                published_rows = snapshot.rows.len(),
                upserted_rows = 0u64,
                "topic detail empty publish skipped"
            );
            return;
        };
        let base_generation = previous.map(|previous| previous.generation);
        self.assign_revisions(&mut snapshot);
        if let Some(patch) = snapshot.home_row_patch.as_ref() {
            core.patch_cached_home_topic_counts(patch);
        }
        let snapshot = Arc::new(snapshot);
        debug!(
            topic_id = self.topic_id,
            published_rows = snapshot.rows.len(),
            upserted_rows = diff.upserted_post_ids.len(),
            order_changed = diff.order_changed,
            base_generation,
            generation = snapshot.generation,
            "topic detail snapshot change"
        );
        let change = snapshot_change(Arc::clone(&snapshot), base_generation, diff);
        for owner in self.owners.values() {
            let _ = panic::catch_unwind(AssertUnwindSafe(|| owner.on_change(&change)));
        }
        self.published_index = Some(build_published_index(&snapshot));
        self.published = Some(snapshot);
    }

    pub(super) fn assign_revisions(&mut self, snapshot: &mut TopicDetailUiSnapshot) {
        let previous = self.published.as_deref();
        let structure = structure_changed(previous, snapshot);
        if structure {
            self.collection_revision = self.collection_revision.saturating_add(1);
        }
        // A row whose height changed while the collection kept its shape is
        // patched in place, so it rides the interaction revision.
        if interaction_checksums_changed(previous, snapshot)
            || (!structure && layout_checksums_changed(previous, snapshot))
        {
            self.interaction_revision = self.interaction_revision.saturating_add(1);
        }
        if previous.is_none_or(|previous| previous.composer != snapshot.composer) {
            self.composer_revision = self.composer_revision.saturating_add(1);
        }
        if previous.is_none_or(|previous| chrome_fields_changed(&previous.chrome, &snapshot.chrome))
        {
            self.chrome_revision = self.chrome_revision.saturating_add(1);
        }
        if previous.is_none_or(|previous| {
            sidecar_changed(
                &previous.sidecar,
                &snapshot.sidecar,
                &previous.notice,
                &snapshot.notice,
            ) && !(snapshot.sidecar.is_loading
                && previous.sidecar.summarized_text == snapshot.sidecar.summarized_text
                && previous.sidecar.error == snapshot.sidecar.error
                && previous.notice == snapshot.notice)
        }) {
            self.sidecar_revision = self.sidecar_revision.saturating_add(1);
        }
        self.generation = self.generation.saturating_add(1);
        snapshot.generation = self.generation;
        snapshot.collection_revision = self.collection_revision;
        snapshot.chrome_revision = self.chrome_revision;
        snapshot.sidecar_revision = self.sidecar_revision;
        snapshot.interaction_revision = self.interaction_revision;
        snapshot.composer_revision = self.composer_revision;
    }

    pub(super) fn make_snapshot(&mut self, core: &FireCore) -> TopicDetailUiSnapshot {
        let previous_header = self.header.clone();
        let header =
            core.with_topic_source_session(self.topic_id, |session| session.header().clone());
        let home_row_patch = match (previous_header.as_ref(), header.as_ref()) {
            (Some(previous), Some(next)) if header_counts_changed(previous, next) => Some(
                core.note_local_topic_read(
                    next.topic_id,
                    next.last_read_post_number,
                    next.highest_post_number,
                )
                .unwrap_or_else(|| home_row_patch_for_header(next)),
            ),
            _ => None,
        };
        if let Some(next) = header.as_ref() {
            if next.topic_id == self.topic_id && next.posts_count > 0 {
                self.header = Some(next.clone());
            }
        }
        let mut chrome = self.projection_chrome(core);
        chrome.scroll_target_post_number = self.scroll_target.filter(|_| !self.scroll_exhausted);
        chrome.home_row_patch = home_row_patch;
        let cache = &mut self.row_cache;
        if let Some(snapshot) = core
            .with_topic_source_session(self.topic_id, |session| {
                let body_post = session.body_post_ref()?;
                let tree = if session.posts_by_id().is_empty() && body_post.id == 0 {
                    TopicTreePresentation::default()
                } else {
                    build_topic_tree_presentation_from_posts_by_id(
                        body_post,
                        session.raw_stream_ids(),
                        session.posts_by_id(),
                        session.header().last_read_post_number,
                    )
                };
                Some(project_topic_detail_snapshot_from_posts(
                    ProjectedPostSource {
                        header: session.header(),
                        body_post,
                        posts_by_id: session.posts_by_id(),
                        tree: &tree,
                        versions: session.post_versions(),
                        source_exhausted: session.source_exhausted(),
                    },
                    &chrome,
                    cache,
                ))
            })
            .flatten()
        {
            return snapshot;
        }
        let source = TopicDetailSourceSnapshot {
            header: self.header.clone().unwrap_or_else(|| TopicHeader {
                topic_id: self.topic_id,
                slug: self.slug_hint.clone().unwrap_or_default(),
                ..TopicHeader::default()
            }),
            ..TopicDetailSourceSnapshot::default()
        };
        let tree = TopicTreePresentation::default();
        project_topic_detail_snapshot(&source, &tree, &chrome)
    }

    pub(super) fn projection_chrome(&self, core: &FireCore) -> ProjectionChrome {
        ProjectionChrome {
            phase: self.phase,
            load_error: self.load_error.clone(),
            notice: self.notice.clone(),
            is_loading_more: self.loading_more,
            load_more_error: self.load_more_error.clone(),
            scroll_target_post_number: self.scroll_target,
            summary: self.summary.clone(),
            summary_loading: self.summary_loading,
            summary_error: self.summary_error.clone(),
            typing_users: self.typing_users.clone(),
            current_user_id: core.snapshot().bootstrap.current_user_id,
            is_submitting: self.submitting,
            mutating: self.mutating.clone(),
            loading_reply_context: self.loading_reply_context.clone(),
            reply_context: self.reply_context.clone(),
            flag_types: self.flag_types.clone(),
            home_row_patch: None,
        }
    }
}
