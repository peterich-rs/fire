use fire_models::{
    MessageBusClientMode, MessageBusEvent, MessageBusEventKind, MessageBusSubscription,
    MessageBusSubscriptionScope, NotificationAlert, NotificationAlertPollResult, TopicPresence,
    TopicPresenceUser,
};

use crate::state_topic_list::TopicListKindState;

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum MessageBusClientModeState {
    Foreground,
    IosBackground,
}

impl From<MessageBusClientMode> for MessageBusClientModeState {
    fn from(value: MessageBusClientMode) -> Self {
        match value {
            MessageBusClientMode::Foreground => Self::Foreground,
            MessageBusClientMode::IosBackground => Self::IosBackground,
        }
    }
}

impl From<MessageBusClientModeState> for MessageBusClientMode {
    fn from(value: MessageBusClientModeState) -> Self {
        match value {
            MessageBusClientModeState::Foreground => Self::Foreground,
            MessageBusClientModeState::IosBackground => Self::IosBackground,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum MessageBusSubscriptionScopeState {
    Durable,
    Transient,
}

impl From<MessageBusSubscriptionScope> for MessageBusSubscriptionScopeState {
    fn from(value: MessageBusSubscriptionScope) -> Self {
        match value {
            MessageBusSubscriptionScope::Durable => Self::Durable,
            MessageBusSubscriptionScope::Transient => Self::Transient,
        }
    }
}

impl From<MessageBusSubscriptionScopeState> for MessageBusSubscriptionScope {
    fn from(value: MessageBusSubscriptionScopeState) -> Self {
        match value {
            MessageBusSubscriptionScopeState::Durable => Self::Durable,
            MessageBusSubscriptionScopeState::Transient => Self::Transient,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct MessageBusSubscriptionState {
    pub owner_token: String,
    pub channel: String,
    pub last_message_id: Option<i64>,
    pub scope: MessageBusSubscriptionScopeState,
}

impl From<MessageBusSubscription> for MessageBusSubscriptionState {
    fn from(value: MessageBusSubscription) -> Self {
        Self {
            owner_token: value.owner_token,
            channel: value.channel,
            last_message_id: value.last_message_id,
            scope: value.scope.into(),
        }
    }
}

impl From<MessageBusSubscriptionState> for MessageBusSubscription {
    fn from(value: MessageBusSubscriptionState) -> Self {
        Self {
            owner_token: value.owner_token,
            channel: value.channel,
            last_message_id: value.last_message_id,
            scope: value.scope.into(),
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum MessageBusEventKindState {
    TopicList,
    TopicDetail,
    TopicReaction,
    Presence,
    Notification,
    NotificationAlert,
    Unknown,
}

impl From<MessageBusEventKind> for MessageBusEventKindState {
    fn from(value: MessageBusEventKind) -> Self {
        match value {
            MessageBusEventKind::TopicList => Self::TopicList,
            MessageBusEventKind::TopicDetail => Self::TopicDetail,
            MessageBusEventKind::TopicReaction => Self::TopicReaction,
            MessageBusEventKind::Presence => Self::Presence,
            MessageBusEventKind::Notification => Self::Notification,
            MessageBusEventKind::NotificationAlert => Self::NotificationAlert,
            MessageBusEventKind::Unknown => Self::Unknown,
        }
    }
}

impl From<MessageBusEventKindState> for MessageBusEventKind {
    fn from(value: MessageBusEventKindState) -> Self {
        match value {
            MessageBusEventKindState::TopicList => Self::TopicList,
            MessageBusEventKindState::TopicDetail => Self::TopicDetail,
            MessageBusEventKindState::TopicReaction => Self::TopicReaction,
            MessageBusEventKindState::Presence => Self::Presence,
            MessageBusEventKindState::Notification => Self::Notification,
            MessageBusEventKindState::NotificationAlert => Self::NotificationAlert,
            MessageBusEventKindState::Unknown => Self::Unknown,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct MessageBusEventState {
    pub channel: String,
    pub message_id: i64,
    pub kind: MessageBusEventKindState,
    pub topic_list_kind: Option<TopicListKindState>,
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

impl From<MessageBusEvent> for MessageBusEventState {
    fn from(value: MessageBusEvent) -> Self {
        Self {
            channel: value.channel,
            message_id: value.message_id,
            kind: value.kind.into(),
            topic_list_kind: value.topic_list_kind.map(Into::into),
            topic_id: value.topic_id,
            notification_user_id: value.notification_user_id,
            message_type: value.message_type,
            detail_event_type: value.detail_event_type,
            reload_topic: value.reload_topic,
            refresh_stream: value.refresh_stream,
            all_unread_notifications_count: value.all_unread_notifications_count,
            unread_notifications: value.unread_notifications,
            unread_high_priority_notifications: value.unread_high_priority_notifications,
            payload_json: value.payload_json,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPresenceUserState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicPresenceUser> for TopicPresenceUserState {
    fn from(value: TopicPresenceUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPresenceState {
    pub topic_id: u64,
    pub message_id: i64,
    pub users: Vec<TopicPresenceUserState>,
}

impl From<TopicPresence> for TopicPresenceState {
    fn from(value: TopicPresence) -> Self {
        Self {
            topic_id: value.topic_id,
            message_id: value.message_id,
            users: value.users.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationAlertState {
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

impl From<NotificationAlert> for NotificationAlertState {
    fn from(value: NotificationAlert) -> Self {
        Self {
            message_id: value.message_id,
            notification_type: value.notification_type,
            topic_id: value.topic_id,
            post_number: value.post_number,
            topic_title: value.topic_title,
            excerpt: value.excerpt,
            username: value.username,
            post_url: value.post_url,
            payload_json: value.payload_json,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationAlertPollResultState {
    pub notification_user_id: u64,
    pub client_id: String,
    pub last_message_id: i64,
    pub alerts: Vec<NotificationAlertState>,
}

impl From<NotificationAlertPollResult> for NotificationAlertPollResultState {
    fn from(value: NotificationAlertPollResult) -> Self {
        Self {
            notification_user_id: value.notification_user_id,
            client_id: value.client_id,
            last_message_id: value.last_message_id,
            alerts: value.alerts.into_iter().map(Into::into).collect(),
        }
    }
}

#[uniffi::export(with_foreign)]
pub trait MessageBusEventHandler: Send + Sync {
    fn on_message_bus_event(&self, event: MessageBusEventState);
}
