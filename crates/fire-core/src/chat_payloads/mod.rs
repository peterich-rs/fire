use fire_models::{
    ChatBusEvent, ChatBusLastIdEntry, ChatChannel, ChatChannelBusLastIds, ChatChannelMember,
    ChatChannelMembership, ChatChannelTrackingEntry, ChatMessage, ChatMessageBookmark,
    ChatMessageReaction, ChatMessageReplyRef, ChatMessagesResponse, ChatReactionAction,
    ChatSearchResult, ChatThreadRef, ChatUpload, ChatUser, MyChatChannelsResponse,
};
use serde_json::Value;
use tracing::warn;

use crate::json_helpers::{
    boolean, integer_i32, integer_i64, integer_u32, integer_u64, invalid_json, object_field,
    parse_array_items_lossy, scalar_string,
};

include!("channels.rs");
include!("messages.rs");
include!("members.rs");
include!("bus.rs");
include!("nested.rs");
include!("helpers.rs");
include!("tests.rs");
