use fire_models::{PostActionType, PostFlagRequest, PostUpdateRequest, TopicPost};
use serde_json::Value;
use tracing::info;

use super::super::{network::expect_success, FireCore};
use super::parse::{parse_post_action_types_response, post_action_types_from_value};
use crate::{
    error::FireCoreError,
    parsing::parse_preloaded_payload,
    topic_payloads::{
        parse_post_reply_ids_value, parse_topic_post_list_value, parse_topic_post_value,
    },
};
use http::Method;

impl FireCore {
    pub async fn fetch_post(&self, post_id: u64) -> Result<TopicPost, FireCoreError> {
        info!(post_id, "fetching post");
        let path = format!("/posts/{post_id}.json");
        let traced = self.build_json_get_request("fetch post", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch post", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch post", trace_id, response)
            .await?;
        parse_topic_post_value(value, self.base_url()).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch post",
                source,
            }
        })
    }

    pub async fn fetch_post_replies(
        &self,
        post_id: u64,
        after: Option<u32>,
    ) -> Result<Vec<TopicPost>, FireCoreError> {
        info!(post_id, after = ?after, "fetching post replies");
        let path = format!("/posts/{post_id}/replies.json");
        let params = after
            .map(|after| vec![("after", after.to_string())])
            .unwrap_or_default();
        let traced = self.build_json_get_request("fetch post replies", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch post replies", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch post replies", trace_id, response)
            .await?;
        parse_topic_post_list_value(value, self.base_url()).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch post replies",
                source,
            }
        })
    }

    pub async fn fetch_post_reply_ids(&self, post_id: u64) -> Result<Vec<u64>, FireCoreError> {
        info!(post_id, "fetching post reply ids");
        let path = format!("/posts/{post_id}/reply-ids.json");
        let traced = self.build_json_get_request("fetch post reply ids", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch post reply ids", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch post reply ids", trace_id, response)
            .await?;
        parse_post_reply_ids_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "fetch post reply ids",
            source,
        })
    }

    pub async fn fetch_post_reply_history(
        &self,
        post_id: u64,
    ) -> Result<Vec<TopicPost>, FireCoreError> {
        info!(post_id, "fetching post reply history");
        let path = format!("/posts/{post_id}/reply-history");
        let traced = self.build_json_get_request("fetch post reply history", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch post reply history", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch post reply history", trace_id, response)
            .await?;
        parse_topic_post_list_value(value, self.base_url()).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch post reply history",
                source,
            }
        })
    }

    pub async fn update_post(&self, input: PostUpdateRequest) -> Result<TopicPost, FireCoreError> {
        info!(
            post_id = input.post_id,
            raw_len = input.raw.len(),
            has_edit_reason = input.edit_reason.is_some(),
            "updating post"
        );

        let path = format!("/posts/{}.json", input.post_id);
        let mut fields = vec![("post[raw]", input.raw)];
        if let Some(edit_reason) = input.edit_reason.filter(|value| !value.trim().is_empty()) {
            fields.push(("post[edit_reason]", edit_reason));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("update post", || {
                self.build_form_request("update post", Method::PUT, &path, fields.clone(), true)
            })
            .await?;
        let response = expect_success(self, "update post", trace_id, response).await?;
        let value: Value = self
            .read_response_json("update post", trace_id, response)
            .await?;
        parse_topic_post_value(value, self.base_url()).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "update post",
                source,
            }
        })
    }

    pub async fn delete_post(&self, post_id: u64) -> Result<(), FireCoreError> {
        info!(post_id, "deleting post");

        let path = format!("/posts/{post_id}.json");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("delete post", || {
                self.build_api_request("delete post", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "delete post", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn recover_post(&self, post_id: u64) -> Result<(), FireCoreError> {
        info!(post_id, "recovering post");

        let path = format!("/posts/{post_id}/recover.json");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("recover post", || {
                self.build_api_request("recover post", Method::PUT, &path, true)
            })
            .await?;
        let response = expect_success(self, "recover post", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn accept_solution(&self, post_id: u64) -> Result<(), FireCoreError> {
        self.update_solution_acceptance("accept solution", "/solution/accept", post_id)
            .await
    }

    pub async fn unaccept_solution(&self, post_id: u64) -> Result<(), FireCoreError> {
        self.update_solution_acceptance("unaccept solution", "/solution/unaccept", post_id)
            .await
    }

    async fn update_solution_acceptance(
        &self,
        operation: &'static str,
        path: &'static str,
        post_id: u64,
    ) -> Result<(), FireCoreError> {
        info!(post_id, operation, "updating post solution state");
        let fields = vec![("id", post_id.to_string())];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry(operation, || {
                self.build_form_request(operation, Method::POST, path, fields.clone(), true)
            })
            .await?;
        let response = expect_success(self, operation, trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn flag_post(&self, input: PostFlagRequest) -> Result<(), FireCoreError> {
        info!(
            post_id = input.post_id,
            flag_type_id = input.flag_type_id,
            has_message = input.message.is_some(),
            "flagging post"
        );

        let mut fields = vec![
            ("id", input.post_id.to_string()),
            ("post_action_type_id", input.flag_type_id.to_string()),
        ];
        if let Some(message) = input.message.filter(|value| !value.trim().is_empty()) {
            fields.push(("message", message));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("flag post", || {
                self.build_form_request(
                    "flag post",
                    Method::POST,
                    "/post_actions",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "flag post", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn fetch_post_action_types(&self) -> Result<Vec<PostActionType>, FireCoreError> {
        if let Some(types) = self.post_action_types_from_preloaded() {
            info!(
                count = types.len(),
                "using post action types from bootstrap preloaded data"
            );
            return Ok(types);
        }

        info!("fetching post action types");
        let traced = self.build_json_get_request(
            "fetch post action types",
            "/post_action_types.json",
            vec![],
            &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch post action types", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch post action types", trace_id, response)
            .await?;
        parse_post_action_types_response(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch post action types",
                source,
            }
        })
    }

    fn post_action_types_from_preloaded(&self) -> Option<Vec<PostActionType>> {
        let snapshot = self.snapshot();
        let preloaded_json = snapshot.bootstrap.preloaded_json.as_deref()?;
        let preloaded = parse_preloaded_payload(preloaded_json)?;
        let types = post_action_types_from_value(&preloaded)?;
        (!types.is_empty()).then_some(types)
    }
}
