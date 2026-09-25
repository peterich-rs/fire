use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::topic::TopicCategory;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PreloadedDataResult {
    pub current_user: Option<crate::user::CurrentUserSnapshot>,
    pub site_settings: Option<serde_json::Value>,
    pub site: Option<serde_json::Value>,
    pub topic_tracking_state_meta: Option<HashMap<String, u64>>,
    pub topic_tracking_states: Option<Vec<serde_json::Value>>,
    pub custom_emoji: Option<Vec<serde_json::Value>>,
    pub topic_list: Option<serde_json::Value>,
    pub enabled_reaction_ids: Vec<String>,
    pub categories: Vec<TopicCategory>,
    pub top_tags: Vec<String>,
    pub can_tag_topics: Option<bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreloadedDataState {
    NotStarted,
    Loading,
    Ready,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RefreshTrigger {
    LoginCompleted,
    LogoutCompleted,
    SessionRestored,
    /// Full session rebuild after a successful Cloudflare challenge.
    CloudflareResolved,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RefreshBatch {
    Core,
    Secondary,
}

#[derive(Debug, Clone)]
pub struct AppStateRefreshEvent {
    pub batch: RefreshBatch,
    pub trigger: RefreshTrigger,
}
