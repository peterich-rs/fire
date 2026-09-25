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

