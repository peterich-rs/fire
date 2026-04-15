use fire_models::{
    NotificationCounters, NotificationData, NotificationItem, NotificationListResponse,
    NotificationState,
};

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationCountersState {
    pub all_unread: u32,
    pub unread: u32,
    pub high_priority: u32,
}

impl From<NotificationCounters> for NotificationCountersState {
    fn from(value: NotificationCounters) -> Self {
        Self {
            all_unread: value.all_unread,
            unread: value.unread,
            high_priority: value.high_priority,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationDataState {
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

impl From<NotificationData> for NotificationDataState {
    fn from(value: NotificationData) -> Self {
        Self {
            display_username: value.display_username,
            original_post_id: value.original_post_id,
            original_post_type: value.original_post_type,
            original_username: value.original_username,
            revision_number: value.revision_number,
            topic_title: value.topic_title,
            badge_name: value.badge_name,
            badge_id: value.badge_id,
            badge_slug: value.badge_slug,
            group_name: value.group_name,
            inbox_count: value.inbox_count,
            count: value.count,
            username: value.username,
            username2: value.username2,
            avatar_template: value.avatar_template,
            excerpt: value.excerpt,
            payload_json: value.payload_json,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationItemState {
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
    pub data: NotificationDataState,
}

impl From<NotificationItem> for NotificationItemState {
    fn from(value: NotificationItem) -> Self {
        Self {
            id: value.id,
            user_id: value.user_id,
            notification_type: value.notification_type,
            read: value.read,
            high_priority: value.high_priority,
            created_at: value.created_at,
            created_timestamp_unix_ms: value.created_timestamp_unix_ms,
            post_number: value.post_number,
            topic_id: value.topic_id,
            slug: value.slug,
            fancy_title: value.fancy_title,
            acting_user_avatar_template: value.acting_user_avatar_template,
            data: value.data.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationListState {
    pub notifications: Vec<NotificationItemState>,
    pub total_rows_notifications: u32,
    pub seen_notification_id: Option<u64>,
    pub load_more_notifications: Option<String>,
    pub next_offset: Option<u32>,
}

impl From<NotificationListResponse> for NotificationListState {
    fn from(value: NotificationListResponse) -> Self {
        Self {
            notifications: value.notifications.into_iter().map(Into::into).collect(),
            total_rows_notifications: value.total_rows_notifications,
            seen_notification_id: value.seen_notification_id,
            load_more_notifications: value.load_more_notifications,
            next_offset: value.next_offset,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NotificationCenterState {
    pub counters: NotificationCountersState,
    pub recent: Vec<NotificationItemState>,
    pub has_loaded_recent: bool,
    pub recent_seen_notification_id: Option<u64>,
    pub full: Vec<NotificationItemState>,
    pub has_loaded_full: bool,
    pub total_rows_notifications: u32,
    pub full_seen_notification_id: Option<u64>,
    pub full_load_more_notifications: Option<String>,
    pub full_next_offset: Option<u32>,
}

impl From<NotificationState> for NotificationCenterState {
    fn from(value: NotificationState) -> Self {
        Self {
            counters: value.counters.into(),
            recent: value.recent.into_iter().map(Into::into).collect(),
            has_loaded_recent: value.has_loaded_recent,
            recent_seen_notification_id: value.recent_seen_notification_id,
            full: value.full.into_iter().map(Into::into).collect(),
            has_loaded_full: value.has_loaded_full,
            total_rows_notifications: value.total_rows_notifications,
            full_seen_notification_id: value.full_seen_notification_id,
            full_load_more_notifications: value.full_load_more_notifications,
            full_next_offset: value.full_next_offset,
        }
    }
}
