use fire_models::{
    Poll, PollOption, PostReactionUpdate, ReactionUser, ReactionUsersGroup, TopicAiSummary,
    TopicDetail, TopicDetailCreatedBy, TopicDetailMeta, TopicListResponse, TopicParticipant,
    TopicPost, TopicPostAuthorMetadata, TopicPostBoost, TopicPostBoostUser, TopicPostStream,
    TopicPoster, TopicReaction, TopicReplyToUser, TopicRow, TopicSummary, TopicTag, TopicThread,
    TopicUser, VoteResponse, VotedUser,
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
    boolean, integer_i32, integer_u32, integer_u64, invalid_json, parse_array_items_lossy,
    scalar_string,
};
use crate::topic_status_labels;
use crate::{plain_text_from_html, preview_text_from_html, render_cooked_html};

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RawTopicListResponse {
    #[serde(default, deserialize_with = "deserialize_default_record")]
    topic_list: RawTopicListPage,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    users: Vec<RawTopicUser>,
    #[serde(default, deserialize_with = "deserialize_default_record")]
    user_bookmark_list: RawUserBookmarkList,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    bookmarks: Vec<RawUserBookmarkEntry>,
}

impl From<RawTopicListResponse> for TopicListResponse {
    fn from(value: RawTopicListResponse) -> Self {
        let mut users = value.users;
        let topic_list_has_payload =
            !value.topic_list.topics.is_empty() || value.topic_list.more_topics_url.is_some();
        let bookmark_list_has_payload = !value.user_bookmark_list.bookmarks.is_empty()
            || value.user_bookmark_list.more_bookmarks_url.is_some();

        let (raw_topics, more_topics_url) = if topic_list_has_payload {
            (value.topic_list.topics, value.topic_list.more_topics_url)
        } else if bookmark_list_has_payload {
            let topics = value
                .user_bookmark_list
                .bookmarks
                .into_iter()
                .filter_map(|bookmark| bookmark.into_topic_summary(&mut users))
                .collect();
            (topics, value.user_bookmark_list.more_bookmarks_url)
        } else {
            let topics = value
                .bookmarks
                .into_iter()
                .filter_map(|bookmark| bookmark.into_topic_summary(&mut users))
                .collect();
            (topics, None)
        };

        let topics: Vec<TopicSummary> = raw_topics.into_iter().map(Into::into).collect();
        let users: Vec<TopicUser> = users.into_iter().map(Into::into).collect();
        let next_page = next_page_from_more_topics_url(more_topics_url.as_deref());
        let rows = topic_rows_from_topics_and_users(&topics, &users);
        Self {
            topics,
            users,
            rows,
            more_topics_url,
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
struct RawUserBookmarkList {
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    bookmarks: Vec<RawUserBookmarkEntry>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    more_bookmarks_url: Option<String>,
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
struct RawUserBookmarkEntry {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    reminder_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    bookmarkable_type: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    bookmarkable_id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    topic_id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    linked_post_number: Option<u32>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    title: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    fancy_title: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    slug: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    excerpt: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    created_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    bumped_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    last_posted_at: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    last_poster_username: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_u64")]
    category_id: Option<u64>,
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    posts_count: Option<u32>,
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    reply_count: Option<u32>,
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    highest_post_number: Option<u32>,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    views: u32,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    like_count: u32,
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
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    last_read_post_number: Option<u32>,
    #[serde(default, deserialize_with = "deserialize_optional_record")]
    user: Option<RawTopicUser>,
}

impl RawUserBookmarkEntry {
    fn into_topic_summary(self, users: &mut Vec<RawTopicUser>) -> Option<RawTopicSummary> {
        let topic_id = self.topic_id.or_else(|| {
            if self.bookmarkable_type.as_deref() == Some("Topic") {
                self.bookmarkable_id
            } else {
                None
            }
        })?;
        if topic_id == 0 {
            return None;
        }

        let bookmark_name = normalized_scalar(self.name.as_deref());
        let title = normalized_scalar(self.title.as_deref())
            .or_else(|| normalized_scalar(self.fancy_title.as_deref()))
            .or_else(|| bookmark_name.clone())
            .unwrap_or_else(|| format!("Topic {topic_id}"));
        let posts_count = self
            .posts_count
            .or(self.highest_post_number)
            .unwrap_or(1)
            .max(1);
        let reply_count = self
            .reply_count
            .unwrap_or_else(|| posts_count.saturating_sub(1));
        let bookmarked_post_number = match self.bookmarkable_type.as_deref() {
            Some("Post") => self.linked_post_number,
            _ => None,
        };

        let user = self.user;
        let last_poster_username = self
            .last_poster_username
            .or_else(|| user.as_ref().map(|user| user.username.clone()));
        let posters = user
            .as_ref()
            .map(|user| {
                vec![RawTopicPoster {
                    user_id: user.id,
                    description: Some("Original Poster".into()),
                    extras: Some("latest".into()),
                }]
            })
            .unwrap_or_default();

        if let Some(user) = user {
            if !users.iter().any(|existing| existing.id == user.id) {
                users.push(user);
            }
        }

        Some(RawTopicSummary {
            id: topic_id,
            title,
            slug: self.slug.unwrap_or_default(),
            posts_count,
            reply_count,
            views: self.views,
            like_count: self.like_count,
            excerpt: self.excerpt,
            created_at: self.created_at.clone(),
            last_posted_at: self.last_posted_at.or(self.bumped_at).or(self.created_at),
            last_poster_username,
            category_id: self.category_id,
            pinned: self.pinned,
            visible: self.visible,
            closed: self.closed,
            archived: self.archived,
            tags: self.tags,
            posters,
            participants: Vec::new(),
            unseen: false,
            unread_posts: 0,
            new_posts: 0,
            last_read_post_number: self.last_read_post_number,
            highest_post_number: self.highest_post_number.unwrap_or(posts_count),
            bookmarked_post_number,
            bookmark_id: Some(self.id),
            bookmark_name,
            bookmark_reminder_at: self.reminder_at,
            bookmarkable_type: self.bookmarkable_type,
            has_accepted_answer: false,
            can_have_answer: false,
        })
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
struct RawTopicParticipant {
    #[serde(
        default,
        alias = "id",
        alias = "user_id",
        deserialize_with = "deserialize_default_u64"
    )]
    user_id: u64,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    username: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    avatar_template: Option<String>,
}

impl From<RawTopicParticipant> for TopicParticipant {
    fn from(value: RawTopicParticipant) -> Self {
        Self {
            user_id: value.user_id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
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
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    participants: Vec<RawTopicParticipant>,
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
            participants: value.participants.into_iter().map(Into::into).collect(),
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

fn boost_display_text(cooked: &str) -> String {
    let plain_text = render_cooked_html(cooked, "https://linux.do").plain_text;
    separate_boost_emoji_shortcodes(&plain_text)
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
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
        let plain_text = plain_text_from_html(&value.html).trim().to_string();
        Self {
            id: value.id,
            html: value.html,
            plain_text,
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
        let display_text = boost_display_text(&value.cooked);
        Self {
            id: value.id,
            cooked: value.cooked,
            display_text,
            user: value.user.into(),
            can_delete: value.can_delete,
            can_flag: value.can_flag,
            user_flag_status: value.user_flag_status,
            available_flags: value.available_flags,
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

pub(crate) fn parse_topic_post_list_value(
    value: Value,
) -> Result<Vec<TopicPost>, serde_json::Error> {
    Vec::<RawTopicPost>::deserialize(value).map(|posts| posts.into_iter().map(Into::into).collect())
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

pub(crate) fn parse_topic_ai_summary_value(
    value: Value,
) -> Result<Option<TopicAiSummary>, serde_json::Error> {
    let Value::Object(mut object) = value else {
        return Ok(None);
    };
    let Some(summary_value) = object.remove("ai_topic_summary") else {
        return Ok(None);
    };
    if summary_value.is_null() {
        return Ok(None);
    }
    RawTopicAiSummary::deserialize(summary_value).map(|summary| Some(summary.into()))
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
            crate::json_helpers::parse_array_items_lossy(items, "voted user entry", |item| {
                parse_voted_user_value(item.clone())
            })
        })
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

    Ok(crate::json_helpers::parse_array_items_lossy(
        &items,
        "voted user entry",
        |item| parse_voted_user_value(item.clone()),
    ))
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
    #[serde(default, deserialize_with = "deserialize_optional_record")]
    created_by: Option<RawTopicDetailCreatedBy>,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    participants: Vec<RawTopicParticipant>,
}

impl From<RawTopicDetailMeta> for TopicDetailMeta {
    fn from(value: RawTopicDetailMeta) -> Self {
        Self {
            notification_level: value.notification_level,
            can_edit: value.can_edit,
            created_by: value.created_by.map(Into::into),
            participants: value.participants.into_iter().map(Into::into).collect(),
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
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    message_bus_last_id: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    title: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    slug: String,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    posts_count: u32,
    #[serde(default, deserialize_with = "deserialize_optional_u32")]
    highest_post_number: Option<u32>,
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

impl RawTopicDetail {
    pub(crate) fn into_topic_detail(self, include_thread_state: bool) -> TopicDetail {
        let value = self;
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
        let (thread, flat_posts) = if include_thread_state {
            let thread = TopicThread::from_posts(&post_stream.posts);
            let flat_posts = thread.flatten(&post_stream.posts);
            (thread, flat_posts)
        } else {
            (TopicThread::default(), Vec::new())
        };

        TopicDetail {
            id: value.id,
            message_bus_last_id: value.message_bus_last_id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            highest_post_number: value.highest_post_number.unwrap_or(value.posts_count),
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
            timeline_entries: Vec::new(),
            details: value.details.into(),
        }
    }
}

impl From<RawTopicDetail> for TopicDetail {
    fn from(value: RawTopicDetail) -> Self {
        value.into_topic_detail(true)
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicAiSummary {
    #[serde(default, deserialize_with = "deserialize_default_string")]
    summarized_text: String,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    algorithm: Option<String>,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    outdated: bool,
    #[serde(default, deserialize_with = "deserialize_default_bool")]
    can_regenerate: bool,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    new_posts_since_summary: u32,
    #[serde(default, deserialize_with = "deserialize_optional_scalar_string")]
    updated_at: Option<String>,
}

impl From<RawTopicAiSummary> for TopicAiSummary {
    fn from(value: RawTopicAiSummary) -> Self {
        Self {
            summarized_text: value.summarized_text,
            algorithm: value.algorithm,
            outdated: value.outdated,
            can_regenerate: value.can_regenerate,
            new_posts_since_summary: value.new_posts_since_summary,
            updated_at: value.updated_at,
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

fn deserialize_optional_record<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(value) => match T::deserialize(value) {
            Ok(record) => Ok(Some(record)),
            Err(error) => {
                warn!(
                    record_type = type_name::<T>(),
                    error = %error,
                    "dropping malformed optional record while deserializing topic payload"
                );
                Ok(None)
            }
        },
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

fn deserialize_default_string_sequence<'de, D>(deserializer: D) -> Result<Vec<String>, D::Error>
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
            Value::String(value) => Some(value),
            Value::Number(value) => Some(value.to_string()),
            Value::Bool(value) => Some(value.to_string()),
            Value::Array(_) | Value::Object(_) | Value::Null => None,
        })
        .collect())
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

fn deserialize_optional_i64<'de, D>(deserializer: D) -> Result<Option<i64>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Number(value)) => value.as_i64(),
        Some(Value::String(value)) => value.parse::<i64>().ok(),
        Some(Value::Bool(value)) => Some(i64::from(value)),
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn sample_raw_topic_detail() -> RawTopicDetail {
        serde_json::from_value(json!({
            "id": 42,
            "title": "Topic",
            "slug": "topic",
            "posts_count": 2,
            "post_stream": {
                "posts": [
                    {
                        "id": 101,
                        "username": "alice",
                        "cooked": "<p>root</p>",
                        "post_number": 1,
                        "reply_count": 1,
                        "can_boost": true,
                        "boosts": [
                            {
                                "id": 501,
                                "cooked": "<p>Hello <img class=\"emoji\" title=\":wave:\" alt=\":wave:\" src=\"/images/emoji/twitter/wave.png?v=12\"></p>",
                                "user": {
                                    "id": 7,
                                    "username": "carol",
                                    "name": "Carol",
                                    "avatar_template": "/user_avatar/linux.do/carol/{size}/1.png"
                                },
                                "can_delete": true,
                                "can_flag": true,
                                "user_flag_status": 0,
                                "available_flags": ["off_topic", 9]
                            }
                        ]
                    },
                    {
                        "id": 102,
                        "username": "bob",
                        "cooked": "<p>reply</p>",
                        "post_number": 2,
                        "reply_to_post_number": 1
                    }
                ],
                "stream": [101, 102]
            },
            "details": {}
        }))
        .expect("sample topic detail should deserialize")
    }

    #[test]
    fn lightweight_topic_detail_skips_thread_state() {
        let detail = sample_raw_topic_detail().into_topic_detail(false);

        assert_eq!(detail.thread, TopicThread::default());
        assert!(detail.flat_posts.is_empty());
        assert!(detail.timeline_entries.is_empty());
        assert_eq!(detail.post_stream.posts.len(), 2);
    }

    #[test]
    fn full_topic_detail_preserves_thread_state() {
        let detail = sample_raw_topic_detail().into_topic_detail(true);

        assert_eq!(detail.thread.original_post_number, Some(1));
        assert_eq!(detail.flat_posts.len(), 2);
        assert!(detail.timeline_entries.is_empty());
    }

    #[test]
    fn topic_post_boosts_parse_display_text_and_permissions() {
        let detail = sample_raw_topic_detail().into_topic_detail(false);
        let post = detail
            .post_stream
            .posts
            .iter()
            .find(|post| post.id == 101)
            .expect("root post");

        assert!(post.can_boost);
        assert_eq!(post.boosts.len(), 1);
        let boost = &post.boosts[0];
        assert_eq!(boost.id, 501);
        assert_eq!(boost.display_text, "Hello :wave:");
        assert_eq!(boost.user.username, "carol");
        assert_eq!(boost.user.name.as_deref(), Some("Carol"));
        assert!(boost.can_delete);
        assert!(boost.can_flag);
        assert_eq!(boost.user_flag_status, Some(0));
        assert_eq!(boost.available_flags, ["off_topic", "9"]);
    }

    #[test]
    fn topic_post_boost_display_text_normalizes_emoji_images_without_alt() {
        let detail = serde_json::from_value::<RawTopicDetail>(json!({
            "id": 42,
            "title": "Topic",
            "slug": "topic",
            "post_stream": {
                "posts": [
                    {
                        "id": 101,
                        "username": "alice",
                        "cooked": "<p>root</p>",
                        "post_number": 1,
                        "boosts": [
                            {
                                "id": 501,
                                "cooked": "<p><img class=\"emoji\" title=\"smile\" src=\"/images/emoji/twitter/smile.png?v=12\"><img class=\"emoji\" src=\"/images/emoji/twitter/wave/t3.png?v=12\"> 🎉</p>",
                                "user": {"id": 7, "username": "carol"}
                            }
                        ]
                    }
                ],
                "stream": [101]
            },
            "details": {}
        }))
        .expect("sample topic detail should deserialize")
        .into_topic_detail(false);
        let boost = &detail.post_stream.posts[0].boosts[0];

        assert_eq!(boost.display_text, ":smile: :wave:t3: 🎉");
    }
}
