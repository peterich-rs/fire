use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use fire_models::{BrowserTransportPref, CloudflarePolicy, NetworkTransport};

use super::FireCore;
use crate::error::FireCoreError;

const POLICY_FILE_NAME: &str = "cloudflare-policy.json";
const DECLINE_TTL: Duration = Duration::from_secs(24 * 60 * 60);
const SESSION_BACKGROUND_LIMIT: Duration = Duration::from_secs(30 * 60);
const NATIVE_PROBE_SUCCESS_LIMIT: u32 = 5;

#[derive(Default)]
pub(crate) struct FireCloudflarePolicyRuntime {
    pub(crate) policy: CloudflarePolicy,
    pub(crate) transport: NetworkTransport,
    pub(crate) browser_transport_eligible: bool,
    pub(crate) declined_at_unix_s: Option<u64>,
    pub(crate) native_probe_successes: u32,
    pub(crate) backgrounded_at: Option<Instant>,
}

impl FireCore {
    pub fn cloudflare_policy(&self) -> CloudflarePolicy {
        self.cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned")
            .policy
            .clone()
    }

    pub fn set_cloudflare_policy(
        &self,
        policy: CloudflarePolicy,
    ) -> Result<CloudflarePolicy, FireCoreError> {
        let normalized = CloudflarePolicy {
            auto_verify: policy.auto_verify,
            browser_transport: policy.browser_transport,
        };
        {
            let mut runtime = self
                .cloudflare_policy
                .lock()
                .expect("cloudflare policy mutex poisoned");
            runtime.policy = normalized.clone();
            runtime.transport = match normalized.browser_transport {
                BrowserTransportPref::Persistent => NetworkTransport::BrowserSession,
                BrowserTransportPref::Session => runtime.transport,
                BrowserTransportPref::Off => NetworkTransport::Native,
            };
            if normalized.browser_transport == BrowserTransportPref::Off {
                runtime.native_probe_successes = 0;
            }
        }
        persist_policy(self.workspace_path(), &normalized)?;
        Ok(normalized)
    }

    pub fn network_transport(&self) -> NetworkTransport {
        self.cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned")
            .transport
    }

    pub fn enable_browser_transport_for_session(&self) {
        let mut runtime = self
            .cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned");
        runtime.policy.browser_transport = BrowserTransportPref::Session;
        runtime.transport = NetworkTransport::BrowserSession;
        runtime.native_probe_successes = 0;
        let policy = runtime.policy.clone();
        drop(runtime);
        let _ = persist_policy(self.workspace_path(), &policy);
        self.clear_ask_enable_browser_transport_signal();
    }

    pub fn decline_browser_transport(&self) {
        let mut runtime = self
            .cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned");
        runtime.declined_at_unix_s = Some(unix_s());
        runtime.browser_transport_eligible = false;
        drop(runtime);
        self.clear_ask_enable_browser_transport_signal();
    }

    pub(crate) fn reset_session_browser_transport(&self) {
        let mut runtime = self
            .cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned");
        if runtime.policy.browser_transport == BrowserTransportPref::Session {
            runtime.policy.browser_transport = BrowserTransportPref::Off;
            runtime.transport = NetworkTransport::Native;
            runtime.native_probe_successes = 0;
            runtime.backgrounded_at = None;
            let policy = runtime.policy.clone();
            drop(runtime);
            let _ = persist_policy(self.workspace_path(), &policy);
            return;
        }
        if runtime.policy.browser_transport != BrowserTransportPref::Persistent {
            runtime.transport = NetworkTransport::Native;
        }
        runtime.native_probe_successes = 0;
        runtime.backgrounded_at = None;
    }

    pub(crate) fn mark_browser_transport_eligible(&self) {
        let mut runtime = self
            .cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned");
        runtime.browser_transport_eligible = true;
    }

    pub(crate) fn should_ask_browser_transport(&self) -> bool {
        let runtime = self
            .cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned");
        if runtime.policy.browser_transport != BrowserTransportPref::Off {
            return false;
        }
        if !runtime.browser_transport_eligible {
            return false;
        }
        if let Some(declined_at) = runtime.declined_at_unix_s {
            if unix_s().saturating_sub(declined_at) < DECLINE_TTL.as_secs() {
                return false;
            }
        }
        true
    }

    pub(crate) fn should_use_browser_transport(&self, operation: &str) -> bool {
        if operation.contains("message bus") || operation.contains("logout") {
            return false;
        }
        let runtime = self
            .cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned");
        runtime.transport == NetworkTransport::BrowserSession
            && self.browser_http_handler.get().is_some()
    }

    pub fn note_app_backgrounded(&self) {
        self.cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned")
            .backgrounded_at = Some(Instant::now());
        self.note_message_bus_app_backgrounded();
    }

    pub fn note_app_foregrounded(&self) {
        self.note_message_bus_app_foregrounded();
        let mut runtime = self
            .cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned");
        if runtime.policy.browser_transport == BrowserTransportPref::Session {
            if runtime
                .backgrounded_at
                .is_some_and(|at| at.elapsed() >= SESSION_BACKGROUND_LIMIT)
            {
                runtime.transport = NetworkTransport::Native;
                runtime.policy.browser_transport = BrowserTransportPref::Off;
                let policy = runtime.policy.clone();
                drop(runtime);
                let _ = persist_policy(self.workspace_path(), &policy);
                return;
            }
        }
        runtime.backgrounded_at = None;
    }

    pub(crate) fn note_native_probe_success(&self) {
        let mut runtime = self
            .cloudflare_policy
            .lock()
            .expect("cloudflare policy mutex poisoned");
        if runtime.policy.browser_transport != BrowserTransportPref::Session {
            return;
        }
        runtime.native_probe_successes = runtime.native_probe_successes.saturating_add(1);
        if runtime.native_probe_successes >= NATIVE_PROBE_SUCCESS_LIMIT {
            runtime.transport = NetworkTransport::Native;
            runtime.policy.browser_transport = BrowserTransportPref::Off;
            runtime.native_probe_successes = 0;
            let policy = runtime.policy.clone();
            drop(runtime);
            let _ = persist_policy(self.workspace_path(), &policy);
        }
    }
}

pub(crate) fn load_cloudflare_policy(workspace_path: Option<&Path>) -> FireCloudflarePolicyRuntime {
    let policy: CloudflarePolicy = workspace_path
        .map(policy_path)
        .and_then(|path| std::fs::read_to_string(path).ok())
        .and_then(|payload| serde_json::from_str(&payload).ok())
        .unwrap_or_default();
    let transport = match policy.browser_transport {
        BrowserTransportPref::Persistent => NetworkTransport::BrowserSession,
        _ => NetworkTransport::Native,
    };
    FireCloudflarePolicyRuntime {
        policy,
        transport,
        ..FireCloudflarePolicyRuntime::default()
    }
}

fn persist_policy(
    workspace_path: Option<&Path>,
    policy: &CloudflarePolicy,
) -> Result<(), FireCoreError> {
    let Some(workspace_path) = workspace_path else {
        return Ok(());
    };
    let path = policy_path(workspace_path);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|source| FireCoreError::WorkspaceIo {
            path: parent.to_path_buf(),
            source,
        })?;
    }
    let payload = serde_json::to_string_pretty(policy).map_err(FireCoreError::PersistSerialize)?;
    std::fs::write(&path, payload).map_err(|source| FireCoreError::WorkspaceIo { path, source })
}

fn policy_path(workspace_path: &Path) -> PathBuf {
    workspace_path.join("cache").join(POLICY_FILE_NAME)
}

fn unix_s() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use fire_models::{BrowserHttpResponse, BrowserTransportPref, NetworkTransport};

    use super::*;
    use crate::config::FireCoreConfig;

    fn test_core() -> FireCore {
        FireCore::new(FireCoreConfig::default()).expect("core")
    }

    #[test]
    fn message_bus_stays_native_when_browser_transport_enabled() {
        let core = test_core();
        core.set_browser_http_handler(|_| {
            Ok(BrowserHttpResponse {
                status: 200,
                headers: Vec::new(),
                body: Vec::new(),
            })
        });
        core.enable_browser_transport_for_session();
        assert_eq!(core.network_transport(), NetworkTransport::BrowserSession);
        assert!(!core.should_use_browser_transport("message bus poll"));
        assert!(!core.should_use_browser_transport("logout"));
        assert!(core.should_use_browser_transport("fetch home topic list"));
    }

    #[test]
    fn logout_clears_session_browser_transport() {
        let core = test_core();
        core.enable_browser_transport_for_session();
        assert_eq!(
            core.cloudflare_policy().browser_transport,
            BrowserTransportPref::Session
        );
        assert_eq!(core.network_transport(), NetworkTransport::BrowserSession);
        let _ = core.logout_local(true);
        assert_eq!(core.network_transport(), NetworkTransport::Native);
        assert_eq!(
            core.cloudflare_policy().browser_transport,
            BrowserTransportPref::Off
        );
    }

    #[test]
    fn ask_enable_signal_is_copied_onto_session_snapshot() {
        use fire_models::{
            AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource,
            AuthRuntimeSignalStrength,
        };

        let core = test_core();
        core.record_auth_runtime_signal(AuthRuntimeSignal {
            kind: AuthRuntimeSignalKind::AskEnableBrowserTransport,
            strength: AuthRuntimeSignalStrength::Diagnostic,
            source: AuthRuntimeSignalSource::HttpResponse,
            operation: Some("fetch home topic list".into()),
            status: Some(403),
        });
        let snapshot = core.snapshot();
        assert_eq!(
            snapshot
                .last_auth_runtime_signal
                .as_ref()
                .map(|signal| signal.kind.clone()),
            Some(AuthRuntimeSignalKind::AskEnableBrowserTransport)
        );
        core.decline_browser_transport();
        assert!(core.snapshot().last_auth_runtime_signal.is_none());
    }
}
