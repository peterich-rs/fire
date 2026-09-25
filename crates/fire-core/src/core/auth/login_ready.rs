use fire_models::SessionSnapshot;
use tracing::warn;

use super::super::FireCore;
use crate::error::FireCoreError;

impl FireCore {
    /// After cookie handoff during login: try bootstrap refresh with a hard
    /// timeout, but never leave the UI stuck if bootstrap is slow. Cookie auth
    /// alone is enough to enter the app (fluxdo LoginReady finally semantics).
    pub async fn finalize_login_ready(&self) -> Result<SessionSnapshot, FireCoreError> {
        const LOGIN_READY_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(8);

        self.clear_cloudflare_clearance_rejected();

        if !self.snapshot().cookies.has_login_session() {
            return Ok(self.snapshot());
        }

        match tokio::time::timeout(LOGIN_READY_TIMEOUT, self.refresh_bootstrap_if_needed()).await {
            Ok(Ok(snapshot)) => Ok(snapshot),
            Ok(Err(error)) => {
                warn!(error = %error, "login-ready bootstrap refresh failed; continuing with cookies");
                Ok(self.snapshot())
            }
            Err(_) => {
                warn!("login-ready bootstrap refresh timed out; continuing with cookies");
                Ok(self.snapshot())
            }
        }
    }
}
