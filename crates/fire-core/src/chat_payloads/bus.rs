/// Best-effort MessageBus envelope → domain message.
///
/// Accepts `{ chat_message }`, `{ message }`, or a bare message object.
/// Parse failure is absence: live bus events must not fail the host.
pub fn chat_message_from_bus_payload(
    payload_json: &str,
    fallback_channel_id: Option<u64>,
    base_url: &str,
) -> Option<ChatMessage> {
    let value: Value = serde_json::from_str(payload_json).ok()?;
    if !value.is_object() {
        return None;
    }
    let message = object_field(&value, "chat_message")
        .or_else(|| object_field(&value, "message"))
        .unwrap_or(&value);
    let mut parsed = parse_chat_message(message, fallback_channel_id).ok()?;
    crate::attach_chat_message_presentation(&mut parsed, base_url);
    Some(parsed)
}

/// Typed chat MessageBus payload. `event_type` is the bus detail type when known.
pub fn chat_bus_event_from_payload(
    payload_json: &str,
    event_type: Option<&str>,
    fallback_channel_id: Option<u64>,
    base_url: &str,
) -> ChatBusEvent {
    let Ok(value) = serde_json::from_str::<Value>(payload_json) else {
        return ChatBusEvent::Ignored;
    };
    if !value.is_object() {
        return ChatBusEvent::Ignored;
    }

    let kind = event_type.unwrap_or("").trim();
    match kind {
        "delete" => {
            if let Some(id) = integer_u64(object_field(&value, "deleted_id")) {
                return ChatBusEvent::MessageDeleted { id };
            }
        }
        "reaction" => {
            if let Some(event) = parse_chat_reaction_event(&value) {
                return event;
            }
        }
        "sent"
        | "edit"
        | "processed"
        | "refresh"
        | "restore"
        | "thread_created"
        | "update_thread_original_message"
        | "pin"
        | "unpin" => {
            if let Some(message) =
                chat_message_from_bus_payload(payload_json, fallback_channel_id, base_url)
            {
                return ChatBusEvent::MessageUpsert {
                    message: Box::new(message),
                };
            }
        }
        _ => {}
    }

    if integer_u64(object_field(&value, "deleted_id")).is_some() && kind.is_empty() {
        if let Some(id) = integer_u64(object_field(&value, "deleted_id")) {
            return ChatBusEvent::MessageDeleted { id };
        }
    }
    if object_field(&value, "unread_count").is_some()
        || object_field(&value, "mention_count").is_some()
    {
        return ChatBusEvent::Tracking {
            channel_id: integer_u64(object_field(&value, "channel_id")).unwrap_or(0),
            unread: integer_u32(object_field(&value, "unread_count")).unwrap_or(0),
            mention: integer_u32(object_field(&value, "mention_count")).unwrap_or(0),
            thread_id: integer_u64(object_field(&value, "thread_id")),
        };
    }
    if let Some(channel) = chat_channel_from_bus_payload(payload_json, base_url) {
        if channel.id > 0 {
            return ChatBusEvent::ChannelUpsert {
                channel: Box::new(channel),
            };
        }
    }
    if object_field(&value, "type").is_some() || object_field(&value, "message").is_some() {
        let message = object_field(&value, "message")
            .and_then(|item| parse_chat_message(item, fallback_channel_id).ok())
            .map(|mut message| {
                crate::attach_chat_message_presentation(&mut message, base_url);
                message
            });
        let actor_id = message
            .as_ref()
            .and_then(|item| item.user.as_ref().map(|user| user.id));
        return ChatBusEvent::NewMessages {
            channel_id: fallback_channel_id
                .or_else(|| integer_u64(object_field(&value, "channel_id")))
                .unwrap_or(0),
            is_channel_level: scalar_string(object_field(&value, "type"))
                .is_none_or(|value| value == "channel"),
            message: message.map(Box::new),
            actor_id,
        };
    }
    if let Some(event) = parse_chat_reaction_event(&value) {
        return event;
    }
    ChatBusEvent::Ignored
}

fn parse_chat_reaction_event(value: &Value) -> Option<ChatBusEvent> {
    let message_id = integer_u64(object_field(value, "chat_message_id"))?;
    let emoji = scalar_string(object_field(value, "emoji"))?;
    let action = match scalar_string(object_field(value, "action"))
        .unwrap_or_default()
        .as_str()
    {
        "add" => ChatReactionAction::Add,
        "remove" => ChatReactionAction::Remove,
        _ => return None,
    };
    let actor_id =
        object_field(value, "user").and_then(|user| integer_u64(object_field(user, "id")));
    Some(ChatBusEvent::Reaction {
        message_id,
        emoji,
        action,
        actor_id,
    })
}

