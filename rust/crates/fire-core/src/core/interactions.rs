use std::io;

use fire_models::{PostReactionUpdate, TopicPost, TopicReplyRequest};
use http::Method;
use serde_json::Value;
use url::form_urlencoded::byte_serialize;

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    topic_payloads::{parse_post_reaction_update_value, parse_topic_post_value},
};

impl FireCore {
    pub async fn create_reply(&self, input: TopicReplyRequest) -> Result<TopicPost, FireCoreError> {
        let mut fields = vec![("topic_id", input.topic_id.to_string()), ("raw", input.raw)];
        if let Some(reply_to_post_number) = input.reply_to_post_number {
            fields.push(("reply_to_post_number", reply_to_post_number.to_string()));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create reply", || {
                self.build_form_request(
                    "create reply",
                    Method::POST,
                    "/posts.json",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "create reply", trace_id, response).await?;
        let value: Value = self
            .read_response_json("create reply", trace_id, response)
            .await?;
        parse_create_reply_response(value)
    }

    pub async fn like_post(&self, post_id: u64) -> Result<(), FireCoreError> {
        let fields = vec![
            ("id", post_id.to_string()),
            ("post_action_type_id", "2".to_string()),
        ];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("like post", || {
                self.build_form_request(
                    "like post",
                    Method::POST,
                    "/post_actions",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "like post", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn unlike_post(&self, post_id: u64) -> Result<(), FireCoreError> {
        let path = format!("/post_actions/{post_id}?post_action_type_id=2");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unlike post", || {
                self.build_api_request("unlike post", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "unlike post", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn toggle_post_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<PostReactionUpdate, FireCoreError> {
        let reaction_id = encode_path_segment(&reaction_id);
        let path = format!(
            "/discourse-reactions/posts/{post_id}/custom-reactions/{reaction_id}/toggle.json"
        );
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("toggle post reaction", || {
                self.build_api_request("toggle post reaction", Method::PUT, &path, true)
            })
            .await?;
        let response = expect_success(self, "toggle post reaction", trace_id, response).await?;
        let value: Value = self
            .read_response_json("toggle post reaction", trace_id, response)
            .await?;
        parse_toggle_reaction_response(value)
    }
}

fn encode_path_segment(value: &str) -> String {
    byte_serialize(value.as_bytes()).collect()
}

fn parse_create_reply_response(value: Value) -> Result<TopicPost, FireCoreError> {
    let Value::Object(mut object) = value else {
        return Err(invalid_response(
            "create reply",
            "response root was not a JSON object",
        ));
    };

    if object
        .get("action")
        .and_then(Value::as_str)
        .is_some_and(|action| action == "enqueued")
    {
        return Err(FireCoreError::PostEnqueued {
            pending_count: pending_count_from(object.get("pending_count")),
        });
    }

    if let Some(post_value) = object.remove("post") {
        return parse_topic_post_value(post_value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "create reply",
                source,
            }
        });
    }

    if object.contains_key("id")
        || object.contains_key("post_number")
        || object.contains_key("cooked")
    {
        return parse_topic_post_value(Value::Object(object)).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "create reply",
                source,
            }
        });
    }

    Err(invalid_response(
        "create reply",
        "response object did not contain a post payload",
    ))
}

fn parse_toggle_reaction_response(value: Value) -> Result<PostReactionUpdate, FireCoreError> {
    let Value::Object(object) = &value else {
        return Err(invalid_response(
            "toggle post reaction",
            "response root was not a JSON object",
        ));
    };

    if !object.contains_key("reactions") && !object.contains_key("current_user_reaction") {
        return Err(invalid_response(
            "toggle post reaction",
            "response object did not contain reaction fields",
        ));
    }

    parse_post_reaction_update_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
        operation: "toggle post reaction",
        source,
    })
}

fn pending_count_from(value: Option<&Value>) -> u32 {
    match value {
        Some(Value::Number(value)) => value
            .as_u64()
            .and_then(|value| u32::try_from(value).ok())
            .unwrap_or_default(),
        Some(Value::String(value)) => value.parse::<u32>().unwrap_or_default(),
        Some(Value::Bool(value)) => u32::from(*value),
        _ => 0,
    }
}

fn invalid_response(operation: &'static str, details: &'static str) -> FireCoreError {
    FireCoreError::ResponseDeserialize {
        operation,
        source: serde_json::Error::io(io::Error::new(io::ErrorKind::InvalidData, details)),
    }
}
