use std::collections::{BTreeMap, HashMap, HashSet};
use std::time::Instant;

use fire_models::{
    LoadMoreTopicPostsQuery, TopicAiSummary, TopicBody, TopicDetail, TopicDetailPage,
    TopicDetailQuery, TopicDetailSourceAppend, TopicDetailSourceQuery, TopicDetailSourceSnapshot,
    TopicHeader, TopicListKind, TopicListQuery, TopicListResponse, TopicLoadMoreOutcome,
    TopicLoadMoreStopReason, TopicLoadedRange, TopicPost, TopicPostStream, TopicSourceCursor,
    TopicThread, TopicTreePresentation, TopicTreePresentationQuery, TopicTreeRow,
};
use http::StatusCode;
use serde_json::Value;
use tracing::{debug, info, warn};

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    topic_payloads::{
        parse_topic_ai_summary_value, parse_topic_post_stream_value, parse_topic_post_value,
        RawTopicDetail, RawTopicListResponse,
    },
};

const TOPIC_POST_BATCH_SIZE: usize = 50;
const FETCH_TOPIC_AI_SUMMARY_OPERATION: &str = "fetch topic ai summary";
const DEFAULT_TOPIC_INITIAL_BATCH_SIZE: u16 = 40;
const DEFAULT_TOPIC_LOAD_MORE_BATCH_SIZE: u16 = 40;
const DEFAULT_TOPIC_MAX_AUTO_BATCHES_PER_GESTURE: u8 = 3;
const DEFAULT_TOPIC_MAX_AUTO_POSTS_PER_GESTURE: u16 = 120;
const TOPIC_PARENT_HOP_LIMIT: usize = 32;
const TOPIC_LOAD_MORE_FAILURE_MESSAGE: &str = "topic source batch append failed";

#[derive(Default)]
pub(crate) struct FireTopicDetailSourceRuntime {
    next_session_id: u64,
    sessions_by_topic_id: HashMap<u64, TopicDetailSourceSession>,
}

#[derive(Clone)]
struct TopicDetailSourceSession {
    session_id: u64,
    session_epoch: u64,
    header: TopicHeader,
    body_post_id: u64,
    body_post_number: u32,
    focused_post_number: Option<u32>,
    raw_stream_ids: Vec<u64>,
    posts_by_id: HashMap<u64, TopicPost>,
    post_id_by_number: HashMap<u32, u64>,
    unavailable_post_ids: HashSet<u64>,
    loaded_ranges: Vec<TopicLoadedRange>,
    next_stream_offset: usize,
    last_loaded_post_id: Option<u64>,
    source_exhausted: bool,
    load_more_policy: TopicLoadMorePolicy,
}

#[derive(Clone, Copy)]
struct TopicLoadMorePolicy {
    batch_size: u16,
    max_auto_batches_per_gesture: u8,
    max_auto_posts_per_gesture: u16,
    require_new_root_progress: bool,
}

struct TopicDetailSourceSessionInit {
    session_epoch: u64,
    header: TopicHeader,
    body_post: TopicPost,
    focused_post_number: Option<u32>,
    raw_stream_ids: Vec<u64>,
    cached_posts: Vec<TopicPost>,
    unavailable_post_ids: HashSet<u64>,
    load_more_policy: TopicLoadMorePolicy,
}

impl FireCore {
    pub async fn fetch_topic_detail_initial(
        &self,
        query: TopicDetailQuery,
    ) -> Result<TopicDetail, FireCoreError> {
        let mut result = self.fetch_topic_detail_base(query, true).await?;
        result.rebuild_timeline_entries();
        info!(
            topic_id = result.id,
            posts_count = result.posts_count,
            post_stream_total = result.post_stream.stream.len(),
            post_stream_len = result.post_stream.posts.len(),
            timeline_entries = result.timeline_entries.len(),
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
        let mut result = self.fetch_topic_detail_base(query, true).await?;
        if let Err(error) = self
            .hydrate_topic_detail_posts(result.id, &mut result)
            .await
        {
            warn!(
                topic_id = result.id,
                error = %error,
                "topic detail hydration fell back to partially loaded posts"
            );
            // Hydration builds timeline entries on success; build from partial data on failure.
            result.rebuild_timeline_entries();
        }
        info!(
            topic_id = result.id,
            posts_count = result.posts_count,
            post_stream_total = result.post_stream.stream.len(),
            post_stream_len = result.post_stream.posts.len(),
            timeline_entries = result.timeline_entries.len(),
            "topic detail fetched successfully"
        );
        Ok(result)
    }

    pub async fn fetch_topic_detail_source_snapshot(
        &self,
        query: TopicDetailSourceQuery,
    ) -> Result<TopicDetailSourceSnapshot, FireCoreError> {
        let focused_post_number = query
            .target_post_number
            .filter(|post_number| *post_number > 1);
        let initial_batch_size = normalized_topic_initial_batch_size(query.initial_batch_size);
        let load_more_policy = TopicLoadMorePolicy {
            batch_size: normalized_topic_load_more_batch_size(query.load_more_batch_size),
            max_auto_batches_per_gesture: normalized_topic_auto_batch_limit(
                query.max_auto_batches_per_gesture,
            ),
            max_auto_posts_per_gesture: normalized_topic_auto_post_limit(
                query.max_auto_posts_per_gesture,
            ),
            require_new_root_progress: true,
        };

        let mut detail = self
            .fetch_topic_detail_base(
                TopicDetailQuery {
                    topic_id: query.topic_id,
                    post_number: focused_post_number,
                    track_visit: query.track_visit,
                    force_load: query.force_load,
                    filter: None,
                    username_filters: None,
                    filter_top_level_replies: false,
                },
                false,
            )
            .await?;

        let body_post = match detail
            .post_stream
            .posts
            .iter()
            .find(|post| post.post_number == 1)
            .cloned()
        {
            Some(post) => post,
            None => self.fetch_post_by_number(query.topic_id, 1).await?,
        };
        if detail.post_stream.stream.is_empty() && body_post.id > 0 {
            detail.post_stream.stream.push(body_post.id);
        }

        if let Some(target_post_number) = focused_post_number.filter(|post_number| {
            !detail
                .post_stream
                .posts
                .iter()
                .any(|post| post.post_number == *post_number)
        }) {
            detail.post_stream.posts.push(
                self.fetch_post_by_number(query.topic_id, target_post_number)
                    .await?,
            );
        }
        if !detail
            .post_stream
            .posts
            .iter()
            .any(|post| post.id == body_post.id)
        {
            detail.post_stream.posts.push(body_post.clone());
        }

        let initial_source_post_ids = detail
            .post_stream
            .stream
            .iter()
            .copied()
            .take(usize::from(initial_batch_size))
            .collect::<Vec<_>>();
        let missing_initial_post_ids =
            missing_post_ids_from_ids(&initial_source_post_ids, &detail.post_stream.posts);
        let fetched_initial_posts = if missing_initial_post_ids.is_empty() {
            Vec::new()
        } else {
            self.fetch_topic_posts(query.topic_id, missing_initial_post_ids.clone())
                .await?
        };
        let fetched_initial_post_ids = fetched_initial_posts
            .iter()
            .map(|post| post.id)
            .collect::<HashSet<_>>();
        let initial_unavailable_post_ids = missing_initial_post_ids
            .into_iter()
            .filter(|post_id| !fetched_initial_post_ids.contains(post_id))
            .collect::<HashSet<_>>();
        detail.post_stream.posts = merge_topic_posts(
            &detail.post_stream.stream,
            std::mem::take(&mut detail.post_stream.posts),
            fetched_initial_posts,
        );

        let header = detail.header();
        let session = TopicDetailSourceSession::new(TopicDetailSourceSessionInit {
            session_epoch: self.current_session_epoch(),
            header,
            body_post,
            focused_post_number,
            raw_stream_ids: detail.post_stream.stream,
            cached_posts: detail.post_stream.posts,
            unavailable_post_ids: initial_unavailable_post_ids,
            load_more_policy,
        });

        let snapshot = {
            let mut runtime = self
                .topic_detail_source
                .lock()
                .expect("topic detail source runtime lock poisoned");
            let next_session_id = runtime.next_session_id.saturating_add(1).max(1);
            runtime.next_session_id = next_session_id;
            let session = session.with_session_id(next_session_id);
            let snapshot = session.source_snapshot();
            runtime.sessions_by_topic_id.insert(query.topic_id, session);
            snapshot
        };

        Ok(snapshot)
    }

    pub async fn fetch_topic_detail_page(
        &self,
        query: TopicDetailSourceQuery,
    ) -> Result<TopicDetailPage, FireCoreError> {
        let topic_id = query.topic_id;
        let source_started_at = Instant::now();
        let source_snapshot = self.fetch_topic_detail_source_snapshot(query).await?;
        let source_fetch_ms = source_started_at.elapsed().as_millis();
        let tree_started_at = Instant::now();
        let tree_presentation =
            build_topic_tree_presentation_from_source_snapshot(&source_snapshot);
        let tree_presentation_ms = tree_started_at.elapsed().as_millis();
        info!(
            topic_id,
            source_fetch_ms,
            tree_presentation_ms,
            source_loaded_posts = source_snapshot.loaded_posts.len(),
            body_post_included = true,
            cooked_byte_count = topic_detail_source_cooked_byte_count(&source_snapshot),
            reply_rows = tree_presentation.reply_rows.len(),
            visible_root_count = tree_presentation.visible_root_post_numbers.len(),
            total_loaded_post_count = tree_presentation.total_loaded_post_count,
            "topic detail page built"
        );
        Ok(TopicDetailPage {
            source_snapshot,
            tree_presentation,
        })
    }

    pub fn build_topic_tree_presentation(
        &self,
        query: TopicTreePresentationQuery,
    ) -> TopicTreePresentation {
        build_topic_tree_presentation_from_query(query)
    }

    pub async fn append_topic_detail_source(
        &self,
        query: LoadMoreTopicPostsQuery,
    ) -> Result<TopicDetailSourceAppend, FireCoreError> {
        self.append_topic_source_batch(query.cursor).await
    }

    pub async fn load_more_topic_posts(
        &self,
        query: LoadMoreTopicPostsQuery,
    ) -> Result<TopicLoadMoreOutcome, FireCoreError> {
        let initial_session = self.clone_active_source_session(
            query.cursor.topic_id,
            query.cursor.session_id,
            None,
            None,
        )?;
        let initial_snapshot = initial_session.source_snapshot();
        let baseline_tree = build_topic_tree_presentation_from_source_snapshot(&initial_snapshot);
        let baseline_visible_roots = baseline_tree.visible_root_post_numbers.clone();
        let policy = initial_session.load_more_policy;

        let mut current_cursor = query.cursor;
        let mut latest_snapshot = initial_snapshot;
        let mut latest_tree = baseline_tree;
        let mut chained_batches: u8 = 0;
        let mut chained_posts: u16 = 0;

        loop {
            let append_result = self.append_topic_source_batch(current_cursor.clone()).await;
            let append = match append_result {
                Ok(append) => append,
                Err(error) if chained_batches == 0 => return Err(error),
                Err(error) => {
                    warn!(
                        topic_id = current_cursor.topic_id,
                        session_id = current_cursor.session_id,
                        batches = chained_batches,
                        posts = chained_posts,
                        error = %error,
                        "{TOPIC_LOAD_MORE_FAILURE_MESSAGE}"
                    );
                    latest_tree.gained_new_root_progress = gained_visible_root_progress(
                        &baseline_visible_roots,
                        &latest_tree.visible_root_post_numbers,
                    );
                    return Ok(TopicLoadMoreOutcome {
                        source_snapshot: latest_snapshot,
                        tree_presentation: latest_tree,
                        chained_batches,
                        chained_posts,
                        stop_reason: TopicLoadMoreStopReason::RequestFailed,
                    });
                }
            };

            chained_batches = chained_batches.saturating_add(1);
            chained_posts = chained_posts
                .saturating_add(u16::try_from(append.appended_posts.len()).unwrap_or(u16::MAX));
            let session = self.clone_active_source_session(
                current_cursor.topic_id,
                current_cursor.session_id,
                None,
                None,
            )?;
            latest_snapshot = session.source_snapshot();
            latest_tree = build_topic_tree_presentation_from_source_snapshot(&latest_snapshot);
            latest_tree.gained_new_root_progress = gained_visible_root_progress(
                &baseline_visible_roots,
                &latest_tree.visible_root_post_numbers,
            );

            if policy.require_new_root_progress && latest_tree.gained_new_root_progress {
                return Ok(TopicLoadMoreOutcome {
                    source_snapshot: latest_snapshot,
                    tree_presentation: latest_tree,
                    chained_batches,
                    chained_posts,
                    stop_reason: TopicLoadMoreStopReason::GainedVisibleRootProgress,
                });
            }
            if latest_snapshot.source_exhausted {
                return Ok(TopicLoadMoreOutcome {
                    source_snapshot: latest_snapshot,
                    tree_presentation: latest_tree,
                    chained_batches,
                    chained_posts,
                    stop_reason: TopicLoadMoreStopReason::SourceExhausted,
                });
            }
            if chained_batches >= policy.max_auto_batches_per_gesture {
                return Ok(TopicLoadMoreOutcome {
                    source_snapshot: latest_snapshot,
                    tree_presentation: latest_tree,
                    chained_batches,
                    chained_posts,
                    stop_reason: TopicLoadMoreStopReason::MaxAutoBatchesReached,
                });
            }
            if chained_posts >= policy.max_auto_posts_per_gesture {
                return Ok(TopicLoadMoreOutcome {
                    source_snapshot: latest_snapshot,
                    tree_presentation: latest_tree,
                    chained_batches,
                    chained_posts,
                    stop_reason: TopicLoadMoreStopReason::MaxAutoPostsReached,
                });
            }

            let Some(next_cursor) = latest_snapshot.source_cursor.clone() else {
                return Ok(TopicLoadMoreOutcome {
                    source_snapshot: latest_snapshot,
                    tree_presentation: latest_tree,
                    chained_batches,
                    chained_posts,
                    stop_reason: TopicLoadMoreStopReason::SourceExhausted,
                });
            };
            current_cursor = next_cursor;
        }
    }

    pub async fn fetch_topic_posts(
        &self,
        topic_id: u64,
        post_ids: Vec<u64>,
    ) -> Result<Vec<TopicPost>, FireCoreError> {
        let requested_post_ids = ordered_unique_post_ids(post_ids);
        if requested_post_ids.is_empty() {
            return Ok(Vec::new());
        }

        let cached_posts =
            self.cached_topic_posts_for_active_source_session(topic_id, &requested_post_ids);
        let cached_post_ids = cached_posts
            .iter()
            .map(|post| post.id)
            .collect::<HashSet<_>>();
        let missing_post_ids = requested_post_ids
            .iter()
            .copied()
            .filter(|post_id| !cached_post_ids.contains(post_id))
            .collect::<Vec<_>>();
        if missing_post_ids.is_empty() {
            return Ok(topic_posts_for_requested_ids(
                &requested_post_ids,
                cached_posts,
                Vec::new(),
            ));
        }

        let path = format!("/t/{topic_id}/posts.json");
        let params = missing_post_ids
            .iter()
            .copied()
            .map(|post_id| ("post_ids[]", post_id.to_string()))
            .chain(std::iter::once(("include_suggested", "false".to_string())))
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
        let fetched_posts = post_stream.posts;
        self.cache_topic_posts_for_active_source_session(topic_id, &fetched_posts);
        if cached_posts.is_empty() {
            return Ok(fetched_posts);
        }
        Ok(topic_posts_for_requested_ids(
            &requested_post_ids,
            cached_posts,
            fetched_posts,
        ))
    }

    fn cached_topic_posts_for_active_source_session(
        &self,
        topic_id: u64,
        post_ids: &[u64],
    ) -> Vec<TopicPost> {
        let current_epoch = self.current_session_epoch();
        let runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
            return Vec::new();
        };
        if session.session_epoch != current_epoch {
            return Vec::new();
        }
        session.posts_for_ids(post_ids)
    }

    fn cache_topic_posts_for_active_source_session(&self, topic_id: u64, posts: &[TopicPost]) {
        if posts.is_empty() {
            return;
        }
        let current_epoch = self.current_session_epoch();
        let mut runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get_mut(&topic_id) else {
            return;
        };
        if session.session_epoch != current_epoch {
            return;
        }
        session.merge_posts(posts.iter().cloned());
    }

    async fn fetch_post_by_number(
        &self,
        topic_id: u64,
        post_number: u32,
    ) -> Result<TopicPost, FireCoreError> {
        let path = format!("/posts/by_number/{topic_id}/{post_number}.json");
        let traced = self.build_json_get_request("fetch post by number", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch post by number", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch post by number", trace_id, response)
            .await?;
        parse_topic_post_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "fetch post by number",
            source,
        })
    }

    pub async fn fetch_topic_ai_summary(
        &self,
        topic_id: u64,
        skip_age_check: bool,
    ) -> Result<Option<TopicAiSummary>, FireCoreError> {
        info!(topic_id, skip_age_check, "fetching topic AI summary");

        let path = format!("/discourse-ai/summarization/t/{topic_id}");
        let mut params = Vec::new();
        if skip_age_check {
            params.push(("skip_age_check", "true".to_string()));
        }

        let traced =
            self.build_json_get_request(FETCH_TOPIC_AI_SUMMARY_OPERATION, &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = match expect_success(
            self,
            FETCH_TOPIC_AI_SUMMARY_OPERATION,
            trace_id,
            response,
        )
        .await
        {
            Ok(response) => response,
            Err(FireCoreError::HttpStatus {
                status,
                body: _,
                operation: FETCH_TOPIC_AI_SUMMARY_OPERATION,
            }) if status == StatusCode::NOT_FOUND.as_u16()
                || status == StatusCode::FORBIDDEN.as_u16() =>
            {
                info!(topic_id, status, "topic AI summary is unavailable");
                return Ok(None);
            }
            Err(error) => return Err(error),
        };
        let value: Value = self
            .read_response_json(FETCH_TOPIC_AI_SUMMARY_OPERATION, trace_id, response)
            .await?;
        let summary = parse_topic_ai_summary_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: FETCH_TOPIC_AI_SUMMARY_OPERATION,
                source,
            }
        })?;
        info!(
            topic_id,
            has_summary = summary.is_some(),
            "topic AI summary fetched successfully"
        );
        Ok(summary)
    }

    fn clone_active_source_session(
        &self,
        topic_id: u64,
        session_id: u64,
        expected_next_stream_offset: Option<u32>,
        expected_last_loaded_post_id: Option<u64>,
    ) -> Result<TopicDetailSourceSession, FireCoreError> {
        let current_epoch = self.current_session_epoch();
        let runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
            return Err(FireCoreError::InvalidTopicSourceCursor {
                topic_id,
                session_id,
            });
        };
        if session.session_id != session_id || session.session_epoch != current_epoch {
            return Err(FireCoreError::InvalidTopicSourceCursor {
                topic_id,
                session_id,
            });
        }
        if let Some(expected_next_stream_offset) = expected_next_stream_offset {
            if session.next_stream_offset != expected_next_stream_offset as usize
                || session.last_loaded_post_id != expected_last_loaded_post_id
            {
                return Err(FireCoreError::InvalidTopicSourceCursor {
                    topic_id,
                    session_id,
                });
            }
        }
        Ok(session.clone())
    }

    async fn append_topic_source_batch(
        &self,
        cursor: TopicSourceCursor,
    ) -> Result<TopicDetailSourceAppend, FireCoreError> {
        let batch_size = normalized_topic_load_more_batch_size(cursor.batch_size);
        let session = self.clone_active_source_session(
            cursor.topic_id,
            cursor.session_id,
            Some(cursor.next_stream_offset),
            cursor.last_loaded_post_id,
        )?;
        if session.source_exhausted {
            return Ok(TopicDetailSourceAppend {
                appended_posts: Vec::new(),
                loaded_ranges: session.loaded_ranges,
                source_cursor: None,
                source_exhausted: true,
            });
        }

        let batch_start_offset = session.next_stream_offset;
        let batch_end_offset = session
            .next_stream_offset
            .saturating_add(usize::from(batch_size))
            .min(session.raw_stream_ids.len());
        let batch_post_ids = session.raw_stream_ids[batch_start_offset..batch_end_offset].to_vec();
        let previously_loaded_post_ids = batch_post_ids
            .iter()
            .copied()
            .filter(|post_id| session.posts_by_id.contains_key(post_id))
            .collect::<HashSet<_>>();
        let missing_post_ids = batch_post_ids
            .iter()
            .copied()
            .filter(|post_id| !previously_loaded_post_ids.contains(post_id))
            .collect::<Vec<_>>();
        let mut fetched_posts = Vec::new();
        for post_ids in missing_post_ids.chunks(TOPIC_POST_BATCH_SIZE) {
            fetched_posts.extend(
                self.fetch_topic_posts(cursor.topic_id, post_ids.to_vec())
                    .await?,
            );
        }
        let fetched_post_ids = fetched_posts
            .iter()
            .map(|post| post.id)
            .collect::<HashSet<_>>();
        let unavailable_post_ids = missing_post_ids
            .into_iter()
            .filter(|post_id| !fetched_post_ids.contains(post_id))
            .collect::<HashSet<_>>();

        let mut runtime = self
            .topic_detail_source
            .lock()
            .expect("topic detail source runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get_mut(&cursor.topic_id) else {
            return Err(FireCoreError::InvalidTopicSourceCursor {
                topic_id: cursor.topic_id,
                session_id: cursor.session_id,
            });
        };
        if session.session_id != cursor.session_id
            || session.session_epoch != self.current_session_epoch()
            || session.next_stream_offset != cursor.next_stream_offset as usize
            || session.last_loaded_post_id != cursor.last_loaded_post_id
        {
            return Err(FireCoreError::InvalidTopicSourceCursor {
                topic_id: cursor.topic_id,
                session_id: cursor.session_id,
            });
        }

        session.merge_posts(fetched_posts);
        session.mark_unavailable(unavailable_post_ids);
        session.recompute_loaded_state();
        let appended_posts = batch_post_ids
            .iter()
            .filter(|post_id| !previously_loaded_post_ids.contains(post_id))
            .filter_map(|post_id| session.posts_by_id.get(post_id).cloned())
            .collect::<Vec<_>>();
        Ok(TopicDetailSourceAppend {
            appended_posts,
            loaded_ranges: session.loaded_ranges.clone(),
            source_cursor: session.source_cursor(),
            source_exhausted: session.source_exhausted,
        })
    }

    async fn fetch_topic_detail_base(
        &self,
        query: TopicDetailQuery,
        include_thread_state: bool,
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
        if query.force_load {
            params.push(("forceLoad", "true".to_string()));
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
        let detail = raw.into_topic_detail(include_thread_state);
        ensure_requested_topic_detail(query.topic_id, detail.id)?;
        Ok(detail)
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
        detail.rebuild_timeline_entries();

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

fn topic_posts_for_requested_ids(
    requested_post_ids: &[u64],
    cached_posts: Vec<TopicPost>,
    fetched_posts: Vec<TopicPost>,
) -> Vec<TopicPost> {
    let mut posts_by_id: HashMap<u64, TopicPost> = cached_posts
        .into_iter()
        .chain(fetched_posts)
        .map(|post| (post.id, post))
        .collect();

    let mut ordered_posts = Vec::with_capacity(posts_by_id.len());
    for post_id in requested_post_ids {
        if let Some(post) = posts_by_id.remove(post_id) {
            ordered_posts.push(post);
        }
    }

    let mut trailing_posts: Vec<TopicPost> = posts_by_id.into_values().collect();
    trailing_posts.sort_by_key(|post| (post.post_number, post.id));
    ordered_posts.extend(trailing_posts);
    ordered_posts
}

impl TopicDetailSourceSession {
    fn new(init: TopicDetailSourceSessionInit) -> Self {
        let TopicDetailSourceSessionInit {
            session_epoch,
            header,
            body_post,
            focused_post_number,
            raw_stream_ids,
            cached_posts,
            unavailable_post_ids,
            load_more_policy,
        } = init;
        let mut posts_by_id = HashMap::new();
        let mut post_id_by_number = HashMap::new();

        post_id_by_number.insert(body_post.post_number, body_post.id);
        posts_by_id.insert(body_post.id, body_post.clone());

        for post in cached_posts {
            post_id_by_number.insert(post.post_number, post.id);
            posts_by_id.insert(post.id, post);
        }

        let mut session = Self {
            session_id: 0,
            session_epoch,
            header,
            body_post_id: body_post.id,
            body_post_number: body_post.post_number,
            focused_post_number,
            raw_stream_ids,
            posts_by_id,
            post_id_by_number,
            unavailable_post_ids,
            loaded_ranges: Vec::new(),
            next_stream_offset: 0,
            last_loaded_post_id: None,
            source_exhausted: false,
            load_more_policy,
        };
        session.recompute_loaded_state();
        session
    }

    fn with_session_id(mut self, session_id: u64) -> Self {
        self.session_id = session_id;
        self
    }

    fn posts_for_ids(&self, post_ids: &[u64]) -> Vec<TopicPost> {
        post_ids
            .iter()
            .filter_map(|post_id| self.posts_by_id.get(post_id).cloned())
            .collect()
    }

    fn merge_posts(&mut self, posts: impl IntoIterator<Item = TopicPost>) {
        for post in posts {
            self.unavailable_post_ids.remove(&post.id);
            self.post_id_by_number.insert(post.post_number, post.id);
            self.posts_by_id.insert(post.id, post);
        }
    }
    fn mark_unavailable(&mut self, post_ids: HashSet<u64>) {
        for post_id in post_ids {
            if !self.posts_by_id.contains_key(&post_id) {
                self.unavailable_post_ids.insert(post_id);
            }
        }
    }

    fn recompute_loaded_state(&mut self) {
        self.loaded_ranges.clear();
        let mut active_range_start: Option<usize> = None;
        let mut active_range_first_post_id: Option<u64> = None;

        for (offset, post_id) in self.raw_stream_ids.iter().copied().enumerate() {
            if self.is_satisfied_post_id(post_id) {
                if active_range_start.is_none() {
                    active_range_start = Some(offset);
                    active_range_first_post_id = Some(post_id);
                }
                continue;
            }

            if let Some(start_offset) = active_range_start.take() {
                self.loaded_ranges.push(TopicLoadedRange {
                    start_offset: start_offset as u32,
                    end_offset_exclusive: offset as u32,
                    first_post_id: active_range_first_post_id
                        .take()
                        .unwrap_or(self.raw_stream_ids[start_offset]),
                    last_post_id: self.raw_stream_ids[offset.saturating_sub(1)],
                });
            }
        }

        if let Some(start_offset) = active_range_start {
            self.loaded_ranges.push(TopicLoadedRange {
                start_offset: start_offset as u32,
                end_offset_exclusive: self.raw_stream_ids.len() as u32,
                first_post_id: active_range_first_post_id
                    .unwrap_or(self.raw_stream_ids[start_offset]),
                last_post_id: self
                    .raw_stream_ids
                    .last()
                    .copied()
                    .unwrap_or(self.body_post_id),
            });
        }

        self.next_stream_offset = self
            .raw_stream_ids
            .iter()
            .take_while(|post_id| self.is_satisfied_post_id(**post_id))
            .count();
        self.last_loaded_post_id = self
            .next_stream_offset
            .checked_sub(1)
            .and_then(|offset| self.raw_stream_ids.get(offset).copied());
        self.source_exhausted = self.next_stream_offset >= self.raw_stream_ids.len();
    }

    fn source_cursor(&self) -> Option<TopicSourceCursor> {
        (!self.source_exhausted).then_some(TopicSourceCursor {
            topic_id: self.header.topic_id,
            session_id: self.session_id,
            next_stream_offset: self.next_stream_offset as u32,
            last_loaded_post_id: self.last_loaded_post_id,
            batch_size: self.load_more_policy.batch_size,
        })
    }

    fn source_snapshot(&self) -> TopicDetailSourceSnapshot {
        TopicDetailSourceSnapshot {
            header: self.header.clone(),
            body: TopicBody {
                post: self.body_post(),
            },
            raw_stream_ids: self.raw_stream_ids.clone(),
            loaded_posts: self.ordered_loaded_posts(),
            loaded_ranges: self.loaded_ranges.clone(),
            source_cursor: self.source_cursor(),
            source_exhausted: self.source_exhausted,
            focused_post_number: self.focused_post_number,
        }
    }

    fn body_post(&self) -> TopicPost {
        self.posts_by_id
            .get(&self.body_post_id)
            .cloned()
            .or_else(|| {
                self.post_id_by_number
                    .get(&self.body_post_number)
                    .and_then(|post_id| self.posts_by_id.get(post_id))
                    .cloned()
            })
            .expect("topic detail source session missing body post")
    }

    fn ordered_loaded_posts(&self) -> Vec<TopicPost> {
        merge_topic_posts(
            &self.raw_stream_ids,
            self.posts_by_id.values().cloned().collect(),
            Vec::new(),
        )
    }

    fn is_satisfied_post_id(&self, post_id: u64) -> bool {
        self.posts_by_id.contains_key(&post_id) || self.unavailable_post_ids.contains(&post_id)
    }
}

fn build_topic_tree_presentation_from_query(
    query: TopicTreePresentationQuery,
) -> TopicTreePresentation {
    let mut ordered_posts = deduplicate_topic_posts_by_id(merge_topic_posts(
        &query.raw_stream_ids,
        query.loaded_posts,
        Vec::new(),
    ));
    if !ordered_posts
        .iter()
        .any(|post| post.id == query.body_post.id)
    {
        ordered_posts.push(query.body_post.clone());
        ordered_posts = deduplicate_topic_posts_by_id(merge_topic_posts(
            &query.raw_stream_ids,
            ordered_posts,
            Vec::new(),
        ));
    }

    let original_post = ordered_posts
        .iter()
        .find(|post| {
            post.id == query.body_post.id || post.post_number == query.body_post.post_number
        })
        .cloned()
        .unwrap_or(query.body_post);

    let mut posts_by_id = HashMap::new();
    let mut posts_by_number = HashMap::new();
    for post in ordered_posts {
        posts_by_number.insert(post.post_number, post.clone());
        posts_by_id.insert(post.id, post);
    }

    let stream_index_by_post_id = query
        .raw_stream_ids
        .iter()
        .enumerate()
        .map(|(index, post_id)| (*post_id, index))
        .collect::<HashMap<_, _>>();

    let mut children_by_parent = BTreeMap::<u32, Vec<u64>>::new();
    for post in posts_by_id.values() {
        if post.id == original_post.id {
            continue;
        }
        let parent_post_number = resolve_tree_attachment_parent_post_number(
            post,
            &posts_by_number,
            original_post.post_number,
        );
        children_by_parent
            .entry(parent_post_number)
            .or_default()
            .push(post.id);
    }

    for child_post_ids in children_by_parent.values_mut() {
        child_post_ids.sort_by_key(|post_id| {
            let stream_index = stream_index_by_post_id
                .get(post_id)
                .copied()
                .unwrap_or(usize::MAX);
            let post_key = posts_by_id
                .get(post_id)
                .map(|post| (post.post_number, post.id))
                .unwrap_or((u32::MAX, u64::MAX));
            (stream_index, post_key.0, post_key.1)
        });
    }

    let mut reply_rows = Vec::new();
    let mut visible_root_post_numbers = Vec::new();
    let mut visited = HashSet::new();
    let root_children = children_by_parent
        .get(&original_post.post_number)
        .cloned()
        .unwrap_or_default();
    append_tree_rows_preorder(
        &root_children,
        original_post.post_number,
        0,
        None,
        &posts_by_id,
        &children_by_parent,
        &mut visited,
        &mut reply_rows,
        &mut visible_root_post_numbers,
    );

    let mut orphan_post_ids = query
        .raw_stream_ids
        .iter()
        .copied()
        .filter(|post_id| {
            posts_by_id.contains_key(post_id)
                && *post_id != original_post.id
                && !visited.contains(post_id)
        })
        .collect::<Vec<_>>();
    orphan_post_ids.extend(
        posts_by_id
            .keys()
            .copied()
            .filter(|post_id| *post_id != original_post.id && !visited.contains(post_id)),
    );
    orphan_post_ids = ordered_unique_post_ids(orphan_post_ids);
    if !orphan_post_ids.is_empty() {
        append_tree_rows_preorder(
            &orphan_post_ids,
            original_post.post_number,
            0,
            None,
            &posts_by_id,
            &children_by_parent,
            &mut visited,
            &mut reply_rows,
            &mut visible_root_post_numbers,
        );
    }

    TopicTreePresentation {
        original_post_id: original_post.id,
        original_post_number: original_post.post_number,
        reply_rows,
        total_loaded_post_count: posts_by_id.len() as u32,
        visible_root_post_numbers,
        gained_new_root_progress: false,
    }
}

fn build_topic_tree_presentation_from_source_snapshot(
    snapshot: &TopicDetailSourceSnapshot,
) -> TopicTreePresentation {
    build_topic_tree_presentation_from_query(TopicTreePresentationQuery {
        body_post: snapshot.body.post.clone(),
        raw_stream_ids: snapshot.raw_stream_ids.clone(),
        loaded_posts: snapshot.loaded_posts.clone(),
        focused_post_number: snapshot.focused_post_number,
    })
}

fn topic_detail_source_cooked_byte_count(snapshot: &TopicDetailSourceSnapshot) -> usize {
    let mut seen_post_ids = HashSet::new();
    let mut total = 0usize;
    for post in std::iter::once(&snapshot.body.post).chain(snapshot.loaded_posts.iter()) {
        if seen_post_ids.insert(post.id) {
            total += post.cooked.len();
        }
    }
    total
}

#[allow(clippy::too_many_arguments)]
fn append_tree_rows_preorder(
    child_post_ids: &[u64],
    parent_post_number: u32,
    parent_depth: u16,
    current_root_post_number: Option<u32>,
    posts_by_id: &HashMap<u64, TopicPost>,
    children_by_parent: &BTreeMap<u32, Vec<u64>>,
    visited: &mut HashSet<u64>,
    reply_rows: &mut Vec<TopicTreeRow>,
    visible_root_post_numbers: &mut Vec<u32>,
) -> u32 {
    let mut descendant_total = 0_u32;

    for (sibling_index, child_post_id) in child_post_ids.iter().copied().enumerate() {
        if !visited.insert(child_post_id) {
            continue;
        }
        let Some(post) = posts_by_id.get(&child_post_id).cloned() else {
            continue;
        };
        let root_post_number = current_root_post_number.unwrap_or(post.post_number);
        if current_root_post_number.is_none()
            && visible_root_post_numbers.last().copied() != Some(root_post_number)
        {
            visible_root_post_numbers.push(root_post_number);
        }

        let row_index = reply_rows.len();
        let grand_children = children_by_parent
            .get(&post.post_number)
            .cloned()
            .unwrap_or_default();
        reply_rows.push(TopicTreeRow {
            post_id: post.id,
            post_number: post.post_number,
            root_post_number,
            parent_post_number: Some(parent_post_number),
            depth: parent_depth.saturating_add(1),
            preorder_index: row_index as u32,
            has_children: !grand_children.is_empty(),
            sibling_index: sibling_index as u16,
            is_last_sibling: sibling_index + 1 == child_post_ids.len(),
            descendant_count: 0,
        });
        let nested_descendant_count = append_tree_rows_preorder(
            &grand_children,
            post.post_number,
            parent_depth.saturating_add(1),
            Some(root_post_number),
            posts_by_id,
            children_by_parent,
            visited,
            reply_rows,
            visible_root_post_numbers,
        );
        reply_rows[row_index].descendant_count = nested_descendant_count;
        descendant_total = descendant_total.saturating_add(1 + nested_descendant_count);
    }

    descendant_total
}

fn resolve_tree_attachment_parent_post_number(
    post: &TopicPost,
    posts_by_number: &HashMap<u32, TopicPost>,
    body_post_number: u32,
) -> u32 {
    let Some(declared_parent) = normalized_reply_target(post.reply_to_post_number) else {
        return body_post_number;
    };
    if declared_parent == body_post_number || declared_parent == post.post_number {
        if declared_parent == post.post_number {
            debug!(
                post_number = post.post_number,
                declared_parent,
                body_post_number,
                "topic tree attachment parent fell back to body: post replies to itself"
            );
        }
        return body_post_number;
    }
    if !posts_by_number.contains_key(&declared_parent) {
        debug!(
            post_number = post.post_number,
            declared_parent,
            body_post_number,
            "topic tree attachment parent fell back to body: declared parent missing from loaded posts"
        );
        return body_post_number;
    }

    let mut current_parent = declared_parent;
    let mut visited = [0_u32; TOPIC_PARENT_HOP_LIMIT + 1];
    visited[0] = post.post_number;
    let mut visited_len = 1;
    for _ in 0..TOPIC_PARENT_HOP_LIMIT {
        if visited[..visited_len].contains(&current_parent) {
            debug!(
                post_number = post.post_number,
                declared_parent,
                current_parent,
                body_post_number,
                "topic tree attachment parent fell back to body: detected reply cycle"
            );
            return body_post_number;
        }
        visited[visited_len] = current_parent;
        visited_len += 1;
        let Some(parent_post) = posts_by_number.get(&current_parent) else {
            debug!(
                post_number = post.post_number,
                declared_parent,
                current_parent,
                body_post_number,
                "topic tree attachment parent fell back to body: ancestor disappeared from loaded posts"
            );
            return body_post_number;
        };
        match normalized_reply_target(parent_post.reply_to_post_number) {
            Some(next_parent) if next_parent == body_post_number => return declared_parent,
            Some(next_parent) if next_parent == parent_post.post_number => {
                debug!(
                    post_number = post.post_number,
                    declared_parent,
                    current_parent,
                    body_post_number,
                    "topic tree attachment parent fell back to body: ancestor replies to itself"
                );
                return body_post_number;
            }
            Some(next_parent) => {
                current_parent = next_parent;
            }
            None => return declared_parent,
        }
    }

    debug!(
        post_number = post.post_number,
        declared_parent,
        body_post_number,
        hop_limit = TOPIC_PARENT_HOP_LIMIT,
        "topic tree attachment parent fell back to body: exceeded parent hop limit"
    );
    body_post_number
}

fn normalized_reply_target(reply_to_post_number: Option<u32>) -> Option<u32> {
    reply_to_post_number.filter(|post_number| *post_number > 0)
}

fn missing_post_ids_from_ids(ordered_post_ids: &[u64], loaded_posts: &[TopicPost]) -> Vec<u64> {
    let loaded_post_ids: HashSet<u64> = loaded_posts.iter().map(|post| post.id).collect();
    ordered_post_ids
        .iter()
        .copied()
        .filter(|post_id| !loaded_post_ids.contains(post_id))
        .collect()
}

fn ordered_unique_post_ids(ids: Vec<u64>) -> Vec<u64> {
    let mut seen = HashSet::new();
    let mut result = Vec::with_capacity(ids.len());
    for post_id in ids {
        if post_id > 0 && seen.insert(post_id) {
            result.push(post_id);
        }
    }
    result
}

fn ensure_requested_topic_detail(
    requested_topic_id: u64,
    actual_topic_id: u64,
) -> Result<(), FireCoreError> {
    if requested_topic_id == actual_topic_id {
        return Ok(());
    }
    Err(FireCoreError::UnexpectedTopicDetail {
        requested_topic_id,
        actual_topic_id,
    })
}

fn normalized_topic_initial_batch_size(batch_size: u16) -> u16 {
    if batch_size == 0 {
        DEFAULT_TOPIC_INITIAL_BATCH_SIZE
    } else {
        batch_size
    }
}

fn normalized_topic_load_more_batch_size(batch_size: u16) -> u16 {
    if batch_size == 0 {
        DEFAULT_TOPIC_LOAD_MORE_BATCH_SIZE
    } else {
        batch_size
    }
}

fn normalized_topic_auto_batch_limit(limit: u8) -> u8 {
    if limit == 0 {
        DEFAULT_TOPIC_MAX_AUTO_BATCHES_PER_GESTURE
    } else {
        limit
    }
}

fn normalized_topic_auto_post_limit(limit: u16) -> u16 {
    if limit == 0 {
        DEFAULT_TOPIC_MAX_AUTO_POSTS_PER_GESTURE
    } else {
        limit
    }
}

fn gained_visible_root_progress(previous: &[u32], current: &[u32]) -> bool {
    let previous_roots = previous.iter().copied().collect::<HashSet<_>>();
    current
        .iter()
        .copied()
        .any(|post_number| !previous_roots.contains(&post_number))
}

fn deduplicate_topic_posts_by_id(posts: Vec<TopicPost>) -> Vec<TopicPost> {
    let mut seen_post_ids = HashSet::new();
    let mut deduplicated = Vec::with_capacity(posts.len());
    for post in posts {
        if seen_post_ids.insert(post.id) {
            deduplicated.push(post);
        }
    }
    deduplicated
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_topic_post(post_number: u32, reply_to_post_number: Option<u32>) -> TopicPost {
        TopicPost {
            id: u64::from(post_number),
            username: format!("user-{post_number}"),
            cooked: format!("<p>{post_number}</p>"),
            post_number,
            reply_to_post_number,
            ..TopicPost::default()
        }
    }

    #[test]
    fn resolve_tree_attachment_parent_falls_back_to_body_when_intermediate_is_missing() {
        let body_post = make_topic_post(1, None);
        let post = make_topic_post(5, Some(3));
        let posts_by_number = HashMap::from([
            (body_post.post_number, body_post.clone()),
            (post.post_number, post.clone()),
        ]);

        let attachment_parent = resolve_tree_attachment_parent_post_number(
            &post,
            &posts_by_number,
            body_post.post_number,
        );

        assert_eq!(attachment_parent, body_post.post_number);
    }

    #[test]
    fn resolve_tree_attachment_parent_falls_back_to_body_when_cycle_is_detected() {
        let body_post = make_topic_post(1, None);
        let post = make_topic_post(3, Some(4));
        let parent = make_topic_post(4, Some(3));
        let posts_by_number = HashMap::from([
            (body_post.post_number, body_post.clone()),
            (post.post_number, post.clone()),
            (parent.post_number, parent),
        ]);

        let attachment_parent = resolve_tree_attachment_parent_post_number(
            &post,
            &posts_by_number,
            body_post.post_number,
        );

        assert_eq!(attachment_parent, body_post.post_number);
    }

    #[test]
    fn resolve_tree_attachment_parent_falls_back_to_body_after_hop_limit() {
        let body_post = make_topic_post(1, None);
        let mut posts_by_number = HashMap::from([(body_post.post_number, body_post.clone())]);

        for post_number in 2..=36 {
            let reply_to_post_number = if post_number == 3 {
                Some(body_post.post_number)
            } else {
                Some(post_number - 1)
            };
            let post = make_topic_post(post_number, reply_to_post_number);
            posts_by_number.insert(post.post_number, post);
        }

        let post = posts_by_number
            .get(&36)
            .expect("missing deep descendant post");
        let attachment_parent = resolve_tree_attachment_parent_post_number(
            post,
            &posts_by_number,
            body_post.post_number,
        );

        assert_eq!(attachment_parent, body_post.post_number);
    }

    #[test]
    fn tree_presentation_preserves_parent_numbers_depths_and_root_grouping() {
        let body_post = make_topic_post(1, None);
        let root_post = make_topic_post(2, Some(1));
        let child_post = make_topic_post(3, Some(2));
        let grandchild_post = make_topic_post(4, Some(3));
        let second_root = make_topic_post(5, Some(1));

        let presentation = build_topic_tree_presentation_from_query(TopicTreePresentationQuery {
            body_post: body_post.clone(),
            raw_stream_ids: vec![
                body_post.id,
                root_post.id,
                child_post.id,
                grandchild_post.id,
                second_root.id,
            ],
            loaded_posts: vec![
                body_post.clone(),
                root_post.clone(),
                child_post.clone(),
                grandchild_post.clone(),
                second_root.clone(),
            ],
            focused_post_number: None,
        });

        assert_eq!(
            presentation
                .reply_rows
                .iter()
                .map(|row| row.post_id)
                .collect::<Vec<_>>(),
            vec![
                root_post.id,
                child_post.id,
                grandchild_post.id,
                second_root.id
            ]
        );
        assert_eq!(presentation.reply_rows[0].parent_post_number, Some(1));
        assert_eq!(presentation.reply_rows[0].depth, 1);
        assert_eq!(presentation.reply_rows[1].parent_post_number, Some(2));
        assert_eq!(presentation.reply_rows[1].depth, 2);
        assert_eq!(presentation.reply_rows[2].parent_post_number, Some(3));
        assert_eq!(presentation.reply_rows[2].depth, 3);
        assert_eq!(
            presentation
                .reply_rows
                .iter()
                .map(|row| row.root_post_number)
                .collect::<Vec<_>>(),
            vec![2, 2, 2, 5]
        );
        assert_eq!(presentation.visible_root_post_numbers, vec![2, 5]);
    }

    #[test]
    fn tree_presentation_reparents_missing_branch_to_body() {
        let body_post = make_topic_post(1, None);
        let orphan_root = make_topic_post(5, Some(99));
        let orphan_child = make_topic_post(6, Some(5));

        let presentation = build_topic_tree_presentation_from_query(TopicTreePresentationQuery {
            body_post: body_post.clone(),
            raw_stream_ids: vec![body_post.id, orphan_root.id, orphan_child.id],
            loaded_posts: vec![body_post.clone(), orphan_root.clone(), orphan_child.clone()],
            focused_post_number: None,
        });

        assert_eq!(
            presentation
                .reply_rows
                .iter()
                .map(|row| row.post_id)
                .collect::<Vec<_>>(),
            vec![orphan_root.id, orphan_child.id]
        );
        assert_eq!(presentation.reply_rows[0].parent_post_number, Some(1));
        assert_eq!(presentation.reply_rows[1].parent_post_number, Some(1));
        assert_eq!(presentation.reply_rows[0].depth, 1);
        assert_eq!(presentation.reply_rows[1].depth, 1);
        assert_eq!(
            presentation
                .reply_rows
                .iter()
                .map(|row| row.root_post_number)
                .collect::<Vec<_>>(),
            vec![5, 6]
        );
        assert_eq!(presentation.visible_root_post_numbers, vec![5, 6]);
    }

    #[test]
    fn ordered_unique_post_ids_drops_zeroes_and_duplicates() {
        assert_eq!(
            ordered_unique_post_ids(vec![0, 2, 2, 3, 0, 4, 3]),
            vec![2, 3, 4]
        );
    }

    #[test]
    fn source_session_tracks_contiguous_loaded_ranges_and_unavailable_post_ids() {
        let body_post = make_topic_post(1, None);
        let second_post = make_topic_post(2, Some(1));
        let fourth_post = make_topic_post(4, Some(1));
        let mut session = TopicDetailSourceSession::new(TopicDetailSourceSessionInit {
            session_epoch: 3,
            header: TopicHeader {
                topic_id: 42,
                ..TopicHeader::default()
            },
            body_post: body_post.clone(),
            focused_post_number: None,
            raw_stream_ids: vec![body_post.id, second_post.id, 3, fourth_post.id],
            cached_posts: vec![body_post.clone(), second_post.clone(), fourth_post.clone()],
            unavailable_post_ids: HashSet::new(),
            load_more_policy: TopicLoadMorePolicy {
                batch_size: 40,
                max_auto_batches_per_gesture: 3,
                max_auto_posts_per_gesture: 120,
                require_new_root_progress: true,
            },
        });

        assert_eq!(session.next_stream_offset, 2);
        assert_eq!(session.last_loaded_post_id, Some(2));
        assert_eq!(
            session
                .loaded_ranges
                .iter()
                .map(|range| (range.start_offset, range.end_offset_exclusive))
                .collect::<Vec<_>>(),
            vec![(0, 2), (3, 4)]
        );
        assert!(!session.source_exhausted);

        session.mark_unavailable(HashSet::from([3]));
        session.recompute_loaded_state();

        assert_eq!(session.next_stream_offset, 4);
        assert_eq!(session.last_loaded_post_id, Some(4));
        assert!(session.source_exhausted);
        assert_eq!(
            session
                .loaded_ranges
                .iter()
                .map(|range| (range.start_offset, range.end_offset_exclusive))
                .collect::<Vec<_>>(),
            vec![(0, 4)]
        );
    }

    #[test]
    fn gained_visible_root_progress_detects_new_root_post_numbers() {
        assert!(!gained_visible_root_progress(&[2, 5], &[2, 5]));
        assert!(gained_visible_root_progress(&[2, 5], &[2, 5, 8]));
    }
}
