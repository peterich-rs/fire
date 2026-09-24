use std::{fs, path::Path};

use serde_json::{json, Value};

use crate::{error::FireCoreError, session_store::write_atomic};

use super::logs::{list_log_files, read_log_file_page, workspace_relative_path_string};
use super::models::{
    DiagnosticsPageDirection, DiagnosticsTextPage, FireLogFilePage, FireSupportBundleExport,
    FireSupportBundleHostContext, NetworkTraceBodyPage, NetworkTraceDetail, NetworkTraceEvent,
    NetworkTraceHeader, NetworkTraceOutcome, FEEDBACK_BUNDLE_DIR_NAME,
    FEEDBACK_BUNDLE_LOG_FILE_LIMIT, FEEDBACK_BUNDLE_LOG_PAGE_BYTES,
    FEEDBACK_BUNDLE_TRACE_BODY_BYTES, FEEDBACK_BUNDLE_TRACE_LIMIT, SUPPORT_BUNDLE_DIR_NAME,
    SUPPORT_BUNDLE_LOG_FILE_LIMIT, SUPPORT_BUNDLE_LOG_PAGE_BYTES, SUPPORT_BUNDLE_TRACE_BODY_BYTES,
    SUPPORT_BUNDLE_TRACE_LIMIT,
};
use super::store::{now_unix_ms, FireDiagnosticsStore};

pub(crate) fn export_support_bundle(
    workspace_path: &Path,
    diagnostics: &FireDiagnosticsStore,
    session_json: &str,
    host_context: &FireSupportBundleHostContext,
) -> Result<FireSupportBundleExport, FireCoreError> {
    export_diagnostics_bundle(
        workspace_path,
        diagnostics,
        session_json,
        host_context,
        DiagnosticsBundleKind::Support,
    )
}

/// Export a diagnostics package safe for off-device feedback submission.
///
/// Unlike [`export_support_bundle`], this path always expects a **redacted**
/// session JSON and strips cookie / auth / CSRF headers from network traces.
/// Local developer support bundles remain intentionally full-fidelity.
pub(crate) fn export_feedback_bundle(
    workspace_path: &Path,
    diagnostics: &FireDiagnosticsStore,
    redacted_session_json: &str,
    host_context: &FireSupportBundleHostContext,
) -> Result<FireSupportBundleExport, FireCoreError> {
    export_diagnostics_bundle(
        workspace_path,
        diagnostics,
        redacted_session_json,
        host_context,
        DiagnosticsBundleKind::Feedback,
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DiagnosticsBundleKind {
    Support,
    Feedback,
}

impl DiagnosticsBundleKind {
    fn file_prefix(self) -> &'static str {
        match self {
            Self::Support => "fire-support",
            Self::Feedback => "fire-feedback",
        }
    }

    fn dir_name(self) -> &'static str {
        match self {
            Self::Support => SUPPORT_BUNDLE_DIR_NAME,
            Self::Feedback => FEEDBACK_BUNDLE_DIR_NAME,
        }
    }

    fn kind_label(self) -> &'static str {
        match self {
            Self::Support => "support",
            Self::Feedback => "feedback",
        }
    }

    fn log_file_limit(self) -> usize {
        match self {
            Self::Support => SUPPORT_BUNDLE_LOG_FILE_LIMIT,
            Self::Feedback => FEEDBACK_BUNDLE_LOG_FILE_LIMIT,
        }
    }

    fn trace_limit(self) -> usize {
        match self {
            Self::Support => SUPPORT_BUNDLE_TRACE_LIMIT,
            Self::Feedback => FEEDBACK_BUNDLE_TRACE_LIMIT,
        }
    }

    fn log_page_bytes(self) -> usize {
        match self {
            Self::Support => SUPPORT_BUNDLE_LOG_PAGE_BYTES,
            Self::Feedback => FEEDBACK_BUNDLE_LOG_PAGE_BYTES,
        }
    }

    fn trace_body_bytes(self) -> usize {
        match self {
            Self::Support => SUPPORT_BUNDLE_TRACE_BODY_BYTES,
            Self::Feedback => FEEDBACK_BUNDLE_TRACE_BODY_BYTES,
        }
    }

    fn redact_sensitive_headers(self) -> bool {
        matches!(self, Self::Feedback)
    }

    fn session_redacted(self) -> bool {
        matches!(self, Self::Feedback)
    }
}

fn export_diagnostics_bundle(
    workspace_path: &Path,
    diagnostics: &FireDiagnosticsStore,
    session_json: &str,
    host_context: &FireSupportBundleHostContext,
    kind: DiagnosticsBundleKind,
) -> Result<FireSupportBundleExport, FireCoreError> {
    let generated_at_unix_ms = now_unix_ms();
    let file_name = format!("{}-{generated_at_unix_ms}.json", kind.file_prefix());
    let relative_path = Path::new("diagnostics")
        .join(kind.dir_name())
        .join(&file_name);
    let absolute_path = workspace_path.join(&relative_path);
    let parent = absolute_path
        .parent()
        .expect("diagnostics bundle path should have a parent");
    fs::create_dir_all(parent).map_err(|source| FireCoreError::DiagnosticsIo {
        path: parent.to_path_buf(),
        source,
    })?;

    let session: Value =
        serde_json::from_str(session_json).map_err(FireCoreError::DiagnosticsDeserialize)?;
    let log_files = list_log_files(workspace_path)?;
    let log_pages = log_files
        .iter()
        .take(kind.log_file_limit())
        .map(|file| {
            read_log_file_page(
                workspace_path,
                &file.relative_path,
                None,
                kind.log_page_bytes(),
                DiagnosticsPageDirection::Older,
            )
        })
        .collect::<Result<Vec<_>, _>>()?;
    let trace_summaries = diagnostics.summaries(kind.trace_limit());
    let redact_headers = kind.redact_sensitive_headers();
    let trace_payloads = trace_summaries
        .iter()
        .map(|summary| {
            let detail = diagnostics.detail(summary.id).ok_or_else(|| {
                FireCoreError::DiagnosticsTraceNotFound {
                    trace_id: summary.id.to_string(),
                }
            })?;
            let body_page = diagnostics.network_trace_body_page(
                summary.id,
                None,
                kind.trace_body_bytes(),
                DiagnosticsPageDirection::Newer,
            );
            Ok(support_bundle_trace_json(
                &detail,
                body_page.as_ref(),
                redact_headers,
            ))
        })
        .collect::<Result<Vec<_>, FireCoreError>>()?;

    let payload = json!({
        "version": 1,
        "kind": kind.kind_label(),
        "session_redacted": kind.session_redacted(),
        "generated_at_unix_ms": generated_at_unix_ms,
        "diagnostic_session_id": diagnostics.diagnostic_session_id(),
        "host": {
            "platform": host_context.platform,
            "app_version": host_context.app_version,
            "build_number": host_context.build_number,
            "scene_phase": host_context.scene_phase,
        },
        "session": session,
        "logs": log_pages.iter().map(support_bundle_log_json).collect::<Vec<_>>(),
        "network_traces": trace_payloads,
    });

    let contents =
        serde_json::to_vec_pretty(&payload).map_err(FireCoreError::DiagnosticsSerialize)?;
    write_atomic(&absolute_path, &contents).map_err(|source| FireCoreError::DiagnosticsIo {
        path: absolute_path.clone(),
        source,
    })?;
    let size_bytes = fs::metadata(&absolute_path)
        .map_err(|source| FireCoreError::DiagnosticsIo {
            path: absolute_path.clone(),
            source,
        })?
        .len();

    Ok(FireSupportBundleExport {
        file_name,
        relative_path: workspace_relative_path_string(&relative_path),
        absolute_path: absolute_path.display().to_string(),
        size_bytes,
        created_at_unix_ms: generated_at_unix_ms,
        diagnostic_session_id: diagnostics.diagnostic_session_id().to_string(),
    })
}

fn support_bundle_log_json(page: &FireLogFilePage) -> Value {
    json!({
        "relative_path": page.relative_path,
        "file_name": page.file_name,
        "size_bytes": page.size_bytes,
        "modified_at_unix_ms": page.modified_at_unix_ms,
        "window": diagnostics_text_page_json(&page.page),
    })
}

fn support_bundle_trace_json(
    detail: &NetworkTraceDetail,
    body_page: Option<&NetworkTraceBodyPage>,
    redact_sensitive_headers: bool,
) -> Value {
    json!({
        "summary": {
            "id": detail.id,
            "call_id": detail.call_id,
            "operation": detail.operation,
            "method": detail.method,
            "url": detail.url,
            "started_at_unix_ms": detail.started_at_unix_ms,
            "finished_at_unix_ms": detail.finished_at_unix_ms,
            "duration_ms": detail.duration_ms,
            "outcome": support_bundle_trace_outcome(detail.outcome),
            "status_code": detail.status_code,
            "error_message": detail.error_message,
            "response_content_type": detail.response_content_type,
            "response_body_truncated": detail.response_body_truncated,
            "response_body_storage_truncated": detail.response_body_storage_truncated,
            "response_body_stored_bytes": detail.response_body_stored_bytes,
            "response_body_page_available": detail.response_body_page_available,
            "response_body_bytes": detail.response_body_bytes,
        },
        "request_headers": detail
            .request_headers
            .iter()
            .map(|header| support_bundle_header_json(header, redact_sensitive_headers))
            .collect::<Vec<_>>(),
        "response_headers": detail
            .response_headers
            .iter()
            .map(|header| support_bundle_header_json(header, redact_sensitive_headers))
            .collect::<Vec<_>>(),
        "events": detail.events.iter().map(support_bundle_event_json).collect::<Vec<_>>(),
        "body_page": body_page.map(|page| {
            json!({
                "response_content_type": page.response_content_type,
                "response_body_storage_truncated": page.response_body_storage_truncated,
                "response_body_stored_bytes": page.response_body_stored_bytes,
                "window": diagnostics_text_page_json(&page.page),
            })
        }),
    })
}

fn diagnostics_text_page_json(page: &DiagnosticsTextPage) -> Value {
    json!({
        "text": page.text,
        "start_offset": page.start_offset,
        "end_offset": page.end_offset,
        "total_bytes": page.total_bytes,
        "next_cursor": page.next_cursor,
        "has_more_older": page.has_more_older,
        "has_more_newer": page.has_more_newer,
        "is_head_aligned": page.is_head_aligned,
        "is_tail_aligned": page.is_tail_aligned,
    })
}

fn support_bundle_header_json(
    header: &NetworkTraceHeader,
    redact_sensitive_headers: bool,
) -> Value {
    let value = if redact_sensitive_headers && is_sensitive_header_name(&header.name) {
        "[redacted]"
    } else {
        header.value.as_str()
    };
    json!({
        "name": header.name,
        "value": value,
    })
}

fn is_sensitive_header_name(name: &str) -> bool {
    matches!(
        name.to_ascii_lowercase().as_str(),
        "cookie"
            | "set-cookie"
            | "authorization"
            | "proxy-authorization"
            | "x-csrf-token"
            | "x-api-key"
            | "x-auth-token"
            | "x-access-token"
    )
}

fn support_bundle_event_json(event: &NetworkTraceEvent) -> Value {
    json!({
        "sequence": event.sequence,
        "timestamp_unix_ms": event.timestamp_unix_ms,
        "phase": event.phase,
        "summary": event.summary,
        "details": event.details,
    })
}

fn support_bundle_trace_outcome(outcome: NetworkTraceOutcome) -> &'static str {
    match outcome {
        NetworkTraceOutcome::InProgress => "in_progress",
        NetworkTraceOutcome::Succeeded => "succeeded",
        NetworkTraceOutcome::Failed => "failed",
        NetworkTraceOutcome::Cancelled => "cancelled",
    }
}
