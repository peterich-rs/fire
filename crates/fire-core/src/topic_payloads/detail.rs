use fire_models::{
    TopicAiSummary, TopicDetail, TopicDetailCreatedBy, TopicDetailMeta, TopicPostStream, TopicTag,
    TopicThread,
};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;

use super::deser::{
    deserialize_default_bool, deserialize_default_i32, deserialize_default_record,
    deserialize_default_sequence, deserialize_default_string, deserialize_default_u32,
    deserialize_default_u64, deserialize_optional_i32, deserialize_optional_i64,
    deserialize_optional_record, deserialize_optional_scalar_string, deserialize_optional_u32,
    deserialize_optional_u64, deserialize_presence_bool, deserialize_topic_tags,
    deserialize_u64_sequence,
};
use super::list::RawTopicParticipant;
use super::post::RawTopicPost;

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
    pub(crate) fn into_topic_detail(
        self,
        include_thread_state: bool,
        base_url: &str,
    ) -> TopicDetail {
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
        crate::attach_posts_presentation(&mut post_stream.posts, base_url);
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
        value.into_topic_detail(true, "https://linux.do")
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

pub(crate) fn parse_topic_post_stream_value(
    value: Value,
    base_url: &str,
) -> Result<TopicPostStream, serde_json::Error> {
    let value = match value {
        Value::Object(mut object) => object
            .remove("post_stream")
            .unwrap_or(Value::Object(object)),
        value => value,
    };
    let mut stream: TopicPostStream = RawTopicPostStream::deserialize(value)?.into();
    crate::attach_posts_presentation(&mut stream.posts, base_url);
    Ok(stream)
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
