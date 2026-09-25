use super::challenge::{CloudflareChallengeRequestState, CloudflareChallengeResultState};
use super::refresh::{AppStateRefreshEventState, CloudflareClearanceResolvedEventState};

#[uniffi::export(with_foreign)]
pub trait AppStateRefreshHandler: Send + Sync {
    fn on_app_state_refresh_event(&self, event: AppStateRefreshEventState);
}

#[uniffi::export(with_foreign)]
pub trait CloudflareChallengeHandler: Send + Sync {
    fn complete_cloudflare_challenge(
        &self,
        request: CloudflareChallengeRequestState,
    ) -> CloudflareChallengeResultState;
}

#[uniffi::export(with_foreign)]
pub trait CloudflareClearanceResolvedHandler: Send + Sync {
    fn on_clearance_resolved(&self, event: CloudflareClearanceResolvedEventState);
}
