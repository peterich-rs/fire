use tracing::info;

use super::super::{network::expect_success, FireCore};
use super::ensure_chat_session;
use crate::error::FireCoreError;
use http::Method;
use openwire::RequestBody;
use serde_json::json;

impl FireCore {
    pub async fn react_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
        emoji: String,
        react_action: String,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 || message_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "react chat message",
                details: "channel_id and message_id must be > 0".into(),
            });
        }
        let emoji = emoji.trim().to_string();
        let react_action = react_action.trim().to_string();
        if emoji.is_empty() || !matches!(react_action.as_str(), "add" | "remove") {
            return Err(FireCoreError::InvalidArgument {
                operation: "react chat message",
                details: "emoji required and react_action must be add|remove".into(),
            });
        }
        info!(channel_id, message_id, emoji = %emoji, react_action = %react_action, "reacting to chat message");
        let body = json!({
            "emoji": emoji,
            "react_action": react_action,
        });
        let path = format!("/chat/{channel_id}/react/{message_id}");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("react chat message", || {
                self.build_api_request_with_body(
                    "react chat message",
                    Method::PUT,
                    &path,
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.to_string()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "react chat message", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
