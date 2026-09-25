use serde::{Deserialize, Serialize};

use crate::cookie::PlatformCookie;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CloudflareRequestMode {
    Silent,
    Action,
    Data,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CloudflareChallengeRequest {
    pub operation: String,
    pub request_url: String,
    pub origin_url: Option<String>,
    pub is_foreground: bool,
    pub session_epoch: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CloudflareChallengeResult {
    pub completed: bool,
    pub user_cancelled: bool,
    pub fresh_cf_clearance: Option<String>,
    pub cookies: Vec<PlatformCookie>,
    pub browser_user_agent: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CloudflareClearanceResolvedEvent {
    pub generation: u64,
    pub has_login_session: bool,
    pub can_open_message_bus: bool,
}
