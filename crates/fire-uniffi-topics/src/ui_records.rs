use std::sync::Arc;

use fire_models::{
    TopicDetailAuthorDisplay, TopicDetailBoostDisplay, TopicDetailChrome, TopicDetailComposerModel,
    TopicDetailLoadError, TopicDetailNotice, TopicDetailPhase, TopicDetailPollDisplay,
    TopicDetailReactionChip, TopicDetailReplyContext, TopicDetailSidecarModel,
    TopicDetailTypingUser, TopicDetailUiRow, TopicDetailUiSnapshot, TopicHomeRowCountPatch,
    TopicHomeUnreadDecision, TopicListRowPatchBatch,
};
use fire_uniffi_types::{intern_presented_handle, RenderDocumentHandle, TopicListKindState};

use crate::records::{PollOptionState, PollState, PostActionTypeState};

fn presentation_handle(
    presented: &fire_models::AttachedPresentation,
) -> Option<Arc<RenderDocumentHandle>> {
    presented.arc().map(intern_presented_handle)
}

#[derive(uniffi::Enum, Debug, Clone, PartialEq, Eq)]
pub enum TopicDetailPhaseState {
    Loading,
    Ready,
    Failed,
}

impl From<TopicDetailPhase> for TopicDetailPhaseState {
    fn from(value: TopicDetailPhase) -> Self {
        match value {
            TopicDetailPhase::Loading => Self::Loading,
            TopicDetailPhase::Ready => Self::Ready,
            TopicDetailPhase::Failed => Self::Failed,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, PartialEq, Eq)]
pub enum TopicDetailLoadErrorState {
    Network,
    LoginRequired,
    Unrecoverable { message: String },
}

impl From<TopicDetailLoadError> for TopicDetailLoadErrorState {
    fn from(value: TopicDetailLoadError) -> Self {
        match value {
            TopicDetailLoadError::Network => Self::Network,
            TopicDetailLoadError::LoginRequired => Self::LoginRequired,
            TopicDetailLoadError::Unrecoverable { message } => Self::Unrecoverable { message },
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum TopicHomeUnreadDecisionState {
    WhenLastReadMissing,
    CaughtUp,
    StillUnread,
}

impl From<TopicHomeUnreadDecision> for TopicHomeUnreadDecisionState {
    fn from(value: TopicHomeUnreadDecision) -> Self {
        match value {
            TopicHomeUnreadDecision::WhenLastReadMissing => Self::WhenLastReadMissing,
            TopicHomeUnreadDecision::CaughtUp => Self::CaughtUp,
            TopicHomeUnreadDecision::StillUnread => Self::StillUnread,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailNoticeState {
    pub title: Option<String>,
    pub message: String,
    pub retryable: bool,
    pub emphasizes_error: bool,
}

impl From<TopicDetailNotice> for TopicDetailNoticeState {
    fn from(value: TopicDetailNotice) -> Self {
        Self {
            title: value.title,
            message: value.message,
            retryable: value.retryable,
            emphasizes_error: value.emphasizes_error,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicHomeRowCountPatchState {
    pub topic_id: u64,
    pub posts_count: u32,
    pub reply_count: u32,
    pub views: u32,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
    pub unread: TopicHomeUnreadDecisionState,
    pub unread_posts: Option<u32>,
    pub new_posts: Option<u32>,
}

impl From<TopicHomeRowCountPatch> for TopicHomeRowCountPatchState {
    fn from(value: TopicHomeRowCountPatch) -> Self {
        Self {
            topic_id: value.topic_id,
            posts_count: value.posts_count,
            reply_count: value.reply_count,
            views: value.views,
            last_read_post_number: value.last_read_post_number,
            highest_post_number: value.highest_post_number,
            unread: value.unread.into(),
            unread_posts: value.unread_posts,
            new_posts: value.new_posts,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicListRowPatchBatchState {
    pub kind: TopicListKindState,
    pub category_id: Option<u64>,
    pub tags: Vec<String>,
    pub patches: Vec<TopicHomeRowCountPatchState>,
}

impl From<TopicListRowPatchBatch> for TopicListRowPatchBatchState {
    fn from(value: TopicListRowPatchBatch) -> Self {
        Self {
            kind: value.scope.kind.into(),
            category_id: value.scope.category_id,
            tags: value.scope.tags,
            patches: value.patches.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailAuthorDisplayState {
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
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

impl From<TopicDetailAuthorDisplay> for TopicDetailAuthorDisplayState {
    fn from(value: TopicDetailAuthorDisplay) -> Self {
        Self {
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
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
pub struct TopicDetailParticipantDisplayState {
    pub user_id: u64,
    pub username: String,
    pub name: Option<String>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailReactionChipState {
    pub id: String,
    pub kind: Option<String>,
    pub count: u32,
    pub can_undo: Option<bool>,
    pub selected: bool,
}

impl From<TopicDetailReactionChip> for TopicDetailReactionChipState {
    fn from(value: TopicDetailReactionChip) -> Self {
        Self {
            id: value.id,
            kind: value.kind,
            count: value.count,
            can_undo: value.can_undo,
            selected: value.selected,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailBoostUserDisplayState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailBoostDisplayState {
    pub id: u64,
    pub display_text: String,
    pub user: TopicDetailBoostUserDisplayState,
    pub can_delete: bool,
    pub can_flag: bool,
    pub user_flag_status: Option<i32>,
    pub available_flags: Vec<String>,
    pub presentation: Option<Arc<RenderDocumentHandle>>,
}

impl From<TopicDetailBoostDisplay> for TopicDetailBoostDisplayState {
    fn from(value: TopicDetailBoostDisplay) -> Self {
        Self {
            id: value.id,
            display_text: value.display_text,
            user: TopicDetailBoostUserDisplayState {
                id: value.user.id,
                username: value.user.username,
                name: value.user.name,
                avatar_template: value.user.avatar_template,
            },
            can_delete: value.can_delete,
            can_flag: value.can_flag,
            user_flag_status: value.user_flag_status,
            available_flags: value.available_flags,
            presentation: presentation_handle(&value.presentation),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailReplyUserDisplayState {
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailTypingUserState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicDetailTypingUser> for TopicDetailTypingUserState {
    fn from(value: TopicDetailTypingUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailChromeState {
    pub title: String,
    pub slug: String,
    pub archetype: Option<String>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub notification_level: Option<i32>,
    pub can_edit: bool,
    pub category_id: Option<u64>,
    pub tags: Vec<String>,
    pub views: u32,
    pub posts_count: u32,
    pub reply_count: u32,
    pub like_count: u32,
    pub vote_count: i32,
    pub user_voted: bool,
    pub can_vote: bool,
    pub has_accepted_answer: bool,
    pub created_at: Option<String>,
    pub highest_post_number: u32,
    pub last_read_post_number: Option<u32>,
    pub participants: Vec<TopicDetailParticipantDisplayState>,
    pub summarizable: bool,
}

impl From<TopicDetailChrome> for TopicDetailChromeState {
    fn from(value: TopicDetailChrome) -> Self {
        Self {
            title: value.title,
            slug: value.slug,
            archetype: value.archetype,
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            notification_level: value.notification_level,
            can_edit: value.can_edit,
            category_id: value.category_id,
            tags: value.tags,
            views: value.views,
            posts_count: value.posts_count,
            reply_count: value.reply_count,
            like_count: value.like_count,
            vote_count: value.vote_count,
            user_voted: value.user_voted,
            can_vote: value.can_vote,
            has_accepted_answer: value.has_accepted_answer,
            created_at: value.created_at,
            highest_post_number: value.highest_post_number,
            last_read_post_number: value.last_read_post_number,
            participants: value
                .participants
                .into_iter()
                .map(|participant| TopicDetailParticipantDisplayState {
                    user_id: participant.user_id,
                    username: participant.username,
                    name: participant.name,
                })
                .collect(),
            summarizable: value.summarizable,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailComposerModelState {
    pub typing_users: Vec<TopicDetailTypingUserState>,
    pub is_submitting: bool,
}

impl From<TopicDetailComposerModel> for TopicDetailComposerModelState {
    fn from(value: TopicDetailComposerModel) -> Self {
        Self {
            typing_users: value.typing_users.into_iter().map(Into::into).collect(),
            is_submitting: value.is_submitting,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailSidecarModelState {
    pub summarized_text: Option<String>,
    pub algorithm: Option<String>,
    pub outdated: bool,
    pub can_regenerate: bool,
    pub new_posts_since_summary: u32,
    pub updated_at: Option<String>,
    pub is_loading: bool,
    pub error: Option<String>,
}

impl From<TopicDetailSidecarModel> for TopicDetailSidecarModelState {
    fn from(value: TopicDetailSidecarModel) -> Self {
        Self {
            summarized_text: value.summarized_text,
            algorithm: value.algorithm,
            outdated: value.outdated,
            can_regenerate: value.can_regenerate,
            new_posts_since_summary: value.new_posts_since_summary,
            updated_at: value.updated_at,
            is_loading: value.is_loading,
            error: value.error,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailUiRowState {
    pub post_id: u64,
    pub post_number: u32,
    pub root_post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u16,
    pub has_children: bool,
    pub is_last_sibling: bool,
    pub descendant_count: u32,
    pub author: TopicDetailAuthorDisplayState,
    pub presentation: Option<Arc<RenderDocumentHandle>>,
    pub layout_checksum: u64,
    pub interaction_checksum: u64,
    pub author_band_checksum: u64,
    pub text_band_checksum: u64,
    pub actions_band_checksum: u64,
    pub reactions_band_checksum: u64,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub post_type: i32,
    pub reply_count: u32,
    pub reply_to_username: Option<String>,
    pub reply_to_user: Option<TopicDetailReplyUserDisplayState>,
    pub like_count: u32,
    pub reactions: Vec<TopicDetailReactionChipState>,
    pub current_reaction_id: Option<String>,
    pub polls: Vec<PollState>,
    pub boosts: Vec<TopicDetailBoostDisplayState>,
    pub accepted_answer: bool,
    pub can_accept_answer: bool,
    pub can_unaccept_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub can_boost: bool,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub hidden: bool,
    pub is_mutating: bool,
    pub is_loading_reply_context: bool,
    pub is_original_post: bool,
}

impl From<&TopicDetailUiRow> for TopicDetailUiRowState {
    fn from(value: &TopicDetailUiRow) -> Self {
        Self::from(value.clone())
    }
}

impl From<TopicDetailUiRow> for TopicDetailUiRowState {
    fn from(value: TopicDetailUiRow) -> Self {
        Self {
            post_id: value.post_id,
            post_number: value.post_number,
            root_post_number: value.root_post_number,
            parent_post_number: value.parent_post_number,
            depth: value.depth,
            has_children: value.has_children,
            is_last_sibling: value.is_last_sibling,
            descendant_count: value.descendant_count,
            author: value.author.into(),
            presentation: presentation_handle(&value.presentation),
            layout_checksum: value.layout_checksum,
            interaction_checksum: value.interaction_checksum,
            author_band_checksum: value.author_band_checksum,
            text_band_checksum: value.text_band_checksum,
            actions_band_checksum: value.actions_band_checksum,
            reactions_band_checksum: value.reactions_band_checksum,
            created_at: value.created_at,
            updated_at: value.updated_at,
            post_type: value.post_type,
            reply_count: value.reply_count,
            reply_to_username: value.reply_to_username,
            reply_to_user: value
                .reply_to_user
                .map(|user| TopicDetailReplyUserDisplayState {
                    username: user.username,
                    name: user.name,
                    avatar_template: user.avatar_template,
                }),
            like_count: value.like_count,
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_reaction_id: value.current_reaction_id,
            polls: value
                .polls
                .into_iter()
                .map(poll_state_from_display)
                .collect(),
            boosts: value.boosts.into_iter().map(Into::into).collect(),
            accepted_answer: value.accepted_answer,
            can_accept_answer: value.can_accept_answer,
            can_unaccept_answer: value.can_unaccept_answer,
            can_edit: value.can_edit,
            can_delete: value.can_delete,
            can_recover: value.can_recover,
            can_boost: value.can_boost,
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            hidden: value.hidden,
            is_mutating: value.is_mutating,
            is_loading_reply_context: value.is_loading_reply_context,
            is_original_post: value.is_original_post,
        }
    }
}

fn poll_state_from_display(poll: TopicDetailPollDisplay) -> PollState {
    PollState {
        id: poll.id,
        name: poll.name,
        kind: poll.kind,
        status: poll.status,
        results: poll.results,
        options: poll
            .options
            .into_iter()
            .map(|option| PollOptionState {
                id: option.id,
                html: option.html,
                plain_text: option.plain_text,
                votes: option.votes,
            })
            .collect(),
        voters: poll.voters,
        user_votes: poll.user_votes,
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailReplyContextState {
    pub root_post_id: u64,
    pub appended_post_ids: Vec<u64>,
    pub history_rows: Vec<TopicDetailUiRowState>,
}

impl From<TopicDetailReplyContext> for TopicDetailReplyContextState {
    fn from(value: TopicDetailReplyContext) -> Self {
        Self {
            root_post_id: value.root_post_id,
            appended_post_ids: value.appended_post_ids,
            history_rows: value.history_rows.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailUiSnapshotState {
    pub topic_id: u64,
    pub generation: u64,
    pub phase: TopicDetailPhaseState,
    pub load_error: Option<TopicDetailLoadErrorState>,
    pub notice: Option<TopicDetailNoticeState>,
    pub has_more: bool,
    pub is_loading_more: bool,
    pub load_more_error: Option<String>,
    pub scroll_target_post_number: Option<u32>,
    pub collection_revision: u64,
    pub chrome_revision: u64,
    pub sidecar_revision: u64,
    pub interaction_revision: u64,
    pub composer_revision: u64,
    pub chrome: TopicDetailChromeState,
    pub composer: TopicDetailComposerModelState,
    pub sidecar: TopicDetailSidecarModelState,
    pub rows: Vec<TopicDetailUiRowState>,
    pub focused_reply_context: Option<TopicDetailReplyContextState>,
    pub flag_types: Vec<PostActionTypeState>,
    pub home_row_patch: Option<TopicHomeRowCountPatchState>,
}

impl TopicDetailUiSnapshotState {
    pub fn from_core(snapshot: TopicDetailUiSnapshot) -> Self {
        Self::from_core_ref(&snapshot)
    }

    pub fn from_core_ref(snapshot: &TopicDetailUiSnapshot) -> Self {
        Self {
            topic_id: snapshot.topic_id,
            generation: snapshot.generation,
            phase: snapshot.phase.into(),
            load_error: snapshot.load_error.clone().map(Into::into),
            notice: snapshot.notice.clone().map(Into::into),
            has_more: snapshot.has_more,
            is_loading_more: snapshot.is_loading_more,
            load_more_error: snapshot.load_more_error.clone(),
            scroll_target_post_number: snapshot.scroll_target_post_number,
            collection_revision: snapshot.collection_revision,
            chrome_revision: snapshot.chrome_revision,
            sidecar_revision: snapshot.sidecar_revision,
            interaction_revision: snapshot.interaction_revision,
            composer_revision: snapshot.composer_revision,
            chrome: snapshot.chrome.clone().into(),
            composer: snapshot.composer.clone().into(),
            sidecar: snapshot.sidecar.clone().into(),
            rows: snapshot
                .rows
                .iter()
                .map(TopicDetailUiRowState::from)
                .collect(),
            focused_reply_context: snapshot.focused_reply_context.clone().map(Into::into),
            flag_types: snapshot
                .flag_types
                .iter()
                .cloned()
                .map(PostActionTypeState::from)
                .collect(),
            home_row_patch: snapshot.home_row_patch.clone().map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailRevisionsState {
    pub collection: u64,
    pub chrome: u64,
    pub sidecar: u64,
    pub interaction: u64,
    pub composer: u64,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailStatusState {
    pub phase: TopicDetailPhaseState,
    pub load_error: Option<TopicDetailLoadErrorState>,
    pub notice: Option<TopicDetailNoticeState>,
    pub has_more: bool,
    pub is_loading_more: bool,
    pub load_more_error: Option<String>,
    pub scroll_target_post_number: Option<u32>,
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum TopicDetailReplyContextChangeState {
    Unchanged,
    Cleared,
    Set {
        context: TopicDetailReplyContextState,
    },
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailSnapshotChangeState {
    pub topic_id: u64,
    pub generation: u64,
    pub base_generation: Option<u64>,
    pub revisions: TopicDetailRevisionsState,
    pub status: Option<TopicDetailStatusState>,
    pub chrome: Option<TopicDetailChromeState>,
    pub composer: Option<TopicDetailComposerModelState>,
    pub sidecar: Option<TopicDetailSidecarModelState>,
    pub reply_context: TopicDetailReplyContextChangeState,
    pub flag_types: Option<Vec<PostActionTypeState>>,
    pub row_order: Option<Vec<u64>>,
    pub upserted_rows: Vec<TopicDetailUiRowState>,
    pub home_row_patch: Option<TopicHomeRowCountPatchState>,
}

impl TopicDetailSnapshotChangeState {
    pub fn from_core(change: &fire_models::TopicDetailSnapshotChange) -> Self {
        let snapshot = change.snapshot.as_ref();
        let first = change.base_generation.is_none();
        Self {
            topic_id: snapshot.topic_id,
            generation: snapshot.generation,
            base_generation: change.base_generation,
            revisions: TopicDetailRevisionsState {
                collection: snapshot.collection_revision,
                chrome: snapshot.chrome_revision,
                sidecar: snapshot.sidecar_revision,
                interaction: snapshot.interaction_revision,
                composer: snapshot.composer_revision,
            },
            status: change.regions.status.then(|| TopicDetailStatusState {
                phase: snapshot.phase.into(),
                load_error: snapshot.load_error.clone().map(Into::into),
                notice: snapshot.notice.clone().map(Into::into),
                has_more: snapshot.has_more,
                is_loading_more: snapshot.is_loading_more,
                load_more_error: snapshot.load_more_error.clone(),
                scroll_target_post_number: snapshot.scroll_target_post_number,
            }),
            chrome: change
                .regions
                .chrome
                .then(|| snapshot.chrome.clone().into()),
            composer: change
                .regions
                .composer
                .then(|| snapshot.composer.clone().into()),
            sidecar: change
                .regions
                .sidecar
                .then(|| snapshot.sidecar.clone().into()),
            reply_context: if !change.regions.reply_context {
                TopicDetailReplyContextChangeState::Unchanged
            } else {
                match snapshot.focused_reply_context.as_ref() {
                    None => TopicDetailReplyContextChangeState::Cleared,
                    Some(context) => TopicDetailReplyContextChangeState::Set {
                        context: context.clone().into(),
                    },
                }
            },
            flag_types: change.regions.flag_types.then(|| {
                snapshot
                    .flag_types
                    .iter()
                    .cloned()
                    .map(PostActionTypeState::from)
                    .collect()
            }),
            row_order: change
                .order_changed
                .then(|| snapshot.rows.iter().map(|row| row.post_id).collect()),
            upserted_rows: if first {
                Vec::new()
            } else {
                change
                    .upserted_post_ids
                    .iter()
                    .filter_map(|post_id| {
                        snapshot
                            .rows
                            .iter()
                            .find(|row| row.post_id == *post_id)
                            .map(TopicDetailUiRowState::from)
                    })
                    .collect()
            },
            home_row_patch: snapshot.home_row_patch.clone().map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailOpenRequestState {
    pub topic_id: u64,
    pub owner_token: String,
    pub slug_hint: Option<String>,
    pub target_post_number: Option<u32>,
    pub bypass_cache: bool,
    pub force_load: bool,
    pub track_visit: bool,
    pub allow_suggested_unread_root: bool,
}

impl TopicDetailOpenRequestState {
    pub fn into_core(self) -> fire_core::TopicDetailOpenRequest {
        fire_core::TopicDetailOpenRequest {
            topic_id: self.topic_id,
            owner_token: self.owner_token,
            slug_hint: self.slug_hint,
            target_post_number: self.target_post_number,
            bypass_cache: self.bypass_cache,
            force_load: self.force_load,
            track_visit: self.track_visit,
            allow_suggested_unread_root: self.allow_suggested_unread_root,
        }
    }
}
