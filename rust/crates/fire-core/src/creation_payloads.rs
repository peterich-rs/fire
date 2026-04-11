use fire_models::{Draft, DraftData, DraftListResponse, ResolvedUploadUrl, UploadResult};
use serde_json::Value;
use tracing::warn;

use crate::json_helpers::{
    boolean, integer_u32, integer_u64, invalid_json, parse_array_items_lossy, scalar_string,
};

pub(crate) fn parse_draft_list_response_value(
    value: Value,
) -> Result<DraftListResponse, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("draft list response root was not an object"));
    };

    let drafts = object
        .get("drafts")
        .and_then(Value::as_array)
        .map(|items| {
            parse_array_items_lossy(items, "draft list item", |item| {
                parse_draft_item_value(item.clone())
            })
        })
        .unwrap_or_default();

    Ok(DraftListResponse {
        drafts,
        has_more: boolean(object.get("has_more")),
    })
}

pub(crate) fn parse_draft_detail_response_value(
    value: Value,
    draft_key: &str,
) -> Result<Option<Draft>, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("draft detail response root was not an object"));
    };

    let Some(draft_value) = object.get("draft") else {
        return Ok(None);
    };
    if draft_value.is_null() {
        return Ok(None);
    }

    let data = parse_draft_data_value(draft_value)?;
    Ok(Some(Draft {
        draft_key: draft_key.trim().to_string(),
        data,
        sequence: integer_u32(object.get("draft_sequence"))
            .or_else(|| integer_u32(object.get("sequence")))
            .unwrap_or(0),
        title: scalar_string(object.get("title")),
        excerpt: scalar_string(object.get("excerpt")),
        updated_at: scalar_string(object.get("updated_at"))
            .or_else(|| scalar_string(object.get("created_at"))),
        username: scalar_string(object.get("username")),
        avatar_template: scalar_string(object.get("avatar_template")),
        topic_id: integer_u64(object.get("topic_id"))
            .or_else(|| topic_id_from_draft_key(draft_key)),
    }))
}

pub(crate) fn parse_upload_result_value(value: Value) -> Result<UploadResult, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json(
            "upload result response root was not an object",
        ));
    };

    let short_url = scalar_string(object.get("short_url"))
        .or_else(|| scalar_string(object.get("url")))
        .ok_or_else(|| invalid_json("upload result did not contain a short_url or url"))?;

    Ok(UploadResult {
        short_url,
        url: scalar_string(object.get("url")),
        original_filename: scalar_string(object.get("original_filename")),
        width: integer_u32(object.get("width")),
        height: integer_u32(object.get("height")),
        thumbnail_width: integer_u32(object.get("thumbnail_width")),
        thumbnail_height: integer_u32(object.get("thumbnail_height")),
    })
}

pub(crate) fn parse_resolved_upload_urls_value(
    value: Value,
) -> Result<Vec<ResolvedUploadUrl>, serde_json::Error> {
    let Value::Array(items) = value else {
        return Err(invalid_json(
            "resolved upload urls response root was not an array",
        ));
    };

    Ok(parse_array_items_lossy(
        &items,
        "resolved upload url item",
        |item| parse_resolved_upload_url_value(item.clone()),
    ))
}

fn parse_draft_item_value(value: Value) -> Result<Draft, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("draft list item was not an object"));
    };

    let draft_key = scalar_string(object.get("draft_key")).unwrap_or_default();
    let data = object
        .get("data")
        .map(parse_draft_data_value)
        .transpose()?
        .unwrap_or_default();

    Ok(Draft {
        draft_key: draft_key.clone(),
        data,
        sequence: integer_u32(object.get("draft_sequence"))
            .or_else(|| integer_u32(object.get("sequence")))
            .unwrap_or(0),
        title: scalar_string(object.get("title")),
        excerpt: scalar_string(object.get("excerpt")),
        updated_at: scalar_string(object.get("updated_at"))
            .or_else(|| scalar_string(object.get("created_at"))),
        username: scalar_string(object.get("username")),
        avatar_template: scalar_string(object.get("avatar_template")),
        topic_id: integer_u64(object.get("topic_id"))
            .or_else(|| topic_id_from_draft_key(&draft_key)),
    })
}

fn parse_draft_data_value(value: &Value) -> Result<DraftData, serde_json::Error> {
    match value {
        Value::String(raw) => {
            if raw.trim().is_empty() {
                return Ok(DraftData::default());
            }
            match serde_json::from_str::<Value>(raw) {
                Ok(value) => parse_draft_data_value(&value),
                Err(error) => {
                    warn!(
                        error = %error,
                        "failed to decode draft data JSON string; defaulting to empty draft data"
                    );
                    Ok(DraftData::default())
                }
            }
        }
        Value::Object(object) => Ok(parse_draft_data_object(object)),
        Value::Null => Ok(DraftData::default()),
        _ => Ok(DraftData::default()),
    }
}

fn parse_resolved_upload_url_value(value: Value) -> Result<ResolvedUploadUrl, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("resolved upload url item was not an object"));
    };

    Ok(ResolvedUploadUrl {
        short_url: scalar_string(object.get("short_url")).unwrap_or_default(),
        short_path: scalar_string(object.get("short_path")),
        url: scalar_string(object.get("url")),
    })
}

fn topic_id_from_draft_key(draft_key: &str) -> Option<u64> {
    let trimmed = draft_key.trim();
    let topic_key = trimmed.strip_prefix("topic_")?;
    let topic_id = topic_key.split("_post_").next()?;
    topic_id.parse::<u64>().ok()
}

fn parse_draft_data_object(object: &serde_json::Map<String, Value>) -> DraftData {
    DraftData {
        reply: scalar_string(object.get("reply")),
        title: scalar_string(object.get("title")),
        category_id: integer_u64(object.get("categoryId"))
            .or_else(|| integer_u64(object.get("category_id"))),
        tags: scalar_array(object.get("tags")),
        reply_to_post_number: integer_u32(object.get("replyToPostNumber"))
            .or_else(|| integer_u32(object.get("reply_to_post_number"))),
        action: scalar_string(object.get("action")),
        recipients: scalar_array(object.get("recipients")),
        archetype_id: scalar_string(object.get("archetypeId"))
            .or_else(|| scalar_string(object.get("archetype_id"))),
        composer_time: integer_u32(object.get("composerTime"))
            .or_else(|| integer_u32(object.get("composer_time"))),
        typing_time: integer_u32(object.get("typingTime"))
            .or_else(|| integer_u32(object.get("typing_time"))),
    }
}

fn scalar_array(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|item| scalar_string(Some(item)))
            .collect(),
        Some(value) => scalar_string(Some(value)).into_iter().collect(),
        None => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_draft_list_response_skips_malformed_items_and_coerces_data() {
        let value = json!({
            "drafts": [
                1,
                {
                    "draft_key": "topic_123_post_2",
                    "data": {
                        "reply": "hello",
                        "replyToPostNumber": "2",
                        "categoryId": "3",
                        "tags": ["rust", 1]
                    },
                    "draft_sequence": "4"
                }
            ],
            "has_more": "1"
        });

        let drafts = parse_draft_list_response_value(value).unwrap();
        assert_eq!(drafts.drafts.len(), 1);
        assert_eq!(drafts.drafts[0].draft_key, "topic_123_post_2");
        assert_eq!(drafts.drafts[0].sequence, 4);
        assert_eq!(drafts.drafts[0].data.reply.as_deref(), Some("hello"));
        assert_eq!(drafts.drafts[0].data.reply_to_post_number, Some(2));
        assert_eq!(drafts.drafts[0].data.category_id, Some(3));
        assert_eq!(drafts.drafts[0].data.tags, vec!["rust", "1"]);
        assert!(drafts.has_more);
    }

    #[test]
    fn parse_draft_detail_response_tolerates_malformed_draft_data_string() {
        let value = json!({
            "draft": "{not-json",
            "draft_sequence": 6
        });

        let draft = parse_draft_detail_response_value(value, "topic_123_post_2")
            .unwrap()
            .expect("draft");
        assert_eq!(draft.sequence, 6);
        assert_eq!(draft.topic_id, Some(123));
        assert_eq!(draft.data, DraftData::default());
    }

    #[test]
    fn parse_resolved_upload_urls_value_skips_malformed_items() {
        let value = json!([
            1,
            {
                "short_url": "upload://fire.png",
                "url": "/uploads/default/original/1X/fire.png"
            }
        ]);

        let urls = parse_resolved_upload_urls_value(value).unwrap();
        assert_eq!(urls.len(), 1);
        assert_eq!(urls[0].short_url, "upload://fire.png");
    }
}
