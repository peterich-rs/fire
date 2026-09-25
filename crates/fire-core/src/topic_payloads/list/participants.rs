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

