use fire_models::{
    TopicListKind, TopicListResponse, TopicParticipant, TopicPoster, TopicRow, TopicSummary,
    TopicTag, TopicUser,
};

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
pub struct TopicUserState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicUser> for TopicUserState {
    fn from(value: TopicUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPosterState {
    pub user_id: u64,
    pub description: Option<String>,
    pub extras: Option<String>,
}

impl From<TopicPoster> for TopicPosterState {
    fn from(value: TopicPoster) -> Self {
        Self {
            user_id: value.user_id,
            description: value.description,
            extras: value.extras,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicParticipantState {
    pub user_id: u64,
    pub username: Option<String>,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<TopicParticipant> for TopicParticipantState {
    fn from(value: TopicParticipant) -> Self {
        Self {
            user_id: value.user_id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTagState {
    pub id: Option<u64>,
    pub name: String,
    pub slug: Option<String>,
}

impl From<TopicTag> for TopicTagState {
    fn from(value: TopicTag) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicSummaryState {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub reply_count: u32,
    pub views: u32,
    pub like_count: u32,
    pub excerpt: Option<String>,
    pub created_at: Option<String>,
    pub last_posted_at: Option<String>,
    pub last_poster_username: Option<String>,
    pub category_id: Option<u64>,
    pub pinned: bool,
    pub visible: bool,
    pub closed: bool,
    pub archived: bool,
    pub tags: Vec<TopicTagState>,
    pub posters: Vec<TopicPosterState>,
    pub participants: Vec<TopicParticipantState>,
    pub unseen: bool,
    pub unread_posts: u32,
    pub new_posts: u32,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
    pub bookmarked_post_number: Option<u32>,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub bookmarkable_type: Option<String>,
    pub has_accepted_answer: bool,
    pub can_have_answer: bool,
}

impl From<TopicSummary> for TopicSummaryState {
    fn from(value: TopicSummary) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            reply_count: value.reply_count,
            views: value.views,
            like_count: value.like_count,
            excerpt: value.excerpt,
            created_at: value.created_at,
            last_posted_at: value.last_posted_at,
            last_poster_username: value.last_poster_username,
            category_id: value.category_id,
            pinned: value.pinned,
            visible: value.visible,
            closed: value.closed,
            archived: value.archived,
            tags: value.tags.into_iter().map(Into::into).collect(),
            posters: value.posters.into_iter().map(Into::into).collect(),
            participants: value.participants.into_iter().map(Into::into).collect(),
            unseen: value.unseen,
            unread_posts: value.unread_posts,
            new_posts: value.new_posts,
            last_read_post_number: value.last_read_post_number,
            highest_post_number: value.highest_post_number,
            bookmarked_post_number: value.bookmarked_post_number,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            bookmarkable_type: value.bookmarkable_type,
            has_accepted_answer: value.has_accepted_answer,
            can_have_answer: value.can_have_answer,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicRowState {
    pub topic: TopicSummaryState,
    pub excerpt_text: Option<String>,
    pub original_poster_username: Option<String>,
    pub original_poster_avatar_template: Option<String>,
    pub tag_names: Vec<String>,
    pub status_labels: Vec<String>,
    pub is_pinned: bool,
    pub is_closed: bool,
    pub is_archived: bool,
    pub has_accepted_answer: bool,
    pub has_unread_posts: bool,
    pub created_timestamp_unix_ms: Option<u64>,
    pub activity_timestamp_unix_ms: Option<u64>,
    pub last_poster_username: Option<String>,
}

impl From<TopicRow> for TopicRowState {
    fn from(value: TopicRow) -> Self {
        Self {
            topic: value.topic.into(),
            excerpt_text: value.excerpt_text,
            original_poster_username: value.original_poster_username,
            original_poster_avatar_template: value.original_poster_avatar_template,
            tag_names: value.tag_names,
            status_labels: value.status_labels,
            is_pinned: value.is_pinned,
            is_closed: value.is_closed,
            is_archived: value.is_archived,
            has_accepted_answer: value.has_accepted_answer,
            has_unread_posts: value.has_unread_posts,
            created_timestamp_unix_ms: value.created_timestamp_unix_ms,
            activity_timestamp_unix_ms: value.activity_timestamp_unix_ms,
            last_poster_username: value.last_poster_username,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicListState {
    pub topics: Vec<TopicSummaryState>,
    pub users: Vec<TopicUserState>,
    pub rows: Vec<TopicRowState>,
    pub more_topics_url: Option<String>,
    pub next_page: Option<u32>,
}

impl From<TopicListResponse> for TopicListState {
    fn from(value: TopicListResponse) -> Self {
        Self {
            topics: value.topics.into_iter().map(Into::into).collect(),
            users: value.users.into_iter().map(Into::into).collect(),
            rows: value.rows.into_iter().map(Into::into).collect(),
            more_topics_url: value.more_topics_url,
            next_page: value.next_page,
        }
    }
}
