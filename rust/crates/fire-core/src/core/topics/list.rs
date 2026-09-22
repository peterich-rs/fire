use fire_models::{TopicListKind, TopicListQuery, TopicListResponse};
use tracing::{info, warn};

use super::super::{network::expect_success, FireCore};
use crate::{error::FireCoreError, topic_payloads::RawTopicListResponse};

pub(crate) fn topic_list_cache_scope_key(query: &TopicListQuery) -> String {
    let mut parts = vec![
        format!("kind={}", query.kind.filter_name()),
        format!(
            "category_slug={}",
            query.category_slug.as_deref().unwrap_or("")
        ),
        format!(
            "category_id={}",
            query.category_id.map_or(String::new(), |id| id.to_string())
        ),
        format!(
            "parent_category_slug={}",
            query.parent_category_slug.as_deref().unwrap_or("")
        ),
        format!("tag={}", normalized_cache_value(query.tag.as_deref())),
        format!("order={}", query.order.as_deref().unwrap_or("")),
        format!(
            "ascending={}",
            query
                .ascending
                .map_or(String::new(), |value| value.to_string())
        ),
        format!("match_all_tags={}", query.match_all_tags),
    ];

    let mut topic_ids = query.topic_ids.clone();
    topic_ids.sort_unstable();
    parts.push(format!(
        "topic_ids={}",
        topic_ids
            .iter()
            .map(u64::to_string)
            .collect::<Vec<_>>()
            .join(",")
    ));

    parts.push(format!(
        "additional_tags={}",
        query
            .additional_tags
            .iter()
            .map(|tag| normalized_cache_value(Some(tag)))
            .collect::<Vec<_>>()
            .join(",")
    ));

    parts.join("|")
}

fn normalized_cache_value(value: Option<&str>) -> String {
    value.unwrap_or("").trim().to_ascii_lowercase()
}

impl FireCore {
    pub async fn fetch_topic_list(
        &self,
        query: TopicListQuery,
    ) -> Result<TopicListResponse, FireCoreError> {
        info!(
            kind = ?query.kind,
            page = ?query.page,
            category_slug = ?query.category_slug,
            tag = ?query.tag,
            topic_ids_count = query.topic_ids.len(),
            "fetching topic list"
        );

        if matches!(
            query.kind,
            TopicListKind::Unread
                | TopicListKind::Unseen
                | TopicListKind::PrivateMessagesInbox
                | TopicListKind::PrivateMessagesSent
        ) && !self.snapshot().cookies.can_authenticate_requests()
        {
            warn!(kind = ?query.kind, "topic list fetch rejected: missing login session");
            return Err(FireCoreError::MissingLoginSession);
        }

        let path = match query.kind {
            TopicListKind::PrivateMessagesInbox | TopicListKind::PrivateMessagesSent => {
                let snapshot = self.snapshot();
                let username = snapshot
                    .bootstrap
                    .current_username
                    .filter(|value| !value.trim().is_empty())
                    .ok_or(FireCoreError::MissingLoginSession)?;
                match query.kind {
                    TopicListKind::PrivateMessagesInbox => {
                        format!("/topics/private-messages/{username}.json")
                    }
                    TopicListKind::PrivateMessagesSent => {
                        format!("/topics/private-messages-sent/{username}.json")
                    }
                    _ => unreachable!(),
                }
            }
            _ => query.api_path(),
        };

        let mut params = Vec::new();
        if let Some(page) = query.page {
            if page > 0 {
                params.push(("no_definitions", "true".to_string()));
                params.push(("page", page.to_string()));
            }
        }
        if !query.topic_ids.is_empty() {
            params.push((
                "topic_ids",
                query
                    .topic_ids
                    .iter()
                    .map(u64::to_string)
                    .collect::<Vec<_>>()
                    .join(","),
            ));
        }
        if let Some(order) = &query.order {
            params.push(("order", order.clone()));
        }
        if let Some(ascending) = query.ascending {
            params.push(("ascending", ascending.to_string()));
        }
        let primary_tag_as_query_param = query.category_slug.is_some().then(|| {
            query
                .tag
                .as_ref()
                .map(|tag| tag.trim())
                .filter(|tag| !tag.is_empty())
                .map(ToOwned::to_owned)
        });
        for tag in primary_tag_as_query_param.into_iter().flatten() {
            params.push(("tags[]", tag));
        }
        for tag in &query.additional_tags {
            params.push(("tags[]", tag.clone()));
        }
        if query.match_all_tags {
            params.push(("match_all_tags", "true".to_string()));
        }

        let cache_scope_key = topic_list_cache_scope_key(&query);
        let cache_page = query.page.unwrap_or(0);
        let traced = self.build_json_get_request("fetch topic list", &path, params, &[])?;
        let (trace_id, response) = match self.execute_request(traced).await {
            Ok(response) => response,
            Err(error @ FireCoreError::Network { .. }) => {
                if let Some(cached) = self.read_cached_topic_list(&cache_scope_key, cache_page)? {
                    warn!(
                        kind = ?query.kind,
                        page = ?query.page,
                        "topic list network fetch failed; returning cached page"
                    );
                    return Ok(cached);
                }
                return Err(error);
            }
            Err(error) => return Err(error),
        };
        let response = expect_success(self, "fetch topic list", trace_id, response).await?;
        let raw: RawTopicListResponse = self
            .read_response_json("fetch topic list", trace_id, response)
            .await?;
        let result: TopicListResponse = raw.into();
        self.write_cached_topic_list(&cache_scope_key, cache_page, &result);
        info!(
            kind = ?query.kind,
            topic_count = result.topics.len(),
            user_count = result.users.len(),
            has_more = result.more_topics_url.is_some(),
            "topic list fetched successfully"
        );
        Ok(result)
    }

    fn read_cached_topic_list(
        &self,
        scope_key: &str,
        page: u32,
    ) -> Result<Option<TopicListResponse>, FireCoreError> {
        let auth_scope_hash = self.current_auth_scope_hash();
        let payload = {
            let store = self
                .shared_store
                .lock()
                .expect("shared store mutex poisoned");
            store.topic_list_cache_read(&auth_scope_hash, scope_key, page)?
        };

        let Some(payload) = payload else {
            return Ok(None);
        };

        let mut cached: TopicListResponse = serde_json::from_str(&payload).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "cached topic list",
                source,
            }
        })?;
        cached.is_cached = true;
        Ok(Some(cached))
    }

    fn write_cached_topic_list(&self, scope_key: &str, page: u32, response: &TopicListResponse) {
        let auth_scope_hash = self.current_auth_scope_hash();
        let mut cached = response.clone();
        cached.is_cached = false;
        let payload = match serde_json::to_string(&cached) {
            Ok(payload) => payload,
            Err(error) => {
                warn!(error = %error, "failed to serialize topic list cache payload");
                return;
            }
        };
        let result = self
            .shared_store
            .lock()
            .expect("shared store mutex poisoned")
            .topic_list_cache_write(&auth_scope_hash, scope_key, page, &payload);
        if let Err(error) = result {
            warn!(error = %error, "failed to write topic list cache");
        }
    }
}
