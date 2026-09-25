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
