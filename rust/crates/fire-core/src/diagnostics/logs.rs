use std::{fs, path::Path, time::UNIX_EPOCH};

use mars_xlog::Xlog;
use mars_xlog_core::{
    compress::{decompress_raw_zlib, decompress_zstd_frames},
    protocol::{
        LogHeader, HEADER_LEN, MAGIC_ASYNC_NO_CRYPT_ZLIB_START, MAGIC_ASYNC_NO_CRYPT_ZSTD_START,
        MAGIC_ASYNC_ZLIB_START, MAGIC_ASYNC_ZSTD_START, MAGIC_END, MAGIC_SYNC_ZLIB_START,
        MAGIC_SYNC_ZSTD_START, TAILER_LEN,
    },
};

use crate::error::FireCoreError;
use crate::workspace::validate_workspace_relative_path;

use super::models::{
    DiagnosticsPageDirection, DiagnosticsTextPage, FireLogFileDetail, FireLogFilePage,
    FireLogFileSummary, DEFAULT_LOG_PAGE_BYTES, FEEDBACK_BUNDLE_DIR_NAME, MAX_LOG_CONTENT_BYTES,
    SUPPORT_BUNDLE_DIR_NAME,
};

pub(crate) fn list_log_files(
    workspace_path: &Path,
) -> Result<Vec<FireLogFileSummary>, FireCoreError> {
    let log_root = workspace_path.join("logs");
    let mut out = Vec::new();
    if log_root.exists() {
        visit_log_files(workspace_path, &log_root, &mut out)?;
    }
    let diagnostics_root = workspace_path.join("diagnostics");
    if diagnostics_root.exists() {
        visit_log_files(workspace_path, &diagnostics_root, &mut out)?;
    }
    out.sort_by(|left, right| {
        right
            .modified_at_unix_ms
            .cmp(&left.modified_at_unix_ms)
            .then_with(|| right.relative_path.cmp(&left.relative_path))
    });
    Ok(out)
}

pub(crate) fn read_log_file(
    workspace_path: &Path,
    relative_path: impl AsRef<Path>,
) -> Result<FireLogFileDetail, FireCoreError> {
    let relative_path = relative_path.as_ref();
    validate_workspace_relative_path(relative_path)?;

    let resolved_path = workspace_path.join(relative_path);
    let metadata = fs::metadata(&resolved_path).map_err(|source| FireCoreError::WorkspaceIo {
        path: resolved_path.clone(),
        source,
    })?;
    let bytes = fs::read(&resolved_path).map_err(|source| FireCoreError::WorkspaceIo {
        path: resolved_path.clone(),
        source,
    })?;
    let decoded = decode_log_file_contents(&resolved_path, &bytes);
    let (contents, is_truncated) = truncate_text(&decoded, MAX_LOG_CONTENT_BYTES);

    Ok(FireLogFileDetail {
        relative_path: workspace_relative_path_string(relative_path),
        file_name: resolved_path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string(),
        size_bytes: metadata.len(),
        modified_at_unix_ms: metadata
            .modified()
            .ok()
            .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
            .map(|value| value.as_millis().min(u64::MAX as u128) as u64)
            .unwrap_or_default(),
        contents,
        is_truncated,
    })
}

pub(crate) fn read_log_file_page(
    workspace_path: &Path,
    relative_path: impl AsRef<Path>,
    cursor: Option<u64>,
    max_bytes: usize,
    direction: DiagnosticsPageDirection,
) -> Result<FireLogFilePage, FireCoreError> {
    let relative_path = relative_path.as_ref();
    validate_workspace_relative_path(relative_path)?;

    let resolved_path = workspace_path.join(relative_path);
    let metadata = fs::metadata(&resolved_path).map_err(|source| FireCoreError::WorkspaceIo {
        path: resolved_path.clone(),
        source,
    })?;
    let bytes = fs::read(&resolved_path).map_err(|source| FireCoreError::WorkspaceIo {
        path: resolved_path.clone(),
        source,
    })?;
    let decoded = decode_log_file_contents(&resolved_path, &bytes);
    let page = paginate_log_text(
        &decoded,
        cursor,
        normalized_page_bytes(max_bytes, DEFAULT_LOG_PAGE_BYTES),
        direction,
    );

    Ok(FireLogFilePage {
        relative_path: workspace_relative_path_string(relative_path),
        file_name: resolved_path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string(),
        size_bytes: metadata.len(),
        modified_at_unix_ms: metadata
            .modified()
            .ok()
            .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
            .map(|value| value.as_millis().min(u64::MAX as u128) as u64)
            .unwrap_or_default(),
        page,
    })
}

pub(super) fn visit_log_files(
    workspace_path: &Path,
    dir: &Path,
    out: &mut Vec<FireLogFileSummary>,
) -> Result<(), FireCoreError> {
    for entry in fs::read_dir(dir).map_err(|source| FireCoreError::WorkspaceIo {
        path: dir.to_path_buf(),
        source,
    })? {
        let entry = entry.map_err(|source| FireCoreError::WorkspaceIo {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.is_dir() {
            if is_support_bundle_path(workspace_path, &path) {
                continue;
            }
            visit_log_files(workspace_path, &path, out)?;
            continue;
        }

        if is_support_bundle_path(workspace_path, &path) {
            continue;
        }

        let metadata = entry
            .metadata()
            .map_err(|source| FireCoreError::WorkspaceIo {
                path: path.clone(),
                source,
            })?;
        let relative_path = path.strip_prefix(workspace_path).map_or_else(
            |_| workspace_relative_path_string(&path),
            workspace_relative_path_string,
        );

        out.push(FireLogFileSummary {
            relative_path,
            file_name: path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string(),
            size_bytes: metadata.len(),
            modified_at_unix_ms: metadata
                .modified()
                .ok()
                .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
                .map(|value| value.as_millis().min(u64::MAX as u128) as u64)
                .unwrap_or_default(),
        });
    }

    Ok(())
}

fn decode_log_file_contents(path: &Path, bytes: &[u8]) -> String {
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default();

    if extension != "xlog" {
        return String::from_utf8(bytes.to_vec()).unwrap_or_else(|_| Xlog::memory_dump(bytes));
    }

    let blocks = parse_blocks(bytes);
    if blocks.is_empty() {
        return Xlog::memory_dump(bytes);
    }

    let mut out = String::new();
    for (index, (header, payload)) in blocks.into_iter().enumerate() {
        if index > 0 && !out.ends_with('\n') {
            out.push('\n');
        }

        match decode_block_payload(&header, &payload) {
            Ok(plain) => out.push_str(&String::from_utf8_lossy(&plain)),
            Err(message) => {
                out.push('[');
                out.push_str(&message);
                out.push_str("]\n");
            }
        }
    }

    out
}

fn parse_blocks(bytes: &[u8]) -> Vec<(LogHeader, Vec<u8>)> {
    let mut blocks = Vec::new();
    let mut offset = 0usize;

    while offset + HEADER_LEN + TAILER_LEN <= bytes.len() {
        let Ok(header) = LogHeader::decode(&bytes[offset..offset + HEADER_LEN]) else {
            break;
        };
        let payload_len = header.len as usize;
        let payload_start = offset + HEADER_LEN;
        let payload_end = payload_start + payload_len;
        if payload_end + TAILER_LEN > bytes.len() {
            break;
        }
        if bytes[payload_end] != MAGIC_END {
            break;
        }

        blocks.push((header, bytes[payload_start..payload_end].to_vec()));
        offset = payload_end + TAILER_LEN;
    }

    blocks
}

fn decode_block_payload(header: &LogHeader, payload: &[u8]) -> Result<Vec<u8>, String> {
    match header.magic {
        MAGIC_ASYNC_NO_CRYPT_ZLIB_START => {
            decompress_raw_zlib(payload).map_err(|error| error.to_string())
        }
        MAGIC_ASYNC_NO_CRYPT_ZSTD_START => {
            decompress_zstd_frames(payload).map_err(|error| error.to_string())
        }
        MAGIC_ASYNC_ZLIB_START
        | MAGIC_ASYNC_ZSTD_START
        | MAGIC_SYNC_ZLIB_START
        | MAGIC_SYNC_ZSTD_START => Err(format!(
            "encrypted block seq={} len={} cannot be decoded without the private key",
            header.seq, header.len
        )),
        _ => Ok(payload.to_vec()),
    }
}

fn paginate_log_text(
    text: &str,
    cursor: Option<u64>,
    max_bytes: usize,
    direction: DiagnosticsPageDirection,
) -> DiagnosticsTextPage {
    if text.is_empty() {
        return paginate_text(text, cursor, max_bytes, direction);
    }

    let total_bytes = text.len();
    let max_bytes = max_bytes.max(1);

    let (start, end, next_cursor) = match direction {
        DiagnosticsPageDirection::Older => {
            let end = previous_char_boundary(text, cursor.unwrap_or(total_bytes as u64) as usize);
            let raw_start = end.saturating_sub(max_bytes);
            let start = if raw_start == 0 {
                0
            } else {
                line_start_at_or_before(text, raw_start)
            };
            let next_cursor = (start > 0).then_some(start as u64);
            (start, end, next_cursor)
        }
        DiagnosticsPageDirection::Newer => {
            let start = next_char_boundary(text, cursor.unwrap_or(0) as usize);
            let raw_end = start.saturating_add(max_bytes).min(total_bytes);
            let end = if raw_end >= total_bytes {
                total_bytes
            } else {
                line_end_at_or_after(text, raw_end)
            };
            let next_cursor = (end < total_bytes).then_some(end as u64);
            (start, end, next_cursor)
        }
    };

    DiagnosticsTextPage {
        text: text[start..end].to_string(),
        start_offset: start as u64,
        end_offset: end as u64,
        total_bytes: total_bytes as u64,
        next_cursor,
        has_more_older: start > 0,
        has_more_newer: end < total_bytes,
        is_head_aligned: start == 0,
        is_tail_aligned: end == total_bytes,
    }
}

pub(super) fn paginate_text(
    text: &str,
    cursor: Option<u64>,
    max_bytes: usize,
    direction: DiagnosticsPageDirection,
) -> DiagnosticsTextPage {
    let total_bytes = text.len();
    let max_bytes = max_bytes.max(1);

    if text.is_empty() {
        return DiagnosticsTextPage {
            text: String::new(),
            start_offset: 0,
            end_offset: 0,
            total_bytes: 0,
            next_cursor: None,
            has_more_older: false,
            has_more_newer: false,
            is_head_aligned: true,
            is_tail_aligned: true,
        };
    }

    let (start, end, next_cursor) = match direction {
        DiagnosticsPageDirection::Older => {
            let end = previous_char_boundary(text, cursor.unwrap_or(total_bytes as u64) as usize);
            let mut start = next_char_boundary(text, end.saturating_sub(max_bytes));
            if start == end && end > 0 {
                start = previous_char_boundary(text, end.saturating_sub(1));
            }
            let next_cursor = (start > 0).then_some(start as u64);
            (start, end, next_cursor)
        }
        DiagnosticsPageDirection::Newer => {
            let start = next_char_boundary(text, cursor.unwrap_or(0) as usize);
            let mut end = previous_char_boundary(text, start.saturating_add(max_bytes));
            if end == start && start < total_bytes {
                end = next_char_boundary(text, start.saturating_add(1));
            }
            let next_cursor = (end < total_bytes).then_some(end as u64);
            (start, end, next_cursor)
        }
    };

    DiagnosticsTextPage {
        text: text[start..end].to_string(),
        start_offset: start as u64,
        end_offset: end as u64,
        total_bytes: total_bytes as u64,
        next_cursor,
        has_more_older: start > 0,
        has_more_newer: end < total_bytes,
        is_head_aligned: start == 0,
        is_tail_aligned: end == total_bytes,
    }
}

fn line_start_at_or_before(text: &str, offset: usize) -> usize {
    let offset = previous_char_boundary(text, offset);
    match text[..offset].rfind('\n') {
        Some(index) => index + 1,
        None => 0,
    }
}

fn line_end_at_or_after(text: &str, offset: usize) -> usize {
    let offset = next_char_boundary(text, offset);
    match text[offset..].find('\n') {
        Some(index) => offset + index + 1,
        None => text.len(),
    }
}

fn previous_char_boundary(text: &str, offset: usize) -> usize {
    let mut offset = offset.min(text.len());
    while offset > 0 && !text.is_char_boundary(offset) {
        offset -= 1;
    }
    offset
}

fn next_char_boundary(text: &str, offset: usize) -> usize {
    let mut offset = offset.min(text.len());
    while offset < text.len() && !text.is_char_boundary(offset) {
        offset += 1;
    }
    offset
}

pub(super) fn normalized_page_bytes(requested: usize, fallback: usize) -> usize {
    match requested {
        0 => fallback,
        value => value,
    }
}

pub(super) fn is_support_bundle_path(workspace_path: &Path, path: &Path) -> bool {
    let support_bundle_root = Path::new("diagnostics").join(SUPPORT_BUNDLE_DIR_NAME);
    let feedback_bundle_root = Path::new("diagnostics").join(FEEDBACK_BUNDLE_DIR_NAME);
    path.strip_prefix(workspace_path)
        .ok()
        .is_some_and(|relative_path| {
            relative_path.starts_with(&support_bundle_root)
                || relative_path.starts_with(&feedback_bundle_root)
        })
}

pub(super) fn workspace_relative_path_string(path: &Path) -> String {
    path.iter()
        .filter_map(|component| {
            let component = component.to_string_lossy();
            (!component.is_empty() && component != ".").then(|| component.into_owned())
        })
        .collect::<Vec<_>>()
        .join("/")
}

pub(super) fn truncate_text(text: &str, max_bytes: usize) -> (String, bool) {
    if text.len() <= max_bytes {
        return (text.to_string(), false);
    }

    let mut end = max_bytes;
    while end > 0 && !text.is_char_boundary(end) {
        end -= 1;
    }

    let mut out = text[..end].to_string();
    out.push_str("\n\n<... truncated ...>");
    (out, true)
}

pub(super) fn truncate_text_prefix(text: &str, max_bytes: usize) -> (String, bool) {
    if text.len() <= max_bytes {
        return (text.to_string(), false);
    }

    let mut end = max_bytes;
    while end > 0 && !text.is_char_boundary(end) {
        end -= 1;
    }

    (text[..end].to_string(), true)
}
