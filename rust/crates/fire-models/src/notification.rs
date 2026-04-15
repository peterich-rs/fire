use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationAlert {
    pub message_id: i64,
    pub notification_type: Option<u32>,
    pub topic_id: Option<u64>,
    pub post_number: Option<u32>,
    pub topic_title: Option<String>,
    pub excerpt: Option<String>,
    pub username: Option<String>,
    pub post_url: Option<String>,
    pub payload_json: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationAlertPollResult {
    pub notification_user_id: u64,
    pub client_id: String,
    pub last_message_id: i64,
    pub alerts: Vec<NotificationAlert>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationCounters {
    pub all_unread: u32,
    pub unread: u32,
    pub high_priority: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationData {
    pub display_username: Option<String>,
    pub original_post_id: Option<String>,
    pub original_post_type: Option<i32>,
    pub original_username: Option<String>,
    pub revision_number: Option<u32>,
    pub topic_title: Option<String>,
    pub badge_name: Option<String>,
    pub badge_id: Option<u64>,
    pub badge_slug: Option<String>,
    pub group_name: Option<String>,
    pub inbox_count: Option<String>,
    pub count: Option<u32>,
    pub username: Option<String>,
    pub username2: Option<String>,
    pub avatar_template: Option<String>,
    pub excerpt: Option<String>,
    pub payload_json: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationItem {
    pub id: u64,
    pub user_id: Option<u64>,
    pub notification_type: i32,
    pub read: bool,
    pub high_priority: bool,
    pub created_at: Option<String>,
    pub created_timestamp_unix_ms: Option<u64>,
    pub post_number: Option<u32>,
    pub topic_id: Option<u64>,
    pub slug: Option<String>,
    pub fancy_title: Option<String>,
    pub acting_user_avatar_template: Option<String>,
    pub data: NotificationData,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationListResponse {
    pub notifications: Vec<NotificationItem>,
    pub total_rows_notifications: u32,
    pub seen_notification_id: Option<u64>,
    pub load_more_notifications: Option<String>,
    pub next_offset: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationState {
    pub counters: NotificationCounters,
    pub recent: Vec<NotificationItem>,
    pub has_loaded_recent: bool,
    pub recent_seen_notification_id: Option<u64>,
    pub full: Vec<NotificationItem>,
    pub has_loaded_full: bool,
    pub total_rows_notifications: u32,
    pub full_seen_notification_id: Option<u64>,
    pub full_load_more_notifications: Option<String>,
    pub full_next_offset: Option<u32>,
}
