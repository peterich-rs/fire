//! Shared HTTP networking layer for FireCore.

mod auth_signals;
mod body;
mod challenge;
mod client;
mod constants;
mod csrf;
mod execute;
mod headers;
mod heal;
mod profile;
mod recovery;
mod request;
mod traced;

#[cfg(test)]
mod tests;

use std::sync::{Arc, Mutex, RwLock};

use openwire::Client;

use crate::diagnostics::FireDiagnosticsStore;

pub(crate) use body::{classify_http_status_error, expect_success, header_value, is_bad_csrf_body};
#[allow(unused_imports)] // crate API surface
pub(crate) use challenge::{
    extract_turnstile_sitekey, is_cloudflare_challenge_body, is_cloudflare_challenge_response,
};
pub(crate) use client::apply_platform_tls;
#[allow(unused_imports)]
pub(crate) use headers::{request_origin, request_referer};
pub(crate) use profile::take_trace_cancellation_guard;
#[allow(unused_imports)]
pub(crate) use traced::{
    FireSkipCloudflareBlock, FireSkipCookieSelfHeal, FireSkipCsrfHeader, TracedRequest,
};

#[derive(Clone, Copy)]
pub(crate) enum FireRequestProfile {
    HomeHtml,
    JsonApi,
    MessageBusPoll,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) enum FireCallProfile {
    #[default]
    DefaultApi,
    MessageBusPoll,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum FireChallengePresentation {
    Foreground,
    Background,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FireRequestEpoch(pub(crate) u64);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FireResponseEpochContext {
    pub(crate) request_epoch: u64,
    pub(crate) operation: &'static str,
}

#[derive(Clone)]
pub(crate) struct FireNetworkLayer {
    client: Client,
    diagnostics: Arc<FireDiagnosticsStore>,
    session: Arc<RwLock<super::FireSessionRuntimeState>>,
    cloudflare_challenge_runtime: Arc<Mutex<super::cf_challenge::FireCloudflareChallengeRuntime>>,
}
