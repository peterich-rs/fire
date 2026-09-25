use fire_models::{
    LoadMoreTopicPostsQuery, TopicBody, TopicDetail, TopicDetailCreatedBy, TopicDetailMeta,
    TopicDetailPage, TopicDetailSourceQuery, TopicDetailSourceSnapshot, TopicHeader,
    TopicLoadMoreOutcome, TopicLoadMoreStopReason, TopicTreePresentation, TopicTreeRow,
};

use super::list::{TopicLoadedRangeState, TopicSourceCursorState};
use super::post::{
    topic_post_state_from_model, topic_post_stream_state_from_model, TopicPostState,
    TopicPostStreamState,
};
use fire_uniffi_types::{TopicParticipantState, TopicTagState};

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailSourceQueryState {
    pub topic_id: u64,
    pub target_post_number: Option<u32>,
    pub allow_suggested_unread_root: bool,
    pub track_visit: bool,
    pub force_load: bool,
    pub initial_batch_size: u16,
    pub load_more_batch_size: u16,
    pub max_auto_batches_per_gesture: u8,
    pub max_auto_posts_per_gesture: u16,
}

impl From<TopicDetailSourceQueryState> for TopicDetailSourceQuery {
    fn from(value: TopicDetailSourceQueryState) -> Self {
        Self {
            topic_id: value.topic_id,
            target_post_number: value.target_post_number,
            allow_suggested_unread_root: value.allow_suggested_unread_root,
            track_visit: value.track_visit,
            force_load: value.force_load,
            initial_batch_size: value.initial_batch_size,
            load_more_batch_size: value.load_more_batch_size,
            max_auto_batches_per_gesture: value.max_auto_batches_per_gesture,
            max_auto_posts_per_gesture: value.max_auto_posts_per_gesture,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailSourceSnapshotState {
    pub header: TopicHeaderState,
    pub body: TopicBodyState,
    pub raw_stream_ids: Vec<u64>,
    pub loaded_posts: Vec<TopicPostState>,
    pub loaded_ranges: Vec<TopicLoadedRangeState>,
    pub source_cursor: Option<TopicSourceCursorState>,
    pub source_exhausted: bool,
    pub focused_post_number: Option<u32>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LoadMoreTopicPostsQueryState {
    pub cursor: TopicSourceCursorState,
}

impl From<LoadMoreTopicPostsQueryState> for LoadMoreTopicPostsQuery {
    fn from(value: LoadMoreTopicPostsQueryState) -> Self {
        Self {
            cursor: value.cursor.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailCreatedByState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicDetailCreatedBy> for TopicDetailCreatedByState {
    fn from(value: TopicDetailCreatedBy) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailMetaState {
    pub notification_level: Option<i32>,
    pub can_edit: bool,
    pub created_by: Option<TopicDetailCreatedByState>,
    pub participants: Vec<TopicParticipantState>,
}

impl From<TopicDetailMeta> for TopicDetailMetaState {
    fn from(value: TopicDetailMeta) -> Self {
        Self {
            notification_level: value.notification_level,
            can_edit: value.can_edit,
            created_by: value.created_by.map(Into::into),
            participants: value.participants.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicHeaderState {
    pub topic_id: u64,
    pub message_bus_last_id: Option<i64>,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub reply_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTagState>,
    pub views: u32,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub highest_post_number: u32,
    pub last_read_post_number: Option<u32>,
    pub bookmarks: Vec<u64>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub accepted_answer: bool,
    pub has_accepted_answer: bool,
    pub can_vote: bool,
    pub vote_count: i32,
    pub user_voted: bool,
    pub summarizable: bool,
    pub has_cached_summary: bool,
    pub has_summary: bool,
    pub archetype: Option<String>,
    pub details: TopicDetailMetaState,
}

impl From<TopicHeader> for TopicHeaderState {
    fn from(value: TopicHeader) -> Self {
        Self {
            topic_id: value.topic_id,
            message_bus_last_id: value.message_bus_last_id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            reply_count: value.reply_count,
            category_id: value.category_id,
            tags: value.tags.into_iter().map(Into::into).collect(),
            views: value.views,
            like_count: value.like_count,
            created_at: value.created_at,
            highest_post_number: value.highest_post_number,
            last_read_post_number: value.last_read_post_number,
            bookmarks: value.bookmarks,
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            accepted_answer: value.accepted_answer,
            has_accepted_answer: value.has_accepted_answer,
            can_vote: value.can_vote,
            vote_count: value.vote_count,
            user_voted: value.user_voted,
            summarizable: value.summarizable,
            has_cached_summary: value.has_cached_summary,
            has_summary: value.has_summary,
            archetype: value.archetype,
            details: value.details.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicBodyState {
    pub post: TopicPostState,
}

fn topic_body_state_from_model(value: TopicBody, base_url: &str) -> TopicBodyState {
    TopicBodyState {
        post: topic_post_state_from_model(value.post, base_url),
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTreeRowState {
    pub post_id: u64,
    pub post_number: u32,
    pub root_post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u16,
    pub preorder_index: u32,
    pub has_children: bool,
    pub descendant_count: u32,
    pub sibling_index: u16,
    pub is_last_sibling: bool,
}

fn topic_tree_row_state_from_model(value: TopicTreeRow) -> TopicTreeRowState {
    TopicTreeRowState {
        post_id: value.post_id,
        post_number: value.post_number,
        root_post_number: value.root_post_number,
        parent_post_number: value.parent_post_number,
        depth: value.depth,
        preorder_index: value.preorder_index,
        has_children: value.has_children,
        descendant_count: value.descendant_count,
        sibling_index: value.sibling_index,
        is_last_sibling: value.is_last_sibling,
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTreePresentationState {
    pub original_post_id: u64,
    pub original_post_number: u32,
    pub reply_rows: Vec<TopicTreeRowState>,
    pub total_loaded_post_count: u32,
    pub visible_root_post_numbers: Vec<u32>,
    pub first_unread_root_post_number: Option<u32>,
    pub gained_new_root_progress: bool,
}

pub(crate) fn topic_tree_presentation_state_from_model(
    value: TopicTreePresentation,
) -> TopicTreePresentationState {
    TopicTreePresentationState {
        original_post_id: value.original_post_id,
        original_post_number: value.original_post_number,
        reply_rows: value
            .reply_rows
            .into_iter()
            .map(topic_tree_row_state_from_model)
            .collect(),
        total_loaded_post_count: value.total_loaded_post_count,
        visible_root_post_numbers: value.visible_root_post_numbers,
        first_unread_root_post_number: value.first_unread_root_post_number,
        gained_new_root_progress: value.gained_new_root_progress,
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailPageState {
    pub source_snapshot: TopicDetailSourceSnapshotState,
    pub tree_presentation: TopicTreePresentationState,
}

pub fn topic_detail_page_state_from_model(
    value: TopicDetailPage,
    base_url: &str,
) -> TopicDetailPageState {
    TopicDetailPageState {
        source_snapshot: topic_detail_source_snapshot_state_from_model(
            value.source_snapshot,
            base_url,
        ),
        tree_presentation: topic_tree_presentation_state_from_model(value.tree_presentation),
    }
}

pub fn topic_detail_source_snapshot_state_from_model(
    value: TopicDetailSourceSnapshot,
    base_url: &str,
) -> TopicDetailSourceSnapshotState {
    TopicDetailSourceSnapshotState {
        header: value.header.into(),
        body: topic_body_state_from_model(value.body, base_url),
        raw_stream_ids: value.raw_stream_ids,
        loaded_posts: value
            .loaded_posts
            .into_iter()
            .map(|post| topic_post_state_from_model(post, base_url))
            .collect(),
        loaded_ranges: value.loaded_ranges.into_iter().map(Into::into).collect(),
        source_cursor: value.source_cursor.map(Into::into),
        source_exhausted: value.source_exhausted,
        focused_post_number: value.focused_post_number,
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum TopicLoadMoreStopReasonState {
    GainedVisibleRootProgress,
    SourceExhausted,
    MaxAutoBatchesReached,
    MaxAutoPostsReached,
    RequestFailed,
}

impl From<TopicLoadMoreStopReason> for TopicLoadMoreStopReasonState {
    fn from(value: TopicLoadMoreStopReason) -> Self {
        match value {
            TopicLoadMoreStopReason::GainedVisibleRootProgress => Self::GainedVisibleRootProgress,
            TopicLoadMoreStopReason::SourceExhausted => Self::SourceExhausted,
            TopicLoadMoreStopReason::MaxAutoBatchesReached => Self::MaxAutoBatchesReached,
            TopicLoadMoreStopReason::MaxAutoPostsReached => Self::MaxAutoPostsReached,
            TopicLoadMoreStopReason::RequestFailed => Self::RequestFailed,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicLoadMoreOutcomeState {
    pub appended_posts: Vec<TopicPostState>,
    pub loaded_ranges: Vec<TopicLoadedRangeState>,
    pub source_cursor: Option<TopicSourceCursorState>,
    pub source_exhausted: bool,
    pub tree_presentation: TopicTreePresentationState,
    pub chained_batches: u8,
    pub chained_posts: u16,
    pub stop_reason: TopicLoadMoreStopReasonState,
}

pub fn topic_load_more_outcome_state_from_model(
    value: TopicLoadMoreOutcome,
    base_url: &str,
) -> TopicLoadMoreOutcomeState {
    TopicLoadMoreOutcomeState {
        appended_posts: value
            .appended_posts
            .into_iter()
            .map(|post| topic_post_state_from_model(post, base_url))
            .collect(),
        loaded_ranges: value
            .source_snapshot
            .loaded_ranges
            .into_iter()
            .map(Into::into)
            .collect(),
        source_cursor: value.source_snapshot.source_cursor.map(Into::into),
        source_exhausted: value.source_snapshot.source_exhausted,
        tree_presentation: topic_tree_presentation_state_from_model(value.tree_presentation),
        chained_batches: value.chained_batches,
        chained_posts: value.chained_posts,
        stop_reason: value.stop_reason.into(),
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailState {
    pub id: u64,
    pub message_bus_last_id: Option<i64>,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub reply_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTagState>,
    pub views: u32,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub highest_post_number: u32,
    pub last_read_post_number: Option<u32>,
    pub bookmarks: Vec<u64>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub accepted_answer: bool,
    pub has_accepted_answer: bool,
    pub can_vote: bool,
    pub vote_count: i32,
    pub user_voted: bool,
    pub summarizable: bool,
    pub has_cached_summary: bool,
    pub has_summary: bool,
    pub archetype: Option<String>,
    pub post_stream: TopicPostStreamState,
    pub details: TopicDetailMetaState,
}

pub fn topic_detail_state_from_model(value: TopicDetail, base_url: &str) -> TopicDetailState {
    let reply_count = value.reply_count();
    TopicDetailState {
        id: value.id,
        message_bus_last_id: value.message_bus_last_id,
        title: value.title,
        slug: value.slug,
        posts_count: value.posts_count,
        reply_count,
        category_id: value.category_id,
        tags: value.tags.into_iter().map(Into::into).collect(),
        views: value.views,
        like_count: value.like_count,
        created_at: value.created_at,
        highest_post_number: value.highest_post_number,
        last_read_post_number: value.last_read_post_number,
        bookmarks: value.bookmarks,
        bookmarked: value.bookmarked,
        bookmark_id: value.bookmark_id,
        bookmark_name: value.bookmark_name,
        bookmark_reminder_at: value.bookmark_reminder_at,
        accepted_answer: value.accepted_answer,
        has_accepted_answer: value.has_accepted_answer,
        can_vote: value.can_vote,
        vote_count: value.vote_count,
        user_voted: value.user_voted,
        summarizable: value.summarizable,
        has_cached_summary: value.has_cached_summary,
        has_summary: value.has_summary,
        archetype: value.archetype,
        post_stream: topic_post_stream_state_from_model(value.post_stream, base_url),
        details: value.details.into(),
    }
}

#[cfg(test)]
mod tests {
    use fire_models::{TopicDetailSourceSnapshot, TopicLoadMoreOutcome, TopicPost};

    use super::topic_load_more_outcome_state_from_model;

    #[test]
    fn load_more_ffi_sends_only_appended_posts() {
        let appended = TopicPost {
            id: 9,
            post_number: 9,
            ..TopicPost::default()
        };
        let existing = TopicPost {
            id: 1,
            post_number: 1,
            ..TopicPost::default()
        };
        let state = topic_load_more_outcome_state_from_model(
            TopicLoadMoreOutcome {
                source_snapshot: TopicDetailSourceSnapshot {
                    loaded_posts: vec![existing, appended.clone()],
                    source_exhausted: true,
                    ..TopicDetailSourceSnapshot::default()
                },
                appended_posts: vec![appended],
                ..TopicLoadMoreOutcome::default()
            },
            "https://linux.do",
        );
        assert_eq!(state.appended_posts.len(), 1);
        assert_eq!(state.appended_posts[0].id, 9);
        assert!(state.source_exhausted);
        assert!(state.source_cursor.is_none());
    }
}
