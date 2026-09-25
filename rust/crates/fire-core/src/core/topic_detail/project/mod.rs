use std::collections::{HashMap, HashSet};

use fire_models::{
    TopicAiSummary, TopicDetailChrome, TopicDetailComposerModel, TopicDetailLoadError,
    TopicDetailNotice, TopicDetailPhase, TopicDetailReplyContext, TopicDetailSidecarModel,
    TopicDetailSourceSnapshot, TopicDetailTypingUser, TopicDetailUiRow, TopicDetailUiSnapshot,
    TopicHeader, TopicHomeRowCountPatch, TopicHomeUnreadDecision, TopicPost, TopicPresenceUser,
    TopicTreePresentation, TopicTreeRow,
};

mod checksum;
mod chrome;
mod row;

use chrome::{project_chrome, project_sidecar};
use row::{posts_by_id, project_row};

pub(crate) struct ProjectionChrome {
    pub phase: TopicDetailPhase,
    pub load_error: Option<TopicDetailLoadError>,
    pub notice: Option<TopicDetailNotice>,
    pub is_loading_more: bool,
    pub load_more_error: Option<String>,
    pub scroll_target_post_number: Option<u32>,
    pub summary: Option<TopicAiSummary>,
    pub summary_loading: bool,
    pub summary_error: Option<String>,
    pub typing_users: Vec<TopicPresenceUser>,
    pub current_user_id: Option<u64>,
    pub is_submitting: bool,
    pub mutating: HashSet<u64>,
    pub loading_reply_context: HashSet<u64>,
    pub reply_context: Option<TopicDetailReplyContext>,
    pub flag_types: Vec<fire_models::PostActionType>,
    pub home_row_patch: Option<TopicHomeRowCountPatch>,
    pub generation: u64,
    pub collection_revision: u64,
    pub chrome_revision: u64,
    pub sidecar_revision: u64,
    pub interaction_revision: u64,
}

pub(crate) fn project_topic_detail_snapshot(
    source: &TopicDetailSourceSnapshot,
    tree: &TopicTreePresentation,
    chrome: &ProjectionChrome,
) -> TopicDetailUiSnapshot {
    let posts = posts_by_id(source);
    let original_id = tree.original_post_id;
    let mut rows = Vec::new();
    if let Some(post) = posts
        .get(&original_id)
        .or_else(|| posts.get(&source.body.post.id))
    {
        rows.push(project_row(
            post,
            &TopicTreeRow {
                post_id: post.id,
                post_number: post.post_number,
                root_post_number: post.post_number,
                parent_post_number: None,
                depth: 0,
                preorder_index: 0,
                has_children: tree
                    .reply_rows
                    .iter()
                    .any(|row| row.parent_post_number == Some(post.post_number) || row.depth == 1),
                sibling_index: 0,
                is_last_sibling: true,
                descendant_count: post.reply_count,
            },
            true,
            chrome,
        ));
    }
    for tree_row in &tree.reply_rows {
        if tree_row.post_id == original_id {
            continue;
        }
        if let Some(post) = posts.get(&tree_row.post_id) {
            rows.push(project_row(post, tree_row, false, chrome));
        }
    }

    let header = &source.header;
    TopicDetailUiSnapshot {
        topic_id: header.topic_id,
        generation: chrome.generation,
        phase: chrome.phase,
        load_error: chrome.load_error.clone(),
        notice: chrome.notice.clone(),
        has_more: !source.source_exhausted,
        is_loading_more: chrome.is_loading_more,
        load_more_error: chrome.load_more_error.clone(),
        scroll_target_post_number: chrome.scroll_target_post_number,
        collection_revision: chrome.collection_revision,
        chrome_revision: chrome.chrome_revision,
        sidecar_revision: chrome.sidecar_revision,
        interaction_revision: chrome.interaction_revision,
        chrome: project_chrome(header),
        composer: TopicDetailComposerModel {
            typing_users: chrome
                .typing_users
                .iter()
                .filter(|user| Some(user.id) != chrome.current_user_id)
                .map(|user| TopicDetailTypingUser {
                    id: user.id,
                    username: user.username.clone(),
                    avatar_template: user.avatar_template.clone(),
                })
                .collect(),
            is_submitting: chrome.is_submitting,
        },
        sidecar: project_sidecar(chrome),
        rows,
        focused_reply_context: chrome.reply_context.clone(),
        flag_types: chrome.flag_types.clone(),
        home_row_patch: chrome.home_row_patch.clone(),
    }
}

pub(crate) fn project_history_rows(
    posts: &[TopicPost],
    root_post_number: u32,
    chrome: &ProjectionChrome,
) -> Vec<TopicDetailUiRow> {
    posts
        .iter()
        .map(|post| {
            project_row(
                post,
                &TopicTreeRow {
                    post_id: post.id,
                    post_number: post.post_number,
                    root_post_number,
                    parent_post_number: post.reply_to_post_number,
                    depth: 1,
                    preorder_index: 0,
                    has_children: post.reply_count > 0,
                    sibling_index: 0,
                    is_last_sibling: true,
                    descendant_count: post.reply_count,
                },
                false,
                chrome,
            )
        })
        .collect()
}

pub(crate) fn unread_decision(last_read: Option<u32>, highest: u32) -> TopicHomeUnreadDecision {
    match last_read {
        None => TopicHomeUnreadDecision::WhenLastReadMissing,
        Some(last_read) if last_read >= highest => TopicHomeUnreadDecision::CaughtUp,
        Some(_) => TopicHomeUnreadDecision::StillUnread,
    }
}

pub(crate) fn home_row_patch_for_header(header: &TopicHeader) -> TopicHomeRowCountPatch {
    TopicHomeRowCountPatch {
        topic_id: header.topic_id,
        posts_count: header.posts_count,
        reply_count: header.reply_count,
        views: header.views,
        last_read_post_number: header.last_read_post_number,
        highest_post_number: header.highest_post_number,
        unread: unread_decision(header.last_read_post_number, header.highest_post_number),
    }
}

pub(crate) fn header_counts_changed(previous: &TopicHeader, next: &TopicHeader) -> bool {
    previous.posts_count != next.posts_count
        || previous.reply_count != next.reply_count
        || previous.views != next.views
        || previous.last_read_post_number != next.last_read_post_number
        || previous.highest_post_number != next.highest_post_number
}

/// Applies the patched-row unread formula. `has_unread_posts` is the row flag.
pub(crate) fn apply_home_unread_counts(
    has_unread_posts: bool,
    decision: TopicHomeUnreadDecision,
    unread_posts: u32,
    new_posts: u32,
) -> (u32, u32, bool) {
    match decision {
        TopicHomeUnreadDecision::WhenLastReadMissing => {
            if has_unread_posts {
                (unread_posts, new_posts, has_unread_posts)
            } else {
                (0, 0, has_unread_posts)
            }
        }
        TopicHomeUnreadDecision::CaughtUp => (0, 0, false),
        TopicHomeUnreadDecision::StillUnread => (unread_posts, new_posts, true),
    }
}

pub(crate) fn apply_patch_to_summary(
    summary: &mut fire_models::TopicSummary,
    patch: &TopicHomeRowCountPatch,
    row_has_unread: Option<bool>,
) {
    summary.posts_count = patch.posts_count;
    summary.reply_count = patch.reply_count;
    summary.views = patch.views;
    summary.last_read_post_number = patch.last_read_post_number;
    summary.highest_post_number = patch.highest_post_number;
    let has_unread = row_has_unread.unwrap_or(summary.unread_posts > 0 || summary.new_posts > 0);
    let (unread_posts, new_posts, _) = apply_home_unread_counts(
        has_unread,
        patch.unread,
        summary.unread_posts,
        summary.new_posts,
    );
    summary.unread_posts = unread_posts;
    summary.new_posts = new_posts;
}

pub(crate) fn apply_patch_to_row(row: &mut fire_models::TopicRow, patch: &TopicHomeRowCountPatch) {
    let (unread_posts, new_posts, has_unread) = apply_home_unread_counts(
        row.has_unread_posts,
        patch.unread,
        row.topic.unread_posts,
        row.topic.new_posts,
    );
    row.topic.posts_count = patch.posts_count;
    row.topic.reply_count = patch.reply_count;
    row.topic.views = patch.views;
    row.topic.last_read_post_number = patch.last_read_post_number;
    row.topic.highest_post_number = patch.highest_post_number;
    row.topic.unread_posts = unread_posts;
    row.topic.new_posts = new_posts;
    row.has_unread_posts = has_unread;
}

pub(crate) fn structure_changed(
    previous: Option<&TopicDetailUiSnapshot>,
    next: &TopicDetailUiSnapshot,
) -> bool {
    let Some(previous) = previous else {
        return true;
    };
    previous.phase != next.phase
        || previous.load_error != next.load_error
        || previous.has_more != next.has_more
        || previous.is_loading_more != next.is_loading_more
        || previous.load_more_error != next.load_more_error
        || previous
            .rows
            .iter()
            .map(|row| row.post_id)
            .collect::<Vec<_>>()
            != next.rows.iter().map(|row| row.post_id).collect::<Vec<_>>()
}

pub(crate) fn layout_checksums_changed(
    previous: Option<&TopicDetailUiSnapshot>,
    next: &TopicDetailUiSnapshot,
) -> bool {
    let Some(previous) = previous else {
        return !next.rows.is_empty();
    };
    let previous_rows = previous
        .rows
        .iter()
        .map(|row| (row.post_id, row.layout_checksum))
        .collect::<HashMap<_, _>>();
    next.rows.iter().any(|row| {
        previous_rows
            .get(&row.post_id)
            .is_none_or(|checksum| *checksum != row.layout_checksum)
    })
}

pub(crate) fn interaction_checksums_changed(
    previous: Option<&TopicDetailUiSnapshot>,
    next: &TopicDetailUiSnapshot,
) -> bool {
    let Some(previous) = previous else {
        return false;
    };
    let previous_rows = previous
        .rows
        .iter()
        .map(|row| (row.post_id, row.interaction_checksum))
        .collect::<HashMap<_, _>>();
    next.rows.iter().any(|row| {
        previous_rows
            .get(&row.post_id)
            .is_some_and(|checksum| *checksum != row.interaction_checksum)
    }) || previous.composer != next.composer
}

pub(crate) fn chrome_fields_changed(
    previous: &TopicDetailChrome,
    next: &TopicDetailChrome,
) -> bool {
    previous.title != next.title
        || previous.slug != next.slug
        || previous.bookmarked != next.bookmarked
        || previous.bookmark_id != next.bookmark_id
        || previous.bookmark_name != next.bookmark_name
        || previous.bookmark_reminder_at != next.bookmark_reminder_at
        || previous.notification_level != next.notification_level
        || previous.can_edit != next.can_edit
        || previous.category_id != next.category_id
        || previous.tags != next.tags
        || previous.vote_count != next.vote_count
        || previous.user_voted != next.user_voted
        || previous.can_vote != next.can_vote
        || previous.has_accepted_answer != next.has_accepted_answer
        || previous.participants != next.participants
}

pub(crate) fn sidecar_changed(
    previous: &TopicDetailSidecarModel,
    next: &TopicDetailSidecarModel,
    previous_notice: &Option<TopicDetailNotice>,
    next_notice: &Option<TopicDetailNotice>,
) -> bool {
    previous != next || previous_notice != next_notice
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn when_last_read_missing_zeros_counts_when_has_unread_is_false() {
        let (unread, new_posts, flag) =
            apply_home_unread_counts(false, TopicHomeUnreadDecision::WhenLastReadMissing, 4, 2);
        assert_eq!((unread, new_posts, flag), (0, 0, false));
    }

    #[test]
    fn when_last_read_missing_keeps_counts_when_has_unread_is_true() {
        let (unread, new_posts, flag) =
            apply_home_unread_counts(true, TopicHomeUnreadDecision::WhenLastReadMissing, 4, 2);
        assert_eq!((unread, new_posts, flag), (4, 2, true));
    }

    #[test]
    fn caught_up_zeros_and_clears_flag() {
        let (unread, new_posts, flag) =
            apply_home_unread_counts(true, TopicHomeUnreadDecision::CaughtUp, 3, 1);
        assert_eq!((unread, new_posts, flag), (0, 0, false));
    }
}
