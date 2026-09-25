use fire_models::ChatMessage;
use serde_json::Value;
use tracing::info;

use super::super::{network::expect_success, FireCore};
use super::ensure_chat_session;
use crate::{chat_payloads::parse_chat_channel_pins_value, error::FireCoreError};
use http::Method;

impl FireCore {
    pub async fn fetch_chat_channel_pins(
        &self,
        channel_id: u64,
    ) -> Result<Vec<ChatMessage>, FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "fetch chat channel pins",
                details: "channel_id must be > 0".into(),
            });
        }
        info!(channel_id, "fetching chat channel pins");
        let path = format!("/chat/api/channels/{channel_id}/pins");
        let traced = self.build_json_get_request("fetch chat channel pins", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch chat channel pins", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("fetch chat channel pins", trace_id, response)
            .await?;
        parse_chat_channel_pins_value(raw, channel_id).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch chat channel pins",
                source,
            }
        })
    }

    /// POST `/chat/api/channels/:id/messages/:mid/pin`
    pub async fn pin_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 || message_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "pin chat message",
                details: "channel_id and message_id must be > 0".into(),
            });
        }
        info!(channel_id, message_id, "pinning chat message");
        let path = format!("/chat/api/channels/{channel_id}/messages/{message_id}/pin");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("pin chat message", || {
                self.build_api_request("pin chat message", Method::POST, &path, true)
            })
            .await?;
        let response = expect_success(self, "pin chat message", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    /// DELETE `/chat/api/channels/:id/messages/:mid/pin`
    pub async fn unpin_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 || message_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "unpin chat message",
                details: "channel_id and message_id must be > 0".into(),
            });
        }
        info!(channel_id, message_id, "unpinning chat message");
        let path = format!("/chat/api/channels/{channel_id}/messages/{message_id}/pin");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unpin chat message", || {
                self.build_api_request("unpin chat message", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "unpin chat message", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    /// PUT `/chat/api/channels/:id/pins/read`
    pub async fn mark_chat_channel_pins_read(&self, channel_id: u64) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "mark chat channel pins read",
                details: "channel_id must be > 0".into(),
            });
        }
        let path = format!("/chat/api/channels/{channel_id}/pins/read");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("mark chat channel pins read", || {
                self.build_api_request("mark chat channel pins read", Method::PUT, &path, true)
            })
            .await?;
        let response =
            expect_success(self, "mark chat channel pins read", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
