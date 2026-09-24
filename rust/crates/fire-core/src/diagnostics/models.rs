pub(crate) const MAX_NETWORK_TRACES: usize = 200;
pub(crate) const MAX_RESPONSE_BODY_BYTES: usize = 256 * 1024;
pub(crate) const MAX_RESPONSE_BODY_INLINE_BYTES: usize = 16 * 1024;
pub(crate) const MAX_LOG_CONTENT_BYTES: usize = 512 * 1024;
pub(crate) const DEFAULT_LOG_PAGE_BYTES: usize = 128 * 1024;
pub(crate) const DEFAULT_TRACE_BODY_PAGE_BYTES: usize = 32 * 1024;
pub(crate) const SUPPORT_BUNDLE_LOG_FILE_LIMIT: usize = 4;
pub(crate) const SUPPORT_BUNDLE_TRACE_LIMIT: usize = 20;
pub(crate) const SUPPORT_BUNDLE_LOG_PAGE_BYTES: usize = 96 * 1024;
pub(crate) const SUPPORT_BUNDLE_TRACE_BODY_BYTES: usize = 32 * 1024;
pub(crate) const SUPPORT_BUNDLE_DIR_NAME: &str = "support-bundles";
pub(crate) const FEEDBACK_BUNDLE_DIR_NAME: &str = "feedback-bundles";
pub(crate) const FEEDBACK_BUNDLE_LOG_FILE_LIMIT: usize = 4;
pub(crate) const FEEDBACK_BUNDLE_TRACE_LIMIT: usize = 12;
pub(crate) const FEEDBACK_BUNDLE_LOG_PAGE_BYTES: usize = 64 * 1024;
pub(crate) const FEEDBACK_BUNDLE_TRACE_BODY_BYTES: usize = 16 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkTraceOutcome {
    InProgress,
    Succeeded,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiagnosticsPageDirection {
    Older,
    Newer,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiagnosticsTextPage {
    pub text: String,
    pub start_offset: u64,
    pub end_offset: u64,
    pub total_bytes: u64,
    pub next_cursor: Option<u64>,
    pub has_more_older: bool,
    pub has_more_newer: bool,
    pub is_head_aligned: bool,
    pub is_tail_aligned: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceHeader {
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceEvent {
    pub sequence: u32,
    pub timestamp_unix_ms: u64,
    pub phase: String,
    pub summary: String,
    pub details: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceSummary {
    pub id: u64,
    pub call_id: Option<u64>,
    pub operation: String,
    pub method: String,
    pub url: String,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub duration_ms: Option<u64>,
    pub outcome: NetworkTraceOutcome,
    pub status_code: Option<u16>,
    pub error_message: Option<String>,
    pub response_content_type: Option<String>,
    pub response_body_truncated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceDetail {
    pub id: u64,
    pub call_id: Option<u64>,
    pub operation: String,
    pub method: String,
    pub url: String,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub duration_ms: Option<u64>,
    pub outcome: NetworkTraceOutcome,
    pub status_code: Option<u16>,
    pub error_message: Option<String>,
    pub request_headers: Vec<NetworkTraceHeader>,
    pub response_headers: Vec<NetworkTraceHeader>,
    pub response_content_type: Option<String>,
    pub response_body: Option<String>,
    pub response_body_truncated: bool,
    pub response_body_storage_truncated: bool,
    pub response_body_stored_bytes: Option<u64>,
    pub response_body_page_available: bool,
    pub response_body_bytes: Option<u64>,
    pub events: Vec<NetworkTraceEvent>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireLogFileSummary {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireLogFileDetail {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub contents: String,
    pub is_truncated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireLogFilePage {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub page: DiagnosticsTextPage,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkTraceBodyPage {
    pub trace_id: u64,
    pub response_content_type: Option<String>,
    pub response_body_storage_truncated: bool,
    pub response_body_stored_bytes: Option<u64>,
    pub page: DiagnosticsTextPage,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireSupportBundleHostContext {
    pub platform: String,
    pub app_version: Option<String>,
    pub build_number: Option<String>,
    pub scene_phase: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FireSupportBundleExport {
    pub file_name: String,
    pub relative_path: String,
    pub absolute_path: String,
    pub size_bytes: u64,
    pub created_at_unix_ms: u64,
    pub diagnostic_session_id: String,
}

#[derive(Debug, Clone)]
pub(crate) struct FireRequestTraceMetadata {
    pub(crate) trace_id: u64,
    pub(crate) operation: String,
}
