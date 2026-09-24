use fire_models::{
    Poll, PostReactionUpdate, ReactionUser, ReactionUsersGroup, TopicPost, TopicPostAuthorMetadata,
    TopicPostBoost, TopicPostBoostUser, TopicReaction, TopicReplyToUser,
};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;

use super::deser::{
    deserialize_default_bool, deserialize_default_i32, deserialize_default_record,
    deserialize_default_sequence, deserialize_default_string, deserialize_default_string_sequence,
    deserialize_default_u32, deserialize_default_u64, deserialize_optional_bool,
    deserialize_optional_i32, deserialize_optional_record, deserialize_optional_scalar_string,
    deserialize_optional_string_sequence_map, deserialize_optional_u32, deserialize_optional_u64,
};
use super::list::normalized_scalar;
use super::poll::RawPoll;
use crate::json_helpers::{
    integer_u32, integer_u64, invalid_json, parse_array_items_lossy, scalar_string,
};

fn boost_display_text(cooked: &str, user: &RawTopicPostBoostUser) -> String {
    let plain_text = crate::present_cooked_html(cooked, "https://linux.do")
        .map(|presented| presented.presentation().plain_text.clone())
        .unwrap_or_default();
    let body_text = strip_boost_leading_attribution(&plain_text, user);
    separate_boost_emoji_shortcodes(&body_text)
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn strip_boost_leading_attribution(value: &str, user: &RawTopicPostBoostUser) -> String {
    let trimmed = value.trim_start();
    if trimmed.is_empty() {
        return String::new();
    }

    let candidates = [
        normalized_scalar(Some(user.username.as_str())).map(|username| format!("@{username}:")),
        normalized_scalar(Some(user.username.as_str())).map(|username| format!("{username}:")),
        normalized_scalar(user.name.as_deref()).map(|name| format!("{name}:")),
        normalized_scalar(Some(user.username.as_str())).map(|username| format!("@{username}：")),
        normalized_scalar(Some(user.username.as_str())).map(|username| format!("{username}：")),
        normalized_scalar(user.name.as_deref()).map(|name| format!("{name}：")),
    ];

    for candidate in candidates.into_iter().flatten() {
        if trimmed
            .get(..candidate.len())
            .is_some_and(|prefix| prefix.eq_ignore_ascii_case(&candidate))
        {
            return trimmed[candidate.len()..].trim_start().to_string();
        }
    }

    let Some(rest) = trimmed.strip_prefix('@') else {
        return trimmed.to_string();
    };
    let Some(colon_index_after_at) = rest.find([':', '：']) else {
        return trimmed.to_string();
    };
    let username = &rest[..colon_index_after_at];
    if !username.is_empty()
        && username.len() <= 40
        && username.chars().all(|character| !character.is_whitespace())
    {
        let colon_width = rest[colon_index_after_at..]
            .chars()
            .next()
            .map(char::len_utf8)
            .unwrap_or(1);
        let colon_end_index = 1 + colon_index_after_at + colon_width;
        return trimmed[colon_end_index..].trim_start().to_string();
    }

    trimmed.to_string()
}

fn separate_boost_emoji_shortcodes(value: &str) -> String {
    let mut result = String::with_capacity(value.len());
    let mut index = 0;

    while index < value.len() {
        let remaining = &value[index..];
        if let Some((shortcode, next_index)) = boost_emoji_shortcode_at(value, index) {
            if result
                .chars()
                .last()
                .is_some_and(|character| !character.is_whitespace())
            {
                result.push(' ');
            }
            result.push_str(shortcode);
            if value[next_index..]
                .chars()
                .next()
                .is_some_and(|character| !character.is_whitespace())
            {
                result.push(' ');
            }
            index = next_index;
            continue;
        }

        let character = remaining
            .chars()
            .next()
            .expect("remaining string is non-empty");
        result.push(character);
        index += character.len_utf8();
    }

    result
}

fn boost_emoji_shortcode_at(value: &str, index: usize) -> Option<(&str, usize)> {
    let remaining = value.get(index..)?;
    let after_open = remaining.strip_prefix(':')?;
    for (end, character) in after_open.char_indices() {
        if character != ':' {
            continue;
        }
        let name = &after_open[..end];
        if !is_boost_emoji_shortcode_name(name) {
            continue;
        }
        let next_index = index + end + 2;
        let next_character = value[next_index..].chars().next();
        if next_character.is_some_and(is_boost_emoji_shortcode_component_character) {
            continue;
        }
        return Some((&value[index..next_index], next_index));
    }
    None
}

fn is_boost_emoji_shortcode_name(value: &str) -> bool {
    !value.is_empty()
        && value.split(':').all(|component| {
            !component.is_empty()
                && component
                    .chars()
                    .all(is_boost_emoji_shortcode_component_character)
        })
}

fn is_boost_emoji_shortcode_component_character(character: char) -> bool {
    character.is_ascii_alphanumeric() || matches!(character, '_' | '-' | '+')
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicReaction {
    #[serde(default, deserialize_with = "deserialize_default_string")]
    id: String,
    #[serde(rename = "type")]
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    kind: Option<String>,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    count: u32,
    #[serde(default, deserialize_with = "deserialize_optional_bool")]
    can_undo: Option<bool>,
}

impl From<RawTopicReaction> for TopicReaction {
    fn from(value: RawTopicReaction) -> Self {
        Self {
            id: value.id,
            kind: value.kind,
            count: value.count,
            can_undo: value.can_undo,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawPostReactionUpdate {
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    reactions: Vec<RawTopicReaction>,
    #[serde(default, deserialize_with = "deserialize_optional_record")]
    current_user_reaction: Option<RawTopicReaction>,
}

impl From<RawPostReactionUpdate> for PostReactionUpdate {
    fn from(value: RawPostReactionUpdate) -> Self {
        Self {
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicReplyToUser {
    #[serde(default, deserialize_with = "deserialize_default_string")]
    username: String,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    avatar_template: Option<String>,
}

impl From<RawTopicReplyToUser> for TopicReplyToUser {
    fn from(value: RawTopicReplyToUser) -> Self {
        Self {
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicPostUserStatus {
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    emoji: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    description: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicPostBoostUser {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    username: String,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    avatar_template: Option<String>,
}

impl From<RawTopicPostBoostUser> for TopicPostBoostUser {
    fn from(value: RawTopicPostBoostUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicPostBoost {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    cooked: String,
    #[serde(default, deserialize_with = "deserialize_default_record")]
    user: RawTopicPostBoostUser,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_delete: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_flag: bool,
    #[serde(default, deserialize_with = "deserialize_optional_i32")]
    user_flag_status: Option<i32>,
    #[serde(default, deserialize_with = "deserialize_default_string_sequence")]
    available_flags: Vec<String>,
}

impl From<RawTopicPostBoost> for TopicPostBoost {
    fn from(value: RawTopicPostBoost) -> Self {
        let presented = crate::present_cooked_html(&value.cooked, "https://linux.do");
        let display_text = presented
            .as_ref()
            .map(|document| {
                let body_text = strip_boost_leading_attribution(
                    &document.presentation().plain_text,
                    &value.user,
                );
                separate_boost_emoji_shortcodes(&body_text)
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .unwrap_or_else(|| boost_display_text(&value.cooked, &value.user));
        Self {
            id: value.id,
            cooked: value.cooked,
            display_text,
            user: value.user.into(),
            can_delete: value.can_delete,
            can_flag: value.can_flag,
            user_flag_status: value.user_flag_status,
            available_flags: value.available_flags,
            presented: presented
                .map(|document| {
                    fire_models::AttachedPresentation::some(std::sync::Arc::new(document))
                })
                .unwrap_or_default(),
        }
    }
}

#[derive(Debug, Default, Deserialize)]
pub(super) struct RawTopicPost {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    username: String,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    avatar_template: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    user_id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    user_title: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    primary_group_name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    flair_url: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    flair_name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    flair_bg_color: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    flair_color: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    flair_group_id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    moderator: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    admin: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    group_moderator: bool,
    #[serde(default, deserialize_with = "deserialize_optional_record")]
    user_status: Option<RawTopicPostUserStatus>,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    cooked: String,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    raw: Option<String>,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    post_number: u32,
    #[serde(
        default = "default_post_type",
        deserialize_with = "deserialize_default_i32"
    )]
    post_type: i32,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    created_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    updated_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    like_count: u32,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    reply_count: u32,
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    reply_to_post_number: Option<u32>,
    #[serde(default, deserialize_with = "deserialize_optional_record")]
    reply_to_user: Option<RawTopicReplyToUser>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    bookmarked: bool,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    bookmark_id: Option<u64>,
    #[serde(
        default,
        rename = "_bookmark_name",
        deserialize_with = "deserialize_optional_scalar_string"
    )]
    bookmark_name: Option<String>,
    #[serde(
        default,
        rename = "_bookmark_reminder_at",
        deserialize_with = "deserialize_optional_scalar_string"
    )]
    bookmark_reminder_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    reactions: Vec<RawTopicReaction>,
    #[serde(default, deserialize_with = "deserialize_optional_record")]
    current_user_reaction: Option<RawTopicReaction>,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    boosts: Vec<RawTopicPostBoost>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_boost: bool,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    polls: Vec<RawPoll>,
    #[serde(default, deserialize_with = "deserialize_optional_string_sequence_map")]
    polls_votes: Option<HashMap<String, Vec<String>>>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    accepted_answer: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_accept_answer: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_unaccept_answer: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_edit: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_delete: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_recover: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    hidden: bool,
}

impl From<RawTopicPost> for TopicPost {
    fn from(value: RawTopicPost) -> Self {
        let poll_votes = value.polls_votes.unwrap_or_default();
        let polls = value
            .polls
            .into_iter()
            .map(|poll| {
                let mut parsed: Poll = poll.into();
                parsed.user_votes = poll_votes.get(&parsed.name).cloned().unwrap_or_default();
                parsed
            })
            .collect();

        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            author_metadata: TopicPostAuthorMetadata {
                user_id: value.user_id,
                user_title: value.user_title,
                primary_group_name: value.primary_group_name,
                flair_url: value.flair_url,
                flair_name: value.flair_name,
                flair_bg_color: value.flair_bg_color,
                flair_color: value.flair_color,
                flair_group_id: value.flair_group_id,
                moderator: value.moderator,
                admin: value.admin,
                group_moderator: value.group_moderator,
                user_status_emoji: value
                    .user_status
                    .as_ref()
                    .and_then(|status| status.emoji.clone()),
                user_status_description: value.user_status.and_then(|status| status.description),
            },
            cooked: value.cooked,
            raw: value.raw,
            post_number: value.post_number,
            post_type: value.post_type,
            created_at: value.created_at,
            updated_at: value.updated_at,
            like_count: value.like_count,
            reply_count: value.reply_count,
            reply_to_post_number: value.reply_to_post_number,
            reply_to_user: value.reply_to_user.map(Into::into),
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
            boosts: value.boosts.into_iter().map(Into::into).collect(),
            can_boost: value.can_boost,
            polls,
            accepted_answer: value.accepted_answer,
            can_accept_answer: value.can_accept_answer,
            can_unaccept_answer: value.can_unaccept_answer,
            can_edit: value.can_edit,
            can_delete: value.can_delete,
            can_recover: value.can_recover,
            hidden: value.hidden,
            presented: Default::default(),
        }
    }
}

pub(crate) fn parse_topic_post_boost_value(
    value: Value,
) -> Result<TopicPostBoost, serde_json::Error> {
    let value = match value {
        Value::Object(mut object) => object.remove("boost").unwrap_or(Value::Object(object)),
        other => other,
    };
    let raw: RawTopicPostBoost = serde_json::from_value(value)?;
    Ok(raw.into())
}

pub(crate) fn parse_topic_post_value(
    value: Value,
    base_url: &str,
) -> Result<TopicPost, serde_json::Error> {
    let value = match value {
        Value::Object(mut object) => object.remove("post").unwrap_or(Value::Object(object)),
        value => value,
    };
    let mut post: TopicPost = RawTopicPost::deserialize(value)?.into();
    crate::attach_post_presentation(&mut post, base_url);
    Ok(post)
}

pub(crate) fn parse_topic_post_list_value(
    value: Value,
    base_url: &str,
) -> Result<Vec<TopicPost>, serde_json::Error> {
    let mut posts: Vec<TopicPost> = Vec::<RawTopicPost>::deserialize(value)?
        .into_iter()
        .map(Into::into)
        .collect();
    crate::attach_posts_presentation(&mut posts, base_url);
    Ok(posts)
}

pub(crate) fn parse_post_reply_ids_value(value: Value) -> Result<Vec<u64>, serde_json::Error> {
    let items = match value {
        Value::Array(items) => items,
        value => {
            return Err(invalid_json(format!(
                "post reply ids root was {}, expected array",
                value_kind(&value)
            )));
        }
    };

    Ok(items
        .iter()
        .filter_map(|item| match item {
            Value::Object(object) => integer_u64(object.get("id")),
            value => integer_u64(Some(value)),
        })
        .filter(|id| *id > 0)
        .collect())
}

pub(crate) fn parse_post_reaction_update_value(
    value: Value,
) -> Result<PostReactionUpdate, serde_json::Error> {
    RawPostReactionUpdate::deserialize(value).map(Into::into)
}

pub(crate) fn parse_reaction_users_groups_value(
    value: Value,
) -> Result<Vec<ReactionUsersGroup>, serde_json::Error> {
    let items = match value {
        Value::Array(items) => items,
        Value::Object(object) => object
            .get("reaction_users")
            .or_else(|| object.get("reactions"))
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
        _ => Vec::new(),
    };

    Ok(parse_array_items_lossy(
        &items,
        "reaction users group",
        parse_reaction_users_group_value,
    ))
}

fn parse_reaction_users_group_value(
    value: &Value,
) -> Result<ReactionUsersGroup, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("reaction users group was not an object"))?;
    let id = scalar_string(object.get("id"))
        .ok_or_else(|| invalid_json("reaction users group did not contain an id"))?;
    let users = object
        .get("users")
        .and_then(Value::as_array)
        .map(|items| {
            parse_array_items_lossy(items, "reaction user entry", parse_reaction_user_value)
        })
        .unwrap_or_default();
    let count = integer_u32(object.get("count")).unwrap_or(users.len() as u32);

    Ok(ReactionUsersGroup { id, count, users })
}

fn parse_reaction_user_value(value: &Value) -> Result<ReactionUser, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("reaction user entry was not an object"))?;
    let username = scalar_string(object.get("username"))
        .ok_or_else(|| invalid_json("reaction user entry did not contain a username"))?;

    Ok(ReactionUser {
        id: integer_u64(object.get("id")).unwrap_or_default(),
        username,
        name: scalar_string(object.get("name")),
        avatar_template: scalar_string(object.get("avatar_template")),
    })
}

fn value_kind(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "bool",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "object",
    }
}

fn default_post_type() -> i32 {
    1
}
