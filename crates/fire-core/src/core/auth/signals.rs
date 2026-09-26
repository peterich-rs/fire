use fire_models::{
    AuthRuntimeSignal, AuthRuntimeSignalKind, AuthRuntimeSignalSource, AuthRuntimeSignalStrength,
    PassiveLogoutTrigger, ProbeResult, SignalStrength,
};
use tracing::info;

use super::super::FireCore;
use super::StrikeDecision;
use crate::{
    error::FireCoreError,
    sync_utils::{read_rwlock, write_rwlock},
};

impl FireCore {
    pub(crate) fn record_auth_runtime_signal(&self, signal: AuthRuntimeSignal) {
        let signal_kind = signal.kind.clone();
        let signal_strength = signal.strength;
        let signal_source = signal.source;
        let operation = signal.operation.clone();
        let status = signal.status;
        let snapshot = {
            let mut state = write_rwlock(&self.session, "session");
            state.last_auth_runtime_signal = Some(signal.clone());
            state.snapshot.last_auth_runtime_signal = Some(signal);
            state.snapshot.clone()
        };
        self.state_observers().notify_session(snapshot);
        info!(
            kind = ?signal_kind,
            strength = ?signal_strength,
            source = ?signal_source,
            operation = ?operation,
            status = ?status,
            "recorded auth runtime signal"
        );
    }

    pub(crate) fn clear_ask_enable_browser_transport_signal(&self) {
        let snapshot = {
            let mut state = write_rwlock(&self.session, "session");
            if !matches!(
                state
                    .last_auth_runtime_signal
                    .as_ref()
                    .map(|signal| &signal.kind),
                Some(AuthRuntimeSignalKind::AskEnableBrowserTransport)
            ) {
                return;
            }
            state.last_auth_runtime_signal = None;
            state.snapshot.last_auth_runtime_signal = None;
            state.snapshot.clone()
        };
        self.state_observers().notify_session(snapshot);
    }

    pub(crate) async fn process_auth_runtime_signal(
        &self,
        signal: AuthRuntimeSignal,
        operation: &'static str,
    ) -> Option<FireCoreError> {
        let strike_strength = match signal.kind {
            AuthRuntimeSignalKind::NotLoggedInBody
            | AuthRuntimeSignalKind::DiscourseLoggedOutHeader => Some(SignalStrength::Strong),
            AuthRuntimeSignalKind::MixedLoggedOutHeader
            | AuthRuntimeSignalKind::MixedSignalCookieDeletionBlocked => Some(SignalStrength::Weak),
            _ => None,
        };
        self.record_auth_runtime_signal(signal);
        match strike_strength {
            Some(strength) => self.process_auth_strike_signal(strength, operation).await,
            None => None,
        }
    }

    pub(crate) async fn process_auth_strike_signal(
        &self,
        strength: SignalStrength,
        operation: &'static str,
    ) -> Option<FireCoreError> {
        if self.cloudflare_recovery_active() {
            return None;
        }
        let decision = {
            let mut state = write_rwlock(&self.session, "session");
            state.auth_strike.receive_auth_signal(strength.clone())
        };
        match decision {
            StrikeDecision::ProbeNeeded => {
                {
                    let mut state = write_rwlock(&self.session, "session");
                    state.auth_strike.probe_in_progress = true;
                }
                let probe_result = self.probe_session().await;
                {
                    let mut state = write_rwlock(&self.session, "session");
                    state.auth_strike.probe_in_progress = false;
                }
                match probe_result {
                    Ok(ProbeResult::Valid { .. }) => {
                        self.record_auth_runtime_signal(AuthRuntimeSignal {
                            kind: AuthRuntimeSignalKind::ProbeValid,
                            strength: AuthRuntimeSignalStrength::Terminal,
                            source: AuthRuntimeSignalSource::Probe,
                            operation: Some(operation.to_string()),
                            status: None,
                        });
                        self.note_native_probe_success();
                        info!(
                            operation,
                            "probe confirmed session valid, resetting strikes"
                        );
                        {
                            let mut state = write_rwlock(&self.session, "session");
                            state.auth_strike.reset_strikes();
                        }
                        None
                    }
                    Ok(ProbeResult::Invalid) => {
                        self.record_auth_runtime_signal(AuthRuntimeSignal {
                            kind: AuthRuntimeSignalKind::ProbeInvalid,
                            strength: AuthRuntimeSignalStrength::Terminal,
                            source: AuthRuntimeSignalSource::Probe,
                            operation: Some(operation.to_string()),
                            status: None,
                        });
                        info!(
                            operation,
                            "probe confirmed session invalid, triggering passive logout"
                        );
                        let _ = self
                            .passive_logout(PassiveLogoutTrigger {
                                source: format!("strike_probe_invalid:{operation}"),
                                signal_strength: strength,
                                cookie_diagnostic: String::new(),
                            })
                            .await;
                        Some(FireCoreError::LoginRequired {
                            operation,
                            message: "登录状态已失效，请重新登录。".to_string(),
                        })
                    }
                    Ok(ProbeResult::Inconclusive) => {
                        let strikes = {
                            let state = read_rwlock(&self.session, "session");
                            state.auth_strike.strike_count
                        };
                        if strikes >= 2 {
                            self.record_auth_runtime_signal(AuthRuntimeSignal {
                                kind: AuthRuntimeSignalKind::ProbeInconclusiveEscalated,
                                strength: AuthRuntimeSignalStrength::Terminal,
                                source: AuthRuntimeSignalSource::Probe,
                                operation: Some(operation.to_string()),
                                status: None,
                            });
                            info!(
                                operation,
                                strikes,
                                "probe inconclusive with enough strikes, triggering passive logout"
                            );
                            let _ = self
                                .passive_logout(PassiveLogoutTrigger {
                                    source: format!("strike_probe_inconclusive:{operation}"),
                                    signal_strength: strength,
                                    cookie_diagnostic: String::new(),
                                })
                                .await;
                            Some(FireCoreError::LoginRequired {
                                operation,
                                message: "登录状态已失效，请重新登录。".to_string(),
                            })
                        } else {
                            self.record_auth_runtime_signal(AuthRuntimeSignal {
                                kind: AuthRuntimeSignalKind::ProbeInconclusive,
                                strength: AuthRuntimeSignalStrength::Diagnostic,
                                source: AuthRuntimeSignalSource::Probe,
                                operation: Some(operation.to_string()),
                                status: None,
                            });
                            info!(
                                operation,
                                strikes, "probe inconclusive with few strikes, entering cooldown"
                            );
                            let mut state = write_rwlock(&self.session, "session");
                            state.auth_strike.enter_inconclusive_cooldown();
                            Some(FireCoreError::LoginRequired {
                                operation,
                                message: "登录状态已失效，请重新登录。".to_string(),
                            })
                        }
                    }
                    Err(_) => {
                        let strikes = {
                            let state = read_rwlock(&self.session, "session");
                            state.auth_strike.strike_count
                        };
                        if strikes >= 2 {
                            self.record_auth_runtime_signal(AuthRuntimeSignal {
                                kind: AuthRuntimeSignalKind::ProbeInconclusiveEscalated,
                                strength: AuthRuntimeSignalStrength::Terminal,
                                source: AuthRuntimeSignalSource::Probe,
                                operation: Some(operation.to_string()),
                                status: None,
                            });
                            let _ = self
                                .passive_logout(PassiveLogoutTrigger {
                                    source: format!("strike_probe_error:{operation}"),
                                    signal_strength: strength,
                                    cookie_diagnostic: String::new(),
                                })
                                .await;
                        } else {
                            self.record_auth_runtime_signal(AuthRuntimeSignal {
                                kind: AuthRuntimeSignalKind::ProbeInconclusive,
                                strength: AuthRuntimeSignalStrength::Diagnostic,
                                source: AuthRuntimeSignalSource::Probe,
                                operation: Some(operation.to_string()),
                                status: None,
                            });
                            let mut state = write_rwlock(&self.session, "session");
                            state.auth_strike.enter_inconclusive_cooldown();
                        }
                        Some(FireCoreError::LoginRequired {
                            operation,
                            message: "登录状态已失效，请重新登录。".to_string(),
                        })
                    }
                }
            }
            StrikeDecision::Accumulated { .. } | StrikeDecision::Ignore => None,
        }
    }
}
