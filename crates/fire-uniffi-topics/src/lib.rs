uniffi::setup_scaffolding!("fire_uniffi_topics");

use std::sync::Arc;

use fire_uniffi_types::{run_on_ffi_runtime, FireUniFfiError, SharedFireCore, TopicListState};

pub mod records;
mod session;
mod ui_records;

pub use session::{TopicDetailObserver, TopicDetailSessionHandle, TopicDetailSnapshotHandle};
pub use ui_records::{
    TopicDetailAuthorDisplayState, TopicDetailBoostDisplayState, TopicDetailChromeState,
    TopicDetailComposerModelState, TopicDetailLoadErrorState, TopicDetailNoticeState,
    TopicDetailOpenRequestState, TopicDetailPhaseState, TopicDetailReplyContextChangeState,
    TopicDetailReplyContextState, TopicDetailRevisionsState, TopicDetailSidecarModelState,
    TopicDetailSnapshotChangeState, TopicDetailStatusState, TopicDetailUiRowState,
    TopicDetailUiSnapshotState, TopicHomeRowCountPatchState, TopicHomeUnreadDecisionState,
    TopicListRowPatchBatchState,
};

pub use records::{
    LoadMoreTopicPostsQueryState, PollOptionState, PollState, PostActionTypeState,
    PostFlagRequestState, PostReactionUpdateState, PostUpdateRequestState,
    PrivateMessageCreateRequestState, ReactionUserState, ReactionUsersGroupState,
    ResolvedUploadUrlState, TopicAiSummaryState, TopicBodyState, TopicCreateRequestState,
    TopicDetailCreatedByState, TopicDetailMetaState, TopicDetailPageState,
    TopicDetailSourceQueryState, TopicDetailSourceSnapshotState, TopicDetailState,
    TopicHeaderState, TopicListQueryState, TopicLoadMoreOutcomeState, TopicLoadMoreStopReasonState,
    TopicLoadedRangeState, TopicPostAuthorMetadataState, TopicPostBoostState,
    TopicPostBoostUserState, TopicPostState, TopicPostStreamState, TopicReactionState,
    TopicReplyRequestState, TopicReplyToUserState, TopicSourceCursorState, TopicTimingEntryState,
    TopicTimingsRequestState, TopicTreePresentationState, TopicTreeRowState,
    TopicUpdateRequestState, UploadImageRequestState, UploadResultState, VoteResponseState,
    VotedUserState,
};

#[derive(uniffi::Object)]
pub struct FireTopicsHandle {
    shared: Arc<SharedFireCore>,
}

impl FireTopicsHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

include!("handle/lists.rs");
include!("handle/posts.rs");
include!("handle/creation.rs");
include!("handle/reactions.rs");
include!("handle/solutions.rs");
include!("handle/polls.rs");
