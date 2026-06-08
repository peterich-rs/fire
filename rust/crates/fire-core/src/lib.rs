mod app_state_refresher;
mod config;
mod cookies;
mod core;
mod creation_payloads;
mod diagnostics;
mod error;
mod json_helpers;
mod ldc_payloads;
mod logging;
mod notification_payloads;
mod parsing;
mod preloaded_data;
mod presentation;
mod rich_text;
mod search_payloads;
mod session_store;
mod state_observer;
mod sync_utils;
mod topic_payloads;
mod user_payloads;
mod workspace;

pub use config::FireCoreConfig;
pub use core::{
    FireAuthRecoveryHint, FireAuthRecoveryHintReason, FireCore, FireSessionPersistenceState,
};
pub use diagnostics::{
    DiagnosticsPageDirection, DiagnosticsTextPage, FireLogFileDetail, FireLogFilePage,
    FireLogFileSummary, FireSupportBundleExport, FireSupportBundleHostContext,
    NetworkTraceBodyPage, NetworkTraceDetail, NetworkTraceEvent, NetworkTraceHeader,
    NetworkTraceOutcome, NetworkTraceSummary,
};
pub use error::FireCoreError;
pub use fire_models::LoginFinalizationResult;
pub use logging::{FireHostLogLevel, FireLogger, FireLoggerConfig};
pub use presentation::{
    monogram_for_username, plain_text_from_html, preview_text_from_html, topic_status_labels,
};
pub use rich_text::{parse_cooked_html, render_cooked_html};
pub use state_observer::{FireStateObserverCallbacks, FireStateObserverRegistry};
