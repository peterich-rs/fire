uniffi::setup_scaffolding!("fire_uniffi");

use std::sync::Arc;

use fire_core::{
    monogram_for_username as shared_monogram_for_username,
    plain_text_from_html as shared_plain_text_from_html,
    preview_text_from_html as shared_preview_text_from_html,
};
use fire_uniffi_diagnostics::FireDiagnosticsHandle;
use fire_uniffi_messagebus::FireMessageBusHandle;
use fire_uniffi_notifications::FireNotificationsHandle;
use fire_uniffi_search::FireSearchHandle;
use fire_uniffi_session::FireSessionHandle;
use fire_uniffi_topics::FireTopicsHandle;
use fire_uniffi_types::{FireUniFfiError, SharedFireCore};
use fire_uniffi_user::FireUserHandle;

#[uniffi::export]
pub fn plain_text_from_html(raw_html: String) -> String {
    shared_plain_text_from_html(&raw_html)
}

#[uniffi::export]
pub fn preview_text_from_html(raw_html: Option<String>) -> Option<String> {
    shared_preview_text_from_html(raw_html.as_deref())
}

#[uniffi::export]
pub fn monogram_for_username(username: String) -> String {
    shared_monogram_for_username(&username)
}

#[derive(uniffi::Object)]
pub struct FireAppCore {
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
}

#[cfg(test)]
mod tests {
    use fire_uniffi_types::{
        ffi_runtime, run_infallible, run_on_ffi_runtime, FireUniFfiError, PanicState,
        SharedFireCore,
    };

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
