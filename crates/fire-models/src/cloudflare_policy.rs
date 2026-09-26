use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum BrowserTransportPref {
    #[default]
    Off,
    Session,
    Persistent,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum NetworkTransport {
    #[default]
    Native,
    BrowserSession,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CloudflarePolicy {
    #[serde(default = "default_auto_verify")]
    pub auto_verify: bool,
    #[serde(default)]
    pub browser_transport: BrowserTransportPref,
}

impl Default for CloudflarePolicy {
    fn default() -> Self {
        Self {
            auto_verify: true,
            browser_transport: BrowserTransportPref::Off,
        }
    }
}

fn default_auto_verify() -> bool {
    true
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BrowserHttpRequest {
    pub method: String,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
    pub timeout_ms: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BrowserHttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}
