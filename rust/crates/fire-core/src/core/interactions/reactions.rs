use fire_models::{PostReactionUpdate, ReactionUsersGroup};
use http::{Method, Response};
use serde_json::Value;
use tracing::{info, warn};

use super::super::{network::expect_success, FireCore};
use super::parse::{
    encode_path_segment, parse_optional_post_reaction_update, parse_toggle_reaction_response,
};
use crate::{error::FireCoreError, topic_payloads::parse_reaction_users_groups_value};

impl FireCore {
    pub async fn like_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdate>, FireCoreError> {
        info!(post_id, "liking post");

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
        let update = self
            .read_optional_post_reaction_update("like post", trace_id, response)
            .await?;
        info!(
            post_id,
            has_update = update.is_some(),
            "post liked successfully"
        );
        Ok(update)
    }

    pub async fn unlike_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdate>, FireCoreError> {
        info!(post_id, "unliking post");

        let path = format!("/post_actions/{post_id}?post_action_type_id=2");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unlike post", || {
                self.build_api_request("unlike post", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "unlike post", trace_id, response).await?;
        let update = self
            .read_optional_post_reaction_update("unlike post", trace_id, response)
            .await?;
        info!(
            post_id,
            has_update = update.is_some(),
            "post unliked successfully"
        );
        Ok(update)
    }

    pub async fn toggle_post_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<PostReactionUpdate, FireCoreError> {
        info!(post_id, reaction_id = %reaction_id, "toggling post reaction");

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
        let result = parse_toggle_reaction_response(value);
        match &result {
            Ok(update) => info!(
                post_id,
                reactions_count = update.reactions.len(),
                has_current = update.current_user_reaction.is_some(),
                "post reaction toggled successfully"
            ),
            Err(e) => warn!(
                post_id,
                error = %e,
                "post reaction toggle failed during response parsing"
            ),
        }
        result
    }

    pub async fn fetch_reaction_users(
        &self,
        post_id: u64,
    ) -> Result<Vec<ReactionUsersGroup>, FireCoreError> {
        info!(post_id, "fetching reaction users");
        let path = format!("/discourse-reactions/posts/{post_id}/reactions-users.json");
        let traced = self.build_json_get_request("fetch reaction users", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch reaction users", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch reaction users", trace_id, response)
            .await?;
        let groups = parse_reaction_users_groups_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch reaction users",
                source,
            }
        })?;
        info!(
            post_id,
            group_count = groups.len(),
            "reaction users fetched successfully"
        );
        Ok(groups)
    }

    async fn read_optional_post_reaction_update(
        &self,
        operation: &'static str,
        trace_id: u64,
        response: Response<openwire::ResponseBody>,
    ) -> Result<Option<PostReactionUpdate>, FireCoreError> {
        let body = self.read_response_text(trace_id, response).await?;
        let trimmed = body.trim();
        if trimmed.is_empty() {
            return Ok(None);
        }

        let value: Value = match serde_json::from_str(trimmed) {
            Ok(value) => value,
            Err(error) => {
                warn!(
                    operation,
                    trace_id,
                    error = %error,
                    body_prefix = %trimmed.chars().take(200).collect::<String>(),
                    "post action response did not contain parseable JSON"
                );
                return Ok(None);
            }
        };

        parse_optional_post_reaction_update(operation, value)
    }
}
