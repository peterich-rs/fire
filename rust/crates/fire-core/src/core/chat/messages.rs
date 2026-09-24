use fire_models::{
    ChatMessagesQuery, ChatMessagesResponse, SendChatMessageRequest, SendChatMessageResult,
};
use http::Method;
use openwire::RequestBody;
use serde_json::{json, Value};
use tracing::{info, warn};

use super::super::{network::expect_success, FireCore};
use super::{ensure_chat_session, DEFAULT_MESSAGE_PAGE_SIZE};
use crate::{
    chat_payloads::{parse_chat_messages_response_value, parse_send_chat_message_id},
    error::FireCoreError,
};

impl FireCore {
    pub async fn fetch_chat_messages(
        &self,
        query: ChatMessagesQuery,
    ) -> Result<ChatMessagesResponse, FireCoreError> {
        ensure_chat_session(self)?;
        let channel_id = query.channel_id;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "fetch chat messages",
                details: "channel_id must be > 0".into(),
            });
        }
        let page_size = query
            .page_size
            .filter(|value| *value > 0)
            .unwrap_or(DEFAULT_MESSAGE_PAGE_SIZE)
            .min(100);

        info!(
            channel_id,
            direction = ?query.direction,
            target_message_id = ?query.target_message_id,
            fetch_from_last_read = query.fetch_from_last_read,
            page_size,
            "fetching chat messages"
        );

        let mut params = vec![("page_size", page_size.to_string())];
        if let Some(direction) = query
            .direction
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        {
            params.push(("direction", direction));
        }
        if let Some(target_message_id) = query.target_message_id {
            params.push(("target_message_id", target_message_id.to_string()));
        }
        if query.fetch_from_last_read {
            params.push(("fetch_from_last_read", "true".to_string()));
        }

        let path = format!("/chat/api/channels/{channel_id}/messages");
        let traced = self.build_json_get_request("fetch chat messages", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch chat messages", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("fetch chat messages", trace_id, response)
            .await?;
        let result = parse_chat_messages_response_value(raw, channel_id, self.base_url()).map_err(
            |source| FireCoreError::ResponseDeserialize {
                operation: "fetch chat messages",
                source,
            },
        )?;
        self.write_cached_chat_messages(channel_id, 0, &result);
        info!(
            channel_id,
            message_count = result.messages.len(),
            can_load_more_past = result.can_load_more_past,
            "chat messages fetched"
        );
        Ok(result)
    }

    pub fn cached_chat_messages(
        &self,
        channel_id: u64,
        thread_id: u64,
    ) -> Option<ChatMessagesResponse> {
        let auth_scope_hash = self.current_auth_scope_hash();
        let payload = {
            let store = self
                .shared_store
                .lock()
                .expect("shared store mutex poisoned");
            match store.chat_messages_cache_read(&auth_scope_hash, channel_id, thread_id) {
                Ok(payload) => payload,
                Err(error) => {
                    warn!(error = %error, "failed to read chat messages cache");
                    return None;
                }
            }
        }?;
        match serde_json::from_str(&payload) {
            Ok(parsed) => Some(parsed),
            Err(error) => {
                warn!(error = %error, "failed to deserialize chat messages cache");
                None
            }
        }
    }

    pub(super) fn write_cached_chat_messages(
        &self,
        channel_id: u64,
        thread_id: u64,
        response: &ChatMessagesResponse,
    ) {
        let payload = match serde_json::to_string(response) {
            Ok(payload) => payload,
            Err(error) => {
                warn!(error = %error, "failed to serialize chat messages cache");
                return;
            }
        };
        let auth_scope_hash = self.current_auth_scope_hash();
        if let Err(error) = self
            .shared_store
            .lock()
            .expect("shared store mutex poisoned")
            .chat_messages_cache_write(&auth_scope_hash, channel_id, thread_id, &payload)
        {
            warn!(error = %error, "failed to write chat messages cache");
        }
    }

    /// POST `/chat/:channel_id`
    pub async fn send_chat_message(
        &self,
        request: SendChatMessageRequest,
    ) -> Result<SendChatMessageResult, FireCoreError> {
        ensure_chat_session(self)?;
        let channel_id = request.channel_id;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "send chat message",
                details: "channel_id must be > 0".into(),
            });
        }
        let message = request.message.trim().to_string();
        if message.is_empty() && request.upload_ids.is_empty() {
            return Err(FireCoreError::InvalidArgument {
                operation: "send chat message",
                details: "message or upload_ids required".into(),
            });
        }

        info!(
            channel_id,
            message_len = message.len(),
            upload_count = request.upload_ids.len(),
            "sending chat message"
        );

        let mut body = json!({ "message": message });
        if let Some(staged_id) = request
            .staged_id
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        {
            body["staged_id"] = Value::String(staged_id);
        }
        if let Some(in_reply_to_id) = request.in_reply_to_id {
            body["in_reply_to_id"] = json!(in_reply_to_id);
        }
        if let Some(thread_id) = request.thread_id {
            body["thread_id"] = json!(thread_id);
        }
        if !request.upload_ids.is_empty() {
            body["upload_ids"] = json!(request.upload_ids);
        }

        let path = format!("/chat/{channel_id}");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("send chat message", || {
                self.build_api_request_with_body(
                    "send chat message",
                    Method::POST,
                    &path,
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.to_string()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "send chat message", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("send chat message", trace_id, response)
            .await?;
        Ok(SendChatMessageResult {
            message_id: parse_send_chat_message_id(&raw),
        })
    }

    pub async fn edit_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
        message: String,
        upload_ids: Option<Vec<u64>>,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 || message_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "edit chat message",
                details: "channel_id and message_id must be > 0".into(),
            });
        }
        info!(channel_id, message_id, "editing chat message");
        let mut body = json!({ "message": message });
        if let Some(upload_ids) = upload_ids {
            body["upload_ids"] = json!(upload_ids);
        }
        let path = format!("/chat/api/channels/{channel_id}/messages/{message_id}");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("edit chat message", || {
                self.build_api_request_with_body(
                    "edit chat message",
                    Method::PUT,
                    &path,
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.to_string()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "edit chat message", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    /// DELETE `/chat/api/channels/:id/messages/:mid`
    pub async fn delete_chat_message(
        &self,
        channel_id: u64,
        message_id: u64,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 || message_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "delete chat message",
                details: "channel_id and message_id must be > 0".into(),
            });
        }
        info!(channel_id, message_id, "deleting chat message");
        let path = format!("/chat/api/channels/{channel_id}/messages/{message_id}");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("delete chat message", || {
                self.build_api_request("delete chat message", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "delete chat message", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
