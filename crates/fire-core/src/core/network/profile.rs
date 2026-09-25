use std::sync::Arc;

use http::Response;
use openwire::{Call, CallOptions, ResponseBody};

use super::super::{FireCore, MESSAGE_BUS_CALL_TIMEOUT};
use super::{FireCallProfile, FireResponseEpochContext};
use crate::diagnostics::{FireDiagnosticsStore, FireNetworkTraceCancellationGuard};
use crate::error::FireCoreError;

pub(crate) fn take_trace_cancellation_guard(
    response: &mut Response<ResponseBody>,
) -> Option<FireNetworkTraceCancellationGuard> {
    response
        .extensions_mut()
        .remove::<FireNetworkTraceCancellationGuard>()
}

pub(super) fn response_epoch_context(
    response: &Response<ResponseBody>,
) -> Option<FireResponseEpochContext> {
    response
        .extensions()
        .get::<FireResponseEpochContext>()
        .copied()
}

pub(super) fn stale_response_error(
    core: &FireCore,
    diagnostics: &Arc<FireDiagnosticsStore>,
    trace_id: u64,
    context: FireResponseEpochContext,
) -> Option<FireCoreError> {
    let current_epoch = core.current_session_epoch();
    if current_epoch == context.request_epoch {
        return None;
    }

    diagnostics.record_cancelled_if_in_progress(
        trace_id,
        "Session superseded",
        Some(&format!(
            "Discarded `{}` response after session epoch advanced from {} to {}",
            context.operation, context.request_epoch, current_epoch
        )),
    );
    Some(FireCoreError::StaleSessionResponse {
        operation: context.operation,
    })
}

pub(super) fn apply_call_profile(call: Call, profile: FireCallProfile) -> Call {
    call.options(call_options_for_profile(profile))
}

pub(super) fn call_options_for_profile(profile: FireCallProfile) -> CallOptions {
    match profile {
        FireCallProfile::DefaultApi => CallOptions::default(),
        FireCallProfile::MessageBusPoll => {
            CallOptions::default().call_timeout(MESSAGE_BUS_CALL_TIMEOUT)
        }
    }
}
