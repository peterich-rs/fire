use std::collections::{HashMap, HashSet};

use fire_models::{
    TopicAiSummary, TopicDetailChrome, TopicDetailComposerModel, TopicDetailLoadError,
    TopicDetailNotice, TopicDetailPhase, TopicDetailReplyContext, TopicDetailSidecarModel,
    TopicDetailSourceSnapshot, TopicDetailTypingUser, TopicDetailUiRow, TopicDetailUiSnapshot,
    TopicHeader, TopicHomeRowCountPatch, TopicHomeUnreadDecision, TopicPost, TopicPresenceUser,
    TopicTreePresentation, TopicTreeRow,
};

mod cache;
mod checksum;
mod chrome;
mod diff;
mod row;

use chrome::{project_chrome, project_sidecar};
use row::{posts_by_id, project_row};

pub(crate) use cache::ProjectedRowCache;
pub(crate) use diff::{build_published_index, diff_snapshots, snapshot_change, PublishedRowIndex};

#[cfg(test)]
pub(crate) use diff::apply_change;

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
            &original_tree_row(post, tree),
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
    // Generation and revisions stay zero until `ActorState::assign_revisions`
    // stamps them; nothing may publish an unstamped snapshot.
    TopicDetailUiSnapshot {
        topic_id: header.topic_id,
        generation: 0,
        phase: chrome.phase,
        load_error: chrome.load_error.clone(),
        notice: chrome.notice.clone(),
        has_more: !source.source_exhausted,
        is_loading_more: chrome.is_loading_more,
        load_more_error: chrome.load_more_error.clone(),
        scroll_target_post_number: chrome.scroll_target_post_number,
        collection_revision: 0,
        chrome_revision: 0,
        sidecar_revision: 0,
        interaction_revision: 0,
        composer_revision: 0,
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

pub(crate) struct ProjectedPostSource<'a> {
    pub header: &'a TopicHeader,
    pub body_post: &'a TopicPost,
    pub posts_by_id: &'a HashMap<u64, TopicPost>,
    pub tree: &'a TopicTreePresentation,
    pub versions: &'a HashMap<u64, u64>,
    pub source_exhausted: bool,
}

pub(crate) fn project_topic_detail_snapshot_from_posts(
    source: ProjectedPostSource<'_>,
    chrome: &ProjectionChrome,
    cache: &mut ProjectedRowCache,
) -> TopicDetailUiSnapshot {
    let original_id = source.tree.original_post_id;
    let mut rows = Vec::new();
    if let Some(post) = source
        .posts_by_id
        .get(&original_id)
        .or_else(|| source.posts_by_id.get(&source.body_post.id))
    {
        rows.push(project_cached_row(
            post,
            &original_tree_row(post, source.tree),
            true,
            chrome,
            source.versions.get(&post.id).copied().unwrap_or(0),
            cache,
        ));
    }
    for tree_row in &source.tree.reply_rows {
        if tree_row.post_id == original_id {
            continue;
        }
        if let Some(post) = source.posts_by_id.get(&tree_row.post_id) {
            rows.push(project_cached_row(
                post,
                tree_row,
                false,
                chrome,
                source.versions.get(&post.id).copied().unwrap_or(0),
                cache,
            ));
        }
    }
    cache.retain_ids(rows.iter().map(|row| row.post_id));

    TopicDetailUiSnapshot {
        topic_id: source.header.topic_id,
        generation: 0,
        phase: chrome.phase,
        load_error: chrome.load_error.clone(),
        notice: chrome.notice.clone(),
        has_more: !source.source_exhausted,
        is_loading_more: chrome.is_loading_more,
        load_more_error: chrome.load_more_error.clone(),
        scroll_target_post_number: chrome.scroll_target_post_number,
        collection_revision: 0,
        chrome_revision: 0,
        sidecar_revision: 0,
        interaction_revision: 0,
        composer_revision: 0,
        chrome: project_chrome(source.header),
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

fn original_tree_row(post: &TopicPost, tree: &TopicTreePresentation) -> TopicTreeRow {
    TopicTreeRow {
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
    }
}

fn project_cached_row(
    post: &TopicPost,
    tree_row: &TopicTreeRow,
    is_original_post: bool,
    chrome: &ProjectionChrome,
    version: u64,
    cache: &mut ProjectedRowCache,
) -> TopicDetailUiRow {
    if let Some(row) = cache.take(post, tree_row, is_original_post, chrome, version) {
        return row;
    }
    let row = project_row(post, tree_row, is_original_post, chrome);
    cache.insert(
        post.id,
        version,
        tree_row,
        is_original_post,
        chrome,
        row.clone(),
    );
    row
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
        unread_posts: None,
        new_posts: None,
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
        patch.unread_posts.unwrap_or(summary.unread_posts),
        patch.new_posts.unwrap_or(summary.new_posts),
    );
    summary.unread_posts = unread_posts;
    summary.new_posts = new_posts;
}

pub(crate) fn apply_patch_to_row(row: &mut fire_models::TopicRow, patch: &TopicHomeRowCountPatch) {
    let (unread_posts, new_posts, has_unread) = apply_home_unread_counts(
        row.has_unread_posts,
        patch.unread,
        patch.unread_posts.unwrap_or(row.topic.unread_posts),
        patch.new_posts.unwrap_or(row.topic.new_posts),
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

/// Structure covers everything hosts use to plan the reply list: row order,
/// tree shape, and `reply_count` (reply-thread shortcut counts). Row content
/// is covered by the layout and interaction checksums.
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
        || previous.rows.len() != next.rows.len()
        || previous
            .rows
            .iter()
            .zip(&next.rows)
            .any(|(previous, next)| row_shape(previous) != row_shape(next))
}

pub(crate) type RowShape = (u64, u32, u32, Option<u32>, u16, bool, bool, u32, u32, bool);

pub(crate) fn row_shape(row: &TopicDetailUiRow) -> RowShape {
    (
        row.post_id,
        row.post_number,
        row.root_post_number,
        row.parent_post_number,
        row.depth,
        row.has_children,
        row.is_last_sibling,
        row.descendant_count,
        row.reply_count,
        row.is_original_post,
    )
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
    })
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
pub(crate) mod test_support {
    use std::collections::HashSet;

    use fire_models::{
        TopicBody, TopicDetailPhase, TopicDetailSourceSnapshot, TopicDetailUiSnapshot, TopicHeader,
        TopicPost,
    };

    use super::super::super::topics::build_topic_tree_presentation_from_source_snapshot;
    use super::{project_topic_detail_snapshot, ProjectionChrome};

    pub(crate) fn projection_chrome() -> ProjectionChrome {
        ProjectionChrome {
            phase: TopicDetailPhase::Ready,
            load_error: None,
            notice: None,
            is_loading_more: false,
            load_more_error: None,
            scroll_target_post_number: None,
            summary: None,
            summary_loading: false,
            summary_error: None,
            typing_users: Vec::new(),
            current_user_id: None,
            is_submitting: false,
            mutating: HashSet::new(),
            loading_reply_context: HashSet::new(),
            reply_context: None,
            flag_types: Vec::new(),
            home_row_patch: None,
        }
    }

    pub(crate) fn post(id: u64, reply_to_post_number: Option<u32>) -> TopicPost {
        TopicPost {
            id,
            username: format!("user-{id}"),
            post_number: id as u32,
            reply_to_post_number,
            ..TopicPost::default()
        }
    }

    /// The first post is the body.
    pub(crate) fn snapshot(posts: &[TopicPost]) -> TopicDetailUiSnapshot {
        let source = TopicDetailSourceSnapshot {
            header: TopicHeader {
                topic_id: 42,
                posts_count: posts.len() as u32,
                ..TopicHeader::default()
            },
            body: TopicBody {
                post: posts.first().cloned().unwrap_or_default(),
            },
            raw_stream_ids: posts.iter().map(|post| post.id).collect(),
            loaded_posts: posts.to_vec(),
            ..TopicDetailSourceSnapshot::default()
        };
        let tree = build_topic_tree_presentation_from_source_snapshot(&source);
        project_topic_detail_snapshot(&source, &tree, &projection_chrome())
    }
}

#[cfg(test)]
mod tests {
    use fire_models::{Poll, PollOption, TopicReplyToUser};

    use super::test_support::{post, snapshot};
    use super::*;

    fn reply_row(reply: &TopicPost) -> TopicDetailUiRow {
        snapshot(&[post(1, None), reply.clone()]).rows[1].clone()
    }

    #[test]
    fn structure_tracks_reply_counts_and_tree_shape() {
        let base = [post(1, None), post(2, Some(1)), post(3, Some(1))];
        let previous = snapshot(&base);
        assert!(!structure_changed(Some(&previous), &snapshot(&base)));

        let mut replied = base.clone();
        replied[1].reply_count = 4;
        assert!(structure_changed(Some(&previous), &snapshot(&replied)));

        let mut reparented = base.clone();
        reparented[2].reply_to_post_number = Some(2);
        assert!(structure_changed(Some(&previous), &snapshot(&reparented)));
    }

    #[test]
    fn row_checksums_cover_every_rendered_field() {
        let base = post(2, Some(1));
        let original = reply_row(&base);
        let poll = Poll {
            id: 7,
            name: "poll".into(),
            options: vec![PollOption {
                id: "a".into(),
                html: "A".into(),
                plain_text: "A".into(),
                votes: 1,
            }],
            ..Poll::default()
        };
        let cases = [
            (
                "post_type",
                TopicPost {
                    post_type: 2,
                    ..base.clone()
                },
            ),
            (
                "can_accept_answer",
                TopicPost {
                    can_accept_answer: true,
                    ..base.clone()
                },
            ),
            (
                "can_unaccept_answer",
                TopicPost {
                    can_unaccept_answer: true,
                    ..base.clone()
                },
            ),
            (
                "reply_to_user",
                TopicPost {
                    reply_to_user: Some(TopicReplyToUser {
                        username: "bob".into(),
                        name: None,
                        avatar_template: None,
                    }),
                    ..base.clone()
                },
            ),
            (
                "polls",
                TopicPost {
                    polls: vec![poll],
                    ..base.clone()
                },
            ),
        ];
        for (field, changed) in cases {
            let next = reply_row(&changed);
            assert!(
                next.layout_checksum != original.layout_checksum
                    || next.interaction_checksum != original.interaction_checksum,
                "{field} is not covered by the row checksums"
            );
        }
    }

    #[test]
    fn poll_changes_are_layout_only() {
        let base = post(2, Some(1));
        let mut voted = base.clone();
        voted.polls = vec![Poll {
            id: 7,
            name: "poll".into(),
            voters: 3,
            ..Poll::default()
        }];
        let previous = snapshot(&[post(1, None), base]);
        let next = snapshot(&[post(1, None), voted]);
        assert!(!structure_changed(Some(&previous), &next));
        assert!(layout_checksums_changed(Some(&previous), &next));
        assert!(!interaction_checksums_changed(Some(&previous), &next));
    }

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
