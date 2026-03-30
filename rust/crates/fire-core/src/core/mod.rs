mod auth;
mod message_bus;
mod network;
mod persistence;
mod session;
mod topics;

use std::{
    path::{Path, PathBuf},
    sync::{Arc, RwLock},
};

use fire_models::{BootstrapArtifacts, CookieSnapshot, SessionSnapshot};
use openwire::Client;
use tracing::info;
use url::Url;

use crate::{
    config::FireCoreConfig,
    cookies::FireSessionCookieJar,
    error::FireCoreError,
    logging::logger_runtime_for_workspace,
    workspace::{normalize_workspace_path, validate_workspace_relative_path},
};

#[derive(Clone)]
pub struct FireCore {
    base_url: Url,
    workspace_path: Option<PathBuf>,
    client: Client,
    session: Arc<RwLock<SessionSnapshot>>,
}

impl FireCore {
    pub fn new(config: FireCoreConfig) -> Result<Self, FireCoreError> {
        let base_url = Url::parse(&config.base_url)?;
        let workspace_path = normalize_workspace_path(config.workspace_path);
        if let Some(workspace_path) = workspace_path.as_deref() {
            let logger = logger_runtime_for_workspace(workspace_path)?;
            info!(
                workspace_path = %workspace_path.display(),
                log_dir = %logger.log_dir.display(),
                cache_dir = %logger.cache_dir.display(),
                "initialized fire workspace logging"
            );
        }
        let session = SessionSnapshot {
            cookies: CookieSnapshot::default(),
            bootstrap: BootstrapArtifacts {
                base_url: base_url.as_str().to_string(),
                ..BootstrapArtifacts::default()
            },
        };
        let session = Arc::new(RwLock::new(session));
        let cookie_jar = Arc::new(FireSessionCookieJar::new(base_url.clone(), session.clone()));
        let client = Client::builder()
            .cookie_jar(cookie_jar)
            .build()
            .map_err(|source| FireCoreError::ClientBuild { source })?;

        Ok(Self {
            base_url,
            workspace_path,
            client,
            session,
        })
    }

    pub fn base_url(&self) -> &str {
        self.base_url.as_str()
    }

    pub fn workspace_path(&self) -> Option<&Path> {
        self.workspace_path.as_deref()
    }

    pub fn resolve_workspace_path(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<PathBuf, FireCoreError> {
        let workspace_path = self
            .workspace_path()
            .ok_or(FireCoreError::MissingWorkspacePath)?;
        validate_workspace_relative_path(relative_path.as_ref())?;
        Ok(workspace_path.join(relative_path))
    }

    pub fn flush_logs(&self, sync: bool) {
        if let Some(workspace_path) = self.workspace_path() {
            if let Ok(runtime) = logger_runtime_for_workspace(workspace_path) {
                runtime.flush(sync);
            }
        }
    }

    pub fn snapshot(&self) -> SessionSnapshot {
        self.session.read().expect("session poisoned").clone()
    }

    pub fn shared_client(&self) -> Client {
        self.client.clone()
    }

    pub(crate) fn update_session<F>(&self, mutate: F) -> SessionSnapshot
    where
        F: FnOnce(&mut SessionSnapshot),
    {
        let mut session = self.session.write().expect("session poisoned");
        mutate(&mut session);
        session.clone()
    }
}
