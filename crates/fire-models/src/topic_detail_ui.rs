use crate::rich_text::AttachedPresentation;
use crate::topic_detail::{Poll, PostActionType, TopicReaction};

/// Read-path login wake-up. Lives on runtime session state, not the persisted envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReadPathLoginRequest {
    pub generation: u64,
    pub operation: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TopicDetailPhase {
    Loading,
    Ready,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TopicDetailLoadError {
    Network,
    LoginRequired,
    Unrecoverable { message: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailNotice {
    pub title: Option<String>,
    pub message: String,
    pub retryable: bool,
    pub emphasizes_error: bool,
}

/// Unread formula copied from the removed Swift `patchedTopicRow`.
/// Swift assigns fields; it does not compare post numbers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TopicHomeUnreadDecision {
    /// `last_read` is None. If the row's `has_unread_posts` is false, zero both counts.
    /// If it is true, keep both counts. Leave the flag as it is.
    WhenLastReadMissing,
    /// `last_read >= highest`. Zero both counts. `has_unread_posts = false`.
    CaughtUp,
    /// `last_read < highest`. Keep both counts. `has_unread_posts = true`.
    StillUnread,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicHomeRowCountPatch {
    pub topic_id: u64,
    pub posts_count: u32,
    pub reply_count: u32,
    pub views: u32,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
    pub unread: TopicHomeUnreadDecision,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailAuthorDisplay {
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailParticipantDisplay {
    pub user_id: u64,
    pub username: String,
    pub name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailReactionChip {
    pub id: String,
    pub kind: Option<String>,
    pub count: u32,
    pub can_undo: Option<bool>,
    pub selected: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailPollOptionDisplay {
    pub id: String,
    pub html: String,
    pub plain_text: String,
    pub votes: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailPollDisplay {
    pub id: u64,
    pub name: String,
    pub kind: String,
    pub status: String,
    pub results: String,
    pub options: Vec<TopicDetailPollOptionDisplay>,
    pub voters: u32,
    pub user_votes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailBoostUserDisplay {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TopicDetailBoostDisplay {
    pub id: u64,
    pub display_text: String,
    pub user: TopicDetailBoostUserDisplay,
    pub can_delete: bool,
    pub can_flag: bool,
    pub user_flag_status: Option<i32>,
    pub available_flags: Vec<String>,
    pub presentation: AttachedPresentation,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailReplyUserDisplay {
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailTypingUser {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicDetailChrome {
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
    pub participants: Vec<TopicDetailParticipantDisplay>,
    pub summarizable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct TopicDetailComposerModel {
    pub typing_users: Vec<TopicDetailTypingUser>,
    pub is_submitting: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct TopicDetailSidecarModel {
    pub summarized_text: Option<String>,
    pub algorithm: Option<String>,
    pub outdated: bool,
    pub can_regenerate: bool,
    pub new_posts_since_summary: u32,
    pub updated_at: Option<String>,
    pub is_loading: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TopicDetailUiRow {
    pub post_id: u64,
    pub post_number: u32,
    pub root_post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u16,
    pub has_children: bool,
    pub is_last_sibling: bool,
    pub descendant_count: u32,
    pub author: TopicDetailAuthorDisplay,
    pub presentation: AttachedPresentation,
    pub layout_checksum: u64,
    pub interaction_checksum: u64,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub post_type: i32,
    pub reply_count: u32,
    pub reply_to_username: Option<String>,
    pub reply_to_user: Option<TopicDetailReplyUserDisplay>,
    pub like_count: u32,
    pub reactions: Vec<TopicDetailReactionChip>,
    pub current_reaction_id: Option<String>,
    pub polls: Vec<TopicDetailPollDisplay>,
    pub boosts: Vec<TopicDetailBoostDisplay>,
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

#[derive(Debug, Clone, PartialEq)]
pub struct TopicDetailReplyContext {
    pub root_post_id: u64,
    pub appended_post_ids: Vec<u64>,
    pub history_rows: Vec<TopicDetailUiRow>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TopicDetailUiSnapshot {
    pub topic_id: u64,
    pub generation: u64,
    pub phase: TopicDetailPhase,
    pub load_error: Option<TopicDetailLoadError>,
    pub notice: Option<TopicDetailNotice>,
    pub has_more: bool,
    pub is_loading_more: bool,
    pub load_more_error: Option<String>,
    pub scroll_target_post_number: Option<u32>,
    pub collection_revision: u64,
    pub chrome_revision: u64,
    pub sidecar_revision: u64,
    pub interaction_revision: u64,
    pub chrome: TopicDetailChrome,
    pub composer: TopicDetailComposerModel,
    pub sidecar: TopicDetailSidecarModel,
    pub rows: Vec<TopicDetailUiRow>,
    pub focused_reply_context: Option<TopicDetailReplyContext>,
    pub flag_types: Vec<PostActionType>,
    pub home_row_patch: Option<TopicHomeRowCountPatch>,
}

impl TopicDetailReactionChip {
    pub fn from_reaction(reaction: &TopicReaction, selected: bool) -> Self {
        Self {
            id: reaction.id.clone(),
            kind: reaction.kind.clone(),
            count: reaction.count,
            can_undo: reaction.can_undo,
            selected,
        }
    }
}

impl From<&Poll> for TopicDetailPollDisplay {
    fn from(poll: &Poll) -> Self {
        Self {
            id: poll.id,
            name: poll.name.clone(),
            kind: poll.kind.clone(),
            status: poll.status.clone(),
            results: poll.results.clone(),
            options: poll
                .options
                .iter()
                .map(|option| TopicDetailPollOptionDisplay {
                    id: option.id.clone(),
                    html: option.html.clone(),
                    plain_text: option.plain_text.clone(),
                    votes: option.votes,
                })
                .collect(),
            voters: poll.voters,
            user_votes: poll.user_votes.clone(),
        }
    }
}
