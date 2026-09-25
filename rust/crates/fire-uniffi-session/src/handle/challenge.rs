use std::sync::Arc;

use fire_uniffi_types::{run_infallible, FireUniFfiError};

use crate::records::*;
use crate::FireSessionHandle;

#[uniffi::export]
impl FireSessionHandle {
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
    pub fn register_cloudflare_clearance_resolved_handler(
        &self,
        handler: Arc<dyn CloudflareClearanceResolvedHandler>,
    ) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "register_cloudflare_clearance_resolved_handler",
            move |inner| {
                let handler = handler.clone();
                inner.set_cloudflare_clearance_resolved_handler(move |event| {
                    handler.on_clearance_resolved(event.into());
                });
            },
        )
    }
    pub fn unregister_cloudflare_clearance_resolved_handler(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "unregister_cloudflare_clearance_resolved_handler",
            |inner| inner.clear_cloudflare_clearance_resolved_handler(),
        )
    }
    pub fn cloudflare_clearance_resolved_generation(&self) -> Result<u64, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "cloudflare_clearance_resolved_generation",
            |inner| inner.cloudflare_clearance_resolved_generation(),
        )
    }
    pub fn complete_cloudflare_challenge(
        &self,
        cookies: Vec<PlatformCookieState>,
        fresh_cf_clearance: Option<String>,
        browser_user_agent: Option<String>,
    ) -> Result<SessionState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "complete_cloudflare_challenge",
            move |inner| {
                SessionState::from_snapshot(
                    inner.complete_cloudflare_challenge(
                        cookies.into_iter().map(Into::into).collect(),
                        fresh_cf_clearance
                            .map(|value| value.trim().to_string())
                            .filter(|value| !value.is_empty()),
                        browser_user_agent,
                    ),
                )
            },
        )
    }
    /// True when jar has cf_clearance and CF has not recently rejected it.
    pub fn cloudflare_clearance_is_trusted(&self) -> Result<bool, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "cloudflare_clearance_is_trusted",
            |inner| inner.cloudflare_clearance_is_trusted(),
        )
    }
    pub fn note_cloudflare_clearance_rejected(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "note_cloudflare_clearance_rejected",
            |inner| {
                inner.note_cloudflare_clearance_rejected();
            },
        )
    }
}
