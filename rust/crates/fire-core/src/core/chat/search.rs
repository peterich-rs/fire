use fire_models::{ChatSearchQuery, ChatSearchResult};
use serde_json::Value;
use tracing::info;

use super::super::{network::expect_success, FireCore};
use super::{ensure_chat_session, DEFAULT_SEARCH_LIMIT};
use crate::{chat_payloads::parse_chat_search_result_value, error::FireCoreError};

impl FireCore {
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
