use std::{
    collections::BTreeMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex, RwLock,
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use fire_models::{
    BootstrapArtifacts, MessageBusClientMode, MessageBusEvent, MessageBusEventKind,
    MessageBusSubscription, MessageBusSubscriptionScope, NotificationAlert,
    NotificationAlertPollResult, SessionSnapshot, TopicListKind,
};
use http::{Method, Request, Response};
use http_body_util::BodyExt;
use openwire::{RequestBody, ResponseBody};
use serde::Deserialize;
use serde_json::Value;
use tokio::{runtime::Handle, sync::mpsc::UnboundedSender, task::JoinHandle, time::sleep};
use tracing::{debug, info, warn};
use url::{form_urlencoded::Serializer, Url};

use super::{
    network::{
        classify_http_status_error, header_value, request_origin, FireCallProfile,
        FireNetworkLayer, FireRequestProfile, TracedRequest,
    },
    notifications::{merge_notification_event_data, FireNotificationRuntime},
    presence::{merge_topic_presence_event_data, FireTopicPresenceRuntime},
    FireCore,
};
use crate::{
    diagnostics::FireDiagnosticsStore,
    error::FireCoreError,
    json_helpers::{boolean, integer_i64, integer_u32, positive_u64},
    sync_utils::read_rwlock,
};

const MESSAGE_BUS_OPERATION: &str = "message bus poll";
const INITIAL_MESSAGE_ID: i64 = -1;
const MAX_BACKOFF_DELAY: Duration = Duration::from_secs(30);

static FOREGROUND_CLIENT_COUNTER: AtomicU64 = AtomicU64::new(1);

#[derive(Default)]
pub(crate) struct FireMessageBusRuntime {
    foreground_client_id: Option<String>,
    active_client_id: Option<String>,
    active_mode: Option<MessageBusClientMode>,
    runtime_handle: Option<Handle>,
    event_sender: Option<UnboundedSender<MessageBusEvent>>,
    subscriptions: BTreeMap<String, RuntimeSubscription>,
    poll_task: Option<JoinHandle<()>>,
}

#[derive(Debug, Clone)]
struct RuntimeSubscription {
    last_message_id: i64,
    scope: MessageBusSubscriptionScope,
}

#[derive(Clone)]
struct MessageBusPollContext {
    base_url: Url,
    network: FireNetworkLayer,
    diagnostics: Arc<FireDiagnosticsStore>,
    session: Arc<RwLock<SessionSnapshot>>,
    runtime: Arc<Mutex<FireMessageBusRuntime>>,
    notifications: Arc<Mutex<FireNotificationRuntime>>,
    topic_presence: Arc<Mutex<FireTopicPresenceRuntime>>,
    event_sender: UnboundedSender<MessageBusEvent>,
    client_id: String,
}

#[derive(Debug, Deserialize)]
struct RawMessageBusMessage {
    channel: String,
    message_id: i64,
    #[serde(default)]
    data: Value,
}

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
        ensure_bootstrap_subscriptions(&snapshot.bootstrap, &mut runtime);

        let last_message_id = subscription.last_message_id.unwrap_or_else(|| {
            bootstrap_message_id_for_channel(&snapshot.bootstrap, &subscription.channel)
                .unwrap_or(INITIAL_MESSAGE_ID)
        });
        let entry = runtime
            .subscriptions
            .entry(subscription.channel)
            .or_insert_with(|| RuntimeSubscription {
                last_message_id,
                scope: subscription.scope,
            });
        entry.last_message_id = entry.last_message_id.max(last_message_id);
        entry.scope = merge_subscription_scopes(entry.scope, subscription.scope);

        restart_poll_task(self, &mut runtime)?;
        Ok(())
    }

    pub fn unsubscribe_message_bus_channel(&self, channel: String) -> Result<(), FireCoreError> {
        let mut runtime = self
            .message_bus
            .lock()
            .expect("message bus runtime lock poisoned");
        runtime.subscriptions.remove(&channel);
        restart_poll_task(self, &mut runtime)?;
        Ok(())
    }

    pub async fn start_message_bus(
        &self,
        mode: MessageBusClientMode,
        event_sender: UnboundedSender<MessageBusEvent>,
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
        ensure_bootstrap_subscriptions(&snapshot.bootstrap, &mut runtime);

        stop_poll_task_locked(&mut runtime);
        runtime.active_mode = Some(mode);
        runtime.runtime_handle = Some(runtime_handle);
        runtime.event_sender = Some(event_sender);

        let client_id = client_id_for_mode(&mut runtime, mode);
        runtime.active_client_id = Some(client_id.clone());

        if runtime.subscriptions.is_empty() {
            info!(
                client_id = %client_id,
                mode = ?mode,
                subscriptions = 0,
                "message bus started idle without subscriptions"
            );
            return Ok(client_id);
        }

        runtime.poll_task = Some(spawn_poll_task(self, &runtime, client_id.clone())?);

        info!(
            client_id = %client_id,
            mode = ?mode,
            subscriptions = runtime.subscriptions.len(),
            "message bus started"
        );
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
            &client_id,
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

fn restart_poll_task(
    core: &FireCore,
    runtime: &mut FireMessageBusRuntime,
) -> Result<(), FireCoreError> {
    if runtime.active_mode.is_none() {
        return Ok(());
    }
    if runtime.subscriptions.is_empty() {
        stop_poll_task_locked(runtime);
        runtime.active_client_id = None;
        return Ok(());
    }

    stop_poll_task_locked(runtime);
    let client_id = runtime
        .active_mode
        .map(|mode| client_id_for_mode(runtime, mode))
        .expect("message bus active mode should exist");
    runtime.active_client_id = Some(client_id.clone());
    runtime.poll_task = Some(spawn_poll_task(core, runtime, client_id)?);
    Ok(())
}

fn stop_poll_task_locked(runtime: &mut FireMessageBusRuntime) {
    if let Some(task) = runtime.poll_task.take() {
        task.abort();
    }
}

fn spawn_poll_task(
    core: &FireCore,
    runtime: &FireMessageBusRuntime,
    client_id: String,
) -> Result<JoinHandle<()>, FireCoreError> {
    let runtime_handle = runtime
        .runtime_handle
        .clone()
        .ok_or(FireCoreError::MessageBusNotStarted)?;
    let event_sender = runtime
        .event_sender
        .clone()
        .ok_or(FireCoreError::MessageBusNotStarted)?;
    let context = MessageBusPollContext {
        base_url: core.base_url.clone(),
        network: core.network.clone(),
        diagnostics: Arc::clone(&core.diagnostics),
        session: Arc::clone(&core.session),
        runtime: Arc::clone(&core.message_bus),
        notifications: Arc::clone(&core.notifications),
        topic_presence: Arc::clone(&core.topic_presence),
        event_sender,
        client_id,
    };
    Ok(runtime_handle.spawn(async move {
        run_message_bus_poll_loop(context).await;
    }))
}

async fn run_message_bus_poll_loop(context: MessageBusPollContext) {
    let mut failure_count = 0_u32;

    loop {
        let subscriptions = {
            let runtime = context
                .runtime
                .lock()
                .expect("message bus runtime lock poisoned");
            if runtime.active_client_id.as_deref() != Some(context.client_id.as_str()) {
                return;
            }
            if runtime.subscriptions.is_empty() {
                return;
            }
            runtime
                .subscriptions
                .iter()
                .map(|(channel, entry)| (channel.clone(), entry.last_message_id))
                .collect::<Vec<_>>()
        };

        match execute_poll_once(&context, &subscriptions).await {
            Ok(keep_running) => {
                failure_count = 0;
                if !keep_running {
                    return;
                }
            }
            Err(error) => {
                warn!(
                    client_id = %context.client_id,
                    error = %error,
                    "message bus poll iteration failed"
                );
                failure_count = failure_count.saturating_add(1);
                let delay = backoff_delay(failure_count);
                sleep(delay).await;
            }
        }
    }
}

async fn execute_poll_once(
    context: &MessageBusPollContext,
    subscriptions: &[(String, i64)],
) -> Result<bool, FireCoreError> {
    let traced = build_message_bus_poll_request(context, subscriptions)?;
    debug!(
        trace_id = traced.trace_id,
        client_id = %context.client_id,
        subscriptions = subscriptions.len(),
        "executing message bus poll request"
    );
    let (trace_id, response) = context
        .network
        .execute_traced(traced, FireCallProfile::MessageBusPoll)
        .await?;

    if !response.status().is_success() {
        return read_message_bus_error_response(context, trace_id, response).await;
    }

    read_message_bus_success_response(context, trace_id, response).await
}

fn build_message_bus_poll_request(
    context: &MessageBusPollContext,
    subscriptions: &[(String, i64)],
) -> Result<TracedRequest, FireCoreError> {
    let snapshot = read_rwlock(&context.session, "session").clone();
    build_message_bus_poll_request_for_snapshot(
        &context.diagnostics,
        &context.base_url,
        &snapshot,
        &context.client_id,
        subscriptions,
    )
}

fn build_message_bus_poll_request_for_snapshot(
    diagnostics: &Arc<FireDiagnosticsStore>,
    base_url: &Url,
    snapshot: &SessionSnapshot,
    client_id: &str,
    subscriptions: &[(String, i64)],
) -> Result<TracedRequest, FireCoreError> {
    let poll_base_url = message_bus_poll_base_url(base_url, &snapshot.bootstrap)?;
    let uri = poll_base_url.join(&format!("/message-bus/{client_id}/poll"))?;
    let same_origin = request_origin(base_url) == request_origin(&poll_base_url);

    let mut serializer = Serializer::new(String::new());
    for (channel, last_message_id) in subscriptions {
        serializer.append_pair(channel, &last_message_id.to_string());
    }

    let mut builder = Request::builder()
        .method(Method::POST)
        .uri(uri.as_str())
        .header("Accept", "application/json")
        .header(
            "Content-Type",
            "application/x-www-form-urlencoded; charset=utf-8",
        )
        .header("X-SILENCE-LOGGER", "true")
        .header("Discourse-Background", "true");

    if !same_origin {
        let shared_session_key = snapshot
            .bootstrap
            .shared_session_key
            .as_ref()
            .ok_or(FireCoreError::MissingSharedSessionKey)?;
        builder = builder.header("X-Shared-Session-Key", shared_session_key);
    }

    let mut request = builder
        .body(RequestBody::from(serializer.finish()))
        .map_err(FireCoreError::RequestBuild)?;
    request
        .extensions_mut()
        .insert(FireRequestProfile::MessageBusPoll);
    let trace_id = diagnostics.prepare_request_trace(MESSAGE_BUS_OPERATION, &mut request);
    Ok(TracedRequest { trace_id, request })
}

async fn read_message_bus_error_response(
    context: &MessageBusPollContext,
    trace_id: u64,
    response: Response<ResponseBody>,
) -> Result<bool, FireCoreError> {
    read_message_bus_error_response_for_diagnostics(&context.diagnostics, trace_id, response).await
}

async fn read_message_bus_error_response_for_diagnostics(
    diagnostics: &Arc<FireDiagnosticsStore>,
    trace_id: u64,
    response: Response<ResponseBody>,
) -> Result<bool, FireCoreError> {
    let status = response.status().as_u16();
    let body = response.into_body().text().await.map_err(|source| {
        diagnostics.record_call_failed(trace_id, &source);
        FireCoreError::Network { source }
    })?;
    diagnostics.record_http_status_error(trace_id, status, &body);
    Err(classify_http_status_error(
        MESSAGE_BUS_OPERATION,
        status,
        body,
    ))
}

async fn read_message_bus_success_response(
    context: &MessageBusPollContext,
    trace_id: u64,
    response: Response<ResponseBody>,
) -> Result<bool, FireCoreError> {
    let content_type = header_value(response.headers(), "content-type");
    let mut body = response.into_body();
    let mut response_text = String::new();
    let mut chunk_buffer = String::new();

    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|source| {
            context.diagnostics.record_call_failed(trace_id, &source);
            FireCoreError::Network { source }
        })?;
        let Ok(bytes) = frame.into_data() else {
            continue;
        };
        let text = String::from_utf8_lossy(&bytes);
        response_text.push_str(&text);
        chunk_buffer.push_str(&text);

        while let Some(delimiter) = chunk_buffer.find('|') {
            let chunk = chunk_buffer[..delimiter].trim().to_string();
            chunk_buffer = chunk_buffer[delimiter + 1..].to_string();
            if !chunk.is_empty() && !process_chunk(context, &chunk)? {
                context.diagnostics.record_response_body_text(
                    trace_id,
                    &response_text,
                    content_type.as_deref(),
                );
                return Ok(false);
            }
        }
    }

    if !chunk_buffer.trim().is_empty() && !process_chunk(context, chunk_buffer.trim())? {
        context.diagnostics.record_response_body_text(
            trace_id,
            &response_text,
            content_type.as_deref(),
        );
        return Ok(false);
    }

    context.diagnostics.record_response_body_text(
        trace_id,
        &response_text,
        content_type.as_deref(),
    );
    Ok(true)
}

async fn read_notification_alert_success_response(
    diagnostics: &Arc<FireDiagnosticsStore>,
    trace_id: u64,
    response: Response<ResponseBody>,
    notification_user_id: u64,
    client_id: &str,
    channel: &str,
    initial_last_message_id: i64,
) -> Result<NotificationAlertPollResult, FireCoreError> {
    let content_type = header_value(response.headers(), "content-type");
    let mut body = response.into_body();
    let mut response_text = String::new();
    let mut chunk_buffer = String::new();
    let mut result = NotificationAlertPollResult {
        notification_user_id,
        client_id: client_id.to_string(),
        last_message_id: initial_last_message_id,
        alerts: Vec::new(),
    };

    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|source| {
            diagnostics.record_call_failed(trace_id, &source);
            FireCoreError::Network { source }
        })?;
        let Ok(bytes) = frame.into_data() else {
            continue;
        };
        let text = String::from_utf8_lossy(&bytes);
        response_text.push_str(&text);
        chunk_buffer.push_str(&text);

        while let Some(delimiter) = chunk_buffer.find('|') {
            let chunk = chunk_buffer[..delimiter].trim().to_string();
            chunk_buffer = chunk_buffer[delimiter + 1..].to_string();
            if !chunk.is_empty() {
                process_notification_alert_chunk(&mut result, channel, client_id, &chunk);
            }
        }
    }

    if !chunk_buffer.trim().is_empty() {
        process_notification_alert_chunk(&mut result, channel, client_id, chunk_buffer.trim());
    }

    diagnostics.record_response_body_text(trace_id, &response_text, content_type.as_deref());
    Ok(result)
}

fn process_notification_alert_chunk(
    result: &mut NotificationAlertPollResult,
    channel: &str,
    client_id: &str,
    chunk: &str,
) {
    let messages: Vec<RawMessageBusMessage> = match serde_json::from_str(chunk) {
        Ok(messages) => messages,
        Err(error) => {
            warn!(
                client_id = %client_id,
                error = %error,
                chunk = %chunk,
                "failed to parse background notification-alert chunk"
            );
            return;
        }
    };

    for message in messages {
        if message.channel == "/__status" {
            if let Some(last_message_id) = message
                .data
                .get(channel)
                .and_then(|value| integer_i64(Some(value)))
            {
                result.last_message_id = result.last_message_id.max(last_message_id);
            }
            continue;
        }

        if message.channel != channel {
            continue;
        }

        result.last_message_id = result.last_message_id.max(message.message_id);
        result.alerts.push(notification_alert_from_raw(&message));
    }
}

fn process_chunk(context: &MessageBusPollContext, chunk: &str) -> Result<bool, FireCoreError> {
    let messages: Vec<RawMessageBusMessage> = match serde_json::from_str(chunk) {
        Ok(messages) => messages,
        Err(error) => {
            warn!(
                client_id = %context.client_id,
                error = %error,
                chunk = %chunk,
                "failed to parse message bus chunk"
            );
            return Ok(true);
        }
    };

    for message in messages {
        if message.channel == "/__status" {
            apply_status_message(&context.runtime, &message.data);
            continue;
        }

        update_channel_checkpoint(&context.runtime, &message.channel, message.message_id);
        if notification_user_id_from_channel(&message.channel).is_some() {
            merge_notification_event_data(&context.notifications, &message.data);
        }
        if let Some(topic_id) = presence_topic_id_from_channel(&message.channel) {
            merge_topic_presence_event_data(
                &context.topic_presence,
                topic_id,
                message.message_id,
                &message.data,
            );
        }
        let event = message_bus_event_from_raw(&message);
        if context.event_sender.send(event).is_err() {
            warn!("message bus listener dropped; stopping poll loop");
            return Ok(false);
        }
    }

    Ok(true)
}

fn apply_status_message(runtime: &Arc<Mutex<FireMessageBusRuntime>>, data: &Value) {
    let Some(object) = data.as_object() else {
        return;
    };
    let mut runtime = runtime.lock().expect("message bus runtime lock poisoned");
    for (channel, value) in object {
        let Some(last_message_id) = integer_i64(Some(value)) else {
            continue;
        };
        if let Some(subscription) = runtime.subscriptions.get_mut(channel) {
            subscription.last_message_id = subscription.last_message_id.max(last_message_id);
        }
    }
}

fn update_channel_checkpoint(
    runtime: &Arc<Mutex<FireMessageBusRuntime>>,
    channel: &str,
    message_id: i64,
) {
    let mut runtime = runtime.lock().expect("message bus runtime lock poisoned");
    if let Some(subscription) = runtime.subscriptions.get_mut(channel) {
        subscription.last_message_id = subscription.last_message_id.max(message_id);
    }
}

fn message_bus_event_from_raw(message: &RawMessageBusMessage) -> MessageBusEvent {
    let payload_json = serde_json::to_string(&message.data)
        .ok()
        .filter(|value| value != "null");

    if let Some(topic_list_kind) = topic_list_kind_for_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::TopicList,
            topic_list_kind: Some(topic_list_kind),
            topic_id: message
                .data
                .get("topic_id")
                .and_then(|value| positive_u64(Some(value)))
                .or_else(|| {
                    message
                        .data
                        .get("payload")
                        .and_then(|value| value.get("topic_id"))
                        .and_then(|value| positive_u64(Some(value)))
                }),
            message_type: message
                .data
                .get("message_type")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(topic_id) = topic_reaction_topic_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::TopicReaction,
            topic_id: Some(topic_id),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(topic_id) = topic_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::TopicDetail,
            topic_id: Some(topic_id),
            detail_event_type: message
                .data
                .get("type")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            reload_topic: boolean(message.data.get("reload_topic")),
            refresh_stream: boolean(message.data.get("refresh_stream")),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(topic_id) = presence_topic_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::Presence,
            topic_id: Some(topic_id),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(notification_user_id) = notification_user_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::Notification,
            notification_user_id: Some(notification_user_id),
            all_unread_notifications_count: message
                .data
                .get("all_unread_notifications_count")
                .and_then(|value| integer_u32(Some(value))),
            unread_notifications: message
                .data
                .get("unread_notifications")
                .and_then(|value| integer_u32(Some(value))),
            unread_high_priority_notifications: message
                .data
                .get("unread_high_priority_notifications")
                .and_then(|value| integer_u32(Some(value))),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    if let Some(notification_user_id) = notification_alert_user_id_from_channel(&message.channel) {
        return MessageBusEvent {
            channel: message.channel.clone(),
            message_id: message.message_id,
            kind: MessageBusEventKind::NotificationAlert,
            notification_user_id: Some(notification_user_id),
            payload_json,
            ..MessageBusEvent::default()
        };
    }

    MessageBusEvent {
        channel: message.channel.clone(),
        message_id: message.message_id,
        kind: MessageBusEventKind::Unknown,
        payload_json,
        ..MessageBusEvent::default()
    }
}

fn notification_alert_from_raw(message: &RawMessageBusMessage) -> NotificationAlert {
    NotificationAlert {
        message_id: message.message_id,
        notification_type: message
            .data
            .get("notification_type")
            .and_then(|value| integer_u32(Some(value))),
        topic_id: message
            .data
            .get("topic_id")
            .and_then(|value| positive_u64(Some(value))),
        post_number: message
            .data
            .get("post_number")
            .and_then(|value| integer_u32(Some(value))),
        topic_title: message
            .data
            .get("topic_title")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        excerpt: message
            .data
            .get("excerpt")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        username: message
            .data
            .get("username")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        post_url: message
            .data
            .get("post_url")
            .and_then(Value::as_str)
            .map(ToOwned::to_owned),
        payload_json: serde_json::to_string(&message.data)
            .ok()
            .filter(|value| value != "null"),
    }
}

fn ensure_bootstrap_subscriptions(
    bootstrap: &BootstrapArtifacts,
    runtime: &mut FireMessageBusRuntime,
) {
    for (channel, last_message_id) in bootstrap_tracking_subscriptions(bootstrap) {
        let entry = runtime
            .subscriptions
            .entry(channel)
            .or_insert_with(|| RuntimeSubscription {
                last_message_id,
                scope: MessageBusSubscriptionScope::Durable,
            });
        entry.last_message_id = entry.last_message_id.max(last_message_id);
        entry.scope = merge_subscription_scopes(entry.scope, MessageBusSubscriptionScope::Durable);
    }

    if let (Some(user_id), Some(last_message_id)) = (
        bootstrap.current_user_id,
        bootstrap.notification_channel_position,
    ) {
        let channel = format!("/notification/{user_id}");
        let entry = runtime
            .subscriptions
            .entry(channel)
            .or_insert_with(|| RuntimeSubscription {
                last_message_id,
                scope: MessageBusSubscriptionScope::Durable,
            });
        entry.last_message_id = entry.last_message_id.max(last_message_id);
        entry.scope = merge_subscription_scopes(entry.scope, MessageBusSubscriptionScope::Durable);
    }
}

fn bootstrap_tracking_subscriptions(bootstrap: &BootstrapArtifacts) -> Vec<(String, i64)> {
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

fn bootstrap_message_id_for_channel(bootstrap: &BootstrapArtifacts, channel: &str) -> Option<i64> {
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

fn bootstrap_notification_channel(bootstrap: &BootstrapArtifacts) -> Option<(String, i64)> {
    Some((
        format!("/notification/{}", bootstrap.current_user_id?),
        bootstrap.notification_channel_position?,
    ))
}

fn client_id_for_mode(runtime: &mut FireMessageBusRuntime, mode: MessageBusClientMode) -> String {
    match mode {
        MessageBusClientMode::Foreground => runtime
            .foreground_client_id
            .get_or_insert_with(generate_foreground_client_id)
            .clone(),
        MessageBusClientMode::IosBackground => generate_ios_background_client_id(),
    }
}

fn generate_foreground_client_id() -> String {
    let counter = FOREGROUND_CLIENT_COUNTER.fetch_add(1, Ordering::SeqCst);
    format!("fire_{:x}{:x}", now_unix_ms(), counter)
}

fn generate_ios_background_client_id() -> String {
    format!("ios_bg_{}", now_unix_ms())
}

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

fn backoff_delay(failure_count: u32) -> Duration {
    let seconds = 2_u64.saturating_pow(failure_count.min(5));
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

fn merge_subscription_scopes(
    current: MessageBusSubscriptionScope,
    incoming: MessageBusSubscriptionScope,
) -> MessageBusSubscriptionScope {
    match (current, incoming) {
        (MessageBusSubscriptionScope::Durable, _) | (_, MessageBusSubscriptionScope::Durable) => {
            MessageBusSubscriptionScope::Durable
        }
        _ => MessageBusSubscriptionScope::Transient,
    }
}

fn message_bus_poll_base_url(
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

fn message_bus_requires_shared_session_key(
    base_url: &Url,
    bootstrap: &BootstrapArtifacts,
) -> Result<bool, FireCoreError> {
    let poll_base_url = message_bus_poll_base_url(base_url, bootstrap)?;
    Ok(request_origin(base_url) != request_origin(&poll_base_url))
}

fn topic_list_kind_for_channel(channel: &str) -> Option<TopicListKind> {
    match channel {
        "/latest" => Some(TopicListKind::Latest),
        "/new" => Some(TopicListKind::New),
        _ => None,
    }
}

fn topic_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("topic"), Some(topic_id), None, None) => topic_id.parse::<u64>().ok(),
        _ => None,
    }
}

fn topic_reaction_topic_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some("topic"), Some(topic_id), Some("reactions"), None) => topic_id.parse::<u64>().ok(),
        _ => None,
    }
}

pub(crate) fn presence_topic_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (Some("presence"), Some("discourse-presence"), Some("reply"), Some(topic_id), None) => {
            topic_id.parse::<u64>().ok()
        }
        _ => None,
    }
}

pub(crate) fn message_bus_presence_channel_for_topic(topic_id: u64) -> String {
    format!("/presence/discourse-presence/reply/{topic_id}")
}

fn notification_user_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next()) {
        (Some("notification"), Some(user_id), None) => user_id.parse::<u64>().ok(),
        _ => None,
    }
}

fn notification_alert_user_id_from_channel(channel: &str) -> Option<u64> {
    let mut parts = channel.trim_matches('/').split('/');
    match (parts.next(), parts.next(), parts.next()) {
        (Some("notification-alert"), Some(user_id), None) => user_id.parse::<u64>().ok(),
        _ => None,
    }
}

pub(crate) fn active_message_bus_client_id(
    runtime: &Arc<Mutex<FireMessageBusRuntime>>,
) -> Option<String> {
    runtime
        .lock()
        .expect("message bus runtime lock poisoned")
        .active_client_id
        .clone()
}
