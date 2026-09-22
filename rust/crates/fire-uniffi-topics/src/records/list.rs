use fire_models::{TopicListQuery, TopicLoadedRange, TopicSourceCursor};

use fire_uniffi_types::TopicListKindState;

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicListQueryState {
    pub kind: TopicListKindState,
    pub page: Option<u32>,
    pub topic_ids: Vec<u64>,
    pub order: Option<String>,
    pub ascending: Option<bool>,
    pub category_slug: Option<String>,
    pub category_id: Option<u64>,
    pub parent_category_slug: Option<String>,
    pub tag: Option<String>,
    pub additional_tags: Vec<String>,
    pub match_all_tags: bool,
}

impl From<TopicListQuery> for TopicListQueryState {
    fn from(value: TopicListQuery) -> Self {
        Self {
            kind: value.kind.into(),
            page: value.page,
            topic_ids: value.topic_ids,
            order: value.order,
            ascending: value.ascending,
            category_slug: value.category_slug,
            category_id: value.category_id,
            parent_category_slug: value.parent_category_slug,
            tag: value.tag,
            additional_tags: value.additional_tags,
            match_all_tags: value.match_all_tags,
        }
    }
}

impl From<TopicListQueryState> for TopicListQuery {
    fn from(value: TopicListQueryState) -> Self {
        Self {
            kind: value.kind.into(),
            page: value.page,
            topic_ids: value.topic_ids,
            order: value.order,
            ascending: value.ascending,
            category_slug: value.category_slug,
            category_id: value.category_id,
            parent_category_slug: value.parent_category_slug,
            tag: value.tag,
            additional_tags: value.additional_tags,
            match_all_tags: value.match_all_tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicLoadedRangeState {
    pub start_offset: u32,
    pub end_offset_exclusive: u32,
    pub first_post_id: u64,
    pub last_post_id: u64,
}

impl From<TopicLoadedRange> for TopicLoadedRangeState {
    fn from(value: TopicLoadedRange) -> Self {
        Self {
            start_offset: value.start_offset,
            end_offset_exclusive: value.end_offset_exclusive,
            first_post_id: value.first_post_id,
            last_post_id: value.last_post_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicSourceCursorState {
    pub topic_id: u64,
    pub session_id: u64,
    pub next_stream_offset: u32,
    pub last_loaded_post_id: Option<u64>,
    pub batch_size: u16,
}

impl From<TopicSourceCursor> for TopicSourceCursorState {
    fn from(value: TopicSourceCursor) -> Self {
        Self {
            topic_id: value.topic_id,
            session_id: value.session_id,
            next_stream_offset: value.next_stream_offset,
            last_loaded_post_id: value.last_loaded_post_id,
            batch_size: value.batch_size,
        }
    }
}

impl From<TopicSourceCursorState> for TopicSourceCursor {
    fn from(value: TopicSourceCursorState) -> Self {
        Self {
            topic_id: value.topic_id,
            session_id: value.session_id,
            next_stream_offset: value.next_stream_offset,
            last_loaded_post_id: value.last_loaded_post_id,
            batch_size: value.batch_size,
        }
    }
}
