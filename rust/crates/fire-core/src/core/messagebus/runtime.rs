use std::{
    collections::{BTreeMap, HashMap},
    sync::{atomic::Ordering, Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use fire_models::{
    BootstrapArtifacts, MessageBusClientMode, MessageBusEvent, MessageBusSubscription,
    MessageBusSubscriptionScope, NotificationAlertPollResult,
};
use openwire::WireErrorKind;
use serde_json::Value;
use tokio::{
    runtime::Handle,
    sync::{mpsc::UnboundedSender, watch},
};
use tracing::{debug, info, warn};
use url::Url;

use super::super::{
    network::{request_origin, FireCallProfile},
    presence::clear_topic_presence_snapshot,
    FireCore,
};
use super::channels::*;
use super::poll::*;
use super::*;
use crate::{error::FireCoreError, json_helpers::integer_i64};

impl FireCore {
    pub fn subscribe_message_bus_channel(
        &self,
        subscription: MessageBusSubscription,
    ) -> Result<(), FireCoreError> {
        let snapshot = self.snapshot();
        let mut runtime = self
            .message_bus
            .lock()
            .expect("message bus runtime lock poisoned");
        let mut changed = ensure_bootstrap_subscriptions(&snapshot.bootstrap, &mut runtime);

        let last_message_id = subscription.last_message_id.unwrap_or_else(|| {
            bootstrap_message_id_for_channel(&snapshot.bootstrap, &subscription.channel)
                .unwrap_or(INITIAL_MESSAGE_ID)
        });
        changed |= upsert_runtime_subscription_owner(
            &mut runtime,
            subscription.owner_token,
            subscription.channel,
            last_message_id,
            subscription.scope,
        );

        if changed {
            mark_subscriptions_changed(&mut runtime);
            ensure_poll_task_running(self, &mut runtime)?;
        }
        Ok(())
    }

    pub fn unsubscribe_message_bus_channel(
        &self,
        owner_token: String,
        channel: String,
    ) -> Result<(), FireCoreError> {
        let mut runtime = self
            .message_bus
            .lock()
            .expect("message bus runtime lock poisoned");
        if remove_runtime_subscription_owner(&mut runtime, &owner_token, &channel) {
            let removed_presence_topic_id = presence_topic_id_from_channel(&channel);
            mark_subscriptions_changed(&mut runtime);
            ensure_poll_task_running(self, &mut runtime)?;
            if let Some(topic_id) = removed_presence_topic_id {
                // Keep the message bus lock until the cached snapshot is evicted so a
                // concurrent re-subscribe cannot reintroduce the same topic between steps.
                clear_topic_presence_snapshot(&self.topic_presence, topic_id);
            }
        }
        Ok(())
    }

    pub async fn start_message_bus(
        &self,
        mode: MessageBusClientMode,
        event_sender: UnboundedSender<MessageBusEvent>,
        topic_tracking_state_meta: Option<HashMap<String, i64>>,
    ) -> Result<String, FireCoreError> {
        let snapshot = self.snapshot();
        if !snapshot.cookies.can_authenticate_requests() {
            return Err(FireCoreError::MissingLoginSession);
        }
        if message_bus_requires_shared_session_key(&self.base_url, &snapshot.bootstrap)?
            && snapshot.bootstrap.shared_session_key.is_none()
        {
            return Err(FireCoreError::MissingSharedSessionKey);
        }

        let runtime_handle = Handle::current();
        let mut runtime = self
            .message_bus
            .lock()
            .expect("message bus runtime lock poisoned");
        let mut bootstrap_changed =
            ensure_bootstrap_subscriptions(&snapshot.bootstrap, &mut runtime);
        if let Some(meta) = topic_tracking_state_meta {
            bootstrap_changed |= apply_topic_tracking_state_meta(&meta, &mut runtime);
        }
        if bootstrap_changed {
            mark_subscriptions_changed(&mut runtime);
        }

        stop_poll_task_locked(&mut runtime);
        runtime.active_mode = Some(mode);
        runtime.runtime_handle = Some(runtime_handle);
        runtime.event_sender = Some(event_sender);

        let client_id = client_id_for_mode(&mut runtime, mode);
        runtime.active_client_id = Some(client_id.clone());

        runtime.poll_task = Some(spawn_poll_task(self, &mut runtime, client_id.clone())?);

        info!(
            client_id = %client_id,
            mode = ?mode,
            subscriptions = runtime.subscriptions.len(),
            idle = runtime.subscriptions.is_empty(),
            "message bus started"
        );
        let listeners = runtime.internal_listeners.clone();
        drop(runtime);
        for listener in listeners {
            let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                (listener.on_started)();
            }));
        }
        Ok(client_id)
    }

    pub fn stop_message_bus(&self, clear_subscriptions: bool) {
        let mut runtime = self
            .message_bus
            .lock()
            .expect("message bus runtime lock poisoned");
        stop_poll_task_locked(&mut runtime);
        runtime.active_client_id = None;
        runtime.active_mode = None;
        runtime.event_sender = None;
        runtime.runtime_handle = None;
        if clear_subscriptions {
            runtime.subscriptions.clear();
            runtime.foreground_client_id = None;
        }
        let listeners = runtime.internal_listeners.clone();
        drop(runtime);
        for listener in listeners {
            let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                (listener.on_stopped)();
            }));
        }
    }

    pub(crate) fn add_message_bus_internal_listener(
        &self,
        on_event: std::sync::Arc<dyn Fn(&MessageBusEvent) + Send + Sync>,
        on_stopped: std::sync::Arc<dyn Fn() + Send + Sync>,
        on_started: std::sync::Arc<dyn Fn() + Send + Sync>,
    ) -> u64 {
        let mut runtime = self
            .message_bus
            .lock()
            .expect("message bus runtime lock poisoned");
        runtime.next_internal_listener_id =
            runtime.next_internal_listener_id.saturating_add(1).max(1);
        let id = runtime.next_internal_listener_id;
        runtime.internal_listeners.push(MessageBusInternalListener {
            id,
            on_event,
            on_stopped,
            on_started,
        });
        id
    }

    pub(crate) fn remove_message_bus_internal_listener(&self, id: u64) {
        let mut runtime = self
            .message_bus
            .lock()
            .expect("message bus runtime lock poisoned");
        runtime
            .internal_listeners
            .retain(|listener| listener.id != id);
    }

    pub async fn poll_notification_alert_once(
        &self,
        last_message_id: i64,
    ) -> Result<NotificationAlertPollResult, FireCoreError> {
        let snapshot = self.snapshot();
        if !snapshot.cookies.can_authenticate_requests() {
            return Err(FireCoreError::MissingLoginSession);
        }
        if message_bus_requires_shared_session_key(&self.base_url, &snapshot.bootstrap)?
            && snapshot.bootstrap.shared_session_key.is_none()
        {
            return Err(FireCoreError::MissingSharedSessionKey);
        }

        let notification_user_id = snapshot
            .bootstrap
            .current_user_id
            .ok_or(FireCoreError::MissingCurrentUserId)?;
        let channel = format!("/notification-alert/{notification_user_id}");
        let client_id = generate_ios_background_client_id();
        let traced = build_message_bus_poll_request_for_snapshot(
            &self.diagnostics,
            &self.base_url,
            &snapshot,
            self.snapshot_with_epoch().1,
            &client_id,
            MessageBusClientMode::IosBackground,
            &[(channel.clone(), last_message_id)],
        )?;
        debug!(
            trace_id = traced.trace_id,
            client_id = %client_id,
            channel = %channel,
            last_message_id,
            "executing background notification-alert poll request"
        );
        let (trace_id, response) = self
            .network
            .execute_traced(traced, FireCallProfile::MessageBusPoll)
            .await?;

        if !response.status().is_success() {
            match read_message_bus_error_response_for_diagnostics(
                &self.diagnostics,
                trace_id,
                response,
            )
            .await
            {
                Err(error) => return Err(error),
                Ok(_) => unreachable!("message bus error response should not succeed"),
            }
        }

        read_notification_alert_success_response(
            &self.diagnostics,
            trace_id,
            response,
            notification_user_id,
            &client_id,
            &channel,
            last_message_id,
        )
        .await
    }
}

fn ensure_bootstrap_subscriptions(
    bootstrap: &BootstrapArtifacts,
    runtime: &mut FireMessageBusRuntime,
) -> bool {
    let mut changed = false;

    for (channel, last_message_id) in bootstrap_tracking_subscriptions(bootstrap) {
        changed |= upsert_runtime_subscription_owner(
            runtime,
            BOOTSTRAP_TRACKING_OWNER_TOKEN.to_string(),
            channel,
            last_message_id,
            MessageBusSubscriptionScope::Durable,
        );
    }

    if let (Some(user_id), Some(last_message_id)) = (
        bootstrap.current_user_id,
        bootstrap.notification_channel_position,
    ) {
        changed |= upsert_runtime_subscription_owner(
            runtime,
            BOOTSTRAP_NOTIFICATION_OWNER_TOKEN.to_string(),
            format!("/notification/{user_id}"),
            last_message_id,
            MessageBusSubscriptionScope::Durable,
        );
    }

    if let Some(user_id) = bootstrap.current_user_id.filter(|id| *id > 0) {
        let channel = format!("/logout/{user_id}");
        let last_message_id =
            bootstrap_message_id_for_channel(bootstrap, &channel).unwrap_or(INITIAL_MESSAGE_ID);
        changed |= upsert_runtime_subscription_owner(
            runtime,
            BOOTSTRAP_LOGOUT_OWNER_TOKEN.to_string(),
            channel,
            last_message_id,
            MessageBusSubscriptionScope::Durable,
        );
    }

    changed
}

pub(super) fn bootstrap_tracking_subscriptions(
    bootstrap: &BootstrapArtifacts,
) -> Vec<(String, i64)> {
    let Some(raw) = bootstrap.topic_tracking_state_meta.as_deref() else {
        return Vec::new();
    };
    let Ok(value) = serde_json::from_str::<Value>(raw) else {
        return Vec::new();
    };
    let Some(object) = value.as_object() else {
        return Vec::new();
    };

    object
        .iter()
        .filter_map(|(channel, value)| {
            if !channel.starts_with('/') {
                return None;
            }
            integer_i64(Some(value)).map(|last_message_id| (channel.clone(), last_message_id))
        })
        .collect()
}

pub(super) fn apply_topic_tracking_state_meta(
    meta: &HashMap<String, i64>,
    runtime: &mut FireMessageBusRuntime,
) -> bool {
    let mut changed = false;
    for (channel, last_message_id) in meta {
        if !channel.starts_with('/') {
            continue;
        }
        changed |= upsert_runtime_subscription_owner(
            runtime,
            BOOTSTRAP_TRACKING_OWNER_TOKEN.to_string(),
            channel.clone(),
            *last_message_id,
            MessageBusSubscriptionScope::Durable,
        );
    }
    changed
}

pub(super) fn bootstrap_message_id_for_channel(
    bootstrap: &BootstrapArtifacts,
    channel: &str,
) -> Option<i64> {
    if let Some(notification_channel) = bootstrap_notification_channel(bootstrap) {
        if notification_channel.0 == channel {
            return Some(notification_channel.1);
        }
    }

    bootstrap_tracking_subscriptions(bootstrap)
        .into_iter()
        .find_map(|(known_channel, last_message_id)| {
            (known_channel == channel).then_some(last_message_id)
        })
}

pub(super) fn bootstrap_notification_channel(
    bootstrap: &BootstrapArtifacts,
) -> Option<(String, i64)> {
    Some((
        format!("/notification/{}", bootstrap.current_user_id?),
        bootstrap.notification_channel_position?,
    ))
}

pub(super) fn client_id_for_mode(
    runtime: &mut FireMessageBusRuntime,
    mode: MessageBusClientMode,
) -> String {
    match mode {
        MessageBusClientMode::Foreground => runtime
            .foreground_client_id
            .get_or_insert_with(generate_foreground_client_id)
            .clone(),
        MessageBusClientMode::IosBackground => generate_ios_background_client_id(),
    }
}

pub(super) fn generate_foreground_client_id() -> String {
    let counter = FOREGROUND_CLIENT_COUNTER.fetch_add(1, Ordering::SeqCst);
    format!("fire_{:x}{:x}", now_unix_ms(), counter)
}

pub(super) fn generate_ios_background_client_id() -> String {
    format!("ios_bg_{}", now_unix_ms())
}

pub(super) fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

pub(super) fn backoff_delay(failure_count: u32) -> Duration {
    let exponent = failure_count.saturating_sub(1).min(4);
    let seconds = 2_u64.saturating_pow(exponent);
    let base_delay = Duration::from_secs(seconds).min(MAX_BACKOFF_DELAY);
    let base_delay_ms = base_delay.as_millis() as u64;
    let jitter_window_ms = base_delay_ms / 4;
    if jitter_window_ms == 0 {
        return base_delay;
    }

    let jitter_seed = now_unix_ms()
        ^ u64::from(failure_count)
        ^ FOREGROUND_CLIENT_COUNTER.load(Ordering::Relaxed);
    let jitter_ms = jitter_seed % (jitter_window_ms.saturating_mul(2) + 1);
    let delay_ms = base_delay_ms
        .saturating_sub(jitter_window_ms)
        .saturating_add(jitter_ms);
    Duration::from_millis(delay_ms).min(MAX_BACKOFF_DELAY)
}

pub(super) fn upsert_runtime_subscription_owner(
    runtime: &mut FireMessageBusRuntime,
    owner_token: String,
    channel: String,
    last_message_id: i64,
    scope: MessageBusSubscriptionScope,
) -> bool {
    let owner_key = owner_token;
    let mut is_new_channel = false;
    let entry = runtime.subscriptions.entry(channel).or_insert_with(|| {
        is_new_channel = true;
        RuntimeSubscription {
            last_message_id,
            owners: BTreeMap::new(),
        }
    });
    let previous_last_message_id = entry.last_message_id;
    entry.last_message_id = entry.last_message_id.max(last_message_id);
    entry
        .owners
        .insert(owner_key.clone(), RuntimeSubscriptionOwner { scope });
    is_new_channel || entry.last_message_id != previous_last_message_id
}

pub(super) fn remove_runtime_subscription_owner(
    runtime: &mut FireMessageBusRuntime,
    owner_token: &str,
    channel: &str,
) -> bool {
    let Some(entry) = runtime.subscriptions.get_mut(channel) else {
        return false;
    };

    let removed = entry.owners.remove(owner_token).is_some();
    if !removed {
        return false;
    }

    if entry.owners.is_empty() {
        runtime.subscriptions.remove(channel);
        return true;
    }

    false
}

pub(super) fn mark_subscriptions_changed(runtime: &mut FireMessageBusRuntime) {
    runtime.subscription_revision = runtime.subscription_revision.saturating_add(1);
    if let Some(sender) = &runtime.subscription_updates {
        let _ = sender.send(runtime.subscription_revision);
    }
}

pub(super) fn subscription_updates_receiver(
    runtime: &mut FireMessageBusRuntime,
) -> watch::Receiver<u64> {
    if let Some(sender) = &runtime.subscription_updates {
        sender.subscribe()
    } else {
        let (sender, receiver) = watch::channel(runtime.subscription_revision);
        runtime.subscription_updates = Some(sender);
        receiver
    }
}

pub(super) fn is_expected_long_poll_timeout(error: &FireCoreError) -> bool {
    matches!(
        error,
        FireCoreError::Network { source }
            if source.kind() == WireErrorKind::Timeout && !source.is_connect_timeout()
    )
}

pub(super) fn log_message_bus_poll_failure(client_id: &str, error: &FireCoreError) {
    match error {
        FireCoreError::HttpStatus { status, .. } if matches!(status, 429 | 502 | 503 | 504) => {
            let category = match status {
                429 => "rate_limited",
                _ => "server_unavailable",
            };
            warn!(
                client_id = %client_id,
                status = *status,
                category,
                error = %error,
                "message bus poll iteration failed"
            );
        }
        _ => {
            warn!(
                client_id = %client_id,
                error = %error,
                "message bus poll iteration failed"
            );
        }
    }
}

pub(super) fn clear_poll_task_on_exit(
    runtime: &Arc<Mutex<FireMessageBusRuntime>>,
    client_id: &str,
    task_token: u64,
) {
    let mut runtime = runtime.lock().expect("message bus runtime lock poisoned");
    if runtime.active_client_id.as_deref() == Some(client_id)
        && runtime.poll_task_token == task_token
    {
        runtime.poll_task = None;
    }
}

pub(super) fn message_bus_poll_base_url(
    base_url: &Url,
    bootstrap: &BootstrapArtifacts,
) -> Result<Url, FireCoreError> {
    match bootstrap.long_polling_base_url.as_deref() {
        Some(long_polling_base_url) if !long_polling_base_url.is_empty() => {
            Url::parse(long_polling_base_url).map_err(Into::into)
        }
        _ => Ok(base_url.clone()),
    }
}

pub(crate) fn message_bus_requires_shared_session_key(
    base_url: &Url,
    bootstrap: &BootstrapArtifacts,
) -> Result<bool, FireCoreError> {
    let poll_base_url = message_bus_poll_base_url(base_url, bootstrap)?;
    Ok(request_origin(base_url) != request_origin(&poll_base_url))
}
