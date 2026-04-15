use fire_core::FireCoreError;

#[derive(uniffi::Error, thiserror::Error, Debug)]
pub enum FireUniFfiError {
    #[error("configuration error: {details}")]
    Configuration { details: String },
    #[error("validation error: {details}")]
    Validation { details: String },
    #[error("authentication error: {details}")]
    Authentication { details: String },
    #[error("login required: {details}")]
    LoginRequired { details: String },
    #[error("stale session response discarded: {operation}")]
    StaleSessionResponse { operation: String },
    #[error("network error: {details}")]
    Network { details: String },
    #[error("request requires Cloudflare challenge verification")]
    CloudflareChallenge,
    #[error("{operation} failed with HTTP {status}: {body}")]
    HttpStatus {
        operation: String,
        status: u16,
        body: String,
    },
    #[error("storage error: {details}")]
    Storage { details: String },
    #[error("serialization error: {details}")]
    Serialization { details: String },
    #[error("runtime error: {details}")]
    Runtime { details: String },
    #[error("internal error: {details}")]
    Internal { details: String },
}

impl From<FireCoreError> for FireUniFfiError {
    fn from(value: FireCoreError) -> Self {
        match value {
            FireCoreError::InvalidUrl(source) => Self::Configuration {
                details: source.to_string(),
            },
            FireCoreError::RequestBuild(source) => Self::Internal {
                details: source.to_string(),
            },
            FireCoreError::ClientBuild { source } | FireCoreError::Network { source } => {
                Self::Network {
                    details: source.to_string(),
                }
            }
            FireCoreError::Logger(source) => Self::Configuration {
                details: source.to_string(),
            },
            FireCoreError::LoginRequired { message, .. } => {
                Self::LoginRequired { details: message }
            }
            FireCoreError::StaleSessionResponse { operation } => Self::StaleSessionResponse {
                operation: operation.to_string(),
            },
            FireCoreError::CloudflareChallenge { .. } => Self::CloudflareChallenge,
            FireCoreError::HttpStatus {
                operation,
                status,
                body,
            } => Self::HttpStatus {
                operation: operation.to_string(),
                status,
                body,
            },
            FireCoreError::ResponseDeserialize { source, .. } => Self::Serialization {
                details: source.to_string(),
            },
            FireCoreError::MissingCurrentUsername => Self::Authentication {
                details: "logout requires a current username".to_string(),
            },
            FireCoreError::MissingCurrentUserId => Self::Authentication {
                details: "request requires a current user id".to_string(),
            },
            FireCoreError::MissingLoginSession => Self::Authentication {
                details: "request requires a login session".to_string(),
            },
            FireCoreError::MissingSharedSessionKey => Self::Authentication {
                details: "message bus requires a shared session key".to_string(),
            },
            FireCoreError::MissingMessageBusSubscription => Self::Validation {
                details: "message bus requires at least one subscribed channel".to_string(),
            },
            FireCoreError::MessageBusNotStarted => Self::Validation {
                details: "message bus has not been started".to_string(),
            },
            FireCoreError::MissingCsrfToken => Self::Authentication {
                details: "request requires a csrf token".to_string(),
            },
            FireCoreError::PostEnqueued { pending_count } => Self::Validation {
                details: format!("post is pending review (pending_count={pending_count})"),
            },
            FireCoreError::MissingWorkspacePath => Self::Configuration {
                details: "fire workspace path is not configured".to_string(),
            },
            FireCoreError::InvalidWorkspaceRelativePath { path } => Self::Validation {
                details: format!(
                    "workspace relative path must stay under the configured root: {}",
                    path.display()
                ),
            },
            FireCoreError::WorkspaceIo { path, source }
            | FireCoreError::PersistIo { path, source }
            | FireCoreError::DiagnosticsIo { path, source } => Self::Storage {
                details: format!("{}: {}", path.display(), source),
            },
            FireCoreError::LoggerWorkspaceMismatch { expected, found } => Self::Configuration {
                details: format!(
                    "logger workspace mismatch: expected {}, found {}",
                    expected.display(),
                    found.display()
                ),
            },
            FireCoreError::InvalidCsrfResponse => Self::Validation {
                details: "csrf response did not contain a usable token".to_string(),
            },
            FireCoreError::PersistSerialize(source)
            | FireCoreError::PersistDeserialize(source)
            | FireCoreError::DiagnosticsSerialize(source)
            | FireCoreError::DiagnosticsDeserialize(source) => Self::Serialization {
                details: source.to_string(),
            },
            FireCoreError::DiagnosticsTraceNotFound { trace_id } => Self::Validation {
                details: format!("network request trace not found: {trace_id}"),
            },
            FireCoreError::PersistVersionMismatch { expected, found } => Self::Validation {
                details: format!(
                    "persisted session uses unsupported version {found}, expected {expected}"
                ),
            },
            FireCoreError::PersistBaseUrlMismatch { expected, found } => Self::Validation {
                details: format!(
                    "persisted session base url mismatch: expected {expected}, found {found}"
                ),
            },
        }
    }
}
