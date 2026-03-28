use std::{
    fs, io,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use fire_models::{BootstrapArtifacts, CookieSnapshot, SessionSnapshot};
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

#[derive(Debug, Deserialize)]
pub(crate) struct LegacyPersistedSessionSnapshot {
    pub(crate) cookies: LegacyCookieSnapshot,
    pub(crate) bootstrap: LegacyBootstrapArtifacts,
}

impl From<LegacyPersistedSessionSnapshot> for SessionSnapshot {
    fn from(value: LegacyPersistedSessionSnapshot) -> Self {
        Self {
            cookies: value.cookies.into(),
            bootstrap: value.bootstrap.into(),
        }
    }
}

#[derive(Debug, Deserialize)]
pub(crate) struct LegacyCookieSnapshot {
    #[serde(alias = "tToken")]
    pub(crate) t_token: Option<String>,
    #[serde(alias = "forumSession")]
    pub(crate) forum_session: Option<String>,
    #[serde(alias = "cfClearance")]
    pub(crate) cf_clearance: Option<String>,
    #[serde(alias = "csrfToken")]
    pub(crate) csrf_token: Option<String>,
}

impl From<LegacyCookieSnapshot> for CookieSnapshot {
    fn from(value: LegacyCookieSnapshot) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
            cf_clearance: value.cf_clearance,
            csrf_token: value.csrf_token,
        }
    }
}

#[derive(Debug, Deserialize)]
pub(crate) struct LegacyBootstrapArtifacts {
    #[serde(alias = "baseUrl")]
    pub(crate) base_url: String,
    #[serde(alias = "discourseBaseUri")]
    pub(crate) discourse_base_uri: Option<String>,
    #[serde(alias = "sharedSessionKey")]
    pub(crate) shared_session_key: Option<String>,
    #[serde(alias = "currentUsername")]
    pub(crate) current_username: Option<String>,
    #[serde(alias = "longPollingBaseUrl")]
    pub(crate) long_polling_base_url: Option<String>,
    #[serde(alias = "turnstileSitekey")]
    pub(crate) turnstile_sitekey: Option<String>,
    #[serde(alias = "topicTrackingStateMeta")]
    pub(crate) topic_tracking_state_meta: Option<String>,
    #[serde(alias = "preloadedJson")]
    pub(crate) preloaded_json: Option<String>,
    #[serde(default, alias = "hasPreloadedData")]
    pub(crate) has_preloaded_data: bool,
}

impl From<LegacyBootstrapArtifacts> for BootstrapArtifacts {
    fn from(value: LegacyBootstrapArtifacts) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
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
