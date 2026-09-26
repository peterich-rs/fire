use fire_models::{ChatMessagesQuery, ChatMessagesResponse};
use openwire::RequestBody;
use serde_json::{json, Value};
use tracing::info;

use super::super::{network::expect_success, FireCore};
use super::{ensure_chat_session, DEFAULT_MESSAGE_PAGE_SIZE};
use crate::{
    chat_payloads::{parse_chat_messages_response_value, parse_chat_thread_id_value},
    error::FireCoreError,
};
use http::Method;

impl FireCore {
    pub async fn create_chat_thread(
        &self,
        channel_id: u64,
        original_message_id: u64,
    ) -> Result<u64, FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 || original_message_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "create chat thread",
                details: "channel_id and original_message_id must be > 0".into(),
            });
        }
        info!(channel_id, original_message_id, "creating chat thread");
        let body = json!({ "original_message_id": original_message_id });
        let path = format!("/chat/api/channels/{channel_id}/threads");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create chat thread", || {
                self.build_api_request_with_body(
                    "create chat thread",
                    Method::POST,
                    &path,
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.to_string()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "create chat thread", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("create chat thread", trace_id, response)
            .await?;
        parse_chat_thread_id_value(&raw).ok_or_else(|| FireCoreError::InvalidArgument {
            operation: "create chat thread",
            details: "response did not contain a thread id".into(),
        })
    }

    /// GET `/chat/api/channels/:id/threads/:tid/messages`
    pub async fn fetch_chat_thread_messages(
        &self,
        channel_id: u64,
        thread_id: u64,
        query: ChatMessagesQuery,
    ) -> Result<ChatMessagesResponse, FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 || thread_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "fetch chat thread messages",
                details: "channel_id and thread_id must be > 0".into(),
            });
        }
        let page_size = query
            .page_size
            .filter(|value| *value > 0)
            .unwrap_or(DEFAULT_MESSAGE_PAGE_SIZE)
            .min(100);
        info!(
            channel_id,
            thread_id, page_size, "fetching chat thread messages"
        );

        let is_past = query
            .direction
            .as_deref()
            .is_some_and(|value| value.eq_ignore_ascii_case("past"));
        let mut params = vec![("page_size", page_size.to_string())];
        if let Some(direction) = query
            .direction
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            params.push(("direction", direction.to_string()));
        }
        if let Some(target_message_id) = query.target_message_id {
            params.push(("target_message_id", target_message_id.to_string()));
        }
        if query.fetch_from_last_read {
            params.push(("fetch_from_last_read", "true".to_string()));
        }
        let path = format!("/chat/api/channels/{channel_id}/threads/{thread_id}/messages");
        let traced =
            self.build_json_get_request("fetch chat thread messages", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response =
            expect_success(self, "fetch chat thread messages", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("fetch chat thread messages", trace_id, response)
            .await?;
        let result = parse_chat_messages_response_value(raw, channel_id, self.base_url()).map_err(
            |source| FireCoreError::ResponseDeserialize {
                operation: "fetch chat thread messages",
                source,
            },
        )?;
        self.write_cached_chat_messages(channel_id, thread_id, &result);
        if is_past {
            self.prepend_chat_channel_messages(channel_id, Some(thread_id), &result);
        } else {
            self.replace_chat_channel_messages(channel_id, Some(thread_id), &result);
        }
        Ok(result)
    }

    /// PUT `/chat/api/channels/:id/threads/:tid/read`
    pub async fn mark_chat_thread_read(
        &self,
        channel_id: u64,
        thread_id: u64,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 || thread_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "mark chat thread read",
                details: "channel_id and thread_id must be > 0".into(),
            });
        }
        let path = format!("/chat/api/channels/{channel_id}/threads/{thread_id}/read");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("mark chat thread read", || {
                self.build_api_request("mark chat thread read", Method::PUT, &path, true)
            })
            .await?;
        let response = expect_success(self, "mark chat thread read", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
