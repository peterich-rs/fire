use std::sync::{atomic::Ordering, Arc};
use std::time::Duration;

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
    time::{sleep, timeout, Instant},
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
use super::schedule::*;

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
    let schedule_updates = schedule_updates_receiver(runtime);
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
        schedule_updates,
    };
    Ok(runtime_handle.spawn(async move {
        run_message_bus_poll_loop(context, subscription_updates).await;
    }))
}

async fn run_message_bus_poll_loop(
    mut context: MessageBusPollContext,
    mut subscription_updates: watch::Receiver<u64>,
) {
    let mut failure_count = 0_u32;
    let mut force_dont_chunk = false;

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

        let cycle_started_at = Instant::now();
        match execute_poll_once_with_subscription_changes(
            &context,
            &mut subscription_updates,
            &subscriptions,
            subscription_revision,
            force_dont_chunk,
        )
        .await
        {
            Ok(PollIterationResult::Continue) => {
                failure_count = 0;
                force_dont_chunk = false;
                note_chunked_success(&context);
                wait_for_next_poll(&mut context, cycle_started_at).await;
            }
            Ok(PollIterationResult::Restart) => {
                failure_count = 0;
                force_dont_chunk = false;
            }
            Ok(PollIterationResult::Stop) => break,
            Ok(PollIterationResult::RateLimited { delay }) => {
                failure_count = 0;
                force_dont_chunk = false;
                sleep(delay).await;
            }
            Ok(PollIterationResult::RetryWithoutChunk) => {
                failure_count = 0;
                force_dont_chunk = true;
                arm_chunked_backoff(&context);
            }
            Err(error) => {
                if is_expected_long_poll_timeout(&error) {
                    debug!(
                        client_id = %context.client_id,
                        error = %error,
                        "message bus poll timed out; continuing without backoff"
                    );
                    failure_count = 0;
                    force_dont_chunk = false;
                    wait_for_next_poll(&mut context, cycle_started_at).await;
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
    force_dont_chunk: bool,
) -> Result<PollIterationResult, FireCoreError> {
    let poll_started_at = Instant::now();
    let poll = execute_poll_once(context, subscriptions, force_dont_chunk);
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
                    return map_poll_once_result(result);
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
                    return map_poll_once_result(result);
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

fn map_poll_once_result(
    result: Result<PollOnceOutcome, FireCoreError>,
) -> Result<PollIterationResult, FireCoreError> {
    result.map(|outcome| match outcome {
        PollOnceOutcome::KeepRunning => PollIterationResult::Continue,
        PollOnceOutcome::Stop => PollIterationResult::Stop,
        PollOnceOutcome::RateLimited { delay } => PollIterationResult::RateLimited { delay },
        PollOnceOutcome::FirstChunkTimeout => PollIterationResult::RetryWithoutChunk,
    })
}

async fn execute_poll_once(
    context: &MessageBusPollContext,
    subscriptions: &[(String, i64)],
    force_dont_chunk: bool,
) -> Result<PollOnceOutcome, FireCoreError> {
    let traced = build_message_bus_poll_request(context, subscriptions, force_dont_chunk)?;
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

    let chunked = !should_dont_chunk_now(context, force_dont_chunk);
    read_message_bus_success_response(context, trace_id, response, chunked).await
}

pub(super) fn build_message_bus_poll_request(
    context: &MessageBusPollContext,
    subscriptions: &[(String, i64)],
    force_dont_chunk: bool,
) -> Result<TracedRequest, FireCoreError> {
    let state = read_rwlock(&context.session, "session");
    let dont_chunk = should_dont_chunk_now(context, force_dont_chunk);
    build_message_bus_poll_request_for_snapshot(MessageBusPollSnapshotRequest {
        diagnostics: &context.diagnostics,
        base_url: &context.base_url,
        snapshot: &state.snapshot,
        epoch: state.epoch,
        client_id: &context.client_id,
        mode: context.mode,
        subscriptions,
        dont_chunk,
    })
}

pub(super) struct MessageBusPollSnapshotRequest<'a> {
    pub diagnostics: &'a Arc<FireDiagnosticsStore>,
    pub base_url: &'a Url,
    pub snapshot: &'a SessionSnapshot,
    pub epoch: u64,
    pub client_id: &'a str,
    pub mode: MessageBusClientMode,
    pub subscriptions: &'a [(String, i64)],
    pub dont_chunk: bool,
}

pub(super) fn build_message_bus_poll_request_for_snapshot(
    request: MessageBusPollSnapshotRequest<'_>,
) -> Result<TracedRequest, FireCoreError> {
    let MessageBusPollSnapshotRequest {
        diagnostics,
        base_url,
        snapshot,
        epoch,
        client_id,
        mode,
        subscriptions,
        dont_chunk,
    } = request;
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
        .header("X-SILENCE-LOGGER", "true");
    if dont_chunk {
        builder = builder.header("Dont-Chunk", "true");
    }

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
) -> Result<PollOnceOutcome, FireCoreError> {
    let status = response.status().as_u16();
    let retry_after = if status == 429 {
        parse_retry_after(response.headers(), now_system_time())
    } else {
        None
    };
    match read_message_bus_error_response_for_diagnostics(&context.diagnostics, trace_id, response)
        .await
    {
        Err(FireCoreError::HttpStatus { status: 429, .. }) => Ok(PollOnceOutcome::RateLimited {
            delay: rate_limit_delay(retry_after, rate_limit_jitter(now_unix_ms())),
        }),
        Ok(_) => Ok(PollOnceOutcome::KeepRunning),
        Err(error) => Err(error),
    }
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
    chunked: bool,
) -> Result<PollOnceOutcome, FireCoreError> {
    let mut response = response;
    let _trace_guard = take_trace_cancellation_guard(&mut response).unwrap_or_else(|| {
        context.diagnostics.cancellation_guard(
            trace_id,
            "Request cancelled",
            "Future dropped while processing the message bus response body",
        )
    });
    let content_type = header_value(response.headers(), "content-type");
    let uses_chunked_te = header_value(response.headers(), "transfer-encoding")
        .is_some_and(|value| value.to_ascii_lowercase().contains("chunked"));
    let content_length = content_length_bytes(response.headers());
    let mut body = response.into_body();
    if !chunked || !uses_chunked_te {
        let response_text = match body.text().await {
            Ok(text) => text,
            Err(source) => {
                context.diagnostics.record_call_failed(trace_id, &source);
                return Err(FireCoreError::Network { source });
            }
        };
        return finish_message_bus_body(context, trace_id, content_type.as_deref(), &response_text);
    }

    let mut response_text = String::new();
    let mut chunk_buffer = String::new();
    let mut bytes_read = 0_usize;

    let mut saw_first_chunk = false;
    loop {
        let next_frame = if chunked && !saw_first_chunk {
            match timeout(FIRST_CHUNK_TIMEOUT, body.frame()).await {
                Ok(frame) => frame,
                Err(_) => {
                    debug!(
                        trace_id,
                        client_id = %context.client_id,
                        "message bus first chunk timed out; retrying without chunked encoding"
                    );
                    return Ok(PollOnceOutcome::FirstChunkTimeout);
                }
            }
        } else {
            body.frame().await
        };
        let Some(frame) = next_frame else {
            break;
        };
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
        saw_first_chunk = true;
        bytes_read = bytes_read.saturating_add(bytes.len());
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
                return Ok(PollOnceOutcome::Stop);
            }
        }
        if content_length.is_some_and(|expected| bytes_read >= expected) {
            break;
        }
    }

    if !chunk_buffer.trim().is_empty() && !process_chunk(context, chunk_buffer.trim())? {
        context.diagnostics.record_response_body_text(
            trace_id,
            &response_text,
            content_type.as_deref(),
        );
        return Ok(PollOnceOutcome::Stop);
    }
    context.diagnostics.record_response_body_text(
        trace_id,
        &response_text,
        content_type.as_deref(),
    );
    Ok(PollOnceOutcome::KeepRunning)
}

fn finish_message_bus_body(
    context: &MessageBusPollContext,
    trace_id: u64,
    content_type: Option<&str>,
    response_text: &str,
) -> Result<PollOnceOutcome, FireCoreError> {
    let mut chunk_buffer = response_text.to_string();
    while let Some(delimiter) = chunk_buffer.find('|') {
        let chunk = chunk_buffer[..delimiter].trim().to_string();
        chunk_buffer = chunk_buffer[delimiter + 1..].to_string();
        if !chunk.is_empty() && !process_chunk(context, &chunk)? {
            context
                .diagnostics
                .record_response_body_text(trace_id, response_text, content_type);
            return Ok(PollOnceOutcome::Stop);
        }
    }
    if !chunk_buffer.trim().is_empty() && !process_chunk(context, chunk_buffer.trim())? {
        context
            .diagnostics
            .record_response_body_text(trace_id, response_text, content_type);
        return Ok(PollOnceOutcome::Stop);
    }

    context
        .diagnostics
        .record_response_body_text(trace_id, response_text, content_type);
    Ok(PollOnceOutcome::KeepRunning)
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
    let content_length = content_length_bytes(response.headers());
    let mut body = response.into_body();
    let mut response_text = String::new();
    let mut chunk_buffer = String::new();
    let mut bytes_read = 0_usize;
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
        bytes_read = bytes_read.saturating_add(bytes.len());
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
        if content_length.is_some_and(|expected| bytes_read >= expected) {
            break;
        }
    }

    if !chunk_buffer.trim().is_empty() {
        process_notification_alert_chunk(&mut result, channel, client_id, chunk_buffer.trim());
    }

    diagnostics.record_response_body_text(trace_id, &response_text, content_type.as_deref());
    Ok(result)
}

fn content_length_bytes(headers: &http::HeaderMap) -> Option<usize> {
    header_value(headers, "content-length")?.parse().ok()
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
        let _ = context
            .core
            .apply_topic_tracking_bus_event(&message.channel, &message.data);
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

fn should_dont_chunk_now(context: &MessageBusPollContext, force_dont_chunk: bool) -> bool {
    if force_dont_chunk {
        return true;
    }
    let runtime = context
        .runtime
        .lock()
        .expect("message bus runtime lock poisoned");
    let snapshot = read_rwlock(&context.session, "session");
    should_send_dont_chunk(
        snapshot.snapshot.bootstrap.enable_chunked_encoding,
        runtime.chunked_backoff_remaining,
        runtime.app_backgrounded,
        context.mode,
    )
}

fn note_chunked_success(context: &MessageBusPollContext) {
    let mut runtime = context
        .runtime
        .lock()
        .expect("message bus runtime lock poisoned");
    if runtime.chunked_backoff_remaining > 0 {
        runtime.chunked_backoff_remaining -= 1;
    }
}

fn arm_chunked_backoff(context: &MessageBusPollContext) {
    let mut runtime = context
        .runtime
        .lock()
        .expect("message bus runtime lock poisoned");
    runtime.chunked_backoff_remaining = CHUNKED_BACKOFF_SUCCESSES;
}

async fn wait_for_next_poll(context: &mut MessageBusPollContext, cycle_started_at: Instant) {
    loop {
        let (wait, poll_now) = {
            let mut runtime = context
                .runtime
                .lock()
                .expect("message bus runtime lock poisoned");
            if runtime.poll_immediately {
                runtime.poll_immediately = false;
                (Duration::ZERO, true)
            } else {
                let snapshot = read_rwlock(&context.session, "session");
                let target = target_poll_interval(
                    &snapshot.snapshot.bootstrap,
                    context.mode,
                    runtime.app_backgrounded,
                );
                (success_wait(cycle_started_at.elapsed(), target), false)
            }
        };
        if poll_now || wait.is_zero() {
            return;
        }
        tokio::select! {
            _ = sleep(wait) => return,
            changed = context.schedule_updates.changed() => {
                if changed.is_err() {
                    return;
                }
            }
        }
    }
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
