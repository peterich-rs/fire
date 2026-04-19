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

type FireAuthKey = (Option<String>, Option<String>);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FireAuthRecoveryHintReason {
    TOnlyRotation,
    ForumSessionOnlyRotation,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FireAuthRecoveryHint {
    pub observed_epoch: u64,
    pub reason: FireAuthRecoveryHintReason,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FireSessionPersistenceState {
    pub snapshot_revision: u64,
    pub auth_cookie_revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum FireAuthChangeSource {
    DirectMutation,
    PlatformSync,
    NetworkIngress,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum FireAuthRotation {
    TOnly,
    ForumSessionOnly,
    Both,
}

impl FireAuthRotation {
    fn recovery_hint_reason(self) -> Option<FireAuthRecoveryHintReason> {
        match self {
            Self::TOnly => Some(FireAuthRecoveryHintReason::TOnlyRotation),
            Self::ForumSessionOnly => Some(FireAuthRecoveryHintReason::ForumSessionOnlyRotation),
            Self::Both => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct FireResponseAuthChange {
    pub(crate) request_trace_id: u64,
    pub(crate) observed_epoch: u64,
}

#[derive(Clone)]
pub(crate) struct FireSessionRuntimeState {
    pub(crate) snapshot: SessionSnapshot,
    pub(crate) epoch: u64,
    pub(crate) snapshot_revision: u64,
    pub(crate) auth_cookie_revision: u64,
    pub(crate) auth_recovery_hint: Option<FireAuthRecoveryHint>,
    pub(crate) last_response_auth_change: Option<FireResponseAuthChange>,
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
            snapshot_revision: 1,
            auth_cookie_revision: 1,
            auth_recovery_hint: None,
            last_response_auth_change: None,
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

    pub(crate) fn current_session_epoch(&self) -> u64 {
        read_rwlock(&self.session, "session").epoch
    }

    pub fn session_epoch(&self) -> u64 {
        self.current_session_epoch()
    }

    pub fn session_persistence_state(&self) -> FireSessionPersistenceState {
        let state = read_rwlock(&self.session, "session");
        FireSessionPersistenceState {
            snapshot_revision: state.snapshot_revision,
            auth_cookie_revision: state.auth_cookie_revision,
        }
    }

    pub fn auth_recovery_hint(&self) -> Option<FireAuthRecoveryHint> {
        read_rwlock(&self.session, "session").auth_recovery_hint
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
            let before_snapshot = session.snapshot.clone();
            mutate(&mut session.snapshot);
            update_session_persistence_revisions(&mut session, &before_snapshot);
            session.snapshot.clone()
        };
        notifications::reconcile_notification_runtime(&self.notifications, &snapshot);
        presence::reconcile_topic_presence_runtime(&self.topic_presence, &snapshot);
        snapshot
    }

    pub(crate) fn update_session_advancing_epoch_if_auth_changed<F>(
        &self,
        reason: &'static str,
        source: FireAuthChangeSource,
        mutate: F,
    ) -> SessionSnapshot
    where
        F: FnOnce(&mut SessionSnapshot),
    {
        let snapshot = {
            let mut session = write_rwlock(&self.session, "session");
            mutate_runtime_session_tracking_auth_change(&mut session, source, reason, mutate);
            session.snapshot.clone()
        };
        notifications::reconcile_notification_runtime(&self.notifications, &snapshot);
        presence::reconcile_topic_presence_runtime(&self.topic_presence, &snapshot);
        snapshot
    }

    pub(crate) fn clear_auth_recovery_hint(&self, reason: &'static str) {
        let cleared_hint = {
            let mut session = write_rwlock(&self.session, "session");
            session.auth_recovery_hint.take()
        };
        if let Some(cleared_hint) = cleared_hint {
            info!(
                reason,
                observed_epoch = cleared_hint.observed_epoch,
                auth_recovery_hint = ?cleared_hint.reason,
                "cleared auth recovery hint"
            );
        }
    }
}

pub(crate) fn mutate_runtime_session_tracking_auth_change<F>(
    session: &mut FireSessionRuntimeState,
    source: FireAuthChangeSource,
    reason: &'static str,
    mutate: F,
) where
    F: FnOnce(&mut SessionSnapshot),
{
    let before_snapshot = session.snapshot.clone();
    let before = auth_cookie_epoch_key(&before_snapshot);
    let before_csrf = before_snapshot.cookies.csrf_token.clone();
    mutate(&mut session.snapshot);
    update_session_persistence_revisions(session, &before_snapshot);
    let after = auth_cookie_epoch_key(&session.snapshot);
    if before == after {
        return;
    }

    let rotation = classify_auth_rotation(&before, &after);
    let stale_csrf_cleared =
        before_csrf.is_some() && session.snapshot.cookies.csrf_token == before_csrf;
    if stale_csrf_cleared {
        session.snapshot.cookies.csrf_token = None;
    }
    session.epoch = session.epoch.saturating_add(1);
    session.auth_recovery_hint = match (source, rotation.recovery_hint_reason()) {
        (FireAuthChangeSource::NetworkIngress, Some(reason)) => Some(FireAuthRecoveryHint {
            observed_epoch: session.epoch,
            reason,
        }),
        _ => None,
    };
    session.last_response_auth_change = if source == FireAuthChangeSource::NetworkIngress {
        crate::cookies::FIRE_REQUEST_TRACE_ID
            .try_with(|trace_id| FireResponseAuthChange {
                request_trace_id: *trace_id,
                observed_epoch: session.epoch,
            })
            .ok()
    } else {
        None
    };
    info!(
        session_epoch = session.epoch,
        source = ?source,
        auth_rotation = ?rotation,
        stale_csrf_cleared,
        auth_recovery_hint = ?session.auth_recovery_hint,
        reason,
        "processed auth rotation"
    );
}

fn auth_cookie_epoch_key(snapshot: &SessionSnapshot) -> FireAuthKey {
    (
        snapshot.cookies.t_token.clone(),
        snapshot.cookies.forum_session.clone(),
    )
}

fn update_session_persistence_revisions(
    session: &mut FireSessionRuntimeState,
    before_snapshot: &SessionSnapshot,
) {
    if session.snapshot != *before_snapshot {
        session.snapshot_revision = session.snapshot_revision.saturating_add(1);
    }

    if auth_cookie_persistence_changed(before_snapshot, &session.snapshot) {
        session.auth_cookie_revision = session.auth_cookie_revision.saturating_add(1);
    }
}

fn auth_cookie_persistence_changed(
    before_snapshot: &SessionSnapshot,
    after_snapshot: &SessionSnapshot,
) -> bool {
    before_snapshot.cookies.t_token != after_snapshot.cookies.t_token
        || before_snapshot.cookies.forum_session != after_snapshot.cookies.forum_session
        || before_snapshot.cookies.cf_clearance != after_snapshot.cookies.cf_clearance
        || before_snapshot.cookies.platform_cookies != after_snapshot.cookies.platform_cookies
}

fn classify_auth_rotation(before: &FireAuthKey, after: &FireAuthKey) -> FireAuthRotation {
    let t_changed = before.0 != after.0;
    let forum_session_changed = before.1 != after.1;
    match (t_changed, forum_session_changed) {
        (true, false) => FireAuthRotation::TOnly,
        (false, true) => FireAuthRotation::ForumSessionOnly,
        _ => FireAuthRotation::Both,
    }
}
