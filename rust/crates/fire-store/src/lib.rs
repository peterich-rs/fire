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
}
