mod migrations;
pub mod topic_detail;

use std::path::{Path, PathBuf};

use rusqlite::Connection;
use thiserror::Error;

pub use topic_detail::TopicDetailStoreStats;

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
}
