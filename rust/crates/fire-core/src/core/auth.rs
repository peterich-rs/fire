use fire_models::{BootstrapArtifacts, CookieSnapshot, SessionSnapshot};
use http::{Method, StatusCode};
use serde::Deserialize;
use tracing::{debug, warn};

use super::{
    network::{expect_success, header_value, is_bad_csrf_body},
    FireCore,
};
use crate::error::FireCoreError;
use crate::parsing::parse_home_state;

#[derive(Debug, Deserialize)]
struct CsrfResponse {
    csrf: String,
}

impl FireCore {
    pub async fn refresh_bootstrap(&self) -> Result<SessionSnapshot, FireCoreError> {
        let traced = self.build_home_request("refresh bootstrap")?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "refresh bootstrap", trace_id, response).await?;
        let response_username = header_value(response.headers(), "x-discourse-username");
        let html = self.read_response_text(trace_id, response).await?;
        let parsed = parse_home_state(self.base_url(), &html);

        Ok(self.update_session(|session| {
            session.cookies.merge_patch(&parsed.cookies_patch);
            session.bootstrap.merge_patch(&parsed.bootstrap_patch);
            if let Some(response_username) = response_username.clone() {
                session.bootstrap.merge_patch(&BootstrapArtifacts {
                    current_username: Some(response_username),
                    ..BootstrapArtifacts::default()
                });
            }
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "refreshed bootstrap over network"
            );
        }))
    }

    pub async fn refresh_csrf_token(&self) -> Result<SessionSnapshot, FireCoreError> {
        let traced =
            self.build_api_request("refresh csrf token", Method::GET, "/session/csrf", false)?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "refresh csrf token", trace_id, response).await?;
        let payload: CsrfResponse = self
            .read_response_json("refresh csrf token", trace_id, response)
            .await?;
        if payload.csrf.is_empty() {
            self.diagnostics.record_parse_error(
                trace_id,
                "CSRF response did not contain a usable token".to_string(),
                "csrf token was empty".to_string(),
            );
            return Err(FireCoreError::InvalidCsrfResponse);
        }

        Ok(self.update_session(|session| {
            session.cookies.merge_patch(&CookieSnapshot {
                csrf_token: Some(payload.csrf.clone()),
                ..CookieSnapshot::default()
            });
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "refreshed csrf token over network"
            );
        }))
    }

    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionSnapshot, FireCoreError> {
        let username = self
            .snapshot()
            .bootstrap
            .current_username
            .ok_or(FireCoreError::MissingCurrentUsername)?;

        if !self.snapshot().cookies.has_csrf_token() {
            let _ = self.refresh_csrf_token().await?;
        }

        let path = format!("/session/{username}");
        let traced = self.build_api_request("logout", Method::DELETE, &path, true)?;
        let (trace_id, response) = self.execute_request(traced).await?;

        if response.status() == StatusCode::FORBIDDEN {
            let body = self.read_response_text(trace_id, response).await?;
            self.diagnostics.record_http_status_error(
                trace_id,
                StatusCode::FORBIDDEN.as_u16(),
                &body,
            );
            if is_bad_csrf_body(&body) {
                warn!("logout received BAD CSRF, refreshing token and retrying once");
                let _ = self.clear_csrf_token();
                let _ = self.refresh_csrf_token().await?;
                let retry = self.build_api_request("logout", Method::DELETE, &path, true)?;
                let (retry_trace_id, response) = self.execute_request(retry).await?;
                let response = expect_success(self, "logout", retry_trace_id, response).await?;
                let _ = self.read_response_text(retry_trace_id, response).await?;
                return Ok(self.logout_local(preserve_cf_clearance));
            }

            return Err(FireCoreError::HttpStatus {
                operation: "logout",
                status: StatusCode::FORBIDDEN.as_u16(),
                body,
            });
        }

        let response = expect_success(self, "logout", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(self.logout_local(preserve_cf_clearance))
    }
}
