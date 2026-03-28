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
        let request = self.build_home_request()?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let response = expect_success("refresh bootstrap", response).await?;
        let response_username = header_value(response.headers(), "x-discourse-username");
        let html = response
            .into_body()
            .text()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
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
        let request = self.build_api_request(Method::GET, "/session/csrf", false)?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        let response = expect_success("refresh csrf token", response).await?;
        let payload: CsrfResponse = response
            .into_body()
            .json()
            .await
            .map_err(|source| FireCoreError::Network { source })?;
        if payload.csrf.is_empty() {
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
        let request = self.build_api_request(Method::DELETE, &path, true)?;
        let response = self
            .client
            .execute(request)
            .await
            .map_err(|source| FireCoreError::Network { source })?;

        if response.status() == StatusCode::FORBIDDEN {
            let body = response
                .into_body()
                .text()
                .await
                .map_err(|source| FireCoreError::Network { source })?;
            if is_bad_csrf_body(&body) {
                warn!("logout received BAD CSRF, refreshing token and retrying once");
                let _ = self.clear_csrf_token();
                let _ = self.refresh_csrf_token().await?;
                let retry = self.build_api_request(Method::DELETE, &path, true)?;
                let response = self
                    .client
                    .execute(retry)
                    .await
                    .map_err(|source| FireCoreError::Network { source })?;
                let _ = expect_success("logout", response).await?;
                return Ok(self.logout_local(preserve_cf_clearance));
            }

            return Err(FireCoreError::HttpStatus {
                operation: "logout",
                status: StatusCode::FORBIDDEN.as_u16(),
                body,
            });
        }

        let _ = expect_success("logout", response).await?;
        Ok(self.logout_local(preserve_cf_clearance))
    }
}
