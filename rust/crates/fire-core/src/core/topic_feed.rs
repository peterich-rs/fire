use fire_models::{
    FeedSnapshotSource, TopicDetailCursor, TopicDetailFeedItem, TopicDetailFeedItemKind,
    TopicDetailFeedLoadState, TopicDetailFeedQuery, TopicDetailFeedSnapshot, TopicDetailLoadPolicy,
    TopicDetailLoadedRange, TopicPost, TopicResponseRow, TopicScreenQuery,
};
use sha1::{Digest, Sha1};
use tracing::{info, warn};

use super::FireCore;
use crate::error::FireCoreError;

const TOPIC_FEED_ROOT_PAGE_SIZE: u16 = 10;
const TOPIC_FEED_ROW_PAGE_SIZE: u16 = 40;

impl FireCore {
    pub async fn load_topic_detail_feed(
        &self,
        query: TopicDetailFeedQuery,
    ) -> Result<TopicDetailFeedSnapshot, FireCoreError> {
        let auth_scope_hash = self.topic_feed_auth_scope_hash();

        match query.policy {
            TopicDetailLoadPolicy::CacheOnly => {
                return Ok(self
                    .read_cached_topic_feed(&auth_scope_hash, query.topic_id)?
                    .unwrap_or_else(|| {
                        TopicDetailFeedSnapshot::empty_cache_error(
                            query.topic_id,
                            "No processed topic snapshot is cached for this auth scope.",
                        )
                    }));
            }
            TopicDetailLoadPolicy::CacheFirstThenRefresh => {
                if let Some(mut snapshot) =
                    self.read_cached_topic_feed(&auth_scope_hash, query.topic_id)?
                {
                    snapshot.source = FeedSnapshotSource::ProcessedCache;
                    snapshot.load_state = TopicDetailFeedLoadState::Ready;
                    info!(
                        topic_id = query.topic_id,
                        revision = snapshot.revision,
                        item_count = snapshot.items.len(),
                        "topic detail feed loaded from processed cache"
                    );
                    return Ok(snapshot);
                }
            }
            TopicDetailLoadPolicy::NetworkFirst | TopicDetailLoadPolicy::ForceRefresh => {}
        }

        self.refresh_topic_detail_feed(query).await
    }

    pub async fn refresh_topic_detail_feed(
        &self,
        query: TopicDetailFeedQuery,
    ) -> Result<TopicDetailFeedSnapshot, FireCoreError> {
        let auth_scope_hash = self.topic_feed_auth_scope_hash();
        match self
            .fetch_topic_detail_feed_from_network(&auth_scope_hash, query.clone())
            .await
        {
            Ok(snapshot) => Ok(snapshot),
            Err(error) if should_propagate_topic_feed_error(&error) => Err(error),
            Err(error) => {
                if let Some(mut cached) =
                    self.read_cached_topic_feed(&auth_scope_hash, query.topic_id)?
                {
                    warn!(
                        topic_id = query.topic_id,
                        error = %error,
                        "topic detail feed refresh failed; returning stale processed snapshot"
                    );
                    cached.source = FeedSnapshotSource::StaleIfError;
                    cached.load_state = TopicDetailFeedLoadState::StaleWithError;
                    cached.stale_error_message = Some(error.to_string());
                    append_notice_item(&mut cached, "刷新失败，正在显示缓存内容。", true);
                    return Ok(cached);
                }

                warn!(
                    topic_id = query.topic_id,
                    error = %error,
                    "topic detail feed refresh failed with no cached snapshot"
                );
                Ok(error_snapshot_for(query.topic_id, &error))
            }
        }
    }

    pub fn cached_topic_detail_feed(
        &self,
        topic_id: u64,
    ) -> Result<Option<TopicDetailFeedSnapshot>, FireCoreError> {
        let auth_scope_hash = self.topic_feed_auth_scope_hash();
        self.read_cached_topic_feed(&auth_scope_hash, topic_id)
    }

    async fn fetch_topic_detail_feed_from_network(
        &self,
        auth_scope_hash: &str,
        query: TopicDetailFeedQuery,
    ) -> Result<TopicDetailFeedSnapshot, FireCoreError> {
        let screen = self
            .fetch_topic_screen(TopicScreenQuery {
                topic_id: query.topic_id,
                target_post_number: query.target_post_number,
                root_page_size: TOPIC_FEED_ROOT_PAGE_SIZE,
                row_page_size: TOPIC_FEED_ROW_PAGE_SIZE,
                track_visit: true,
                force_load: matches!(query.policy, TopicDetailLoadPolicy::ForceRefresh),
            })
            .await?;

        let revision = {
            let store = self
                .topic_feed_store
                .lock()
                .expect("topic feed store mutex poisoned");
            store.next_topic_detail_revision(auth_scope_hash, query.topic_id)?
        };
        let mut snapshot =
            topic_screen_to_feed_snapshot(screen, revision, FeedSnapshotSource::Network);
        snapshot.updated_at_ms = now_ms();

        {
            let mut store = self
                .topic_feed_store
                .lock()
                .expect("topic feed store mutex poisoned");
            store.write_topic_detail_snapshot(auth_scope_hash, &snapshot)?;
        }

        info!(
            topic_id = snapshot.topic_id,
            revision = snapshot.revision,
            item_count = snapshot.items.len(),
            has_more = snapshot.cursor.has_more,
            "topic detail feed fetched and stored"
        );
        Ok(snapshot)
    }

    fn read_cached_topic_feed(
        &self,
        auth_scope_hash: &str,
        topic_id: u64,
    ) -> Result<Option<TopicDetailFeedSnapshot>, FireCoreError> {
        let store = self
            .topic_feed_store
            .lock()
            .expect("topic feed store mutex poisoned");
        Ok(store.read_topic_detail_snapshot(auth_scope_hash, topic_id)?)
    }

    fn topic_feed_auth_scope_hash(&self) -> String {
        let snapshot = self.snapshot();
        let username = snapshot
            .bootstrap
            .current_username
            .as_deref()
            .unwrap_or("anonymous");
        let token = snapshot.cookies.t_token.as_deref().unwrap_or("anonymous");
        let forum_session = snapshot
            .cookies
            .forum_session
            .as_deref()
            .unwrap_or("anonymous");
        let mut hasher = Sha1::new();
        hasher.update(self.base_url().as_bytes());
        hasher.update(b"|");
        hasher.update(username.as_bytes());
        hasher.update(b"|");
        hasher.update(token.as_bytes());
        hasher.update(b"|");
        hasher.update(forum_session.as_bytes());
        format!("{:x}", hasher.finalize())
    }
}

fn topic_screen_to_feed_snapshot(
    screen: fire_models::TopicScreen,
    revision: u64,
    source: FeedSnapshotSource,
) -> TopicDetailFeedSnapshot {
    let topic_id = screen.header.topic_id;
    let mut items = Vec::new();

    items.push(TopicDetailFeedItem {
        item_id: format!("topic-header:{topic_id}"),
        kind: TopicDetailFeedItemKind::Header,
        ordinal: 0,
        content_revision: header_revision(&screen.header),
        header: Some(screen.header.clone()),
        ..TopicDetailFeedItem::default()
    });

    items.push(TopicDetailFeedItem {
        item_id: format!("post:{}:original", screen.body.post.id),
        kind: TopicDetailFeedItemKind::OriginalPost,
        ordinal: 1,
        post_id: Some(screen.body.post.id),
        content_revision: post_revision(&screen.body.post),
        post: Some(screen.body.post.clone()),
        ..TopicDetailFeedItem::default()
    });

    let mut seen_post_ids = std::collections::HashSet::from([screen.body.post.id]);
    for row in screen.response.rows {
        if !seen_post_ids.insert(row.post.id) {
            continue;
        }
        let ordinal = items.len() as u32;
        items.push(response_row_to_feed_item(row, ordinal));
    }

    let next_response_cursor = screen.response.next_cursor.clone();
    let has_more = next_response_cursor.is_some();

    if has_more {
        let ordinal = items.len() as u32;
        items.push(TopicDetailFeedItem {
            item_id: format!("footer:{topic_id}:{revision}"),
            kind: TopicDetailFeedItemKind::Footer,
            ordinal,
            content_revision: format!("footer:{revision}"),
            title: Some("Load more replies".to_string()),
            retryable: true,
            ..TopicDetailFeedItem::default()
        });
    }

    let loaded_ranges = loaded_ranges_from_items(&items);
    TopicDetailFeedSnapshot {
        topic_id,
        revision,
        items,
        cursor: TopicDetailCursor {
            next_response_cursor,
            has_more,
            loaded_ranges,
        },
        source,
        load_state: TopicDetailFeedLoadState::Ready,
        stale_error_message: None,
        updated_at_ms: now_ms(),
    }
}

fn response_row_to_feed_item(row: TopicResponseRow, ordinal: u32) -> TopicDetailFeedItem {
    TopicDetailFeedItem {
        item_id: format!("post:{}:reply", row.post.id),
        kind: TopicDetailFeedItemKind::Reply,
        ordinal,
        post_id: Some(row.post.id),
        content_revision: response_row_revision(&row),
        post: Some(row.post.clone()),
        response_row: Some(row),
        ..TopicDetailFeedItem::default()
    }
}

fn loaded_ranges_from_items(items: &[TopicDetailFeedItem]) -> Vec<TopicDetailLoadedRange> {
    let mut post_numbers: Vec<u32> = items
        .iter()
        .filter_map(|item| item.post.as_ref().map(|post| post.post_number))
        .collect();
    post_numbers.sort_unstable();
    let (Some(first), Some(last)) = (post_numbers.first(), post_numbers.last()) else {
        return Vec::new();
    };
    vec![TopicDetailLoadedRange {
        first_post_number: *first,
        last_post_number: *last,
    }]
}

fn append_notice_item(snapshot: &mut TopicDetailFeedSnapshot, message: &str, retryable: bool) {
    let ordinal = snapshot.items.len() as u32;
    snapshot.items.push(TopicDetailFeedItem {
        item_id: format!("notice:{}:{}:stale", snapshot.topic_id, snapshot.revision),
        kind: TopicDetailFeedItemKind::Notice,
        ordinal,
        content_revision: format!("notice:{}", snapshot.revision),
        message: Some(message.to_string()),
        retryable,
        ..TopicDetailFeedItem::default()
    });
}

fn error_snapshot_for(topic_id: u64, error: &FireCoreError) -> TopicDetailFeedSnapshot {
    let mut snapshot = TopicDetailFeedSnapshot::empty_cache_error(topic_id, error.to_string());
    snapshot.updated_at_ms = now_ms();
    if is_non_retryable_topic_feed_error(error) {
        for item in &mut snapshot.items {
            item.retryable = false;
        }
    }
    snapshot
}

fn should_propagate_topic_feed_error(error: &FireCoreError) -> bool {
    matches!(
        error,
        FireCoreError::CloudflareChallenge { .. }
            | FireCoreError::LoginRequired { .. }
            | FireCoreError::MissingLoginSession
            | FireCoreError::MissingCsrfToken
    )
}

fn is_non_retryable_topic_feed_error(error: &FireCoreError) -> bool {
    matches!(
        error,
        FireCoreError::HttpStatus {
            status: 401 | 403 | 404,
            ..
        } | FireCoreError::MissingCurrentUserId
    )
}

fn header_revision(header: &fire_models::TopicHeader) -> String {
    format!(
        "header:{}:{}:{}:{}:{}:{}",
        header.topic_id,
        header.posts_count,
        header.reply_count,
        header.like_count,
        header.vote_count,
        header.bookmarked
    )
}

fn response_row_revision(row: &TopicResponseRow) -> String {
    format!(
        "{}|row:{}:{}:{}:{}",
        post_revision(&row.post),
        row.depth,
        row.preorder_index,
        row.descendant_count,
        row.is_last_sibling
    )
}

fn post_revision(post: &TopicPost) -> String {
    format!(
        "post:{}:{}:{}:{}:{}:{}:{}:{}",
        post.id,
        post.post_number,
        post.updated_at.as_deref().unwrap_or_default(),
        post.cooked.len(),
        post.like_count,
        post.reactions.len(),
        post.polls.len(),
        post.hidden
    )
}

fn now_ms() -> u64 {
    (time::OffsetDateTime::now_utc().unix_timestamp_nanos() / 1_000_000) as u64
}

#[cfg(test)]
mod tests {
    use fire_models::{
        FeedSnapshotSource, TopicBody, TopicHeader, TopicPost, TopicResponsePage, TopicResponseRow,
        TopicScreen,
    };

    use super::topic_screen_to_feed_snapshot;

    #[test]
    fn feed_snapshot_deduplicates_body_and_response_rows_by_post_id() {
        let post = TopicPost {
            id: 10,
            post_number: 1,
            username: "alice".into(),
            cooked: "<p>Hello</p>".into(),
            ..TopicPost::default()
        };
        let screen = TopicScreen {
            header: TopicHeader {
                topic_id: 42,
                title: "Fire".into(),
                ..TopicHeader::default()
            },
            body: TopicBody { post: post.clone() },
            response: TopicResponsePage {
                rows: vec![
                    TopicResponseRow {
                        post: post.clone(),
                        ..TopicResponseRow::default()
                    },
                    TopicResponseRow {
                        post: TopicPost {
                            id: 11,
                            post_number: 2,
                            username: "bob".into(),
                            cooked: "<p>Reply</p>".into(),
                            ..TopicPost::default()
                        },
                        depth: 1,
                        ..TopicResponseRow::default()
                    },
                ],
                ..TopicResponsePage::default()
            },
        };

        let snapshot = topic_screen_to_feed_snapshot(screen, 7, FeedSnapshotSource::Network);

        assert_eq!(
            snapshot
                .items
                .iter()
                .filter(|item| item.post_id == Some(10))
                .count(),
            1
        );
        assert_eq!(
            snapshot
                .items
                .iter()
                .filter(|item| item.post_id == Some(11))
                .count(),
            1
        );
        assert_eq!(snapshot.revision, 7);
    }
}
