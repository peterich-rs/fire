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

