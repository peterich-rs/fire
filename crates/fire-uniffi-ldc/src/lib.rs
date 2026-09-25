uniffi::setup_scaffolding!("fire_uniffi_ldc");

use std::sync::Arc;

use fire_uniffi_types::{run_on_ffi_runtime, FireUniFfiError, SharedFireCore};

pub mod records;

pub use records::{
    CdkAuthorizationUrlState, CdkUserInfoState, LdcApprovalStatusKindState, LdcApprovalStatusState,
    LdcAuthorizationUrlState, LdcRewardRequestState, LdcRewardResultState, LdcUserInfoState,
};

#[derive(uniffi::Object)]
pub struct FireLdcHandle {
    shared: Arc<SharedFireCore>,
}

impl FireLdcHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireLdcHandle {
    pub async fn ldc_authorization_url(&self) -> Result<LdcAuthorizationUrlState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let auth = run_on_ffi_runtime("ldc_authorization_url", panic_state, async move {
            inner.ldc_authorization_url().await
        })
        .await?;
        Ok(auth.into())
    }

    pub async fn ldc_approval_link(
        &self,
        authorization_url: String,
    ) -> Result<String, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("ldc_approval_link", panic_state, async move {
            inner.ldc_approval_link(&authorization_url).await
        })
        .await
    }

    pub async fn ldc_approve(
        &self,
        approve_path: String,
    ) -> Result<LdcApprovalStatusState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let status = run_on_ffi_runtime("ldc_approve", panic_state, async move {
            inner.ldc_approve(&approve_path).await
        })
        .await?;
        Ok(status.into())
    }

    pub async fn ldc_callback(&self, code: String, state: String) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("ldc_callback", panic_state, async move {
            inner.ldc_callback(&code, &state).await
        })
        .await
    }

    pub async fn ldc_user_info(&self) -> Result<LdcUserInfoState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let info = run_on_ffi_runtime("ldc_user_info", panic_state, async move {
            inner.ldc_user_info().await
        })
        .await?;
        Ok(info.into())
    }

    pub async fn ldc_logout(&self) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("ldc_logout", panic_state, async move {
            inner.ldc_logout().await
        })
        .await
    }

    pub async fn ldc_reward(
        &self,
        client_id: String,
        client_secret: String,
        request: LdcRewardRequestState,
    ) -> Result<LdcRewardResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let reward = run_on_ffi_runtime("ldc_reward", panic_state, async move {
            inner
                .ldc_reward(&client_id, &client_secret, request.into())
                .await
        })
        .await?;
        Ok(reward.into())
    }

    pub async fn cdk_authorization_url(&self) -> Result<CdkAuthorizationUrlState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let auth = run_on_ffi_runtime("cdk_authorization_url", panic_state, async move {
            inner.cdk_authorization_url().await
        })
        .await?;
        Ok(auth.into())
    }

    pub async fn cdk_approval_link(
        &self,
        authorization_url: String,
    ) -> Result<String, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("cdk_approval_link", panic_state, async move {
            inner.cdk_approval_link(&authorization_url).await
        })
        .await
    }

    pub async fn cdk_approve(
        &self,
        approve_path: String,
    ) -> Result<LdcApprovalStatusState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let status = run_on_ffi_runtime("cdk_approve", panic_state, async move {
            inner.cdk_approve(&approve_path).await
        })
        .await?;
        Ok(status.into())
    }

    pub async fn cdk_callback(&self, code: String, state: String) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("cdk_callback", panic_state, async move {
            inner.cdk_callback(&code, &state).await
        })
        .await
    }

    pub async fn cdk_user_info(&self) -> Result<CdkUserInfoState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let info = run_on_ffi_runtime("cdk_user_info", panic_state, async move {
            inner.cdk_user_info().await
        })
        .await?;
        Ok(info.into())
    }

    pub async fn cdk_logout(&self) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("cdk_logout", panic_state, async move {
            inner.cdk_logout().await
        })
        .await
    }
}
