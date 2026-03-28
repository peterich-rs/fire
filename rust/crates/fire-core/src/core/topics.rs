use fire_models::{
    TopicDetail, TopicDetailQuery, TopicListKind, TopicListQuery, TopicListResponse,
};

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    topic_payloads::{RawTopicDetail, RawTopicListResponse},
};

impl FireCore {
    pub async fn fetch_topic_list(
        &self,
        query: TopicListQuery,
    ) -> Result<TopicListResponse, FireCoreError> {
        if matches!(query.kind, TopicListKind::Unread | TopicListKind::Unseen)
            && !self.snapshot().cookies.can_authenticate_requests()
        {
            return Err(FireCoreError::MissingLoginSession);
        }

        let path = if query.topic_ids.is_empty() {
            query.kind.path().to_string()
        } else {
            TopicListKind::Latest.path().to_string()
        };

        let mut params = Vec::new();
        if let Some(page) = query.page {
            if page > 0 {
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
        if let Some(order) = query.order {
            params.push(("order", order));
        }
        if let Some(ascending) = query.ascending {
            params.push(("ascending", ascending.to_string()));
        }

        let request = self.build_json_get_request(&path, params, &[])?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let response = expect_success("fetch topic list", response).await?;
        let raw: RawTopicListResponse = response
            .into_body()
            .json()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        Ok(raw.into())
    }

    pub async fn fetch_topic_detail(
        &self,
        query: TopicDetailQuery,
    ) -> Result<TopicDetail, FireCoreError> {
        let path = if let Some(post_number) = query.post_number {
            format!("/t/{}/{}.json", query.topic_id, post_number)
        } else {
            format!("/t/{}.json", query.topic_id)
        };

        let mut params = Vec::new();
        if query.track_visit {
            params.push(("track_visit", "true".to_string()));
        }
        if let Some(filter) = query.filter {
            params.push(("filter", filter));
        }
        if let Some(username_filters) = query.username_filters {
            params.push(("username_filters", username_filters));
        }
        if query.filter_top_level_replies {
            params.push(("filter_top_level_replies", "true".to_string()));
        }

        let mut extra_headers = Vec::new();
        if query.track_visit {
            extra_headers.push(("Discourse-Track-View", "1".to_string()));
            extra_headers.push(("Discourse-Track-View-Topic-Id", query.topic_id.to_string()));
        }

        let request = self.build_json_get_request(&path, params, &extra_headers)?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let response = expect_success("fetch topic detail", response).await?;
        let raw: RawTopicDetail = response
            .into_body()
            .json()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        Ok(raw.into())
    }
}
