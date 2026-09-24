use fire_models::TopicPostBoost;
use serde_json::Value;
use tracing::{info, warn};

use super::super::{network::expect_success, FireCore};
use super::parse::parse_create_boost_response;
use crate::error::FireCoreError;
use http::Method;

impl FireCore {
    pub async fn create_boost(
        &self,
        post_id: u64,
        raw: String,
    ) -> Result<TopicPostBoost, FireCoreError> {
        info!(post_id, raw_len = raw.len(), "creating boost");

        let path = format!("/discourse-boosts/posts/{post_id}/boosts");
        let fields = vec![("raw", raw)];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create boost", || {
                self.build_form_request("create boost", Method::POST, &path, fields.clone(), true)
            })
            .await?;
        let response = expect_success(self, "create boost", trace_id, response).await?;
        let value: Value = self
            .read_response_json("create boost", trace_id, response)
            .await?;
        let result = parse_create_boost_response(value);
        match &result {
            Ok(boost) => info!(post_id, boost_id = boost.id, "boost created successfully"),
            Err(error) => warn!(post_id, error = %error, "boost creation failed"),
        }
        result
    }

    pub async fn delete_boost(&self, boost_id: u64) -> Result<(), FireCoreError> {
        info!(boost_id, "deleting boost");

        let path = format!("/discourse-boosts/boosts/{boost_id}");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("delete boost", || {
                self.build_api_request("delete boost", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "delete boost", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        info!(boost_id, "boost deleted successfully");
        Ok(())
    }
}
