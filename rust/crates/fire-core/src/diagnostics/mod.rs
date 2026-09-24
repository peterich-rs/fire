mod bundle;
mod listener;
mod logs;
mod models;
mod store;

#[cfg(test)]
mod tests;

pub use models::{
    DiagnosticsPageDirection, DiagnosticsTextPage, FireLogFileDetail, FireLogFilePage,
    FireLogFileSummary, FireSupportBundleExport, FireSupportBundleHostContext,
    NetworkTraceBodyPage, NetworkTraceDetail, NetworkTraceEvent, NetworkTraceHeader,
    NetworkTraceOutcome, NetworkTraceSummary,
};

pub(crate) use bundle::{export_feedback_bundle, export_support_bundle};
pub(crate) use listener::FireNetworkTraceEventListenerFactory;
pub(crate) use logs::{list_log_files, read_log_file, read_log_file_page};
pub(crate) use models::FireRequestTraceMetadata;
#[cfg(test)]
pub(crate) use models::{
    MAX_RESPONSE_BODY_BYTES, MAX_RESPONSE_BODY_INLINE_BYTES, SUPPORT_BUNDLE_DIR_NAME,
};
pub(crate) use store::{FireDiagnosticsStore, FireNetworkTraceCancellationGuard};
