uniffi::setup_scaffolding!("fire_uniffi");

use std::sync::Arc;

use fire_core::{
    monogram_for_username as shared_monogram_for_username,
    parse_cooked_html as shared_parse_cooked_html,
    plain_text_from_html as shared_plain_text_from_html,
    present_cooked_html as shared_present_cooked_html,
    preview_text_from_html as shared_preview_text_from_html, FireStateObserverCallbacks,
};
use fire_models::{CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind};
use fire_uniffi_chat::FireChatHandle;
use fire_uniffi_diagnostics::FireDiagnosticsHandle;
use fire_uniffi_ldc::FireLdcHandle;
use fire_uniffi_messagebus::FireMessageBusHandle;
use fire_uniffi_notifications::{FireNotificationsHandle, NotificationCenterState};
use fire_uniffi_search::FireSearchHandle;
use fire_uniffi_session::{FireSessionHandle, SessionState};
use fire_uniffi_topics::{FireTopicsHandle, TopicListRowPatchBatchState};
use fire_uniffi_types::{FireUniFfiError, SharedFireCore, TopicListState};
use fire_uniffi_user::FireUserHandle;

include!("records/rich_text.rs");

#[uniffi::export(with_foreign)]
pub trait StateObserver: Send + Sync {
    fn on_session_snapshot(&self, snapshot: SessionState);
    fn on_topic_list_snapshot(&self, snapshot: TopicListState);
    fn on_topic_list_patches(&self, batch: TopicListRowPatchBatchState);
    fn on_notification_center_snapshot(&self, snapshot: NotificationCenterState);
}

#[derive(uniffi::Object)]
pub struct FireAppCore {
    shared: Arc<SharedFireCore>,
    chat: Arc<FireChatHandle>,
    diagnostics: Arc<FireDiagnosticsHandle>,
    ldc: Arc<FireLdcHandle>,
    messagebus: Arc<FireMessageBusHandle>,
    notifications: Arc<FireNotificationsHandle>,
    search: Arc<FireSearchHandle>,
    session: Arc<FireSessionHandle>,
    topics: Arc<FireTopicsHandle>,
    user: Arc<FireUserHandle>,
}

include!("handle/construct.rs");
include!("handle/domains.rs");
include!("handle/observers.rs");
