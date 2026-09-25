use std::sync::Arc;

use fire_models::{
    BrowseChatChannelsQuery, ChatBusEvent, ChatBusLastIdEntry, ChatChannel, ChatChannelBusLastIds,
    ChatChannelMember, ChatChannelMembership, ChatChannelTrackingEntry, ChatMessage,
    ChatMessageBookmark, ChatMessageReaction, ChatMessageReplyRef, ChatMessagesQuery,
    ChatMessagesResponse, ChatReactionAction, ChatSearchQuery, ChatSearchResult, ChatThreadRef,
    ChatUpload, ChatUser, CreateDirectMessageChannelRequest, MyChatChannelsResponse,
    SendChatMessageRequest, SendChatMessageResult,
};
use fire_uniffi_types::{intern_presented_handle, RenderDocumentHandle};

#[derive(Clone, Copy)]
pub(crate) struct ChatStateMapper<'a> {
    base_url: &'a str,
}

impl<'a> ChatStateMapper<'a> {
    pub(crate) fn new(base_url: &'a str) -> Self {
        Self { base_url }
    }

    pub(crate) fn message(&self, value: ChatMessage) -> ChatMessageState {
        chat_message_state_from_model(value, self.base_url)
    }

    pub(crate) fn channel(&self, value: ChatChannel) -> ChatChannelState {
        chat_channel_state_from_model(value, self.base_url)
    }

    pub(crate) fn messages(&self, value: ChatMessagesResponse) -> ChatMessagesState {
        ChatMessagesState {
            messages: value
                .messages
                .into_iter()
                .map(|message| self.message(message))
                .collect(),
            can_load_more_past: value.can_load_more_past,
            can_load_more_future: value.can_load_more_future,
            target_message_id: value.target_message_id,
        }
    }

    pub(crate) fn my_channels(&self, value: MyChatChannelsResponse) -> MyChatChannelsState {
        let total_unread_badge = value.total_unread_badge();
        let inbox_channels = value
            .inbox_channels()
            .into_iter()
            .cloned()
            .map(|channel| self.channel(channel))
            .collect();
        MyChatChannelsState {
            public_channels: value
                .public_channels
                .into_iter()
                .map(|channel| self.channel(channel))
                .collect(),
            direct_message_channels: value
                .direct_message_channels
                .into_iter()
                .map(|channel| self.channel(channel))
                .collect(),
            inbox_channels,
            channel_tracking: value.channel_tracking.into_iter().map(Into::into).collect(),
            global_bus_last_ids: value
                .global_bus_last_ids
                .into_iter()
                .map(Into::into)
                .collect(),
            total_unread_badge,
        }
    }

    pub(crate) fn search_result(&self, value: ChatSearchResult) -> ChatSearchResultState {
        ChatSearchResultState {
            messages: value
                .messages
                .into_iter()
                .map(|message| self.message(message))
                .collect(),
            has_more: value.has_more,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<ChatUser> for ChatUserState {
    fn from(value: ChatUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelMembershipState {
    pub following: bool,
    pub muted: bool,
    pub starred: bool,
    pub notification_level: Option<String>,
    pub last_read_message_id: Option<u64>,
    pub last_viewed_at: Option<String>,
}

impl From<ChatChannelMembership> for ChatChannelMembershipState {
    fn from(value: ChatChannelMembership) -> Self {
        Self {
            following: value.following,
            muted: value.muted,
            starred: value.starred,
            notification_level: value.notification_level,
            last_read_message_id: value.last_read_message_id,
            last_viewed_at: value.last_viewed_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelBusLastIdsState {
    pub channel_message_bus_last_id: Option<i64>,
    pub new_messages: Option<i64>,
    pub new_mentions: Option<i64>,
    pub kick: Option<i64>,
}

impl From<ChatChannelBusLastIds> for ChatChannelBusLastIdsState {
    fn from(value: ChatChannelBusLastIds) -> Self {
        Self {
            channel_message_bus_last_id: value.channel_message_bus_last_id,
            new_messages: value.new_messages,
            new_mentions: value.new_mentions,
            kick: value.kick,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatUploadState {
    pub id: u64,
    pub url: Option<String>,
    pub short_url: Option<String>,
    pub original_filename: Option<String>,
    pub extension: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
    pub dominant_color: Option<String>,
}

impl From<ChatUpload> for ChatUploadState {
    fn from(value: ChatUpload) -> Self {
        Self {
            id: value.id,
            url: value.url,
            short_url: value.short_url,
            original_filename: value.original_filename,
            extension: value.extension,
            width: value.width,
            height: value.height,
            thumbnail_width: value.thumbnail_width,
            thumbnail_height: value.thumbnail_height,
            dominant_color: value.dominant_color,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessageReactionState {
    pub emoji: String,
    pub count: u32,
    pub reacted: bool,
    pub users: Vec<ChatUserState>,
}

impl From<ChatMessageReaction> for ChatMessageReactionState {
    fn from(value: ChatMessageReaction) -> Self {
        Self {
            emoji: value.emoji,
            count: value.count,
            reacted: value.reacted,
            users: value.users.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessageReplyRefState {
    pub id: u64,
    pub excerpt: Option<String>,
    pub user: Option<ChatUserState>,
}

impl From<ChatMessageReplyRef> for ChatMessageReplyRefState {
    fn from(value: ChatMessageReplyRef) -> Self {
        Self {
            id: value.id,
            excerpt: value.excerpt,
            user: value.user.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatThreadRefState {
    pub id: u64,
    pub title: Option<String>,
    pub reply_count: u32,
    pub last_reply_created_at: Option<String>,
    pub last_reply_excerpt: Option<String>,
    pub last_reply_user: Option<ChatUserState>,
    pub participants: Vec<ChatUserState>,
}

impl From<ChatThreadRef> for ChatThreadRefState {
    fn from(value: ChatThreadRef) -> Self {
        Self {
            id: value.id,
            title: value.title,
            reply_count: value.reply_count,
            last_reply_created_at: value.last_reply_created_at,
            last_reply_excerpt: value.last_reply_excerpt,
            last_reply_user: value.last_reply_user.map(Into::into),
            participants: value.participants.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessageBookmarkState {
    pub id: u64,
    pub name: Option<String>,
    pub reminder_at: Option<String>,
}

impl From<ChatMessageBookmark> for ChatMessageBookmarkState {
    fn from(value: ChatMessageBookmark) -> Self {
        Self {
            id: value.id,
            name: value.name,
            reminder_at: value.reminder_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessageState {
    pub id: u64,
    pub channel_id: u64,
    pub message: String,
    pub presentation: Option<Arc<RenderDocumentHandle>>,
    pub excerpt: Option<String>,
    pub preview_text: String,
    pub created_at: Option<String>,
    pub deleted_at: Option<String>,
    pub deleted_by_id: Option<u64>,
    pub edited: bool,
    pub thread_id: Option<u64>,
    pub thread: Option<ChatThreadRefState>,
    pub user: Option<ChatUserState>,
    pub mentioned_users: Vec<ChatUserState>,
    pub reactions: Vec<ChatMessageReactionState>,
    pub uploads: Vec<ChatUploadState>,
    pub in_reply_to: Option<ChatMessageReplyRefState>,
    pub streaming: bool,
    pub available_flags: Vec<String>,
    pub user_flag_status: Option<i32>,
    pub bookmark: Option<ChatMessageBookmarkState>,
    pub pinned: bool,
    pub is_deleted: bool,
}

fn chat_message_state_from_model(value: ChatMessage, _base_url: &str) -> ChatMessageState {
    let preview_text = value.preview_text();
    let is_deleted = value.is_deleted();
    let presentation = value.presented.arc().map(intern_presented_handle);
    ChatMessageState {
        id: value.id,
        channel_id: value.channel_id,
        message: value.message,
        presentation,
        excerpt: value.excerpt,
        preview_text,
        created_at: value.created_at,
        deleted_at: value.deleted_at,
        deleted_by_id: value.deleted_by_id,
        edited: value.edited,
        thread_id: value.thread_id,
        thread: value.thread.map(Into::into),
        user: value.user.map(Into::into),
        mentioned_users: value.mentioned_users.into_iter().map(Into::into).collect(),
        reactions: value.reactions.into_iter().map(Into::into).collect(),
        uploads: value.uploads.into_iter().map(Into::into).collect(),
        in_reply_to: value.in_reply_to.map(Into::into),
        streaming: value.streaming,
        available_flags: value.available_flags,
        user_flag_status: value.user_flag_status,
        bookmark: value.bookmark.map(Into::into),
        pinned: value.pinned,
        is_deleted,
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelState {
    pub id: u64,
    pub title: Option<String>,
    pub unicode_title: Option<String>,
    pub display_title: String,
    pub slug: Option<String>,
    pub description: Option<String>,
    pub chatable_type: String,
    pub status: Option<String>,
    pub threading_enabled: bool,
    pub memberships_count: Option<u32>,
    pub is_group_dm: bool,
    pub is_direct_message: bool,
    pub is_public_channel: bool,
    pub dm_users: Vec<ChatUserState>,
    pub category_color: Option<String>,
    pub category_name: Option<String>,
    pub emoji: Option<String>,
    pub formatted_emoji: Option<String>,
    pub current_user_membership: Option<ChatChannelMembershipState>,
    pub last_message: Option<ChatMessageState>,
    pub bus_last_ids: ChatChannelBusLastIdsState,
    pub can_moderate: bool,
    pub can_manage_pins: bool,
    pub can_delete_self: bool,
    pub can_delete_others: bool,
    pub can_remove_members: bool,
    pub can_flag: bool,
}

fn chat_channel_state_from_model(value: ChatChannel, base_url: &str) -> ChatChannelState {
    let display_title = value.display_title();
    let is_direct_message = value.is_direct_message();
    let is_public_channel = value.is_public_channel();
    let formatted_emoji = value.formatted_emoji();
    ChatChannelState {
        id: value.id,
        title: value.title,
        unicode_title: value.unicode_title,
        display_title,
        slug: value.slug,
        description: value.description,
        chatable_type: value.chatable_type,
        status: value.status,
        threading_enabled: value.threading_enabled,
        memberships_count: value.memberships_count,
        is_group_dm: value.is_group_dm,
        is_direct_message,
        is_public_channel,
        dm_users: value.dm_users.into_iter().map(Into::into).collect(),
        category_color: value.category_color,
        category_name: value.category_name,
        emoji: value.emoji,
        formatted_emoji,
        current_user_membership: value.current_user_membership.map(Into::into),
        last_message: value
            .last_message
            .map(|message| chat_message_state_from_model(message, base_url)),
        bus_last_ids: value.bus_last_ids.into(),
        can_moderate: value.can_moderate,
        can_manage_pins: value.can_manage_pins,
        can_delete_self: value.can_delete_self,
        can_delete_others: value.can_delete_others,
        can_remove_members: value.can_remove_members,
        can_flag: value.can_flag,
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelTrackingEntryState {
    pub channel_id: u64,
    pub unread_count: u32,
    pub mention_count: u32,
}

impl From<ChatChannelTrackingEntry> for ChatChannelTrackingEntryState {
    fn from(value: ChatChannelTrackingEntry) -> Self {
        Self {
            channel_id: value.channel_id,
            unread_count: value.unread_count,
            mention_count: value.mention_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatBusLastIdEntryState {
    pub channel: String,
    pub last_id: i64,
}

impl From<ChatBusLastIdEntry> for ChatBusLastIdEntryState {
    fn from(value: ChatBusLastIdEntry) -> Self {
        Self {
            channel: value.channel,
            last_id: value.last_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct MyChatChannelsState {
    pub public_channels: Vec<ChatChannelState>,
    pub direct_message_channels: Vec<ChatChannelState>,
    pub inbox_channels: Vec<ChatChannelState>,
    pub channel_tracking: Vec<ChatChannelTrackingEntryState>,
    pub global_bus_last_ids: Vec<ChatBusLastIdEntryState>,
    pub total_unread_badge: u32,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessagesQueryState {
    pub channel_id: u64,
    pub direction: Option<String>,
    pub target_message_id: Option<u64>,
    pub fetch_from_last_read: bool,
    pub page_size: Option<u32>,
}

impl From<ChatMessagesQueryState> for ChatMessagesQuery {
    fn from(value: ChatMessagesQueryState) -> Self {
        Self {
            channel_id: value.channel_id,
            direction: value.direction,
            target_message_id: value.target_message_id,
            fetch_from_last_read: value.fetch_from_last_read,
            page_size: value.page_size,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessagesState {
    pub messages: Vec<ChatMessageState>,
    pub can_load_more_past: bool,
    pub can_load_more_future: bool,
    pub target_message_id: Option<u64>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CreateDirectMessageChannelRequestState {
    pub target_usernames: Vec<String>,
    pub name: Option<String>,
    pub upsert: bool,
}

impl From<CreateDirectMessageChannelRequestState> for CreateDirectMessageChannelRequest {
    fn from(value: CreateDirectMessageChannelRequestState) -> Self {
        Self {
            target_usernames: value.target_usernames,
            name: value.name,
            upsert: value.upsert,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SendChatMessageRequestState {
    pub channel_id: u64,
    pub message: String,
    pub staged_id: Option<String>,
    pub in_reply_to_id: Option<u64>,
    pub thread_id: Option<u64>,
    pub upload_ids: Vec<u64>,
}

impl From<SendChatMessageRequestState> for SendChatMessageRequest {
    fn from(value: SendChatMessageRequestState) -> Self {
        Self {
            channel_id: value.channel_id,
            message: value.message,
            staged_id: value.staged_id,
            in_reply_to_id: value.in_reply_to_id,
            thread_id: value.thread_id,
            upload_ids: value.upload_ids,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SendChatMessageResultState {
    pub message_id: Option<u64>,
}

impl From<SendChatMessageResult> for SendChatMessageResultState {
    fn from(value: SendChatMessageResult) -> Self {
        Self {
            message_id: value.message_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BrowseChatChannelsQueryState {
    pub filter: Option<String>,
    pub offset: Option<u32>,
    pub limit: Option<u32>,
}

impl From<BrowseChatChannelsQueryState> for BrowseChatChannelsQuery {
    fn from(value: BrowseChatChannelsQueryState) -> Self {
        Self {
            filter: value.filter,
            offset: value.offset,
            limit: value.limit,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelMemberState {
    pub user: ChatUserState,
    pub following: bool,
    pub muted: bool,
}

impl From<ChatChannelMember> for ChatChannelMemberState {
    fn from(value: ChatChannelMember) -> Self {
        Self {
            user: value.user.into(),
            following: value.following,
            muted: value.muted,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatSearchQueryState {
    pub query: String,
    pub channel_id: Option<u64>,
    pub offset: Option<u32>,
    pub limit: Option<u32>,
}

impl From<ChatSearchQueryState> for ChatSearchQuery {
    fn from(value: ChatSearchQueryState) -> Self {
        Self {
            query: value.query,
            channel_id: value.channel_id,
            offset: value.offset,
            limit: value.limit,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatSearchResultState {
    pub messages: Vec<ChatMessageState>,
    pub has_more: bool,
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum ChatReactionActionState {
    Add,
    Remove,
}

impl From<ChatReactionAction> for ChatReactionActionState {
    fn from(value: ChatReactionAction) -> Self {
        match value {
            ChatReactionAction::Add => Self::Add,
            ChatReactionAction::Remove => Self::Remove,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum ChatBusEventState {
    MessageUpsert {
        message: ChatMessageState,
    },
    MessageDeleted {
        id: u64,
    },
    Reaction {
        message_id: u64,
        emoji: String,
        action: ChatReactionActionState,
        actor_id: Option<u64>,
    },
    Tracking {
        channel_id: u64,
        unread: u32,
        mention: u32,
        thread_id: Option<u64>,
    },
    ChannelUpsert {
        channel: ChatChannelState,
    },
    NewMessages {
        channel_id: u64,
        is_channel_level: bool,
        message: Option<ChatMessageState>,
        actor_id: Option<u64>,
    },
    Ignored,
}

impl ChatStateMapper<'_> {
    pub(crate) fn bus_event(&self, value: ChatBusEvent) -> ChatBusEventState {
        match value {
            ChatBusEvent::MessageUpsert { message } => ChatBusEventState::MessageUpsert {
                message: self.message(*message),
            },
            ChatBusEvent::MessageDeleted { id } => ChatBusEventState::MessageDeleted { id },
            ChatBusEvent::Reaction {
                message_id,
                emoji,
                action,
                actor_id,
            } => ChatBusEventState::Reaction {
                message_id,
                emoji,
                action: action.into(),
                actor_id,
            },
            ChatBusEvent::Tracking {
                channel_id,
                unread,
                mention,
                thread_id,
            } => ChatBusEventState::Tracking {
                channel_id,
                unread,
                mention,
                thread_id,
            },
            ChatBusEvent::ChannelUpsert { channel } => ChatBusEventState::ChannelUpsert {
                channel: self.channel(*channel),
            },
            ChatBusEvent::NewMessages {
                channel_id,
                is_channel_level,
                message,
                actor_id,
            } => ChatBusEventState::NewMessages {
                channel_id,
                is_channel_level,
                message: message.map(|item| self.message(*item)),
                actor_id,
            },
            ChatBusEvent::Ignored => ChatBusEventState::Ignored,
        }
    }
}
