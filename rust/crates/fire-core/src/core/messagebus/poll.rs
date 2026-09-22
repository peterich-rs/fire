use std::sync::{atomic::Ordering, Arc};

use fire_models::{
    MessageBusClientMode, MessageBusEvent, MessageBusEventKind, NotificationAlertPollResult,
    SessionSnapshot,
};
use http::{Method, Request, Response};
use http_body_util::BodyExt;
use openwire::{RequestBody, ResponseBody};
use tokio::{
    sync::watch,
    task::JoinHandle,
    time::{sleep, Instant},
};
use tracing::{debug, warn};
use url::{form_urlencoded::Serializer, Url};

use super::super::{
    network::{
        classify_http_status_error, header_value, request_origin, take_trace_cancellation_guard,
        FireCallProfile, FireRequestEpoch, FireRequestProfile, TracedRequest,
    },
    notifications::merge_notification_event_data,
    presence::merge_topic_presence_event_data,
    FireCore,
};
use super::*;
use crate::{
    diagnostics::FireDiagnosticsStore, error::FireCoreError, json_helpers::integer_i64,
    sync_utils::read_rwlock,
};

use super::channels::*;
use super::parse::*;
use super::runtime::*;

pub(super) fn ensure_poll_task_running(
    core: &FireCore,
    runtime: &mut FireMessageBusRuntime,
) -> Result<(), FireCoreError> {
    if runtime.active_mode.is_none() || runtime.poll_task.is_some() {
        return Ok(());
    }
    let client_id = runtime
        .active_client_id
        .clone()
        .or_else(|| {
            runtime
                .active_mode
                .map(|mode| client_id_for_mode(runtime, mode))
        })
        .expect("message bus active mode should exist");
    runtime.active_client_id = Some(client_id.clone());
    runtime.poll_task = Some(spawn_poll_task(core, runtime, client_id)?);
    Ok(())
}

pub(super) fn stop_poll_task_locked(runtime: &mut FireMessageBusRuntime) {
    if let Some(task) = runtime.poll_task.take() {
        task.abort();
    }
}

pub(super) fn spawn_poll_task(
    core: &FireCore,
    runtime: &mut FireMessageBusRuntime,
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
    let subscription_updates = subscription_updates_receiver(runtime);
    runtime.poll_task_token = runtime.poll_task_token.saturating_add(1);
    let task_token = runtime.poll_task_token;
    let mode = runtime
        .active_mode
        .ok_or(FireCoreError::MessageBusNotStarted)?;
    let context = MessageBusPollContext {
        core: core.clone(),
        base_url: core.base_url.clone(),
        network: core.network.clone(),
        diagnostics: Arc::clone(&core.diagnostics),
        session: Arc::clone(&core.session),
        runtime: Arc::clone(&core.message_bus),
        notifications: Arc::clone(&core.notifications),
        topic_presence: Arc::clone(&core.topic_presence),
        event_sender,
        client_id,
        mode,
        task_token,
    };
    Ok(runtime_handle.spawn(async move {
        run_message_bus_poll_loop(context, subscription_updates).await;
    }))
}

async fn run_message_bus_poll_loop(
    context: MessageBusPollContext,
    mut subscription_updates: watch::Receiver<u64>,
) {
    let mut failure_count = 0_u32;

    loop {
        let (subscriptions, subscription_revision) = {
            let runtime = context
                .runtime
                .lock()
                .expect("message bus runtime lock poisoned");
            if runtime.active_client_id.as_deref() != Some(context.client_id.as_str()) {
                break;
            }
            (
                runtime
                    .subscriptions
                    .iter()
                    .map(|(channel, entry)| (channel.clone(), entry.last_message_id))
                    .collect::<Vec<_>>(),
                runtime.subscription_revision,
            )
        };

        if subscriptions.is_empty() {
            if !wait_for_subscription_change(&context, &mut subscription_updates).await {
                break;
            }
            continue;
        }

        match execute_poll_once_with_subscription_changes(
            &context,
            &mut subscription_updates,
            &subscriptions,
            subscription_revision,
        )
        .await
        {
            Ok(PollIterationResult::Continue) => {
                failure_count = 0;
            }
            Ok(PollIterationResult::Restart) => {
                failure_count = 0;
            }
            Ok(PollIterationResult::Stop) => break,
            Err(error) => {
                if is_expected_long_poll_timeout(&error) {
                    debug!(
                        client_id = %context.client_id,
                        error = %error,
                        "message bus poll timed out; continuing without backoff"
                    );
                    failure_count = 0;
                    continue;
                }

                log_message_bus_poll_failure(&context.client_id, &error);
                failure_count = failure_count.saturating_add(1);
                let delay = backoff_delay(failure_count);
                sleep(delay).await;
            }
        }
    }

    clear_poll_task_on_exit(&context.runtime, &context.client_id, context.task_token);
}

async fn wait_for_subscription_change(
    context: &MessageBusPollContext,
    subscription_updates: &mut watch::Receiver<u64>,
) -> bool {
    match subscription_updates.changed().await {
        Ok(_) => {
            context
                .runtime
                .lock()
                .expect("message bus runtime lock poisoned")
                .active_client_id
                .as_deref()
                == Some(context.client_id.as_str())
        }
        Err(_) => false,
    }
}

async fn execute_poll_once_with_subscription_changes(
    context: &MessageBusPollContext,
    subscription_updates: &mut watch::Receiver<u64>,
    subscriptions: &[(String, i64)],
    subscription_revision: u64,
) -> Result<PollIterationResult, FireCoreError> {
    let poll_started_at = Instant::now();
    let poll = execute_poll_once(context, subscriptions);
    tokio::pin!(poll);
    let mut pending_restart = false;

    loop {
        if pending_restart {
            let remaining =
                MESSAGE_BUS_MIN_RESTART_INTERVAL.saturating_sub(poll_started_at.elapsed());
            if remaining.is_zero() {
                return Ok(PollIterationResult::Restart);
            }

            tokio::select! {
                result = &mut poll => {
                    return result.map(|keep_running| {
                        if keep_running {
                            PollIterationResult::Continue
                        } else {
                            PollIterationResult::Stop
                        }
                    });
                }
                changed = subscription_updates.changed() => {
                    if changed.is_err() {
                        return Ok(PollIterationResult::Stop);
                    }
                    pending_restart |= *subscription_updates.borrow() != subscription_revision;
                }
                _ = sleep(remaining) => {
                    return Ok(PollIterationResult::Restart);
                }
            }
        } else {
            tokio::select! {
                result = &mut poll => {
                    return result.map(|keep_running| {
                        if keep_running {
                            PollIterationResult::Continue
                        } else {
                            PollIterationResult::Stop
                        }
                    });
                }
                changed = subscription_updates.changed() => {
                    if changed.is_err() {
                        return Ok(PollIterationResult::Stop);
                    }
                    pending_restart = *subscription_updates.borrow() != subscription_revision;
                }
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

pub(super) fn build_message_bus_poll_request(
    context: &MessageBusPollContext,
    subscriptions: &[(String, i64)],
) -> Result<TracedRequest, FireCoreError> {
    let state = read_rwlock(&context.session, "session");
    build_message_bus_poll_request_for_snapshot(
        &context.diagnostics,
        &context.base_url,
        &state.snapshot,
        state.epoch,
        &context.client_id,
        context.mode,
        subscriptions,
    )
}

pub(super) fn build_message_bus_poll_request_for_snapshot(
    diagnostics: &Arc<FireDiagnosticsStore>,
    base_url: &Url,
    snapshot: &SessionSnapshot,
    epoch: u64,
    client_id: &str,
    mode: MessageBusClientMode,
    subscriptions: &[(String, i64)],
) -> Result<TracedRequest, FireCoreError> {
    let poll_base_url = message_bus_poll_base_url(base_url, &snapshot.bootstrap)?;
    let uri = poll_base_url.join(&format!("/message-bus/{client_id}/poll"))?;
    let same_origin = request_origin(base_url) == request_origin(&poll_base_url);

    let mut serializer = Serializer::new(String::new());
    for (channel, last_message_id) in subscriptions {
        serializer.append_pair(channel, &last_message_id.to_string());
    }
    let sequence = MESSAGE_BUS_SEQUENCE_COUNTER.fetch_add(1, Ordering::SeqCst);
    serializer.append_pair("__seq", &sequence.to_string());

    let mut builder = Request::builder()
        .method(Method::POST)
        .uri(uri.as_str())
        .header("Accept", "text/plain, */*; q=0.01")
        .header(
            "Content-Type",
            "application/x-www-form-urlencoded; charset=UTF-8",
        )
        .header("X-SILENCE-LOGGER", "true")
        .header("Dont-Chunk", "true");

    if mode == MessageBusClientMode::IosBackground {
        builder = builder.header("Discourse-Background", "true");
    }

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
    request.extensions_mut().insert(FireRequestEpoch(epoch));
    let trace_id = diagnostics.prepare_request_trace(MESSAGE_BUS_OPERATION, &mut request);
    Ok(TracedRequest {
        trace_id,
        operation: MESSAGE_BUS_OPERATION,
        request,
    })
}

async fn read_message_bus_error_response(
    context: &MessageBusPollContext,
    trace_id: u64,
    response: Response<ResponseBody>,
) -> Result<bool, FireCoreError> {
    read_message_bus_error_response_for_diagnostics(&context.diagnostics, trace_id, response).await
}

pub(super) async fn read_message_bus_error_response_for_diagnostics(
    diagnostics: &Arc<FireDiagnosticsStore>,
    trace_id: u64,
    response: Response<ResponseBody>,
) -> Result<bool, FireCoreError> {
    let mut response = response;
    let _trace_guard = take_trace_cancellation_guard(&mut response).unwrap_or_else(|| {
        diagnostics.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped while reading the message bus error response body",
        )
    });
    let status = response.status().as_u16();
    let response_headers = response.headers().clone();
    let body = match response.into_body().text().await {
        Ok(body) => body,
        Err(source) => {
            diagnostics.record_call_failed(trace_id, &source);
            return Err(FireCoreError::Network { source });
        }
    };
    diagnostics.record_http_status_error(trace_id, status, &body);
    Err(classify_http_status_error(
        MESSAGE_BUS_OPERATION,
        status,
        &response_headers,
        body,
    ))
}

async fn read_message_bus_success_response(
    context: &MessageBusPollContext,
    trace_id: u64,
    response: Response<ResponseBody>,
) -> Result<bool, FireCoreError> {
    let mut response = response;
    let _trace_guard = take_trace_cancellation_guard(&mut response).unwrap_or_else(|| {
        context.diagnostics.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped while processing the message bus response body",
        )
    });
    let content_type = header_value(response.headers(), "content-type");
    let mut body = response.into_body();
    let mut response_text = String::new();
    let mut chunk_buffer = String::new();

    while let Some(frame) = body.frame().await {
        let frame = match frame {
            Ok(frame) => frame,
            Err(source) => {
                context.diagnostics.record_call_failed(trace_id, &source);
                return Err(FireCoreError::Network { source });
            }
        };
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

pub(super) async fn read_notification_alert_success_response(
    diagnostics: &Arc<FireDiagnosticsStore>,
    trace_id: u64,
    response: Response<ResponseBody>,
    notification_user_id: u64,
    client_id: &str,
    channel: &str,
    initial_last_message_id: i64,
) -> Result<NotificationAlertPollResult, FireCoreError> {
    let mut response = response;
    let _trace_guard = take_trace_cancellation_guard(&mut response).unwrap_or_else(|| {
        diagnostics.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped while processing the notification alert response body",
        )
    });
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
        let frame = match frame {
            Ok(frame) => frame,
            Err(source) => {
                diagnostics.record_call_failed(trace_id, &source);
                return Err(FireCoreError::Network { source });
            }
        };
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

pub(super) fn process_notification_alert_chunk(
    result: &mut NotificationAlertPollResult,
    channel: &str,
    client_id: &str,
    chunk: &str,
) {
    let Some(messages) =
        parse_message_bus_messages(chunk, client_id, "background notification-alert")
    else {
        return;
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

pub(super) fn process_chunk(
    context: &MessageBusPollContext,
    chunk: &str,
) -> Result<bool, FireCoreError> {
    let Some(messages) = parse_message_bus_messages(chunk, &context.client_id, "message bus")
    else {
        return Ok(true);
    };

    for message in messages {
        if message.channel == "/__status" {
            apply_status_message(&context.runtime, &message.data);
            continue;
        }

        update_channel_checkpoint(&context.runtime, &message.channel, message.message_id);
        if let Some(user_id) = logout_user_id_from_channel(&message.channel) {
            if context.core.handle_server_forced_logout(user_id) {
                let event = MessageBusEvent {
                    channel: message.channel.clone(),
                    message_id: message.message_id,
                    kind: MessageBusEventKind::SessionLogout,
                    notification_user_id: Some(user_id),
                    payload_json: serde_json::to_string(&message.data)
                        .ok()
                        .filter(|value| value != "null"),
                    ..MessageBusEvent::default()
                };
                if context.event_sender.send(event).is_err() {
                    warn!("message bus listener dropped; stopping poll loop");
                    return Ok(false);
                }
            }
            continue;
        }
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
        let listeners = {
            let runtime = context
                .runtime
                .lock()
                .expect("message bus runtime lock poisoned");
            runtime.internal_listeners.clone()
        };
        for listener in listeners {
            let event = event.clone();
            let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                (listener.on_event)(&event);
            }));
        }
        if context.event_sender.send(event).is_err() {
            warn!("message bus listener dropped; stopping poll loop");
            return Ok(false);
        }
    }

    Ok(true)
}

#[cfg(test)]
mod tests {
    use openwire::WireError;

    use super::*;

    #[test]
    fn call_timeout_is_treated_as_expected_long_poll_timeout() {
        let error = FireCoreError::Network {
            source: WireError::timeout("call timed out after 75s"),
        };

        assert!(is_expected_long_poll_timeout(&error));
    }

    #[test]
    fn connect_timeout_is_not_treated_as_expected_long_poll_timeout() {
        let error = FireCoreError::Network {
            source: WireError::connect_timeout("connect timed out after 10s"),
        };

        assert!(!is_expected_long_poll_timeout(&error));
    }
}
