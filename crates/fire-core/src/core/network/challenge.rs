use std::sync::{Arc, Mutex};

use http::header::HeaderMap;
use http::{Request, Response, StatusCode};
use openwire::{CallOptions, RequestBody, ResponseBody};

use super::super::FireCore;
use super::body::header_value;
use super::traced::{trace_request, FireSkipCloudflareBlock};
use super::{FireCallProfile, FireChallengePresentation, FireRequestEpoch};
use crate::error::{CloudflareChallengeFailureReason, FireCoreError};
use crate::sync_utils::write_rwlock;

pub(super) struct CloudflareChallengeFinishGuard {
    pub(super) runtime: Arc<Mutex<super::super::cf_challenge::FireCloudflareChallengeRuntime>>,
    pub(super) finished: bool,
}

impl CloudflareChallengeFinishGuard {
    pub(super) fn finish(&mut self, success: bool) {
        self.finish_with_publish(success, success);
    }

    pub(super) fn disarm(&mut self) {
        self.finished = true;
    }

    pub(super) fn finish_page_clear(&mut self) {
        if self.finished {
            return;
        }
        self.runtime
            .lock()
            .expect("cloudflare challenge runtime mutex poisoned")
            .enter_proving();
    }

    fn finish_with_publish(&mut self, success: bool, publish_resolved: bool) {
        if self.finished {
            return;
        }
        self.finished = true;
        self.runtime
            .lock()
            .expect("cloudflare challenge runtime mutex poisoned")
            .finish_with_publish(success, publish_resolved);
    }
}

impl Drop for CloudflareChallengeFinishGuard {
    fn drop(&mut self) {
        self.finish(false);
    }
}

pub(super) fn should_present_foreground_challenge(
    operation: &'static str,
    profile: FireCallProfile,
    request: &Request<RequestBody>,
) -> bool {
    if let Some(presentation) = request.extensions().get::<FireChallengePresentation>() {
        return *presentation == FireChallengePresentation::Foreground;
    }

    if profile == FireCallProfile::MessageBusPoll {
        return false;
    }

    !matches!(
        operation,
        "refresh bootstrap"
            | "fetch site metadata"
            | "refresh csrf token"
            | "fetch recent notifications"
            | "fetch notifications"
            | "report topic timings"
    ) && !operation.contains("message bus")
}

impl FireCore {
    pub(super) async fn await_shared_cloudflare_challenge_and_retry(
        &self,
        operation: &'static str,
        mut join_rx: tokio::sync::watch::Receiver<
            Option<super::super::cf_challenge::CloudflareChallengeJoinOutcome>,
        >,
        retry_request: Option<Request<RequestBody>>,
        options: CallOptions,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        loop {
            let current = *join_rx.borrow();
            if let Some(outcome) = current {
                return match outcome {
                    super::super::cf_challenge::CloudflareChallengeJoinOutcome::Succeeded => {
                        self.retry_after_cloudflare_challenge(operation, retry_request, options)
                            .await
                    }
                    super::super::cf_challenge::CloudflareChallengeJoinOutcome::Failed => {
                        Err(FireCoreError::CloudflareChallenge {
                            operation,
                            reason: CloudflareChallengeFailureReason::Failed,
                        })
                    }
                };
            }
            if join_rx.changed().await.is_err() {
                return Err(FireCoreError::CloudflareChallenge {
                    operation,
                    reason: CloudflareChallengeFailureReason::Failed,
                });
            }
        }
    }

    pub(super) fn capture_turnstile_sitekey_from_challenge_body(&self, body: &str) {
        let Some(sitekey) = extract_turnstile_sitekey(body) else {
            return;
        };
        let mut session = write_rwlock(&self.session, "session");
        let current = session
            .snapshot
            .bootstrap
            .turnstile_sitekey
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty());
        if current.is_some() {
            return;
        }
        session.snapshot.bootstrap.turnstile_sitekey = Some(sitekey);
    }

    pub(super) async fn retry_after_cloudflare_challenge(
        &self,
        operation: &'static str,
        retry_request: Option<Request<RequestBody>>,
        options: CallOptions,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        let Some(mut retry_request) = retry_request else {
            return Err(FireCoreError::CloudflareChallenge {
                operation,
                reason: CloudflareChallengeFailureReason::Failed,
            });
        };
        retry_request
            .extensions_mut()
            .insert(FireRequestEpoch(self.current_session_epoch()));
        retry_request
            .extensions_mut()
            .insert(FireSkipCloudflareBlock);
        let retry = trace_request(&self.diagnostics, operation, retry_request);
        self.network
            .execute_traced_with_options(retry, FireCallProfile::DefaultApi, options)
            .await
    }
}

pub(crate) fn is_cloudflare_challenge_body(body: &str) -> bool {
    let normalized = body.to_ascii_lowercase();
    normalized.contains("cf_chl_opt")
        || normalized.contains("cf-turnstile")
        || normalized.contains("challenge-running")
        || normalized.contains("challenge-stage")
        || (normalized.contains("challenge-platform") && normalized.contains("cloudflare"))
        || (normalized.contains("just a moment")
            && (normalized.contains("cloudflare") || normalized.contains("cf-challenge")))
}

pub(crate) fn extract_turnstile_sitekey(body: &str) -> Option<String> {
    const PATTERNS: &[&str] = &[
        "data-sitekey=\"",
        "data-sitekey='",
        "sitekey:\"",
        "sitekey:'",
        "\"sitekey\":\"",
        "'sitekey':'",
    ];

    for pattern in PATTERNS {
        if let Some(index) = body.find(pattern) {
            let rest = &body[index + pattern.len()..];
            let end = rest
                .find(['"', '\'', ' ', '<', '>', ',', '}', '\n', '\r'])
                .unwrap_or(rest.len());
            let candidate = rest[..end].trim();
            if candidate.len() >= 10 && candidate.is_ascii() {
                return Some(candidate.to_string());
            }
        }
    }
    None
}

pub(crate) fn is_cloudflare_challenge_response(
    status: u16,
    headers: &HeaderMap,
    body: &str,
) -> bool {
    if status != StatusCode::FORBIDDEN.as_u16() && status != StatusCode::TOO_MANY_REQUESTS.as_u16()
    {
        return false;
    }

    let cf_mitigated = header_value(headers, "cf-mitigated").unwrap_or_default();
    if cf_mitigated.to_ascii_lowercase().contains("challenge") {
        return true;
    }

    let content_type = header_value(headers, "content-type").unwrap_or_default();
    if !content_type.is_empty() && !content_type.to_ascii_lowercase().contains("text/html") {
        return false;
    }

    is_cloudflare_challenge_body(body)
}

#[cfg(test)]
mod tests {
    use http::header::{HeaderName, HeaderValue};

    use super::*;

    fn headers(pairs: &[(&str, &str)]) -> HeaderMap {
        let mut headers = HeaderMap::new();
        for (name, value) in pairs {
            headers.append(
                HeaderName::from_bytes(name.as_bytes()).expect("header name"),
                HeaderValue::from_str(value).expect("header value"),
            );
        }
        headers
    }

    #[test]
    fn cf_mitigated_alone_is_enough() {
        assert!(is_cloudflare_challenge_response(
            403,
            &headers(&[("cf-mitigated", "challenge")]),
            "blocked",
        ));
        assert!(is_cloudflare_challenge_response(
            429,
            &headers(&[
                ("cf-mitigated", "challenge"),
                ("content-type", "text/plain"),
            ]),
            "rate limited",
        ));
    }

    #[test]
    fn body_fallback_does_not_require_server_header() {
        assert!(is_cloudflare_challenge_response(
            403,
            &headers(&[("content-type", "text/html")]),
            "<html>cf_chl_opt Just a moment</html>",
        ));
    }

    #[test]
    fn json_403_without_mitigated_is_not_challenge() {
        assert!(!is_cloudflare_challenge_response(
            403,
            &headers(&[("content-type", "application/json")]),
            r#"{"errors":["invalid_access"]}"#,
        ));
    }
}
