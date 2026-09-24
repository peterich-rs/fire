use fire_uniffi_types::{run_fallible, run_infallible, run_on_ffi_runtime, FireUniFfiError};

use crate::records::*;
use crate::FireSessionHandle;

#[uniffi::export]
impl FireSessionHandle {
    pub fn list_doh_presets(&self) -> Result<Vec<DohPresetState>, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "list_doh_presets",
            |inner| {
                inner
                    .list_doh_presets()
                    .iter()
                    .map(DohPresetState::from)
                    .collect()
            },
        )
    }
    pub fn get_doh_settings(&self) -> Result<DohSettingsState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "get_doh_settings",
            |inner| inner.doh_settings().into(),
        )
    }
    pub fn set_doh_settings(
        &self,
        settings: DohSettingsState,
    ) -> Result<DohSettingsState, FireUniFfiError> {
        run_fallible(
            &self.shared.panic_state,
            &self.shared.core,
            "set_doh_settings",
            move |inner| inner.set_doh_settings(settings.into()).map(Into::into),
        )
    }
    pub async fn probe_doh_settings(
        &self,
        settings: DohSettingsState,
        host: Option<String>,
    ) -> Result<DohProbeResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let result = run_on_ffi_runtime("probe_doh_settings", panic_state, async move {
            inner.probe_doh_settings(settings.into(), host).await
        })
        .await?;
        Ok(result.into())
    }
}
