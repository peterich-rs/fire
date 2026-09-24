use fire_models::{
    LoginFailure, LoginFailureKind, SecondFactorRequirement, WebViewLoginDecision,
    WebViewLoginJsResult, WebViewLoginPhase,
};
use serde_json::Value;

use super::super::FireCore;

pub(crate) fn classify_webview_login_result(result: WebViewLoginJsResult) -> WebViewLoginDecision {
    match result.phase {
        WebViewLoginPhase::Csrf => classify_csrf_phase(result.status, &result.body),
        WebViewLoginPhase::Hcaptcha => WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Network,
            message: Some(
                non_empty_string(result.body)
                    .unwrap_or_else(|| format!("hCaptcha create failed: HTTP {}", result.status)),
            ),
            sent_to_email: None,
            current_email: None,
        }),
        WebViewLoginPhase::Exception => WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Network,
            message: Some(
                non_empty_string(result.body)
                    .unwrap_or_else(|| "WebView login exception".to_string()),
            ),
            sent_to_email: None,
            current_email: None,
        }),
        WebViewLoginPhase::Session => classify_session_phase(result.status, &result.body),
    }
}

fn classify_csrf_phase(status: u16, body: &str) -> WebViewLoginDecision {
    if matches!(status, 403 | 429) && looks_like_cloudflare_challenge(body) {
        return WebViewLoginDecision::RetryCloudflare;
    }
    WebViewLoginDecision::Failure(LoginFailure {
        kind: LoginFailureKind::Network,
        message: Some(
            non_empty_string(body).unwrap_or_else(|| format!("CSRF request failed: HTTP {status}")),
        ),
        sent_to_email: None,
        current_email: None,
    })
}

fn classify_session_phase(status: u16, body: &str) -> WebViewLoginDecision {
    let Ok(value) = serde_json::from_str::<Value>(body) else {
        return WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Unknown,
            message: Some(format!("Discourse returned non-JSON: HTTP {status}")),
            sent_to_email: None,
            current_email: None,
        });
    };
    let Some(object) = value.as_object() else {
        return WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Unknown,
            message: Some(format!("Discourse returned non-object JSON: HTTP {status}")),
            sent_to_email: None,
            current_email: None,
        });
    };

    if let Some(reason) = object.get("reason").and_then(Value::as_str) {
        return classify_login_reason(reason, object);
    }

    if object.get("error").is_some() && object.get("user").is_none() {
        return WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Unknown,
            message: optional_string_field(object, "error"),
            sent_to_email: None,
            current_email: None,
        });
    }

    WebViewLoginDecision::Success
}

fn classify_login_reason(
    reason: &str,
    object: &serde_json::Map<String, Value>,
) -> WebViewLoginDecision {
    match reason {
        "invalid_second_factor" | "second_factor" => {
            WebViewLoginDecision::NeedSecondFactor(SecondFactorRequirement {
                totp_enabled: bool_field(object, "totp_enabled"),
                security_key_enabled: bool_field(object, "security_key_enabled"),
                backup_enabled: bool_field(object, "backup_enabled"),
                message: optional_string_field(object, "error"),
            })
        }
        "invalid_credentials" => failure(LoginFailureKind::InvalidCredentials, object, None),
        "not_activated" => failure(
            LoginFailureKind::NotActivated,
            object,
            Some((
                optional_string_field(object, "sent_to_email"),
                optional_string_field(object, "current_email"),
            )),
        ),
        "not_approved" => failure(LoginFailureKind::NotApproved, object, None),
        "expired" => failure(LoginFailureKind::PasswordExpired, object, None),
        _ => WebViewLoginDecision::Failure(LoginFailure {
            kind: LoginFailureKind::Unknown,
            message: optional_string_field(object, "error")
                .or_else(|| Some(format!("reason={reason}"))),
            sent_to_email: None,
            current_email: None,
        }),
    }
}

fn failure(
    kind: LoginFailureKind,
    object: &serde_json::Map<String, Value>,
    email_fields: Option<(Option<String>, Option<String>)>,
) -> WebViewLoginDecision {
    let (sent_to_email, current_email) = email_fields.unwrap_or_default();
    WebViewLoginDecision::Failure(LoginFailure {
        kind,
        message: optional_string_field(object, "error"),
        sent_to_email,
        current_email,
    })
}

fn optional_string_field(object: &serde_json::Map<String, Value>, key: &str) -> Option<String> {
    object
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn bool_field(object: &serde_json::Map<String, Value>, key: &str) -> bool {
    object.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn non_empty_string(value: impl AsRef<str>) -> Option<String> {
    let trimmed = value.as_ref().trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn looks_like_cloudflare_challenge(body: &str) -> bool {
    let lower = body.to_ascii_lowercase();
    lower.contains("cf_chl_opt")
        || lower.contains("cf-turnstile")
        || lower.contains("challenge-running")
        || lower.contains("challenge-stage")
        || (lower.contains("challenge-platform") && lower.contains("cloudflare"))
        || (lower.contains("just a moment") && lower.contains("cloudflare"))
        || lower.contains("cf-mitigated")
}

impl FireCore {
    pub fn classify_webview_login_result(
        &self,
        result: WebViewLoginJsResult,
    ) -> WebViewLoginDecision {
        classify_webview_login_result(result)
    }
}
