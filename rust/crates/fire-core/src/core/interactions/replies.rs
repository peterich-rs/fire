use fire_models::{TopicPost, TopicReplyRequest};
use serde_json::Value;
use tracing::{info, warn};

use super::super::{network::expect_success, FireCore};
use super::parse::parse_create_reply_response;
use crate::error::FireCoreError;
use http::Method;

impl FireCore {
    pub async fn create_reply(&self, input: TopicReplyRequest) -> Result<TopicPost, FireCoreError> {
        info!(
            topic_id = input.topic_id,
            reply_to = ?input.reply_to_post_number,
            raw_len = input.raw.len(),
            "creating reply"
        );

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
        let result = parse_create_reply_response(value, self.base_url());
        match &result {
            Ok(post) => info!(
                topic_id = input.topic_id,
                post_id = post.id,
                post_number = post.post_number,
                "reply created successfully"
            ),
            Err(e) => warn!(
                topic_id = input.topic_id,
                error = %e,
                "reply creation failed during response parsing"
            ),
        }
        result
    }
}
