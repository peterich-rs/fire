use std::sync::Arc;

use fire_uniffi_types::{run_fallible, run_infallible, FireUniFfiError};

use crate::records::*;
use crate::FireSessionHandle;

#[uniffi::export]
impl FireSessionHandle {
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
}
