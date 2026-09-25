use fire_models::{AppStateRefreshEvent, RefreshBatch};

#[derive(uniffi::Record, Debug, Clone)]
pub struct CurrentUserSnapshotState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub animated_avatar: Option<String>,
    pub trust_level: u8,
    pub status_description: Option<String>,
    pub status_emoji: Option<String>,
    pub flair_url: Option<String>,
    pub flair_name: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub flair_group_id: Option<u64>,
    pub gamification_score: Option<i64>,
    pub unread_notifications: u32,
    pub unread_high_priority_notifications: u32,
    pub all_unread_notifications_count: u32,
    pub seen_notification_id: u64,
    pub notification_channel_position: i64,
}

impl From<fire_models::CurrentUserSnapshot> for CurrentUserSnapshotState {
    fn from(value: fire_models::CurrentUserSnapshot) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            animated_avatar: value.animated_avatar,
            trust_level: value.trust_level,
            status_description: value.status.as_ref().and_then(|s| s.description.clone()),
            status_emoji: value.status.and_then(|s| s.emoji),
            flair_url: value.flair_url,
            flair_name: value.flair_name,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            flair_group_id: value.flair_group_id,
            gamification_score: value.gamification_score,
            unread_notifications: value.unread_notifications,
            unread_high_priority_notifications: value.unread_high_priority_notifications,
            all_unread_notifications_count: value.all_unread_notifications_count,
            seen_notification_id: value.seen_notification_id,
            notification_channel_position: value.notification_channel_position,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum PreloadedDataStateState {
    NotStarted,
    Loading,
    Ready,
    Failed { error: String },
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum LoginStateDeterminationState {
    LoggedIn { username: String, user_id: u64 },
    NotLoggedIn,
    SessionExpired,
    NetworkErrorPreserveState,
}

impl From<fire_models::LoginStateDetermination> for LoginStateDeterminationState {
    fn from(value: fire_models::LoginStateDetermination) -> Self {
        match value {
            fire_models::LoginStateDetermination::LoggedIn { username, user_id } => {
                Self::LoggedIn { username, user_id }
            }
            fire_models::LoginStateDetermination::NotLoggedIn => Self::NotLoggedIn,
            fire_models::LoginStateDetermination::SessionExpired => Self::SessionExpired,
            fire_models::LoginStateDetermination::NetworkErrorPreserveState => {
                Self::NetworkErrorPreserveState
            }
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum RefreshTriggerState {
    LoginCompleted,
    LogoutCompleted,
    SessionRestored,
    CloudflareResolved,
}

impl From<RefreshTriggerState> for fire_models::RefreshTrigger {
    fn from(value: RefreshTriggerState) -> Self {
        match value {
            RefreshTriggerState::LoginCompleted => Self::LoginCompleted,
            RefreshTriggerState::LogoutCompleted => Self::LogoutCompleted,
            RefreshTriggerState::SessionRestored => Self::SessionRestored,
            RefreshTriggerState::CloudflareResolved => Self::CloudflareResolved,
        }
    }
}

impl From<fire_models::RefreshTrigger> for RefreshTriggerState {
    fn from(value: fire_models::RefreshTrigger) -> Self {
        match value {
            fire_models::RefreshTrigger::LoginCompleted => Self::LoginCompleted,
            fire_models::RefreshTrigger::LogoutCompleted => Self::LogoutCompleted,
            fire_models::RefreshTrigger::SessionRestored => Self::SessionRestored,
            fire_models::RefreshTrigger::CloudflareResolved => Self::CloudflareResolved,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CloudflareClearanceResolvedEventState {
    pub generation: u64,
    pub has_login_session: bool,
    pub can_open_message_bus: bool,
}

impl From<fire_models::CloudflareClearanceResolvedEvent> for CloudflareClearanceResolvedEventState {
    fn from(value: fire_models::CloudflareClearanceResolvedEvent) -> Self {
        Self {
            generation: value.generation,
            has_login_session: value.has_login_session,
            can_open_message_bus: value.can_open_message_bus,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum RefreshBatchState {
    Core,
    Secondary,
}

impl From<RefreshBatch> for RefreshBatchState {
    fn from(value: RefreshBatch) -> Self {
        match value {
            RefreshBatch::Core => Self::Core,
            RefreshBatch::Secondary => Self::Secondary,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct AppStateRefreshEventState {
    pub batch: RefreshBatchState,
    pub trigger: RefreshTriggerState,
}

impl From<AppStateRefreshEvent> for AppStateRefreshEventState {
    fn from(value: AppStateRefreshEvent) -> Self {
        Self {
            batch: value.batch.into(),
            trigger: value.trigger.into(),
        }
    }
}
