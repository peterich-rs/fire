#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatMessageUpsert {
    Updated(usize),
    Inserted,
    Ignored,
}

pub fn chat_channel_badge(channel: &ChatChannel, tracking: &ChatChannelTracking) -> u32 {
    if channel
        .current_user_membership
        .as_ref()
        .is_some_and(|membership| membership.muted)
    {
        return 0;
    }
    if channel.is_direct_message() {
        tracking
            .unread_count
            .saturating_add(tracking.mention_count)
    } else {
        tracking.mention_count
    }
}

pub fn apply_chat_new_message_unread(
    local: ChatChannelTracking,
    is_self: bool,
) -> ChatChannelTracking {
    if is_self {
        return local;
    }
    apply_chat_unread(
        local.clone(),
        ChatChannelTracking {
            unread_count: local.unread_count.saturating_add(1),
            mention_count: local.mention_count,
        },
        false,
    )
}

pub fn merge_chat_channel_edit(existing: ChatChannel, incoming: &ChatChannel) -> ChatChannel {
    let mut next = existing;
    if incoming.title.is_some() {
        next.title = incoming.title.clone();
    }
    if incoming.unicode_title.is_some() {
        next.unicode_title = incoming.unicode_title.clone();
    }
    if incoming.description.is_some() {
        next.description = incoming.description.clone();
    }
    if incoming.emoji.is_some() {
        next.emoji = incoming.emoji.clone();
    }
    if incoming.current_user_membership.is_some() {
        next.current_user_membership = incoming.current_user_membership.clone();
    }
    if incoming.last_message.is_some() {
        next.last_message = incoming.last_message.clone();
    }
    next
}

pub fn upsert_chat_message(
    messages: &mut Vec<ChatMessage>,
    mut incoming: ChatMessage,
    prefer_append: bool,
) -> ChatMessageUpsert {
    if incoming.id > 0 {
        if let Some(index) = messages.iter().position(|message| message.id == incoming.id) {
            incoming.reuse_presentation_from(&messages[index]);
            messages[index] = incoming;
            return ChatMessageUpsert::Updated(index);
        }
    }
    if let Some(staged) = incoming
        .staged_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        if let Some(index) = messages
            .iter()
            .position(|message| message.staged_id.as_deref() == Some(staged))
        {
            incoming.reuse_presentation_from(&messages[index]);
            messages[index] = incoming;
            return ChatMessageUpsert::Updated(index);
        }
    }
    if prefer_append {
        messages.push(incoming);
        return ChatMessageUpsert::Inserted;
    }
    ChatMessageUpsert::Ignored
}

pub fn apply_chat_reaction(
    message: &mut ChatMessage,
    emoji: &str,
    action: ChatReactionAction,
    actor_is_self: bool,
) {
    let is_add = action == ChatReactionAction::Add;
    if let Some(existing) = message
        .reactions
        .iter_mut()
        .find(|reaction| reaction.emoji == emoji)
    {
        existing.count = if is_add {
            existing.count.saturating_add(1)
        } else {
            existing.count.saturating_sub(1)
        };
        existing.reacted = is_add && (existing.reacted || actor_is_self);
        if existing.count == 0 {
            message.reactions.retain(|reaction| reaction.emoji != emoji);
        }
        return;
    }
    if is_add {
        message.reactions.push(ChatMessageReaction {
            emoji: emoji.to_string(),
            count: 1,
            reacted: true,
            users: Vec::new(),
        });
    }
}

pub fn apply_chat_channel_bus_event(
    messages: &mut Vec<ChatMessage>,
    pins: &mut Vec<ChatMessage>,
    event: ChatBusEvent,
    event_type: Option<&str>,
    current_user_id: Option<u64>,
) {
    let kind = event_type.unwrap_or("").trim();
    match (kind, event) {
        ("pin", ChatBusEvent::MessageUpsert { message }) => {
            let cloned = (*message).clone();
            let _ = upsert_chat_message(messages, *message, false);
            apply_chat_pin_event(pins, cloned, true);
        }
        ("unpin", ChatBusEvent::MessageUpsert { message }) => {
            apply_chat_pin_event(pins, *message, false);
        }
        (
            "sent" | "edit" | "processed" | "refresh" | "restore" | "thread_created"
            | "update_thread_original_message",
            ChatBusEvent::MessageUpsert { message },
        ) => {
            let prefer_append = kind == "sent";
            let _ = upsert_chat_message(messages, *message, prefer_append);
        }
        (_, event) => match event {
            ChatBusEvent::MessageUpsert { message } => {
                let _ = upsert_chat_message(messages, *message, true);
            }
            ChatBusEvent::MessageDeleted { id } => {
                messages.retain(|message| message.id != id);
            }
            ChatBusEvent::Reaction {
                message_id,
                emoji,
                action,
                actor_id,
            } => {
                if let Some(message) = messages.iter_mut().find(|message| message.id == message_id)
                {
                    apply_chat_reaction(
                        message,
                        &emoji,
                        action,
                        actor_id.is_some_and(|id| Some(id) == current_user_id),
                    );
                }
            }
            ChatBusEvent::NewMessages { message, .. } => {
                if let Some(message) = message {
                    let _ = upsert_chat_message(messages, *message, true);
                }
            }
            ChatBusEvent::ChannelUpsert { channel } => {
                if let Some(last_message) = channel.last_message {
                    let _ = upsert_chat_message(messages, last_message, true);
                }
            }
            ChatBusEvent::Tracking { .. } | ChatBusEvent::Ignored => {}
        },
    }
}

pub fn apply_chat_pin_event(pins: &mut Vec<ChatMessage>, message: ChatMessage, pin: bool) {
    pins.retain(|existing| existing.id != message.id);
    if pin {
        pins.insert(0, message);
    }
}
