use std::collections::{HashMap, HashSet};

use fire_models::{
    TopicDetail, TopicDetailQuery, TopicListKind, TopicListQuery, TopicListResponse, TopicPost,
    TopicPostStream, TopicThread,
};
use serde_json::Value;
use tracing::{info, warn};

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    topic_payloads::{parse_topic_post_stream_value, RawTopicDetail, RawTopicListResponse},
};

const TOPIC_POST_BATCH_SIZE: usize = 50;

impl FireCore {
    pub async fn fetch_topic_detail_initial(
        &self,
        query: TopicDetailQuery,
    ) -> Result<TopicDetail, FireCoreError> {
        let result = self.fetch_topic_detail_base(query).await?;
        info!(
            topic_id = result.id,
            posts_count = result.posts_count,
            post_stream_total = result.post_stream.stream.len(),
            post_stream_len = result.post_stream.posts.len(),
            "topic detail initial payload fetched successfully"
        );
        Ok(result)
    }

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

        if matches!(query.kind, TopicListKind::Unread | TopicListKind::Unseen)
            && !self.snapshot().cookies.can_authenticate_requests()
        {
            warn!(kind = ?query.kind, "topic list fetch rejected: missing login session");
            return Err(FireCoreError::MissingLoginSession);
        }

        let path = query.api_path();

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
        if let Some(order) = &query.order {
            params.push(("order", order.clone()));
        }
        if let Some(ascending) = query.ascending {
            params.push(("ascending", ascending.to_string()));
        }
        for tag in &query.additional_tags {
            params.push(("tags[]", tag.clone()));
        }
        if query.match_all_tags {
            params.push(("match_all_tags", "true".to_string()));
        }

        let traced = self.build_json_get_request("fetch topic list", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch topic list", trace_id, response).await?;
        let raw: RawTopicListResponse = self
            .read_response_json("fetch topic list", trace_id, response)
            .await?;
        let result: TopicListResponse = raw.into();
        info!(
            kind = ?query.kind,
            topic_count = result.topics.len(),
            user_count = result.users.len(),
            has_more = result.more_topics_url.is_some(),
            "topic list fetched successfully"
        );
        Ok(result)
    }

    pub async fn fetch_topic_detail(
        &self,
        query: TopicDetailQuery,
    ) -> Result<TopicDetail, FireCoreError> {
        let mut result = self.fetch_topic_detail_base(query).await?;
        if let Err(error) = self
            .hydrate_topic_detail_posts(result.id, &mut result)
            .await
        {
            warn!(
                topic_id = result.id,
                error = %error,
                "topic detail hydration fell back to partially loaded posts"
            );
        }
        info!(
            topic_id = result.id,
            posts_count = result.posts_count,
            post_stream_total = result.post_stream.stream.len(),
            post_stream_len = result.post_stream.posts.len(),
            "topic detail fetched successfully"
        );
        Ok(result)
    }

    pub async fn fetch_topic_posts(
        &self,
        topic_id: u64,
        post_ids: Vec<u64>,
    ) -> Result<Vec<TopicPost>, FireCoreError> {
        if post_ids.is_empty() {
            return Ok(Vec::new());
        }

        let path = format!("/t/{topic_id}/posts.json");
        let params = post_ids
            .iter()
            .copied()
            .map(|post_id| ("post_ids[]", post_id.to_string()))
            .collect::<Vec<_>>();
        let traced = self.build_json_get_request("fetch topic posts", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch topic posts", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch topic posts", trace_id, response)
            .await?;
        let post_stream = parse_topic_post_stream_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch topic posts",
                source,
            }
        })?;
        Ok(post_stream.posts)
    }

    async fn fetch_topic_detail_base(
        &self,
        query: TopicDetailQuery,
    ) -> Result<TopicDetail, FireCoreError> {
        info!(
            topic_id = query.topic_id,
            post_number = ?query.post_number,
            track_visit = query.track_visit,
            "fetching topic detail"
        );

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

        let traced =
            self.build_json_get_request("fetch topic detail", &path, params, &extra_headers)?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch topic detail", trace_id, response).await?;
        let raw: RawTopicDetail = self
            .read_response_json("fetch topic detail", trace_id, response)
            .await?;
        Ok(raw.into())
    }

    async fn hydrate_topic_detail_posts(
        &self,
        topic_id: u64,
        detail: &mut TopicDetail,
    ) -> Result<(), FireCoreError> {
        let missing_post_ids = missing_topic_post_ids(&detail.post_stream);
        if missing_post_ids.is_empty() {
            return Ok(());
        }

        info!(
            topic_id,
            loaded_posts = detail.post_stream.posts.len(),
            total_posts = detail.post_stream.stream.len(),
            missing_posts = missing_post_ids.len(),
            "hydrating missing topic posts"
        );

        let mut fetched_posts = Vec::with_capacity(missing_post_ids.len());
        for post_ids in missing_post_ids.chunks(TOPIC_POST_BATCH_SIZE) {
            fetched_posts.extend(self.fetch_topic_posts(topic_id, post_ids.to_vec()).await?);
        }

        if fetched_posts.is_empty() {
            return Ok(());
        }

        detail.post_stream.posts = merge_topic_posts(
            &detail.post_stream.stream,
            std::mem::take(&mut detail.post_stream.posts),
            fetched_posts,
        );
        detail.thread = TopicThread::from_posts(&detail.post_stream.posts);
        detail.flat_posts = detail.thread.flatten(&detail.post_stream.posts);

        let remaining_missing = missing_topic_post_ids(&detail.post_stream);
        if !remaining_missing.is_empty() {
            warn!(
                topic_id,
                missing_posts = remaining_missing.len(),
                loaded_posts = detail.post_stream.posts.len(),
                total_posts = detail.post_stream.stream.len(),
                "topic detail hydration completed with unresolved missing posts"
            );
        }

        Ok(())
    }
}

fn missing_topic_post_ids(post_stream: &TopicPostStream) -> Vec<u64> {
    if post_stream.stream.len() <= post_stream.posts.len() {
        return Vec::new();
    }

    let loaded_post_ids: HashSet<u64> = post_stream.posts.iter().map(|post| post.id).collect();
    post_stream
        .stream
        .iter()
        .copied()
        .filter(|post_id| !loaded_post_ids.contains(post_id))
        .collect()
}

fn merge_topic_posts(
    ordered_post_ids: &[u64],
    existing_posts: Vec<TopicPost>,
    fetched_posts: Vec<TopicPost>,
) -> Vec<TopicPost> {
    let mut posts_by_id: HashMap<u64, TopicPost> = existing_posts
        .into_iter()
        .chain(fetched_posts)
        .map(|post| (post.id, post))
        .collect();

    let mut merged_posts = Vec::with_capacity(posts_by_id.len());
    for post_id in ordered_post_ids {
        if let Some(post) = posts_by_id.remove(post_id) {
            merged_posts.push(post);
        }
    }

    let mut trailing_posts: Vec<TopicPost> = posts_by_id.into_values().collect();
    trailing_posts.sort_by_key(|post| (post.post_number, post.id));
    merged_posts.extend(trailing_posts);
    merged_posts
}
