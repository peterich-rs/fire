use std::panic::{self, AssertUnwindSafe};

use fire_models::{
    TopicDetailSourceSnapshot, TopicDetailUiSnapshot, TopicHeader, TopicTreePresentation,
};

use super::super::topic_detail_project::{
    chrome_fields_changed, header_counts_changed, home_row_patch_for_header,
    interaction_checksums_changed, layout_checksums_changed, project_topic_detail_snapshot,
    sidecar_changed, structure_changed, ProjectionChrome,
};
use super::super::topics::build_topic_tree_presentation_from_source_snapshot;
use super::super::FireCore;
use super::*;

impl ActorState {
    pub(super) fn publish(&mut self, core: &FireCore, structural_hint: bool) {
        let _ = structural_hint;
        if self.defer_publish && self.scroll_active {
            let mut snapshot = self.make_snapshot(core);
            self.assign_revisions(&mut snapshot);
            self.deferred = DeferredRefresh::Ready(Box::new(snapshot));
            return;
        }
        let mut snapshot = self.make_snapshot(core);
        self.assign_revisions(&mut snapshot);
        self.publish_snapshot(core, snapshot);
    }

    pub(super) fn publish_snapshot(&mut self, core: &FireCore, snapshot: TopicDetailUiSnapshot) {
        if let Some(patch) = snapshot.home_row_patch.clone() {
            core.patch_cached_home_topic_counts(&patch);
        }
        self.published = Some(snapshot.clone());
        let owners = self.owners.values().cloned().collect::<Vec<_>>();
        for owner in owners {
            let snapshot = snapshot.clone();
            let _ = panic::catch_unwind(AssertUnwindSafe(|| owner.on_snapshot(snapshot)));
        }
        let _ = core;
    }

    pub(super) fn assign_revisions(&mut self, snapshot: &mut TopicDetailUiSnapshot) {
        let previous = self.published.as_ref();
        if structure_changed(previous, snapshot) {
            self.collection_revision = self.collection_revision.saturating_add(1);
        }
        let layout_changed = layout_checksums_changed(previous, snapshot);
        let interaction_changed = interaction_checksums_changed(previous, snapshot);
        if interaction_changed || (layout_changed && !structure_changed(previous, snapshot)) {
            self.interaction_revision = self.interaction_revision.saturating_add(1);
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
    }

    pub(super) fn make_snapshot(&mut self, core: &FireCore) -> TopicDetailUiSnapshot {
        let source = core
            .clone_topic_source_snapshot(self.topic_id)
            .unwrap_or_else(|| TopicDetailSourceSnapshot {
                header: self.header.clone().unwrap_or_else(|| TopicHeader {
                    topic_id: self.topic_id,
                    slug: self.slug_hint.clone().unwrap_or_default(),
                    ..TopicHeader::default()
                }),
                ..TopicDetailSourceSnapshot::default()
            });
        let previous_header = self.header.clone();
        let home_row_patch = previous_header
            .as_ref()
            .filter(|previous| header_counts_changed(previous, &source.header))
            .map(|_| home_row_patch_for_header(&source.header));
        if source.header.topic_id == self.topic_id && source.header.posts_count > 0 {
            self.header = Some(source.header.clone());
        }
        let tree = if source.loaded_posts.is_empty() && source.body.post.id == 0 {
            TopicTreePresentation::default()
        } else {
            build_topic_tree_presentation_from_source_snapshot(&source)
        };
        let mut chrome = ProjectionChrome {
            phase: self.phase,
            load_error: self.load_error.clone(),
            notice: self.notice.clone(),
            is_loading_more: self.loading_more,
            load_more_error: self.load_more_error.clone(),
            scroll_target_post_number: self.scroll_target.filter(|_| !self.scroll_exhausted),
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
            home_row_patch,
            generation: self.generation,
            collection_revision: self.collection_revision,
            chrome_revision: self.chrome_revision,
            sidecar_revision: self.sidecar_revision,
            interaction_revision: self.interaction_revision,
        };
        if self.reply_context.is_some() {
            chrome.reply_context = self.reply_context.clone();
        }
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
            generation: self.generation,
            collection_revision: self.collection_revision,
            chrome_revision: self.chrome_revision,
            sidecar_revision: self.sidecar_revision,
            interaction_revision: self.interaction_revision,
        }
    }
}
