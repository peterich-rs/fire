use fire_models::{
    TopicListResponse, TopicParticipant, TopicPoster, TopicRow, TopicSummary, TopicTag, TopicUser,
};
use serde::Deserialize;
use std::collections::HashMap;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

use super::deser::{
    deserialize_default_bool, deserialize_default_record, deserialize_default_sequence,
    deserialize_default_string, deserialize_default_true_bool, deserialize_default_u32,
    deserialize_default_u64, deserialize_optional_record, deserialize_optional_scalar_string,
    deserialize_optional_u32, deserialize_optional_u64, deserialize_topic_tags,
};
use crate::preview_text_from_html;
use crate::topic_status_labels;

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
            is_cached: false,
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
pub(super) struct RawTopicParticipant {
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

pub(super) fn normalized_scalar(value: Option<&str>) -> Option<String> {
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
