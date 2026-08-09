use fire_models::{
    ChatBusLastIdEntry, ChatChannel, ChatChannelBusLastIds, ChatChannelMember,
    ChatChannelMembership, ChatChannelTrackingEntry, ChatMessage, ChatMessageBookmark,
    ChatMessageReaction, ChatMessageReplyRef, ChatMessagesResponse, ChatSearchResult,
    ChatThreadRef, ChatUpload, ChatUser, MyChatChannelsResponse,
};
use serde_json::Value;
use tracing::warn;

use crate::json_helpers::{
    boolean, integer_i32, integer_i64, integer_u32, integer_u64, invalid_json, object_field,
    parse_array_items_lossy, scalar_string,
};

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

pub(crate) fn parse_chat_messages_response_value(
    value: Value,
    channel_id: u64,
) -> Result<ChatMessagesResponse, serde_json::Error> {
    require_object(&value, "chat messages response root was not an object")?;

    let messages = optional_array_field(&value, "messages")
        .map(|items| {
            parse_array_items_lossy(items, "chat message", |item| {
                parse_chat_message(item, Some(channel_id))
            })
        })
        .unwrap_or_default();

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
    })
}

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

fn require_object(value: &Value, details: impl Into<String>) -> Result<(), serde_json::Error> {
    if value.is_object() {
        Ok(())
    } else {
        Err(invalid_json(details))
    }
}

fn optional_array_field<'a>(value: &'a Value, key: &str) -> Option<&'a [Value]> {
    match object_field(value, key) {
        Some(Value::Array(items)) => Some(items.as_slice()),
        Some(_) => {
            warn!(
                key,
                "chat payload field was not an array; treating as empty"
            );
            None
        }
        None => None,
    }
}

fn required_u64_field(
    value: &Value,
    key: &str,
    details: impl Into<String>,
) -> Result<u64, serde_json::Error> {
    integer_u64(object_field(value, key)).ok_or_else(|| invalid_json(details))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_my_channels_with_tracking_and_dm() {
        let value = json!({
            "public_channels": [{
                "id": 10,
                "title": "general",
                "chatable_type": "Category",
                "chatable": {"name": "General", "color": "0088CC"},
                "current_user_membership": {
                    "following": true,
                    "muted": false,
                    "starred": true,
                    "last_read_message_id": 99
                },
                "meta": {
                    "can_flag": true,
                    "message_bus_last_ids": {
                        "new_messages": 12
                    }
                }
            }],
            "direct_message_channels": [{
                "id": 20,
                "title": "@alice",
                "unicode_title": "@alice",
                "chatable_type": "DirectMessage",
                "chatable": {
                    "group": false,
                    "users": [{
                        "id": 2,
                        "username": "alice",
                        "name": "Alice",
                        "avatar_template": "/user_avatar/alice/{size}.png"
                    }]
                },
                "last_message": {
                    "id": 5,
                    "message": "hello",
                    "cooked": "<p>hello</p>",
                    "user": {"id": 2, "username": "alice"}
                }
            }],
            "tracking": {
                "channel_tracking": {
                    "10": {"unread_count": 0, "mention_count": 1},
                    "20": {"unread_count": 2, "mention_count": 0}
                }
            },
            "meta": {
                "message_bus_last_ids": {
                    "user_tracking_state": 3,
                    "new_channel": 4
                }
            }
        });

        let parsed = parse_my_chat_channels_response_value(value).expect("parse");
        assert_eq!(parsed.public_channels.len(), 1);
        assert_eq!(parsed.direct_message_channels.len(), 1);
        assert!(parsed.direct_message_channels[0].is_direct_message());
        assert_eq!(
            parsed.direct_message_channels[0].dm_users[0].username,
            "alice"
        );
        assert_eq!(
            parsed.direct_message_channels[0]
                .last_message
                .as_ref()
                .map(|m| m.message.as_str()),
            Some("hello")
        );
        assert_eq!(parsed.channel_tracking.len(), 2);
        assert_eq!(parsed.total_unread_badge(), 3); // mention 1 + dm unread 2
        assert_eq!(parsed.global_bus_last_ids.len(), 2);
        assert_eq!(
            parsed.public_channels[0].bus_last_ids.new_messages,
            Some(12)
        );
    }

    #[test]
    fn parses_messages_page_meta() {
        let value = json!({
            "messages": [{
                "id": 1,
                "chat_channel_id": 20,
                "message": "hi",
                "cooked": "<p>hi</p>",
                "edited": false,
                "reactions": [{"emoji": "heart", "count": 1, "reacted": true}],
                "uploads": []
            }],
            "meta": {
                "can_load_more_past": true,
                "can_load_more_future": false,
                "target_message_id": 1
            }
        });
        let parsed = parse_chat_messages_response_value(value, 20).expect("parse");
        assert_eq!(parsed.messages.len(), 1);
        assert!(parsed.can_load_more_past);
        assert!(!parsed.can_load_more_future);
        assert_eq!(parsed.target_message_id, Some(1));
        assert_eq!(parsed.messages[0].reactions[0].emoji, "heart");
    }
}
