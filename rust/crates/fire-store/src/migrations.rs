use rusqlite::Connection;

use crate::FireStoreError;

pub(crate) fn run(connection: &Connection) -> Result<(), FireStoreError> {
    connection.pragma_update(None, "foreign_keys", "ON")?;
    connection.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at_ms INTEGER NOT NULL
        );
        "#,
    )?;

    let current_version: i64 = connection.query_row(
        "SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
        [],
        |row| row.get(0),
    )?;

    if current_version < 1 {
        connection.execute_batch(MIGRATION_1)?;
        connection.execute(
            "INSERT OR IGNORE INTO schema_migrations (version, applied_at_ms) VALUES (1, ?1)",
            [now_ms()],
        )?;
    }

    Ok(())
}

fn now_ms() -> i64 {
    time::OffsetDateTime::now_utc().unix_timestamp_nanos() as i64 / 1_000_000
}

const MIGRATION_1: &str = r#"
CREATE TABLE IF NOT EXISTS topic_posts (
    auth_scope_hash TEXT NOT NULL,
    post_id INTEGER NOT NULL,
    topic_id INTEGER NOT NULL,
    post_number INTEGER NOT NULL,
    user_id INTEGER,
    username TEXT NOT NULL,
    avatar_template TEXT,
    cooked_html TEXT NOT NULL,
    raw_markdown TEXT,
    created_at TEXT,
    updated_at TEXT,
    reply_to_post_number INTEGER,
    hidden INTEGER NOT NULL,
    deleted INTEGER NOT NULL,
    permissions_json TEXT NOT NULL,
    reactions_json TEXT NOT NULL,
    polls_json TEXT NOT NULL,
    raw_revision TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (auth_scope_hash, post_id)
);

CREATE INDEX IF NOT EXISTS topic_posts_by_topic
    ON topic_posts (auth_scope_hash, topic_id, post_number);

CREATE TABLE IF NOT EXISTS topic_response_rows (
    auth_scope_hash TEXT NOT NULL,
    topic_id INTEGER NOT NULL,
    post_id INTEGER NOT NULL,
    parent_post_number INTEGER,
    depth INTEGER NOT NULL,
    preorder_index INTEGER NOT NULL,
    root_post_id INTEGER,
    branch_offset INTEGER,
    payload_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (auth_scope_hash, topic_id, post_id)
);

CREATE INDEX IF NOT EXISTS topic_response_rows_by_preorder
    ON topic_response_rows (auth_scope_hash, topic_id, preorder_index);

CREATE TABLE IF NOT EXISTS post_render_blocks (
    auth_scope_hash TEXT NOT NULL,
    post_id INTEGER NOT NULL,
    render_revision TEXT NOT NULL,
    plain_text TEXT NOT NULL,
    blocks_json TEXT NOT NULL,
    images_json TEXT NOT NULL,
    links_json TEXT NOT NULL,
    estimated_metrics_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (auth_scope_hash, post_id)
);

CREATE TABLE IF NOT EXISTS topic_detail_snapshots (
    auth_scope_hash TEXT NOT NULL,
    topic_id INTEGER NOT NULL,
    snapshot_revision INTEGER NOT NULL,
    body_post_id INTEGER,
    cursor_json TEXT NOT NULL,
    loaded_ranges_json TEXT NOT NULL,
    has_more INTEGER NOT NULL,
    load_state TEXT NOT NULL,
    source TEXT NOT NULL,
    stale_error_message TEXT,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (auth_scope_hash, topic_id)
);

CREATE TABLE IF NOT EXISTS topic_detail_feed_items (
    auth_scope_hash TEXT NOT NULL,
    topic_id INTEGER NOT NULL,
    ordinal INTEGER NOT NULL,
    item_id TEXT NOT NULL,
    item_kind TEXT NOT NULL,
    post_id INTEGER,
    content_revision TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (auth_scope_hash, topic_id, ordinal)
);

CREATE UNIQUE INDEX IF NOT EXISTS topic_detail_feed_items_by_id
    ON topic_detail_feed_items (auth_scope_hash, topic_id, item_id);
"#;
