use std::{
    fs, io,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use fire_models::SessionSnapshot;
use serde::{Deserialize, Serialize};

use crate::parsing::hydrate_preloaded_fields;

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct PersistedSessionEnvelope {
    pub(crate) version: u32,
    pub(crate) saved_at_unix_ms: u64,
    pub(crate) snapshot: SessionSnapshot,
}

impl PersistedSessionEnvelope {
    pub(crate) const CURRENT_VERSION: u32 = 1;

    pub(crate) fn new(snapshot: SessionSnapshot) -> Self {
        Self {
            version: Self::CURRENT_VERSION,
            saved_at_unix_ms: now_unix_ms(),
            snapshot,
        }
    }
}

pub(crate) fn sanitize_snapshot_for_restore(
    base_url: &str,
    mut snapshot: SessionSnapshot,
) -> SessionSnapshot {
    snapshot.bootstrap.base_url = base_url.to_string();

    normalize_option(&mut snapshot.cookies.t_token);
    normalize_option(&mut snapshot.cookies.forum_session);
    normalize_option(&mut snapshot.cookies.cf_clearance);
    normalize_option(&mut snapshot.cookies.csrf_token);

    normalize_option(&mut snapshot.bootstrap.discourse_base_uri);
    normalize_option(&mut snapshot.bootstrap.shared_session_key);
    normalize_option(&mut snapshot.bootstrap.current_username);
    normalize_option(&mut snapshot.bootstrap.long_polling_base_url);
    normalize_option(&mut snapshot.bootstrap.turnstile_sitekey);
    normalize_option(&mut snapshot.bootstrap.topic_tracking_state_meta);
    normalize_option(&mut snapshot.bootstrap.preloaded_json);

    if let Some(preloaded_json) = snapshot.bootstrap.preloaded_json.clone() {
        snapshot.bootstrap.has_preloaded_data = true;
        hydrate_preloaded_fields(&preloaded_json, &mut snapshot.bootstrap);
    } else {
        snapshot.bootstrap.has_preloaded_data = false;
    }

    if !snapshot.cookies.can_authenticate_requests() {
        snapshot.clear_login_state(true);
        snapshot.bootstrap.base_url = base_url.to_string();
    }

    snapshot
}

fn normalize_option(slot: &mut Option<String>) {
    if slot.as_ref().is_some_and(|value| value.is_empty()) {
        *slot = None;
    }
}

pub(crate) fn write_atomic(path: &Path, contents: &[u8]) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let temp_path = temp_path_for(path);
    fs::write(&temp_path, contents)?;

    if path.exists() {
        fs::remove_file(path)?;
    }

    fs::rename(temp_path, path)
}

fn temp_path_for(path: &Path) -> PathBuf {
    let millis = now_unix_ms();
    let pid = std::process::id();
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .map_or_else(|| "fire-session".to_string(), ToOwned::to_owned);
    path.with_file_name(format!("{file_name}.{pid}.{millis}.tmp"))
}

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_millis() as u64)
}
