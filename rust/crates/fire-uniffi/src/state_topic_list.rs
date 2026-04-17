use fire_models::{TopicListKind, TopicListQuery};

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum TopicListKindState {
    Latest,
    New,
    Unread,
    Unseen,
    Hot,
    Top,
    PrivateMessagesInbox,
    PrivateMessagesSent,
}

impl From<TopicListKind> for TopicListKindState {
    fn from(value: TopicListKind) -> Self {
        match value {
            TopicListKind::Latest => Self::Latest,
            TopicListKind::New => Self::New,
            TopicListKind::Unread => Self::Unread,
            TopicListKind::Unseen => Self::Unseen,
            TopicListKind::Hot => Self::Hot,
            TopicListKind::Top => Self::Top,
            TopicListKind::PrivateMessagesInbox => Self::PrivateMessagesInbox,
            TopicListKind::PrivateMessagesSent => Self::PrivateMessagesSent,
        }
    }
}

impl From<TopicListKindState> for TopicListKind {
    fn from(value: TopicListKindState) -> Self {
        match value {
            TopicListKindState::Latest => Self::Latest,
            TopicListKindState::New => Self::New,
            TopicListKindState::Unread => Self::Unread,
            TopicListKindState::Unseen => Self::Unseen,
            TopicListKindState::Hot => Self::Hot,
            TopicListKindState::Top => Self::Top,
            TopicListKindState::PrivateMessagesInbox => Self::PrivateMessagesInbox,
            TopicListKindState::PrivateMessagesSent => Self::PrivateMessagesSent,
        }
    }
}

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
