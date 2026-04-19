use std::{fs, io, path::Path};

use tracing::{debug, warn};

use super::{notifications, presence, update_session_persistence_revisions, FireCore};
use crate::{
    error::FireCoreError,
    session_store::{
        sanitize_snapshot_for_restore, write_atomic, LegacyPersistedSessionSnapshot,
        PersistedSessionEnvelope,
    },
    sync_utils::write_rwlock,
};

impl FireCore {
    pub fn export_session_json(&self) -> Result<String, FireCoreError> {
        let envelope = PersistedSessionEnvelope::new(self.snapshot());
        serde_json::to_string_pretty(&envelope).map_err(FireCoreError::PersistSerialize)
    }

    pub fn export_redacted_session_json(&self) -> Result<String, FireCoreError> {
        self.export_session_json()
    }

    pub fn restore_session_json(
        &self,
        json: String,
    ) -> Result<fire_models::SessionSnapshot, FireCoreError> {
        let snapshot = self.decode_persisted_snapshot(&json)?;
        self.clear_notification_state();
        self.clear_topic_presence_state();
        let snapshot = {
            let mut session = write_rwlock(&self.session, "session");
            let before_snapshot = session.snapshot.clone();
            session.snapshot = snapshot;
            update_session_persistence_revisions(&mut session, &before_snapshot);
            session.auth_recovery_hint = None;
            session.last_response_auth_change = None;
            debug!(
                phase = ?session.snapshot.login_phase(),
                readiness = ?session.snapshot.readiness(),
                "restored persisted session from json"
            );
            session.snapshot.clone()
        };
        notifications::reconcile_notification_runtime(&self.notifications, &snapshot);
        presence::reconcile_topic_presence_runtime(&self.topic_presence, &snapshot);
        Ok(snapshot)
    }

    pub fn save_session_to_path(&self, path: impl AsRef<Path>) -> Result<(), FireCoreError> {
        let path = path.as_ref();
        let payload = self.export_session_json()?;
        write_atomic(path, payload.as_bytes()).map_err(|source| FireCoreError::PersistIo {
            path: path.to_path_buf(),
            source,
        })
    }

    pub fn save_redacted_session_to_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<(), FireCoreError> {
        self.save_session_to_path(path)
    }

    pub fn load_session_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<fire_models::SessionSnapshot, FireCoreError> {
        let path = path.as_ref();
        let payload = fs::read_to_string(path).map_err(|source| FireCoreError::PersistIo {
            path: path.to_path_buf(),
            source,
        })?;
        let snapshot = self.restore_session_json(payload)?;
        debug!(path = %path.display(), "restored persisted session from path");
        Ok(snapshot)
    }

    pub fn clear_session_path(&self, path: impl AsRef<Path>) -> Result<(), FireCoreError> {
        let path = path.as_ref();
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(source) => Err(FireCoreError::PersistIo {
                path: path.to_path_buf(),
                source,
            }),
        }
    }

    fn decode_persisted_snapshot(
        &self,
        json: &str,
    ) -> Result<fire_models::SessionSnapshot, FireCoreError> {
        match serde_json::from_str::<PersistedSessionEnvelope>(json) {
            Ok(envelope) => self.normalize_persisted_snapshot(envelope),
            Err(envelope_error) => {
                let legacy_snapshot: LegacyPersistedSessionSnapshot = serde_json::from_str(json)
                    .map_err(|_| FireCoreError::PersistDeserialize(envelope_error))?;
                warn!("restoring legacy persisted session without envelope metadata");
                self.normalize_snapshot_for_restore(legacy_snapshot.into(), false)
            }
        }
    }

    fn normalize_persisted_snapshot(
        &self,
        envelope: PersistedSessionEnvelope,
    ) -> Result<fire_models::SessionSnapshot, FireCoreError> {
        if envelope.version != PersistedSessionEnvelope::FULL_SNAPSHOT_VERSION
            && envelope.version != PersistedSessionEnvelope::REDACTED_SNAPSHOT_VERSION
        {
            return Err(FireCoreError::PersistVersionMismatch {
                expected: PersistedSessionEnvelope::REDACTED_SNAPSHOT_VERSION,
                found: envelope.version,
            });
        }

        self.normalize_snapshot_for_restore(envelope.snapshot, envelope.auth_cookies_redacted)
    }

    fn normalize_snapshot_for_restore(
        &self,
        mut snapshot: fire_models::SessionSnapshot,
        auth_cookies_redacted: bool,
    ) -> Result<fire_models::SessionSnapshot, FireCoreError> {
        let persisted_base_url = snapshot.bootstrap.base_url.clone();
        if !persisted_base_url.is_empty() && persisted_base_url != self.base_url() {
            return Err(FireCoreError::PersistBaseUrlMismatch {
                expected: self.base_url().to_string(),
                found: persisted_base_url,
            });
        }

        snapshot = sanitize_snapshot_for_restore(self.base_url(), snapshot, auth_cookies_redacted);
        Ok(snapshot)
    }
}
