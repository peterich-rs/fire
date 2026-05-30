use fire_models::{
    TopicDetailFeedItem, TopicDetailFeedItemKind, TopicDetailFeedLoadState,
    TopicDetailFeedSnapshot, TopicPost,
};
use rusqlite::{params, OptionalExtension};
use serde::Serialize;

use crate::{FireStore, FireStoreError};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TopicDetailStoreStats {
    pub processed_post_count: u64,
    pub response_row_count: u64,
    pub render_block_count: u64,
    pub snapshot_count: u64,
    pub feed_item_count: u64,
}

impl FireStore {
    pub fn next_topic_detail_revision(
        &self,
        auth_scope_hash: &str,
        topic_id: u64,
    ) -> Result<u64, FireStoreError> {
        let revision: Option<i64> = self
            .connection()
            .query_row(
                "SELECT snapshot_revision FROM topic_detail_snapshots
                 WHERE auth_scope_hash = ?1 AND topic_id = ?2",
                params![auth_scope_hash, topic_id as i64],
                |row| row.get(0),
            )
            .optional()?;
        Ok(revision.unwrap_or(0).max(0) as u64 + 1)
    }

    pub fn write_topic_detail_snapshot(
        &mut self,
        auth_scope_hash: &str,
        snapshot: &TopicDetailFeedSnapshot,
    ) -> Result<(), FireStoreError> {
        let tx = self.connection.transaction()?;
        let updated_at_ms = snapshot.updated_at_ms as i64;
        let body_post_id = snapshot
            .items
            .iter()
            .find(|item| item.kind == TopicDetailFeedItemKind::OriginalPost)
            .and_then(|item| item.post_id)
            .map(|value| value as i64);

        tx.execute(
            "INSERT INTO topic_detail_snapshots (
                auth_scope_hash, topic_id, snapshot_revision, body_post_id,
                cursor_json, loaded_ranges_json, has_more, load_state, source,
                stale_error_message, updated_at_ms
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
             ON CONFLICT(auth_scope_hash, topic_id) DO UPDATE SET
                snapshot_revision = excluded.snapshot_revision,
                body_post_id = excluded.body_post_id,
                cursor_json = excluded.cursor_json,
                loaded_ranges_json = excluded.loaded_ranges_json,
                has_more = excluded.has_more,
                load_state = excluded.load_state,
                source = excluded.source,
                stale_error_message = excluded.stale_error_message,
                updated_at_ms = excluded.updated_at_ms",
            params![
                auth_scope_hash,
                snapshot.topic_id as i64,
                snapshot.revision as i64,
                body_post_id,
                to_json(&snapshot.cursor)?,
                to_json(&snapshot.cursor.loaded_ranges)?,
                snapshot.cursor.has_more as i64,
                format!("{:?}", snapshot.load_state),
                format!("{:?}", snapshot.source),
                snapshot.stale_error_message,
                updated_at_ms,
            ],
        )?;

        tx.execute(
            "DELETE FROM topic_detail_feed_items
             WHERE auth_scope_hash = ?1 AND topic_id = ?2",
            params![auth_scope_hash, snapshot.topic_id as i64],
        )?;

        for item in &snapshot.items {
            tx.execute(
                "INSERT INTO topic_detail_feed_items (
                    auth_scope_hash, topic_id, ordinal, item_id, item_kind,
                    post_id, content_revision, payload_json, updated_at_ms
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                params![
                    auth_scope_hash,
                    snapshot.topic_id as i64,
                    item.ordinal as i64,
                    item.item_id,
                    format!("{:?}", item.kind),
                    item.post_id.map(|value| value as i64),
                    item.content_revision,
                    to_json(item)?,
                    updated_at_ms,
                ],
            )?;

            if let Some(post) = item.post.as_ref() {
                upsert_post(&tx, auth_scope_hash, snapshot.topic_id, post, updated_at_ms)?;
                upsert_render_block(
                    &tx,
                    auth_scope_hash,
                    post,
                    &item.content_revision,
                    updated_at_ms,
                )?;
            }

            if let Some(row) = item.response_row.as_ref() {
                tx.execute(
                    "INSERT INTO topic_response_rows (
                        auth_scope_hash, topic_id, post_id, parent_post_number,
                        depth, preorder_index, root_post_id, branch_offset,
                        payload_json, updated_at_ms
                     ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
                     ON CONFLICT(auth_scope_hash, topic_id, post_id) DO UPDATE SET
                        parent_post_number = excluded.parent_post_number,
                        depth = excluded.depth,
                        preorder_index = excluded.preorder_index,
                        root_post_id = excluded.root_post_id,
                        branch_offset = excluded.branch_offset,
                        payload_json = excluded.payload_json,
                        updated_at_ms = excluded.updated_at_ms",
                    params![
                        auth_scope_hash,
                        snapshot.topic_id as i64,
                        row.post.id as i64,
                        row.parent_post_number.map(|value| value as i64),
                        row.depth as i64,
                        row.preorder_index as i64,
                        row.post.id as i64,
                        item.ordinal as i64,
                        to_json(row)?,
                        updated_at_ms,
                    ],
                )?;
            }
        }

        tx.commit()?;
        Ok(())
    }

    pub fn read_topic_detail_snapshot(
        &self,
        auth_scope_hash: &str,
        topic_id: u64,
    ) -> Result<Option<TopicDetailFeedSnapshot>, FireStoreError> {
        let snapshot_row = self
            .connection()
            .query_row(
                "SELECT snapshot_revision, cursor_json, source, load_state,
                        stale_error_message, updated_at_ms
                 FROM topic_detail_snapshots
                 WHERE auth_scope_hash = ?1 AND topic_id = ?2",
                params![auth_scope_hash, topic_id as i64],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, String>(3)?,
                        row.get::<_, Option<String>>(4)?,
                        row.get::<_, i64>(5)?,
                    ))
                },
            )
            .optional()?;

        let Some((revision, cursor_json, source, load_state, stale_error_message, updated_at_ms)) =
            snapshot_row
        else {
            return Ok(None);
        };

        let mut statement = self.connection().prepare(
            "SELECT payload_json FROM topic_detail_feed_items
             WHERE auth_scope_hash = ?1 AND topic_id = ?2
             ORDER BY ordinal ASC",
        )?;
        let item_rows = statement.query_map(params![auth_scope_hash, topic_id as i64], |row| {
            row.get::<_, String>(0)
        })?;

        let mut items = Vec::new();
        for row in item_rows {
            let payload = row?;
            items.push(serde_json::from_str::<TopicDetailFeedItem>(&payload)?);
        }

        let mut snapshot = TopicDetailFeedSnapshot {
            topic_id,
            revision: revision.max(0) as u64,
            items,
            cursor: serde_json::from_str(&cursor_json)?,
            source: parse_source(&source),
            load_state: parse_load_state(&load_state),
            stale_error_message,
            updated_at_ms: updated_at_ms.max(0) as u64,
        };
        if snapshot.load_state == TopicDetailFeedLoadState::StaleWithError {
            snapshot.source = fire_models::FeedSnapshotSource::StaleIfError;
        }
        Ok(Some(snapshot))
    }

    pub fn topic_detail_stats(
        &self,
        auth_scope_hash: &str,
    ) -> Result<TopicDetailStoreStats, FireStoreError> {
        Ok(TopicDetailStoreStats {
            processed_post_count: count_for_scope(self, auth_scope_hash, "topic_posts")?,
            response_row_count: count_for_scope(self, auth_scope_hash, "topic_response_rows")?,
            render_block_count: count_for_scope(self, auth_scope_hash, "post_render_blocks")?,
            snapshot_count: count_for_scope(self, auth_scope_hash, "topic_detail_snapshots")?,
            feed_item_count: count_for_scope(self, auth_scope_hash, "topic_detail_feed_items")?,
        })
    }
}

fn upsert_post(
    tx: &rusqlite::Transaction<'_>,
    auth_scope_hash: &str,
    topic_id: u64,
    post: &TopicPost,
    updated_at_ms: i64,
) -> Result<(), FireStoreError> {
    tx.execute(
        "INSERT INTO topic_posts (
            auth_scope_hash, post_id, topic_id, post_number, user_id, username,
            avatar_template, cooked_html, raw_markdown, created_at, updated_at,
            reply_to_post_number, hidden, deleted, permissions_json, reactions_json,
            polls_json, raw_revision, payload_json, updated_at_ms
         ) VALUES (?1, ?2, ?3, ?4, NULL, ?5, ?6, ?7, ?8, ?9, ?10, ?11,
                   ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)
         ON CONFLICT(auth_scope_hash, post_id) DO UPDATE SET
            topic_id = excluded.topic_id,
            post_number = excluded.post_number,
            username = excluded.username,
            avatar_template = excluded.avatar_template,
            cooked_html = excluded.cooked_html,
            raw_markdown = excluded.raw_markdown,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            reply_to_post_number = excluded.reply_to_post_number,
            hidden = excluded.hidden,
            deleted = excluded.deleted,
            permissions_json = excluded.permissions_json,
            reactions_json = excluded.reactions_json,
            polls_json = excluded.polls_json,
            raw_revision = excluded.raw_revision,
            payload_json = excluded.payload_json,
            updated_at_ms = excluded.updated_at_ms",
        params![
            auth_scope_hash,
            post.id as i64,
            topic_id as i64,
            post.post_number as i64,
            post.username,
            post.avatar_template,
            post.cooked,
            post.raw,
            post.created_at,
            post.updated_at,
            post.reply_to_post_number.map(|value| value as i64),
            post.hidden as i64,
            post.hidden as i64,
            to_json(&serde_json::json!({
                "can_edit": post.can_edit,
                "can_delete": post.can_delete,
                "can_recover": post.can_recover,
                "can_accept_answer": post.can_accept_answer,
                "can_unaccept_answer": post.can_unaccept_answer,
            }))?,
            to_json(&post.reactions)?,
            to_json(&post.polls)?,
            post_revision(post),
            to_json(post)?,
            updated_at_ms,
        ],
    )?;
    Ok(())
}

fn upsert_render_block(
    tx: &rusqlite::Transaction<'_>,
    auth_scope_hash: &str,
    post: &TopicPost,
    content_revision: &str,
    updated_at_ms: i64,
) -> Result<(), FireStoreError> {
    tx.execute(
        "INSERT INTO post_render_blocks (
            auth_scope_hash, post_id, render_revision, plain_text, blocks_json,
            images_json, links_json, estimated_metrics_json, updated_at_ms
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT(auth_scope_hash, post_id) DO UPDATE SET
            render_revision = excluded.render_revision,
            plain_text = excluded.plain_text,
            blocks_json = excluded.blocks_json,
            images_json = excluded.images_json,
            links_json = excluded.links_json,
            estimated_metrics_json = excluded.estimated_metrics_json,
            updated_at_ms = excluded.updated_at_ms",
        params![
            auth_scope_hash,
            post.id as i64,
            content_revision,
            post.raw.as_deref().unwrap_or_default(),
            "[]",
            "[]",
            "[]",
            "{}",
            updated_at_ms,
        ],
    )?;
    Ok(())
}

fn to_json(value: &impl Serialize) -> Result<String, FireStoreError> {
    Ok(serde_json::to_string(value)?)
}

fn post_revision(post: &TopicPost) -> String {
    format!(
        "post:{}:{}:{}:{}:{}",
        post.id,
        post.post_number,
        post.updated_at.as_deref().unwrap_or_default(),
        post.cooked.len(),
        post.reactions.len()
    )
}

fn count_for_scope(
    store: &FireStore,
    auth_scope_hash: &str,
    table: &str,
) -> Result<u64, FireStoreError> {
    let sql = format!("SELECT COUNT(*) FROM {table} WHERE auth_scope_hash = ?1");
    let count: i64 = store
        .connection()
        .query_row(&sql, [auth_scope_hash], |row| row.get(0))?;
    Ok(count.max(0) as u64)
}

fn parse_source(value: &str) -> fire_models::FeedSnapshotSource {
    match value {
        "ProcessedCache" => fire_models::FeedSnapshotSource::ProcessedCache,
        "StaleIfError" => fire_models::FeedSnapshotSource::StaleIfError,
        "EmptyCacheError" => fire_models::FeedSnapshotSource::EmptyCacheError,
        "LocalFixture" => fire_models::FeedSnapshotSource::LocalFixture,
        _ => fire_models::FeedSnapshotSource::Network,
    }
}

fn parse_load_state(value: &str) -> TopicDetailFeedLoadState {
    match value {
        "Loading" => TopicDetailFeedLoadState::Loading,
        "EmptyCacheError" => TopicDetailFeedLoadState::EmptyCacheError,
        "StaleWithError" => TopicDetailFeedLoadState::StaleWithError,
        _ => TopicDetailFeedLoadState::Ready,
    }
}

#[cfg(test)]
mod tests {
    use fire_models::{
        FeedSnapshotSource, TopicDetailCursor, TopicDetailFeedItem, TopicDetailFeedItemKind,
        TopicDetailFeedLoadState, TopicDetailFeedSnapshot, TopicHeader, TopicPost,
    };

    use crate::FireStore;

    #[test]
    fn processed_snapshot_round_trips_with_auth_scope_isolation() {
        let mut store = FireStore::open_in_memory().expect("store");
        let snapshot = sample_snapshot(42, 1);

        store
            .write_topic_detail_snapshot("scope-a", &snapshot)
            .expect("write");

        let restored = store
            .read_topic_detail_snapshot("scope-a", 42)
            .expect("read")
            .expect("snapshot");
        assert_eq!(restored.topic_id, 42);
        assert_eq!(restored.revision, 1);
        assert_eq!(restored.items.len(), 2);
        assert_eq!(
            restored.items[1].post.as_ref().map(|post| post.id),
            Some(10)
        );

        let missing = store
            .read_topic_detail_snapshot("scope-b", 42)
            .expect("read");
        assert!(missing.is_none());
    }

    #[test]
    fn stats_count_processed_tables() {
        let mut store = FireStore::open_in_memory().expect("store");
        store
            .write_topic_detail_snapshot("scope-a", &sample_snapshot(42, 1))
            .expect("write");

        let stats = store.topic_detail_stats("scope-a").expect("stats");
        assert_eq!(stats.snapshot_count, 1);
        assert_eq!(stats.feed_item_count, 2);
        assert_eq!(stats.processed_post_count, 1);
        assert_eq!(stats.render_block_count, 1);
    }

    fn sample_snapshot(topic_id: u64, revision: u64) -> TopicDetailFeedSnapshot {
        TopicDetailFeedSnapshot {
            topic_id,
            revision,
            items: vec![
                TopicDetailFeedItem {
                    item_id: format!("topic-header:{topic_id}"),
                    kind: TopicDetailFeedItemKind::Header,
                    ordinal: 0,
                    content_revision: "header-v1".into(),
                    header: Some(TopicHeader {
                        topic_id,
                        title: "Fire".into(),
                        slug: "fire".into(),
                        posts_count: 1,
                        ..TopicHeader::default()
                    }),
                    ..TopicDetailFeedItem::default()
                },
                TopicDetailFeedItem {
                    item_id: "post:10:original".into(),
                    kind: TopicDetailFeedItemKind::OriginalPost,
                    ordinal: 1,
                    post_id: Some(10),
                    content_revision: "post-v1".into(),
                    post: Some(TopicPost {
                        id: 10,
                        username: "alice".into(),
                        cooked: "<p>Hello</p>".into(),
                        post_number: 1,
                        ..TopicPost::default()
                    }),
                    ..TopicDetailFeedItem::default()
                },
            ],
            cursor: TopicDetailCursor::default(),
            source: FeedSnapshotSource::Network,
            load_state: TopicDetailFeedLoadState::Ready,
            stale_error_message: None,
            updated_at_ms: 1,
        }
    }
}
