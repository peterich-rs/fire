uniffi::setup_scaffolding!("fire_uniffi");

pub mod handle;
pub mod state_diagnostics;
pub mod state_messagebus;
pub mod state_notification;
pub mod state_search;
pub mod state_session;
pub mod state_topic_detail;
pub mod state_topic_list;
pub mod state_user;

pub use fire_uniffi_types::{
    constructor_guard, ffi_runtime, run_fallible, run_infallible, run_on_ffi_runtime,
    CapturedPanic, FireUniFfiError, PanicState, SharedFireCore,
};

pub use handle::*;
pub use state_diagnostics::*;
pub use state_messagebus::*;
pub use state_notification::*;
pub use state_search::*;
pub use state_session::*;
pub use state_topic_detail::*;
pub use state_topic_list::*;
pub use state_user::*;

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io, path::PathBuf};

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
    fn topic_detail_state_carries_interaction_count() {
        use fire_models::{TopicDetail, TopicPost, TopicPostStream, TopicReaction};

        let state = TopicDetailState::from(TopicDetail {
            like_count: 8,
            post_stream: TopicPostStream {
                posts: vec![TopicPost {
                    reactions: vec![TopicReaction {
                        id: "clap".into(),
                        count: 2,
                        ..TopicReaction::default()
                    }],
                    ..TopicPost::default()
                }],
                ..TopicPostStream::default()
            },
            ..TopicDetail::default()
        });

        assert_eq!(state.interaction_count, 10);
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
        let handle = FireCoreHandle::new(None, None).expect("constructor should succeed");

        let error = handle
            .run_infallible("test_sync_panic", |_| {
                panic!("boom");
            })
            .expect_err("panic should map to an internal error");

        assert!(matches!(
            error,
            FireUniFfiError::Internal { details } if details.contains("test_sync_panic panicked: boom")
        ));
        assert!(matches!(
            handle.panic_state.ensure_healthy("snapshot"),
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
