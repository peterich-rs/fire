use fire_models::Poll;
use serde_json::Value;
use tracing::info;

use super::super::{network::expect_success, FireCore};
use crate::{error::FireCoreError, topic_payloads::parse_poll_response_value};
use http::Method;

impl FireCore {
    pub async fn vote_poll(
        &self,
        post_id: u64,
        poll_name: &str,
        options: Vec<String>,
    ) -> Result<Poll, FireCoreError> {
        info!(
            post_id,
            poll_name,
            options_count = options.len(),
            "voting in poll"
        );
        let mut fields = vec![
            ("post_id", post_id.to_string()),
            ("poll_name", poll_name.to_string()),
        ];
        for option in options.into_iter().filter(|value| !value.trim().is_empty()) {
            fields.push(("options[]", option));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("vote poll", || {
                self.build_form_request(
                    "vote poll",
                    Method::PUT,
                    "/polls/vote",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "vote poll", trace_id, response).await?;
        let value: Value = self
            .read_response_json("vote poll", trace_id, response)
            .await?;
        parse_poll_response_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "vote poll",
            source,
        })
    }

    pub async fn unvote_poll(&self, post_id: u64, poll_name: &str) -> Result<Poll, FireCoreError> {
        info!(post_id, poll_name, "removing poll vote");
        let fields = vec![
            ("post_id", post_id.to_string()),
            ("poll_name", poll_name.to_string()),
        ];

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unvote poll", || {
                self.build_form_request(
                    "unvote poll",
                    Method::DELETE,
                    "/polls/vote",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "unvote poll", trace_id, response).await?;
        let value: Value = self
            .read_response_json("unvote poll", trace_id, response)
            .await?;
        parse_poll_response_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "unvote poll",
            source,
        })
    }
}
