use fire_models::{VoteResponse, VotedUser};
use serde_json::Value;
use tracing::info;

use super::super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    topic_payloads::{parse_vote_response_value, parse_voted_users_value},
};
use http::Method;

impl FireCore {
    pub async fn vote_topic(&self, topic_id: u64) -> Result<VoteResponse, FireCoreError> {
        info!(topic_id, "voting topic");
        let fields = vec![("topic_id", topic_id.to_string())];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("vote topic", || {
                self.build_form_request(
                    "vote topic",
                    Method::POST,
                    "/voting/vote",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "vote topic", trace_id, response).await?;
        let value: Value = self
            .read_response_json("vote topic", trace_id, response)
            .await?;
        parse_vote_response_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "vote topic",
            source,
        })
    }

    pub async fn unvote_topic(&self, topic_id: u64) -> Result<VoteResponse, FireCoreError> {
        info!(topic_id, "removing topic vote");
        let fields = vec![("topic_id", topic_id.to_string())];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unvote topic", || {
                self.build_form_request(
                    "unvote topic",
                    Method::POST,
                    "/voting/unvote",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "unvote topic", trace_id, response).await?;
        let value: Value = self
            .read_response_json("unvote topic", trace_id, response)
            .await?;
        parse_vote_response_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "unvote topic",
            source,
        })
    }

    pub async fn fetch_topic_voters(&self, topic_id: u64) -> Result<Vec<VotedUser>, FireCoreError> {
        info!(topic_id, "fetching topic voters");
        let traced = self.build_json_get_request(
            "fetch topic voters",
            "/voting/who",
            vec![("topic_id", topic_id.to_string())],
            &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch topic voters", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch topic voters", trace_id, response)
            .await?;
        parse_voted_users_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "fetch topic voters",
            source,
        })
    }
}
