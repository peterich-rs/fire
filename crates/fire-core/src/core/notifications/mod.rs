mod fetch;
mod read;
mod runtime;

pub(crate) use runtime::{
    merge_notification_event_data, reconcile_notification_runtime, FireNotificationRuntime,
};

pub(super) const DEFAULT_RECENT_LIMIT: u32 = 30;
pub(super) const DEFAULT_FULL_LIMIT: u32 = 60;
