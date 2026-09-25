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

