#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatReactionAction {
    Add,
    Remove,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatBusEvent {
    MessageUpsert {
        message: Box<ChatMessage>,
    },
    MessageDeleted {
        id: u64,
    },
    Reaction {
        message_id: u64,
        emoji: String,
        action: ChatReactionAction,
        actor_id: Option<u64>,
    },
    Tracking {
        channel_id: u64,
        unread: u32,
        mention: u32,
        thread_id: Option<u64>,
    },
    ChannelUpsert {
        channel: Box<ChatChannel>,
    },
    NewMessages {
        channel_id: u64,
        is_channel_level: bool,
        message: Option<Box<ChatMessage>>,
        actor_id: Option<u64>,
    },
    Ignored,
}

