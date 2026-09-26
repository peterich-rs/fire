use fire_models::{
    BrowseChatChannelsQuery, ChatChannel, ChatChannelMember, CreateDirectMessageChannelRequest,
    MyChatChannelsResponse,
};
use http::Method;
use openwire::RequestBody;
use serde_json::{json, Value};
use tracing::{info, warn};

use super::super::{network::expect_success, FireCore};
use super::{ensure_chat_session, DEFAULT_BROWSE_LIMIT};
use crate::{
    chat_payloads::{
        parse_browse_chat_channels_value, parse_chat_channel_members_value,
        parse_chat_channel_response_value, parse_my_chat_channels_response_value,
    },
    error::FireCoreError,
};

impl FireCore {
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
        self.write_cached_my_chat_channels(&result);
        self.hydrate_chat_list(&result);
        info!(
            public_count = result.public_channels.len(),
            dm_count = result.direct_message_channels.len(),
            badge = result.total_unread_badge(),
            "my chat channels fetched"
        );
        Ok(result)
    }

    pub fn cached_my_chat_channels(&self) -> Option<MyChatChannelsResponse> {
        let auth_scope_hash = self.current_auth_scope_hash();
        let payload = {
            let store = self
                .shared_store
                .lock()
                .expect("shared store mutex poisoned");
            match store.chat_channels_cache_read(&auth_scope_hash) {
                Ok(payload) => payload,
                Err(error) => {
                    warn!(error = %error, "failed to read chat channels cache");
                    return None;
                }
            }
        }?;
        match serde_json::from_str(&payload) {
            Ok(parsed) => {
                self.hydrate_chat_list(&parsed);
                Some(parsed)
            }
            Err(error) => {
                warn!(error = %error, "failed to deserialize chat channels cache");
                None
            }
        }
    }

    fn write_cached_my_chat_channels(&self, response: &MyChatChannelsResponse) {
        let payload = match serde_json::to_string(response) {
            Ok(payload) => payload,
            Err(error) => {
                warn!(error = %error, "failed to serialize chat channels cache");
                return;
            }
        };
        let auth_scope_hash = self.current_auth_scope_hash();
        if let Err(error) = self
            .shared_store
            .lock()
            .expect("shared store mutex poisoned")
            .chat_channels_cache_write(&auth_scope_hash, &payload)
        {
            warn!(error = %error, "failed to write chat channels cache");
        }
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
        let channel = parse_chat_channel_response_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "create direct message channel",
                source,
            }
        })?;
        let _ = self.apply_chat_list_bus_event(fire_models::ChatBusEvent::ChannelUpsert {
            channel: Box::new(channel.clone()),
        });
        Ok(channel)
    }

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
        let _ = self.apply_chat_list_tracking(channel_id, 0, 0, true);
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
}
