use std::{fs, io, path::Path};

use tracing::debug;

use super::FireCore;
use crate::{
    error::FireCoreError,
    session_store::{sanitize_snapshot_for_restore, write_atomic, PersistedSessionEnvelope},
};

impl FireCore {
    pub fn export_session_json(&self) -> Result<String, FireCoreError> {
        let envelope = PersistedSessionEnvelope::new(self.snapshot());
        serde_json::to_string_pretty(&envelope).map_err(FireCoreError::PersistSerialize)
    }

    pub fn restore_session_json(
        &self,
        json: String,
    ) -> Result<fire_models::SessionSnapshot, FireCoreError> {
        let envelope: PersistedSessionEnvelope =
            serde_json::from_str(&json).map_err(FireCoreError::PersistDeserialize)?;
        let snapshot = self.normalize_persisted_snapshot(envelope)?;
        Ok(self.update_session(|session| {
            *session = snapshot.clone();
            debug!(
                phase = ?session.login_phase(),
                readiness = ?session.readiness(),
                "restored persisted session from json"
            );
        }))
    }

    pub fn save_session_to_path(&self, path: impl AsRef<Path>) -> Result<(), FireCoreError> {
        let path = path.as_ref();
        let payload = self.export_session_json()?;
        write_atomic(path, payload.as_bytes()).map_err(|source| FireCoreError::PersistIo {
            path: path.to_path_buf(),
            source,
        })
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

    fn normalize_persisted_snapshot(
        &self,
        envelope: PersistedSessionEnvelope,
    ) -> Result<fire_models::SessionSnapshot, FireCoreError> {
        if envelope.version != PersistedSessionEnvelope::CURRENT_VERSION {
            return Err(FireCoreError::PersistVersionMismatch {
                expected: PersistedSessionEnvelope::CURRENT_VERSION,
                found: envelope.version,
            });
        }

        let mut snapshot = envelope.snapshot;
        let persisted_base_url = snapshot.bootstrap.base_url.clone();
        if !persisted_base_url.is_empty() && persisted_base_url != self.base_url() {
            return Err(FireCoreError::PersistBaseUrlMismatch {
                expected: self.base_url().to_string(),
                found: persisted_base_url,
            });
        }

        snapshot = sanitize_snapshot_for_restore(self.base_url(), snapshot);
        Ok(snapshot)
    }
}
