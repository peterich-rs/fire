use fire_models::TopicTag;
use serde::{
    de::{DeserializeOwned, Error as DeError},
    Deserialize, Deserializer,
};
use serde_json::Value;
use std::{any::type_name, collections::HashMap};
use tracing::warn;

pub(super) fn deserialize_default_record<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned + Default,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    match value {
        None | Some(Value::Null) => Ok(T::default()),
        Some(value) => T::deserialize(value).map_err(D::Error::custom),
    }
}

pub(super) fn deserialize_optional_record<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(value) => match T::deserialize(value) {
            Ok(record) => Ok(Some(record)),
            Err(error) => {
                warn!(
                    record_type = type_name::<T>(),
                    error = %error,
                    "dropping malformed optional record while deserializing topic payload"
                );
                Ok(None)
            }
        },
    }
}

pub(super) fn deserialize_default_sequence<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Value::Array(values) = value.unwrap_or(Value::Array(Vec::new())) else {
        return Ok(Vec::new());
    };

    let record_type = type_name::<T>();
    let mut records = Vec::with_capacity(values.len());
    for (index, value) in values.into_iter().enumerate() {
        match T::deserialize(value) {
            Ok(record) => records.push(record),
            Err(error) => warn!(
                index,
                record_type,
                error = %error,
                "dropping malformed item while deserializing default sequence"
            ),
        }
    }

    Ok(records)
}

pub(super) fn deserialize_default_string_sequence<'de, D>(
    deserializer: D,
) -> Result<Vec<String>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Value::Array(values) = value.unwrap_or(Value::Array(Vec::new())) else {
        return Ok(Vec::new());
    };

    Ok(values
        .into_iter()
        .filter_map(|value| match value {
            Value::String(value) => Some(value),
            Value::Number(value) => Some(value.to_string()),
            Value::Bool(value) => Some(value.to_string()),
            Value::Array(_) | Value::Object(_) | Value::Null => None,
        })
        .collect())
}

pub(super) fn deserialize_optional_string_sequence_map<'de, D>(
    deserializer: D,
) -> Result<Option<HashMap<String, Vec<String>>>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Some(Value::Object(object)) = value else {
        return Ok(None);
    };

    let mut result = HashMap::new();
    for (key, value) in object {
        let values = match value {
            Value::Array(items) => items
                .into_iter()
                .filter_map(|item| match item {
                    Value::String(value) => Some(value),
                    Value::Number(value) => Some(value.to_string()),
                    Value::Bool(value) => Some(value.to_string()),
                    Value::Array(_) | Value::Object(_) | Value::Null => None,
                })
                .collect::<Vec<_>>(),
            Value::String(value) => vec![value],
            Value::Number(value) => vec![value.to_string()],
            Value::Bool(value) => vec![value.to_string()],
            Value::Object(_) | Value::Null => Vec::new(),
        };
        if !values.is_empty() {
            result.insert(key, values);
        }
    }

    Ok(Some(result))
}

pub(super) fn deserialize_u64_sequence<'de, D>(deserializer: D) -> Result<Vec<u64>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Value::Array(values) = value.unwrap_or(Value::Array(Vec::new())) else {
        return Ok(Vec::new());
    };

    Ok(values
        .into_iter()
        .filter_map(|value| match value {
            Value::Number(value) => value.as_u64(),
            Value::String(value) => value.parse::<u64>().ok(),
            Value::Bool(value) => Some(u64::from(value)),
            Value::Array(_) | Value::Object(_) | Value::Null => None,
        })
        .collect())
}

pub(super) fn deserialize_optional_scalar_string<'de, D>(
    deserializer: D,
) -> Result<Option<String>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::String(value)) => Some(value),
        Some(Value::Bool(value)) => Some(value.to_string()),
        Some(Value::Number(value)) => Some(value.to_string()),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

pub(super) fn deserialize_default_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(deserialize_optional_scalar_string(deserializer)?.unwrap_or_default())
}

pub(super) fn deserialize_default_u64<'de, D>(deserializer: D) -> Result<u64, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(deserialize_optional_u64(deserializer)?.unwrap_or_default())
}

pub(super) fn deserialize_optional_u64<'de, D>(deserializer: D) -> Result<Option<u64>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Number(value)) => value.as_u64(),
        Some(Value::String(value)) => value.parse::<u64>().ok(),
        Some(Value::Bool(value)) => Some(u64::from(value)),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

pub(super) fn deserialize_default_u32<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(deserialize_optional_u32(deserializer)?.unwrap_or_default())
}

pub(super) fn deserialize_optional_u32<'de, D>(deserializer: D) -> Result<Option<u32>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Number(value)) => value.as_u64().and_then(|value| u32::try_from(value).ok()),
        Some(Value::String(value)) => value.parse::<u32>().ok(),
        Some(Value::Bool(value)) => Some(u32::from(value)),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

pub(super) fn deserialize_optional_i32<'de, D>(deserializer: D) -> Result<Option<i32>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Number(value)) => value.as_i64().and_then(|value| i32::try_from(value).ok()),
        Some(Value::String(value)) => value.parse::<i32>().ok(),
        Some(Value::Bool(value)) => Some(i32::from(value)),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

pub(super) fn deserialize_optional_i64<'de, D>(deserializer: D) -> Result<Option<i64>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Number(value)) => value.as_i64(),
        Some(Value::String(value)) => value.parse::<i64>().ok(),
        Some(Value::Bool(value)) => Some(i64::from(value)),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

pub(super) fn deserialize_default_i32<'de, D>(deserializer: D) -> Result<i32, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(deserialize_optional_i32(deserializer)?.unwrap_or_default())
}

pub(super) fn deserialize_default_bool<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => false,
        Some(Value::Bool(value)) => value,
        Some(Value::Number(value)) => value.as_i64().is_some_and(|value| value != 0),
        Some(Value::String(value)) => matches!(value.as_str(), "true" | "1"),
        Some(Value::Array(_)) | Some(Value::Object(_)) => false,
    })
}

pub(super) fn deserialize_optional_bool<'de, D>(deserializer: D) -> Result<Option<bool>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => None,
        Some(Value::Bool(value)) => Some(value),
        Some(Value::Number(value)) => value.as_i64().map(|value| value != 0),
        Some(Value::String(value)) => Some(matches!(value.as_str(), "true" | "1")),
        Some(Value::Array(_)) | Some(Value::Object(_)) => None,
    })
}

pub(super) fn deserialize_default_true_bool<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => true,
        Some(Value::Bool(value)) => value,
        Some(Value::Number(value)) => value.as_i64().is_some_and(|value| value != 0),
        Some(Value::String(value)) => matches!(value.as_str(), "true" | "1"),
        Some(Value::Array(_)) | Some(Value::Object(_)) => true,
    })
}

pub(super) fn deserialize_presence_bool<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    Ok(match value {
        None | Some(Value::Null) => false,
        Some(Value::Bool(value)) => value,
        Some(Value::Number(value)) => value.as_i64().is_some_and(|value| value != 0),
        Some(Value::String(value)) => !value.is_empty() && !matches!(value.as_str(), "false" | "0"),
        Some(Value::Array(value)) => !value.is_empty(),
        Some(Value::Object(value)) => !value.is_empty(),
    })
}

pub(super) fn deserialize_topic_tags<'de, D>(deserializer: D) -> Result<Vec<TopicTag>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    let Value::Array(values) = value.unwrap_or(Value::Array(Vec::new())) else {
        return Ok(Vec::new());
    };

    Ok(values
        .into_iter()
        .filter_map(|value| match value {
            Value::Null => None,
            Value::String(value) => Some(TopicTag {
                id: None,
                name: value,
                slug: None,
            }),
            Value::Number(value) => Some(TopicTag {
                id: None,
                name: value.to_string(),
                slug: None,
            }),
            Value::Bool(value) => Some(TopicTag {
                id: None,
                name: value.to_string(),
                slug: None,
            }),
            Value::Object(mut value) => {
                let id = value.remove("id").and_then(|value| match value {
                    Value::Number(value) => value.as_u64(),
                    Value::String(value) => value.parse::<u64>().ok(),
                    _ => None,
                });
                let slug = value
                    .remove("slug")
                    .and_then(|value| value.as_str().map(ToOwned::to_owned));
                let name = value
                    .remove("name")
                    .and_then(|value| value.as_str().map(ToOwned::to_owned))
                    .or_else(|| slug.clone())?;

                Some(TopicTag { id, name, slug })
            }
            Value::Array(_) => None,
        })
        .collect())
}
