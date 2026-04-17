uniffi::setup_scaffolding!("fire_uniffi_diagnostics");

use std::sync::Arc;

use fire_uniffi_types::{run_fallible, run_infallible, FireUniFfiError, SharedFireCore};

pub mod records;

pub use records::{
    DiagnosticsPageDirectionState, DiagnosticsTextPageState, HostLogLevelState, LogFileDetailState,
    LogFilePageState, LogFileSummaryState, NetworkTraceBodyPageState, NetworkTraceDetailState,
    NetworkTraceEventState, NetworkTraceHeaderState, NetworkTraceOutcomeState,
    NetworkTraceSummaryState, SupportBundleExportState, SupportBundleHostContextState,
};

#[derive(uniffi::Object)]
pub struct FireDiagnosticsHandle {
    shared: Arc<SharedFireCore>,
}

impl FireDiagnosticsHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireDiagnosticsHandle {
    pub fn diagnostic_session_id(&self) -> Result<String, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "diagnostic_session_id",
            |inner| inner.diagnostic_session_id(),
        )
    }

    pub fn export_support_bundle(
        &self,
        host_context: SupportBundleHostContextState,
    ) -> Result<SupportBundleExportState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "export_support_bundle",
            move |inner| {
                inner
                    .export_support_bundle(host_context.into())
                    .map(Into::into)
            },
        )
    }

    pub fn flush_logs(&self, sync: bool) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "flush_logs",
            move |inner| inner.flush_logs(sync),
        )
    }

    pub fn log_host(
        &self,
        level: HostLogLevelState,
        target: String,
        message: String,
    ) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "log_host",
            move |inner| inner.log_host(level.into(), target, message),
        )
    }

    pub fn list_log_files(&self) -> Result<Vec<LogFileSummaryState>, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "list_log_files",
            |inner| {
                inner
                    .list_log_files()
                    .map(|items| items.into_iter().map(Into::into).collect())
            },
        )
    }

    pub fn read_log_file(
        &self,
        relative_path: String,
    ) -> Result<LogFileDetailState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "read_log_file",
            move |inner| inner.read_log_file(relative_path).map(Into::into),
        )
    }

    pub fn read_log_file_page(
        &self,
        relative_path: String,
        cursor: Option<u64>,
        max_bytes: Option<u64>,
        direction: DiagnosticsPageDirectionState,
    ) -> Result<LogFilePageState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "read_log_file_page",
            move |inner| {
                inner
                    .read_log_file_page(
                        relative_path,
                        cursor,
                        max_bytes
                            .and_then(|value| usize::try_from(value).ok())
                            .unwrap_or_default(),
                        direction.into(),
                    )
                    .map(Into::into)
            },
        )
    }

    pub fn list_network_traces(
        &self,
        limit: u64,
    ) -> Result<Vec<NetworkTraceSummaryState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "list_network_traces",
            move |inner| {
                let limit = usize::try_from(limit).unwrap_or(usize::MAX);
                inner
                    .list_network_traces(limit)
                    .into_iter()
                    .map(Into::into)
                    .collect()
            },
        )
    }

    pub fn network_trace_detail(
        &self,
        trace_id: u64,
    ) -> Result<Option<NetworkTraceDetailState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "network_trace_detail",
            move |inner| inner.network_trace_detail(trace_id).map(Into::into),
        )
    }

    pub fn network_trace_body_page(
        &self,
        trace_id: u64,
        cursor: Option<u64>,
        max_bytes: Option<u64>,
        direction: DiagnosticsPageDirectionState,
    ) -> Result<Option<NetworkTraceBodyPageState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "network_trace_body_page",
            move |inner| {
                inner
                    .network_trace_body_page(
                        trace_id,
                        cursor,
                        max_bytes
                            .and_then(|value| usize::try_from(value).ok())
                            .unwrap_or_default(),
                        direction.into(),
                    )
                    .map(Into::into)
            },
        )
    }
}
