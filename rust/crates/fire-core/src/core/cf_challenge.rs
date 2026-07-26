use std::{
    future::Future,
    pin::Pin,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use fire_models::{CloudflareChallengeRequest, CloudflareChallengeResult};
use tokio::sync::watch;

use super::FireCore;

pub(crate) type FireCloudflareChallengeFuture =
    Pin<Box<dyn Future<Output = CloudflareChallengeResult> + Send>>;
pub(crate) type FireCloudflareChallengeHandlerFn =
    Arc<dyn Fn(CloudflareChallengeRequest) -> FireCloudflareChallengeFuture + Send + Sync>;

const CLOUDFLARE_CHALLENGE_FAILURE_COOLDOWN: Duration = Duration::from_secs(30);
const CLOUDFLARE_CHALLENGE_FAILURES_BEFORE_COOLDOWN: u32 = 3;
/// After CF rejects a clearance, do not treat local jar clearance as trusted.
pub(crate) const CLEARANCE_REJECTED_WINDOW: Duration = Duration::from_secs(120);
/// Brief settle window after a successful challenge so first-wave requests see
/// the merged jar before racing out.
pub(crate) const TRUST_SETTLE_WINDOW: Duration = Duration::from_millis(400);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CloudflareChallengeJoinOutcome {
    Succeeded,
    Failed,
}

#[derive(Debug)]
pub(crate) enum CloudflareChallengeBegin {
    /// This caller owns the platform challenge presentation.
    Start,
    /// Another caller already owns the challenge; wait then retry locally.
    Join(watch::Receiver<Option<CloudflareChallengeJoinOutcome>>),
    /// Recent failures are cooling down and this caller may not bypass.
    Cooldown,
    /// Background/silent traffic must not open a new challenge UI.
    BackgroundSuppressed,
}

#[derive(Clone, Default)]
pub(crate) struct FireCloudflareChallengeHandlerRegistry {
    inner: Arc<Mutex<Option<FireCloudflareChallengeHandlerFn>>>,
}

impl FireCloudflareChallengeHandlerRegistry {
    pub(crate) fn set(&self, handler: FireCloudflareChallengeHandlerFn) {
        *self
            .inner
            .lock()
            .expect("cloudflare challenge handler mutex poisoned") = Some(handler);
    }

    pub(crate) fn clear(&self) {
        *self
            .inner
            .lock()
            .expect("cloudflare challenge handler mutex poisoned") = None;
    }

    pub(crate) fn get(&self) -> Option<FireCloudflareChallengeHandlerFn> {
        self.inner
            .lock()
            .expect("cloudflare challenge handler mutex poisoned")
            .clone()
    }
}

#[derive(Debug)]
pub(crate) struct FireCloudflareChallengeRuntime {
    pub(crate) in_progress: bool,
    pub(crate) cooldown_until: Option<Instant>,
    consecutive_failures: u32,
    clearance_rejected_at: Option<Instant>,
    trust_settle_until: Option<Instant>,
    join_tx: Option<watch::Sender<Option<CloudflareChallengeJoinOutcome>>>,
    join_rx: Option<watch::Receiver<Option<CloudflareChallengeJoinOutcome>>>,
    /// Monotonic counter bumped on each successful challenge completion.
    resolved_generation: u64,
    resolved_tx: watch::Sender<u64>,
}

impl Default for FireCloudflareChallengeRuntime {
    fn default() -> Self {
        let (resolved_tx, _) = watch::channel(0);
        Self {
            in_progress: false,
            cooldown_until: None,
            consecutive_failures: 0,
            clearance_rejected_at: None,
            trust_settle_until: None,
            join_tx: None,
            join_rx: None,
            resolved_generation: 0,
            resolved_tx,
        }
    }
}

impl FireCloudflareChallengeRuntime {
    pub(crate) fn begin_or_join(&mut self, is_foreground: bool) -> CloudflareChallengeBegin {
        if self.in_progress {
            return self
                .join_rx
                .clone()
                .map(CloudflareChallengeBegin::Join)
                // Owner is tearing down; treat as a soft challenge failure.
                .unwrap_or(CloudflareChallengeBegin::BackgroundSuppressed);
        }

        let in_cooldown = self
            .cooldown_until
            .is_some_and(|until| Instant::now() < until);
        if in_cooldown && !is_foreground {
            return CloudflareChallengeBegin::Cooldown;
        }
        if !is_foreground {
            // Silent/background traffic never opens a new challenge surface.
            // It may only join an already-running foreground verification.
            return CloudflareChallengeBegin::BackgroundSuppressed;
        }

        let (tx, rx) = watch::channel(None);
        self.in_progress = true;
        self.cooldown_until = None;
        self.join_tx = Some(tx);
        self.join_rx = Some(rx);
        CloudflareChallengeBegin::Start
    }

    pub(crate) fn finish(&mut self, success: bool) {
        self.in_progress = false;
        if success {
            self.consecutive_failures = 0;
            self.cooldown_until = None;
            let _ = self.publish_resolved();
        } else {
            self.consecutive_failures = self.consecutive_failures.saturating_add(1);
            self.cooldown_until =
                if self.consecutive_failures >= CLOUDFLARE_CHALLENGE_FAILURES_BEFORE_COOLDOWN {
                    Some(Instant::now() + CLOUDFLARE_CHALLENGE_FAILURE_COOLDOWN)
                } else {
                    None
                };
        }

        if let Some(tx) = self.join_tx.take() {
            let outcome = if success {
                CloudflareChallengeJoinOutcome::Succeeded
            } else {
                CloudflareChallengeJoinOutcome::Failed
            };
            let _ = tx.send(Some(outcome));
        }
        self.join_rx = None;
    }

    /// Publish a new clearance-resolved generation (manual or network success).
    pub(crate) fn publish_resolved(&mut self) -> u64 {
        self.clearance_rejected_at = None;
        self.trust_settle_until = Some(Instant::now() + TRUST_SETTLE_WINDOW);
        self.resolved_generation = self.resolved_generation.saturating_add(1);
        let _ = self.resolved_tx.send(self.resolved_generation);
        self.resolved_generation
    }

    pub(crate) fn in_progress(&self) -> bool {
        self.in_progress
    }

    pub(crate) fn mark_clearance_rejected(&mut self) {
        self.clearance_rejected_at = Some(Instant::now());
    }

    pub(crate) fn clear_clearance_rejected(&mut self) {
        self.clearance_rejected_at = None;
    }

    pub(crate) fn is_clearance_recently_rejected(&self) -> bool {
        self.clearance_rejected_at
            .is_some_and(|at| Instant::now().duration_since(at) < CLEARANCE_REJECTED_WINDOW)
    }

    pub(crate) fn trust_settle_remaining(&self) -> Option<Duration> {
        let until = self.trust_settle_until?;
        let now = Instant::now();
        if now >= until {
            None
        } else {
            Some(until.saturating_duration_since(now))
        }
    }

    #[allow(dead_code)] // Available for internal awaiters / tests.
    pub(crate) fn subscribe_resolved(&self) -> watch::Receiver<u64> {
        self.resolved_tx.subscribe()
    }

    pub(crate) fn resolved_generation(&self) -> u64 {
        self.resolved_generation
    }
}

pub(crate) type FireClearanceResolvedHandlerFn =
    Arc<dyn Fn(fire_models::CloudflareClearanceResolvedEvent) + Send + Sync>;

#[derive(Clone, Default)]
pub(crate) struct FireClearanceResolvedHandlerRegistry {
    inner: Arc<Mutex<Option<FireClearanceResolvedHandlerFn>>>,
}

impl FireClearanceResolvedHandlerRegistry {
    pub(crate) fn set(&self, handler: FireClearanceResolvedHandlerFn) {
        *self
            .inner
            .lock()
            .expect("clearance resolved handler mutex poisoned") = Some(handler);
    }

    pub(crate) fn clear(&self) {
        *self
            .inner
            .lock()
            .expect("clearance resolved handler mutex poisoned") = None;
    }

    pub(crate) fn get(&self) -> Option<FireClearanceResolvedHandlerFn> {
        self.inner
            .lock()
            .expect("clearance resolved handler mutex poisoned")
            .clone()
    }
}

impl FireCore {
    pub fn set_cloudflare_challenge_handler<F, Fut>(&self, handler: F)
    where
        F: Fn(CloudflareChallengeRequest) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = CloudflareChallengeResult> + Send + 'static,
    {
        let handler = Arc::new(move |request: CloudflareChallengeRequest| {
            Box::pin(handler(request)) as FireCloudflareChallengeFuture
        });
        self.cloudflare_challenge_handler.set(handler);
    }

    pub fn clear_cloudflare_challenge_handler(&self) {
        self.cloudflare_challenge_handler.clear();
    }

    /// Local jar has clearance and it has not been rejected by CF recently.
    pub fn cloudflare_clearance_is_trusted(&self) -> bool {
        let has_clearance = {
            let session = self.session.read().expect("session mutex poisoned");
            session.snapshot.cookies.has_cloudflare_clearance()
        };
        if !has_clearance {
            return false;
        }
        let runtime = self
            .cloudflare_challenge_runtime
            .lock()
            .expect("cloudflare challenge runtime mutex poisoned");
        !runtime.is_clearance_recently_rejected()
    }

    pub fn note_cloudflare_clearance_rejected(&self) {
        let mut runtime = self
            .cloudflare_challenge_runtime
            .lock()
            .expect("cloudflare challenge runtime mutex poisoned");
        runtime.mark_clearance_rejected();
    }

    pub fn clear_cloudflare_clearance_rejected(&self) {
        let mut runtime = self
            .cloudflare_challenge_runtime
            .lock()
            .expect("cloudflare challenge runtime mutex poisoned");
        runtime.clear_clearance_rejected();
    }

    pub fn cloudflare_clearance_resolved_generation(&self) -> u64 {
        self.cloudflare_challenge_runtime
            .lock()
            .expect("cloudflare challenge runtime mutex poisoned")
            .resolved_generation()
    }

    pub fn set_cloudflare_clearance_resolved_handler<F>(&self, handler: F)
    where
        F: Fn(fire_models::CloudflareClearanceResolvedEvent) + Send + Sync + 'static,
    {
        self.clearance_resolved_handler
            .set(Arc::new(handler) as FireClearanceResolvedHandlerFn);
    }

    pub fn clear_cloudflare_clearance_resolved_handler(&self) {
        self.clearance_resolved_handler.clear();
    }

    /// Mark clearance resolved for paths that never entered the network join gate
    /// (manual login preflight / platform-owned challenge).
    pub(crate) fn publish_clearance_resolved_if_idle(&self) -> u64 {
        let mut runtime = self
            .cloudflare_challenge_runtime
            .lock()
            .expect("cloudflare challenge runtime mutex poisoned");
        if runtime.in_progress() {
            // Network owner will publish via finish(true).
            runtime.resolved_generation()
        } else {
            runtime.publish_resolved()
        }
    }

    pub(crate) fn notify_clearance_resolved(&self, generation: u64) {
        let snapshot = self.snapshot();
        let event = fire_models::CloudflareClearanceResolvedEvent {
            generation,
            has_login_session: snapshot.cookies.has_login_session(),
            can_open_message_bus: snapshot.readiness().can_open_message_bus,
        };
        if let Some(handler) = self.clearance_resolved_handler.get() {
            handler(event);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recently_rejected_expires() {
        let mut runtime = FireCloudflareChallengeRuntime::default();
        assert!(!runtime.is_clearance_recently_rejected());
        runtime.mark_clearance_rejected();
        assert!(runtime.is_clearance_recently_rejected());
        runtime.clear_clearance_rejected();
        assert!(!runtime.is_clearance_recently_rejected());
    }

    #[test]
    fn finish_success_clears_reject_and_sets_settle() {
        let mut runtime = FireCloudflareChallengeRuntime::default();
        runtime.mark_clearance_rejected();
        let _ = runtime.begin_or_join(true);
        runtime.finish(true);
        assert!(!runtime.is_clearance_recently_rejected());
        assert!(runtime.trust_settle_remaining().is_some());
        assert_eq!(runtime.resolved_generation(), 1);
    }
}
