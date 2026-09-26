use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

use fire_models::{
    NotificationCounters, NotificationItem, NotificationListResponse, NotificationState,
    SessionSnapshot,
};
use serde_json::Value;

use super::super::FireCore;
use super::DEFAULT_RECENT_LIMIT;
use crate::{
    error::FireCoreError,
    json_helpers::{boolean, integer_u32, integer_u64},
    notification_payloads::parse_notification_item_value,
    parsing::parse_preloaded_payload,
};

#[derive(Default)]
pub(crate) struct FireNotificationRuntime {
    user_id: Option<u64>,
    counters: Option<NotificationCounters>,
    recent: Vec<NotificationItem>,
    has_loaded_recent: bool,
    recent_is_cached: bool,
    recent_seen_notification_id: Option<u64>,
    full: Vec<NotificationItem>,
    has_loaded_full: bool,
    full_is_cached: bool,
    total_rows_notifications: u32,
    full_seen_notification_id: Option<u64>,
    full_load_more_notifications: Option<String>,
    full_next_offset: Option<u32>,
    live_badge_epoch: bool,
}

impl FireCore {
    pub fn notification_state(&self) -> NotificationState {
        let snapshot = self.snapshot();
        let runtime = self
            .notifications
            .lock()
            .expect("notification runtime lock poisoned");

        NotificationState {
            counters: runtime
                .counters
                .clone()
                .unwrap_or_else(|| notification_counters_from_snapshot(&snapshot)),
            recent: runtime.recent.clone(),
            has_loaded_recent: runtime.has_loaded_recent,
            recent_is_cached: runtime.recent_is_cached,
            recent_seen_notification_id: runtime.recent_seen_notification_id,
            full: runtime.full.clone(),
            has_loaded_full: runtime.has_loaded_full,
            full_is_cached: runtime.full_is_cached,
            total_rows_notifications: runtime.total_rows_notifications,
            full_seen_notification_id: runtime.full_seen_notification_id,
            full_load_more_notifications: runtime.full_load_more_notifications.clone(),
            full_next_offset: runtime.full_next_offset,
        }
    }

    pub fn clear_notification_state(&self) {
        let mut runtime = self
            .notifications
            .lock()
            .expect("notification runtime lock poisoned");
        *runtime = FireNotificationRuntime::default();
    }
}

pub(crate) fn merge_notification_event_data(
    runtime: &Arc<Mutex<FireNotificationRuntime>>,
    data: &Value,
) {
    let Some(object) = data.as_object() else {
        return;
    };

    let mut runtime = runtime.lock().expect("notification runtime lock poisoned");

    merge_notification_counters(
        &mut runtime,
        object
            .get("all_unread_notifications_count")
            .and_then(|value| integer_u32(Some(value))),
        object
            .get("unread_notifications")
            .and_then(|value| integer_u32(Some(value))),
        object
            .get("unread_high_priority_notifications")
            .and_then(|value| integer_u32(Some(value))),
    );

    let last_notification_value = object
        .get("last_notification")
        .and_then(|value| value.get("notification"))
        .cloned()
        .or_else(|| object.get("notification").cloned());
    if let Some(last_notification_value) = last_notification_value {
        if let Ok(notification) = parse_notification_item_value(last_notification_value) {
            merge_live_notification(&mut runtime, notification);
        }
    }

    let read_updates = object
        .get("recent")
        .and_then(Value::as_array)
        .map(|entries| notification_read_updates(entries))
        .unwrap_or_default();
    if !read_updates.is_empty() {
        apply_read_updates(&mut runtime, &read_updates);
    }
}

pub(crate) fn reconcile_notification_runtime(
    runtime: &Arc<Mutex<FireNotificationRuntime>>,
    snapshot: &SessionSnapshot,
) {
    let user_id = snapshot.bootstrap.current_user_id;
    if !snapshot.cookies.can_authenticate_requests() || user_id.is_none() {
        let mut runtime = runtime.lock().expect("notification runtime lock poisoned");
        *runtime = FireNotificationRuntime::default();
        return;
    }

    let mut runtime = runtime.lock().expect("notification runtime lock poisoned");
    if runtime.user_id != user_id {
        *runtime = FireNotificationRuntime {
            user_id,
            counters: Some(notification_counters_from_snapshot(snapshot)),
            ..FireNotificationRuntime::default()
        };
        return;
    }
    if runtime.live_badge_epoch {
        return;
    }
    if runtime.counters.is_none() {
        runtime.counters = Some(notification_counters_from_snapshot(snapshot));
    }
}

pub(super) fn ensure_notification_session(core: &FireCore) -> Result<(), FireCoreError> {
    if core.snapshot().cookies.can_authenticate_requests() {
        Ok(())
    } else {
        Err(FireCoreError::MissingLoginSession)
    }
}

pub(super) fn normalized_limit(limit: Option<u32>, default_value: u32) -> u32 {
    limit
        .filter(|value| *value > 0)
        .map(|value| value.min(default_value))
        .unwrap_or(default_value)
}

pub(super) fn notification_cache_scope_key(kind: &str, limit: u32, offset: Option<u32>) -> String {
    format!("{kind}|limit={limit}|offset={}", offset.unwrap_or(0))
}

pub(super) fn apply_recent_page(
    runtime: &mut FireNotificationRuntime,
    page: &NotificationListResponse,
) {
    runtime.recent = page.notifications.clone();
    runtime.has_loaded_recent = true;
    runtime.recent_is_cached = page.is_cached;
    runtime.recent_seen_notification_id = page.seen_notification_id;

    if runtime.has_loaded_full {
        for notification in page.notifications.iter().rev() {
            upsert_notification(&mut runtime.full, notification.clone(), true);
        }
        sync_read_status_between_lists(&mut runtime.recent, &runtime.full);
        sync_read_status_between_lists(&mut runtime.full, &runtime.recent);
    }
}

pub(super) fn apply_full_page(
    runtime: &mut FireNotificationRuntime,
    page: &NotificationListResponse,
    offset: u32,
) {
    if offset == 0 || !runtime.has_loaded_full {
        runtime.full = page.notifications.clone();
    } else {
        for notification in &page.notifications {
            upsert_notification(&mut runtime.full, notification.clone(), false);
        }
    }
    runtime.has_loaded_full = true;
    runtime.full_is_cached = page.is_cached;
    runtime.total_rows_notifications = page.total_rows_notifications;
    runtime.full_seen_notification_id = page.seen_notification_id;
    runtime.full_load_more_notifications = page.load_more_notifications.clone();
    runtime.full_next_offset = page.next_offset;

    if runtime.has_loaded_recent {
        sync_read_status_between_lists(&mut runtime.recent, &runtime.full);
    }
}

fn merge_live_notification(runtime: &mut FireNotificationRuntime, notification: NotificationItem) {
    if runtime.has_loaded_recent {
        runtime.recent_is_cached = false;
        insert_recent_notification(&mut runtime.recent, notification.clone());
    }
    if runtime.has_loaded_full {
        runtime.full_is_cached = false;
        upsert_notification(&mut runtime.full, notification, true);
    }
}

fn insert_recent_notification(list: &mut Vec<NotificationItem>, notification: NotificationItem) {
    if let Some(index) = list.iter().position(|item| item.id == notification.id) {
        list[index] = notification;
        trim_recent_notifications(list);
        return;
    }

    let insert_index = if notification.high_priority && !notification.read {
        0
    } else {
        list.iter()
            .position(|item| !item.high_priority || item.read)
            .unwrap_or(list.len())
    };
    list.insert(insert_index, notification);
    trim_recent_notifications(list);
}

fn trim_recent_notifications(list: &mut Vec<NotificationItem>) {
    list.truncate(DEFAULT_RECENT_LIMIT as usize);
}

fn upsert_notification(
    list: &mut Vec<NotificationItem>,
    notification: NotificationItem,
    insert_front: bool,
) {
    if let Some(index) = list.iter().position(|item| item.id == notification.id) {
        list[index] = notification;
        return;
    }

    if insert_front {
        list.insert(0, notification);
    } else {
        list.push(notification);
    }
}

fn sync_read_status_between_lists(target: &mut [NotificationItem], source: &[NotificationItem]) {
    if source.is_empty() {
        return;
    }

    let read_by_id = source
        .iter()
        .map(|notification| (notification.id, notification.read))
        .collect::<BTreeMap<_, _>>();
    for notification in target {
        if let Some(read) = read_by_id.get(&notification.id) {
            notification.read = *read;
        }
    }
}

fn notification_read_updates(entries: &[Value]) -> BTreeMap<u64, bool> {
    entries
        .iter()
        .filter_map(|entry| {
            let Value::Array(entry) = entry else {
                return None;
            };
            let notification_id = entry.first().and_then(|value| integer_u64(Some(value)))?;
            let read = entry.get(1).map(|value| boolean(Some(value)))?;
            Some((notification_id, read))
        })
        .collect()
}

fn apply_read_updates(runtime: &mut FireNotificationRuntime, read_updates: &BTreeMap<u64, bool>) {
    for notification in &mut runtime.recent {
        if let Some(read) = read_updates.get(&notification.id) {
            notification.read = *read;
        }
    }
    for notification in &mut runtime.full {
        if let Some(read) = read_updates.get(&notification.id) {
            notification.read = *read;
        }
    }
}

fn merge_notification_counters(
    runtime: &mut FireNotificationRuntime,
    all_unread: Option<u32>,
    unread: Option<u32>,
    high_priority: Option<u32>,
) {
    if all_unread.is_none() && unread.is_none() && high_priority.is_none() {
        return;
    }

    runtime.live_badge_epoch = true;
    let counters = runtime
        .counters
        .get_or_insert_with(NotificationCounters::default);
    if let Some(all_unread) = all_unread {
        counters.all_unread = all_unread;
    }
    if let Some(unread) = unread {
        counters.unread = unread;
    }
    if let Some(high_priority) = high_priority {
        counters.high_priority = high_priority;
    }
}

pub(super) fn mark_notification_read_locked(
    runtime: &mut FireNotificationRuntime,
    notification_id: u64,
) {
    let Some((was_unread, was_high_priority)) = notification_state_for_id(runtime, notification_id)
    else {
        return;
    };

    for notification in &mut runtime.recent {
        if notification.id == notification_id {
            notification.read = true;
        }
    }
    for notification in &mut runtime.full {
        if notification.id == notification_id {
            notification.read = true;
        }
    }

    let counters = runtime
        .counters
        .get_or_insert_with(NotificationCounters::default);
    if was_unread {
        counters.all_unread = counters.all_unread.saturating_sub(1);
        counters.unread = counters.unread.saturating_sub(1);
    }
    if was_unread && was_high_priority {
        counters.high_priority = counters.high_priority.saturating_sub(1);
    }
}

pub(super) fn mark_all_notifications_read_locked(runtime: &mut FireNotificationRuntime) {
    for notification in &mut runtime.recent {
        notification.read = true;
    }
    for notification in &mut runtime.full {
        notification.read = true;
    }
    runtime.counters = Some(NotificationCounters::default());
}

fn notification_state_for_id(
    runtime: &FireNotificationRuntime,
    notification_id: u64,
) -> Option<(bool, bool)> {
    runtime
        .recent
        .iter()
        .chain(runtime.full.iter())
        .find(|notification| notification.id == notification_id)
        .map(|notification| (!notification.read, notification.high_priority))
}

fn notification_counters_from_snapshot(snapshot: &SessionSnapshot) -> NotificationCounters {
    let Some(preloaded_json) = snapshot.bootstrap.preloaded_json.as_deref() else {
        return NotificationCounters::default();
    };
    let Some(value) = parse_preloaded_payload(preloaded_json) else {
        return NotificationCounters::default();
    };
    let Some(current_user) = value.get("currentUser") else {
        return NotificationCounters::default();
    };

    NotificationCounters {
        all_unread: current_user
            .get("all_unread_notifications_count")
            .and_then(|value| integer_u32(Some(value)))
            .unwrap_or_default(),
        unread: current_user
            .get("unread_notifications")
            .and_then(|value| integer_u32(Some(value)))
            .unwrap_or_default(),
        high_priority: current_user
            .get("unread_high_priority_notifications")
            .and_then(|value| integer_u32(Some(value)))
            .unwrap_or_default(),
    }
}

pub(super) fn seed_notification_counters_if_missing(
    runtime: &mut FireNotificationRuntime,
    snapshot: &SessionSnapshot,
) {
    if runtime.live_badge_epoch {
        return;
    }
    if runtime.counters.is_none() {
        runtime.counters = Some(notification_counters_from_snapshot(snapshot));
    }
}
