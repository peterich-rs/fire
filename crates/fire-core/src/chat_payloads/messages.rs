pub(crate) fn parse_chat_messages_response_value(
    value: Value,
    channel_id: u64,
    base_url: &str,
) -> Result<ChatMessagesResponse, serde_json::Error> {
    require_object(&value, "chat messages response root was not an object")?;

    let mut messages = optional_array_field(&value, "messages")
        .map(|items| {
            parse_array_items_lossy(items, "chat message", |item| {
                parse_chat_message(item, Some(channel_id))
            })
        })
        .unwrap_or_default();
    for message in &mut messages {
        crate::attach_chat_message_presentation(message, base_url);
    }

    let meta = object_field(&value, "meta");
    Ok(ChatMessagesResponse {
        messages,
        can_load_more_past: boolean(meta.and_then(|meta| object_field(meta, "can_load_more_past"))),
        can_load_more_future: boolean(
            meta.and_then(|meta| object_field(meta, "can_load_more_future")),
        ),
        target_message_id: meta
            .and_then(|meta| integer_u64(object_field(meta, "target_message_id"))),
    })
}

pub(crate) fn parse_chat_search_result_value(
    value: Value,
) -> Result<ChatSearchResult, serde_json::Error> {
    require_object(&value, "chat search response root was not an object")?;
    let messages = optional_array_field(&value, "messages")
        .map(|items| {
            parse_array_items_lossy(items, "chat search message", |item| {
                parse_chat_message(item, None)
            })
        })
        .unwrap_or_default();
    let has_more =
        boolean(object_field(&value, "meta").and_then(|meta| object_field(meta, "has_more")));
    Ok(ChatSearchResult { messages, has_more })
}

pub(crate) fn parse_send_chat_message_id(value: &Value) -> Option<u64> {
    integer_u64(object_field(value, "message_id"))
}

fn parse_chat_message(
    value: &Value,
    fallback_channel_id: Option<u64>,
) -> Result<ChatMessage, serde_json::Error> {
    require_object(value, "chat message was not an object")?;

    let user = object_field(value, "user")
        .map(parse_chat_user)
        .transpose()?;
    let in_reply_to = object_field(value, "in_reply_to")
        .map(parse_reply_ref)
        .transpose()?
        .flatten();
    let thread = object_field(value, "thread")
        .map(parse_thread_ref)
        .transpose()?
        .flatten();
    let bookmark = object_field(value, "bookmark")
        .map(parse_bookmark)
        .transpose()?
        .flatten();

    Ok(ChatMessage {
        id: integer_u64(object_field(value, "id")).unwrap_or(0),
        channel_id: integer_u64(object_field(value, "chat_channel_id"))
            .or_else(|| integer_u64(object_field(value, "channel_id")))
            .or(fallback_channel_id)
            .unwrap_or(0),
        message: scalar_string(object_field(value, "message")).unwrap_or_default(),
        cooked: scalar_string(object_field(value, "cooked")).unwrap_or_default(),
        excerpt: scalar_string(object_field(value, "excerpt")),
        created_at: scalar_string(object_field(value, "created_at")),
        deleted_at: scalar_string(object_field(value, "deleted_at")),
        deleted_by_id: integer_u64(object_field(value, "deleted_by_id")),
        edited: boolean(object_field(value, "edited")),
        thread_id: integer_u64(object_field(value, "thread_id")),
        thread,
        user,
        mentioned_users: optional_array_field(value, "mentioned_users")
            .map(|items| parse_array_items_lossy(items, "mentioned chat user", parse_chat_user))
            .unwrap_or_default(),
        reactions: optional_array_field(value, "reactions")
            .map(|items| parse_array_items_lossy(items, "chat message reaction", parse_reaction))
            .unwrap_or_default(),
        uploads: optional_array_field(value, "uploads")
            .map(|items| parse_array_items_lossy(items, "chat upload", parse_upload))
            .unwrap_or_default(),
        in_reply_to,
        streaming: boolean(object_field(value, "streaming")),
        available_flags: optional_array_field(value, "available_flags")
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| scalar_string(Some(item)))
                    .collect()
            })
            .unwrap_or_default(),
        user_flag_status: integer_i32(object_field(value, "user_flag_status")),
        bookmark,
        pinned: boolean(object_field(value, "pinned")),
        presented: Default::default(),
    })
}

