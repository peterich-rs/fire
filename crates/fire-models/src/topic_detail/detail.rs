use serde::{Deserialize, Serialize};

use super::{
    post::TopicPostStream,
    source::TopicHeader,
    tree::{build_floor_timeline_entries, TopicThread, TopicThreadFlatPost, TopicTimelineEntry},
};
use crate::topic::{TopicParticipant, TopicTag};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailCreatedBy {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailMeta {
    pub notification_level: Option<i32>,
    pub can_edit: bool,
    pub created_by: Option<TopicDetailCreatedBy>,
    #[serde(default)]
    pub participants: Vec<TopicParticipant>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicAiSummary {
    pub summarized_text: String,
    pub algorithm: Option<String>,
    pub outdated: bool,
    pub can_regenerate: bool,
    pub new_posts_since_summary: u32,
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetail {
    pub id: u64,
    pub message_bus_last_id: Option<i64>,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTag>,
    pub views: u32,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub highest_post_number: u32,
    pub last_read_post_number: Option<u32>,
    pub bookmarks: Vec<u64>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub accepted_answer: bool,
    pub has_accepted_answer: bool,
    pub can_vote: bool,
    pub vote_count: i32,
    pub user_voted: bool,
    pub summarizable: bool,
    pub has_cached_summary: bool,
    pub has_summary: bool,
    pub archetype: Option<String>,
    pub post_stream: TopicPostStream,
    #[serde(default)]
    pub thread: TopicThread,
    #[serde(default)]
    pub flat_posts: Vec<TopicThreadFlatPost>,
    #[serde(default)]
    pub timeline_entries: Vec<TopicTimelineEntry>,
    pub details: TopicDetailMeta,
}

impl TopicDetail {
    pub fn rebuild_timeline_entries(&mut self) {
        self.timeline_entries = build_floor_timeline_entries(&self.post_stream.posts);
    }

    pub fn reply_count(&self) -> u32 {
        self.posts_count.saturating_sub(1)
    }

    pub fn header(&self) -> TopicHeader {
        TopicHeader {
            topic_id: self.id,
            message_bus_last_id: self.message_bus_last_id,
            title: self.title.clone(),
            slug: self.slug.clone(),
            category_id: self.category_id,
            tags: self.tags.clone(),
            views: self.views,
            like_count: self.like_count,
            posts_count: self.posts_count,
            reply_count: self.reply_count(),
            highest_post_number: self.highest_post_number,
            created_at: self.created_at.clone(),
            last_read_post_number: self.last_read_post_number,
            bookmarks: self.bookmarks.clone(),
            bookmarked: self.bookmarked,
            bookmark_id: self.bookmark_id,
            bookmark_name: self.bookmark_name.clone(),
            bookmark_reminder_at: self.bookmark_reminder_at.clone(),
            accepted_answer: self.accepted_answer,
            has_accepted_answer: self.has_accepted_answer,
            can_vote: self.can_vote,
            vote_count: self.vote_count,
            user_voted: self.user_voted,
            summarizable: self.summarizable,
            has_cached_summary: self.has_cached_summary,
            has_summary: self.has_summary,
            archetype: self.archetype.clone(),
            details: self.details.clone(),
        }
    }

    pub fn interaction_count(&self) -> u32 {
        self.like_count.saturating_add(
            self.post_stream
                .posts
                .iter()
                .flat_map(|post| post.reactions.iter())
                .filter(|reaction| !reaction.id.eq_ignore_ascii_case("heart"))
                .fold(0_u32, |total, reaction| {
                    total.saturating_add(reaction.count)
                }),
        )
    }
}
