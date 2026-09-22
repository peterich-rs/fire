use std::sync::Arc;

use fire_models::{
    PostActionType, PostFlagRequest, PostReactionUpdate, PostUpdateRequest,
    PrivateMessageCreateRequest, ReactionUser, ReactionUsersGroup, TopicCreateRequest, TopicPost,
    TopicPostAuthorMetadata, TopicPostBoost, TopicPostBoostUser, TopicPostStream, TopicReaction,
    TopicReplyRequest, TopicReplyToUser, TopicUpdateRequest,
};

use super::poll::PollState;

use fire_uniffi_types::{intern_presented_handle, RenderDocumentHandle};

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
    pub presentation: Option<Arc<RenderDocumentHandle>>,
    pub display_text: String,
    pub user: TopicPostBoostUserState,
    pub can_delete: bool,
    pub can_flag: bool,
    pub user_flag_status: Option<i32>,
    pub available_flags: Vec<String>,
}

pub(crate) fn topic_post_boost_state_from_model(
    value: TopicPostBoost,
    _base_url: &str,
) -> TopicPostBoostState {
    let presentation = handle_from_presented(value.presented.arc());
    TopicPostBoostState {
        id: value.id,
        presentation,
        display_text: value.display_text,
        user: value.user.into(),
        can_delete: value.can_delete,
        can_flag: value.can_flag,
        user_flag_status: value.user_flag_status,
        available_flags: value.available_flags,
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub author_metadata: TopicPostAuthorMetadataState,
    pub presentation: Option<Arc<RenderDocumentHandle>>,
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

fn handle_from_presented(
    presented: Option<Arc<fire_models::PresentedDocument>>,
) -> Option<Arc<RenderDocumentHandle>> {
    presented.map(intern_presented_handle)
}

pub(crate) fn topic_post_state_from_model(value: TopicPost, base_url: &str) -> TopicPostState {
    topic_post_state_from_model_ex(value, base_url, false)
}

pub(crate) fn topic_post_state_from_model_with_raw(
    value: TopicPost,
    base_url: &str,
) -> TopicPostState {
    topic_post_state_from_model_ex(value, base_url, true)
}

fn topic_post_state_from_model_ex(
    value: TopicPost,
    base_url: &str,
    include_raw: bool,
) -> TopicPostState {
    let presentation = handle_from_presented(value.presented.arc());
    TopicPostState {
        id: value.id,
        username: value.username,
        name: value.name,
        avatar_template: value.avatar_template,
        author_metadata: value.author_metadata.into(),
        presentation,
        raw: include_raw.then_some(value.raw).flatten(),
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

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostStreamState {
    pub posts: Vec<TopicPostState>,
    pub stream: Vec<u64>,
}

pub(super) fn topic_post_stream_state_from_model(
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
