pub mod cookie_replay;
mod migrations;

use std::path::{Path, PathBuf};

use rusqlite::Connection;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum FireStoreError {
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
}

pub struct FireStore {
    connection: Connection,
    path: Option<PathBuf>,
}

impl FireStore {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, FireStoreError> {
        let connection = Connection::open(path.as_ref())?;
        let store = Self {
            connection,
            path: Some(path.as_ref().to_path_buf()),
        };
        store.migrate()?;
        Ok(store)
    }

    pub fn open_in_memory() -> Result<Self, FireStoreError> {
        let connection = Connection::open_in_memory()?;
        let store = Self {
            connection,
            path: None,
        };
        store.migrate()?;
        Ok(store)
    }

    pub fn path(&self) -> Option<&Path> {
        self.path.as_deref()
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    fn migrate(&self) -> Result<(), FireStoreError> {
        migrations::run(&self.connection)
    }

    pub fn cookie_replay_enqueue(
        &self,
        url: &str,
        raw_set_cookie: &str,
        cookie_name: &str,
        domain: &str,
        inserted_at: u64,
    ) -> Result<(), FireStoreError> {
        cookie_replay::enqueue_set_cookie(
            &self.connection,
            url,
            raw_set_cookie,
            cookie_name,
            domain,
            inserted_at,
        )?;
        Ok(())
    }

    pub fn cookie_replay_list(
        &self,
    ) -> Result<Vec<cookie_replay::CookieReplayEntry>, FireStoreError> {
        Ok(cookie_replay::list_replay_queue(&self.connection)?)
    }

    pub fn cookie_replay_clear(&self) -> Result<(), FireStoreError> {
        cookie_replay::clear_replay_queue(&self.connection)?;
        Ok(())
    }

    pub fn get_cached_user(&self) -> Result<Option<String>, FireStoreError> {
        let mut stmt = self.connection.prepare(
            "SELECT data FROM current_user_cache WHERE cache_key = 'primary' ORDER BY updated_at DESC LIMIT 1"
        )?;
        let mut rows = stmt.query([])?;
        match rows.next()? {
            Some(row) => Ok(Some(row.get(0)?)),
            None => Ok(None),
        }
    }

    pub fn set_cached_user(&self, data: &str) -> Result<(), FireStoreError> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;
        self.connection.execute(
            "INSERT OR REPLACE INTO current_user_cache (cache_key, data, updated_at) VALUES ('primary', ?1, ?2)",
            rusqlite::params![data, now],
        )?;
        Ok(())
    }

    pub fn clear_cached_user(&self) -> Result<(), FireStoreError> {
        self.connection
            .execute("DELETE FROM current_user_cache", [])?;
        Ok(())
    }

    pub fn topic_list_cache_write(
        &self,
        auth_scope_hash: &str,
        scope_key: &str,
        page: u32,
        payload_json: &str,
    ) -> Result<(), FireStoreError> {
        self.connection.execute(
            r#"
            INSERT OR REPLACE INTO topic_list_cache
                (auth_scope_hash, scope_key, page, payload_json, fetched_at_ms)
            VALUES (?1, ?2, ?3, ?4, ?5)
            "#,
            rusqlite::params![
                auth_scope_hash,
                scope_key,
                i64::from(page),
                payload_json,
                now_ms()
            ],
        )?;
        Ok(())
    }

    pub fn topic_list_cache_read(
        &self,
        auth_scope_hash: &str,
        scope_key: &str,
        page: u32,
    ) -> Result<Option<String>, FireStoreError> {
        let mut stmt = self.connection.prepare(
            r#"
            SELECT payload_json
            FROM topic_list_cache
            WHERE auth_scope_hash = ?1 AND scope_key = ?2 AND page = ?3
            ORDER BY fetched_at_ms DESC
            LIMIT 1
            "#,
        )?;
        let mut rows = stmt.query(rusqlite::params![
            auth_scope_hash,
            scope_key,
            i64::from(page)
        ])?;
        match rows.next()? {
            Some(row) => Ok(Some(row.get(0)?)),
            None => Ok(None),
        }
    }

    pub fn notification_list_cache_write(
        &self,
        auth_scope_hash: &str,
        scope_key: &str,
        payload_json: &str,
    ) -> Result<(), FireStoreError> {
        self.connection.execute(
            r#"
            INSERT OR REPLACE INTO notification_list_cache
                (auth_scope_hash, scope_key, payload_json, fetched_at_ms)
            VALUES (?1, ?2, ?3, ?4)
            "#,
            rusqlite::params![auth_scope_hash, scope_key, payload_json, now_ms()],
        )?;
        Ok(())
    }

    pub fn notification_list_cache_read(
        &self,
        auth_scope_hash: &str,
        scope_key: &str,
    ) -> Result<Option<String>, FireStoreError> {
        let mut stmt = self.connection.prepare(
            r#"
            SELECT payload_json
            FROM notification_list_cache
            WHERE auth_scope_hash = ?1 AND scope_key = ?2
            ORDER BY fetched_at_ms DESC
            LIMIT 1
            "#,
        )?;
        let mut rows = stmt.query(rusqlite::params![auth_scope_hash, scope_key])?;
        match rows.next()? {
            Some(row) => Ok(Some(row.get(0)?)),
            None => Ok(None),
        }
    }

    pub fn clear_list_caches(&self, auth_scope_hash: &str) -> Result<(), FireStoreError> {
        self.connection.execute(
            "DELETE FROM topic_list_cache WHERE auth_scope_hash = ?1",
            [auth_scope_hash],
        )?;
        self.connection.execute(
            "DELETE FROM notification_list_cache WHERE auth_scope_hash = ?1",
            [auth_scope_hash],
        )?;
        self.connection.execute(
            "DELETE FROM chat_channels_cache WHERE auth_scope_hash = ?1",
            [auth_scope_hash],
        )?;
        self.connection.execute(
            "DELETE FROM chat_messages_cache WHERE auth_scope_hash = ?1",
            [auth_scope_hash],
        )?;
        Ok(())
    }

    pub fn chat_channels_cache_write(
        &self,
        auth_scope_hash: &str,
        payload_json: &str,
    ) -> Result<(), FireStoreError> {
        self.connection.execute(
            r#"
            INSERT OR REPLACE INTO chat_channels_cache
                (auth_scope_hash, payload_json, fetched_at_ms)
            VALUES (?1, ?2, ?3)
            "#,
            rusqlite::params![auth_scope_hash, payload_json, now_ms()],
        )?;
        Ok(())
    }

    pub fn chat_channels_cache_read(
        &self,
        auth_scope_hash: &str,
    ) -> Result<Option<String>, FireStoreError> {
        let mut stmt = self.connection.prepare(
            r#"
            SELECT payload_json
            FROM chat_channels_cache
            WHERE auth_scope_hash = ?1
            LIMIT 1
            "#,
        )?;
        let mut rows = stmt.query(rusqlite::params![auth_scope_hash])?;
        match rows.next()? {
            Some(row) => Ok(Some(row.get(0)?)),
            None => Ok(None),
        }
    }

    pub fn chat_messages_cache_write(
        &self,
        auth_scope_hash: &str,
        channel_id: u64,
        thread_id: u64,
        payload_json: &str,
    ) -> Result<(), FireStoreError> {
        self.connection.execute(
            r#"
            INSERT OR REPLACE INTO chat_messages_cache
                (auth_scope_hash, channel_id, thread_id, payload_json, fetched_at_ms)
            VALUES (?1, ?2, ?3, ?4, ?5)
            "#,
            rusqlite::params![
                auth_scope_hash,
                channel_id as i64,
                thread_id as i64,
                payload_json,
                now_ms()
            ],
        )?;
        Ok(())
    }

    pub fn chat_messages_cache_read(
        &self,
        auth_scope_hash: &str,
        channel_id: u64,
        thread_id: u64,
    ) -> Result<Option<String>, FireStoreError> {
        let mut stmt = self.connection.prepare(
            r#"
            SELECT payload_json
            FROM chat_messages_cache
            WHERE auth_scope_hash = ?1 AND channel_id = ?2 AND thread_id = ?3
            LIMIT 1
            "#,
        )?;
        let mut rows = stmt.query(rusqlite::params![
            auth_scope_hash,
            channel_id as i64,
            thread_id as i64
        ])?;
        match rows.next()? {
            Some(row) => Ok(Some(row.get(0)?)),
            None => Ok(None),
        }
    }
}

fn now_ms() -> i64 {
    time::OffsetDateTime::now_utc().unix_timestamp_nanos() as i64 / 1_000_000
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn topic_list_cache_is_scoped_by_auth_scope_key_and_page() {
        let store = FireStore::open_in_memory().expect("store");

        store
            .topic_list_cache_write("auth-a", "latest", 0, r#"{"page":0}"#)
            .expect("write page 0");
        store
            .topic_list_cache_write("auth-a", "latest", 1, r#"{"page":1}"#)
            .expect("write page 1");
        store
            .topic_list_cache_write("auth-b", "latest", 0, r#"{"other":true}"#)
            .expect("write other auth");

        assert_eq!(
            store
                .topic_list_cache_read("auth-a", "latest", 0)
                .expect("read page 0")
                .as_deref(),
            Some(r#"{"page":0}"#)
        );
        assert_eq!(
            store
                .topic_list_cache_read("auth-a", "latest", 1)
                .expect("read page 1")
                .as_deref(),
            Some(r#"{"page":1}"#)
        );
        assert!(store
            .topic_list_cache_read("auth-a", "hot", 0)
            .expect("read miss")
            .is_none());
    }

    #[test]
    fn notification_cache_is_scoped_and_cleared_with_topic_cache() {
        let store = FireStore::open_in_memory().expect("store");

        store
            .topic_list_cache_write("auth-a", "latest", 0, r#"{"topics":[]}"#)
            .expect("write topic");
        store
            .notification_list_cache_write("auth-a", "recent|limit=30|offset=0", r#"{"n":1}"#)
            .expect("write notification");
        store
            .notification_list_cache_write("auth-b", "recent|limit=30|offset=0", r#"{"n":2}"#)
            .expect("write other auth");

        store.clear_list_caches("auth-a").expect("clear auth-a");

        assert!(store
            .topic_list_cache_read("auth-a", "latest", 0)
            .expect("topic cleared")
            .is_none());
        assert!(store
            .notification_list_cache_read("auth-a", "recent|limit=30|offset=0")
            .expect("notification cleared")
            .is_none());
        assert_eq!(
            store
                .notification_list_cache_read("auth-b", "recent|limit=30|offset=0")
                .expect("other auth remains")
                .as_deref(),
            Some(r#"{"n":2}"#)
        );
    }

    #[test]
    fn chat_caches_are_scoped_by_auth_and_thread() {
        let store = FireStore::open_in_memory().expect("store");
        store
            .chat_channels_cache_write("auth-a", r#"{"channels":1}"#)
            .expect("write channels");
        store
            .chat_messages_cache_write("auth-a", 9, 0, r#"{"messages":[]}"#)
            .expect("write messages");
        store
            .chat_messages_cache_write("auth-a", 9, 4, r#"{"thread":true}"#)
            .expect("write thread");
        store
            .chat_channels_cache_write("auth-b", r#"{"channels":2}"#)
            .expect("write other auth");

        assert_eq!(
            store
                .chat_channels_cache_read("auth-a")
                .expect("read channels")
                .as_deref(),
            Some(r#"{"channels":1}"#)
        );
        assert_eq!(
            store
                .chat_messages_cache_read("auth-a", 9, 0)
                .expect("read main")
                .as_deref(),
            Some(r#"{"messages":[]}"#)
        );
        assert_eq!(
            store
                .chat_messages_cache_read("auth-a", 9, 4)
                .expect("read thread")
                .as_deref(),
            Some(r#"{"thread":true}"#)
        );

        store.clear_list_caches("auth-a").expect("clear");
        assert!(store
            .chat_channels_cache_read("auth-a")
            .expect("cleared channels")
            .is_none());
        assert!(store
            .chat_messages_cache_read("auth-a", 9, 0)
            .expect("cleared messages")
            .is_none());
        assert_eq!(
            store
                .chat_channels_cache_read("auth-b")
                .expect("other auth remains")
                .as_deref(),
            Some(r#"{"channels":2}"#)
        );
    }
}
