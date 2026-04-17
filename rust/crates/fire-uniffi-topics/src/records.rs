use fire_models::{
    Poll, PollOption, PostReactionUpdate, PostUpdateRequest, PrivateMessageCreateRequest,
    ResolvedUploadUrl, TopicCreateRequest, TopicDetail, TopicDetailCreatedBy, TopicDetailMeta,
    TopicDetailQuery, TopicListQuery, TopicPost, TopicPostStream, TopicReaction, TopicReplyRequest,
    TopicThread, TopicThreadFlatPost, TopicThreadReply, TopicThreadSection, TopicTimelineEntry,
    TopicTimingEntry, TopicTimingsRequest, TopicUpdateRequest, UploadResult, VoteResponse,
    VotedUser,
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
            filter: value.filter,
            username_filters: value.username_filters,
            filter_top_level_replies: value.filter_top_level_replies,
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
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub reactions: Vec<TopicReactionState>,
    pub current_user_reaction: Option<TopicReactionState>,
    pub polls: Vec<PollState>,
    pub accepted_answer: bool,
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
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
            polls: value.polls.into_iter().map(Into::into).collect(),
            accepted_answer: value.accepted_answer,
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
pub struct TopicThreadReplyState {
    pub post_number: u32,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
}

impl From<TopicThreadReply> for TopicThreadReplyState {
    fn from(value: TopicThreadReply) -> Self {
        Self {
            post_number: value.post_number,
            depth: value.depth,
            parent_post_number: value.parent_post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadSectionState {
    pub anchor_post_number: u32,
    pub replies: Vec<TopicThreadReplyState>,
}

impl From<TopicThreadSection> for TopicThreadSectionState {
    fn from(value: TopicThreadSection) -> Self {
        Self {
            anchor_post_number: value.anchor_post_number,
            replies: value.replies.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadState {
    pub original_post_number: Option<u32>,
    pub reply_sections: Vec<TopicThreadSectionState>,
}

impl From<TopicThread> for TopicThreadState {
    fn from(value: TopicThread) -> Self {
        Self {
            original_post_number: value.original_post_number,
            reply_sections: value.reply_sections.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadFlatPostState {
    pub post: TopicPostState,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
    pub shows_thread_line: bool,
    pub is_original_post: bool,
}

impl From<TopicThreadFlatPost> for TopicThreadFlatPostState {
    fn from(value: TopicThreadFlatPost) -> Self {
        Self {
            post: value.post.into(),
            depth: value.depth,
            parent_post_number: value.parent_post_number,
            shows_thread_line: value.shows_thread_line,
            is_original_post: value.is_original_post,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTimelineEntryState {
    pub post_id: u64,
    pub post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u32,
    pub is_original_post: bool,
}

impl From<TopicTimelineEntry> for TopicTimelineEntryState {
    fn from(value: TopicTimelineEntry) -> Self {
        Self {
            post_id: value.post_id,
            post_number: value.post_number,
            parent_post_number: value.parent_post_number,
            depth: value.depth,
            is_original_post: value.is_original_post,
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
pub struct TopicDetailState {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTagState>,
    pub views: u32,
    pub like_count: u32,
    pub interaction_count: u32,
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
    pub thread: TopicThreadState,
    pub flat_posts: Vec<TopicThreadFlatPostState>,
    pub timeline_entries: Vec<TopicTimelineEntryState>,
    pub details: TopicDetailMetaState,
}

impl From<TopicDetail> for TopicDetailState {
    fn from(value: TopicDetail) -> Self {
        let interaction_count = value.interaction_count();
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            category_id: value.category_id,
            tags: value.tags.into_iter().map(Into::into).collect(),
            views: value.views,
            like_count: value.like_count,
            interaction_count,
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
            thread: value.thread.into(),
            flat_posts: value.flat_posts.into_iter().map(Into::into).collect(),
            timeline_entries: value.timeline_entries.into_iter().map(Into::into).collect(),
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
