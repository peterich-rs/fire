mod auth;
mod auth_strike;
mod cdk;
mod cf_challenge;
mod cookie_healing;
mod creation;
mod interactions;
mod ldc;
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
    fs,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock, RwLock},
    time::Duration,
};

use fire_models::{
    AuthRuntimeSignal, BootstrapArtifacts, CookieSnapshot, HomeTopicListScope, SessionSnapshot,
    TopicListQuery,
};
use fire_store::FireStore;
use openwire::Client;
use sha1::{Digest, Sha1};
use tokio::sync::Mutex as TokioMutex;
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
    state_observer::FireStateObserverRegistry,
    sync_utils::{read_rwlock, write_rwlock},
    workspace::{normalize_workspace_path, validate_workspace_relative_path},
};

const NETWORK_CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const NETWORK_CALL_TIMEOUT: Duration = Duration::from_secs(30);
const MESSAGE_BUS_CALL_TIMEOUT: Duration = Duration::from_secs(35);
const CLIENT_MAX_CONNECTIONS_PER_HOST: usize = 8;
const CLIENT_POOL_MAX_IDLE_PER_HOST: usize = 4;
const MESSAGE_BUS_HTTP2_KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(30);

type FireAuthKey = (Option<String>, Option<String>);
const FIRE_STORE_DIR_NAME: &str = "cache";
const FIRE_SHARED_STORE_FILE_NAME: &str = "fire-cache.sqlite3";

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

fn open_shared_store(workspace_path: Option<&Path>) -> Result<FireStore, FireCoreError> {
    let Some(workspace_path) = workspace_path else {
        return Ok(FireStore::open_in_memory()?);
    };

    let cache_dir = workspace_path.join(FIRE_STORE_DIR_NAME);
    fs::create_dir_all(&cache_dir).map_err(|source| FireCoreError::WorkspaceIo {
        path: cache_dir.clone(),
        source,
    })?;
    Ok(FireStore::open(
        cache_dir.join(FIRE_SHARED_STORE_FILE_NAME),
    )?)
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
    pub(crate) auth_strike: auth_strike::AuthStrikeState,
    pub(crate) last_auth_runtime_signal: Option<AuthRuntimeSignal>,
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
    topic_detail_source: Arc<Mutex<topics::FireTopicDetailSourceRuntime>>,
    pub(crate) shared_store: Arc<Mutex<FireStore>>,
    home_topic_list_scope: Arc<Mutex<HomeTopicListScope>>,
    state_observers: FireStateObserverRegistry,
    csrf_refresh: Arc<TokioMutex<()>>,
    cloudflare_challenge_handler: cf_challenge::FireCloudflareChallengeHandlerRegistry,
    cloudflare_challenge_runtime: Arc<Mutex<cf_challenge::FireCloudflareChallengeRuntime>>,
    cookie_self_healing_handler: cookie_healing::FireCookieSelfHealingHandlerRegistry,
    preloaded_data: OnceLock<Arc<crate::preloaded_data::PreloadedDataService>>,
    app_state_refresher: OnceLock<Arc<crate::app_state_refresher::AppStateRefresher>>,
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
            auth_strike: auth_strike::AuthStrikeState::default(),
            last_auth_runtime_signal: None,
        };
        let session = Arc::new(RwLock::new(session));
        let shared_store = open_shared_store(workspace_path.as_deref())?;
        let shared_store = Arc::new(Mutex::new(shared_store));
        let cookie_jar = Arc::new(FireSessionCookieJar::new(
            base_url.clone(),
            Arc::clone(&session),
            Some(Arc::clone(&shared_store)),
        ));
        let cloudflare_challenge_runtime = Arc::new(Mutex::new(
            cf_challenge::FireCloudflareChallengeRuntime::default(),
        ));
        let network = network::FireNetworkLayer::new(
            &base_url,
            Arc::clone(&session),
            Arc::clone(&diagnostics),
            cookie_jar,
            Arc::clone(&cloudflare_challenge_runtime),
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
            topic_detail_source: Arc::new(Mutex::new(
                topics::FireTopicDetailSourceRuntime::default(),
            )),
            shared_store,
            home_topic_list_scope: Arc::new(Mutex::new(HomeTopicListScope::default())),
            state_observers: FireStateObserverRegistry::default(),
            csrf_refresh: Arc::new(TokioMutex::new(())),
            cloudflare_challenge_handler:
                cf_challenge::FireCloudflareChallengeHandlerRegistry::default(),
            cloudflare_challenge_runtime,
            cookie_self_healing_handler:
                cookie_healing::FireCookieSelfHealingHandlerRegistry::default(),
            preloaded_data: OnceLock::new(),
            app_state_refresher: OnceLock::new(),
        })
    }

    pub fn base_url(&self) -> &str {
        self.base_url.as_str()
    }

    pub fn workspace_path(&self) -> Option<&Path> {
        self.workspace_path.as_deref()
    }

    pub fn state_observers(&self) -> &FireStateObserverRegistry {
        &self.state_observers
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

    pub fn last_auth_runtime_signal(&self) -> Option<AuthRuntimeSignal> {
        read_rwlock(&self.session, "session")
            .last_auth_runtime_signal
            .clone()
    }

    pub fn shared_client(&self) -> Client {
        self.network.client()
    }

    pub fn preloaded_data_service(&self) -> &Arc<crate::preloaded_data::PreloadedDataService> {
        self.preloaded_data.get_or_init(|| {
            Arc::new(crate::preloaded_data::PreloadedDataService::new(Arc::new(
                self.clone(),
            )))
        })
    }

    pub(crate) fn sync_preloaded_data_cache(&self, bootstrap: &BootstrapArtifacts) {
        if let Some(service) = self.preloaded_data.get() {
            service.sync_from_bootstrap(bootstrap);
        }
    }

    pub(crate) fn reset_preloaded_data_cache(&self) {
        if let Some(service) = self.preloaded_data.get() {
            service.reset();
        }
    }

    pub(crate) fn current_auth_scope_hash(&self) -> String {
        auth_scope_hash(self.base_url(), &self.snapshot())
    }

    pub fn app_state_refresher(&self) -> &Arc<crate::app_state_refresher::AppStateRefresher> {
        self.app_state_refresher.get_or_init(|| {
            Arc::new(crate::app_state_refresher::AppStateRefresher::new(
                Arc::new(self.clone()),
            ))
        })
    }

    pub fn current_home_topic_list_scope(&self) -> HomeTopicListScope {
        self.home_topic_list_scope
            .lock()
            .expect("home topic list scope mutex poisoned")
            .clone()
    }

    pub fn set_current_home_topic_list_scope(
        &self,
        scope: HomeTopicListScope,
    ) -> HomeTopicListScope {
        let sanitized = scope.sanitized();
        *self
            .home_topic_list_scope
            .lock()
            .expect("home topic list scope mutex poisoned") = sanitized.clone();
        sanitized
    }

    pub(crate) fn reset_current_home_topic_list_scope(&self) {
        *self
            .home_topic_list_scope
            .lock()
            .expect("home topic list scope mutex poisoned") = HomeTopicListScope::default();
    }

    pub(crate) fn current_home_topic_list_query(&self) -> TopicListQuery {
        let scope = self.current_home_topic_list_scope().sanitized();
        let snapshot = self.snapshot();
        let category = scope.category_id.and_then(|category_id| {
            snapshot
                .bootstrap
                .categories
                .iter()
                .find(|item| item.id == category_id)
        });
        let parent = category.and_then(|category| {
            category.parent_category_id.and_then(|parent_id| {
                snapshot
                    .bootstrap
                    .categories
                    .iter()
                    .find(|item| item.id == parent_id)
            })
        });
        let primary_tag = scope.tags.first().cloned();
        let additional_tags = scope.tags.iter().skip(1).cloned().collect::<Vec<_>>();

        TopicListQuery {
            kind: scope.kind,
            page: None,
            topic_ids: Vec::new(),
            order: None,
            ascending: None,
            category_slug: category.map(|category| category.slug.clone()),
            category_id: scope.category_id,
            parent_category_slug: parent.map(|category| category.slug.clone()),
            tag: primary_tag,
            additional_tags: additional_tags.clone(),
            match_all_tags: !additional_tags.is_empty(),
        }
    }

    pub fn cookie_replay_list(
        &self,
    ) -> Result<Vec<fire_store::cookie_replay::CookieReplayEntry>, FireCoreError> {
        let store = self
            .shared_store
            .lock()
            .expect("shared store mutex poisoned");
        Ok(store.cookie_replay_list()?)
    }

    pub fn cookie_replay_clear(&self) -> Result<(), FireCoreError> {
        let store = self
            .shared_store
            .lock()
            .expect("shared store mutex poisoned");
        store.cookie_replay_clear()?;
        Ok(())
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

fn auth_scope_hash(base_url: &str, snapshot: &SessionSnapshot) -> String {
    let mut hasher = Sha1::new();
    hasher.update(base_url.as_bytes());
    hasher.update(b"\0");
    if let Some(user_id) = snapshot.bootstrap.current_user_id {
        hasher.update(user_id.to_string().as_bytes());
    }
    hasher.update(b"\0");
    if let Some(username) = snapshot.bootstrap.current_username.as_deref() {
        hasher.update(username.trim().to_ascii_lowercase().as_bytes());
    }
    hasher.update(b"\0");
    if let Some(t_token) = snapshot.cookies.t_token.as_deref() {
        hasher.update(t_token.as_bytes());
    }
    hasher.update(b"\0");
    if let Some(forum_session) = snapshot.cookies.forum_session.as_deref() {
        hasher.update(forum_session.as_bytes());
    }
    format!("{:x}", hasher.finalize())
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
    session.auth_strike.clear_runtime_flags_after_auth_change();
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
