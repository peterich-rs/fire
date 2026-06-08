use fire_models::{
    LdcApprovalStatus, LdcAuthorizationUrl, LdcRewardRequest, LdcRewardResult, LdcUserInfo,
};
use http::{header::LOCATION, HeaderValue, Method};
use openwire::{CallOptions, RequestBody};
use serde_json::Value;
use tracing::info;

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    ldc_payloads::{
        extract_oauth_approve_path, parse_ldc_authorization_url_value,
        parse_ldc_reward_result_value, parse_ldc_user_info_value,
    },
};

const LDC_BASE_URL: &str = "https://credit.linux.do";
const CONNECT_BASE_URL: &str = "https://connect.linux.do";

impl FireCore {
    pub async fn ldc_authorization_url(&self) -> Result<LdcAuthorizationUrl, FireCoreError> {
        info!("fetching LDC authorization URL");
        let raw = self
            .get_json_value(
                "ldc authorization url",
                &format!("{LDC_BASE_URL}/api/v1/oauth/login"),
            )
            .await?;
        parse_ldc_authorization_url_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "ldc authorization url",
                source,
            }
        })
    }

    pub async fn ldc_approval_link(
        &self,
        authorization_url: &str,
    ) -> Result<String, FireCoreError> {
        info!("loading LDC authorization page");
        self.oauth_approval_link("ldc approval page", authorization_url)
            .await
    }

    pub async fn ldc_approve(
        &self,
        approve_path: &str,
    ) -> Result<LdcApprovalStatus, FireCoreError> {
        info!("approving LDC authorization");
        self.oauth_approve_redirect("ldc approve", approve_path)
            .await
    }

    pub async fn ldc_callback(&self, code: &str, state: &str) -> Result<(), FireCoreError> {
        info!("posting LDC OAuth callback");
        self.oauth_callback(
            "ldc callback",
            &format!("{LDC_BASE_URL}/api/v1/oauth/callback"),
            code,
            state,
        )
        .await
    }

    pub async fn ldc_user_info(&self) -> Result<LdcUserInfo, FireCoreError> {
        info!("fetching LDC user info");
        let raw = self
            .get_json_value(
                "ldc user info",
                &format!("{LDC_BASE_URL}/api/v1/oauth/user-info"),
            )
            .await?;
        parse_ldc_user_info_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "ldc user info",
            source,
        })
    }

    pub async fn ldc_logout(&self) -> Result<(), FireCoreError> {
        info!("logging out LDC OAuth session");
        let traced = self
            .build_json_get_request(
                "ldc logout",
                &format!("{LDC_BASE_URL}/api/v1/oauth/logout"),
                vec![],
                &[],
            )?
            .without_csrf_header();
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "ldc logout", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn ldc_reward(
        &self,
        client_id: &str,
        client_secret: &str,
        request: LdcRewardRequest,
    ) -> Result<LdcRewardResult, FireCoreError> {
        info!(
            user_id = request.user_id,
            username = %request.username,
            amount = request.amount,
            "executing LDC reward"
        );

        let auth = basic_auth_header(client_id, client_secret);
        let mut body = serde_json::Map::new();
        body.insert("user_id".into(), Value::from(request.user_id));
        body.insert("username".into(), Value::from(request.username));
        body.insert("amount".into(), Value::from(request.amount));
        body.insert("out_trade_no".into(), Value::from(request.out_trade_no));
        if let Some(remark) = request.remark.filter(|value| !value.trim().is_empty()) {
            body.insert("remark".into(), Value::from(remark));
        }

        let traced = self.build_api_request_with_body(
            "ldc reward",
            Method::POST,
            &format!("{LDC_BASE_URL}/epay/pay/distribute"),
            Some("application/json; charset=utf-8"),
            RequestBody::from(Value::Object(body).to_string()),
            false,
        )?;
        let mut traced = traced;
        traced.request.headers_mut().insert(
            "Authorization",
            HeaderValue::from_str(&auth).expect("Basic auth header should be ASCII"),
        );

        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "ldc reward", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("ldc reward", trace_id, response)
            .await?;
        parse_ldc_reward_result_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "ldc reward",
            source,
        })
    }

    pub(crate) async fn get_json_value(
        &self,
        operation: &'static str,
        url: &str,
    ) -> Result<Value, FireCoreError> {
        let traced = self
            .build_json_get_request(operation, url, vec![], &[])?
            .without_csrf_header();
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, operation, trace_id, response).await?;
        self.read_response_json(operation, trace_id, response).await
    }

    pub(crate) async fn oauth_approval_link(
        &self,
        operation: &'static str,
        authorization_url: &str,
    ) -> Result<String, FireCoreError> {
        let traced = self
            .build_html_get_request(operation, authorization_url)?
            .without_csrf_header();
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, operation, trace_id, response).await?;
        let html = self.read_response_text(trace_id, response).await?;
        extract_oauth_approve_path(&html).ok_or_else(|| FireCoreError::ResponseDeserialize {
            operation,
            source: crate::json_helpers::invalid_json(
                "OAuth approval page did not contain an approval link",
            ),
        })
    }

    pub(crate) async fn oauth_approve_redirect(
        &self,
        operation: &'static str,
        approve_path: &str,
    ) -> Result<LdcApprovalStatus, FireCoreError> {
        let approve_url = if approve_path.starts_with("https://") {
            approve_path.to_string()
        } else {
            format!("{CONNECT_BASE_URL}{approve_path}")
        };
        let traced = self
            .build_html_get_request(operation, &approve_url)?
            .without_csrf_header();
        let (trace_id, response) = self
            .execute_request_with_options(traced, CallOptions::new().follow_redirects(false))
            .await?;
        if response.status().is_redirection() {
            let location = response
                .headers()
                .get(LOCATION)
                .and_then(|value| value.to_str().ok())
                .map(str::to_string);
            let _ = self.read_response_text(trace_id, response).await?;
            if let Some(status) = location.as_deref().and_then(approval_status_from_location) {
                return Ok(status);
            }
            return Err(FireCoreError::ResponseDeserialize {
                operation,
                source: crate::json_helpers::invalid_json(
                    "OAuth approval redirect did not contain code and state",
                ),
            });
        }

        let response = expect_success(self, operation, trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(LdcApprovalStatus::Pending)
    }

    pub(crate) async fn oauth_callback(
        &self,
        operation: &'static str,
        callback_url: &str,
        code: &str,
        state: &str,
    ) -> Result<(), FireCoreError> {
        let fields = vec![("code", code.to_string()), ("state", state.to_string())];
        let traced = self
            .build_form_request(operation, Method::POST, callback_url, fields, false)?
            .without_csrf_header();
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, operation, trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}

fn approval_status_from_location(location: &str) -> Option<LdcApprovalStatus> {
    let url = url::Url::parse(location).ok()?;
    let mut code = None;
    let mut state = None;
    let mut denied = false;
    for (key, value) in url.query_pairs() {
        match key.as_ref() {
            "code" => code = Some(value.into_owned()),
            "state" => state = Some(value.into_owned()),
            "error" if value == "access_denied" || value == "denied" => denied = true,
            _ => {}
        }
    }
    if denied {
        return Some(LdcApprovalStatus::Denied);
    }
    Some(LdcApprovalStatus::Approved {
        code: code?,
        state: state?,
    })
}

fn basic_auth_header(client_id: &str, client_secret: &str) -> String {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let credentials = format!("{client_id}:{client_secret}");
    format!("Basic {}", STANDARD.encode(credentials.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::{approval_status_from_location, basic_auth_header};
    use fire_models::LdcApprovalStatus;

    #[test]
    fn parses_code_and_state_from_callback_redirect() {
        let parsed = approval_status_from_location(
            "https://credit.linux.do/api/v1/oauth/callback?code=abc&state=xyz",
        );

        assert_eq!(
            parsed,
            Some(LdcApprovalStatus::Approved {
                code: "abc".to_string(),
                state: "xyz".to_string()
            })
        );
    }

    #[test]
    fn builds_basic_auth_header() {
        assert_eq!(
            basic_auth_header("client", "secret"),
            "Basic Y2xpZW50OnNlY3JldA=="
        );
    }
}
