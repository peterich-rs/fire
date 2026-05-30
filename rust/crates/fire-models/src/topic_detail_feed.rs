use serde::{Deserialize, Serialize};

use crate::{TopicHeader, TopicPost, TopicResponseCursor, TopicResponseRow};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum TopicDetailLoadPolicy {
    #[default]
    CacheFirstThenRefresh,
    NetworkFirst,
    CacheOnly,
    ForceRefresh,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailFeedQuery {
    pub topic_id: u64,
    pub target_post_number: Option<u32>,
    pub policy: TopicDetailLoadPolicy,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum TopicDetailFeedItemKind {
    Header,
    OriginalPost,
    Reply,
    Loading,
    Error,
    Footer,
    Gap,
    Notice,
    #[default]
    Unknown,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum FeedSnapshotSource {
    #[default]
    Network,
    ProcessedCache,
    StaleIfError,
    EmptyCacheError,
    LocalFixture,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum TopicDetailFeedLoadState {
    #[default]
    Ready,
    Loading,
    EmptyCacheError,
    StaleWithError,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailLoadedRange {
    pub first_post_number: u32,
    pub last_post_number: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailCursor {
    pub next_response_cursor: Option<TopicResponseCursor>,
    pub loaded_ranges: Vec<TopicDetailLoadedRange>,
    pub has_more: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailFeedItem {
    pub item_id: String,
    pub kind: TopicDetailFeedItemKind,
    pub ordinal: u32,
    pub post_id: Option<u64>,
    pub content_revision: String,
    pub header: Option<TopicHeader>,
    pub post: Option<TopicPost>,
    pub response_row: Option<TopicResponseRow>,
    pub title: Option<String>,
    pub message: Option<String>,
    pub retryable: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailFeedSnapshot {
    pub topic_id: u64,
    pub revision: u64,
    pub items: Vec<TopicDetailFeedItem>,
    pub cursor: TopicDetailCursor,
    pub source: FeedSnapshotSource,
    pub load_state: TopicDetailFeedLoadState,
    pub stale_error_message: Option<String>,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum TopicDetailFeedPatchOperationKind {
    Insert,
    Delete,
    Replace,
    Reload,
    #[default]
    Unknown,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailFeedPatchOperation {
    pub kind: TopicDetailFeedPatchOperationKind,
    pub index: u32,
    pub delete_count: u32,
    pub items: Vec<TopicDetailFeedItem>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailFeedPatch {
    pub topic_id: u64,
    pub base_revision: u64,
    pub new_revision: u64,
    pub operations: Vec<TopicDetailFeedPatchOperation>,
}

impl TopicDetailFeedSnapshot {
    pub fn empty_cache_error(topic_id: u64, message: impl Into<String>) -> Self {
        Self {
            topic_id,
            revision: 0,
            items: vec![TopicDetailFeedItem {
                item_id: format!("error:{topic_id}:empty-cache"),
                kind: TopicDetailFeedItemKind::Error,
                ordinal: 0,
                title: Some("Topic unavailable".to_string()),
                message: Some(message.into()),
                retryable: true,
                ..TopicDetailFeedItem::default()
            }],
            source: FeedSnapshotSource::EmptyCacheError,
            load_state: TopicDetailFeedLoadState::EmptyCacheError,
            ..Self::default()
        }
    }
}
