#[uniffi::export]
impl FireAppCore {
    pub fn register_state_observer(&self, observer: Arc<dyn StateObserver>) {
        let session_observer = observer.clone();
        let topic_list_observer = observer.clone();
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
            reason: fire_core::CloudflareChallengeFailureReason::Required,
        });

        assert!(matches!(
            error,
            FireUniFfiError::CloudflareChallenge { reason }
                if reason == "required"
        ));
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
