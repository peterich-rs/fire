uniffi::setup_scaffolding!("fire_uniffi");

use std::sync::Arc;

use fire_core::{
    monogram_for_username as shared_monogram_for_username,
    parse_cooked_html as shared_parse_cooked_html,
    plain_text_from_html as shared_plain_text_from_html,
    preview_text_from_html as shared_preview_text_from_html,
    render_cooked_html as shared_render_cooked_html, FireStateObserverCallbacks,
};
use fire_models::{CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind};
use fire_uniffi_diagnostics::FireDiagnosticsHandle;
use fire_uniffi_messagebus::FireMessageBusHandle;
use fire_uniffi_notifications::{FireNotificationsHandle, NotificationCenterState};
use fire_uniffi_search::FireSearchHandle;
use fire_uniffi_session::{FireSessionHandle, SessionState};
use fire_uniffi_topics::FireTopicsHandle;
use fire_uniffi_topics::TopicDetailFeedSnapshotState;
use fire_uniffi_types::{FireUniFfiError, RenderDocumentState, SharedFireCore, TopicListState};
use fire_uniffi_user::FireUserHandle;

#[uniffi::export]
pub fn plain_text_from_html(raw_html: String) -> String {
    shared_plain_text_from_html(&raw_html)
}

#[uniffi::export]
pub fn parse_cooked_html(raw_html: String) -> CookedHtmlDocumentState {
    shared_parse_cooked_html(&raw_html).into()
}

#[uniffi::export]
pub fn render_cooked_html(raw_html: String, base_url: String) -> RenderDocumentState {
    shared_render_cooked_html(&raw_html, &base_url).into()
}

#[uniffi::export]
pub fn preview_text_from_html(raw_html: Option<String>) -> Option<String> {
    shared_preview_text_from_html(raw_html.as_deref())
}

#[uniffi::export]
pub fn monogram_for_username(username: String) -> String {
    shared_monogram_for_username(&username)
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum CookedHtmlNodeKindState {
    Document,
    Text,
    Paragraph,
    Heading,
    LineBreak,
    Strong,
    Emphasis,
    Strikethrough,
    Link,
    Image,
    Emoji,
    Code,
    CodeBlock,
    Blockquote,
    DiscourseQuote,
    Divider,
    List,
    ListItem,
    Spoiler,
    Details,
    Table,
    TableRow,
    TableCell,
    Onebox,
    Iframe,
    Mention,
    Hashtag,
    Attachment,
    Unknown,
}

impl From<CookedHtmlNodeKind> for CookedHtmlNodeKindState {
    fn from(value: CookedHtmlNodeKind) -> Self {
        match value {
            CookedHtmlNodeKind::Document => Self::Document,
            CookedHtmlNodeKind::Text => Self::Text,
            CookedHtmlNodeKind::Paragraph => Self::Paragraph,
            CookedHtmlNodeKind::Heading => Self::Heading,
            CookedHtmlNodeKind::LineBreak => Self::LineBreak,
            CookedHtmlNodeKind::Strong => Self::Strong,
            CookedHtmlNodeKind::Emphasis => Self::Emphasis,
            CookedHtmlNodeKind::Strikethrough => Self::Strikethrough,
            CookedHtmlNodeKind::Link => Self::Link,
            CookedHtmlNodeKind::Image => Self::Image,
            CookedHtmlNodeKind::Emoji => Self::Emoji,
            CookedHtmlNodeKind::Code => Self::Code,
            CookedHtmlNodeKind::CodeBlock => Self::CodeBlock,
            CookedHtmlNodeKind::Blockquote => Self::Blockquote,
            CookedHtmlNodeKind::DiscourseQuote => Self::DiscourseQuote,
            CookedHtmlNodeKind::Divider => Self::Divider,
            CookedHtmlNodeKind::List => Self::List,
            CookedHtmlNodeKind::ListItem => Self::ListItem,
            CookedHtmlNodeKind::Spoiler => Self::Spoiler,
            CookedHtmlNodeKind::Details => Self::Details,
            CookedHtmlNodeKind::Table => Self::Table,
            CookedHtmlNodeKind::TableRow => Self::TableRow,
            CookedHtmlNodeKind::TableCell => Self::TableCell,
            CookedHtmlNodeKind::Onebox => Self::Onebox,
            CookedHtmlNodeKind::Iframe => Self::Iframe,
            CookedHtmlNodeKind::Mention => Self::Mention,
            CookedHtmlNodeKind::Hashtag => Self::Hashtag,
            CookedHtmlNodeKind::Attachment => Self::Attachment,
            CookedHtmlNodeKind::Unknown => Self::Unknown,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookedHtmlAttributeState {
    pub name: String,
    pub value: String,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookedHtmlNodeState {
    pub id: u32,
    pub parent_id: Option<u32>,
    pub kind: CookedHtmlNodeKindState,
    pub depth: u32,
    pub text: Option<String>,
    pub url: Option<String>,
    pub title: Option<String>,
    pub alt: Option<String>,
    pub level: Option<u32>,
    pub ordered: Option<bool>,
    pub attributes: Vec<CookedHtmlAttributeState>,
}

impl From<CookedHtmlNode> for CookedHtmlNodeState {
    fn from(value: CookedHtmlNode) -> Self {
        Self {
            id: value.id,
            parent_id: value.parent_id,
            kind: value.kind.into(),
            depth: value.depth,
            text: value.text,
            url: value.url,
            title: value.title,
            alt: value.alt,
            level: value.level,
            ordered: value.ordered,
            attributes: value
                .attributes
                .into_iter()
                .map(|(name, value)| CookedHtmlAttributeState { name, value })
                .collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookedHtmlDocumentState {
    pub nodes: Vec<CookedHtmlNodeState>,
    pub plain_text: String,
    pub image_urls: Vec<String>,
    pub link_urls: Vec<String>,
}

impl From<CookedHtmlDocument> for CookedHtmlDocumentState {
    fn from(value: CookedHtmlDocument) -> Self {
        Self {
            nodes: value.nodes.into_iter().map(Into::into).collect(),
            plain_text: value.plain_text,
            image_urls: value.image_urls,
            link_urls: value.link_urls,
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait StateObserver: Send + Sync {
    fn on_session_snapshot(&self, snapshot: SessionState);
    fn on_topic_list_snapshot(&self, snapshot: TopicListState);
    fn on_topic_detail_feed_snapshot(&self, snapshot: TopicDetailFeedSnapshotState);
    fn on_notification_center_snapshot(&self, snapshot: NotificationCenterState);
}

#[derive(uniffi::Object)]
pub struct FireAppCore {
    shared: Arc<SharedFireCore>,
    diagnostics: Arc<FireDiagnosticsHandle>,
    messagebus: Arc<FireMessageBusHandle>,
    notifications: Arc<FireNotificationsHandle>,
    search: Arc<FireSearchHandle>,
    session: Arc<FireSessionHandle>,
    topics: Arc<FireTopicsHandle>,
    user: Arc<FireUserHandle>,
}

#[uniffi::export]
impl FireAppCore {
    #[uniffi::constructor]
    pub fn new(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Arc<Self>, FireUniFfiError> {
        let shared = Arc::new(SharedFireCore::bootstrap(base_url, workspace_path)?);
        Ok(Arc::new(Self {
            shared: shared.clone(),
            diagnostics: FireDiagnosticsHandle::from_shared(shared.clone()),
            messagebus: FireMessageBusHandle::from_shared(shared.clone()),
            notifications: FireNotificationsHandle::from_shared(shared.clone()),
            search: FireSearchHandle::from_shared(shared.clone()),
            session: FireSessionHandle::from_shared(shared.clone()),
            topics: FireTopicsHandle::from_shared(shared.clone()),
            user: FireUserHandle::from_shared(shared),
        }))
    }

    pub fn diagnostics(&self) -> Arc<FireDiagnosticsHandle> {
        self.diagnostics.clone()
    }

    pub fn messagebus(&self) -> Arc<FireMessageBusHandle> {
        self.messagebus.clone()
    }

    pub fn notifications(&self) -> Arc<FireNotificationsHandle> {
        self.notifications.clone()
    }

    pub fn search(&self) -> Arc<FireSearchHandle> {
        self.search.clone()
    }

    pub fn session(&self) -> Arc<FireSessionHandle> {
        self.session.clone()
    }

    pub fn topics(&self) -> Arc<FireTopicsHandle> {
        self.topics.clone()
    }

    pub fn user(&self) -> Arc<FireUserHandle> {
        self.user.clone()
    }

    pub fn register_state_observer(&self, observer: Arc<dyn StateObserver>) {
        let base_url = self.shared.core.base_url().to_string();
        let session_observer = observer.clone();
        let topic_list_observer = observer.clone();
        let topic_detail_observer = observer.clone();
        let notification_observer = observer;
        self.shared
            .core
            .state_observers()
            .set(FireStateObserverCallbacks {
                session: Arc::new(move |snapshot| {
                    session_observer.on_session_snapshot(SessionState::from_snapshot(snapshot));
                }),
                topic_list: Arc::new(move |snapshot| {
                    topic_list_observer.on_topic_list_snapshot(snapshot.into());
                }),
                topic_detail_feed: Arc::new(move |snapshot| {
                    topic_detail_observer.on_topic_detail_feed_snapshot(
                        fire_uniffi_topics::records::topic_detail_feed_snapshot_state_from_model(
                            snapshot, &base_url,
                        ),
                    );
                }),
                notification_center: Arc::new(move |snapshot| {
                    notification_observer.on_notification_center_snapshot(snapshot.into());
                }),
            });
    }

    pub fn unregister_state_observer(&self) {
        self.shared.core.state_observers().clear();
    }
}

#[cfg(test)]
mod tests {
    use crate::{parse_cooked_html, CookedHtmlNodeKindState};
    use fire_uniffi_types::{
        ffi_runtime, run_infallible, run_on_ffi_runtime, FireUniFfiError, PanicState,
        SharedFireCore,
    };

    #[test]
    fn parse_cooked_html_exposes_shared_ast_record() {
        let document = parse_cooked_html(
            r#"<p>Hello <a href="/t/123/4">topic</a></p><img src="/uploads/fire.png" alt="fire">"#
                .to_string(),
        );

        assert_eq!(document.plain_text, "Hello topic\n\nfire");
        assert_eq!(document.image_urls, vec!["/uploads/fire.png".to_string()]);
        assert_eq!(document.link_urls, vec!["/t/123/4".to_string()]);
        assert!(document
            .nodes
            .iter()
            .any(|node| node.kind == CookedHtmlNodeKindState::Link
                && node.url.as_deref() == Some("/t/123/4")));
    }

    #[test]
    fn maps_http_status_errors_without_flattening() {
        let error = FireUniFfiError::from(fire_core::FireCoreError::HttpStatus {
            operation: "fetch topic list",
            status: 429,
            body: "slow down".to_string(),
        });

        assert!(matches!(
            error,
            FireUniFfiError::HttpStatus {
                operation,
                status: 429,
                body,
            } if operation == "fetch topic list" && body == "slow down"
        ));
    }

    #[test]
    fn maps_cloudflare_challenge_errors_to_dedicated_variant() {
        let error = FireUniFfiError::from(fire_core::FireCoreError::CloudflareChallenge {
            operation: "create reply",
        });

        assert!(matches!(error, FireUniFfiError::CloudflareChallenge));
    }

    #[test]
    fn maps_login_required_errors_to_dedicated_variant() {
        let error = FireUniFfiError::from(fire_core::FireCoreError::LoginRequired {
            operation: "report topic timings",
            message: "您需要登录才能执行此操作。".to_string(),
        });

        assert!(matches!(
            error,
            FireUniFfiError::LoginRequired { details }
                if details == "您需要登录才能执行此操作。"
        ));
    }

    #[test]
    fn maps_stale_session_response_errors_to_dedicated_variant() {
        let error = FireUniFfiError::from(fire_core::FireCoreError::StaleSessionResponse {
            operation: "fetch topic list",
        });

        assert!(matches!(
            error,
            FireUniFfiError::StaleSessionResponse { operation }
                if operation == "fetch topic list"
        ));
    }

    #[test]
    fn maps_storage_errors_to_storage_variant() {
        use std::{io, path::PathBuf};

        let error = FireUniFfiError::from(fire_core::FireCoreError::PersistIo {
            path: PathBuf::from("/tmp/session.json"),
            source: io::Error::new(io::ErrorKind::PermissionDenied, "denied"),
        });

        assert!(matches!(
            error,
            FireUniFfiError::Storage { details }
                if details.contains("/tmp/session.json") && details.contains("denied")
        ));
    }

    #[test]
    fn runs_async_work_on_ffi_runtime() {
        let panic_state = std::sync::Arc::new(PanicState::default());
        let value = ffi_runtime()
            .block_on(run_on_ffi_runtime(
                "test_async_success",
                std::sync::Arc::clone(&panic_state),
                async { Ok::<_, fire_core::FireCoreError>(42_u8) },
            ))
            .expect("ffi runtime should resolve async work");

        assert_eq!(value, 42);
    }

    #[test]
    fn converts_sync_panic_to_internal_error_and_poisoned_handle() {
        let shared = std::sync::Arc::new(SharedFireCore::bootstrap(None, None).expect("bootstrap"));

        let error =
            run_infallible::<(), _>(&shared.panic_state, &shared.core, "test_sync_panic", |_| {
                panic!("boom")
            })
            .expect_err("panic should map to an internal error");

        assert!(matches!(
            error,
            FireUniFfiError::Internal { details } if details.contains("test_sync_panic panicked: boom")
        ));
        assert!(matches!(
            shared.panic_state.ensure_healthy("snapshot"),
            Err(FireUniFfiError::Internal { details })
                if details.contains("poisoned by a previous panic")
                    && details.contains("test_sync_panic panicked: boom")
        ));
    }

    #[test]
    fn converts_async_panic_to_internal_error_and_poisoned_handle() {
        let panic_state = std::sync::Arc::new(PanicState::default());

        let error = ffi_runtime()
            .block_on(run_on_ffi_runtime(
                "test_async_panic",
                std::sync::Arc::clone(&panic_state),
                async {
                    panic!("async boom");
                    #[allow(unreachable_code)]
                    Ok::<(), fire_core::FireCoreError>(())
                },
            ))
            .expect_err("panic should map to an internal error");

        assert!(matches!(
            error,
            FireUniFfiError::Internal { details }
                if details.contains("test_async_panic panicked: async boom")
        ));
        assert!(matches!(
            panic_state.ensure_healthy("fetch_topic_list"),
            Err(FireUniFfiError::Internal { details })
                if details.contains("poisoned by a previous panic")
                    && details.contains("test_async_panic panicked: async boom")
        ));
    }
}
