use fire_models::{DohPreset, DohProbeResult, DohSettings};

#[derive(uniffi::Record, Debug, Clone)]
pub struct DohSettingsState {
    pub enabled: bool,
    pub endpoint_url: String,
}

impl From<DohSettings> for DohSettingsState {
    fn from(value: DohSettings) -> Self {
        Self {
            enabled: value.enabled,
            endpoint_url: value.endpoint_url,
        }
    }
}

impl From<DohSettingsState> for DohSettings {
    fn from(value: DohSettingsState) -> Self {
        Self {
            enabled: value.enabled,
            endpoint_url: value.endpoint_url,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DohPresetState {
    pub id: String,
    pub display_name: String,
    pub endpoint_url: String,
    pub bootstrap_ips: Vec<String>,
}

impl From<&DohPreset> for DohPresetState {
    fn from(value: &DohPreset) -> Self {
        Self {
            id: value.id.to_string(),
            display_name: value.display_name.to_string(),
            endpoint_url: value.endpoint_url.to_string(),
            bootstrap_ips: value
                .bootstrap_ips
                .iter()
                .map(|ip| (*ip).to_string())
                .collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DohProbeResultState {
    pub ok: bool,
    pub host: String,
    pub resolved_addresses: Vec<String>,
    pub elapsed_ms: u64,
    pub error_message: Option<String>,
}

impl From<DohProbeResult> for DohProbeResultState {
    fn from(value: DohProbeResult) -> Self {
        Self {
            ok: value.ok,
            host: value.host,
            resolved_addresses: value.resolved_addresses,
            elapsed_ms: value.elapsed_ms,
            error_message: value.error_message,
        }
    }
}
