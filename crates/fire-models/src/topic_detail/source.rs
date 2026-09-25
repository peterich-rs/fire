use serde::{Deserialize, Serialize};

use super::{detail::TopicDetailMeta, post::TopicPost, tree::TopicTreePresentation};
use crate::topic::TopicTag;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailSourceQuery {
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

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicHeader {
    pub topic_id: u64,
    pub message_bus_last_id: Option<i64>,
    pub title: String,
    pub slug: String,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTag>,
    pub views: u32,
    pub like_count: u32,
    pub posts_count: u32,
    pub reply_count: u32,
    pub highest_post_number: u32,
    pub created_at: Option<String>,
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
    pub details: TopicDetailMeta,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicBody {
    pub post: TopicPost,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicLoadedRange {
    pub start_offset: u32,
    pub end_offset_exclusive: u32,
    pub first_post_id: u64,
    pub last_post_id: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailSourceSnapshot {
    pub header: TopicHeader,
    pub body: TopicBody,
    pub raw_stream_ids: Vec<u64>,
    pub loaded_posts: Vec<TopicPost>,
    pub loaded_ranges: Vec<TopicLoadedRange>,
    pub source_cursor: Option<TopicSourceCursor>,
    pub source_exhausted: bool,
    pub focused_post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailPage {
    pub source_snapshot: TopicDetailSourceSnapshot,
    pub tree_presentation: TopicTreePresentation,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicSourceCursor {
    pub topic_id: u64,
    pub session_id: u64,
    pub next_stream_offset: u32,
    pub last_loaded_post_id: Option<u64>,
    pub batch_size: u16,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoadMoreTopicPostsQuery {
    pub cursor: TopicSourceCursor,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailSourceAppend {
    pub appended_posts: Vec<TopicPost>,
    pub loaded_ranges: Vec<TopicLoadedRange>,
    pub source_cursor: Option<TopicSourceCursor>,
    pub source_exhausted: bool,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum TopicLoadMoreStopReason {
    #[default]
    GainedVisibleRootProgress,
    SourceExhausted,
    MaxAutoBatchesReached,
    MaxAutoPostsReached,
    RequestFailed,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicLoadMoreOutcome {
    pub source_snapshot: TopicDetailSourceSnapshot,
    pub appended_posts: Vec<TopicPost>,
    pub tree_presentation: TopicTreePresentation,
    pub chained_batches: u8,
    pub chained_posts: u16,
    pub stop_reason: TopicLoadMoreStopReason,
}
