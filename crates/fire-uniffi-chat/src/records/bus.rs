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
