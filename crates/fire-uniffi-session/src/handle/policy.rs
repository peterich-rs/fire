use std::sync::Arc;

use fire_uniffi_types::{run_infallible, FireUniFfiError};

use crate::records::*;
use crate::FireSessionHandle;

#[uniffi::export]
impl FireSessionHandle {
    pub fn get_cloudflare_policy(&self) -> Result<CloudflarePolicyState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "get_cloudflare_policy",
            |inner| inner.cloudflare_policy().into(),
        )
    }

    pub fn set_cloudflare_policy(
        &self,
        policy: CloudflarePolicyState,
    ) -> Result<CloudflarePolicyState, FireUniFfiError> {
        fire_uniffi_types::run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "set_cloudflare_policy",
            move |inner| inner.set_cloudflare_policy(policy.into()).map(Into::into),
        )
    }

    pub fn enable_browser_transport_for_session(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "enable_browser_transport_for_session",
            |inner| inner.enable_browser_transport_for_session(),
        )
    }

    pub fn note_app_backgrounded(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "note_app_backgrounded",
            |inner| inner.note_app_backgrounded(),
        )
    }

    pub fn note_app_foregrounded(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "note_app_foregrounded",
            |inner| inner.note_app_foregrounded(),
        )
    }

    pub fn decline_browser_transport(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "decline_browser_transport",
            |inner| inner.decline_browser_transport(),
        )
    }

    pub fn register_browser_http_handler(
        &self,
        handler: Arc<dyn BrowserHttpHandler>,
    ) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "register_browser_http_handler",
            move |inner| {
                let handler = handler.clone();
                inner.set_browser_http_handler(move |request| {
                    handler
                        .execute_browser_http(request.into())
                        .map(Into::into)
                        .map_err(|error| error.to_string())
                });
            },
        )
    }

    pub fn unregister_browser_http_handler(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "unregister_browser_http_handler",
            |inner| inner.clear_browser_http_handler(),
        )
    }
}
