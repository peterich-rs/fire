use fire_models::{UserAction, UserProfile, UserSummaryResponse};
use serde_json::Value;
use tracing::info;

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    user_payloads::{parse_user_actions_value, parse_user_profile_value, parse_user_summary_value},
};

impl FireCore {
    pub async fn fetch_user_profile(
        &self,
        username: &str,
    ) -> Result<UserProfile, FireCoreError> {
        info!(username, "fetching user profile");
        let path = format!("/u/{}.json", username);
        let traced = self.build_json_get_request("fetch user profile", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response =
            expect_success(self, "fetch user profile", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch user profile", trace_id, response)
            .await?;
        let profile = parse_user_profile_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user profile",
                source,
            }
        })?;
        info!(username, user_id = profile.id, "user profile fetched successfully");
        Ok(profile)
    }

    pub async fn fetch_user_summary(
        &self,
        username: &str,
    ) -> Result<UserSummaryResponse, FireCoreError> {
        info!(username, "fetching user summary");
        let path = format!("/u/{}/summary.json", username);
        let traced = self.build_json_get_request("fetch user summary", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response =
            expect_success(self, "fetch user summary", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch user summary", trace_id, response)
            .await?;
        let summary = parse_user_summary_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user summary",
                source,
            }
        })?;
        info!(
            username,
            badge_count = summary.badges.len(),
            top_topic_count = summary.top_topics.len(),
            "user summary fetched successfully"
        );
        Ok(summary)
    }

    pub async fn fetch_user_actions(
        &self,
        username: &str,
        offset: Option<u32>,
        filter: Option<&str>,
    ) -> Result<Vec<UserAction>, FireCoreError> {
        info!(username, ?offset, ?filter, "fetching user actions");
        let mut params: Vec<(&str, String)> = vec![("username", username.to_string())];
        if let Some(offset) = offset {
            params.push(("offset", offset.to_string()));
        }
        if let Some(filter) = filter {
            params.push(("filter", filter.to_string()));
        }
        let traced = self.build_json_get_request(
            "fetch user actions",
            "/user_actions.json",
            params,
            &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response =
            expect_success(self, "fetch user actions", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch user actions", trace_id, response)
            .await?;
        let actions = parse_user_actions_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user actions",
                source,
            }
        })?;
        info!(username, action_count = actions.len(), "user actions fetched successfully");
        Ok(actions)
    }
}
