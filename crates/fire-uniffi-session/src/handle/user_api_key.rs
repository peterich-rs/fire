use std::sync::Arc;

use fire_uniffi_types::{run_fallible, run_infallible, run_on_ffi_runtime, FireUniFfiError};

use crate::records::*;
use crate::FireSessionHandle;

#[uniffi::export]
impl FireSessionHandle {
    pub fn register_user_api_key_crypto_handler(
        &self,
        handler: Arc<dyn UserApiKeyCryptoHandler>,
    ) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "register_user_api_key_crypto_handler",
            move |inner| {
                let public = Arc::clone(&handler);
                let decrypt = Arc::clone(&handler);
                let read = Arc::clone(&handler);
                let write = Arc::clone(&handler);
                let clear = Arc::clone(&handler);
                inner.set_user_api_key_crypto_handler(
                    move || public.public_key_pem(),
                    move |payload| decrypt.decrypt_payload(payload),
                    move || read.read_api_key(),
                    move |key| write.write_api_key(key),
                    move || clear.clear_api_key(),
                );
            },
        )
    }

    pub fn unregister_user_api_key_crypto_handler(&self) -> Result<(), FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "unregister_user_api_key_crypto_handler",
            |inner| inner.clear_user_api_key_crypto_handler(),
        )
    }

    pub fn build_user_api_key_authorize_url(
        &self,
        public_key_pem: String,
        client_id: String,
        application_name: Option<String>,
    ) -> Result<UserApiKeyAuthorizeUrlState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "build_user_api_key_authorize_url",
            move |inner| {
                inner
                    .build_user_api_key_authorize_url(public_key_pem, client_id, application_name)
                    .map(Into::into)
            },
        )
    }

    pub async fn handle_user_api_key_auth_redirect(
        &self,
        uri: String,
    ) -> Result<UserApiKeyAuthRedirectResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime(
            "handle_user_api_key_auth_redirect",
            panic_state,
            async move { inner.handle_user_api_key_auth_redirect(uri).await },
        )
        .await?;
        Ok(result.into())
    }

    pub async fn complete_user_api_key_login(
        &self,
        otp: String,
        api_key: Option<String>,
    ) -> Result<UserApiKeyAuthRedirectResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime("complete_user_api_key_login", panic_state, async move {
            inner.complete_user_api_key_login(otp, api_key).await
        })
        .await?;
        Ok(result.into())
    }

    pub async fn create_qr_login_payload(
        &self,
        public_key_pem: String,
        client_id: String,
        username: Option<String>,
    ) -> Result<QrLoginPayloadState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime("create_qr_login_payload", panic_state, async move {
            inner
                .create_qr_login_payload(public_key_pem, client_id, username)
                .await
        })
        .await?;
        Ok(result.into())
    }

    pub fn encode_qr_login_payload(
        &self,
        payload: QrLoginPayloadState,
        scheme: String,
    ) -> Result<String, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "encode_qr_login_payload",
            move |inner| inner.encode_qr_login_payload(&payload.into(), &scheme),
        )
    }

    pub fn parse_qr_login_payload(
        &self,
        raw: String,
    ) -> Result<Option<QrLoginPayloadState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "parse_qr_login_payload",
            move |_inner| fire_core::parse_qr_login_payload(&raw).map(Into::into),
        )
    }

    pub async fn login_with_qr_payload(
        &self,
        raw: String,
    ) -> Result<UserApiKeyAuthRedirectResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime("login_with_qr_payload", panic_state, async move {
            inner.login_with_qr_payload(raw).await
        })
        .await?;
        Ok(result.into())
    }
}
