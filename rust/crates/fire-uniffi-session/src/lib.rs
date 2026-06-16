uniffi::setup_scaffolding!("fire_uniffi_session");

use std::sync::Arc;

use fire_uniffi_types::{
    run_fallible, run_infallible, run_on_ffi_runtime, FireUniFfiError, SharedFireCore,
};

pub mod records;

pub use records::{
    format_probe_result, AppStateRefreshEventState, AppStateRefreshHandler, AuthRecoveryHintState,
    BootstrapState, CanonicalCookieState, CloudflareChallengeHandler,
    CloudflareChallengeRequestState, CloudflareChallengeResultState, CookieReplayEntryState,
    CookieSameSiteState, CookieSelfHealingHandler, CookieSelfHealingPhaseState,
    CookieSelfHealingRequestState, CookieSelfHealingResultState, CookieSourceState, CookieState,
    CookieSweepIntentState, CookieSweepPlanState, CurrentUserSnapshotState,
    HomeTopicListScopeState, LoginFailureKindState, LoginFailureState,
    LoginFinalizationResultState, LoginPhaseState, LoginStateDeterminationState, LoginSyncState,
    NuclearResetPlanState, PassiveLogoutTriggerState, PlatformCookieState, PreloadedDataStateState,
    RefreshBatchState, RefreshTriggerState, SecondFactorRequirementState, SessionPersistenceState,
    SessionReadinessState, SessionState, TopicCategoryState, WebViewCookieActionState,
    WebViewCookieInfoState, WebViewLoginDecisionState, WebViewLoginJsResultState,
    WebViewLoginPhaseState,
};

#[derive(uniffi::Object)]
pub struct FireSessionHandle {
    shared: Arc<SharedFireCore>,
}

impl FireSessionHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireSessionHandle {
    pub fn base_url(&self) -> Result<String, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "base_url",
            |inner| inner.base_url().to_string(),
        )
    }

    pub fn workspace_path(&self) -> Result<Option<String>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "workspace_path",
            |inner| {
                inner
                    .workspace_path()
                    .map(|path| path.display().to_string())
            },
        )
    }

    pub fn resolve_workspace_path(&self, relative_path: String) -> Result<String, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "resolve_workspace_path",
            move |inner| {
                inner
                    .resolve_workspace_path(relative_path)
                    .map(|path| path.display().to_string())
            },
        )
    }

    pub fn has_login_session(&self) -> Result<bool, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "has_login_session",
            |inner| inner.has_login_session(),
        )
    }

    pub fn snapshot(&self) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "snapshot",
            |inner| SessionState::from_snapshot(inner.snapshot()),
        )
    }

    pub fn current_home_topic_list_scope(
        &self,
    ) -> Result<HomeTopicListScopeState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "current_home_topic_list_scope",
            |inner| inner.current_home_topic_list_scope().into(),
        )
    }

    pub fn set_current_home_topic_list_scope(
        &self,
        scope: HomeTopicListScopeState,
    ) -> Result<HomeTopicListScopeState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "set_current_home_topic_list_scope",
            move |inner| inner.set_current_home_topic_list_scope(scope.into()).into(),
        )
    }

    pub fn session_epoch(&self) -> Result<u64, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "session_epoch",
            |inner| inner.session_epoch(),
        )
    }

    pub fn session_persistence_state(&self) -> Result<SessionPersistenceState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "session_persistence_state",
            |inner| inner.session_persistence_state().into(),
        )
    }

    pub fn auth_recovery_hint(&self) -> Result<Option<AuthRecoveryHintState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "auth_recovery_hint",
            |inner| inner.auth_recovery_hint().map(Into::into),
        )
    }

    pub fn register_cloudflare_challenge_handler(
        &self,
        handler: Arc<dyn CloudflareChallengeHandler>,
    ) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "register_cloudflare_challenge_handler",
            move |inner| {
                let handler = handler.clone();
                inner.set_cloudflare_challenge_handler(move |request| {
                    let handler = handler.clone();
                    async move { handler.complete_cloudflare_challenge(request.into()).into() }
                });
            },
        )
    }

    pub fn unregister_cloudflare_challenge_handler(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "unregister_cloudflare_challenge_handler",
            |inner| inner.clear_cloudflare_challenge_handler(),
        )
    }

    pub fn export_session_json(&self) -> Result<String, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "export_session_json",
            |inner| inner.export_session_json(),
        )
    }

    pub fn export_redacted_session_json(&self) -> Result<String, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "export_redacted_session_json",
            |inner| inner.export_redacted_session_json(),
        )
    }

    pub fn restore_session_json(&self, json: String) -> Result<SessionState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "restore_session_json",
            move |inner| {
                inner
                    .restore_session_json(json)
                    .map(SessionState::from_snapshot)
            },
        )
    }

    pub fn register_cookie_self_healing_handler(
        &self,
        handler: Arc<dyn CookieSelfHealingHandler>,
    ) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "register_cookie_self_healing_handler",
            move |inner| {
                inner.set_cookie_self_healing_handler(move |request| {
                    let handler = Arc::clone(&handler);
                    async move { handler.heal_cookies(request.into()).into() }
                });
            },
        )
    }

    pub fn unregister_cookie_self_healing_handler(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "unregister_cookie_self_healing_handler",
            move |inner| {
                inner.clear_cookie_self_healing_handler();
            },
        )
    }

    pub fn save_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "save_session_to_path",
            move |inner| inner.save_session_to_path(path),
        )
    }

    pub fn save_redacted_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "save_redacted_session_to_path",
            move |inner| inner.save_redacted_session_to_path(path),
        )
    }

    pub fn load_session_from_path(&self, path: String) -> Result<SessionState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "load_session_from_path",
            move |inner| {
                inner
                    .load_session_from_path(path)
                    .map(SessionState::from_snapshot)
            },
        )
    }

    pub fn clear_session_path(&self, path: String) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "clear_session_path",
            move |inner| inner.clear_session_path(path),
        )
    }

    pub fn apply_cookies(&self, cookies: CookieState) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_cookies",
            move |inner| SessionState::from_snapshot(inner.apply_cookies(cookies.into())),
        )
    }

    pub fn merge_platform_cookies(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "merge_platform_cookies",
            move |inner| {
                SessionState::from_snapshot(
                    inner.merge_platform_cookies(cookies.into_iter().map(Into::into).collect()),
                )
            },
        )
    }

    pub fn apply_platform_cookies(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "apply_platform_cookies",
            move |inner| {
                SessionState::from_snapshot(
                    inner.apply_platform_cookies(cookies.into_iter().map(Into::into).collect()),
                )
            },
        )
    }

    pub fn complete_cloudflare_challenge(
        &self,
        cookies: Vec<PlatformCookieState>,
        fresh_cf_clearance: String,
        browser_user_agent: Option<String>,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "complete_cloudflare_challenge",
            move |inner| {
                SessionState::from_snapshot(inner.complete_cloudflare_challenge(
                    cookies.into_iter().map(Into::into).collect(),
                    Some(fresh_cf_clearance),
                    browser_user_agent,
                ))
            },
        )
    }

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

    pub fn sync_login_context(
        &self,
        context: LoginSyncState,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "sync_login_context",
            move |inner| SessionState::from_snapshot(inner.sync_login_context(context.into())),
        )
    }

    pub fn classify_webview_login_result(
        &self,
        result: WebViewLoginJsResultState,
    ) -> Result<WebViewLoginDecisionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "classify_webview_login_result",
            move |inner| inner.classify_webview_login_result(result.into()).into(),
        )
    }

    pub fn webview_priming_payload(
        &self,
        target_url: Option<String>,
    ) -> Result<Vec<WebViewCookieActionState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "webview_priming_payload",
            move |inner| {
                inner
                    .webview_priming_payload(target_url)
                    .into_iter()
                    .map(Into::into)
                    .collect()
            },
        )
    }

    pub fn cookie_sweep_plan(
        &self,
        target_url: Option<String>,
        name: String,
        webview_cookies: Vec<WebViewCookieInfoState>,
    ) -> Result<CookieSweepPlanState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "cookie_sweep_plan",
            move |inner| {
                inner
                    .cookie_sweep_plan(
                        target_url,
                        name,
                        webview_cookies.into_iter().map(Into::into).collect(),
                    )
                    .into()
            },
        )
    }

    pub fn cookie_nuclear_reset_plan(
        &self,
        target_url: Option<String>,
        webview_cookies: Vec<WebViewCookieInfoState>,
    ) -> Result<NuclearResetPlanState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "cookie_nuclear_reset_plan",
            move |inner| {
                inner
                    .cookie_nuclear_reset_plan(
                        target_url,
                        webview_cookies.into_iter().map(Into::into).collect(),
                    )
                    .into()
            },
        )
    }

    pub fn commit_cookie_sweep_result(
        &self,
        target_url: Option<String>,
        name: String,
        intent: CookieSweepIntentState,
        webview_cookies: Vec<WebViewCookieInfoState>,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "commit_cookie_sweep_result",
            move |inner| {
                SessionState::from_snapshot(inner.commit_cookie_sweep_result(
                    target_url,
                    name,
                    intent.into(),
                    webview_cookies.into_iter().map(Into::into).collect(),
                ))
            },
        )
    }

    pub fn logout_local(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "logout_local",
            move |inner| SessionState::from_snapshot(inner.logout_local(preserve_cf_clearance)),
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

    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let snapshot = run_on_ffi_runtime("logout_remote", panic_state, async move {
            inner.logout_remote(preserve_cf_clearance).await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub fn finalize_login_from_webview(
        &self,
        username: String,
        csrf_token: Option<String>,
        raw_preloaded_html: Option<String>,
        browser_user_agent: Option<String>,
        cookies: Vec<PlatformCookieState>,
        allow_low_confidence_session_cookies: bool,
    ) -> Result<LoginFinalizationResultState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "finalize_login_from_webview",
            move |inner| {
                inner
                    .finalize_login_from_webview(
                        username,
                        csrf_token,
                        raw_preloaded_html,
                        browser_user_agent,
                        cookies.into_iter().map(Into::into).collect(),
                        allow_low_confidence_session_cookies,
                    )
                    .into()
            },
        )
    }

    pub fn cookie_replay_queue(&self) -> Result<Vec<CookieReplayEntryState>, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "cookie_replay_queue",
            |inner| {
                inner
                    .cookie_replay_list()
                    .map(|entries| entries.into_iter().map(Into::into).collect())
            },
        )
    }

    pub fn clear_cookie_replay_queue(&self) -> Result<(), FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "clear_cookie_replay_queue",
            |inner| inner.cookie_replay_clear(),
        )
    }

    pub async fn probe_session(&self) -> Result<String, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime("probe_session", panic_state, async move {
            inner.probe_session().await
        })
        .await?;
        Ok(format_probe_result(result))
    }

    pub fn record_fingerprint_done(&self) {}

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

    pub fn determine_login_state(&self) -> Result<LoginStateDeterminationState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "determine_login_state",
            |inner| inner.determine_login_state().into(),
        )
    }

    pub async fn determine_login_state_with_probe(
        &self,
    ) -> Result<LoginStateDeterminationState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime(
            "determine_login_state_with_probe",
            panic_state,
            async move {
                Ok::<_, fire_core::FireCoreError>(inner.determine_login_state_with_probe().await)
            },
        )
        .await?;
        Ok(result.into())
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
