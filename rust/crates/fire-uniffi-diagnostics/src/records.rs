use fire_core::{
    DiagnosticsPageDirection, DiagnosticsTextPage, FireHostLogLevel, FireLogFileDetail,
    FireLogFilePage, FireLogFileSummary, FireSupportBundleExport, FireSupportBundleHostContext,
    NetworkTraceBodyPage, NetworkTraceDetail, NetworkTraceEvent, NetworkTraceHeader,
    NetworkTraceOutcome, NetworkTraceSummary,
};

#[derive(uniffi::Record, Debug, Clone)]
pub struct LogFileSummaryState {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
}

impl From<FireLogFileSummary> for LogFileSummaryState {
    fn from(value: FireLogFileSummary) -> Self {
        Self {
            relative_path: value.relative_path,
            file_name: value.file_name,
            size_bytes: value.size_bytes,
            modified_at_unix_ms: value.modified_at_unix_ms,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LogFileDetailState {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub contents: String,
    pub is_truncated: bool,
}

impl From<FireLogFileDetail> for LogFileDetailState {
    fn from(value: FireLogFileDetail) -> Self {
        Self {
            relative_path: value.relative_path,
            file_name: value.file_name,
            size_bytes: value.size_bytes,
            modified_at_unix_ms: value.modified_at_unix_ms,
            contents: value.contents,
            is_truncated: value.is_truncated,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum DiagnosticsPageDirectionState {
    Older,
    Newer,
}

impl From<DiagnosticsPageDirectionState> for DiagnosticsPageDirection {
    fn from(value: DiagnosticsPageDirectionState) -> Self {
        match value {
            DiagnosticsPageDirectionState::Older => Self::Older,
            DiagnosticsPageDirectionState::Newer => Self::Newer,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DiagnosticsTextPageState {
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

impl From<DiagnosticsTextPage> for DiagnosticsTextPageState {
    fn from(value: DiagnosticsTextPage) -> Self {
        Self {
            text: value.text,
            start_offset: value.start_offset,
            end_offset: value.end_offset,
            total_bytes: value.total_bytes,
            next_cursor: value.next_cursor,
            has_more_older: value.has_more_older,
            has_more_newer: value.has_more_newer,
            is_head_aligned: value.is_head_aligned,
            is_tail_aligned: value.is_tail_aligned,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LogFilePageState {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub page: DiagnosticsTextPageState,
}

impl From<FireLogFilePage> for LogFilePageState {
    fn from(value: FireLogFilePage) -> Self {
        Self {
            relative_path: value.relative_path,
            file_name: value.file_name,
            size_bytes: value.size_bytes,
            modified_at_unix_ms: value.modified_at_unix_ms,
            page: value.page.into(),
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum HostLogLevelState {
    Debug,
    Info,
    Warn,
    Error,
}

impl From<HostLogLevelState> for FireHostLogLevel {
    fn from(value: HostLogLevelState) -> Self {
        match value {
            HostLogLevelState::Debug => Self::Debug,
            HostLogLevelState::Info => Self::Info,
            HostLogLevelState::Warn => Self::Warn,
            HostLogLevelState::Error => Self::Error,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum NetworkTraceOutcomeState {
    InProgress,
    Succeeded,
    Failed,
    Cancelled,
}

impl From<NetworkTraceOutcome> for NetworkTraceOutcomeState {
    fn from(value: NetworkTraceOutcome) -> Self {
        match value {
            NetworkTraceOutcome::InProgress => Self::InProgress,
            NetworkTraceOutcome::Succeeded => Self::Succeeded,
            NetworkTraceOutcome::Failed => Self::Failed,
            NetworkTraceOutcome::Cancelled => Self::Cancelled,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceHeaderState {
    pub name: String,
    pub value: String,
}

impl From<NetworkTraceHeader> for NetworkTraceHeaderState {
    fn from(value: NetworkTraceHeader) -> Self {
        Self {
            name: value.name,
            value: value.value,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceEventState {
    pub sequence: u32,
    pub timestamp_unix_ms: u64,
    pub phase: String,
    pub summary: String,
    pub details: Option<String>,
}

impl From<NetworkTraceEvent> for NetworkTraceEventState {
    fn from(value: NetworkTraceEvent) -> Self {
        Self {
            sequence: value.sequence,
            timestamp_unix_ms: value.timestamp_unix_ms,
            phase: value.phase,
            summary: value.summary,
            details: value.details,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceSummaryState {
    pub id: u64,
    pub call_id: Option<u64>,
    pub operation: String,
    pub method: String,
    pub url: String,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub duration_ms: Option<u64>,
    pub outcome: NetworkTraceOutcomeState,
    pub status_code: Option<u16>,
    pub error_message: Option<String>,
    pub response_content_type: Option<String>,
    pub response_body_truncated: bool,
}

impl From<NetworkTraceSummary> for NetworkTraceSummaryState {
    fn from(value: NetworkTraceSummary) -> Self {
        Self {
            id: value.id,
            call_id: value.call_id,
            operation: value.operation,
            method: value.method,
            url: value.url,
            started_at_unix_ms: value.started_at_unix_ms,
            finished_at_unix_ms: value.finished_at_unix_ms,
            duration_ms: value.duration_ms,
            outcome: value.outcome.into(),
            status_code: value.status_code,
            error_message: value.error_message,
            response_content_type: value.response_content_type,
            response_body_truncated: value.response_body_truncated,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceDetailState {
    pub summary: NetworkTraceSummaryState,
    pub request_headers: Vec<NetworkTraceHeaderState>,
    pub response_headers: Vec<NetworkTraceHeaderState>,
    pub response_body: Option<String>,
    pub response_body_truncated: bool,
    pub response_body_storage_truncated: bool,
    pub response_body_stored_bytes: Option<u64>,
    pub response_body_page_available: bool,
    pub response_body_bytes: Option<u64>,
    pub events: Vec<NetworkTraceEventState>,
}

impl From<NetworkTraceDetail> for NetworkTraceDetailState {
    fn from(value: NetworkTraceDetail) -> Self {
        Self {
            summary: NetworkTraceSummaryState {
                id: value.id,
                call_id: value.call_id,
                operation: value.operation,
                method: value.method,
                url: value.url,
                started_at_unix_ms: value.started_at_unix_ms,
                finished_at_unix_ms: value.finished_at_unix_ms,
                duration_ms: value.duration_ms,
                outcome: value.outcome.into(),
                status_code: value.status_code,
                error_message: value.error_message,
                response_content_type: value.response_content_type,
                response_body_truncated: value.response_body_truncated,
            },
            request_headers: value.request_headers.into_iter().map(Into::into).collect(),
            response_headers: value.response_headers.into_iter().map(Into::into).collect(),
            response_body: value.response_body,
            response_body_truncated: value.response_body_truncated,
            response_body_storage_truncated: value.response_body_storage_truncated,
            response_body_stored_bytes: value.response_body_stored_bytes,
            response_body_page_available: value.response_body_page_available,
            response_body_bytes: value.response_body_bytes,
            events: value.events.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceBodyPageState {
    pub trace_id: u64,
    pub response_content_type: Option<String>,
    pub response_body_storage_truncated: bool,
    pub response_body_stored_bytes: Option<u64>,
    pub page: DiagnosticsTextPageState,
}

impl From<NetworkTraceBodyPage> for NetworkTraceBodyPageState {
    fn from(value: NetworkTraceBodyPage) -> Self {
        Self {
            trace_id: value.trace_id,
            response_content_type: value.response_content_type,
            response_body_storage_truncated: value.response_body_storage_truncated,
            response_body_stored_bytes: value.response_body_stored_bytes,
            page: value.page.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SupportBundleHostContextState {
    pub platform: String,
    pub app_version: Option<String>,
    pub build_number: Option<String>,
    pub scene_phase: Option<String>,
}

impl From<SupportBundleHostContextState> for FireSupportBundleHostContext {
    fn from(value: SupportBundleHostContextState) -> Self {
        Self {
            platform: value.platform,
            app_version: value.app_version,
            build_number: value.build_number,
            scene_phase: value.scene_phase,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SupportBundleExportState {
    pub file_name: String,
    pub relative_path: String,
    pub absolute_path: String,
    pub size_bytes: u64,
    pub created_at_unix_ms: u64,
    pub diagnostic_session_id: String,
}

impl From<FireSupportBundleExport> for SupportBundleExportState {
    fn from(value: FireSupportBundleExport) -> Self {
        Self {
            file_name: value.file_name,
            relative_path: value.relative_path,
            absolute_path: value.absolute_path,
            size_bytes: value.size_bytes,
            created_at_unix_ms: value.created_at_unix_ms,
            diagnostic_session_id: value.diagnostic_session_id,
        }
    }
}
