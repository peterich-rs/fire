use std::time::{SystemTime, UNIX_EPOCH};

use fire_models::{
    Draft, DraftData, DraftListResponse, PrivateMessageCreateRequest, ResolvedUploadUrl,
    TopicCreateRequest, UploadResult,
};
use http::{Method, StatusCode};
use openwire::RequestBody;
use serde_json::{json, Value};
use tracing::{info, warn};
use url::form_urlencoded::byte_serialize;

use super::{messagebus::upload_client_id, network::expect_success, FireCore};
use crate::{
    creation_payloads::{
        parse_draft_detail_response_value, parse_draft_list_response_value,
        parse_resolved_upload_urls_value, parse_upload_result_value,
    },
    error::FireCoreError,
    json_helpers::{integer_u32, integer_u64, invalid_json},
};

include!("drafts.rs");
include!("uploads.rs");
include!("topics.rs");
include!("private_messages.rs");
fn parse_create_topic_response(value: Value) -> Result<u64, FireCoreError> {
    let Value::Object(object) = value else {
        return Err(FireCoreError::ResponseDeserialize {
            operation: "create topic",
            source: invalid_json("create topic response root was not an object"),
        });
    };

    if object
        .get("action")
        .and_then(Value::as_str)
        .is_some_and(|action| action == "enqueued")
    {
        return Err(FireCoreError::PostEnqueued {
            pending_count: integer_u32(object.get("pending_count")).unwrap_or(0),
        });
    }

    if let Some(topic_id) = object
        .get("post")
        .and_then(Value::as_object)
        .and_then(|post| integer_u64(post.get("topic_id")))
    {
        return Ok(topic_id);
    }

    if let Some(topic_id) = integer_u64(object.get("topic_id")) {
        return Ok(topic_id);
    }

    if let Some(error) = response_error("create topic", &object) {
        return Err(error);
    }

    Err(FireCoreError::ResponseDeserialize {
        operation: "create topic",
        source: invalid_json("create topic response did not contain a topic_id"),
    })
}

fn response_error(
    operation: &'static str,
    object: &serde_json::Map<String, Value>,
) -> Option<FireCoreError> {
    if !object
        .get("success")
        .is_some_and(|value| matches!(value, Value::Bool(false)))
    {
        return None;
    }

    let body = match object.get("errors") {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|item| item.as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        Some(Value::String(value)) => value.clone(),
        Some(value) => value.to_string(),
        None => String::new(),
    };

    Some(FireCoreError::HttpStatus {
        operation,
        status: StatusCode::OK.as_u16(),
        body,
    })
}

fn multipart_boundary() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_nanos())
        .unwrap_or(0);
    format!("fire-boundary-{nanos}")
}

fn multipart_upload_body(
    boundary: &str,
    file_name: &str,
    mime_type: &str,
    bytes: &[u8],
) -> Vec<u8> {
    let sanitized_file_name = file_name.replace(['"', '\r', '\n'], "_");
    let mut body = Vec::new();
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Disposition: form-data; name=\"upload_type\"\r\n\r\n");
    body.extend_from_slice(b"composer\r\n");
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Disposition: form-data; name=\"synchronous\"\r\n\r\n");
    body.extend_from_slice(b"true\r\n");
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!(
            "Content-Disposition: form-data; name=\"file\"; filename=\"{sanitized_file_name}\"\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(format!("Content-Type: {mime_type}\r\n\r\n").as_bytes());
    body.extend_from_slice(bytes);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    body
}

fn encode_path_segment(value: &str) -> String {
    byte_serialize(value.as_bytes()).collect()
}
