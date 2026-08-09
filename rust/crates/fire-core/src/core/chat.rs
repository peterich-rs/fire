use fire_models::{
    BrowseChatChannelsQuery, ChatChannel, ChatChannelMember, ChatMessagesQuery,
    ChatMessagesResponse, ChatSearchQuery, ChatSearchResult, CreateDirectMessageChannelRequest,
    MyChatChannelsResponse, SendChatMessageRequest, SendChatMessageResult,
};
use http::Method;
use openwire::RequestBody;
use serde_json::{json, Value};
use tracing::info;

use super::{network::expect_success, FireCore};
use crate::{
    chat_payloads::{
        parse_browse_chat_channels_value, parse_chat_channel_members_value,
        parse_chat_channel_response_value, parse_chat_messages_response_value,
        parse_chat_search_result_value, parse_my_chat_channels_response_value,
        parse_send_chat_message_id,
    },
    error::FireCoreError,
};

const DEFAULT_MESSAGE_PAGE_SIZE: u32 = 50;
const DEFAULT_BROWSE_LIMIT: u32 = 25;
const DEFAULT_SEARCH_LIMIT: u32 = 20;

impl FireCore {
    /// GET `/chat/api/me/channels`
    pub async fn fetch_my_chat_channels(&self) -> Result<MyChatChannelsResponse, FireCoreError> {
        ensure_chat_session(self)?;
        info!("fetching my chat channels");

        let traced = self.build_json_get_request(
            "fetch my chat channels",
            "/chat/api/me/channels",
            vec![],
            &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch my chat channels", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("fetch my chat channels", trace_id, response)
            .await?;
        let result = parse_my_chat_channels_response_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch my chat channels",
                source,
            }
        })?;
        info!(
            public_count = result.public_channels.len(),
            dm_count = result.direct_message_channels.len(),
            badge = result.total_unread_badge(),
            "my chat channels fetched"
        );
        Ok(result)
    }

    /// GET `/chat/api/channels/:id`
    pub async fn fetch_chat_channel(&self, channel_id: u64) -> Result<ChatChannel, FireCoreError> {
        ensure_chat_session(self)?;
        info!(channel_id, "fetching chat channel");

        let path = format!("/chat/api/channels/{channel_id}");
        let traced = self.build_json_get_request("fetch chat channel", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch chat channel", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("fetch chat channel", trace_id, response)
            .await?;
        parse_chat_channel_response_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch chat channel",
                source,
            }
        })
    }

    /// POST `/chat/api/direct-message-channels`
    pub async fn create_direct_message_channel(
        &self,
        request: CreateDirectMessageChannelRequest,
    ) -> Result<ChatChannel, FireCoreError> {
        ensure_chat_session(self)?;
        let usernames = request
            .target_usernames
            .into_iter()
            .map(|name| name.trim().to_string())
            .filter(|name| !name.is_empty())
            .collect::<Vec<_>>();
        if usernames.is_empty() {
            return Err(FireCoreError::InvalidArgument {
                operation: "create direct message channel",
                details: "target_usernames must not be empty".into(),
            });
        }
        info!(
            recipients = usernames.len(),
            upsert = request.upsert,
            "creating direct message channel"
        );

        let mut body = json!({
            "target_usernames": usernames,
        });
        if let Some(name) = request
            .name
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        {
            body["name"] = Value::String(name);
        }
        if request.upsert {
            body["upsert"] = Value::Bool(true);
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create direct message channel", || {
                self.build_api_request_with_body(
                    "create direct message channel",
                    Method::POST,
                    "/chat/api/direct-message-channels",
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.to_string()),
                    true,
                )
            })
            .await?;
        let response =
            expect_success(self, "create direct message channel", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("create direct message channel", trace_id, response)
            .await?;
        parse_chat_channel_response_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "create direct message channel",
                source,
            }
        })
    }

    /// GET `/chat/api/channels/:id/messages`
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
        let result = parse_chat_messages_response_value(raw, channel_id).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch chat messages",
                source,
            }
        })?;
        info!(
            channel_id,
            message_count = result.messages.len(),
            can_load_more_past = result.can_load_more_past,
            "chat messages fetched"
        );
        Ok(result)
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

    /// PUT `/chat/api/channels/:id/read`
    pub async fn mark_chat_channel_read(
        &self,
        channel_id: u64,
        message_id: Option<u64>,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "mark chat channel read",
                details: "channel_id must be > 0".into(),
            });
        }
        info!(channel_id, message_id = ?message_id, "marking chat channel read");

        let mut path = format!("/chat/api/channels/{channel_id}/read");
        if let Some(message_id) = message_id {
            path.push_str(&format!("?message_id={message_id}"));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("mark chat channel read", || {
                self.build_api_request("mark chat channel read", Method::PUT, &path, true)
            })
            .await?;
        let response = expect_success(self, "mark chat channel read", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    /// GET `/chat/api/channels`
    pub async fn browse_chat_channels(
        &self,
        query: BrowseChatChannelsQuery,
    ) -> Result<Vec<ChatChannel>, FireCoreError> {
        ensure_chat_session(self)?;
        let limit = query
            .limit
            .filter(|value| *value > 0)
            .unwrap_or(DEFAULT_BROWSE_LIMIT)
            .min(50);
        let offset = query.offset.unwrap_or(0);
        info!(offset, limit, filter = ?query.filter, "browsing chat channels");

        let mut params = vec![
            ("offset", offset.to_string()),
            ("limit", limit.to_string()),
            ("status", "open".to_string()),
        ];
        if let Some(filter) = query
            .filter
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        {
            params.push(("filter", filter));
        }

        let traced =
            self.build_json_get_request("browse chat channels", "/chat/api/channels", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "browse chat channels", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("browse chat channels", trace_id, response)
            .await?;
        parse_browse_chat_channels_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "browse chat channels",
            source,
        })
    }

    /// POST `/chat/api/channels/:id/memberships/me`
    pub async fn join_chat_channel(&self, channel_id: u64) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "join chat channel",
                details: "channel_id must be > 0".into(),
            });
        }
        info!(channel_id, "joining chat channel");
        let path = format!("/chat/api/channels/{channel_id}/memberships/me");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("join chat channel", || {
                self.build_api_request("join chat channel", Method::POST, &path, true)
            })
            .await?;
        let response = expect_success(self, "join chat channel", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    /// DELETE `/chat/api/channels/:id/memberships/me/follows`
    pub async fn leave_chat_channel(&self, channel_id: u64) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "leave chat channel",
                details: "channel_id must be > 0".into(),
            });
        }
        info!(channel_id, "leaving chat channel");
        let path = format!("/chat/api/channels/{channel_id}/memberships/me/follows");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("leave chat channel", || {
                self.build_api_request("leave chat channel", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "leave chat channel", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    /// PUT `/chat/api/channels/:id/memberships/me` with starred
    pub async fn star_chat_channel(
        &self,
        channel_id: u64,
        starred: bool,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "star chat channel",
                details: "channel_id must be > 0".into(),
            });
        }
        info!(channel_id, starred, "updating chat channel star");
        let path = format!("/chat/api/channels/{channel_id}/memberships/me");
        let body = json!({ "starred": starred });
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("star chat channel", || {
                self.build_api_request_with_body(
                    "star chat channel",
                    Method::PUT,
                    &path,
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.to_string()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "star chat channel", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    /// PUT `/chat/api/channels/:id/notifications-settings/me`
    pub async fn update_chat_channel_notifications(
        &self,
        channel_id: u64,
        muted: Option<bool>,
        notification_level: Option<String>,
    ) -> Result<(), FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "update chat channel notifications",
                details: "channel_id must be > 0".into(),
            });
        }
        info!(
            channel_id,
            muted = ?muted,
            notification_level = ?notification_level,
            "updating chat channel notifications"
        );

        let mut settings = serde_json::Map::new();
        if let Some(muted) = muted {
            settings.insert("muted".into(), Value::Bool(muted));
        }
        if let Some(level) = notification_level
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        {
            settings.insert("notification_level".into(), Value::String(level));
        }
        let body = json!({ "notifications_settings": settings });
        let path = format!("/chat/api/channels/{channel_id}/notifications-settings/me");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("update chat channel notifications", || {
                self.build_api_request_with_body(
                    "update chat channel notifications",
                    Method::PUT,
                    &path,
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.to_string()),
                    true,
                )
            })
            .await?;
        let response = expect_success(
            self,
            "update chat channel notifications",
            trace_id,
            response,
        )
        .await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    /// PUT `/chat/api/channels/:id/messages/:mid`
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

    /// PUT `/chat/:channel_id/react/:message_id`
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

    /// GET `/chat/api/channels/:id/memberships`
    pub async fn fetch_chat_channel_members(
        &self,
        channel_id: u64,
        offset: Option<u32>,
        limit: Option<u32>,
        username: Option<String>,
    ) -> Result<Vec<ChatChannelMember>, FireCoreError> {
        ensure_chat_session(self)?;
        if channel_id == 0 {
            return Err(FireCoreError::InvalidArgument {
                operation: "fetch chat channel members",
                details: "channel_id must be > 0".into(),
            });
        }
        let limit = limit.filter(|value| *value > 0).unwrap_or(50).min(50);
        let offset = offset.unwrap_or(0);
        info!(channel_id, offset, limit, "fetching chat channel members");

        let mut params = vec![("offset", offset.to_string()), ("limit", limit.to_string())];
        if let Some(username) = username
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        {
            params.push(("username", username));
        }
        let path = format!("/chat/api/channels/{channel_id}/memberships");
        let traced =
            self.build_json_get_request("fetch chat channel members", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response =
            expect_success(self, "fetch chat channel members", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("fetch chat channel members", trace_id, response)
            .await?;
        parse_chat_channel_members_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "fetch chat channel members",
            source,
        })
    }

    /// GET `/chat/api/search`
    pub async fn search_chat_messages(
        &self,
        query: ChatSearchQuery,
    ) -> Result<ChatSearchResult, FireCoreError> {
        ensure_chat_session(self)?;
        let term = query.query.trim().to_string();
        if term.is_empty() {
            return Err(FireCoreError::InvalidArgument {
                operation: "search chat messages",
                details: "query must not be empty".into(),
            });
        }
        let limit = query
            .limit
            .filter(|value| *value > 0)
            .unwrap_or(DEFAULT_SEARCH_LIMIT)
            .min(40);
        let offset = query.offset.unwrap_or(0);
        info!(
            query = %term,
            channel_id = ?query.channel_id,
            offset,
            limit,
            "searching chat messages"
        );

        let mut params = vec![
            ("query", term),
            ("offset", offset.to_string()),
            ("limit", limit.to_string()),
        ];
        if let Some(channel_id) = query.channel_id {
            params.push(("channel_id", channel_id.to_string()));
        }
        let traced =
            self.build_json_get_request("search chat messages", "/chat/api/search", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "search chat messages", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("search chat messages", trace_id, response)
            .await?;
        parse_chat_search_result_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "search chat messages",
            source,
        })
    }
}

fn ensure_chat_session(core: &FireCore) -> Result<(), FireCoreError> {
    if core.snapshot().cookies.can_authenticate_requests() {
        Ok(())
    } else {
        Err(FireCoreError::MissingLoginSession)
    }
}
