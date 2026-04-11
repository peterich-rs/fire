use fire_models::{
    GroupedSearchResult, RequiredTagGroup, SearchPost, SearchResult, SearchTopic, SearchUser,
    TagSearchItem, TagSearchResult, UserMentionGroup, UserMentionResult, UserMentionUser,
};
use serde_json::Value;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};
use tracing::warn;

use crate::json_helpers::{
    boolean, integer_u32, integer_u64, invalid_json, object_field, parse_array_items_lossy,
    scalar_string,
};

pub(crate) fn parse_search_result_value(value: Value) -> Result<SearchResult, serde_json::Error> {
    require_object(&value, "search response root was not an object")?;

    let topics = optional_array_field(&value, "topics")
        .map(|items| parse_array_items_lossy(items, "search topic item", parse_search_topic))
        .unwrap_or_default();
    let posts = optional_array_field(&value, "posts")
        .map(|items| parse_array_items_lossy(items, "search post item", parse_search_post))
        .unwrap_or_default();
    let users = optional_array_field(&value, "users")
        .map(|items| parse_array_items_lossy(items, "search user item", parse_search_user))
        .unwrap_or_default();
    let grouped_result =
        parse_grouped_search_result(required_object_field(&value, "grouped_search_result")?)?;

    Ok(SearchResult {
        posts,
        topics,
        users,
        grouped_result,
    })
}

pub(crate) fn parse_tag_search_result_value(
    value: Value,
) -> Result<TagSearchResult, serde_json::Error> {
    require_object(&value, "tag search response root was not an object")?;

    let results = optional_array_field(&value, "results")
        .map(|items| parse_array_items_lossy(items, "tag search item", parse_tag_search_item))
        .unwrap_or_default();
    let required_tag_group = optional_object_field(&value, "required_tag_group")
        .map(parse_required_tag_group)
        .transpose()?;

    Ok(TagSearchResult {
        results,
        required_tag_group,
    })
}

pub(crate) fn parse_user_mention_result_value(
    value: Value,
) -> Result<UserMentionResult, serde_json::Error> {
    require_object(&value, "user mention response root was not an object")?;

    let users = optional_array_field(&value, "users")
        .map(|items| {
            parse_array_items_lossy(items, "user mention user item", parse_user_mention_user)
        })
        .unwrap_or_default();
    let groups = optional_array_field(&value, "groups")
        .map(|items| {
            parse_array_items_lossy(items, "user mention group item", parse_user_mention_group)
        })
        .unwrap_or_default();

    Ok(UserMentionResult { users, groups })
}

fn parse_search_topic(value: &Value) -> Result<SearchTopic, serde_json::Error> {
    require_object(value, "search topic item was not an object")?;

    Ok(SearchTopic {
        id: required_u64_field(value, "id", "search topic item did not contain a valid id")?,
        title: scalar_string(object_field(value, "title")).unwrap_or_default(),
        slug: scalar_string(object_field(value, "slug")).unwrap_or_default(),
        category_id: integer_u64(object_field(value, "category_id")),
        tags: optional_array_field(value, "tags")
            .map(|items| items.iter().filter_map(tag_name).collect())
            .unwrap_or_default(),
        posts_count: integer_u32(object_field(value, "posts_count")).unwrap_or_default(),
        views: integer_u32(object_field(value, "views")).unwrap_or_default(),
        closed: boolean(object_field(value, "closed")),
        archived: boolean(object_field(value, "archived")),
    })
}

fn parse_search_post(value: &Value) -> Result<SearchPost, serde_json::Error> {
    require_object(value, "search post item was not an object")?;

    let created_at = scalar_string(object_field(value, "created_at"));
    Ok(SearchPost {
        id: required_u64_field(value, "id", "search post item did not contain a valid id")?,
        topic_id: integer_u64(object_field(value, "topic_id")),
        username: scalar_string(object_field(value, "username")).unwrap_or_default(),
        avatar_template: scalar_string(object_field(value, "avatar_template")),
        created_timestamp_unix_ms: timestamp_unix_ms(created_at.as_deref()),
        created_at,
        like_count: integer_u32(object_field(value, "like_count")).unwrap_or_default(),
        blurb: scalar_string(object_field(value, "blurb")).unwrap_or_default(),
        post_number: integer_u32(object_field(value, "post_number"))
            .unwrap_or_default()
            .max(1),
        topic_title_headline: scalar_string(object_field(value, "topic_title_headline")),
    })
}

fn parse_search_user(value: &Value) -> Result<SearchUser, serde_json::Error> {
    require_object(value, "search user item was not an object")?;

    Ok(SearchUser {
        id: required_u64_field(value, "id", "search user item did not contain a valid id")?,
        username: scalar_string(object_field(value, "username")).unwrap_or_default(),
        name: scalar_string(object_field(value, "name")),
        avatar_template: scalar_string(object_field(value, "avatar_template")),
    })
}

fn parse_grouped_search_result(value: &Value) -> Result<GroupedSearchResult, serde_json::Error> {
    require_object(value, "grouped_search_result was not an object")?;

    Ok(GroupedSearchResult {
        term: scalar_string(object_field(value, "term")).unwrap_or_default(),
        more_posts: boolean(object_field(value, "more_posts")),
        more_users: boolean(object_field(value, "more_users")),
        more_categories: boolean(object_field(value, "more_categories")),
        more_full_page_results: boolean(object_field(value, "more_full_page_results")),
        search_log_id: integer_u64(object_field(value, "search_log_id")),
    })
}

fn parse_tag_search_item(value: &Value) -> Result<TagSearchItem, serde_json::Error> {
    require_object(value, "tag search item was not an object")?;

    let name = required_string_field(
        value,
        "name",
        "tag search item did not contain a valid name",
    )?;
    Ok(TagSearchItem {
        text: scalar_string(object_field(value, "text")).unwrap_or_else(|| name.clone()),
        count: integer_u32(object_field(value, "count")).unwrap_or_default(),
        name,
    })
}

fn parse_required_tag_group(value: &Value) -> Result<RequiredTagGroup, serde_json::Error> {
    require_object(value, "required_tag_group was not an object")?;

    Ok(RequiredTagGroup {
        name: required_string_field(
            value,
            "name",
            "required_tag_group did not contain a valid name",
        )?,
        min_count: integer_u32(object_field(value, "min_count"))
            .unwrap_or_default()
            .max(1),
    })
}

fn parse_user_mention_user(value: &Value) -> Result<UserMentionUser, serde_json::Error> {
    require_object(value, "user mention user item was not an object")?;

    Ok(UserMentionUser {
        username: required_string_field(
            value,
            "username",
            "user mention user item did not contain a valid username",
        )?,
        name: scalar_string(object_field(value, "name")),
        avatar_template: scalar_string(object_field(value, "avatar_template")),
        priority_group: integer_u32(object_field(value, "priority_group")),
    })
}

fn parse_user_mention_group(value: &Value) -> Result<UserMentionGroup, serde_json::Error> {
    require_object(value, "user mention group item was not an object")?;

    Ok(UserMentionGroup {
        name: required_string_field(
            value,
            "name",
            "user mention group item did not contain a valid name",
        )?,
        full_name: scalar_string(object_field(value, "full_name")),
        flair_url: scalar_string(object_field(value, "flair_url")),
        flair_bg_color: scalar_string(object_field(value, "flair_bg_color")),
        flair_color: scalar_string(object_field(value, "flair_color")),
        user_count: integer_u32(object_field(value, "user_count")),
    })
}

fn tag_name(value: &Value) -> Option<String> {
    match value {
        Value::String(value) if !value.is_empty() => Some(value.clone()),
        Value::Object(object) => object
            .get("name")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .or_else(|| {
                object
                    .get("slug")
                    .and_then(Value::as_str)
                    .filter(|value| !value.is_empty())
                    .map(ToOwned::to_owned)
            }),
        _ => None,
    }
}

fn require_object(value: &Value, details: impl Into<String>) -> Result<(), serde_json::Error> {
    if value.is_object() {
        Ok(())
    } else {
        Err(invalid_json(details))
    }
}

fn optional_array_field<'a>(value: &'a Value, key: &str) -> Option<&'a [Value]> {
    match object_field(value, key) {
        Some(Value::Array(items)) => Some(items.as_slice()),
        Some(_) => {
            warn!(
                key,
                "search payload field was not an array; treating as empty"
            );
            None
        }
        None => None,
    }
}

fn optional_object_field<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    match object_field(value, key) {
        Some(Value::Object(_)) => object_field(value, key),
        Some(_) => {
            warn!(
                key,
                "search payload field was not an object; treating as absent"
            );
            None
        }
        None => None,
    }
}

fn required_object_field<'a>(value: &'a Value, key: &str) -> Result<&'a Value, serde_json::Error> {
    optional_object_field(value, key).ok_or_else(|| {
        invalid_json(format!(
            "search payload did not contain required object field `{key}`"
        ))
    })
}

fn required_u64_field(
    value: &Value,
    key: &str,
    details: impl Into<String>,
) -> Result<u64, serde_json::Error> {
    integer_u64(object_field(value, key)).ok_or_else(|| invalid_json(details))
}

fn required_string_field(
    value: &Value,
    key: &str,
    details: impl Into<String>,
) -> Result<String, serde_json::Error> {
    scalar_string(object_field(value, key)).ok_or_else(|| invalid_json(details))
}

fn timestamp_unix_ms(value: Option<&str>) -> Option<u64> {
    let value = value?;
    let parsed = OffsetDateTime::parse(value, &Rfc3339).ok()?;
    u64::try_from(parsed.unix_timestamp_nanos() / 1_000_000).ok()
}
