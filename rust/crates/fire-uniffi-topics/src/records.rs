use fire_models::{
    FeedSnapshotSource, Poll, PollOption, PostActionType, PostFlagRequest, PostReactionUpdate,
    PostUpdateRequest, PrivateMessageCreateRequest, ReactionUser, ReactionUsersGroup,
    ResolvedUploadUrl, TopicAiSummary, TopicBody, TopicCreateRequest, TopicDetail,
    TopicDetailCreatedBy, TopicDetailCursor, TopicDetailFeedItem, TopicDetailFeedItemKind,
    TopicDetailFeedLoadState, TopicDetailFeedPatch, TopicDetailFeedPatchOperation,
    TopicDetailFeedPatchOperationKind, TopicDetailFeedQuery, TopicDetailFeedSnapshot,
    TopicDetailLoadPolicy, TopicDetailLoadedRange, TopicDetailMeta, TopicDetailQuery, TopicHeader,
    TopicListQuery, TopicPost, TopicPostStream, TopicReaction, TopicReplyRequest, TopicReplyToUser,
    TopicResponseCursor, TopicResponsePage, TopicResponsePageQuery, TopicResponseRow, TopicScreen,
    TopicScreenQuery, TopicTimingEntry, TopicTimingsRequest, TopicUpdateRequest, UploadResult,
    VoteResponse, VotedUser,
};

use fire_uniffi_types::{TopicListKindState, TopicParticipantState, TopicTagState};

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
pub struct TopicDetailQueryState {
    pub topic_id: u64,
    pub post_number: Option<u32>,
    pub track_visit: bool,
    pub force_load: bool,
    pub filter: Option<String>,
    pub username_filters: Option<String>,
    pub filter_top_level_replies: bool,
}

impl From<TopicDetailQuery> for TopicDetailQueryState {
    fn from(value: TopicDetailQuery) -> Self {
        Self {
            topic_id: value.topic_id,
            post_number: value.post_number,
            track_visit: value.track_visit,
            force_load: value.force_load,
            filter: value.filter,
            username_filters: value.username_filters,
            filter_top_level_replies: value.filter_top_level_replies,
        }
    }
}

impl From<TopicDetailQueryState> for TopicDetailQuery {
    fn from(value: TopicDetailQueryState) -> Self {
        Self {
            topic_id: value.topic_id,
            post_number: value.post_number,
            track_visit: value.track_visit,
            force_load: value.force_load,
            filter: value.filter,
            username_filters: value.username_filters,
            filter_top_level_replies: value.filter_top_level_replies,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum TopicDetailLoadPolicyState {
    CacheFirstThenRefresh,
    NetworkFirst,
    CacheOnly,
    ForceRefresh,
}

impl From<TopicDetailLoadPolicy> for TopicDetailLoadPolicyState {
    fn from(value: TopicDetailLoadPolicy) -> Self {
        match value {
            TopicDetailLoadPolicy::CacheFirstThenRefresh => Self::CacheFirstThenRefresh,
            TopicDetailLoadPolicy::NetworkFirst => Self::NetworkFirst,
            TopicDetailLoadPolicy::CacheOnly => Self::CacheOnly,
            TopicDetailLoadPolicy::ForceRefresh => Self::ForceRefresh,
        }
    }
}

impl From<TopicDetailLoadPolicyState> for TopicDetailLoadPolicy {
    fn from(value: TopicDetailLoadPolicyState) -> Self {
        match value {
            TopicDetailLoadPolicyState::CacheFirstThenRefresh => Self::CacheFirstThenRefresh,
            TopicDetailLoadPolicyState::NetworkFirst => Self::NetworkFirst,
            TopicDetailLoadPolicyState::CacheOnly => Self::CacheOnly,
            TopicDetailLoadPolicyState::ForceRefresh => Self::ForceRefresh,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailFeedQueryState {
    pub topic_id: u64,
    pub target_post_number: Option<u32>,
    pub policy: TopicDetailLoadPolicyState,
}

impl From<TopicDetailFeedQueryState> for TopicDetailFeedQuery {
    fn from(value: TopicDetailFeedQueryState) -> Self {
        Self {
            topic_id: value.topic_id,
            target_post_number: value.target_post_number,
            policy: value.policy.into(),
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum TopicDetailFeedItemKindState {
    Header,
    OriginalPost,
    Reply,
    Loading,
    Error,
    Footer,
    Gap,
    Notice,
    Unknown,
}

impl From<TopicDetailFeedItemKind> for TopicDetailFeedItemKindState {
    fn from(value: TopicDetailFeedItemKind) -> Self {
        match value {
            TopicDetailFeedItemKind::Header => Self::Header,
            TopicDetailFeedItemKind::OriginalPost => Self::OriginalPost,
            TopicDetailFeedItemKind::Reply => Self::Reply,
            TopicDetailFeedItemKind::Loading => Self::Loading,
            TopicDetailFeedItemKind::Error => Self::Error,
            TopicDetailFeedItemKind::Footer => Self::Footer,
            TopicDetailFeedItemKind::Gap => Self::Gap,
            TopicDetailFeedItemKind::Notice => Self::Notice,
            TopicDetailFeedItemKind::Unknown => Self::Unknown,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum FeedSnapshotSourceState {
    Network,
    ProcessedCache,
    StaleIfError,
    EmptyCacheError,
    LocalFixture,
}

impl From<FeedSnapshotSource> for FeedSnapshotSourceState {
    fn from(value: FeedSnapshotSource) -> Self {
        match value {
            FeedSnapshotSource::Network => Self::Network,
            FeedSnapshotSource::ProcessedCache => Self::ProcessedCache,
            FeedSnapshotSource::StaleIfError => Self::StaleIfError,
            FeedSnapshotSource::EmptyCacheError => Self::EmptyCacheError,
            FeedSnapshotSource::LocalFixture => Self::LocalFixture,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum TopicDetailFeedLoadStateState {
    Ready,
    Loading,
    EmptyCacheError,
    StaleWithError,
}

impl From<TopicDetailFeedLoadState> for TopicDetailFeedLoadStateState {
    fn from(value: TopicDetailFeedLoadState) -> Self {
        match value {
            TopicDetailFeedLoadState::Ready => Self::Ready,
            TopicDetailFeedLoadState::Loading => Self::Loading,
            TopicDetailFeedLoadState::EmptyCacheError => Self::EmptyCacheError,
            TopicDetailFeedLoadState::StaleWithError => Self::StaleWithError,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailLoadedRangeState {
    pub first_post_number: u32,
    pub last_post_number: u32,
}

impl From<TopicDetailLoadedRange> for TopicDetailLoadedRangeState {
    fn from(value: TopicDetailLoadedRange) -> Self {
        Self {
            first_post_number: value.first_post_number,
            last_post_number: value.last_post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailCursorState {
    pub next_response_cursor: Option<TopicResponseCursorState>,
    pub loaded_ranges: Vec<TopicDetailLoadedRangeState>,
    pub has_more: bool,
}

impl From<TopicDetailCursor> for TopicDetailCursorState {
    fn from(value: TopicDetailCursor) -> Self {
        Self {
            next_response_cursor: value.next_response_cursor.map(Into::into),
            loaded_ranges: value.loaded_ranges.into_iter().map(Into::into).collect(),
            has_more: value.has_more,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicScreenQueryState {
    pub topic_id: u64,
    pub target_post_number: Option<u32>,
    pub root_page_size: u16,
    pub row_page_size: u16,
    pub track_visit: bool,
    pub force_load: bool,
}

impl From<TopicScreenQueryState> for TopicScreenQuery {
    fn from(value: TopicScreenQueryState) -> Self {
        Self {
            topic_id: value.topic_id,
            target_post_number: value.target_post_number,
            root_page_size: value.root_page_size,
            row_page_size: value.row_page_size,
            track_visit: value.track_visit,
            force_load: value.force_load,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicAiSummaryState {
    pub summarized_text: String,
    pub algorithm: Option<String>,
    pub outdated: bool,
    pub can_regenerate: bool,
    pub new_posts_since_summary: u32,
    pub updated_at: Option<String>,
}

impl From<TopicAiSummary> for TopicAiSummaryState {
    fn from(value: TopicAiSummary) -> Self {
        Self {
            summarized_text: value.summarized_text,
            algorithm: value.algorithm,
            outdated: value.outdated,
            can_regenerate: value.can_regenerate,
            new_posts_since_summary: value.new_posts_since_summary,
            updated_at: value.updated_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicReactionState {
    pub id: String,
    pub kind: Option<String>,
    pub count: u32,
    pub can_undo: Option<bool>,
}

impl From<TopicReaction> for TopicReactionState {
    fn from(value: TopicReaction) -> Self {
        Self {
            id: value.id,
            kind: value.kind,
            count: value.count,
            can_undo: value.can_undo,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ReactionUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<ReactionUser> for ReactionUserState {
    fn from(value: ReactionUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ReactionUsersGroupState {
    pub id: String,
    pub count: u32,
    pub users: Vec<ReactionUserState>,
}

impl From<ReactionUsersGroup> for ReactionUsersGroupState {
    fn from(value: ReactionUsersGroup) -> Self {
        Self {
            id: value.id,
            count: value.count,
            users: value.users.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PollOptionState {
    pub id: String,
    pub html: String,
    pub votes: u32,
}

impl From<PollOption> for PollOptionState {
    fn from(value: PollOption) -> Self {
        Self {
            id: value.id,
            html: value.html,
            votes: value.votes,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PollState {
    pub id: u64,
    pub name: String,
    pub kind: String,
    pub status: String,
    pub results: String,
    pub options: Vec<PollOptionState>,
    pub voters: u32,
    pub user_votes: Vec<String>,
}

impl From<Poll> for PollState {
    fn from(value: Poll) -> Self {
        Self {
            id: value.id,
            name: value.name,
            kind: value.kind,
            status: value.status,
            results: value.results,
            options: value.options.into_iter().map(Into::into).collect(),
            voters: value.voters,
            user_votes: value.user_votes,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicReplyRequestState {
    pub topic_id: u64,
    pub raw: String,
    pub reply_to_post_number: Option<u32>,
}

impl From<TopicReplyRequestState> for TopicReplyRequest {
    fn from(value: TopicReplyRequestState) -> Self {
        Self {
            topic_id: value.topic_id,
            raw: value.raw,
            reply_to_post_number: value.reply_to_post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicCreateRequestState {
    pub title: String,
    pub raw: String,
    pub category_id: u64,
    pub tags: Vec<String>,
}

impl From<TopicCreateRequestState> for TopicCreateRequest {
    fn from(value: TopicCreateRequestState) -> Self {
        Self {
            title: value.title,
            raw: value.raw,
            category_id: value.category_id,
            tags: value.tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PrivateMessageCreateRequestState {
    pub title: String,
    pub raw: String,
    pub target_recipients: Vec<String>,
}

impl From<PrivateMessageCreateRequestState> for PrivateMessageCreateRequest {
    fn from(value: PrivateMessageCreateRequestState) -> Self {
        Self {
            title: value.title,
            raw: value.raw,
            target_recipients: value.target_recipients,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicUpdateRequestState {
    pub topic_id: u64,
    pub title: String,
    pub category_id: u64,
    pub tags: Vec<String>,
}

impl From<TopicUpdateRequestState> for TopicUpdateRequest {
    fn from(value: TopicUpdateRequestState) -> Self {
        Self {
            topic_id: value.topic_id,
            title: value.title,
            category_id: value.category_id,
            tags: value.tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PostUpdateRequestState {
    pub post_id: u64,
    pub raw: String,
    pub edit_reason: Option<String>,
}

impl From<PostUpdateRequestState> for PostUpdateRequest {
    fn from(value: PostUpdateRequestState) -> Self {
        Self {
            post_id: value.post_id,
            raw: value.raw,
            edit_reason: value.edit_reason,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PostFlagRequestState {
    pub post_id: u64,
    pub flag_type_id: u32,
    pub message: Option<String>,
}

impl From<PostFlagRequestState> for PostFlagRequest {
    fn from(value: PostFlagRequestState) -> Self {
        Self {
            post_id: value.post_id,
            flag_type_id: value.flag_type_id,
            message: value.message,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PostActionTypeState {
    pub id: u32,
    pub name_key: String,
    pub name: String,
    pub description: String,
    pub short_description: Option<String>,
    pub is_flag: bool,
    pub require_message: bool,
    pub enabled: bool,
    pub position: i32,
    pub applies_to: Vec<String>,
}

impl From<PostActionType> for PostActionTypeState {
    fn from(value: PostActionType) -> Self {
        Self {
            id: value.id,
            name_key: value.name_key,
            name: value.name,
            description: value.description,
            short_description: value.short_description,
            is_flag: value.is_flag,
            require_message: value.require_message,
            enabled: value.enabled,
            position: value.position,
            applies_to: value.applies_to,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UploadImageRequestState {
    pub file_name: String,
    pub mime_type: Option<String>,
    pub bytes: Vec<u8>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UploadResultState {
    pub short_url: String,
    pub url: Option<String>,
    pub original_filename: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

impl From<UploadResult> for UploadResultState {
    fn from(value: UploadResult) -> Self {
        Self {
            short_url: value.short_url,
            url: value.url,
            original_filename: value.original_filename,
            width: value.width,
            height: value.height,
            thumbnail_width: value.thumbnail_width,
            thumbnail_height: value.thumbnail_height,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ResolvedUploadUrlState {
    pub short_url: String,
    pub short_path: Option<String>,
    pub url: Option<String>,
}

impl From<ResolvedUploadUrl> for ResolvedUploadUrlState {
    fn from(value: ResolvedUploadUrl) -> Self {
        Self {
            short_url: value.short_url,
            short_path: value.short_path,
            url: value.url,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTimingEntryState {
    pub post_number: u32,
    pub milliseconds: u32,
}

impl From<TopicTimingEntryState> for TopicTimingEntry {
    fn from(value: TopicTimingEntryState) -> Self {
        Self {
            post_number: value.post_number,
            milliseconds: value.milliseconds,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTimingsRequestState {
    pub topic_id: u64,
    pub topic_time_ms: u32,
    pub timings: Vec<TopicTimingEntryState>,
}

impl From<TopicTimingsRequestState> for TopicTimingsRequest {
    fn from(value: TopicTimingsRequestState) -> Self {
        Self {
            topic_id: value.topic_id,
            topic_time_ms: value.topic_time_ms,
            timings: value.timings.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PostReactionUpdateState {
    pub reactions: Vec<TopicReactionState>,
    pub current_user_reaction: Option<TopicReactionState>,
}

impl From<PostReactionUpdate> for PostReactionUpdateState {
    fn from(value: PostReactionUpdate) -> Self {
        Self {
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicReplyToUserState {
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<TopicReplyToUser> for TopicReplyToUserState {
    fn from(value: TopicReplyToUser) -> Self {
        Self {
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub cooked: String,
    pub raw: Option<String>,
    pub post_number: u32,
    pub post_type: i32,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub like_count: u32,
    pub reply_count: u32,
    pub reply_to_post_number: Option<u32>,
    pub reply_to_user: Option<TopicReplyToUserState>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub reactions: Vec<TopicReactionState>,
    pub current_user_reaction: Option<TopicReactionState>,
    pub polls: Vec<PollState>,
    pub accepted_answer: bool,
    pub can_accept_answer: bool,
    pub can_unaccept_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub hidden: bool,
}

impl From<TopicPost> for TopicPostState {
    fn from(value: TopicPost) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            cooked: value.cooked,
            raw: value.raw,
            post_number: value.post_number,
            post_type: value.post_type,
            created_at: value.created_at,
            updated_at: value.updated_at,
            like_count: value.like_count,
            reply_count: value.reply_count,
            reply_to_post_number: value.reply_to_post_number,
            reply_to_user: value.reply_to_user.map(Into::into),
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
            polls: value.polls.into_iter().map(Into::into).collect(),
            accepted_answer: value.accepted_answer,
            can_accept_answer: value.can_accept_answer,
            can_unaccept_answer: value.can_unaccept_answer,
            can_edit: value.can_edit,
            can_delete: value.can_delete,
            can_recover: value.can_recover,
            hidden: value.hidden,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostStreamState {
    pub posts: Vec<TopicPostState>,
    pub stream: Vec<u64>,
}

impl From<TopicPostStream> for TopicPostStreamState {
    fn from(value: TopicPostStream) -> Self {
        Self {
            posts: value.posts.into_iter().map(Into::into).collect(),
            stream: value.stream,
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

impl From<TopicBody> for TopicBodyState {
    fn from(value: TopicBody) -> Self {
        Self {
            post: value.post.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicResponseCursorState {
    pub topic_id: u64,
    pub session_id: u64,
    pub next_root_offset: u32,
    pub next_branch_offset: u32,
    pub page_size: u16,
    pub row_page_size: u16,
}

impl From<TopicResponseCursor> for TopicResponseCursorState {
    fn from(value: TopicResponseCursor) -> Self {
        Self {
            topic_id: value.topic_id,
            session_id: value.session_id,
            next_root_offset: value.next_root_offset,
            next_branch_offset: value.next_branch_offset,
            page_size: value.page_size,
            row_page_size: value.row_page_size,
        }
    }
}

impl From<TopicResponseCursorState> for TopicResponseCursor {
    fn from(value: TopicResponseCursorState) -> Self {
        Self {
            topic_id: value.topic_id,
            session_id: value.session_id,
            next_root_offset: value.next_root_offset,
            next_branch_offset: value.next_branch_offset,
            page_size: value.page_size,
            row_page_size: value.row_page_size,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicResponsePageQueryState {
    pub cursor: TopicResponseCursorState,
}

impl From<TopicResponsePageQueryState> for TopicResponsePageQuery {
    fn from(value: TopicResponsePageQueryState) -> Self {
        Self {
            cursor: value.cursor.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicResponseRowState {
    pub post: TopicPostState,
    pub root_post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u16,
    pub preorder_index: u32,
    pub has_children: bool,
    pub descendant_count: u32,
    pub sibling_index: u16,
    pub is_last_sibling: bool,
}

impl From<TopicResponseRow> for TopicResponseRowState {
    fn from(value: TopicResponseRow) -> Self {
        Self {
            post: value.post.into(),
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
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicResponsePageState {
    pub rows: Vec<TopicResponseRowState>,
    pub next_cursor: Option<TopicResponseCursorState>,
    pub total_root_count: u32,
    pub loaded_root_count: u32,
    pub total_response_count: u32,
    pub focused_post_number: Option<u32>,
}

impl From<TopicResponsePage> for TopicResponsePageState {
    fn from(value: TopicResponsePage) -> Self {
        Self {
            rows: value.rows.into_iter().map(Into::into).collect(),
            next_cursor: value.next_cursor.map(Into::into),
            total_root_count: value.total_root_count,
            loaded_root_count: value.loaded_root_count,
            total_response_count: value.total_response_count,
            focused_post_number: value.focused_post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicScreenState {
    pub header: TopicHeaderState,
    pub body: TopicBodyState,
    pub response: TopicResponsePageState,
}

impl From<TopicScreen> for TopicScreenState {
    fn from(value: TopicScreen) -> Self {
        Self {
            header: value.header.into(),
            body: value.body.into(),
            response: value.response.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailFeedItemState {
    pub item_id: String,
    pub kind: TopicDetailFeedItemKindState,
    pub ordinal: u32,
    pub post_id: Option<u64>,
    pub content_revision: String,
    pub header: Option<TopicHeaderState>,
    pub post: Option<TopicPostState>,
    pub response_row: Option<TopicResponseRowState>,
    pub title: Option<String>,
    pub message: Option<String>,
    pub retryable: bool,
}

impl From<TopicDetailFeedItem> for TopicDetailFeedItemState {
    fn from(value: TopicDetailFeedItem) -> Self {
        Self {
            item_id: value.item_id,
            kind: value.kind.into(),
            ordinal: value.ordinal,
            post_id: value.post_id,
            content_revision: value.content_revision,
            header: value.header.map(Into::into),
            post: value.post.map(Into::into),
            response_row: value.response_row.map(Into::into),
            title: value.title,
            message: value.message,
            retryable: value.retryable,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailFeedSnapshotState {
    pub topic_id: u64,
    pub revision: u64,
    pub items: Vec<TopicDetailFeedItemState>,
    pub cursor: TopicDetailCursorState,
    pub source: FeedSnapshotSourceState,
    pub load_state: TopicDetailFeedLoadStateState,
    pub stale_error_message: Option<String>,
    pub updated_at_ms: u64,
}

impl From<TopicDetailFeedSnapshot> for TopicDetailFeedSnapshotState {
    fn from(value: TopicDetailFeedSnapshot) -> Self {
        Self {
            topic_id: value.topic_id,
            revision: value.revision,
            items: value.items.into_iter().map(Into::into).collect(),
            cursor: value.cursor.into(),
            source: value.source.into(),
            load_state: value.load_state.into(),
            stale_error_message: value.stale_error_message,
            updated_at_ms: value.updated_at_ms,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum TopicDetailFeedPatchOperationKindState {
    Insert,
    Delete,
    Replace,
    Reload,
    Unknown,
}

impl From<TopicDetailFeedPatchOperationKind> for TopicDetailFeedPatchOperationKindState {
    fn from(value: TopicDetailFeedPatchOperationKind) -> Self {
        match value {
            TopicDetailFeedPatchOperationKind::Insert => Self::Insert,
            TopicDetailFeedPatchOperationKind::Delete => Self::Delete,
            TopicDetailFeedPatchOperationKind::Replace => Self::Replace,
            TopicDetailFeedPatchOperationKind::Reload => Self::Reload,
            TopicDetailFeedPatchOperationKind::Unknown => Self::Unknown,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailFeedPatchOperationState {
    pub kind: TopicDetailFeedPatchOperationKindState,
    pub index: u32,
    pub delete_count: u32,
    pub items: Vec<TopicDetailFeedItemState>,
}

impl From<TopicDetailFeedPatchOperation> for TopicDetailFeedPatchOperationState {
    fn from(value: TopicDetailFeedPatchOperation) -> Self {
        Self {
            kind: value.kind.into(),
            index: value.index,
            delete_count: value.delete_count,
            items: value.items.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailFeedPatchState {
    pub topic_id: u64,
    pub base_revision: u64,
    pub new_revision: u64,
    pub operations: Vec<TopicDetailFeedPatchOperationState>,
}

impl From<TopicDetailFeedPatch> for TopicDetailFeedPatchState {
    fn from(value: TopicDetailFeedPatch) -> Self {
        Self {
            topic_id: value.topic_id,
            base_revision: value.base_revision,
            new_revision: value.new_revision,
            operations: value.operations.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailState {
    pub id: u64,
    pub message_bus_last_id: Option<i64>,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTagState>,
    pub views: u32,
    pub like_count: u32,
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
    pub post_stream: TopicPostStreamState,
    pub details: TopicDetailMetaState,
}

impl From<TopicDetail> for TopicDetailState {
    fn from(value: TopicDetail) -> Self {
        Self {
            id: value.id,
            message_bus_last_id: value.message_bus_last_id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            category_id: value.category_id,
            tags: value.tags.into_iter().map(Into::into).collect(),
            views: value.views,
            like_count: value.like_count,
            created_at: value.created_at,
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
            post_stream: value.post_stream.into(),
            details: value.details.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct VotedUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<VotedUser> for VotedUserState {
    fn from(value: VotedUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct VoteResponseState {
    pub can_vote: bool,
    pub vote_limit: u32,
    pub vote_count: i32,
    pub votes_left: i32,
    pub alert: bool,
    pub who_voted: Vec<VotedUserState>,
}

impl From<VoteResponse> for VoteResponseState {
    fn from(value: VoteResponse) -> Self {
        Self {
            can_vote: value.can_vote,
            vote_limit: value.vote_limit,
            vote_count: value.vote_count,
            votes_left: value.votes_left,
            alert: value.alert,
            who_voted: value.who_voted.into_iter().map(Into::into).collect(),
        }
    }
}
