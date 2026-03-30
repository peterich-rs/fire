use std::{io, path::PathBuf};

use mars_xlog::XlogError;
use openwire::WireError;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum FireCoreError {
    #[error("invalid url: {0}")]
    InvalidUrl(#[from] url::ParseError),
    #[error("failed to build request: {0}")]
    RequestBuild(http::Error),
    #[error("failed to build network client: {source}")]
    ClientBuild { source: WireError },
    #[error("network request failed: {source}")]
    Network { source: WireError },
    #[error("failed to initialize logger: {0}")]
    Logger(#[from] XlogError),
    #[error("{operation} failed with HTTP {status}: {body}")]
    HttpStatus {
        operation: &'static str,
        status: u16,
        body: String,
    },
    #[error("logout requires a current username")]
    MissingCurrentUsername,
    #[error("request requires a login session")]
    MissingLoginSession,
    #[error("message bus requires a shared session key")]
    MissingSharedSessionKey,
    #[error("message bus requires at least one subscription cursor")]
    MissingMessageBusSubscriptions,
    #[error("request requires a csrf token")]
    MissingCsrfToken,
    #[error("fire workspace path is not configured")]
    MissingWorkspacePath,
    #[error("workspace relative path must stay under the configured root: {path}")]
    InvalidWorkspaceRelativePath { path: PathBuf },
    #[error("failed to access workspace path {path}: {source}")]
    WorkspaceIo { path: PathBuf, source: io::Error },
    #[error("logger workspace mismatch: expected {expected}, found {found}")]
    LoggerWorkspaceMismatch { expected: PathBuf, found: PathBuf },
    #[error("csrf response did not contain a usable token")]
    InvalidCsrfResponse,
    #[error("failed to serialize persisted session: {0}")]
    PersistSerialize(serde_json::Error),
    #[error("failed to deserialize persisted session: {0}")]
    PersistDeserialize(serde_json::Error),
    #[error("persisted session uses unsupported version {found}, expected {expected}")]
    PersistVersionMismatch { expected: u32, found: u32 },
    #[error("persisted session base url mismatch: expected {expected}, found {found}")]
    PersistBaseUrlMismatch { expected: String, found: String },
    #[error("invalid message bus response: {details}")]
    InvalidMessageBusResponse { details: String },
    #[error("failed to access persisted session at {path}: {source}")]
    PersistIo { path: PathBuf, source: io::Error },
}
