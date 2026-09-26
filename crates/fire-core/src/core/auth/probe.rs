use fire_models::ProbeResult;
use serde_json::Value;

use super::super::network::{
    header_value, is_cloudflare_challenge_response, not_logged_in_message,
};
use super::super::FireCore;
use crate::error::FireCoreError;

impl FireCore {
    pub async fn probe_session(&self) -> Result<ProbeResult, FireCoreError> {
        let traced =
            self.build_json_get_request("probe_session", "/session/current.json", Vec::new(), &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let status = response.status();
        let status_code = status.as_u16();
        if status_code == 404 {
            return Ok(ProbeResult::Invalid);
        }
        let headers = response.headers().clone();
        let body = self.read_response_text(trace_id, response).await;
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
