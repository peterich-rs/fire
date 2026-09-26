use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
};
use http::header::HeaderMap;
use http::StatusCode;
use serde::Deserialize;
use tracing::warn;

use super::super::FireCore;
use super::body::{header_value, is_bad_csrf_body};
use super::challenge::is_cloudflare_challenge_response;
use super::constants::LOGIN_INVALIDATED_MESSAGE;
use crate::error::FireCoreError;

#[derive(Debug, Deserialize)]
struct DiscourseErrorEnvelope {
    #[serde(default)]
    errors: Option<DiscourseErrorMessages>,
    #[serde(default)]
    error_type: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum DiscourseErrorMessages {
    One(String),
    Many(Vec<String>),
}

impl DiscourseErrorEnvelope {
    fn first_error_message(&self) -> Option<&str> {
        match &self.errors {
            Some(DiscourseErrorMessages::One(message)) => Some(message.as_str()),
            Some(DiscourseErrorMessages::Many(messages)) => messages
                .iter()
                .map(String::as_str)
                .find(|message| !message.trim().is_empty()),
            None => None,
        }
    }
}

impl FireCore {
    pub(super) async fn classify_and_process_auth_strike(
        &self,
        status: StatusCode,
        invalidation: &LoginInvalidationSignal,
        body: &str,
        operation: &'static str,
    ) -> Option<FireCoreError> {
        let signal = if is_invalid_access_forbidden(status, body) {
            return None;
        } else if not_logged_in_message(status.as_u16(), body).is_some() {
            Some(AuthRuntimeSignal {
                kind: AuthRuntimeSignalKind::NotLoggedInBody,
                strength: AuthRuntimeSignalStrength::Strong,
                source: AuthRuntimeSignalSource::HttpResponse,
                operation: Some(operation.to_string()),
                status: Some(status.as_u16()),
            })
        } else if status.is_client_error() && invalidation.discourse_logged_out {
            Some(AuthRuntimeSignal {
                kind: AuthRuntimeSignalKind::DiscourseLoggedOutHeader,
                strength: AuthRuntimeSignalStrength::Strong,
                source: AuthRuntimeSignalSource::HttpResponse,
                operation: Some(operation.to_string()),
                status: Some(status.as_u16()),
            })
        } else {
            None
        }?;
        self.process_auth_runtime_signal(signal, operation).await
    }
}

fn discourse_error_envelope(body: &str) -> Option<DiscourseErrorEnvelope> {
    serde_json::from_str(body).ok()
}

pub(crate) fn not_logged_in_message(status: u16, body: &str) -> Option<String> {
    if status != StatusCode::UNAUTHORIZED.as_u16() && status != StatusCode::FORBIDDEN.as_u16() {
        return None;
    }

    let envelope = discourse_error_envelope(body)?;
    if envelope.error_type.as_deref() != Some("not_logged_in") {
        return None;
    }

    Some(
        envelope
            .first_error_message()
            .unwrap_or("需要登录才能执行此操作。")
            .to_string(),
    )
}

pub(super) fn is_invalid_access_forbidden(status: StatusCode, body: &str) -> bool {
    status == StatusCode::FORBIDDEN
        && discourse_error_envelope(body)
            .and_then(|envelope| envelope.error_type)
            .as_deref()
            == Some("invalid_access")
}

pub(super) fn success_auth_runtime_signal(
    status: StatusCode,
    invalidation: &LoginInvalidationSignal,
    operation: &'static str,
) -> Option<AuthRuntimeSignal> {
    if !status.is_success() {
        return None;
    }

    if invalidation.discourse_logged_out {
        return Some(AuthRuntimeSignal {
            kind: if invalidation.has_auth_cookie_deletion() {
                AuthRuntimeSignalKind::MixedSignalCookieDeletionBlocked
            } else {
                AuthRuntimeSignalKind::MixedLoggedOutHeader
            },
            strength: AuthRuntimeSignalStrength::Weak,
            source: AuthRuntimeSignalSource::HttpResponse,
            operation: Some(operation.to_string()),
            status: Some(status.as_u16()),
        });
    }

    if invalidation.has_auth_cookie_deletion() {
        return Some(AuthRuntimeSignal {
            kind: AuthRuntimeSignalKind::AuthCookieDeletion,
            strength: AuthRuntimeSignalStrength::Diagnostic,
            source: AuthRuntimeSignalSource::SetCookieIngress,
            operation: Some(operation.to_string()),
            status: Some(status.as_u16()),
        });
    }

    None
}

pub(super) fn response_auth_runtime_signal(
    status: StatusCode,
    headers: &HeaderMap,
    invalidation: &LoginInvalidationSignal,
    body: &str,
    operation: &'static str,
) -> Option<AuthRuntimeSignal> {
    let signal = if is_cloudflare_challenge_response(status.as_u16(), headers, body) {
        Some((
            AuthRuntimeSignalKind::CloudflareChallenge,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else if is_bad_csrf_body(body) {
        Some((
            AuthRuntimeSignalKind::BadCsrf,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else if is_invalid_access_forbidden(status, body) {
        Some((
            AuthRuntimeSignalKind::InvalidAccessForbidden,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else if not_logged_in_message(status.as_u16(), body).is_some() {
        Some((
            AuthRuntimeSignalKind::NotLoggedInBody,
            AuthRuntimeSignalStrength::Strong,
        ))
    } else if status.is_client_error() && invalidation.discourse_logged_out {
        Some((
            AuthRuntimeSignalKind::DiscourseLoggedOutHeader,
            AuthRuntimeSignalStrength::Strong,
        ))
    } else if invalidation.has_auth_cookie_deletion() {
        Some((
            AuthRuntimeSignalKind::AuthCookieDeletion,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else if status == StatusCode::TOO_MANY_REQUESTS {
        Some((
            AuthRuntimeSignalKind::RateLimit,
            AuthRuntimeSignalStrength::Diagnostic,
        ))
    } else {
        None
    }?;

    Some(AuthRuntimeSignal {
        kind: signal.0,
        strength: signal.1,
        source: AuthRuntimeSignalSource::HttpResponse,
        operation: Some(operation.to_string()),
        status: Some(status.as_u16()),
    })
}

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct LoginInvalidationSignal {
    pub(super) discourse_logged_out: bool,
    pub(super) cleared_t_cookie: bool,
    pub(super) cleared_forum_session: bool,
}

impl LoginInvalidationSignal {
    fn any(self) -> bool {
        // Deleted auth cookies are useful diagnostics, but only explicit server
        // invalidation signals should force local logout.
        self.discourse_logged_out
    }

    fn has_auth_cookie_deletion(self) -> bool {
        self.cleared_t_cookie || self.cleared_forum_session
    }
}

pub(super) fn response_login_invalidation_signal(headers: &HeaderMap) -> LoginInvalidationSignal {
    let discourse_logged_out = header_value(headers, "discourse-logged-out").is_some();
    let mut cleared_t_cookie = false;
    let mut cleared_forum_session = false;

    for value in headers.get_all("set-cookie") {
        let Ok(value) = value.to_str() else {
            continue;
        };
        cleared_t_cookie |= clears_cookie(value, "_t");
        cleared_forum_session |= clears_cookie(value, "_forum_session");
    }

    LoginInvalidationSignal {
        discourse_logged_out,
        cleared_t_cookie,
        cleared_forum_session,
    }
}

pub(super) fn clears_cookie(set_cookie_header: &str, name: &str) -> bool {
    let lower = set_cookie_header.trim().to_ascii_lowercase();
    let prefix = format!("{}=", name.to_ascii_lowercase());
    if !lower.starts_with(&prefix) {
        return false;
    }

    let Some((_, rest)) = lower.split_once('=') else {
        return false;
    };
    let value = rest.split(';').next().map(str::trim).unwrap_or_default();
    if !value.is_empty() && value != "del" {
        return false;
    }

    lower.contains("max-age=0") || lower.contains("expires=thu, 01 jan 1970 00:00:00 gmt")
}

pub(super) fn response_login_invalidation_error(
    operation: &'static str,
    trace_id: u64,
    status: StatusCode,
    invalidation: LoginInvalidationSignal,
    body: &str,
) -> Option<FireCoreError> {
    if is_invalid_access_forbidden(status, body) {
        return None;
    }
    let login_required_message = not_logged_in_message(status.as_u16(), body);
    let header_invalidates_login = invalidation.any() && status.is_client_error();
    if !header_invalidates_login && login_required_message.is_none() {
        return None;
    }

    warn!(
        operation,
        trace_id,
        status = status.as_u16(),
        discourse_logged_out = invalidation.discourse_logged_out,
        cleared_t_cookie = invalidation.cleared_t_cookie,
        cleared_forum_session = invalidation.cleared_forum_session,
        header_invalidates_login,
        body_prefix = %body.chars().take(200).collect::<String>(),
        "response reported login-required state"
    );
    Some(FireCoreError::LoginRequired {
        operation,
        message: login_required_message.unwrap_or_else(|| LOGIN_INVALIDATED_MESSAGE.to_string()),
    })
}
