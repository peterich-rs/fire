use std::time::{SystemTime, UNIX_EPOCH};

use fire_models::{
    Draft, DraftData, DraftListResponse, ResolvedUploadUrl, TopicCreateRequest, UploadResult,
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

impl FireCore {
    pub async fn fetch_drafts(
        &self,
        offset: Option<u32>,
        limit: Option<u32>,
    ) -> Result<DraftListResponse, FireCoreError> {
        info!(offset = ?offset, limit = ?limit, "fetching drafts");

        let mut params = Vec::new();
        if let Some(offset) = offset {
            params.push(("offset", offset.to_string()));
        }
        if let Some(limit) = limit.filter(|value| *value > 0) {
            params.push(("limit", limit.to_string()));
        }

        let traced = self.build_json_get_request("fetch drafts", "/drafts.json", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch drafts", trace_id, response).await?;
        let raw: Value = self.read_response_json("fetch drafts", trace_id, response).await?;
        parse_draft_list_response_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "fetch drafts",
            source,
        })
    }

    pub async fn fetch_draft(&self, draft_key: &str) -> Result<Option<Draft>, FireCoreError> {
        info!(draft_key, "fetching draft");

        let path = format!("/drafts/{}.json", encode_path_segment(draft_key));
        let traced = self.build_json_get_request("fetch draft", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        if response.status() == StatusCode::NOT_FOUND {
            let _ = self.read_response_text(trace_id, response).await?;
            return Ok(None);
        }

        let response = expect_success(self, "fetch draft", trace_id, response).await?;
        let raw: Value = self.read_response_json("fetch draft", trace_id, response).await?;
        parse_draft_detail_response_value(raw, draft_key).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch draft",
                source,
            }
        })
    }

    pub async fn save_draft(
        &self,
        draft_key: &str,
        data: DraftData,
        sequence: u32,
    ) -> Result<u32, FireCoreError> {
        info!(
            draft_key,
            sequence,
            has_content = data.has_content(),
            "saving draft"
        );

        let payload = serde_json::to_string(&data)
            .map_err(FireCoreError::DiagnosticsSerialize)?;
        let fields = vec![
            ("draft_key", draft_key.to_string()),
            ("data", payload),
            ("sequence", sequence.to_string()),
        ];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("save draft", || {
                self.build_form_request("save draft", Method::POST, "/drafts.json", fields.clone(), true)
            })
            .await?;
        if response.status() == StatusCode::CONFLICT {
            let raw: Value = self.read_response_json("save draft", trace_id, response).await?;
            return Ok(
                integer_u32(raw.as_object().and_then(|object| object.get("draft_sequence")))
                    .unwrap_or(sequence),
            );
        }

        let response = expect_success(self, "save draft", trace_id, response).await?;
        let raw: Value = self.read_response_json("save draft", trace_id, response).await?;
        Ok(integer_u32(raw.as_object().and_then(|object| object.get("draft_sequence")))
            .unwrap_or(sequence.saturating_add(1)))
    }

    pub async fn delete_draft(
        &self,
        draft_key: &str,
        sequence: Option<u32>,
    ) -> Result<(), FireCoreError> {
        info!(draft_key, sequence = ?sequence, "deleting draft");

        let path = if let Some(sequence) = sequence {
            format!("/drafts/{}.json?sequence={sequence}", encode_path_segment(draft_key))
        } else {
            format!("/drafts/{}.json", encode_path_segment(draft_key))
        };
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("delete draft", || {
                self.build_api_request("delete draft", Method::DELETE, &path, true)
            })
            .await?;
        if response.status() == StatusCode::NOT_FOUND {
            let _ = self.read_response_text(trace_id, response).await?;
            return Ok(());
        }

        let response = expect_success(self, "delete draft", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn lookup_upload_urls(
        &self,
        short_urls: Vec<String>,
    ) -> Result<Vec<ResolvedUploadUrl>, FireCoreError> {
        if short_urls.is_empty() {
            return Ok(Vec::new());
        }

        info!(short_urls_count = short_urls.len(), "looking up upload urls");

        let body = json!({ "short_urls": short_urls }).to_string();
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("lookup upload urls", || {
                self.build_api_request_with_body(
                    "lookup upload urls",
                    Method::POST,
                    "/uploads/lookup-urls",
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.clone()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "lookup upload urls", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("lookup upload urls", trace_id, response)
            .await?;
        parse_resolved_upload_urls_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "lookup upload urls",
            source,
        })
    }

    pub async fn upload_image(
        &self,
        file_name: &str,
        mime_type: Option<&str>,
        bytes: Vec<u8>,
    ) -> Result<UploadResult, FireCoreError> {
        info!(
            file_name,
            has_mime_type = mime_type.is_some(),
            bytes_len = bytes.len(),
            "uploading composer image"
        );

        let client_id = upload_client_id(&self.message_bus);
        let boundary = multipart_boundary();
        let content_type = format!("multipart/form-data; boundary={boundary}");
        let path = format!("/uploads.json?client_id={client_id}");
        let request_body = multipart_upload_body(
            &boundary,
            file_name,
            mime_type.unwrap_or("application/octet-stream"),
            &bytes,
        );

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("upload image", || {
                self.build_api_request_with_body(
                    "upload image",
                    Method::POST,
                    &path,
                    Some(&content_type),
                    RequestBody::from(request_body.clone()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "upload image", trace_id, response).await?;
        let raw: Value = self.read_response_json("upload image", trace_id, response).await?;
        parse_upload_result_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "upload image",
            source,
        })
    }

    pub async fn create_topic(&self, input: TopicCreateRequest) -> Result<u64, FireCoreError> {
        info!(
            category_id = input.category_id,
            tags_count = input.tags.len(),
            title_len = input.title.len(),
            raw_len = input.raw.len(),
            "creating topic"
        );

        let mut fields = vec![
            ("title", input.title),
            ("raw", input.raw),
            ("category", input.category_id.to_string()),
            ("archetype", "regular".to_string()),
        ];
        for tag in input.tags.into_iter().filter(|value| !value.trim().is_empty()) {
            fields.push(("tags[]", tag));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create topic", || {
                self.build_form_request(
                    "create topic",
                    Method::POST,
                    "/posts.json",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "create topic", trace_id, response).await?;
        let raw: Value = self.read_response_json("create topic", trace_id, response).await?;
        let result = parse_create_topic_response(raw);
        match &result {
            Ok(topic_id) => info!(topic_id, "topic created successfully"),
            Err(error) => warn!(error = %error, "topic creation failed during response parsing"),
        }
        result
    }
}

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
    let sanitized_file_name = file_name
        .replace('"', "_")
        .replace('\r', "_")
        .replace('\n', "_");
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
