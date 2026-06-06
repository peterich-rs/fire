use fire_models::SignalStrength;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq)]
pub enum StrikeDecision {
    Ignore,
    Accumulated { strikes: u8 },
    ProbeNeeded,
}

#[derive(Debug, Clone)]
pub struct AuthStrikeState {
    pub strike_count: u8,
    pub last_strike_at: Option<Instant>,
    pub last_signal_strength: Option<SignalStrength>,
    pub inconclusive_until: Option<Instant>,
    pub passive_logout_count_24h: u8,
    pub passive_logout_window_start: Option<Instant>,
    pub probe_in_progress: bool,
    pub logging_out: bool,
}

const STRIKE_WINDOW: Duration = Duration::from_secs(45);
const INCONCLUSIVE_COOLDOWN: Duration = Duration::from_secs(30);
const PASSIVE_LOGOUT_WINDOW: Duration = Duration::from_secs(24 * 60 * 60);
const PASSIVE_LOGOUT_SUGGEST_CLEAR_THRESHOLD: u8 = 3;

impl Default for AuthStrikeState {
    fn default() -> Self {
        Self {
            strike_count: 0,
            last_strike_at: None,
            last_signal_strength: None,
            inconclusive_until: None,
            passive_logout_count_24h: 0,
            passive_logout_window_start: None,
            probe_in_progress: false,
            logging_out: false,
        }
    }
}

impl AuthStrikeState {
    pub fn receive_auth_signal(&mut self, strength: SignalStrength) -> StrikeDecision {
        if self.logging_out {
            return StrikeDecision::Ignore;
        }
        if self.probe_in_progress {
            return StrikeDecision::Ignore;
        }
        if let Some(until) = self.inconclusive_until {
            if Instant::now() < until && strength == SignalStrength::Weak {
                return StrikeDecision::Ignore;
            }
        }

        if let Some(last) = self.last_strike_at {
            if Instant::now().duration_since(last) > STRIKE_WINDOW {
                self.strike_count = 0;
            }
        }

        self.strike_count += 1;
        self.last_strike_at = Some(Instant::now());
        self.last_signal_strength = Some(strength.clone());

        let threshold = match strength {
            SignalStrength::Strong => 1,
            SignalStrength::Weak => 2,
        };

        if self.strike_count >= threshold {
            StrikeDecision::ProbeNeeded
        } else {
            StrikeDecision::Accumulated {
                strikes: self.strike_count,
            }
        }
    }

    pub fn reset_strikes(&mut self) {
        self.strike_count = 0;
        self.last_strike_at = None;
        self.last_signal_strength = None;
        self.inconclusive_until = None;
        self.probe_in_progress = false;
        self.logging_out = false;
    }

    pub fn enter_inconclusive_cooldown(&mut self) {
        self.inconclusive_until = Some(Instant::now() + INCONCLUSIVE_COOLDOWN);
    }

    pub fn should_suggest_data_clear(&self) -> bool {
        self.passive_logout_count_24h >= PASSIVE_LOGOUT_SUGGEST_CLEAR_THRESHOLD
    }

    pub fn record_passive_logout(&mut self) {
        let now = Instant::now();
        if let Some(start) = self.passive_logout_window_start {
            if now.duration_since(start) > PASSIVE_LOGOUT_WINDOW {
                self.passive_logout_count_24h = 0;
                self.passive_logout_window_start = Some(now);
            }
        } else {
            self.passive_logout_window_start = Some(now);
        }
        self.passive_logout_count_24h += 1;
        self.logging_out = true;
    }

    pub fn clear_runtime_flags_after_auth_change(&mut self) {
        self.strike_count = 0;
        self.last_strike_at = None;
        self.last_signal_strength = None;
        self.inconclusive_until = None;
        self.probe_in_progress = false;
        self.logging_out = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strong_signal_triggers_probe_immediately() {
        let mut state = AuthStrikeState::default();
        let decision = state.receive_auth_signal(SignalStrength::Strong);
        assert!(matches!(decision, StrikeDecision::ProbeNeeded));
    }

    #[test]
    fn weak_signal_needs_two_strikes() {
        let mut state = AuthStrikeState::default();
        let decision = state.receive_auth_signal(SignalStrength::Weak);
        assert!(matches!(decision, StrikeDecision::Accumulated { .. }));
        let decision = state.receive_auth_signal(SignalStrength::Weak);
        assert!(matches!(decision, StrikeDecision::ProbeNeeded));
    }

    #[test]
    fn strikes_reset_after_45s_gap() {
        let mut state = AuthStrikeState::default();
        state.receive_auth_signal(SignalStrength::Weak);
        state.last_strike_at = Some(Instant::now() - Duration::from_secs(60));
        let decision = state.receive_auth_signal(SignalStrength::Weak);
        if let StrikeDecision::Accumulated { strikes } = decision {
            assert_eq!(strikes, 1);
        } else {
            panic!("Expected Accumulated");
        }
    }

    #[test]
    fn inconclusive_cooldown_ignores_weak_signals() {
        let mut state = AuthStrikeState::default();
        state.inconclusive_until = Some(Instant::now() + Duration::from_secs(30));
        let decision = state.receive_auth_signal(SignalStrength::Weak);
        assert!(matches!(decision, StrikeDecision::Ignore));
    }

    #[test]
    fn logging_out_ignores_all_signals() {
        let mut state = AuthStrikeState::default();
        state.logging_out = true;
        let decision = state.receive_auth_signal(SignalStrength::Strong);
        assert!(matches!(decision, StrikeDecision::Ignore));
    }

    #[test]
    fn probe_in_progress_ignores_signals() {
        let mut state = AuthStrikeState::default();
        state.probe_in_progress = true;
        let decision = state.receive_auth_signal(SignalStrength::Strong);
        assert!(matches!(decision, StrikeDecision::Ignore));
    }

    #[test]
    fn reset_strikes_clears_all_state() {
        let mut state = AuthStrikeState::default();
        state.receive_auth_signal(SignalStrength::Weak);
        state.receive_auth_signal(SignalStrength::Weak);
        state.reset_strikes();
        assert_eq!(state.strike_count, 0);
        assert!(state.last_strike_at.is_none());
    }
}
