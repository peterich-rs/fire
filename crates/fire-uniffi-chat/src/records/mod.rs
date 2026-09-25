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

include!("mapper.rs");
include!("users.rs");
include!("attachments.rs");
include!("messages.rs");
include!("channels.rs");
include!("requests.rs");
include!("bus.rs");
