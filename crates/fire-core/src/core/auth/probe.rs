use std::sync::{Arc, Mutex};

use fire_models::{CookieSource, CookieTrust, PlatformCookie, ProbeResult};
use serde_json::Value;

use super::super::network::{
    header_value, is_cloudflare_challenge_response, not_logged_in_message,
};
use super::super::{take_previous_t_token, FireCore};
use crate::cookies::FIRE_T_TOKEN_OVERRIDE;
use crate::error::FireCoreError;
use crate::sync_utils::{read_rwlock, write_rwlock};

const REJECTED_CANDIDATE_TTL: std::time::Duration = std::time::Duration::from_secs(5 * 60);

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SessionCandidateCookies {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
}

pub(crate) type FireSessionCandidateHandlerFn =
    Arc<dyn Fn() -> SessionCandidateCookies + Send + Sync>;

#[derive(Clone, Default)]
pub(crate) struct FireSessionCandidateHandlerRegistry {
    inner: Arc<Mutex<Option<FireSessionCandidateHandlerFn>>>,
}

impl FireSessionCandidateHandlerRegistry {
    pub(crate) fn set(&self, handler: FireSessionCandidateHandlerFn) {
        *self
            .inner
            .lock()
            .expect("session candidate handler mutex poisoned") = Some(handler);
    }

    pub(crate) fn clear(&self) {
        *self
            .inner
            .lock()
            .expect("session candidate handler mutex poisoned") = None;
    }

    pub(crate) fn get(&self) -> Option<FireSessionCandidateHandlerFn> {
        self.inner
            .lock()
            .expect("session candidate handler mutex poisoned")
            .clone()
    }
}

impl FireCore {
    pub fn set_session_candidate_handler<F>(&self, handler: F)
    where
        F: Fn() -> SessionCandidateCookies + Send + Sync + 'static,
    {
        self.session_candidate_handler
            .set(Arc::new(handler) as FireSessionCandidateHandlerFn);
    }

    pub fn clear_session_candidate_handler(&self) {
        self.session_candidate_handler.clear();
    }

    pub async fn probe_session(&self) -> Result<ProbeResult, FireCoreError> {
        if let Some(recovered) = self.recover_webview_session_candidate().await? {
            return Ok(recovered);
        }

        let official = self.probe_session_with_override(None).await?;
        if !matches!(official, ProbeResult::Invalid) {
            if matches!(official, ProbeResult::Valid { .. }) {
                self.clear_previous_t_token();
            }
            return Ok(official);
        }

        if let Some(recovered) = self.recover_previous_t_token().await? {
            return Ok(recovered);
        }

        if let Some(recovered) = Box::pin(self.recover_via_user_api_key()).await? {
            return Ok(recovered);
        }

        Ok(official)
    }

    async fn recover_webview_session_candidate(&self) -> Result<Option<ProbeResult>, FireCoreError> {
        let Some(handler) = self.session_candidate_handler.get() else {
            return Ok(None);
        };
        let candidate = handler();
        let Some(candidate_t) = candidate
            .t_token
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
        else {
            return Ok(None);
        };
        let jar_t = read_rwlock(&self.session, "session")
            .snapshot
            .cookies
            .t_token
            .clone();
        if jar_t.as_deref() == Some(candidate_t.as_str()) {
            return Ok(None);
        }
        if self.is_rejected_session_candidate(&candidate_t) {
            return Ok(None);
        }

        match self
            .probe_session_with_override(Some(candidate_t.clone()))
            .await?
        {
            ProbeResult::Valid { username } => {
                self.apply_recovered_session_cookies(&candidate_t, candidate.forum_session.as_deref());
                self.clear_rejected_session_candidate();
                self.clear_previous_t_token();
                Ok(Some(ProbeResult::Valid { username }))
            }
            ProbeResult::Invalid => {
                self.mark_rejected_session_candidate(&candidate_t);
                Ok(None)
            }
            other => Ok(Some(other)),
        }
    }

    async fn recover_previous_t_token(&self) -> Result<Option<ProbeResult>, FireCoreError> {
        let Some(previous) = ({
            let state = read_rwlock(&self.session, "session");
            take_previous_t_token(&state)
        }) else {
            return Ok(None);
        };
        if self.is_rejected_session_candidate(&previous) {
            return Ok(None);
        }
        match self
            .probe_session_with_override(Some(previous.clone()))
            .await?
        {
            ProbeResult::Valid { username } => {
                self.apply_recovered_session_cookies(&previous, None);
                self.clear_rejected_session_candidate();
                self.clear_previous_t_token();
                Ok(Some(ProbeResult::Valid { username }))
            }
            ProbeResult::Invalid => {
                self.mark_rejected_session_candidate(&previous);
                Ok(None)
            }
            other => Ok(Some(other)),
        }
    }

    pub(crate) async fn probe_session_with_override(
        &self,
        t_token: Option<String>,
    ) -> Result<ProbeResult, FireCoreError> {
        let run = async {
            let traced = self.build_json_get_request(
                "probe_session",
                "/session/current.json",
                Vec::new(),
                &[],
            )?;
            let (trace_id, response) = self.execute_request(traced).await?;
            classify_probe_response(self, trace_id, response).await
        };
        match t_token {
            Some(token) => FIRE_T_TOKEN_OVERRIDE.scope(Some(token), run).await,
            None => run.await,
        }
    }

    fn apply_recovered_session_cookies(&self, t_token: &str, forum_session: Option<&str>) {
        let origin = url::Url::parse(self.base_url()).ok();
        let mut cookies = vec![PlatformCookie {
            name: "_t".to_string(),
            value: t_token.to_string(),
            domain: None,
            path: Some("/".to_string()),
            expires_at_unix_ms: None,
            same_site: None,
        }];
        if let Some(forum_session) = forum_session
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            cookies.push(PlatformCookie {
                name: "_forum_session".to_string(),
                value: forum_session.to_string(),
                domain: None,
                path: Some("/".to_string()),
                expires_at_unix_ms: None,
                same_site: None,
            });
        }
        self.update_session(|session| {
            session.cookies.t_token = Some(t_token.to_string());
            if let Some(forum_session) = forum_session
                .map(str::trim)
                .filter(|value| !value.is_empty())
            {
                session.cookies.forum_session = Some(forum_session.to_string());
            }
            if let Some(origin) = origin.as_ref() {
                session.cookies.merge_platform_cookies_for_origin(
                    &cookies,
                    origin,
                    CookieSource::WebViewLogin,
                    CookieTrust::Trusted,
                );
            }
        });
    }

    fn clear_previous_t_token(&self) {
        let mut state = write_rwlock(&self.session, "session");
        state.previous_t_token = None;
        state.previous_t_token_at = None;
    }

    fn is_rejected_session_candidate(&self, token: &str) -> bool {
        let state = read_rwlock(&self.session, "session");
        let Some(rejected) = state.rejected_session_candidate.as_deref() else {
            return false;
        };
        if rejected != token {
            return false;
        }
        state
            .rejected_session_candidate_at
            .is_some_and(|at| at.elapsed() <= REJECTED_CANDIDATE_TTL)
    }

    fn mark_rejected_session_candidate(&self, token: &str) {
        let mut state = write_rwlock(&self.session, "session");
        state.rejected_session_candidate = Some(token.to_string());
        state.rejected_session_candidate_at = Some(std::time::Instant::now());
    }

    fn clear_rejected_session_candidate(&self) {
        let mut state = write_rwlock(&self.session, "session");
        state.rejected_session_candidate = None;
        state.rejected_session_candidate_at = None;
    }
}

async fn classify_probe_response(
    core: &FireCore,
    trace_id: u64,
    response: http::Response<openwire::ResponseBody>,
) -> Result<ProbeResult, FireCoreError> {
    let status = response.status();
    let status_code = status.as_u16();
    if status_code == 404 {
        return Ok(ProbeResult::Invalid);
    }
    let headers = response.headers().clone();
    let body = core.read_response_text(trace_id, response).await;
    match body {
        Ok(text) => {
            let json: Value = serde_json::from_str(&text).unwrap_or_default();
            if let Some(user) = json.get("current_user") {
                let username = user
                    .get("username")
                    .and_then(|u| u.as_str())
                    .unwrap_or("")
                    .to_string();
                if !username.is_empty() {
                    return Ok(ProbeResult::Valid { username });
                }
            }
            if status.is_success() {
                return Ok(ProbeResult::Invalid);
            }
            if status_code == 401
                || (status_code == 403
                    && (not_logged_in_message(status_code, &text).is_some()
                        || header_value(&headers, "discourse-logged-out").is_some()))
            {
                return Ok(ProbeResult::Invalid);
            }
            if status_code == 403
                && is_cloudflare_challenge_response(status_code, &headers, &text)
            {
                return Ok(ProbeResult::Inconclusive);
            }
            Ok(ProbeResult::Inconclusive)
        }
        Err(_) => {
            if status_code == 401 {
                Ok(ProbeResult::Invalid)
            } else {
                Ok(ProbeResult::Inconclusive)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_table_matches_alignment_plan() {
        assert!(matches!(
            classify_probe_fixture(404, "", ""),
            ProbeResult::Invalid
        ));
        assert!(matches!(
            classify_probe_fixture(200, r#"{"current_user":{"username":"alice"}}"#, ""),
            ProbeResult::Valid { .. }
        ));
        assert!(matches!(
            classify_probe_fixture(200, "{}", ""),
            ProbeResult::Invalid
        ));
        assert!(matches!(
            classify_probe_fixture(
                401,
                r#"{"errors":["需要登录"],"error_type":"not_logged_in"}"#,
                ""
            ),
            ProbeResult::Invalid
        ));
        assert!(matches!(
            classify_probe_fixture(
                403,
                r#"{"errors":["需要登录"],"error_type":"not_logged_in"}"#,
                ""
            ),
            ProbeResult::Invalid
        ));
        assert!(matches!(
            classify_probe_fixture(
                403,
                "<!DOCTYPE html><title>Just a moment</title>",
                "cf-mitigated"
            ),
            ProbeResult::Inconclusive
        ));
        assert!(matches!(
            classify_probe_fixture(503, "unavailable", ""),
            ProbeResult::Inconclusive
        ));
    }

    fn classify_probe_fixture(status: u16, body: &str, challenge_header: &str) -> ProbeResult {
        if status == 404 {
            return ProbeResult::Invalid;
        }
        let json: Value = serde_json::from_str(body).unwrap_or_default();
        if let Some(user) = json.get("current_user") {
            let username = user
                .get("username")
                .and_then(|u| u.as_str())
                .unwrap_or("")
                .to_string();
            if !username.is_empty() {
                return ProbeResult::Valid { username };
            }
        }
        if (200..300).contains(&status) {
            return ProbeResult::Invalid;
        }
        if status == 401
            || (status == 403
                && (not_logged_in_message(status, body).is_some()
                    || body.contains("discourse-logged-out")))
        {
            return ProbeResult::Invalid;
        }
        if status == 403 && !challenge_header.is_empty() {
            return ProbeResult::Inconclusive;
        }
        ProbeResult::Inconclusive
    }
}
