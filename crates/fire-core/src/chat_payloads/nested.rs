fn parse_chat_user(value: &Value) -> Result<ChatUser, serde_json::Error> {
    require_object(value, "chat user was not an object")?;
    Ok(ChatUser {
        id: integer_u64(object_field(value, "id")).unwrap_or(0),
        username: scalar_string(object_field(value, "username")).unwrap_or_default(),
        name: scalar_string(object_field(value, "name")),
        avatar_template: scalar_string(object_field(value, "avatar_template")),
    })
}

fn parse_reaction(value: &Value) -> Result<ChatMessageReaction, serde_json::Error> {
    require_object(value, "chat reaction was not an object")?;
    Ok(ChatMessageReaction {
        emoji: scalar_string(object_field(value, "emoji")).unwrap_or_default(),
        count: integer_u32(object_field(value, "count")).unwrap_or(0),
        reacted: boolean(object_field(value, "reacted")),
        users: optional_array_field(value, "users")
            .map(|items| parse_array_items_lossy(items, "reaction user", parse_chat_user))
            .unwrap_or_default(),
    })
}

fn parse_upload(value: &Value) -> Result<ChatUpload, serde_json::Error> {
    require_object(value, "chat upload was not an object")?;
    Ok(ChatUpload {
        id: integer_u64(object_field(value, "id")).unwrap_or(0),
        url: scalar_string(object_field(value, "url")),
        short_url: scalar_string(object_field(value, "short_url")),
        original_filename: scalar_string(object_field(value, "original_filename")),
        extension: scalar_string(object_field(value, "extension")),
        width: integer_u32(object_field(value, "width")),
        height: integer_u32(object_field(value, "height")),
        thumbnail_width: integer_u32(object_field(value, "thumbnail_width")),
        thumbnail_height: integer_u32(object_field(value, "thumbnail_height")),
        dominant_color: scalar_string(object_field(value, "dominant_color")),
    })
}

fn parse_reply_ref(value: &Value) -> Result<Option<ChatMessageReplyRef>, serde_json::Error> {
    if !value.is_object() {
        return Ok(None);
    }
    let user = object_field(value, "user")
        .map(parse_chat_user)
        .transpose()?;
    Ok(Some(ChatMessageReplyRef {
        id: integer_u64(object_field(value, "id")).unwrap_or(0),
        excerpt: scalar_string(object_field(value, "excerpt")),
        user,
    }))
}

fn parse_thread_ref(value: &Value) -> Result<Option<ChatThreadRef>, serde_json::Error> {
    if !value.is_object() {
        return Ok(None);
    }
    let preview = object_field(value, "preview");
    let last_reply_user = preview
        .and_then(|preview| object_field(preview, "last_reply_user"))
        .map(parse_chat_user)
        .transpose()?;
    Ok(Some(ChatThreadRef {
        id: integer_u64(object_field(value, "id")).unwrap_or(0),
        title: scalar_string(object_field(value, "title")),
        reply_count: integer_u32(object_field(value, "reply_count"))
            .or_else(|| {
                preview.and_then(|preview| integer_u32(object_field(preview, "reply_count")))
            })
            .unwrap_or(0),
        last_reply_created_at: preview
            .and_then(|preview| scalar_string(object_field(preview, "last_reply_created_at"))),
        last_reply_excerpt: preview
            .and_then(|preview| scalar_string(object_field(preview, "last_reply_excerpt"))),
        last_reply_user,
        participants: preview
            .and_then(|preview| optional_array_field(preview, "participant_users"))
            .map(|items| parse_array_items_lossy(items, "thread participant", parse_chat_user))
            .unwrap_or_default(),
    }))
}

fn parse_bookmark(value: &Value) -> Result<Option<ChatMessageBookmark>, serde_json::Error> {
    if !value.is_object() {
        return Ok(None);
    }
    Ok(Some(ChatMessageBookmark {
        id: integer_u64(object_field(value, "id")).unwrap_or(0),
        name: scalar_string(object_field(value, "name")),
        reminder_at: scalar_string(object_field(value, "reminder_at")),
    }))
}

