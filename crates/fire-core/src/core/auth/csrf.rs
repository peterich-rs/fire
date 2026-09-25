use fire_models::{CookieSnapshot, SessionSnapshot};
use http::Method;
use serde_json::Value;
use tracing::{debug, info};

use super::super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    json_helpers::{invalid_json, scalar_string},
};

impl FireCore {
    pub async fn refresh_csrf_token_if_needed(&self) -> Result<SessionSnapshot, FireCoreError> {
        let current = self.snapshot();
        if current.cookies.csrf_token.is_some() {
            return Ok(current);
        }
        if !current.cookies.can_authenticate_requests() {
            debug!("skipping CSRF refresh because authenticated cookies are unavailable");
            return Ok(current);
        }

        let _refresh_guard = self.csrf_refresh.lock().await;
        let current = self.snapshot();
        if current.cookies.csrf_token.is_some() {
            return Ok(current);
        }
        if !current.cookies.can_authenticate_requests() {
            debug!("skipping CSRF refresh because authenticated cookies became unavailable");
            return Ok(current);
        }

        self.refresh_csrf_token_without_dedupe().await
    }

    pub async fn refresh_csrf_token(&self) -> Result<SessionSnapshot, FireCoreError> {
        let _refresh_guard = self.csrf_refresh.lock().await;
        self.refresh_csrf_token_without_dedupe().await
    }

    async fn refresh_csrf_token_without_dedupe(&self) -> Result<SessionSnapshot, FireCoreError> {
        info!("refreshing CSRF token");
        let traced =
            self.build_api_request("refresh csrf token", Method::GET, "/session/csrf", false)?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "refresh csrf token", trace_id, response).await?;
        let payload: Value = self
            .read_response_json("refresh csrf token", trace_id, response)
            .await?;
        let csrf = parse_csrf_token_response(&payload).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "refresh csrf token",
                source,
            }
        })?;
        if csrf.is_empty() {
            self.diagnostics.record_parse_error(
                trace_id,
                "CSRF response did not contain a usable token".to_string(),
                "csrf token was empty".to_string(),
            );
            return Err(FireCoreError::InvalidCsrfResponse);
        }

        let result = self.update_session(|session| {
            session.cookies.merge_patch(&CookieSnapshot {
                csrf_token: Some(csrf.clone()),
                last_challenged_cf_clearance: None,
                ..CookieSnapshot::default()
            });
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "refreshed csrf token over network"
            );
        });
        self.clear_auth_recovery_hint("refresh csrf token");
        info!("CSRF token refreshed successfully");
        Ok(result)
    }
}

fn parse_csrf_token_response(value: &Value) -> Result<String, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("csrf response root was not an object"))?;
    Ok(scalar_string(object.get("csrf")).unwrap_or_default())
}
