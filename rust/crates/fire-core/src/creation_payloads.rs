use fire_models::{Draft, DraftData, DraftListResponse, ResolvedUploadUrl, UploadResult};
use serde_json::Value;

use crate::json_helpers::{boolean, integer_u32, integer_u64, invalid_json, scalar_string};

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
            items.iter()
                .cloned()
                .map(parse_draft_item_value)
                .collect::<Result<Vec<_>, _>>()
        })
        .transpose()?
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
        topic_id: integer_u64(object.get("topic_id")).or_else(|| topic_id_from_draft_key(draft_key)),
    }))
}

pub(crate) fn parse_upload_result_value(value: Value) -> Result<UploadResult, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("upload result response root was not an object"));
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

    items.into_iter()
        .map(parse_resolved_upload_url_value)
        .collect::<Result<Vec<_>, _>>()
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
        topic_id: integer_u64(object.get("topic_id")).or_else(|| topic_id_from_draft_key(&draft_key)),
    })
}

fn parse_draft_data_value(value: &Value) -> Result<DraftData, serde_json::Error> {
    match value {
        Value::String(raw) => {
            if raw.trim().is_empty() {
                return Ok(DraftData::default());
            }
            serde_json::from_str::<DraftData>(raw)
        }
        Value::Object(object) => serde_json::from_value::<DraftData>(Value::Object(object.clone())),
        _ => Err(invalid_json("draft data was neither a JSON string nor an object")),
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
