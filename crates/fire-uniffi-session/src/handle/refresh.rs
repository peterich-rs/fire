use std::sync::Arc;

use fire_uniffi_types::{run_infallible, run_on_ffi_runtime, FireUniFfiError};

use crate::records::*;
use crate::FireSessionHandle;

#[uniffi::export]
impl FireSessionHandle {
    pub fn apply_bootstrap(
        &self,
        bootstrap: BootstrapState,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_bootstrap",
            move |inner| SessionState::from_snapshot(inner.apply_bootstrap(bootstrap.into())),
        )
    }
    pub fn apply_csrf_token(&self, csrf_token: String) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_csrf_token",
            move |inner| SessionState::from_snapshot(inner.apply_csrf_token(csrf_token)),
        )
    }
    pub fn clear_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "clear_csrf_token",
            |inner| SessionState::from_snapshot(inner.clear_csrf_token()),
        )
    }
    pub fn apply_home_html(&self, html: String) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_home_html",
            move |inner| SessionState::from_snapshot(inner.apply_home_html(html)),
        )
    }
    pub async fn refresh_bootstrap(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("refresh_bootstrap", panic_state, async move {
            inner.refresh_bootstrap().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }
    pub async fn refresh_bootstrap_if_needed(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("refresh_bootstrap_if_needed", panic_state, async move {
            inner.refresh_bootstrap_if_needed().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }
    pub async fn refresh_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("refresh_csrf_token", panic_state, async move {
            inner.refresh_csrf_token().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }
    pub async fn refresh_csrf_token_if_needed(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot =
            run_on_ffi_runtime("refresh_csrf_token_if_needed", panic_state, async move {
                inner.refresh_csrf_token_if_needed().await
            })
            .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }
    pub fn record_fingerprint_done(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "record_fingerprint_done",
            move |inner| {
                SessionState::from_snapshot(
                    inner.record_fingerprint_done(cookies.into_iter().map(Into::into).collect()),
                )
            },
        )
    }
    pub async fn ensure_preloaded_data_loaded(&self) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("ensure_preloaded_data_loaded", panic_state, async move {
            let service = inner.preloaded_data_service();
            service.ensure_loaded().await?;
            Ok(())
        })
        .await
    }
    pub async fn await_preloaded_data(&self) -> Result<PreloadedDataStateState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime("await_preloaded_data", panic_state, async move {
            let service = inner.preloaded_data_service();
            service.ensure_loaded().await
        })
        .await;
        match result {
            Ok(_) => Ok(PreloadedDataStateState::Ready),
            Err(e) => Ok(PreloadedDataStateState::Failed {
                error: e.to_string(),
            }),
        }
    }
    pub fn current_user_snapshot(
        &self,
    ) -> Result<Option<CurrentUserSnapshotState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "current_user_snapshot",
            |inner| {
                inner
                    .preloaded_data_service()
                    .get_current_user()
                    .map(CurrentUserSnapshotState::from)
            },
        )
    }
    pub fn cached_user(&self) -> Result<Option<CurrentUserSnapshotState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "cached_user",
            |inner| {
                inner
                    .preloaded_data_service()
                    .get_cached_user()
                    .map(CurrentUserSnapshotState::from)
            },
        )
    }
    pub async fn trigger_app_state_refresh(
        &self,
        trigger: RefreshTriggerState,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let rust_trigger = fire_models::RefreshTrigger::from(trigger);
        run_on_ffi_runtime("trigger_app_state_refresh", panic_state, async move {
            inner
                .app_state_refresher()
                .refresh_all(rust_trigger)
                .await?;
            Ok(())
        })
        .await
    }
    pub async fn trigger_app_state_refresh_with_handler(
        &self,
        trigger: RefreshTriggerState,
        handler: Arc<dyn AppStateRefreshHandler>,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let rust_trigger = fire_models::RefreshTrigger::from(trigger);
        let observer: Arc<dyn Fn(fire_models::AppStateRefreshEvent) + Send + Sync> =
            Arc::new(move |event: fire_models::AppStateRefreshEvent| {
                handler.on_app_state_refresh_event(event.into());
            });
        run_on_ffi_runtime(
            "trigger_app_state_refresh_with_handler",
            panic_state,
            async move {
                inner
                    .app_state_refresher()
                    .refresh_all_with_handler(rust_trigger, Some(observer))
                    .await?;
                Ok(())
            },
        )
        .await
    }
}
