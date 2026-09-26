use fire_models::{
    BrowserHttpRequest, BrowserHttpResponse, BrowserTransportPref, CloudflarePolicy,
};

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserTransportPrefState {
    Off,
    Session,
    Persistent,
}

impl From<BrowserTransportPref> for BrowserTransportPrefState {
    fn from(value: BrowserTransportPref) -> Self {
        match value {
            BrowserTransportPref::Off => Self::Off,
            BrowserTransportPref::Session => Self::Session,
            BrowserTransportPref::Persistent => Self::Persistent,
        }
    }
}

impl From<BrowserTransportPrefState> for BrowserTransportPref {
    fn from(value: BrowserTransportPrefState) -> Self {
        match value {
            BrowserTransportPrefState::Off => Self::Off,
            BrowserTransportPrefState::Session => Self::Session,
            BrowserTransportPrefState::Persistent => Self::Persistent,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CloudflarePolicyState {
    pub auto_verify: bool,
    pub browser_transport: BrowserTransportPrefState,
}

impl From<CloudflarePolicy> for CloudflarePolicyState {
    fn from(value: CloudflarePolicy) -> Self {
        Self {
            auto_verify: value.auto_verify,
            browser_transport: value.browser_transport.into(),
        }
    }
}

impl From<CloudflarePolicyState> for CloudflarePolicy {
    fn from(value: CloudflarePolicyState) -> Self {
        Self {
            auto_verify: value.auto_verify,
            browser_transport: value.browser_transport.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BrowserHttpHeaderState {
    pub name: String,
    pub value: String,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BrowserHttpRequestState {
    pub method: String,
    pub url: String,
    pub headers: Vec<BrowserHttpHeaderState>,
    pub body: Option<Vec<u8>>,
    pub timeout_ms: u32,
}

impl From<BrowserHttpRequest> for BrowserHttpRequestState {
    fn from(value: BrowserHttpRequest) -> Self {
        Self {
            method: value.method,
            url: value.url,
            headers: value
                .headers
                .into_iter()
                .map(|(name, value)| BrowserHttpHeaderState { name, value })
                .collect(),
            body: value.body,
            timeout_ms: value.timeout_ms,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BrowserHttpResponseState {
    pub status: u16,
    pub headers: Vec<BrowserHttpHeaderState>,
    pub body: Vec<u8>,
}

impl From<BrowserHttpResponseState> for BrowserHttpResponse {
    fn from(value: BrowserHttpResponseState) -> Self {
        Self {
            status: value.status,
            headers: value
                .headers
                .into_iter()
                .map(|header| (header.name, header.value))
                .collect(),
            body: value.body,
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait BrowserHttpHandler: Send + Sync {
    fn execute_browser_http(
        &self,
        request: BrowserHttpRequestState,
    ) -> Result<BrowserHttpResponseState, FireUniFfiError>;
}

use fire_uniffi_types::FireUniFfiError;
