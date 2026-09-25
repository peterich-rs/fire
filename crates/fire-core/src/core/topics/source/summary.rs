use fire_models::TopicAiSummary;
use http::StatusCode;
use serde_json::Value;
use tracing::info;

use super::super::super::{network::expect_success, FireCore};
use super::FETCH_TOPIC_AI_SUMMARY_OPERATION;
use crate::{error::FireCoreError, topic_payloads::parse_topic_ai_summary_value};

impl FireCore {
    pub async fn fetch_topic_ai_summary(
        &self,
        topic_id: u64,
        skip_age_check: bool,
    ) -> Result<Option<TopicAiSummary>, FireCoreError> {
        info!(topic_id, skip_age_check, "fetching topic AI summary");

        let path = format!("/discourse-ai/summarization/t/{topic_id}");
        let mut params = Vec::new();
        if skip_age_check {
            params.push(("skip_age_check", "true".to_string()));
        }

        let traced =
            self.build_json_get_request(FETCH_TOPIC_AI_SUMMARY_OPERATION, &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = match expect_success(
            self,
            FETCH_TOPIC_AI_SUMMARY_OPERATION,
            trace_id,
            response,
        )
        .await
        {
            Ok(response) => response,
            Err(FireCoreError::HttpStatus {
                status,
                body: _,
                operation: FETCH_TOPIC_AI_SUMMARY_OPERATION,
            }) if status == StatusCode::NOT_FOUND.as_u16()
                || status == StatusCode::FORBIDDEN.as_u16() =>
            {
                info!(topic_id, status, "topic AI summary is unavailable");
                return Ok(None);
            }
            Err(error) => return Err(error),
        };
        let value: Value = self
            .read_response_json(FETCH_TOPIC_AI_SUMMARY_OPERATION, trace_id, response)
            .await?;
        let summary = parse_topic_ai_summary_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: FETCH_TOPIC_AI_SUMMARY_OPERATION,
                source,
            }
        })?;
        info!(
            topic_id,
            has_summary = summary.is_some(),
            "topic AI summary fetched successfully"
        );
        Ok(summary)
    }
}
