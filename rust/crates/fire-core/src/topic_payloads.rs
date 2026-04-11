use fire_models::{
    Poll, PollOption, PostReactionUpdate, TopicDetail, TopicDetailCreatedBy, TopicDetailMeta,
    TopicListResponse, TopicPost, TopicPostStream, TopicPoster, TopicReaction, TopicRow,
    TopicSummary, TopicTag, TopicThread, TopicUser, VoteResponse, VotedUser,
};
use serde::{
    de::{DeserializeOwned, Error as DeError},
    Deserialize, Deserializer,
};
use serde_json::Value;
use std::{any::type_name, collections::HashMap};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use tracing::warn;

use crate::json_helpers::{
    boolean, integer_i32, integer_u32, integer_u64, invalid_json, scalar_string,
};
use crate::preview_text_from_html;
use crate::topic_status_labels;

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RawTopicListResponse {
    #[serde(default, deserialize_with = "deserialize_default_record")]
    topic_list: RawTopicListPage,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    users: Vec<RawTopicUser>,
}

impl From<RawTopicListResponse> for TopicListResponse {
    fn from(value: RawTopicListResponse) -> Self {
        let topics: Vec<TopicSummary> = value
            .topic_list
            .topics
            .into_iter()
            .map(Into::into)
            .collect();
        let users: Vec<TopicUser> = value.users.into_iter().map(Into::into).collect();
        let next_page = next_page_from_more_topics_url(value.topic_list.more_topics_url.as_deref());
        let rows = topic_rows_from_topics_and_users(&topics, &users);
        Self {
            topics,
            users,
            rows,
            more_topics_url: value.topic_list.more_topics_url,
            next_page,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicListPage {
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    topics: Vec<RawTopicSummary>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    more_topics_url: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicUser {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    username: String,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    avatar_template: Option<String>,
}

impl From<RawTopicUser> for TopicUser {
    fn from(value: RawTopicUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicPoster {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    user_id: u64,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    description: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    extras: Option<String>,
}

impl From<RawTopicPoster> for TopicPoster {
    fn from(value: RawTopicPoster) -> Self {
        Self {
            user_id: value.user_id,
            description: value.description,
            extras: value.extras,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicSummary {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    title: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    slug: String,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    posts_count: u32,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    reply_count: u32,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    views: u32,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    like_count: u32,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    excerpt: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    created_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    last_posted_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    last_poster_username: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    category_id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    pinned: bool,
    #[serde(
        default = "default_visible",
        deserialize_with = "deserialize_default_true_bool"
    )]
    visible: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    closed: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    archived: bool,
    #[serde(default, deserialize_with = "deserialize_topic_tags")]
    tags: Vec<TopicTag>,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    posters: Vec<RawTopicPoster>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    unseen: bool,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    unread_posts: u32,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    new_posts: u32,
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    last_read_post_number: Option<u32>,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    highest_post_number: u32,
    #[serde(
        default,
        rename = "_bookmarked_post_number",
        deserialize_with = "deserialize_optional_u32"
    )]
    bookmarked_post_number: Option<u32>,
    #[serde(
        default,
        rename = "_bookmark_id",
        deserialize_with = "deserialize_optional_u64"
    )]
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
    #[serde(
        default,
        rename = "_bookmarkable_type",
        deserialize_with = "deserialize_optional_scalar_string"
    )]
    bookmarkable_type: Option<String>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    has_accepted_answer: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_have_answer: bool,
}

impl From<RawTopicSummary> for TopicSummary {
    fn from(value: RawTopicSummary) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            reply_count: value.reply_count,
            views: value.views,
            like_count: value.like_count,
            excerpt: value.excerpt,
            created_at: value.created_at,
            last_posted_at: value.last_posted_at,
            last_poster_username: value.last_poster_username,
            category_id: value.category_id,
            pinned: value.pinned,
            visible: value.visible,
            closed: value.closed,
            archived: value.archived,
            tags: value.tags,
            posters: value.posters.into_iter().map(Into::into).collect(),
            unseen: value.unseen,
            unread_posts: value.unread_posts,
            new_posts: value.new_posts,
            last_read_post_number: value.last_read_post_number,
            highest_post_number: value.highest_post_number,
            bookmarked_post_number: value.bookmarked_post_number,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            bookmarkable_type: value.bookmarkable_type,
            has_accepted_answer: value.has_accepted_answer,
            can_have_answer: value.can_have_answer,
        }
    }
}

fn topic_rows_from_topics_and_users(topics: &[TopicSummary], users: &[TopicUser]) -> Vec<TopicRow> {
    let users_by_id: HashMap<u64, &TopicUser> = users.iter().map(|user| (user.id, user)).collect();
    topics
        .iter()
        .cloned()
        .map(|topic| topic_row_from_topic(topic, &users_by_id))
        .collect()
}

fn topic_row_from_topic(topic: TopicSummary, users_by_id: &HashMap<u64, &TopicUser>) -> TopicRow {
    let tag_names = topic_tag_names(&topic.tags);
    let original_poster = original_poster_user(&topic, users_by_id);
    TopicRow {
        excerpt_text: preview_text_from_html(topic.excerpt.as_deref()),
        original_poster_username: normalized_scalar(
            original_poster.map(|user| user.username.as_str()),
        ),
        original_poster_avatar_template: normalized_scalar(
            original_poster.and_then(|user| user.avatar_template.as_deref()),
        ),
        tag_names,
        status_labels: topic_status_labels(&topic),
        is_pinned: topic.pinned,
        is_closed: topic.closed,
        is_archived: topic.archived,
        has_accepted_answer: topic.has_accepted_answer,
        has_unread_posts: topic.unread_posts > 0,
        created_timestamp_unix_ms: timestamp_unix_ms(topic.created_at.as_deref()),
        activity_timestamp_unix_ms: timestamp_unix_ms(
            topic
                .last_posted_at
                .as_deref()
                .or(topic.created_at.as_deref()),
        ),
        last_poster_username: resolved_last_poster_username(&topic),
        topic,
    }
}

fn original_poster_user<'a>(
    topic: &TopicSummary,
    users_by_id: &HashMap<u64, &'a TopicUser>,
) -> Option<&'a TopicUser> {
    let original_poster = topic
        .posters
        .iter()
        .find(|poster| {
            poster
                .description
                .as_deref()
                .is_some_and(|value| value.to_ascii_lowercase().contains("original poster"))
        })
        .or_else(|| topic.posters.first())?;
    users_by_id.get(&original_poster.user_id).copied()
}

fn resolved_last_poster_username(topic: &TopicSummary) -> Option<String> {
    normalized_scalar(topic.last_poster_username.as_deref())
        .or_else(|| {
            topic
                .posters
                .first()
                .and_then(|poster| normalized_scalar(poster.description.as_deref()))
        })
        .or_else(|| {
            topic
                .posters
                .first()
                .map(|poster| format!("User {}", poster.user_id))
        })
}

fn topic_tag_names(tags: &[TopicTag]) -> Vec<String> {
    tags.iter()
        .filter_map(|tag| {
            normalized_scalar(Some(tag.name.as_str()))
                .or_else(|| normalized_scalar(tag.slug.as_deref()))
        })
        .take(2)
        .collect()
}

fn normalized_scalar(value: Option<&str>) -> Option<String> {
    let value = value?;
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn timestamp_unix_ms(raw_value: Option<&str>) -> Option<u64> {
    let raw_value = raw_value?.trim();
    if raw_value.is_empty() {
        return None;
    }

    let timestamp_ms = OffsetDateTime::parse(raw_value, &Rfc3339)
        .ok()?
        .unix_timestamp_nanos()
        / 1_000_000;
    u64::try_from(timestamp_ms).ok()
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
struct RawPollOption {
    #[serde(default, deserialize_with = "deserialize_default_string")]
    id: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    html: String,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    votes: u32,
}

impl From<RawPollOption> for PollOption {
    fn from(value: RawPollOption) -> Self {
        Self {
            id: value.id,
            html: value.html,
            votes: value.votes,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawPoll {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    name: String,
    #[serde(
        default,
        rename = "type",
        deserialize_with = "deserialize_default_string"
    )]
    kind: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    status: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    results: String,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    options: Vec<RawPollOption>,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    voters: u32,
}

impl From<RawPoll> for Poll {
    fn from(value: RawPoll) -> Self {
        Self {
            id: value.id,
            name: value.name,
            kind: if value.kind.is_empty() {
                "regular".to_string()
            } else {
                value.kind
            },
            status: if value.status.is_empty() {
                "open".to_string()
            } else {
                value.status
            },
            results: if value.results.is_empty() {
                "always".to_string()
            } else {
                value.results
            },
            options: value.options.into_iter().map(Into::into).collect(),
            voters: value.voters,
            user_votes: Vec::new(),
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicPost {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    username: String,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    avatar_template: Option<String>,
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
    current_user_reaction: Option<RawTopicReaction>,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    polls: Vec<RawPoll>,
    #[serde(default, deserialize_with = "deserialize_optional_string_sequence_map")]
    polls_votes: Option<HashMap<String, Vec<String>>>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    accepted_answer: bool,
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
            cooked: value.cooked,
            raw: value.raw,
            post_number: value.post_number,
            post_type: value.post_type,
            created_at: value.created_at,
            updated_at: value.updated_at,
            like_count: value.like_count,
            reply_count: value.reply_count,
            reply_to_post_number: value.reply_to_post_number,
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            bookmark_name: value.bookmark_name,
            bookmark_reminder_at: value.bookmark_reminder_at,
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
            polls,
            accepted_answer: value.accepted_answer,
            can_edit: value.can_edit,
            can_delete: value.can_delete,
            can_recover: value.can_recover,
            hidden: value.hidden,
        }
    }
}

pub(crate) fn parse_topic_post_value(value: Value) -> Result<TopicPost, serde_json::Error> {
    let value = match value {
        Value::Object(mut object) => object.remove("post").unwrap_or(Value::Object(object)),
        value => value,
    };
    RawTopicPost::deserialize(value).map(Into::into)
}

pub(crate) fn parse_topic_post_stream_value(
    value: Value,
) -> Result<TopicPostStream, serde_json::Error> {
    let value = match value {
        Value::Object(mut object) => object
            .remove("post_stream")
            .unwrap_or(Value::Object(object)),
        value => value,
    };
    RawTopicPostStream::deserialize(value).map(Into::into)
}

pub(crate) fn parse_post_reaction_update_value(
    value: Value,
) -> Result<PostReactionUpdate, serde_json::Error> {
    RawPostReactionUpdate::deserialize(value).map(Into::into)
}

pub(crate) fn parse_poll_response_value(value: Value) -> Result<Poll, serde_json::Error> {
    let value = match value {
        Value::Object(ref object) if object.contains_key("poll") => object
            .get("poll")
            .cloned()
            .unwrap_or_else(|| Value::Object(object.clone())),
        value => value,
    };
    RawPoll::deserialize(value).map(Into::into)
}

pub(crate) fn parse_vote_response_value(value: Value) -> Result<VoteResponse, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("vote response root was not an object"));
    };

    let who_voted = object
        .get("who_voted")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .cloned()
                .map(parse_voted_user_value)
                .collect::<Result<Vec<_>, _>>()
        })
        .transpose()?
        .unwrap_or_default();

    Ok(VoteResponse {
        can_vote: boolean(object.get("can_vote")),
        vote_limit: integer_u32(object.get("vote_limit")).unwrap_or(0),
        vote_count: integer_i32(object.get("vote_count")).unwrap_or(0),
        votes_left: integer_i32(object.get("votes_left")).unwrap_or(0),
        alert: boolean(object.get("alert")),
        who_voted,
    })
}

pub(crate) fn parse_voted_users_value(value: Value) -> Result<Vec<VotedUser>, serde_json::Error> {
    let items = match value {
        Value::Array(items) => items,
        Value::Object(object) => object
            .get("who_voted")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
        _ => Vec::new(),
    };

    items
        .into_iter()
        .map(parse_voted_user_value)
        .collect::<Result<Vec<_>, _>>()
}

fn parse_voted_user_value(value: Value) -> Result<VotedUser, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("voted user entry was not an object"));
    };

    Ok(VotedUser {
        id: integer_u64(object.get("id")).unwrap_or(0),
        username: scalar_string(object.get("username")).unwrap_or_default(),
        name: scalar_string(object.get("name")),
        avatar_template: scalar_string(object.get("avatar_template")),
    })
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicPostStream {
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    posts: Vec<RawTopicPost>,
    #[serde(default, deserialize_with = "deserialize_u64_sequence")]
    stream: Vec<u64>,
}

impl From<RawTopicPostStream> for TopicPostStream {
    fn from(value: RawTopicPostStream) -> Self {
        Self {
            posts: value.posts.into_iter().map(Into::into).collect(),
            stream: value.stream,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicDetailCreatedBy {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    username: String,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    avatar_template: Option<String>,
}

impl From<RawTopicDetailCreatedBy> for TopicDetailCreatedBy {
    fn from(value: RawTopicDetailCreatedBy) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicDetailMeta {
    #[serde(default, deserialize_with = "deserialize_optional_i32")]
    notification_level: Option<i32>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_edit: bool,
    created_by: Option<RawTopicDetailCreatedBy>,
}

impl From<RawTopicDetailMeta> for TopicDetailMeta {
    fn from(value: RawTopicDetailMeta) -> Self {
        Self {
            notification_level: value.notification_level,
            can_edit: value.can_edit,
            created_by: value.created_by.map(Into::into),
        }
    }
}

#[derive(Debug, Default, Clone, Deserialize)]
struct RawBookmarkEntry {
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    bookmarkable_type: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    bookmarkable_id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    reminder_at: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RawTopicDetail {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    title: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    slug: String,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    posts_count: u32,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    category_id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_topic_tags")]
    tags: Vec<TopicTag>,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    views: u32,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    like_count: u32,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    created_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    last_read_post_number: Option<u32>,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    bookmarks: Vec<RawBookmarkEntry>,
    #[serde(default, deserialize_with = "deserialize_presence_bool")]
    accepted_answer: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    has_accepted_answer: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_vote: bool,
    #[serde(default, deserialize_with = "deserialize_default_i32")]
    vote_count: i32,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    user_voted: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    summarizable: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    has_cached_summary: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    has_summary: bool,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    archetype: Option<String>,
    #[serde(default, deserialize_with = "deserialize_default_record")]
    post_stream: RawTopicPostStream,
    #[serde(default, deserialize_with = "deserialize_default_record")]
    details: RawTopicDetailMeta,
}

impl From<RawTopicDetail> for TopicDetail {
    fn from(value: RawTopicDetail) -> Self {
        let bookmark_ids = value
            .bookmarks
            .iter()
            .filter_map(|bookmark| bookmark.id)
            .collect();
        let mut topic_bookmarked = false;
        let mut topic_bookmark_id = None;
        let mut topic_bookmark_name = None;
        let mut topic_bookmark_reminder_at = None;
        let mut post_bookmarks = HashMap::new();
        for bookmark in &value.bookmarks {
            match bookmark.bookmarkable_type.as_deref() {
                Some("Topic") => {
                    topic_bookmarked = true;
                    topic_bookmark_id = bookmark.id;
                    topic_bookmark_name = bookmark.name.clone();
                    topic_bookmark_reminder_at = bookmark.reminder_at.clone();
                }
                Some("Post") => {
                    if let Some(bookmarkable_id) = bookmark.bookmarkable_id {
                        post_bookmarks.insert(bookmarkable_id, bookmark.clone());
                    }
                }
                _ => {}
            }
        }

        let mut post_stream: TopicPostStream = value.post_stream.into();
        if !post_bookmarks.is_empty() {
            for post in &mut post_stream.posts {
                if let Some(bookmark) = post_bookmarks.get(&post.id) {
                    post.bookmarked = true;
                    post.bookmark_id = bookmark.id;
                    post.bookmark_name = bookmark.name.clone();
                    post.bookmark_reminder_at = bookmark.reminder_at.clone();
                }
            }
        }
        let thread = TopicThread::from_posts(&post_stream.posts);
        let flat_posts = thread.flatten(&post_stream.posts);
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            category_id: value.category_id,
            tags: value.tags,
            views: value.views,
            like_count: value.like_count,
            created_at: value.created_at,
            last_read_post_number: value.last_read_post_number,
            bookmarks: bookmark_ids,
            bookmarked: topic_bookmarked,
            bookmark_id: topic_bookmark_id,
            bookmark_name: topic_bookmark_name,
            bookmark_reminder_at: topic_bookmark_reminder_at,
            accepted_answer: value.accepted_answer,
            has_accepted_answer: value.has_accepted_answer,
            can_vote: value.can_vote,
            vote_count: value.vote_count,
            user_voted: value.user_voted,
            summarizable: value.summarizable,
            has_cached_summary: value.has_cached_summary,
            has_summary: value.has_summary,
            archetype: value.archetype,
            post_stream,
            thread,
            flat_posts,
            details: value.details.into(),
        }
    }
}

fn next_page_from_more_topics_url(more_topics_url: Option<&str>) -> Option<u32> {
    let more_topics_url = more_topics_url?.trim();
    if more_topics_url.is_empty() {
        return None;
    }

    [
        more_topics_url,
        &format!("https://linux.do{more_topics_url}"),
    ]
    .into_iter()
    .find_map(query_page_parameter)
}

fn query_page_parameter(url: &str) -> Option<u32> {
    let query = url.split_once('?')?.1;
    query.split('&').find_map(|segment| {
        let (key, value) = segment.split_once('=')?;
        if key == "page" {
            value.parse::<u32>().ok()
        } else {
            None
        }
    })
}

fn default_visible() -> bool {
    true
}

fn default_post_type() -> i32 {
    1
}

fn deserialize_default_record<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned + Default,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    match value {
        None | Some(Value::Null) => Ok(T::default()),
        Some(value) => T::deserialize(value).map_err(D::Error::custom),
    }
}

fn deserialize_default_sequence<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Value::Array(values) = value.unwrap_or(Value::Array(Vec::new())) else {
        return Ok(Vec::new());
    };

    let record_type = type_name::<T>();
    let mut records = Vec::with_capacity(values.len());
    for (index, value) in values.into_iter().enumerate() {
        match T::deserialize(value) {
            Ok(record) => records.push(record),
            Err(error) => warn!(
                index,
                record_type,
                error = %error,
                "dropping malformed item while deserializing default sequence"
            ),
        }
    }

    Ok(records)
}

fn deserialize_optional_string_sequence_map<'de, D>(
    deserializer: D,
) -> Result<Option<HashMap<String, Vec<String>>>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Some(Value::Object(object)) = value else {
        return Ok(None);
    };

    let mut result = HashMap::new();
    for (key, value) in object {
        let values = match value {
            Value::Array(items) => items
                .into_iter()
                .filter_map(|item| match item {
                    Value::String(value) => Some(value),
                    Value::Number(value) => Some(value.to_string()),
                    Value::Bool(value) => Some(value.to_string()),
                    Value::Array(_) | Value::Object(_) | Value::Null => None,
                })
                .collect::<Vec<_>>(),
            Value::String(value) => vec![value],
            Value::Number(value) => vec![value.to_string()],
            Value::Bool(value) => vec![value.to_string()],
            Value::Object(_) | Value::Null => Vec::new(),
        };
        if !values.is_empty() {
            result.insert(key, values);
        }
    }

    Ok(Some(result))
}

fn deserialize_u64_sequence<'de, D>(deserializer: D) -> Result<Vec<u64>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Value::Array(values) = value.unwrap_or(Value::Array(Vec::new())) else {
        return Ok(Vec::new());
    };

    Ok(values
        .into_iter()
        .filter_map(|value| match value {
            Value::Number(value) => value.as_u64(),
            Value::String(value) => value.parse::<u64>().ok(),
            Value::Bool(value) => Some(u64::from(value)),
            Value::Array(_) | Value::Object(_) | Value::Null => None,
        })
        .collect())
}

fn deserialize_optional_scalar_string<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::String(value)) => Some(value),
        Some(Value::Bool(value)) => Some(value.to_string()),
        Some(Value::Number(value)) => Some(value.to_string()),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

fn deserialize_default_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(deserialize_optional_scalar_string(deserializer)?.unwrap_or_default())
}

fn deserialize_default_u64<'de, D>(deserializer: D) -> Result<u64, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(deserialize_optional_u64(deserializer)?.unwrap_or_default())
}

fn deserialize_optional_u64<'de, D>(deserializer: D) -> Result<Option<u64>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Number(value)) => value.as_u64(),
        Some(Value::String(value)) => value.parse::<u64>().ok(),
        Some(Value::Bool(value)) => Some(u64::from(value)),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

fn deserialize_default_u32<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(deserialize_optional_u32(deserializer)?.unwrap_or_default())
}

fn deserialize_optional_u32<'de, D>(deserializer: D) -> Result<Option<u32>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Number(value)) => value.as_u64().and_then(|value| u32::try_from(value).ok()),
        Some(Value::String(value)) => value.parse::<u32>().ok(),
        Some(Value::Bool(value)) => Some(u32::from(value)),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

fn deserialize_optional_i32<'de, D>(deserializer: D) -> Result<Option<i32>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Number(value)) => value.as_i64().and_then(|value| i32::try_from(value).ok()),
        Some(Value::String(value)) => value.parse::<i32>().ok(),
        Some(Value::Bool(value)) => Some(i32::from(value)),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

fn deserialize_default_i32<'de, D>(deserializer: D) -> Result<i32, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(deserialize_optional_i32(deserializer)?.unwrap_or_default())
}

fn deserialize_default_bool<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => false,
        Some(Value::Bool(value)) => value,
        Some(Value::Number(value)) => value.as_i64().is_some_and(|value| value != 0),
        Some(Value::String(value)) => matches!(value.as_str(), "true" | "1"),
        Some(Value::Array(_)) | Some(Value::Object(_)) => false,
    })
}

fn deserialize_optional_bool<'de, D>(deserializer: D) -> Result<Option<bool>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Bool(value)) => Some(value),
        Some(Value::Number(value)) => value.as_i64().map(|value| value != 0),
        Some(Value::String(value)) => Some(matches!(value.as_str(), "true" | "1")),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

fn deserialize_default_true_bool<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => true,
        Some(Value::Bool(value)) => value,
        Some(Value::Number(value)) => value.as_i64().is_some_and(|value| value != 0),
        Some(Value::String(value)) => matches!(value.as_str(), "true" | "1"),
        Some(Value::Array(_)) | Some(Value::Object(_)) => true,
    })
}

fn deserialize_presence_bool<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => false,
        Some(Value::Bool(value)) => value,
        Some(Value::Number(value)) => value.as_i64().is_some_and(|value| value != 0),
        Some(Value::String(value)) => !value.is_empty() && !matches!(value.as_str(), "false" | "0"),
        Some(Value::Array(value)) => !value.is_empty(),
        Some(Value::Object(value)) => !value.is_empty(),
    })
}

fn deserialize_topic_tags<'de, D>(deserializer: D) -> Result<Vec<TopicTag>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Value::Array(values) = value.unwrap_or(Value::Array(Vec::new())) else {
        return Ok(Vec::new());
    };

    Ok(values
        .into_iter()
        .filter_map(|value| match value {
            Value::Null => None,
            Value::String(value) => Some(TopicTag {
                id: None,
                name: value,
                slug: None,
            }),
            Value::Number(value) => Some(TopicTag {
                id: None,
                name: value.to_string(),
                slug: None,
            }),
            Value::Bool(value) => Some(TopicTag {
                id: None,
                name: value.to_string(),
                slug: None,
            }),
            Value::Object(mut value) => {
                let id = value.remove("id").and_then(|value| match value {
                    Value::Number(value) => value.as_u64(),
                    Value::String(value) => value.parse::<u64>().ok(),
                    _ => None,
                });
                let slug = value
                    .remove("slug")
                    .and_then(|value| value.as_str().map(ToOwned::to_owned));
                let name = value
                    .remove("name")
                    .and_then(|value| value.as_str().map(ToOwned::to_owned))
                    .or_else(|| slug.clone())?;

                Some(TopicTag { id, name, slug })
            }
            Value::Array(_) => None,
        })
        .collect())
}
