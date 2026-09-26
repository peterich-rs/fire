use std::collections::HashMap;
use std::sync::Arc;

use fire_models::{
    TopicDetailChangedRegions, TopicDetailReplyContext, TopicDetailSnapshotChange,
    TopicDetailUiRow, TopicDetailUiSnapshot,
};

use super::row_shape;

pub(crate) type RowFingerprint = (super::RowShape, u64, u64);
pub(crate) type PublishedRowIndex = HashMap<u64, (usize, RowFingerprint)>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SnapshotDiff {
    pub regions: TopicDetailChangedRegions,
    pub order_changed: bool,
    pub upserted_post_ids: Vec<u64>,
    pub home_row_patch: bool,
}

impl SnapshotDiff {
    fn first_publish() -> Self {
        Self {
            regions: TopicDetailChangedRegions::default(),
            order_changed: false,
            upserted_post_ids: Vec::new(),
            home_row_patch: false,
        }
    }

    fn is_empty(&self) -> bool {
        !self.regions.status
            && !self.regions.chrome
            && !self.regions.composer
            && !self.regions.sidecar
            && !self.regions.reply_context
            && !self.regions.flag_types
            && !self.order_changed
            && self.upserted_post_ids.is_empty()
            && !self.home_row_patch
    }
}

pub(crate) fn row_fingerprint(row: &TopicDetailUiRow) -> RowFingerprint {
    (
        row_shape(row),
        row.layout_checksum,
        row.interaction_checksum,
    )
}

pub(crate) fn build_published_index(snapshot: &TopicDetailUiSnapshot) -> PublishedRowIndex {
    snapshot
        .rows
        .iter()
        .enumerate()
        .map(|(index, row)| (row.post_id, (index, row_fingerprint(row))))
        .collect()
}

/// `None` means the two snapshots are identical for publish purposes.
pub(crate) fn diff_snapshots(
    previous: Option<&TopicDetailUiSnapshot>,
    previous_index: Option<&PublishedRowIndex>,
    next: &TopicDetailUiSnapshot,
) -> Option<SnapshotDiff> {
    let Some(previous) = previous else {
        return Some(SnapshotDiff::first_publish());
    };
    let owned_index;
    let index = match previous_index {
        Some(index) => index,
        None => {
            owned_index = build_published_index(previous);
            &owned_index
        }
    };

    let mut upserted_post_ids = Vec::new();
    let mut order_changed = previous.rows.len() != next.rows.len();
    for (index_in_next, row) in next.rows.iter().enumerate() {
        match index.get(&row.post_id) {
            Some((previous_index, previous_fingerprint)) => {
                if *previous_index != index_in_next {
                    order_changed = true;
                }
                if *previous_fingerprint != row_fingerprint(row) {
                    upserted_post_ids.push(row.post_id);
                }
            }
            None => {
                order_changed = true;
                upserted_post_ids.push(row.post_id);
            }
        }
    }
    if !order_changed {
        order_changed = previous
            .rows
            .iter()
            .zip(&next.rows)
            .any(|(previous, next)| previous.post_id != next.post_id);
    }

    let diff = SnapshotDiff {
        regions: TopicDetailChangedRegions {
            status: status_changed(previous, next),
            chrome: previous.chrome != next.chrome,
            composer: previous.composer != next.composer,
            sidecar: previous.sidecar != next.sidecar,
            reply_context: reply_context_changed(
                previous.focused_reply_context.as_ref(),
                next.focused_reply_context.as_ref(),
            ),
            flag_types: previous.flag_types != next.flag_types,
        },
        order_changed,
        upserted_post_ids,
        home_row_patch: next.home_row_patch.is_some(),
    };
    (!diff.is_empty()).then_some(diff)
}

pub(crate) fn snapshot_change(
    snapshot: Arc<TopicDetailUiSnapshot>,
    base_generation: Option<u64>,
    diff: SnapshotDiff,
) -> TopicDetailSnapshotChange {
    TopicDetailSnapshotChange {
        snapshot,
        base_generation,
        regions: diff.regions,
        order_changed: diff.order_changed,
        upserted_post_ids: diff.upserted_post_ids,
    }
}

/// Fold `change` onto `mirror`. First frame and resync clone `change.snapshot`.
#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn apply_change(
    mirror: Option<TopicDetailUiSnapshot>,
    change: &TopicDetailSnapshotChange,
) -> TopicDetailUiSnapshot {
    let full = change.snapshot.as_ref();
    if let Some(mirror) = mirror.as_ref() {
        if full.generation <= mirror.generation {
            return mirror.clone();
        }
    }
    if mirror
        .as_ref()
        .is_none_or(|mirror| change.base_generation != Some(mirror.generation))
    {
        return full.clone();
    }
    let Some(mut next) = mirror else {
        return full.clone();
    };
    if change.regions.status {
        next.phase = full.phase;
        next.load_error = full.load_error.clone();
        next.notice = full.notice.clone();
        next.has_more = full.has_more;
        next.is_loading_more = full.is_loading_more;
        next.load_more_error = full.load_more_error.clone();
        next.scroll_target_post_number = full.scroll_target_post_number;
    }
    if change.regions.chrome {
        next.chrome = full.chrome.clone();
    }
    if change.regions.composer {
        next.composer = full.composer.clone();
    }
    if change.regions.sidecar {
        next.sidecar = full.sidecar.clone();
    }
    if change.regions.reply_context {
        next.focused_reply_context = full.focused_reply_context.clone();
    }
    if change.regions.flag_types {
        next.flag_types = full.flag_types.clone();
    }
    next.home_row_patch = full.home_row_patch.clone();

    let mut rows_by_id: HashMap<u64, TopicDetailUiRow> = next
        .rows
        .into_iter()
        .map(|row| (row.post_id, row))
        .collect();
    for post_id in &change.upserted_post_ids {
        if let Some(row) = full.rows.iter().find(|row| row.post_id == *post_id) {
            rows_by_id.insert(*post_id, row.clone());
        }
    }
    if change.order_changed {
        let order: Vec<u64> = full.rows.iter().map(|row| row.post_id).collect();
        if order.iter().any(|id| !rows_by_id.contains_key(id)) {
            return full.clone();
        }
        next.rows = order
            .into_iter()
            .filter_map(|id| rows_by_id.remove(&id))
            .collect();
    } else {
        next.rows = full
            .rows
            .iter()
            .map(|row| {
                rows_by_id
                    .remove(&row.post_id)
                    .unwrap_or_else(|| row.clone())
            })
            .collect();
    }
    next.generation = full.generation;
    next.collection_revision = full.collection_revision;
    next.chrome_revision = full.chrome_revision;
    next.sidecar_revision = full.sidecar_revision;
    next.interaction_revision = full.interaction_revision;
    next.composer_revision = full.composer_revision;
    next
}

fn status_changed(previous: &TopicDetailUiSnapshot, next: &TopicDetailUiSnapshot) -> bool {
    previous.phase != next.phase
        || previous.load_error != next.load_error
        || previous.notice != next.notice
        || previous.has_more != next.has_more
        || previous.is_loading_more != next.is_loading_more
        || previous.load_more_error != next.load_more_error
        || previous.scroll_target_post_number != next.scroll_target_post_number
}

fn reply_context_changed(
    previous: Option<&TopicDetailReplyContext>,
    next: Option<&TopicDetailReplyContext>,
) -> bool {
    match (previous, next) {
        (None, None) => false,
        (None, Some(_)) | (Some(_), None) => true,
        (Some(previous), Some(next)) => {
            previous.root_post_id != next.root_post_id
                || previous.appended_post_ids != next.appended_post_ids
                || previous.history_rows.len() != next.history_rows.len()
                || previous
                    .history_rows
                    .iter()
                    .zip(&next.history_rows)
                    .any(|(previous, next)| row_fingerprint(previous) != row_fingerprint(next))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::test_support::{post, snapshot};
    use super::*;

    #[test]
    fn identical_snapshots_are_empty() {
        let previous = snapshot(&[post(1, None), post(2, Some(1))]);
        assert!(diff_snapshots(Some(&previous), None, &previous).is_none());
    }

    #[test]
    fn like_count_upserts_one_row() {
        let previous = snapshot(&[post(1, None), post(2, Some(1))]);
        let mut liked = [post(1, None), post(2, Some(1))];
        liked[1].like_count = 4;
        let next = snapshot(&liked);
        let diff = diff_snapshots(Some(&previous), None, &next).expect("liked");
        assert_eq!(diff.upserted_post_ids, vec![2]);
        assert!(!diff.order_changed);
        assert!(!diff.regions.status);
    }

    #[test]
    fn composer_only_change_has_no_rows() {
        let previous = snapshot(&[post(1, None)]);
        let mut next = previous.clone();
        next.composer.is_submitting = true;
        let diff = diff_snapshots(Some(&previous), None, &next).expect("composer");
        assert!(diff.regions.composer);
        assert!(diff.upserted_post_ids.is_empty());
        assert!(!diff.order_changed);
    }

    #[test]
    fn folding_changes_matches_full_snapshot() {
        let first = snapshot(&[post(1, None), post(2, Some(1))]);
        let mut liked = [post(1, None), post(2, Some(1))];
        liked[1].like_count = 3;
        let second = snapshot(&liked);
        let mut typed = second.clone();
        typed.composer.is_submitting = true;
        let mut more = [post(1, None), post(2, Some(1)), post(3, Some(1))];
        more[1].like_count = 3;
        let third = snapshot(&more);

        let mut mirror = None;
        for (previous, next) in [
            (None, &first),
            (Some(&first), &second),
            (Some(&second), &typed),
            (Some(&typed), &third),
        ] {
            let mut stamped = next.clone();
            stamped.generation = mirror
                .as_ref()
                .map(|m: &TopicDetailUiSnapshot| m.generation + 1)
                .unwrap_or(1);
            let diff = diff_snapshots(previous, None, next).expect("changed");
            let change = snapshot_change(
                Arc::new(stamped.clone()),
                previous.map(|previous| previous.generation),
                diff,
            );
            mirror = Some(apply_change(mirror, &change));
            let applied = mirror.as_ref().expect("mirror");
            assert_eq!(applied.rows, stamped.rows);
            assert_eq!(applied.composer, stamped.composer);
            assert_eq!(applied.chrome, stamped.chrome);
        }
    }
}
