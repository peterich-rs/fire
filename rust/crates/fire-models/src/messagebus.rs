use serde::{Deserialize, Serialize};

use crate::topic::TopicListKind;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageBusClientMode {
    #[default]
    Foreground,
    IosBackground,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageBusSubscriptionScope {
    #[default]
    Durable,
    Transient,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageBusSubscription {
    pub owner_token: String,
    pub channel: String,
    pub last_message_id: Option<i64>,
    pub scope: MessageBusSubscriptionScope,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageBusEventKind {
    TopicList,
    TopicDetail,
    TopicReaction,
    Presence,
    Notification,
    NotificationAlert,
    #[default]
    Unknown,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageBusEvent {
    pub channel: String,
    pub message_id: i64,
    pub kind: MessageBusEventKind,
    pub topic_list_kind: Option<TopicListKind>,
    pub topic_id: Option<u64>,
    pub notification_user_id: Option<u64>,
    pub message_type: Option<String>,
    pub detail_event_type: Option<String>,
    pub reload_topic: bool,
    pub refresh_stream: bool,
    pub all_unread_notifications_count: Option<u32>,
    pub unread_notifications: Option<u32>,
    pub unread_high_priority_notifications: Option<u32>,
    pub payload_json: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPresenceUser {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPresence {
    pub topic_id: u64,
    pub message_id: i64,
    pub users: Vec<TopicPresenceUser>,
}

impl TopicPresence {
    pub fn empty(topic_id: u64) -> Self {
        Self {
            topic_id,
            message_id: -1,
            users: Vec::new(),
        }
    }
}
