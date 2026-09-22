use std::sync::Arc;

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
    intern_presented_handle, RenderDocumentHandle, TopicListKindState, TopicParticipantState,
    TopicTagState,
};

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
