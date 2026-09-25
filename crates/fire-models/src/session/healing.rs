use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CookieSelfHealingPhase {
    Sweep,
    NuclearReset,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookieSelfHealingRequest {
    pub operation: String,
    pub request_url: String,
    pub target_url: String,
    pub phase: CookieSelfHealingPhase,
    pub attempt: u8,
    pub cookie_names: Vec<String>,
    pub session_epoch: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookieSelfHealingResult {
    pub completed: bool,
    pub session_epoch: u64,
}
