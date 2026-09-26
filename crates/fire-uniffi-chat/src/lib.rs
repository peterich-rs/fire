uniffi::setup_scaffolding!("fire_uniffi_chat");

use std::sync::Arc;

use fire_uniffi_types::{run_infallible, run_on_ffi_runtime, FireUniFfiError, SharedFireCore};

pub mod records;

use records::ChatStateMapper;

pub use records::{
    BrowseChatChannelsQueryState, ChatBusEventState, ChatBusLastIdEntryState,
    ChatChannelBusLastIdsState, ChatChannelMemberState, ChatChannelMembershipState,
    ChatChannelRuntimeState, ChatChannelState, ChatChannelTrackingEntryState,
    ChatMessageBookmarkState,
    ChatMessageReactionState, ChatMessageReplyRefState, ChatMessageState, ChatMessagesQueryState,
    ChatMessagesState, ChatReactionActionState, ChatSearchQueryState, ChatSearchResultState,
    ChatThreadRefState, ChatUploadState, ChatUserState, CreateDirectMessageChannelRequestState,
    MyChatChannelsState, SendChatMessageRequestState, SendChatMessageResultState,
};

#[derive(uniffi::Object)]
pub struct FireChatHandle {
    shared: Arc<SharedFireCore>,
}

impl FireChatHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

include!("handle/channels.rs");
include!("handle/messages.rs");
include!("handle/members.rs");
include!("handle/pins.rs");
include!("handle/threads.rs");
include!("handle/runtime.rs");
/// Lift a live chat MessageBus payload into a UI-ready message.
///
/// Hosts must not parse cooked HTML or synthesize presentation themselves.
/// Missing or malformed payloads are absence, not an error.
#[uniffi::export]
pub fn chat_message_from_bus_payload(
    payload_json: String,
    fallback_channel_id: Option<u64>,
    base_url: String,
) -> Option<ChatMessageState> {
    fire_core::chat_message_from_bus_payload(&payload_json, fallback_channel_id, &base_url)
        .map(|message| ChatStateMapper::new(&base_url).message(message))
}

/// Lift a live chat MessageBus payload into a UI-ready channel.
#[uniffi::export]
pub fn chat_channel_from_bus_payload(
    payload_json: String,
    base_url: String,
) -> Option<ChatChannelState> {
    fire_core::chat_channel_from_bus_payload(&payload_json, &base_url)
        .map(|channel| ChatStateMapper::new(&base_url).channel(channel))
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatUnreadApplyState {
    pub unread: u32,
    pub mention: u32,
}

/// Merge an incoming Chat tracking count. Hosts must not apply a second max/min formula.
#[uniffi::export]
pub fn apply_chat_unread(
    local_unread: u32,
    local_mention: u32,
    incoming_unread: u32,
    incoming_mention: u32,
    explicit_mark_read: bool,
) -> ChatUnreadApplyState {
    let applied = fire_models::apply_chat_unread(
        fire_models::ChatChannelTracking {
            unread_count: local_unread,
            mention_count: local_mention,
        },
        fire_models::ChatChannelTracking {
            unread_count: incoming_unread,
            mention_count: incoming_mention,
        },
        explicit_mark_read,
    );
    ChatUnreadApplyState {
        unread: applied.unread_count,
        mention: applied.mention_count,
    }
}

#[uniffi::export]
pub fn chat_bus_event_from_payload(
    payload_json: String,
    event_type: Option<String>,
    fallback_channel_id: Option<u64>,
    base_url: String,
) -> ChatBusEventState {
    ChatStateMapper::new(&base_url).bus_event(fire_core::chat_bus_event_from_payload(
        &payload_json,
        event_type.as_deref(),
        fallback_channel_id,
        &base_url,
    ))
}

#[cfg(test)]
mod tests {
    use super::{chat_channel_from_bus_payload, chat_message_from_bus_payload};

    #[test]
    fn bus_message_payload_carries_presentation() {
        let message = chat_message_from_bus_payload(
            r#"{"chat_message":{"id":7,"chat_channel_id":3,"message":"hi","cooked":"<p>hi</p>","user":{"id":2,"username":"alice"}}}"#
                .to_string(),
            Some(3),
            "https://linux.do".to_string(),
        )
        .expect("message");
        assert_eq!(message.id, 7);
        assert_eq!(message.channel_id, 3);
        let presentation = message.presentation.expect("presentation");
        assert!(presentation.plain_text().contains("hi"));
        assert!(presentation.segment_count() > 0);
    }

    #[test]
    fn bus_channel_payload_presents_last_message() {
        let channel = chat_channel_from_bus_payload(
            r#"{"channel":{"id":20,"title":"@alice","chatable_type":"DirectMessage","last_message":{"id":5,"message":"hello","cooked":"<p>hello</p>"}}}"#
                .to_string(),
            "https://linux.do".to_string(),
        )
        .expect("channel");
        assert!(channel.is_direct_message);
        let last_message = channel.last_message.expect("last message");
        assert_eq!(last_message.id, 5);
        assert!(last_message.presentation.is_some());
    }
}
