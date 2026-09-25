use fire_models::{CdkAuthorizationUrl, CdkUserInfo, LdcApprovalStatus};
use serde_json::Value;
use tracing::info;

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    ldc_payloads::{parse_cdk_user_info_value, parse_ldc_authorization_url_value},
};

const CDK_BASE_URL: &str = "https://cdk.linux.do";

impl FireCore {
    pub async fn cdk_authorization_url(&self) -> Result<CdkAuthorizationUrl, FireCoreError> {
        info!("fetching CDK authorization URL");
        let raw = self
            .get_json_value(
                "cdk authorization url",
                &format!("{CDK_BASE_URL}/api/v1/oauth/login"),
            )
            .await?;
        let auth = parse_ldc_authorization_url_value(raw).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "cdk authorization url",
                source,
            }
        })?;
        Ok(CdkAuthorizationUrl {
            url: auth.url,
            state: auth.state,
        })
    }

    pub async fn cdk_approval_link(
        &self,
        authorization_url: &str,
    ) -> Result<String, FireCoreError> {
        info!("loading CDK authorization page");
        self.oauth_approval_link("cdk approval page", authorization_url)
            .await
    }

    pub async fn cdk_approve(
        &self,
        approve_path: &str,
    ) -> Result<LdcApprovalStatus, FireCoreError> {
        info!("approving CDK authorization");
        self.oauth_approve_redirect("cdk approve", approve_path)
            .await
    }

    pub async fn cdk_callback(&self, code: &str, state: &str) -> Result<(), FireCoreError> {
        info!("posting CDK OAuth callback");
        self.oauth_callback(
            "cdk callback",
            &format!("{CDK_BASE_URL}/api/v1/oauth/callback"),
            code,
            state,
        )
        .await
    }

    pub async fn cdk_user_info(&self) -> Result<CdkUserInfo, FireCoreError> {
        info!("fetching CDK user info");
        let raw: Value = self
            .get_json_value(
                "cdk user info",
                &format!("{CDK_BASE_URL}/api/v1/oauth/user-info"),
            )
            .await?;
        parse_cdk_user_info_value(raw).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "cdk user info",
            source,
        })
    }

    pub async fn cdk_logout(&self) -> Result<(), FireCoreError> {
        info!("logging out CDK OAuth session");
        let traced = self
            .build_json_get_request(
                "cdk logout",
                &format!("{CDK_BASE_URL}/api/v1/oauth/logout"),
                vec![],
                &[],
            )?
            .without_csrf_header();
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "cdk logout", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
