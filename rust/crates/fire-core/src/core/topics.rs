use std::{
    collections::{BTreeMap, HashMap, HashSet},
    time::Instant,
};

use fire_models::{
    TopicAiSummary, TopicBody, TopicDetail, TopicDetailQuery, TopicHeader, TopicListKind,
    TopicListQuery, TopicListResponse, TopicPost, TopicPostStream, TopicResponseCursor,
    TopicResponsePage, TopicResponsePageQuery, TopicResponseRow, TopicScreen, TopicScreenQuery,
    TopicThread,
};
use futures_util::{stream, StreamExt, TryStreamExt};
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
const DEFAULT_TOPIC_ROOT_PAGE_SIZE: u16 = 10;
const DEFAULT_TOPIC_RESPONSE_ROW_PAGE_SIZE: u16 = 40;
const TOPIC_PARENT_HOP_LIMIT: usize = 32;
const ROOT_BRANCH_LOAD_CONCURRENCY: usize = 4;

#[derive(Default)]
pub(crate) struct FireTopicResponseRuntime {
    next_session_id: u64,
    sessions_by_topic_id: HashMap<u64, TopicResponseSession>,
}

#[derive(Clone)]
struct TopicResponseSession {
    session_id: u64,
    session_epoch: u64,
    header: TopicHeader,
    root_stream_ids: Vec<u64>,
    post_by_id: HashMap<u64, TopicPost>,
    post_id_by_number: HashMap<u32, u64>,
    branch_reply_ids_by_root_id: HashMap<u64, Vec<u64>>,
    branch_by_root_id: HashMap<u64, TopicBranchIndex>,
}

#[derive(Clone)]
struct TopicBranchIndex {
    root_post_number: u32,
    ordered_post_ids: Vec<u64>,
    node_by_post_id: HashMap<u64, TopicResponseNode>,
}

#[derive(Clone)]
struct TopicResponseNode {
    parent_post_number: Option<u32>,
    depth: u16,
    preorder_index: u32,
    child_post_ids: Vec<u64>,
    descendant_count: u32,
    sibling_index: u16,
    is_last_sibling: bool,
}

#[derive(Clone, Copy)]
struct BranchLoadRequest {
    root_post_id: u64,
    required_row_count: usize,
}

#[derive(Clone, Copy)]
struct TopicResponsePageLoadRequest {
    topic_id: u64,
    session_id: u64,
    start_offset: usize,
    branch_offset: usize,
    page_size: u16,
    cursor_page_size: u16,
    row_page_size: u16,
    focused_post_number: Option<u32>,
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

    pub async fn fetch_topic_screen(
        &self,
        query: TopicScreenQuery,
    ) -> Result<TopicScreen, FireCoreError> {
        let page_size = normalized_root_page_size(query.root_page_size);
        let row_page_size = normalized_response_row_page_size(query.row_page_size);
        let mut detail = self
            .fetch_topic_detail_base(
                TopicDetailQuery {
                    topic_id: query.topic_id,
                    post_number: None,
                    track_visit: query.track_visit,
                    force_load: query.force_load,
                    filter: None,
                    username_filters: None,
                    filter_top_level_replies: false,
                },
                false,
            )
            .await?;
        let top_level_detail = self
            .fetch_topic_detail_base(
                TopicDetailQuery {
                    topic_id: query.topic_id,
                    post_number: None,
                    track_visit: false,
                    force_load: false,
                    filter: None,
                    username_filters: None,
                    filter_top_level_replies: true,
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
        let merge_order = detail.post_stream.stream.clone();
        detail.post_stream.posts = merge_topic_posts(
            &merge_order,
            std::mem::take(&mut detail.post_stream.posts),
            top_level_detail.post_stream.posts,
        );
        let mut root_stream_ids = top_level_detail.post_stream.stream;
        root_stream_ids.retain(|post_id| *post_id != body_post.id);

        let focus_root_post = match query
            .target_post_number
            .filter(|post_number| *post_number > 1)
        {
            Some(target_post_number) => {
                let root_post_number = self
                    .resolve_focus_root_post_number(query.topic_id, target_post_number)
                    .await?;
                let root_post = if let Some(post) = detail
                    .post_stream
                    .posts
                    .iter()
                    .find(|post| post.post_number == root_post_number)
                    .cloned()
                {
                    post
                } else {
                    self.fetch_post_by_number(query.topic_id, root_post_number)
                        .await?
                };
                Some(root_post)
            }
            None => None,
        };
        let focus_root_index = focus_root_post.as_ref().and_then(|post| {
            root_stream_ids
                .iter()
                .position(|post_id| *post_id == post.id)
        });
        if let Some(focus_root_post) = focus_root_post
            .as_ref()
            .filter(|post| {
                !detail
                    .post_stream
                    .posts
                    .iter()
                    .any(|loaded| loaded.id == post.id)
            })
            .cloned()
        {
            detail.post_stream.posts.push(focus_root_post);
        }
        let initial_page_size =
            initial_topic_response_page_size(page_size, focus_root_index, root_stream_ids.len());
        let mut initial_root_ids = root_stream_ids
            .iter()
            .copied()
            .take(usize::from(initial_page_size))
            .collect::<Vec<_>>();
        if let Some(focus_root_id) = focus_root_post.as_ref().map(|post| post.id) {
            if !initial_root_ids.contains(&focus_root_id) {
                initial_root_ids.push(focus_root_id);
            }
        }
        let missing_root_ids =
            missing_post_ids_from_ids(&initial_root_ids, &detail.post_stream.posts);
        if !missing_root_ids.is_empty() {
            let fetched_roots = self
                .fetch_topic_posts(query.topic_id, missing_root_ids)
                .await?;
            detail.post_stream.posts = merge_topic_posts(
                &detail.post_stream.stream,
                std::mem::take(&mut detail.post_stream.posts),
                fetched_roots,
            );
        }

        let header = detail.header();
        let body = TopicBody {
            post: body_post.clone(),
        };
        let session = TopicResponseSession::new(
            self.current_session_epoch(),
            header.clone(),
            body_post,
            root_stream_ids,
            detail.post_stream.posts,
        );

        let session_id = {
            let mut runtime = self
                .topic_response
                .lock()
                .expect("topic response runtime lock poisoned");
            let next_session_id = runtime.next_session_id.saturating_add(1).max(1);
            runtime.next_session_id = next_session_id;
            runtime
                .sessions_by_topic_id
                .insert(query.topic_id, session.with_session_id(next_session_id));
            next_session_id
        };

        let response = self
            .load_topic_response_page(TopicResponsePageLoadRequest {
                topic_id: query.topic_id,
                session_id,
                start_offset: 0,
                branch_offset: 0,
                page_size: initial_page_size,
                cursor_page_size: page_size,
                row_page_size,
                focused_post_number: query
                    .target_post_number
                    .filter(|post_number| *post_number > 1),
            })
            .await?;

        Ok(TopicScreen {
            header,
            body,
            response,
        })
    }

    pub async fn fetch_topic_response_page(
        &self,
        query: TopicResponsePageQuery,
    ) -> Result<TopicResponsePage, FireCoreError> {
        self.load_topic_response_page(TopicResponsePageLoadRequest {
            topic_id: query.cursor.topic_id,
            session_id: query.cursor.session_id,
            start_offset: query.cursor.next_root_offset as usize,
            branch_offset: query.cursor.next_branch_offset as usize,
            page_size: normalized_root_page_size(query.cursor.page_size),
            cursor_page_size: normalized_root_page_size(query.cursor.page_size),
            row_page_size: normalized_response_row_page_size(query.cursor.row_page_size),
            focused_post_number: None,
        })
        .await
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
            self.cached_topic_posts_for_active_response_session(topic_id, &requested_post_ids);
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
        self.cache_topic_posts_for_active_response_session(topic_id, &fetched_posts);
        if cached_posts.is_empty() {
            return Ok(fetched_posts);
        }
        Ok(topic_posts_for_requested_ids(
            &requested_post_ids,
            cached_posts,
            fetched_posts,
        ))
    }

    fn cached_topic_posts_for_active_response_session(
        &self,
        topic_id: u64,
        post_ids: &[u64],
    ) -> Vec<TopicPost> {
        let current_epoch = self.current_session_epoch();
        let runtime = self
            .topic_response
            .lock()
            .expect("topic response runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
            return Vec::new();
        };
        if session.session_epoch != current_epoch {
            return Vec::new();
        }
        session.posts_for_ids(post_ids)
    }

    fn cache_topic_posts_for_active_response_session(&self, topic_id: u64, posts: &[TopicPost]) {
        if posts.is_empty() {
            return;
        }
        let current_epoch = self.current_session_epoch();
        let mut runtime = self
            .topic_response
            .lock()
            .expect("topic response runtime lock poisoned");
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

    async fn resolve_focus_root_post_number(
        &self,
        topic_id: u64,
        target_post_number: u32,
    ) -> Result<u32, FireCoreError> {
        let mut current_post_number = target_post_number;
        let mut visited = HashSet::new();

        for _ in 0..TOPIC_PARENT_HOP_LIMIT {
            if !visited.insert(current_post_number) {
                break;
            }
            let post = self
                .fetch_post_by_number(topic_id, current_post_number)
                .await?;
            match normalized_reply_target(post.reply_to_post_number) {
                Some(1) | None => return Ok(post.post_number),
                Some(parent_post_number) => {
                    current_post_number = parent_post_number;
                }
            }
        }

        Ok(current_post_number)
    }

    async fn load_topic_response_page(
        &self,
        request: TopicResponsePageLoadRequest,
    ) -> Result<TopicResponsePage, FireCoreError> {
        let TopicResponsePageLoadRequest {
            topic_id,
            session_id,
            start_offset,
            branch_offset,
            page_size,
            cursor_page_size,
            row_page_size,
            focused_post_number,
        } = request;

        loop {
            let roots_to_load = {
                let runtime = self
                    .topic_response
                    .lock()
                    .expect("topic response runtime lock poisoned");
                let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
                    return Err(FireCoreError::InvalidTopicResponseCursor {
                        topic_id,
                        session_id,
                    });
                };
                if session.session_id != session_id
                    || session.session_epoch != self.current_session_epoch()
                {
                    return Err(FireCoreError::InvalidTopicResponseCursor {
                        topic_id,
                        session_id,
                    });
                }

                roots_needed_for_response_page(
                    session,
                    start_offset,
                    branch_offset,
                    page_size,
                    row_page_size,
                )
            };

            if roots_to_load.is_empty() {
                let runtime = self
                    .topic_response
                    .lock()
                    .expect("topic response runtime lock poisoned");
                let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
                    return Err(FireCoreError::InvalidTopicResponseCursor {
                        topic_id,
                        session_id,
                    });
                };
                if session.session_id != session_id
                    || session.session_epoch != self.current_session_epoch()
                {
                    return Err(FireCoreError::InvalidTopicResponseCursor {
                        topic_id,
                        session_id,
                    });
                }
                return Ok(assemble_topic_response_page(
                    session,
                    start_offset,
                    branch_offset,
                    page_size,
                    cursor_page_size,
                    row_page_size,
                    focused_post_number,
                ));
            }

            stream::iter(roots_to_load.into_iter().map(|request| {
                self.load_root_branch_into_session(
                    topic_id,
                    session_id,
                    request.root_post_id,
                    request.required_row_count,
                )
            }))
            .buffer_unordered(ROOT_BRANCH_LOAD_CONCURRENCY)
            .try_collect::<Vec<_>>()
            .await?;
        }
    }

    async fn load_root_branch_into_session(
        &self,
        topic_id: u64,
        session_id: u64,
        root_post_id: u64,
        required_row_count: usize,
    ) -> Result<(), FireCoreError> {
        let started_at = Instant::now();
        let (root_post, cached_branch_post_ids, cached_descendant_ids) = {
            let runtime = self
                .topic_response
                .lock()
                .expect("topic response runtime lock poisoned");
            let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
                return Err(FireCoreError::InvalidTopicResponseCursor {
                    topic_id,
                    session_id,
                });
            };
            if session.session_id != session_id
                || session.session_epoch != self.current_session_epoch()
            {
                return Err(FireCoreError::InvalidTopicResponseCursor {
                    topic_id,
                    session_id,
                });
            }
            (
                session.post_by_id.get(&root_post_id).cloned(),
                session.post_by_id.keys().copied().collect::<HashSet<_>>(),
                session
                    .branch_reply_ids_by_root_id
                    .get(&root_post_id)
                    .cloned(),
            )
        };

        let root_post = match root_post {
            Some(post) => post,
            None => self
                .fetch_topic_posts(topic_id, vec![root_post_id])
                .await?
                .into_iter()
                .next()
                .ok_or(FireCoreError::InvalidTopicResponseCursor {
                    topic_id,
                    session_id,
                })?,
        };

        let descendant_ids = match cached_descendant_ids {
            Some(ids) => ids,
            None if root_post.reply_count > 0 => self.fetch_post_reply_ids(root_post.id).await?,
            None => Vec::new(),
        };
        let descendant_ids = ordered_unique_post_ids(descendant_ids)
            .into_iter()
            .filter(|post_id| *post_id != root_post.id)
            .collect::<Vec<_>>();
        let required_row_count = required_row_count
            .max(1)
            .min(descendant_ids.len().saturating_add(1));
        let descendant_budget = required_row_count.saturating_sub(1);
        let descendant_ids_for_index = descendant_ids
            .iter()
            .copied()
            .take(descendant_budget)
            .collect::<Vec<_>>();
        let missing_descendant_ids = descendant_ids
            .iter()
            .copied()
            .take(descendant_budget)
            .filter(|post_id| !cached_branch_post_ids.contains(post_id))
            .collect::<Vec<_>>();

        let mut descendant_posts = Vec::new();
        for post_ids in missing_descendant_ids.chunks(TOPIC_POST_BATCH_SIZE) {
            descendant_posts.extend(self.fetch_topic_posts(topic_id, post_ids.to_vec()).await?);
        }

        let cached_branch_posts = {
            let runtime = self
                .topic_response
                .lock()
                .expect("topic response runtime lock poisoned");
            let Some(session) = runtime.sessions_by_topic_id.get(&topic_id) else {
                return Err(FireCoreError::InvalidTopicResponseCursor {
                    topic_id,
                    session_id,
                });
            };
            if session.session_id != session_id
                || session.session_epoch != self.current_session_epoch()
            {
                return Err(FireCoreError::InvalidTopicResponseCursor {
                    topic_id,
                    session_id,
                });
            }

            let mut branch_posts = Vec::with_capacity(descendant_ids_for_index.len() + 1);
            branch_posts.push(root_post.clone());
            branch_posts.extend(
                descendant_ids_for_index
                    .iter()
                    .filter_map(|post_id| session.post_by_id.get(post_id).cloned()),
            );
            branch_posts
        };
        let mut branch_posts = cached_branch_posts;
        branch_posts.extend(descendant_posts.clone());
        let branch_index = build_branch_index(root_post.clone(), branch_posts);

        let mut runtime = self
            .topic_response
            .lock()
            .expect("topic response runtime lock poisoned");
        let Some(session) = runtime.sessions_by_topic_id.get_mut(&topic_id) else {
            return Err(FireCoreError::InvalidTopicResponseCursor {
                topic_id,
                session_id,
            });
        };
        if session.session_id != session_id || session.session_epoch != self.current_session_epoch()
        {
            return Err(FireCoreError::InvalidTopicResponseCursor {
                topic_id,
                session_id,
            });
        }
        session
            .post_id_by_number
            .insert(root_post.post_number, root_post.id);
        session.post_by_id.insert(root_post.id, root_post);
        for post in descendant_posts {
            session.post_id_by_number.insert(post.post_number, post.id);
            session.post_by_id.insert(post.id, post);
        }
        session
            .branch_reply_ids_by_root_id
            .insert(root_post_id, descendant_ids.clone());
        session.branch_by_root_id.insert(root_post_id, branch_index);
        info!(
            topic_id,
            session_id,
            root_post_id,
            descendant_count = descendant_ids.len(),
            fetched_descendant_count = missing_descendant_ids.len(),
            duration_ms = started_at.elapsed().as_millis() as u64,
            "loaded topic response root branch"
        );
        Ok(())
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
        Ok(raw.into_topic_detail(include_thread_state))
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

impl TopicResponseSession {
    fn new(
        session_epoch: u64,
        header: TopicHeader,
        body_post: TopicPost,
        root_stream_ids: Vec<u64>,
        cached_posts: Vec<TopicPost>,
    ) -> Self {
        let mut post_by_id = HashMap::new();
        let mut post_id_by_number = HashMap::new();

        post_id_by_number.insert(body_post.post_number, body_post.id);
        post_by_id.insert(body_post.id, body_post.clone());

        for post in cached_posts {
            post_id_by_number.insert(post.post_number, post.id);
            post_by_id.insert(post.id, post);
        }

        Self {
            session_id: 0,
            session_epoch,
            header,
            root_stream_ids,
            post_by_id,
            post_id_by_number,
            branch_reply_ids_by_root_id: HashMap::new(),
            branch_by_root_id: HashMap::new(),
        }
    }

    fn with_session_id(mut self, session_id: u64) -> Self {
        self.session_id = session_id;
        self
    }

    fn posts_for_ids(&self, post_ids: &[u64]) -> Vec<TopicPost> {
        post_ids
            .iter()
            .filter_map(|post_id| self.post_by_id.get(post_id).cloned())
            .collect()
    }

    fn merge_posts(&mut self, posts: impl IntoIterator<Item = TopicPost>) {
        for post in posts {
            self.post_id_by_number.insert(post.post_number, post.id);
            self.post_by_id.insert(post.id, post);
        }
    }
}

fn roots_needed_for_response_page(
    session: &TopicResponseSession,
    start_offset: usize,
    branch_offset: usize,
    page_size: u16,
    row_page_size: u16,
) -> Vec<BranchLoadRequest> {
    let row_limit = usize::from(row_page_size).max(1);
    let root_limit = usize::from(page_size).max(1);
    let mut requests = Vec::new();
    let mut remaining_rows = row_limit;
    let mut current_root_offset = start_offset;
    let mut current_branch_offset = branch_offset;
    let mut considered_roots = 0_usize;

    while remaining_rows > 0
        && current_root_offset < session.root_stream_ids.len()
        && considered_roots < root_limit
    {
        let root_post_id = session.root_stream_ids[current_root_offset];
        let loaded_rows = session
            .branch_by_root_id
            .get(&root_post_id)
            .map(|branch| branch.ordered_post_ids.len())
            .unwrap_or(0);
        let total_rows = session
            .branch_reply_ids_by_root_id
            .get(&root_post_id)
            .map(|ids| ids.len().saturating_add(1));
        let required_rows = current_branch_offset.saturating_add(remaining_rows);
        let required_loaded_rows = total_rows
            .map(|total| required_rows.min(total))
            .unwrap_or(required_rows.max(1));

        if loaded_rows < required_loaded_rows {
            requests.push(BranchLoadRequest {
                root_post_id,
                required_row_count: required_loaded_rows,
            });
            break;
        }

        let available_rows = loaded_rows.saturating_sub(current_branch_offset);
        let consumed_rows = available_rows.min(remaining_rows);
        remaining_rows = remaining_rows.saturating_sub(consumed_rows);

        let branch_total_rows = total_rows.unwrap_or(loaded_rows);
        if current_branch_offset.saturating_add(consumed_rows) < branch_total_rows {
            break;
        }

        current_root_offset = current_root_offset.saturating_add(1);
        current_branch_offset = 0;
        considered_roots = considered_roots.saturating_add(1);
    }

    requests
}

fn assemble_topic_response_page(
    session: &TopicResponseSession,
    start_offset: usize,
    branch_offset: usize,
    page_size: u16,
    cursor_page_size: u16,
    row_page_size: u16,
    focused_post_number: Option<u32>,
) -> TopicResponsePage {
    let row_limit = usize::from(row_page_size).max(1);
    let root_limit = usize::from(page_size).max(1);
    let mut rows = Vec::new();
    let mut current_root_offset = start_offset;
    let mut current_branch_offset = branch_offset;
    let mut considered_roots = 0_usize;
    let mut next_root_offset = start_offset;
    let mut next_branch_offset = branch_offset;

    while rows.len() < row_limit
        && current_root_offset < session.root_stream_ids.len()
        && considered_roots < root_limit
    {
        let root_post_id = session.root_stream_ids[current_root_offset];
        let Some(branch) = session.branch_by_root_id.get(&root_post_id) else {
            break;
        };
        let total_branch_rows = session
            .branch_reply_ids_by_root_id
            .get(&root_post_id)
            .map(|ids| ids.len().saturating_add(1))
            .unwrap_or(branch.ordered_post_ids.len());
        let mut branch_index = current_branch_offset;
        while rows.len() < row_limit && branch_index < branch.ordered_post_ids.len() {
            let post_id = branch.ordered_post_ids[branch_index];
            let Some(node) = branch.node_by_post_id.get(&post_id) else {
                branch_index = branch_index.saturating_add(1);
                continue;
            };
            let Some(post) = session.post_by_id.get(&post_id).cloned() else {
                branch_index = branch_index.saturating_add(1);
                continue;
            };
            rows.push(TopicResponseRow {
                post,
                root_post_number: branch.root_post_number,
                parent_post_number: node.parent_post_number,
                depth: node.depth,
                preorder_index: node.preorder_index,
                has_children: !node.child_post_ids.is_empty(),
                descendant_count: node.descendant_count,
                sibling_index: node.sibling_index,
                is_last_sibling: node.is_last_sibling,
            });
            branch_index = branch_index.saturating_add(1);
        }

        if branch_index < total_branch_rows {
            next_root_offset = current_root_offset;
            next_branch_offset = branch_index;
            break;
        }

        current_root_offset = current_root_offset.saturating_add(1);
        current_branch_offset = 0;
        considered_roots = considered_roots.saturating_add(1);
        next_root_offset = current_root_offset;
        next_branch_offset = 0;
    }

    let next_cursor =
        (next_root_offset < session.root_stream_ids.len()).then_some(TopicResponseCursor {
            topic_id: session.header.topic_id,
            session_id: session.session_id,
            next_root_offset: next_root_offset as u32,
            next_branch_offset: next_branch_offset as u32,
            page_size: cursor_page_size,
            row_page_size,
        });

    TopicResponsePage {
        rows,
        next_cursor,
        total_root_count: session.root_stream_ids.len() as u32,
        loaded_root_count: next_root_offset
            .saturating_add(usize::from(next_branch_offset > 0))
            .min(session.root_stream_ids.len()) as u32,
        total_response_count: session.header.reply_count,
        focused_post_number,
    }
}

fn build_branch_index(root_post: TopicPost, branch_posts: Vec<TopicPost>) -> TopicBranchIndex {
    let started_at = Instant::now();

    let mut posts_by_id = HashMap::new();
    let mut posts_by_number = HashMap::new();
    for post in deduplicate_topic_posts_by_id(branch_posts) {
        posts_by_number.insert(post.post_number, post.clone());
        posts_by_id.insert(post.id, post);
    }
    posts_by_number.insert(root_post.post_number, root_post.clone());
    posts_by_id.insert(root_post.id, root_post.clone());

    let root_post_number = root_post.post_number;
    let root_post_id = root_post.id;
    let root_parent_post_number = normalized_reply_target(root_post.reply_to_post_number);
    let mut children_by_parent = BTreeMap::<u32, Vec<u64>>::new();

    for post in posts_by_id.values() {
        if post.id == root_post_id {
            continue;
        }

        let attachment_parent =
            resolve_attachment_parent_post_number(post, &posts_by_number, root_post_number);
        children_by_parent
            .entry(attachment_parent)
            .or_default()
            .push(post.id);
    }

    for child_post_ids in children_by_parent.values_mut() {
        child_post_ids.sort_by_key(|post_id| {
            posts_by_id
                .get(post_id)
                .map(|post| (post.post_number, post.id))
                .unwrap_or((u32::MAX, u64::MAX))
        });
    }

    let mut ordered_post_ids = Vec::new();
    let mut node_by_post_id = HashMap::new();

    node_by_post_id.insert(
        root_post_id,
        TopicResponseNode {
            parent_post_number: root_parent_post_number,
            depth: 1,
            preorder_index: 0,
            child_post_ids: Vec::new(),
            descendant_count: 0,
            sibling_index: 0,
            is_last_sibling: true,
        },
    );

    let mut visited = HashSet::from([root_post_id]);
    ordered_post_ids.push(root_post_id);
    let mut preorder_counter = 1_u32;
    let root_children = children_by_parent
        .get(&root_post_number)
        .cloned()
        .unwrap_or_default();
    let root_descendant_count = append_children_preorder(
        &root_children,
        root_post_number,
        1,
        &posts_by_id,
        &children_by_parent,
        &mut visited,
        &mut ordered_post_ids,
        &mut node_by_post_id,
        &mut preorder_counter,
    );
    if let Some(root_node) = node_by_post_id.get_mut(&root_post_id) {
        root_node.child_post_ids = root_children;
        root_node.descendant_count = root_descendant_count;
    }

    let orphan_ids = posts_by_id
        .keys()
        .copied()
        .filter(|post_id| !visited.contains(post_id))
        .collect::<Vec<_>>();
    if !orphan_ids.is_empty() {
        let appended_count = append_children_preorder(
            &orphan_ids,
            root_post_number,
            1,
            &posts_by_id,
            &children_by_parent,
            &mut visited,
            &mut ordered_post_ids,
            &mut node_by_post_id,
            &mut preorder_counter,
        );
        if let Some(root_node) = node_by_post_id.get_mut(&root_post_id) {
            root_node.child_post_ids.extend(orphan_ids);
            root_node.descendant_count = root_node.descendant_count.saturating_add(appended_count);
        }
    }

    let branch_index = TopicBranchIndex {
        root_post_number,
        ordered_post_ids,
        node_by_post_id,
    };

    info!(
        root_post_id = root_post_id,
        root_post_number,
        post_count = branch_index.ordered_post_ids.len(),
        duration_ms = started_at.elapsed().as_millis() as u64,
        "built topic response branch index"
    );

    branch_index
}

#[allow(clippy::too_many_arguments)]
fn append_children_preorder(
    child_post_ids: &[u64],
    parent_post_number: u32,
    parent_depth: u16,
    posts_by_id: &HashMap<u64, TopicPost>,
    children_by_parent: &BTreeMap<u32, Vec<u64>>,
    visited: &mut HashSet<u64>,
    ordered_post_ids: &mut Vec<u64>,
    node_by_post_id: &mut HashMap<u64, TopicResponseNode>,
    preorder_counter: &mut u32,
) -> u32 {
    let mut descendant_total = 0_u32;

    for (sibling_index, child_post_id) in child_post_ids.iter().copied().enumerate() {
        if !visited.insert(child_post_id) {
            continue;
        }
        let Some(post) = posts_by_id.get(&child_post_id) else {
            continue;
        };
        let depth = parent_depth.saturating_add(1);
        let preorder_index = *preorder_counter;
        *preorder_counter = preorder_counter.saturating_add(1);
        ordered_post_ids.push(child_post_id);

        let grand_children = children_by_parent
            .get(&post.post_number)
            .cloned()
            .unwrap_or_default();
        let nested_descendant_count = append_children_preorder(
            &grand_children,
            post.post_number,
            depth,
            posts_by_id,
            children_by_parent,
            visited,
            ordered_post_ids,
            node_by_post_id,
            preorder_counter,
        );

        node_by_post_id.insert(
            child_post_id,
            TopicResponseNode {
                parent_post_number: Some(parent_post_number),
                depth,
                preorder_index,
                child_post_ids: grand_children,
                descendant_count: nested_descendant_count,
                sibling_index: sibling_index as u16,
                is_last_sibling: sibling_index + 1 == child_post_ids.len(),
            },
        );
        descendant_total = descendant_total.saturating_add(1 + nested_descendant_count);
    }

    descendant_total
}

fn resolve_attachment_parent_post_number(
    post: &TopicPost,
    posts_by_number: &HashMap<u32, TopicPost>,
    root_post_number: u32,
) -> u32 {
    let Some(declared_parent) = normalized_reply_target(post.reply_to_post_number) else {
        return root_post_number;
    };
    if declared_parent == root_post_number || declared_parent == post.post_number {
        if declared_parent == post.post_number {
            debug!(
                post_number = post.post_number,
                declared_parent,
                root_post_number,
                "topic response attachment parent fell back to root: post replies to itself"
            );
        }
        return root_post_number;
    }
    if !posts_by_number.contains_key(&declared_parent) {
        debug!(
            post_number = post.post_number,
            declared_parent,
            root_post_number,
            "topic response attachment parent fell back to root: declared parent missing from branch"
        );
        return root_post_number;
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
                root_post_number,
                "topic response attachment parent fell back to root: detected reply cycle"
            );
            return root_post_number;
        }
        visited[visited_len] = current_parent;
        visited_len += 1;
        let Some(parent_post) = posts_by_number.get(&current_parent) else {
            debug!(
                post_number = post.post_number,
                declared_parent,
                current_parent,
                root_post_number,
                "topic response attachment parent fell back to root: ancestor disappeared from branch"
            );
            return root_post_number;
        };
        match normalized_reply_target(parent_post.reply_to_post_number) {
            Some(next_parent) if next_parent == root_post_number => return declared_parent,
            Some(next_parent) if next_parent == parent_post.post_number => {
                debug!(
                    post_number = post.post_number,
                    declared_parent,
                    current_parent,
                    root_post_number,
                    "topic response attachment parent fell back to root: ancestor replies to itself"
                );
                return root_post_number;
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
        root_post_number,
        hop_limit = TOPIC_PARENT_HOP_LIMIT,
        "topic response attachment parent fell back to root: exceeded parent hop limit"
    );
    root_post_number
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

fn normalized_root_page_size(page_size: u16) -> u16 {
    if page_size == 0 {
        DEFAULT_TOPIC_ROOT_PAGE_SIZE
    } else {
        page_size
    }
}

fn normalized_response_row_page_size(page_size: u16) -> u16 {
    if page_size == 0 {
        DEFAULT_TOPIC_RESPONSE_ROW_PAGE_SIZE
    } else {
        page_size
    }
}

fn initial_topic_response_page_size(
    page_size: u16,
    _focus_root_index: Option<usize>,
    _total_root_count: usize,
) -> u16 {
    page_size
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
    fn resolve_attachment_parent_falls_back_to_root_when_intermediate_is_missing() {
        let root_post = make_topic_post(2, Some(1));
        let post = make_topic_post(5, Some(3));
        let posts_by_number = HashMap::from([
            (root_post.post_number, root_post.clone()),
            (post.post_number, post.clone()),
        ]);

        let attachment_parent =
            resolve_attachment_parent_post_number(&post, &posts_by_number, root_post.post_number);

        assert_eq!(attachment_parent, root_post.post_number);
    }

    #[test]
    fn resolve_attachment_parent_falls_back_to_root_when_cycle_is_detected() {
        let root_post = make_topic_post(2, Some(1));
        let post = make_topic_post(3, Some(4));
        let parent = make_topic_post(4, Some(3));
        let posts_by_number = HashMap::from([
            (root_post.post_number, root_post.clone()),
            (post.post_number, post.clone()),
            (parent.post_number, parent),
        ]);

        let attachment_parent =
            resolve_attachment_parent_post_number(&post, &posts_by_number, root_post.post_number);

        assert_eq!(attachment_parent, root_post.post_number);
    }

    #[test]
    fn resolve_attachment_parent_falls_back_to_root_after_hop_limit() {
        let root_post = make_topic_post(2, Some(1));
        let mut posts_by_number = HashMap::from([(root_post.post_number, root_post.clone())]);

        for post_number in 3..=37 {
            let reply_to_post_number = if post_number == 3 {
                Some(root_post.post_number)
            } else {
                Some(post_number - 1)
            };
            let post = make_topic_post(post_number, reply_to_post_number);
            posts_by_number.insert(post.post_number, post);
        }

        let post = posts_by_number
            .get(&37)
            .expect("missing deep descendant post");
        let attachment_parent =
            resolve_attachment_parent_post_number(post, &posts_by_number, root_post.post_number);

        assert_eq!(attachment_parent, root_post.post_number);
    }

    #[test]
    fn build_branch_index_preserves_visual_parent_numbers_and_depths() {
        let root_post = make_topic_post(2, Some(1));
        let child_post = make_topic_post(3, Some(2));
        let grandchild_post = make_topic_post(4, Some(3));

        let branch = build_branch_index(
            root_post.clone(),
            vec![
                root_post.clone(),
                child_post.clone(),
                grandchild_post.clone(),
            ],
        );

        assert_eq!(
            branch.ordered_post_ids,
            vec![root_post.id, child_post.id, grandchild_post.id]
        );

        let root_node = branch
            .node_by_post_id
            .get(&root_post.id)
            .expect("missing root node");
        assert_eq!(root_node.parent_post_number, Some(1));
        assert_eq!(root_node.depth, 1);

        let child_node = branch
            .node_by_post_id
            .get(&child_post.id)
            .expect("missing child node");
        assert_eq!(child_node.parent_post_number, Some(root_post.post_number));
        assert_eq!(child_node.depth, 2);

        let grandchild_node = branch
            .node_by_post_id
            .get(&grandchild_post.id)
            .expect("missing grandchild node");
        assert_eq!(
            grandchild_node.parent_post_number,
            Some(child_post.post_number)
        );
        assert_eq!(grandchild_node.depth, 3);
    }

    #[test]
    fn append_children_preorder_reparents_orphan_roots_to_visual_parent() {
        let root_post = make_topic_post(2, Some(1));
        let orphan_root = make_topic_post(5, Some(99));
        let orphan_child = make_topic_post(6, Some(5));
        let posts_by_id = HashMap::from([
            (root_post.id, root_post.clone()),
            (orphan_root.id, orphan_root.clone()),
            (orphan_child.id, orphan_child.clone()),
        ]);
        let children_by_parent = BTreeMap::from([(orphan_root.post_number, vec![orphan_child.id])]);
        let mut visited = HashSet::from([root_post.id]);
        let mut ordered_post_ids = vec![root_post.id];
        let mut node_by_post_id = HashMap::from([(
            root_post.id,
            TopicResponseNode {
                parent_post_number: Some(1),
                depth: 1,
                preorder_index: 0,
                child_post_ids: Vec::new(),
                descendant_count: 0,
                sibling_index: 0,
                is_last_sibling: true,
            },
        )]);
        let mut preorder_counter = 1;

        let appended_count = append_children_preorder(
            &[orphan_root.id],
            root_post.post_number,
            1,
            &posts_by_id,
            &children_by_parent,
            &mut visited,
            &mut ordered_post_ids,
            &mut node_by_post_id,
            &mut preorder_counter,
        );

        assert_eq!(appended_count, 2);
        assert_eq!(
            ordered_post_ids,
            vec![root_post.id, orphan_root.id, orphan_child.id]
        );

        let orphan_root_node = node_by_post_id
            .get(&orphan_root.id)
            .expect("missing orphan root node");
        assert_eq!(
            orphan_root_node.parent_post_number,
            Some(root_post.post_number)
        );
        assert_eq!(orphan_root_node.depth, 2);

        let orphan_child_node = node_by_post_id
            .get(&orphan_child.id)
            .expect("missing orphan child node");
        assert_eq!(
            orphan_child_node.parent_post_number,
            Some(orphan_root.post_number)
        );
        assert_eq!(orphan_child_node.depth, 3);
    }

    #[test]
    fn ordered_unique_post_ids_drops_zeroes_and_duplicates() {
        assert_eq!(
            ordered_unique_post_ids(vec![0, 2, 2, 3, 0, 4, 3]),
            vec![2, 3, 4]
        );
    }

    #[test]
    fn initial_topic_response_page_size_stays_on_requested_root_page() {
        assert_eq!(initial_topic_response_page_size(10, None, 100), 10);
        assert_eq!(initial_topic_response_page_size(10, Some(3), 100), 10);
        assert_eq!(initial_topic_response_page_size(10, Some(12), 100), 10);
        assert_eq!(initial_topic_response_page_size(10, Some(12), 8), 10);
    }

    #[test]
    fn assemble_topic_response_page_paginates_by_root_branch_and_row_budget() {
        let body_post = make_topic_post(1, None);
        let first_root = make_topic_post(2, Some(1));
        let first_child = make_topic_post(3, Some(2));
        let second_root = make_topic_post(10, Some(1));
        let first_branch = build_branch_index(
            first_root.clone(),
            vec![first_root.clone(), first_child.clone()],
        );
        let second_branch = build_branch_index(second_root.clone(), vec![second_root.clone()]);
        let session = TopicResponseSession {
            session_id: 7,
            session_epoch: 1,
            header: TopicHeader {
                topic_id: 42,
                reply_count: 3,
                ..TopicHeader::default()
            },
            root_stream_ids: vec![first_root.id, second_root.id],
            post_by_id: HashMap::from([
                (body_post.id, body_post),
                (first_root.id, first_root.clone()),
                (first_child.id, first_child.clone()),
                (second_root.id, second_root.clone()),
            ]),
            post_id_by_number: HashMap::from([
                (1, 1),
                (first_root.post_number, first_root.id),
                (first_child.post_number, first_child.id),
                (second_root.post_number, second_root.id),
            ]),
            branch_reply_ids_by_root_id: HashMap::from([
                (first_root.id, vec![first_child.id]),
                (second_root.id, Vec::new()),
            ]),
            branch_by_root_id: HashMap::from([
                (first_root.id, first_branch),
                (second_root.id, second_branch),
            ]),
        };

        let page =
            assemble_topic_response_page(&session, 0, 0, 1, 1, 40, Some(first_child.post_number));

        assert_eq!(page.rows.len(), 2);
        assert_eq!(page.rows[0].post.post_number, first_root.post_number);
        assert_eq!(page.rows[0].depth, 1);
        assert_eq!(page.rows[1].post.post_number, first_child.post_number);
        assert_eq!(
            page.rows[1].parent_post_number,
            Some(first_root.post_number)
        );
        assert_eq!(page.rows[1].depth, 2);
        assert_eq!(page.total_root_count, 2);
        assert_eq!(page.loaded_root_count, 1);
        assert_eq!(page.focused_post_number, Some(first_child.post_number));
        assert_eq!(
            page.next_cursor,
            Some(TopicResponseCursor {
                topic_id: 42,
                session_id: 7,
                next_root_offset: 1,
                next_branch_offset: 0,
                page_size: 1,
                row_page_size: 40,
            })
        );
    }

    #[test]
    fn assemble_topic_response_page_continues_large_branch_by_row_cursor() {
        let root = make_topic_post(2, Some(1));
        let first_child = make_topic_post(3, Some(2));
        let second_child = make_topic_post(4, Some(2));
        let third_child = make_topic_post(5, Some(2));
        let branch = build_branch_index(
            root.clone(),
            vec![
                root.clone(),
                first_child.clone(),
                second_child.clone(),
                third_child.clone(),
            ],
        );
        let session = TopicResponseSession {
            session_id: 9,
            session_epoch: 1,
            header: TopicHeader {
                topic_id: 77,
                reply_count: 4,
                ..TopicHeader::default()
            },
            root_stream_ids: vec![root.id],
            post_by_id: HashMap::from([
                (root.id, root.clone()),
                (first_child.id, first_child.clone()),
                (second_child.id, second_child.clone()),
                (third_child.id, third_child.clone()),
            ]),
            post_id_by_number: HashMap::from([
                (root.post_number, root.id),
                (first_child.post_number, first_child.id),
                (second_child.post_number, second_child.id),
                (third_child.post_number, third_child.id),
            ]),
            branch_reply_ids_by_root_id: HashMap::from([(
                root.id,
                vec![first_child.id, second_child.id, third_child.id],
            )]),
            branch_by_root_id: HashMap::from([(root.id, branch)]),
        };

        let page = assemble_topic_response_page(&session, 0, 0, 10, 10, 2, None);

        assert_eq!(
            page.rows
                .iter()
                .map(|row| row.post.post_number)
                .collect::<Vec<_>>(),
            vec![root.post_number, first_child.post_number]
        );
        assert_eq!(
            page.next_cursor,
            Some(TopicResponseCursor {
                topic_id: 77,
                session_id: 9,
                next_root_offset: 0,
                next_branch_offset: 2,
                page_size: 10,
                row_page_size: 2,
            })
        );
    }

    #[test]
    fn build_branch_index_deduplicates_duplicate_post_ids() {
        let root_post = make_topic_post(2, Some(1));
        let child_post = make_topic_post(3, Some(2));

        let branch = build_branch_index(
            root_post.clone(),
            vec![root_post.clone(), child_post.clone(), child_post.clone()],
        );

        assert_eq!(branch.ordered_post_ids, vec![root_post.id, child_post.id]);
    }
}
