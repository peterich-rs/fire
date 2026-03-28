use fire_models::{
    TopicDetail, TopicDetailCreatedBy, TopicDetailMeta, TopicListResponse, TopicPost,
    TopicPostStream, TopicPoster, TopicReaction, TopicSummary, TopicUser,
};
use serde::Deserialize;

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RawTopicListResponse {
    #[serde(default)]
    topic_list: RawTopicListPage,
    #[serde(default)]
    users: Vec<RawTopicUser>,
}

impl From<RawTopicListResponse> for TopicListResponse {
    fn from(value: RawTopicListResponse) -> Self {
        Self {
            topics: value
                .topic_list
                .topics
                .into_iter()
                .map(Into::into)
                .collect(),
            users: value.users.into_iter().map(Into::into).collect(),
            more_topics_url: value.topic_list.more_topics_url,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicListPage {
    #[serde(default)]
    topics: Vec<RawTopicSummary>,
    more_topics_url: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicUser {
    #[serde(default)]
    id: u64,
    #[serde(default)]
    username: String,
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
    #[serde(default)]
    user_id: u64,
    description: Option<String>,
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
    #[serde(default)]
    id: u64,
    #[serde(default)]
    title: String,
    #[serde(default)]
    slug: String,
    #[serde(default)]
    posts_count: u32,
    #[serde(default)]
    reply_count: u32,
    #[serde(default)]
    views: u32,
    #[serde(default)]
    like_count: u32,
    excerpt: Option<String>,
    created_at: Option<String>,
    last_posted_at: Option<String>,
    last_poster_username: Option<String>,
    category_id: Option<u64>,
    #[serde(default)]
    pinned: bool,
    #[serde(default = "default_visible")]
    visible: bool,
    #[serde(default)]
    closed: bool,
    #[serde(default)]
    archived: bool,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    posters: Vec<RawTopicPoster>,
    #[serde(default)]
    unseen: bool,
    #[serde(default)]
    unread_posts: u32,
    #[serde(default)]
    new_posts: u32,
    last_read_post_number: Option<u32>,
    #[serde(default)]
    highest_post_number: u32,
    #[serde(default)]
    has_accepted_answer: bool,
    #[serde(default)]
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
            has_accepted_answer: value.has_accepted_answer,
            can_have_answer: value.can_have_answer,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicReaction {
    #[serde(default)]
    id: String,
    #[serde(rename = "type")]
    kind: Option<String>,
    #[serde(default)]
    count: u32,
}

impl From<RawTopicReaction> for TopicReaction {
    fn from(value: RawTopicReaction) -> Self {
        Self {
            id: value.id,
            kind: value.kind,
            count: value.count,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicPost {
    #[serde(default)]
    id: u64,
    #[serde(default)]
    username: String,
    name: Option<String>,
    avatar_template: Option<String>,
    #[serde(default)]
    cooked: String,
    #[serde(default)]
    post_number: u32,
    #[serde(default = "default_post_type")]
    post_type: i32,
    created_at: Option<String>,
    updated_at: Option<String>,
    #[serde(default)]
    like_count: u32,
    #[serde(default)]
    reply_count: u32,
    reply_to_post_number: Option<u32>,
    #[serde(default)]
    bookmarked: bool,
    bookmark_id: Option<u64>,
    #[serde(default)]
    reactions: Vec<RawTopicReaction>,
    current_user_reaction: Option<RawTopicReaction>,
    #[serde(default)]
    accepted_answer: bool,
    #[serde(default)]
    can_edit: bool,
    #[serde(default)]
    can_delete: bool,
    #[serde(default)]
    can_recover: bool,
    #[serde(default)]
    hidden: bool,
}

impl From<RawTopicPost> for TopicPost {
    fn from(value: RawTopicPost) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            cooked: value.cooked,
            post_number: value.post_number,
            post_type: value.post_type,
            created_at: value.created_at,
            updated_at: value.updated_at,
            like_count: value.like_count,
            reply_count: value.reply_count,
            reply_to_post_number: value.reply_to_post_number,
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
            accepted_answer: value.accepted_answer,
            can_edit: value.can_edit,
            can_delete: value.can_delete,
            can_recover: value.can_recover,
            hidden: value.hidden,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawTopicPostStream {
    #[serde(default)]
    posts: Vec<RawTopicPost>,
    #[serde(default)]
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
    #[serde(default)]
    id: u64,
    #[serde(default)]
    username: String,
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
    notification_level: Option<i32>,
    #[serde(default)]
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

#[derive(Debug, Default, Deserialize)]
pub(crate) struct RawTopicDetail {
    #[serde(default)]
    id: u64,
    #[serde(default)]
    title: String,
    #[serde(default)]
    slug: String,
    #[serde(default)]
    posts_count: u32,
    category_id: Option<u64>,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    views: u32,
    #[serde(default)]
    like_count: u32,
    created_at: Option<String>,
    last_read_post_number: Option<u32>,
    #[serde(default)]
    bookmarks: Vec<u64>,
    #[serde(default)]
    accepted_answer: bool,
    #[serde(default)]
    has_accepted_answer: bool,
    #[serde(default)]
    can_vote: bool,
    #[serde(default)]
    vote_count: i32,
    #[serde(default)]
    user_voted: bool,
    #[serde(default)]
    summarizable: bool,
    #[serde(default)]
    has_cached_summary: bool,
    #[serde(default)]
    has_summary: bool,
    archetype: Option<String>,
    #[serde(default)]
    post_stream: RawTopicPostStream,
    #[serde(default)]
    details: RawTopicDetailMeta,
}

impl From<RawTopicDetail> for TopicDetail {
    fn from(value: RawTopicDetail) -> Self {
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
            bookmarks: value.bookmarks,
            accepted_answer: value.accepted_answer,
            has_accepted_answer: value.has_accepted_answer,
            can_vote: value.can_vote,
            vote_count: value.vote_count,
            user_voted: value.user_voted,
            summarizable: value.summarizable,
            has_cached_summary: value.has_cached_summary,
            has_summary: value.has_summary,
            archetype: value.archetype,
            post_stream: value.post_stream.into(),
            details: value.details.into(),
        }
    }
}

fn default_visible() -> bool {
    true
}

fn default_post_type() -> i32 {
    1
}
