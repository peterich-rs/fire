use fire_models::{
    SearchQuery, SearchResult, TagSearchQuery, TagSearchResult, UserMentionQuery, UserMentionResult,
};
use serde_json::Value;
use tracing::info;

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    search_payloads::{
        parse_search_result_value, parse_tag_search_result_value, parse_user_mention_result_value,
    },
};

impl FireCore {
    pub async fn search(&self, query: SearchQuery) -> Result<SearchResult, FireCoreError> {
        info!(
            q = %query.q,
            page = ?query.page,
            type_filter = ?query.type_filter,
            "performing search"
        );

        let mut params = vec![("q", query.q)];
        if let Some(page) = query.page.filter(|page| *page > 0) {
            params.push(("page", page.to_string()));
        }
        if let Some(type_filter) = query.type_filter {
            params.push(("type_filter", type_filter.query_value().to_string()));
        }

        let traced = self.build_json_get_request("search", "/search.json", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "search", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("search", trace_id, response)
            .await?;
        let result = parse_search_result_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "search",
                source,
            }
        })?;
        info!(
            post_count = result.posts.len(),
            topic_count = result.topics.len(),
            user_count = result.users.len(),
            "search completed"
        );
        Ok(result)
    }

    pub async fn search_tags(
        &self,
        query: TagSearchQuery,
    ) -> Result<TagSearchResult, FireCoreError> {
        info!(
            q = ?query.q,
            filter_for_input = query.filter_for_input,
            limit = ?query.limit,
            category_id = ?query.category_id,
            selected_tags_count = query.selected_tags.len(),
            "searching tags"
        );

        let mut params = Vec::new();
        if let Some(q) = query.q.filter(|value| !value.is_empty()) {
            params.push(("q", q));
        }
        if query.filter_for_input {
            params.push(("filterForInput", "true".to_string()));
        }
        if let Some(limit) = query.limit.filter(|limit| *limit > 0) {
            params.push(("limit", limit.to_string()));
        }
        if let Some(category_id) = query.category_id {
            params.push(("categoryId", category_id.to_string()));
        }
        for selected_tag in query
            .selected_tags
            .into_iter()
            .filter(|value| !value.is_empty())
        {
            params.push(("selected_tags[]", selected_tag));
        }

        let traced =
            self.build_json_get_request("search tags", "/tags/filter/search", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "search tags", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("search tags", trace_id, response)
            .await?;
        let result = parse_tag_search_result_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "search tags",
                source,
            }
        })?;
        info!(result_count = result.results.len(), "tag search completed");
        Ok(result)
    }

    pub async fn search_users(
        &self,
        query: UserMentionQuery,
    ) -> Result<UserMentionResult, FireCoreError> {
        info!(
            term = %query.term,
            include_groups = query.include_groups,
            limit = query.limit,
            topic_id = ?query.topic_id,
            category_id = ?query.category_id,
            "searching mention users"
        );

        let mut params = vec![
            ("term", query.term),
            ("include_groups", query.include_groups.to_string()),
        ];
        if query.limit > 0 {
            params.push(("limit", query.limit.to_string()));
        }
        if let Some(topic_id) = query.topic_id {
            params.push(("topic_id", topic_id.to_string()));
        }
        if let Some(category_id) = query.category_id {
            params.push(("category_id", category_id.to_string()));
        }

        let traced = self.build_json_get_request("search users", "/u/search/users", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "search users", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("search users", trace_id, response)
            .await?;
        let result = parse_user_mention_result_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "search users",
                source,
            }
        })?;
        info!(
            user_count = result.users.len(),
            group_count = result.groups.len(),
            "mention search completed"
        );
        Ok(result)
    }
}
