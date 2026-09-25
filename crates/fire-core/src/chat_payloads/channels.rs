pub(crate) fn parse_my_chat_channels_response_value(
    value: Value,
) -> Result<MyChatChannelsResponse, serde_json::Error> {
    require_object(&value, "my chat channels response root was not an object")?;

    let public_channels = optional_array_field(&value, "public_channels")
        .map(|items| parse_array_items_lossy(items, "public chat channel", parse_chat_channel))
        .unwrap_or_default();
    let direct_message_channels = optional_array_field(&value, "direct_message_channels")
        .map(|items| {
            parse_array_items_lossy(items, "direct message chat channel", parse_chat_channel)
        })
        .unwrap_or_default();

    let channel_tracking = object_field(&value, "tracking")
        .and_then(|tracking| object_field(tracking, "channel_tracking"))
        .and_then(Value::as_object)
        .map(|map| {
            map.iter()
                .filter_map(|(key, entry)| {
                    let channel_id = key.parse::<u64>().ok()?;
                    let unread_count =
                        integer_u32(object_field(entry, "unread_count")).unwrap_or(0);
                    let mention_count =
                        integer_u32(object_field(entry, "mention_count")).unwrap_or(0);
                    Some(ChatChannelTrackingEntry {
                        channel_id,
                        unread_count,
                        mention_count,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let global_bus_last_ids = object_field(&value, "meta")
        .and_then(|meta| object_field(meta, "message_bus_last_ids"))
        .and_then(Value::as_object)
        .map(|map| {
            map.iter()
                .filter_map(|(channel, last_id)| {
                    let last_id = integer_i64(Some(last_id))?;
                    Some(ChatBusLastIdEntry {
                        channel: channel.clone(),
                        last_id,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Ok(MyChatChannelsResponse {
        public_channels,
        direct_message_channels,
        channel_tracking,
        global_bus_last_ids,
    })
}

pub(crate) fn parse_chat_channel_response_value(
    value: Value,
) -> Result<ChatChannel, serde_json::Error> {
    require_object(&value, "chat channel response root was not an object")?;
    let channel_value = object_field(&value, "channel").unwrap_or(&value);
    parse_chat_channel(channel_value)
}

pub(crate) fn parse_browse_chat_channels_value(
    value: Value,
) -> Result<Vec<ChatChannel>, serde_json::Error> {
    require_object(
        &value,
        "browse chat channels response root was not an object",
    )?;
    Ok(optional_array_field(&value, "channels")
        .map(|items| parse_array_items_lossy(items, "browse chat channel", parse_chat_channel))
        .unwrap_or_default())
}

pub(crate) fn parse_chat_thread_id_value(value: &Value) -> Option<u64> {
    object_field(value, "thread")
        .and_then(|thread| integer_u64(object_field(thread, "id")))
        .or_else(|| integer_u64(object_field(value, "id")))
}

pub(crate) fn parse_chat_channel_pins_value(
    value: Value,
    channel_id: u64,
) -> Result<Vec<ChatMessage>, serde_json::Error> {
    require_object(&value, "chat pins response root was not an object")?;
    Ok(optional_array_field(&value, "pinned_messages")
        .map(|items| {
            parse_array_items_lossy(items, "pinned chat message", |item| {
                // pin envelope may be { message: {...} }
                let message_value = object_field(item, "message").unwrap_or(item);
                parse_chat_message(message_value, Some(channel_id))
            })
        })
        .unwrap_or_default())
}

/// Best-effort MessageBus envelope → domain channel, including last_message.
pub fn chat_channel_from_bus_payload(payload_json: &str, base_url: &str) -> Option<ChatChannel> {
    let value: Value = serde_json::from_str(payload_json).ok()?;
    if !value.is_object() {
        return None;
    }
    let channel = object_field(&value, "channel").unwrap_or(&value);
    let mut parsed = parse_chat_channel(channel).ok()?;
    if let Some(message) = parsed.last_message.as_mut() {
        crate::attach_chat_message_presentation(message, base_url);
    }
    Some(parsed)
}

fn parse_chat_channel(value: &Value) -> Result<ChatChannel, serde_json::Error> {
    require_object(value, "chat channel was not an object")?;

    let channel_id = required_u64_field(value, "id", "chat channel did not contain a valid id")?;
    let chatable = object_field(value, "chatable");
    let membership = object_field(value, "current_user_membership");
    let last_message = object_field(value, "last_message");
    let meta = object_field(value, "meta");
    let bus_last_ids = meta
        .and_then(|meta| object_field(meta, "message_bus_last_ids"))
        .map(parse_bus_last_ids)
        .unwrap_or_default();

    let has_last_message = last_message
        .and_then(|message| integer_u64(object_field(message, "id")))
        .is_some();

    Ok(ChatChannel {
        id: channel_id,
        title: scalar_string(object_field(value, "title")),
        unicode_title: scalar_string(object_field(value, "unicode_title")),
        slug: scalar_string(object_field(value, "slug")),
        description: scalar_string(object_field(value, "description")),
        chatable_type: scalar_string(object_field(value, "chatable_type")).unwrap_or_default(),
        status: scalar_string(object_field(value, "status")),
        threading_enabled: boolean(object_field(value, "threading_enabled")),
        memberships_count: integer_u32(object_field(value, "memberships_count")),
        is_group_dm: boolean(chatable.and_then(|chatable| object_field(chatable, "group"))),
        dm_users: chatable
            .and_then(|chatable| optional_array_field(chatable, "users"))
            .map(|items| parse_array_items_lossy(items, "chat dm user", parse_chat_user))
            .unwrap_or_default(),
        category_color: chatable
            .and_then(|chatable| scalar_string(object_field(chatable, "color"))),
        category_name: chatable.and_then(|chatable| scalar_string(object_field(chatable, "name"))),
        emoji: scalar_string(object_field(value, "emoji")),
        current_user_membership: membership.map(parse_membership).transpose()?.flatten(),
        last_message: if has_last_message {
            last_message
                .map(|message| parse_chat_message(message, Some(channel_id)))
                .transpose()?
        } else {
            None
        },
        bus_last_ids,
        can_moderate: boolean(meta.and_then(|meta| object_field(meta, "can_moderate"))),
        can_manage_pins: boolean(meta.and_then(|meta| object_field(meta, "can_manage_pins"))),
        can_delete_self: boolean(meta.and_then(|meta| object_field(meta, "can_delete_self"))),
        can_delete_others: boolean(meta.and_then(|meta| object_field(meta, "can_delete_others"))),
        can_remove_members: boolean(meta.and_then(|meta| object_field(meta, "can_remove_members"))),
        can_flag: boolean(meta.and_then(|meta| object_field(meta, "can_flag"))),
    })
}

fn parse_membership(value: &Value) -> Result<Option<ChatChannelMembership>, serde_json::Error> {
    if !value.is_object() {
        return Ok(None);
    }
    Ok(Some(ChatChannelMembership {
        following: boolean(object_field(value, "following")),
        muted: boolean(object_field(value, "muted")),
        starred: boolean(object_field(value, "starred")),
        notification_level: scalar_string(object_field(value, "notification_level")),
        last_read_message_id: integer_u64(object_field(value, "last_read_message_id")),
        last_viewed_at: scalar_string(object_field(value, "last_viewed_at")),
    }))
}

fn parse_bus_last_ids(value: &Value) -> ChatChannelBusLastIds {
    ChatChannelBusLastIds {
        channel_message_bus_last_id: integer_i64(object_field(
            value,
            "channel_message_bus_last_id",
        )),
        new_messages: integer_i64(object_field(value, "new_messages")),
        new_mentions: integer_i64(object_field(value, "new_mentions")),
        kick: integer_i64(object_field(value, "kick")),
    }
}

