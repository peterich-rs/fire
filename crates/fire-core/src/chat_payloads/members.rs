pub(crate) fn parse_chat_channel_members_value(
    value: Value,
) -> Result<Vec<ChatChannelMember>, serde_json::Error> {
    require_object(
        &value,
        "chat channel members response root was not an object",
    )?;
    Ok(optional_array_field(&value, "memberships")
        .map(|items| {
            parse_array_items_lossy(items, "chat channel member", parse_chat_channel_member)
        })
        .unwrap_or_default())
}

fn parse_chat_channel_member(value: &Value) -> Result<ChatChannelMember, serde_json::Error> {
    require_object(value, "chat channel member was not an object")?;
    let user_value = object_field(value, "user")
        .ok_or_else(|| invalid_json("chat channel member did not contain a user object"))?;
    Ok(ChatChannelMember {
        user: parse_chat_user(user_value)?,
        following: boolean(object_field(value, "following")),
        muted: boolean(object_field(value, "muted")),
    })
}

