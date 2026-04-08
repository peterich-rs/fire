mod auth;
mod interactions;
mod messagebus;
mod network;
mod notifications;
mod persistence;
mod presence;
mod rate_limit;
mod search;
mod session;
mod topics;

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex, RwLock},
    time::Duration,
};

use fire_models::{BootstrapArtifacts, CookieSnapshot, SessionSnapshot};
use openwire::Client;
use tracing::info;
use url::Url;

use crate::{
    config::FireCoreConfig,
    cookies::FireSessionCookieJar,
    diagnostics::{
        list_log_files, read_log_file, FireDiagnosticsStore, FireLogFileDetail, FireLogFileSummary,
        NetworkTraceDetail, NetworkTraceSummary,
    },
    error::FireCoreError,
    logging::{log_host_message, logger_runtime_for_workspace, FireHostLogLevel},
    sync_utils::{read_rwlock, write_rwlock},
    workspace::{normalize_workspace_path, validate_workspace_relative_path},
};

const NETWORK_CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const NETWORK_CALL_TIMEOUT: Duration = Duration::from_secs(30);
const MESSAGE_BUS_CALL_TIMEOUT: Duration = Duration::from_secs(75);
const CLIENT_MAX_CONNECTIONS_PER_HOST: usize = 8;
const CLIENT_POOL_MAX_IDLE_PER_HOST: usize = 4;
const MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Clone)]
pub struct FireCore {
    base_url: Url,
    workspace_path: Option<PathBuf>,
    network: network::FireNetworkLayer,
    diagnostics: Arc<FireDiagnosticsStore>,
    session: Arc<RwLock<SessionSnapshot>>,
    message_bus: Arc<Mutex<messagebus::FireMessageBusRuntime>>,
    notifications: Arc<Mutex<notifications::FireNotificationRuntime>>,
    topic_presence: Arc<Mutex<presence::FireTopicPresenceRuntime>>,
    topic_timing: Arc<Mutex<interactions::FireTopicTimingRuntime>>,
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
            browser_user_agent: None,
        };
        let session = Arc::new(RwLock::new(session));
        let cookie_jar = Arc::new(FireSessionCookieJar::new(base_url.clone(), session.clone()));
        let diagnostics = Arc::new(FireDiagnosticsStore::new());
        let network = network::FireNetworkLayer::new(
            &base_url,
            Arc::clone(&session),
            Arc::clone(&diagnostics),
            cookie_jar,
        )?;

        Ok(Self {
            base_url,
            workspace_path,
            network,
            diagnostics,
            session,
            message_bus: Arc::new(Mutex::new(messagebus::FireMessageBusRuntime::default())),
            notifications: Arc::new(Mutex::new(notifications::FireNotificationRuntime::default())),
            topic_presence: Arc::new(Mutex::new(presence::FireTopicPresenceRuntime::default())),
            topic_timing: Arc::new(Mutex::new(interactions::FireTopicTimingRuntime::default())),
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

    pub fn log_host(
        &self,
        level: FireHostLogLevel,
        target: impl AsRef<str>,
        message: impl AsRef<str>,
    ) {
        if let Some(workspace_path) = self.workspace_path() {
            let _ = logger_runtime_for_workspace(workspace_path);
        }
        log_host_message(level, target.as_ref(), message.as_ref());
    }

    pub fn snapshot(&self) -> SessionSnapshot {
        read_rwlock(&self.session, "session").clone()
    }

    pub fn shared_client(&self) -> Client {
        self.network.client()
    }

    pub fn list_log_files(&self) -> Result<Vec<FireLogFileSummary>, FireCoreError> {
        self.flush_logs(true);
        let workspace_path = self
            .workspace_path()
            .ok_or(FireCoreError::MissingWorkspacePath)?;
        list_log_files(workspace_path)
    }

    pub fn read_log_file(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<FireLogFileDetail, FireCoreError> {
        self.flush_logs(true);
        let workspace_path = self
            .workspace_path()
            .ok_or(FireCoreError::MissingWorkspacePath)?;
        read_log_file(workspace_path, relative_path)
    }

    pub fn list_network_traces(&self, limit: usize) -> Vec<NetworkTraceSummary> {
        self.diagnostics.summaries(limit)
    }

    pub fn network_trace_detail(&self, trace_id: u64) -> Option<NetworkTraceDetail> {
        self.diagnostics.detail(trace_id)
    }

    pub(crate) fn update_session<F>(&self, mutate: F) -> SessionSnapshot
    where
        F: FnOnce(&mut SessionSnapshot),
    {
        let snapshot = {
            let mut session = write_rwlock(&self.session, "session");
            mutate(&mut session);
            session.clone()
        };
        notifications::reconcile_notification_runtime(&self.notifications, &snapshot);
        presence::reconcile_topic_presence_runtime(&self.topic_presence, &snapshot);
        snapshot
    }
}
