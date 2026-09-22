mod app_state_refresher;
mod chat_payloads;
mod config;
mod cookies;
mod core;
mod creation_payloads;
mod diagnostics;
mod doh;
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

pub use chat_payloads::{
    chat_bus_event_from_payload, chat_channel_from_bus_payload, chat_message_from_bus_payload,
};
pub use config::FireCoreConfig;
pub use core::{
    FireAuthRecoveryHint, FireAuthRecoveryHintReason, FireCore, FireSessionPersistenceState,
    TopicDetailObserver, TopicDetailOpenRequest, TopicDetailSession, TopicDetailSessionRegistry,
};
pub use diagnostics::{
    DiagnosticsPageDirection, DiagnosticsTextPage, FireLogFileDetail, FireLogFilePage,
    FireLogFileSummary, FireSupportBundleExport, FireSupportBundleHostContext,
    NetworkTraceBodyPage, NetworkTraceDetail, NetworkTraceEvent, NetworkTraceHeader,
    NetworkTraceOutcome, NetworkTraceSummary,
};
pub use doh::{FireDohController, FireDohResolver};
pub use error::{CloudflareChallengeFailureReason, FireCoreError};
pub use fire_models::LoginFinalizationResult;
pub use fire_models::{DohPreset, DohProbeResult, DohSettings};
pub use fire_rich_text::PresentedDocument;
pub use logging::{FireHostLogLevel, FireLogger, FireLoggerConfig};
pub use presentation::{
    monogram_for_username, plain_text_from_html, preview_text_from_html, topic_status_labels,
};
pub use rich_text::{
    attach_boost_presentation, attach_chat_message_presentation, attach_post_presentation,
    attach_posts_presentation, parse_cooked_html, present_cooked_html, render_cooked_html,
};
pub use state_observer::{FireStateObserverCallbacks, FireStateObserverRegistry};
