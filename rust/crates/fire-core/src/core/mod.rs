mod auth;
mod interactions;
mod messagebus;
mod network;
mod notifications;
mod persistence;
mod session;
mod topics;

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex, RwLock},
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
        FireNetworkTraceEventListenerFactory, NetworkTraceDetail, NetworkTraceSummary,
    },
    error::FireCoreError,
    logging::logger_runtime_for_workspace,
    sync_utils::{read_rwlock, write_rwlock},
    workspace::{normalize_workspace_path, validate_workspace_relative_path},
};
use std::time::Duration;

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
    client: Client,
    message_bus_client: Client,
    diagnostics: Arc<FireDiagnosticsStore>,
    session: Arc<RwLock<SessionSnapshot>>,
    message_bus: Arc<Mutex<messagebus::FireMessageBusRuntime>>,
    notifications: Arc<Mutex<notifications::FireNotificationRuntime>>,
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
        let diagnostics = Arc::new(FireDiagnosticsStore::new());
        let mut client_builder = Client::builder()
            .cookie_jar(Arc::clone(&cookie_jar))
            .application_interceptor(network::FireCommonHeaderInterceptor::new(
                base_url.clone(),
                Arc::clone(&session),
            ))
            .connect_timeout(NETWORK_CONNECT_TIMEOUT)
            .call_timeout(NETWORK_CALL_TIMEOUT)
            .max_connections_per_host(CLIENT_MAX_CONNECTIONS_PER_HOST)
            .pool_max_idle_per_host(CLIENT_POOL_MAX_IDLE_PER_HOST)
            .event_listener_factory(FireNetworkTraceEventListenerFactory::new(Arc::clone(
                &diagnostics,
            )));
        #[cfg(debug_assertions)]
        {
            client_builder = client_builder.use_system_proxy(true);
        }
        let client = client_builder
            .build()
            .map_err(|source| FireCoreError::ClientBuild { source })?;

        let mut message_bus_client_builder = Client::builder()
            .cookie_jar(cookie_jar)
            .application_interceptor(network::FireCommonHeaderInterceptor::new(
                base_url.clone(),
                Arc::clone(&session),
            ))
            .connect_timeout(NETWORK_CONNECT_TIMEOUT)
            .call_timeout(MESSAGE_BUS_CALL_TIMEOUT)
            .max_connections_per_host(CLIENT_MAX_CONNECTIONS_PER_HOST)
            .pool_max_idle_per_host(CLIENT_POOL_MAX_IDLE_PER_HOST)
            .http2_keep_alive_interval(MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL)
            .http2_keep_alive_while_idle(true)
            .event_listener_factory(FireNetworkTraceEventListenerFactory::new(Arc::clone(
                &diagnostics,
            )));
        #[cfg(debug_assertions)]
        {
            message_bus_client_builder = message_bus_client_builder.use_system_proxy(true);
        }
        let message_bus_client = message_bus_client_builder
            .build()
            .map_err(|source| FireCoreError::ClientBuild { source })?;

        Ok(Self {
            base_url,
            workspace_path,
            client,
            message_bus_client,
            diagnostics,
            session,
            message_bus: Arc::new(Mutex::new(messagebus::FireMessageBusRuntime::default())),
            notifications: Arc::new(Mutex::new(notifications::FireNotificationRuntime::default())),
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
        read_rwlock(&self.session, "session").clone()
    }

    pub fn shared_client(&self) -> Client {
        self.client.clone()
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
        snapshot
    }
}
