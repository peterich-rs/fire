fn boost_display_text(cooked: &str, user: &RawTopicPostBoostUser) -> String {
    let plain_text = crate::present_cooked_html(cooked, "https://linux.do")
        .map(|presented| presented.presentation().plain_text.clone())
        .unwrap_or_default();
    let body_text = strip_boost_leading_attribution(&plain_text, user);
    separate_boost_emoji_shortcodes(&body_text)
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn strip_boost_leading_attribution(value: &str, user: &RawTopicPostBoostUser) -> String {
    let trimmed = value.trim_start();
    if trimmed.is_empty() {
        return String::new();
    }

    let candidates = [
        normalized_scalar(Some(user.username.as_str())).map(|username| format!("@{username}:")),
        normalized_scalar(Some(user.username.as_str())).map(|username| format!("{username}:")),
        normalized_scalar(user.name.as_deref()).map(|name| format!("{name}:")),
        normalized_scalar(Some(user.username.as_str())).map(|username| format!("@{username}：")),
        normalized_scalar(Some(user.username.as_str())).map(|username| format!("{username}：")),
        normalized_scalar(user.name.as_deref()).map(|name| format!("{name}：")),
    ];

    for candidate in candidates.into_iter().flatten() {
        if trimmed
            .get(..candidate.len())
            .is_some_and(|prefix| prefix.eq_ignore_ascii_case(&candidate))
        {
            return trimmed[candidate.len()..].trim_start().to_string();
        }
    }

    let Some(rest) = trimmed.strip_prefix('@') else {
        return trimmed.to_string();
    };
    let Some(colon_index_after_at) = rest.find([':', '：']) else {
        return trimmed.to_string();
    };
    let username = &rest[..colon_index_after_at];
    if !username.is_empty()
        && username.len() <= 40
        && username.chars().all(|character| !character.is_whitespace())
    {
        let colon_width = rest[colon_index_after_at..]
            .chars()
            .next()
            .map(char::len_utf8)
            .unwrap_or(1);
        let colon_end_index = 1 + colon_index_after_at + colon_width;
        return trimmed[colon_end_index..].trim_start().to_string();
    }

    trimmed.to_string()
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
        let presented = crate::present_cooked_html(&value.cooked, "https://linux.do");
        let display_text = presented
            .as_ref()
            .map(|document| {
                let body_text = strip_boost_leading_attribution(
                    &document.presentation().plain_text,
                    &value.user,
                );
                separate_boost_emoji_shortcodes(&body_text)
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .unwrap_or_else(|| boost_display_text(&value.cooked, &value.user));
        Self {
            id: value.id,
            cooked: value.cooked,
            display_text,
            user: value.user.into(),
            can_delete: value.can_delete,
            can_flag: value.can_flag,
            user_flag_status: value.user_flag_status,
            available_flags: value.available_flags,
            presented: presented
                .map(|document| {
                    fire_models::AttachedPresentation::some(std::sync::Arc::new(document))
                })
                .unwrap_or_default(),
        }
    }
}

pub(crate) fn parse_topic_post_boost_value(
    value: Value,
) -> Result<TopicPostBoost, serde_json::Error> {
    let value = match value {
        Value::Object(mut object) => object.remove("boost").unwrap_or(Value::Object(object)),
        other => other,
    };
    let raw: RawTopicPostBoost = serde_json::from_value(value)?;
    Ok(raw.into())
}

