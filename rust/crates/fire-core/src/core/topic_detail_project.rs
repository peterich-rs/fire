use std::collections::{HashMap, HashSet};

use fire_models::{
    TopicAiSummary, TopicDetailAuthorDisplay, TopicDetailBoostDisplay, TopicDetailBoostUserDisplay,
    TopicDetailChrome, TopicDetailComposerModel, TopicDetailLoadError, TopicDetailNotice,
    TopicDetailParticipantDisplay, TopicDetailPhase, TopicDetailPollDisplay,
    TopicDetailReactionChip, TopicDetailReplyContext, TopicDetailReplyUserDisplay,
    TopicDetailSidecarModel, TopicDetailSourceSnapshot, TopicDetailTypingUser, TopicDetailUiRow,
    TopicDetailUiSnapshot, TopicHeader, TopicHomeRowCountPatch, TopicHomeUnreadDecision, TopicPost,
    TopicPresenceUser, TopicTreePresentation, TopicTreeRow,
};

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

fn project_sidecar(chrome: &ProjectionChrome) -> TopicDetailSidecarModel {
    match &chrome.summary {
        Some(summary) => TopicDetailSidecarModel {
            summarized_text: Some(summary.summarized_text.clone()),
            algorithm: summary.algorithm.clone(),
            outdated: summary.outdated,
            can_regenerate: summary.can_regenerate,
            new_posts_since_summary: summary.new_posts_since_summary,
            updated_at: summary.updated_at.clone(),
            is_loading: chrome.summary_loading,
            error: chrome.summary_error.clone(),
        },
        None => TopicDetailSidecarModel {
            summarized_text: None,
            is_loading: chrome.summary_loading,
            error: chrome.summary_error.clone(),
            ..TopicDetailSidecarModel::default()
        },
    }
}

fn project_chrome(header: &TopicHeader) -> TopicDetailChrome {
    TopicDetailChrome {
        title: header.title.clone(),
        slug: header.slug.clone(),
        archetype: header.archetype.clone(),
        bookmarked: header.bookmarked,
        bookmark_id: header.bookmark_id,
        bookmark_name: header.bookmark_name.clone(),
        bookmark_reminder_at: header.bookmark_reminder_at.clone(),
        notification_level: header.details.notification_level,
        can_edit: header.details.can_edit,
        category_id: header.category_id,
        tags: header.tags.iter().map(|tag| tag.name.clone()).collect(),
        views: header.views,
        posts_count: header.posts_count,
        reply_count: header.reply_count,
        like_count: header.like_count,
        vote_count: header.vote_count,
        user_voted: header.user_voted,
        can_vote: header.can_vote,
        has_accepted_answer: header.has_accepted_answer,
        created_at: header.created_at.clone(),
        highest_post_number: header.highest_post_number,
        last_read_post_number: header.last_read_post_number,
        participants: header
            .details
            .participants
            .iter()
            .map(|participant| TopicDetailParticipantDisplay {
                user_id: participant.user_id,
                username: participant.username.clone().unwrap_or_default(),
                name: participant.name.clone(),
            })
            .collect(),
        summarizable: header.summarizable,
    }
}

fn project_row(
    post: &TopicPost,
    tree_row: &TopicTreeRow,
    is_original_post: bool,
    chrome: &ProjectionChrome,
) -> TopicDetailUiRow {
    let selected_id = post
        .current_user_reaction
        .as_ref()
        .map(|reaction| reaction.id.clone());
    let reactions = post
        .reactions
        .iter()
        .map(|reaction| {
            TopicDetailReactionChip::from_reaction(
                reaction,
                Some(&reaction.id) == selected_id.as_ref(),
            )
        })
        .collect::<Vec<_>>();
    let author = author_display(post);
    let polls = post
        .polls
        .iter()
        .map(TopicDetailPollDisplay::from)
        .collect::<Vec<_>>();
    let boosts = post
        .boosts
        .iter()
        .map(|boost| TopicDetailBoostDisplay {
            id: boost.id,
            display_text: boost.display_text.clone(),
            user: TopicDetailBoostUserDisplay {
                id: boost.user.id,
                username: boost.user.username.clone(),
                name: boost.user.name.clone(),
                avatar_template: boost.user.avatar_template.clone(),
            },
            can_delete: boost.can_delete,
            can_flag: boost.can_flag,
            user_flag_status: boost.user_flag_status,
            available_flags: boost.available_flags.clone(),
            presentation: boost.presented.clone(),
        })
        .collect::<Vec<_>>();
    let is_mutating = chrome.mutating.contains(&post.id);
    let is_loading_reply_context = chrome.loading_reply_context.contains(&post.id);
    let mut row = TopicDetailUiRow {
        post_id: post.id,
        post_number: post.post_number,
        root_post_number: tree_row.root_post_number,
        parent_post_number: tree_row.parent_post_number,
        depth: tree_row.depth,
        has_children: tree_row.has_children,
        is_last_sibling: tree_row.is_last_sibling,
        descendant_count: tree_row.descendant_count,
        author: author.clone(),
        presentation: post.presented.clone(),
        layout_checksum: 0,
        interaction_checksum: 0,
        created_at: post.created_at.clone(),
        updated_at: post.updated_at.clone(),
        post_type: post.post_type,
        reply_count: post.reply_count,
        reply_to_username: post
            .reply_to_user
            .as_ref()
            .map(|user| user.username.clone())
            .or_else(|| post.reply_to_post_number.map(|number| format!("#{number}"))),
        reply_to_user: post
            .reply_to_user
            .as_ref()
            .map(|user| TopicDetailReplyUserDisplay {
                username: user.username.clone(),
                name: user.name.clone(),
                avatar_template: user.avatar_template.clone(),
            }),
        like_count: post.like_count,
        reactions,
        current_reaction_id: selected_id,
        polls,
        boosts,
        accepted_answer: post.accepted_answer,
        can_accept_answer: post.can_accept_answer,
        can_unaccept_answer: post.can_unaccept_answer,
        can_edit: post.can_edit,
        can_delete: post.can_delete,
        can_recover: post.can_recover,
        can_boost: post.can_boost,
        bookmarked: post.bookmarked,
        bookmark_id: post.bookmark_id,
        bookmark_name: post.bookmark_name.clone(),
        bookmark_reminder_at: post.bookmark_reminder_at.clone(),
        hidden: post.hidden,
        is_mutating,
        is_loading_reply_context,
        is_original_post,
    };
    row.layout_checksum = layout_checksum(&row);
    row.interaction_checksum = interaction_checksum(&row);
    row
}

fn author_display(post: &TopicPost) -> TopicDetailAuthorDisplay {
    let metadata = &post.author_metadata;
    TopicDetailAuthorDisplay {
        username: post.username.clone(),
        name: post.name.clone(),
        avatar_template: post.avatar_template.clone(),
        user_id: metadata.user_id,
        user_title: metadata.user_title.clone(),
        primary_group_name: metadata.primary_group_name.clone(),
        flair_url: metadata.flair_url.clone(),
        flair_name: metadata.flair_name.clone(),
        flair_bg_color: metadata.flair_bg_color.clone(),
        flair_color: metadata.flair_color.clone(),
        flair_group_id: metadata.flair_group_id,
        moderator: metadata.moderator,
        admin: metadata.admin,
        group_moderator: metadata.group_moderator,
        user_status_emoji: metadata.user_status_emoji.clone(),
        user_status_description: metadata.user_status_description.clone(),
    }
}

fn posts_by_id(source: &TopicDetailSourceSnapshot) -> HashMap<u64, TopicPost> {
    let mut posts = HashMap::new();
    posts.insert(source.body.post.id, source.body.post.clone());
    for post in &source.loaded_posts {
        posts.insert(post.id, post.clone());
    }
    posts
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

fn layout_checksum(row: &TopicDetailUiRow) -> u64 {
    let mut hasher = Hasher::new();
    hasher.u64(row.post_id);
    hash_author(&mut hasher, &row.author);
    hasher.sep();
    match row.presentation.get() {
        Some(document) => hasher.u64(document.presentation().checksum),
        None => hasher.str("pending"),
    }
    hasher.sep();
    hash_polls(&mut hasher, &row.polls);
    hasher.sep();
    hash_boosts(&mut hasher, &row.boosts);
    hasher.sep();
    hasher.bool(row.reactions.is_empty());
    hasher.finish()
}

fn interaction_checksum(row: &TopicDetailUiRow) -> u64 {
    let mut hasher = Hasher::new();
    hasher.u64(u64::from(row.post_number));
    hasher.sep();
    hasher.str(&row.author.username);
    hasher.sep();
    hasher.str(row.author.avatar_template.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(row.created_at.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(row.updated_at.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.u64(u64::from(row.like_count));
    hasher.sep();
    hasher.u64(u64::from(row.reply_count));
    hasher.sep();
    for reaction in &row.reactions {
        hasher.str(&reaction.id);
        hasher.sep();
        hasher.str(reaction.kind.as_deref().unwrap_or(""));
        hasher.sep();
        hasher.u64(u64::from(reaction.count));
        hasher.sep();
        match reaction.can_undo {
            Some(value) => hasher.bool(value),
            None => hasher.str(""),
        }
        hasher.sep();
    }
    hasher.str(row.current_reaction_id.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.bool(row.accepted_answer);
    hasher.bool(row.can_edit);
    hasher.bool(row.can_delete);
    hasher.bool(row.can_recover);
    hasher.bool(row.hidden);
    hasher.bool(row.bookmarked);
    hasher.u64(row.bookmark_id.unwrap_or(0));
    hasher.str(row.bookmark_name.as_deref().unwrap_or(""));
    hasher.str(row.bookmark_reminder_at.as_deref().unwrap_or(""));
    hasher.bool(row.is_mutating);
    hasher.bool(row.is_loading_reply_context);
    hasher.finish()
}

fn hash_author(hasher: &mut Hasher, author: &TopicDetailAuthorDisplay) {
    hasher.str(&author.username);
    hasher.sep();
    hasher.str(author.name.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.user_title.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.primary_group_name.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.flair_name.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.u64(author.user_id.unwrap_or(0));
    hasher.sep();
    hasher.str(author.flair_url.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.flair_bg_color.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.flair_color.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.u64(author.flair_group_id.unwrap_or(0));
    hasher.sep();
    hasher.bool(author.admin);
    hasher.bool(author.moderator);
    hasher.bool(author.group_moderator);
    hasher.str(author.user_status_emoji.as_deref().unwrap_or(""));
    hasher.str(author.user_status_description.as_deref().unwrap_or(""));
}

fn hash_polls(hasher: &mut Hasher, polls: &[TopicDetailPollDisplay]) {
    for poll in polls {
        hasher.u64(poll.id);
        hasher.str(&poll.name);
        hasher.str(&poll.kind);
        hasher.str(&poll.status);
        hasher.str(&poll.results);
        hasher.u64(u64::from(poll.voters));
        for vote in &poll.user_votes {
            hasher.str(vote);
        }
        for option in &poll.options {
            hasher.str(&option.id);
            hasher.str(&option.html);
            hasher.u64(u64::from(option.votes));
        }
        hasher.sep();
    }
}

fn hash_boosts(hasher: &mut Hasher, boosts: &[TopicDetailBoostDisplay]) {
    for boost in boosts {
        hasher.u64(boost.id);
        hasher.str(&boost.user.username);
        hasher.str(boost.user.name.as_deref().unwrap_or(""));
        hasher.str(&boost.display_text);
        let plain = boost
            .presentation
            .get()
            .map(|document| document.presentation().plain_text.clone())
            .unwrap_or_default();
        hasher.str(&plain);
        hasher.bool(boost.can_delete);
        hasher.bool(boost.can_flag);
        hasher.sep();
    }
}

struct Hasher(u64);

impl Hasher {
    fn new() -> Self {
        Self(0xcbf29ce484222325)
    }

    fn byte(&mut self, byte: u8) {
        self.0 ^= u64::from(byte);
        self.0 = self.0.wrapping_mul(0x100000001b3);
    }

    fn str(&mut self, value: &str) {
        for byte in value.as_bytes() {
            self.byte(*byte);
        }
        self.byte(0);
    }

    fn u64(&mut self, value: u64) {
        for byte in value.to_le_bytes() {
            self.byte(byte);
        }
    }

    fn bool(&mut self, value: bool) {
        self.byte(u8::from(value));
    }

    fn sep(&mut self) {
        self.byte(0x1f);
    }

    fn finish(self) -> u64 {
        self.0
    }
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
