use fire_models::ProbeResult;
use serde_json::Value;

use super::super::FireCore;
use crate::error::FireCoreError;

impl FireCore {
    pub async fn probe_session(&self) -> Result<ProbeResult, FireCoreError> {
        let traced =
            self.build_json_get_request("probe_session", "/session/current.json", Vec::new(), &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let status = response.status();
        if status.as_u16() == 404 {
            return Ok(ProbeResult::Invalid);
        }
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
                    Ok(ProbeResult::Invalid)
                } else {
                    Ok(ProbeResult::Inconclusive)
                }
            }
            Err(_) => Ok(ProbeResult::Inconclusive),
        }
    }
}
