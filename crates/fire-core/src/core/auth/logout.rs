use fire_models::{PassiveLogoutTrigger, SessionSnapshot};
use http::{Method, StatusCode};
use tracing::{info, warn};

use super::super::{
    network::{classify_http_status_error, expect_success, is_bad_csrf_body},
    FireCore,
};
use crate::{
    error::FireCoreError,
    sync_utils::{read_rwlock, write_rwlock},
};

impl FireCore {
    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionSnapshot, FireCoreError> {
        let username = self
            .snapshot()
            .bootstrap
            .current_username
            .ok_or(FireCoreError::MissingCurrentUsername)?;
        info!(username = %username, preserve_cf_clearance, "initiating remote logout");

        if !self.snapshot().cookies.has_csrf_token() {
            let _ = self.refresh_csrf_token_if_needed().await?;
        }

        let path = format!("/session/{username}");
        let traced = self.build_api_request("logout", Method::DELETE, &path, true)?;
        let (trace_id, response) = self.execute_request(traced).await?;

        if response.status() == StatusCode::FORBIDDEN {
            let response_headers = response.headers().clone();
            let body = self.read_response_text(trace_id, response).await?;
            self.diagnostics.record_http_status_error(
                trace_id,
                StatusCode::FORBIDDEN.as_u16(),
                &body,
            );
            if is_bad_csrf_body(&body) {
                warn!("logout received BAD CSRF, refreshing token and retrying once");
                let _ = self.clear_csrf_token();
                let _ = self.refresh_csrf_token_if_needed().await?;
                let retry = self.build_api_request("logout", Method::DELETE, &path, true)?;
                let (retry_trace_id, response) = self.execute_request(retry).await?;
                let response = expect_success(self, "logout", retry_trace_id, response).await?;
                let _ = self.read_response_text(retry_trace_id, response).await?;
                return Ok(self.logout_local(preserve_cf_clearance));
            }

            return Err(classify_http_status_error(
                "logout",
                StatusCode::FORBIDDEN.as_u16(),
                &response_headers,
                body,
            ));
        }

        let response = expect_success(self, "logout", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(self.logout_local(preserve_cf_clearance))
    }
}

impl FireCore {
    pub async fn passive_logout(&self, trigger: PassiveLogoutTrigger) -> Result<(), FireCoreError> {
        info!(
            source = %trigger.source,
            signal_strength = ?trigger.signal_strength,
            "initiating passive logout"
        );
        {
            let mut state = write_rwlock(&self.session, "session");
            state.auth_strike.record_passive_logout();
            state.epoch = state.epoch.saturating_add(1);
        }
        self.logout_local(true);
        Ok(())
    }

    pub fn is_logging_out(&self) -> bool {
        read_rwlock(&self.session, "session")
            .auth_strike
            .logging_out
    }

    pub fn handle_server_forced_logout(&self, user_id: u64) -> bool {
        {
            let mut state = write_rwlock(&self.session, "session");
            if state.auth_strike.logging_out {
                return false;
            }
            if state.snapshot.bootstrap.current_user_id != Some(user_id) {
                return false;
            }
            if !state.snapshot.cookies.can_authenticate_requests()
                && !state.snapshot.readiness().can_read_authenticated_api
            {
                return false;
            }
            info!(user_id, "handling server-forced logout");
            state.auth_strike.record_passive_logout();
            state.epoch = state.epoch.saturating_add(1);
        }
        let _ = self.logout_local(true);
        true
    }
}
