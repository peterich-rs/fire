mod auth;
mod creation;
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
mod users;

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
        export_support_bundle, list_log_files, read_log_file, read_log_file_page,
        DiagnosticsPageDirection, FireDiagnosticsStore, FireLogFileDetail, FireLogFilePage,
        FireLogFileSummary, FireSupportBundleExport, FireSupportBundleHostContext,
        NetworkTraceBodyPage, NetworkTraceDetail, NetworkTraceSummary,
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
pub(crate) struct FireSessionRuntimeState {
    pub(crate) snapshot: SessionSnapshot,
    pub(crate) epoch: u64,
}

#[derive(Clone)]
pub struct FireCore {
    base_url: Url,
    workspace_path: Option<PathBuf>,
    network: network::FireNetworkLayer,
    diagnostics: Arc<FireDiagnosticsStore>,
    session: Arc<RwLock<FireSessionRuntimeState>>,
    message_bus: Arc<Mutex<messagebus::FireMessageBusRuntime>>,
    notifications: Arc<Mutex<notifications::FireNotificationRuntime>>,
    topic_presence: Arc<Mutex<presence::FireTopicPresenceRuntime>>,
    topic_timing: Arc<Mutex<interactions::FireTopicTimingRuntime>>,
}

impl FireCore {
    pub fn new(config: FireCoreConfig) -> Result<Self, FireCoreError> {
        let base_url = Url::parse(&config.base_url)?;
        let workspace_path = normalize_workspace_path(config.workspace_path);
        let diagnostics = Arc::new(FireDiagnosticsStore::new());
        if let Some(workspace_path) = workspace_path.as_deref() {
            let logger = logger_runtime_for_workspace(workspace_path)?;
            info!(
                workspace_path = %workspace_path.display(),
                diagnostic_session_id = %diagnostics.diagnostic_session_id(),
                log_dir = %logger.log_dir.display(),
                cache_dir = %logger.cache_dir.display(),
                "initialized fire workspace logging"
            );
        }
        let session = FireSessionRuntimeState {
            snapshot: SessionSnapshot {
                cookies: CookieSnapshot::default(),
                bootstrap: BootstrapArtifacts {
                    base_url: base_url.as_str().to_string(),
                    ..BootstrapArtifacts::default()
                },
                browser_user_agent: None,
            },
            epoch: 1,
        };
        let session = Arc::new(RwLock::new(session));
        let cookie_jar = Arc::new(FireSessionCookieJar::new(base_url.clone(), session.clone()));
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

    pub fn diagnostic_session_id(&self) -> String {
        self.diagnostics.diagnostic_session_id().to_string()
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
        log_host_message(
            level,
            target.as_ref(),
            message.as_ref(),
            Some(self.diagnostics.diagnostic_session_id()),
        );
    }

    pub fn snapshot(&self) -> SessionSnapshot {
        read_rwlock(&self.session, "session").snapshot.clone()
    }

    pub(crate) fn snapshot_with_epoch(&self) -> (SessionSnapshot, u64) {
        let state = read_rwlock(&self.session, "session");
        (state.snapshot.clone(), state.epoch)
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

    pub fn read_log_file_page(
        &self,
        relative_path: impl AsRef<Path>,
        cursor: Option<u64>,
        max_bytes: usize,
        direction: DiagnosticsPageDirection,
    ) -> Result<FireLogFilePage, FireCoreError> {
        self.flush_logs(true);
        let workspace_path = self
            .workspace_path()
            .ok_or(FireCoreError::MissingWorkspacePath)?;
        read_log_file_page(workspace_path, relative_path, cursor, max_bytes, direction)
    }

    pub fn list_network_traces(&self, limit: usize) -> Vec<NetworkTraceSummary> {
        self.diagnostics.summaries(limit)
    }

    pub fn network_trace_detail(&self, trace_id: u64) -> Option<NetworkTraceDetail> {
        self.diagnostics.detail(trace_id)
    }

    pub fn network_trace_body_page(
        &self,
        trace_id: u64,
        cursor: Option<u64>,
        max_bytes: usize,
        direction: DiagnosticsPageDirection,
    ) -> Option<NetworkTraceBodyPage> {
        self.diagnostics
            .network_trace_body_page(trace_id, cursor, max_bytes, direction)
    }

    pub fn export_support_bundle(
        &self,
        host_context: FireSupportBundleHostContext,
    ) -> Result<FireSupportBundleExport, FireCoreError> {
        self.flush_logs(true);
        let workspace_path = self
            .workspace_path()
            .ok_or(FireCoreError::MissingWorkspacePath)?;
        let session_json = self.export_session_json()?;
        export_support_bundle(
            workspace_path,
            &self.diagnostics,
            &session_json,
            &host_context,
        )
    }

    pub(crate) fn update_session<F>(&self, mutate: F) -> SessionSnapshot
    where
        F: FnOnce(&mut SessionSnapshot),
    {
        let snapshot = {
            let mut session = write_rwlock(&self.session, "session");
            mutate(&mut session.snapshot);
            session.snapshot.clone()
        };
        notifications::reconcile_notification_runtime(&self.notifications, &snapshot);
        presence::reconcile_topic_presence_runtime(&self.topic_presence, &snapshot);
        snapshot
    }

    pub(crate) fn update_session_advancing_epoch_if_auth_changed<F>(
        &self,
        reason: &'static str,
        mutate: F,
    ) -> SessionSnapshot
    where
        F: FnOnce(&mut SessionSnapshot),
    {
        let snapshot = {
            let mut session = write_rwlock(&self.session, "session");
            let before = auth_cookie_epoch_key(&session.snapshot);
            mutate(&mut session.snapshot);
            let after = auth_cookie_epoch_key(&session.snapshot);
            if before != after {
                session.epoch = session.epoch.saturating_add(1);
                info!(
                    session_epoch = session.epoch,
                    reason, "advanced session epoch"
                );
            }
            session.snapshot.clone()
        };
        notifications::reconcile_notification_runtime(&self.notifications, &snapshot);
        presence::reconcile_topic_presence_runtime(&self.topic_presence, &snapshot);
        snapshot
    }
}

fn auth_cookie_epoch_key(snapshot: &SessionSnapshot) -> (Option<String>, Option<String>) {
    (
        snapshot.cookies.t_token.clone(),
        snapshot.cookies.forum_session.clone(),
    )
}
