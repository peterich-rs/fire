use std::{
    future::Future,
    pin::Pin,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use fire_models::{CloudflareChallengeRequest, CloudflareChallengeResult};

use super::FireCore;

pub(crate) type FireCloudflareChallengeFuture =
    Pin<Box<dyn Future<Output = CloudflareChallengeResult> + Send>>;
pub(crate) type FireCloudflareChallengeHandlerFn =
    Arc<dyn Fn(CloudflareChallengeRequest) -> FireCloudflareChallengeFuture + Send + Sync>;

const CLOUDFLARE_CHALLENGE_FAILURE_COOLDOWN: Duration = Duration::from_secs(15);

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

#[derive(Debug, Clone, Default)]
pub(crate) struct FireCloudflareChallengeRuntime {
    pub(crate) in_progress: bool,
    pub(crate) cooldown_until: Option<Instant>,
}

impl FireCloudflareChallengeRuntime {
    pub(crate) fn can_start(&self, bypass_cooldown: bool) -> bool {
        if bypass_cooldown {
            return !self.in_progress;
        }
        self.cooldown_until
            .is_none_or(|until| Instant::now() >= until)
            && !self.in_progress
    }

    pub(crate) fn begin(&mut self) {
        self.in_progress = true;
        self.cooldown_until = None;
    }

    pub(crate) fn finish(&mut self, success: bool) {
        self.in_progress = false;
        self.cooldown_until = if success {
            None
        } else {
            Some(Instant::now() + CLOUDFLARE_CHALLENGE_FAILURE_COOLDOWN)
        };
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
