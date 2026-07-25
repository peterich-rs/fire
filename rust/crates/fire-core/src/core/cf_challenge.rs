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

#[derive(Debug, Default)]
pub(crate) struct FireCloudflareChallengeRuntime {
    pub(crate) in_progress: bool,
    pub(crate) cooldown_until: Option<Instant>,
    consecutive_failures: u32,
    join_tx: Option<watch::Sender<Option<CloudflareChallengeJoinOutcome>>>,
    join_rx: Option<watch::Receiver<Option<CloudflareChallengeJoinOutcome>>>,
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
}
