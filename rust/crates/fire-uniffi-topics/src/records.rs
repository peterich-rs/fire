use fire_core::render_cooked_html;
use fire_models::{
    LoadMoreTopicPostsQuery, Poll, PollOption, PostActionType, PostFlagRequest, PostReactionUpdate,
    PostUpdateRequest, PrivateMessageCreateRequest, ReactionUser, ReactionUsersGroup,
    ResolvedUploadUrl, TopicAiSummary, TopicBody, TopicCreateRequest, TopicDetail,
    TopicDetailCreatedBy, TopicDetailMeta, TopicDetailPage, TopicDetailSourceQuery,
    TopicDetailSourceSnapshot, TopicHeader, TopicListQuery, TopicLoadMoreOutcome,
    TopicLoadMoreStopReason, TopicLoadedRange, TopicPost, TopicPostAuthorMetadata, TopicPostBoost,
    TopicPostBoostUser, TopicPostStream, TopicReaction, TopicReplyRequest, TopicReplyToUser,
    TopicSourceCursor, TopicTimingEntry, TopicTimingsRequest, TopicTreePresentation, TopicTreeRow,
    TopicUpdateRequest, UploadResult, VoteResponse, VotedUser,
};

use fire_uniffi_types::{
    RenderDocumentState, TopicListKindState, TopicParticipantState, TopicTagState,
};

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

impl From<TopicReactionState> for TopicReaction {
    fn from(value: TopicReactionState) -> Self {
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
    pub plain_text: String,
    pub votes: u32,
}

impl From<PollOption> for PollOptionState {
    fn from(value: PollOption) -> Self {
        Self {
            id: value.id,
            html: value.html,
            plain_text: value.plain_text,
            votes: value.votes,
        }
    }
}

impl From<PollOptionState> for PollOption {
    fn from(value: PollOptionState) -> Self {
        Self {
            id: value.id,
            html: value.html,
            plain_text: value.plain_text,
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

impl From<PollState> for Poll {
    fn from(value: PollState) -> Self {
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
pub struct TopicPostAuthorMetadataState {
    pub user_id: Option<u64>,
    pub user_title: Option<String>,
    pub primary_group_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_name: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub flair_group_id: Option<u64>,
    pub moderator: bool,
    pub admin: bool,
    pub group_moderator: bool,
    pub user_status_emoji: Option<String>,
    pub user_status_description: Option<String>,
}

impl From<TopicPostAuthorMetadata> for TopicPostAuthorMetadataState {
    fn from(value: TopicPostAuthorMetadata) -> Self {
        Self {
            user_id: value.user_id,
            user_title: value.user_title,
            primary_group_name: value.primary_group_name,
            flair_url: value.flair_url,
            flair_name: value.flair_name,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            flair_group_id: value.flair_group_id,
            moderator: value.moderator,
            admin: value.admin,
            group_moderator: value.group_moderator,
            user_status_emoji: value.user_status_emoji,
            user_status_description: value.user_status_description,
        }
    }
}

impl From<TopicPostAuthorMetadataState> for TopicPostAuthorMetadata {
    fn from(value: TopicPostAuthorMetadataState) -> Self {
        Self {
            user_id: value.user_id,
            user_title: value.user_title,
            primary_group_name: value.primary_group_name,
            flair_url: value.flair_url,
            flair_name: value.flair_name,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            flair_group_id: value.flair_group_id,
            moderator: value.moderator,
            admin: value.admin,
            group_moderator: value.group_moderator,
            user_status_emoji: value.user_status_emoji,
            user_status_description: value.user_status_description,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostBoostUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<TopicPostBoostUser> for TopicPostBoostUserState {
    fn from(value: TopicPostBoostUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

impl From<TopicPostBoostUserState> for TopicPostBoostUser {
    fn from(value: TopicPostBoostUserState) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostBoostState {
    pub id: u64,
    pub cooked: String,
    pub render_document: Option<RenderDocumentState>,
    pub display_text: String,
    pub user: TopicPostBoostUserState,
    pub can_delete: bool,
    pub can_flag: bool,
    pub user_flag_status: Option<i32>,
    pub available_flags: Vec<String>,
}

impl From<TopicPostBoost> for TopicPostBoostState {
    fn from(value: TopicPostBoost) -> Self {
        topic_post_boost_state_from_model(value, "https://linux.do")
    }
}

fn topic_post_boost_state_from_model(value: TopicPostBoost, base_url: &str) -> TopicPostBoostState {
    let render_document = render_document_state_from_cooked(&value.cooked, base_url);
    TopicPostBoostState {
        id: value.id,
        cooked: value.cooked,
        render_document,
        display_text: value.display_text,
        user: value.user.into(),
        can_delete: value.can_delete,
        can_flag: value.can_flag,
        user_flag_status: value.user_flag_status,
        available_flags: value.available_flags,
    }
}

impl From<TopicPostBoostState> for TopicPostBoost {
    fn from(value: TopicPostBoostState) -> Self {
        Self {
            id: value.id,
            cooked: value.cooked,
            display_text: value.display_text,
            user: value.user.into(),
            can_delete: value.can_delete,
            can_flag: value.can_flag,
            user_flag_status: value.user_flag_status,
            available_flags: value.available_flags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub author_metadata: TopicPostAuthorMetadataState,
    pub cooked: String,
    pub render_document: Option<RenderDocumentState>,
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
    pub boosts: Vec<TopicPostBoostState>,
    pub can_boost: bool,
    pub polls: Vec<PollState>,
    pub accepted_answer: bool,
    pub can_accept_answer: bool,
    pub can_unaccept_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub hidden: bool,
}

fn render_document_state_from_cooked(cooked: &str, base_url: &str) -> Option<RenderDocumentState> {
    let trimmed = cooked.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(render_cooked_html(trimmed, base_url).into())
    }
}

pub(crate) fn topic_post_state_from_model(value: TopicPost, base_url: &str) -> TopicPostState {
    let render_document = render_document_state_from_cooked(&value.cooked, base_url);
    TopicPostState {
        id: value.id,
        username: value.username,
        name: value.name,
        avatar_template: value.avatar_template,
        author_metadata: value.author_metadata.into(),
        cooked: value.cooked,
        render_document,
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
        boosts: value
            .boosts
            .into_iter()
            .map(|boost| topic_post_boost_state_from_model(boost, base_url))
            .collect(),
        can_boost: value.can_boost,
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

impl From<TopicReplyToUserState> for TopicReplyToUser {
    fn from(value: TopicReplyToUserState) -> Self {
        Self {
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

impl From<TopicPostState> for TopicPost {
    fn from(value: TopicPostState) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            author_metadata: value.author_metadata.into(),
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
            boosts: value.boosts.into_iter().map(Into::into).collect(),
            can_boost: value.can_boost,
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

fn topic_post_stream_state_from_model(
    value: TopicPostStream,
    base_url: &str,
) -> TopicPostStreamState {
    TopicPostStreamState {
        posts: value
            .posts
            .into_iter()
            .map(|post| topic_post_state_from_model(post, base_url))
            .collect(),
        stream: value.stream,
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
    pub source_snapshot: TopicDetailSourceSnapshotState,
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
        source_snapshot: topic_detail_source_snapshot_state_from_model(
            value.source_snapshot,
            base_url,
        ),
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
