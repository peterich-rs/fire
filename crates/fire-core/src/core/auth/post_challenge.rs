use std::{future::Future, sync::OnceLock};

use tokio::runtime::{Builder, Handle, Runtime};
use tracing::{info, warn};

use super::super::FireCore;

impl FireCore {
    /// After CF success: publish resolved generation, force bootstrap + full
    /// app-state refresh when logged in, then notify platform subscribers
    /// (MessageBus restart / banner clear / login continue).
    /// Safe to call from sync UniFFI paths (falls back when no Tokio handle).
    pub(crate) fn spawn_proved_challenge_refresh(
        core: FireCore,
        runtime: std::sync::Arc<
            std::sync::Mutex<crate::core::cf_challenge::FireCloudflareChallengeRuntime>,
        >,
    ) {
        spawn_post_challenge_task(async move {
            core.run_post_challenge_session_rebuild().await;
            runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned")
                .finish_with_publish(true, true);
            core.sync_cloudflare_recovery_snapshot();
        });
    }

    pub(crate) fn schedule_post_challenge_session_rebuild(&self) {
        let core = self.clone();
        spawn_post_challenge_task(async move {
            core.run_post_challenge_session_rebuild().await;
        });
    }

    pub(crate) async fn run_post_challenge_session_rebuild(&self) {
        // Manual path bumps here; network path bumps in finish(true) after this returns.
        let generation_hint = self.publish_clearance_resolved_if_idle();
        let has_login = self.snapshot().cookies.has_login_session();
        // Allow network finish(true) to publish generation before we notify.
        tokio::time::sleep(std::time::Duration::from_millis(30)).await;

        if !has_login {
            let generation = self
                .cloudflare_clearance_resolved_generation()
                .max(generation_hint);
            self.notify_clearance_resolved(generation);
            return;
        }

        // Let cookie merge settle before the rebuild wave.
        let settle = {
            let runtime = self
                .cloudflare_challenge_runtime
                .lock()
                .expect("cloudflare challenge runtime mutex poisoned");
            runtime.trust_settle_remaining()
        };
        if let Some(remaining) = settle {
            tokio::time::sleep(remaining).await;
        }

        self.set_recovery_http_bypass(true);
        match self.refresh_bootstrap().await {
            Ok(_) => {
                info!("post-challenge bootstrap rebuild complete");
            }
            Err(error) => {
                warn!(error = %error, "post-challenge bootstrap rebuild failed");
            }
        }

        // Bootstrap alone is not enough to keep writes healthy after CF:
        // Set-Cookie may rotate `_forum_session`/`_t` (stale CSRF cleared),
        // while home HTML may omit `<meta name="csrf-token">` (interstitial /
        // redirect / partial page). Force a `/session/csrf` realign so
        // `can_write_authenticated_api` recovers before hosts act on the
        // clearance-resolved event. Failures stay soft — BAD CSRF retry
        // remains the last line of defense.
        if self.snapshot().cookies.can_authenticate_requests() {
            match self.refresh_csrf_token().await {
                Ok(_) => info!("post-challenge CSRF realigned"),
                Err(error) => {
                    warn!(error = %error, "post-challenge CSRF refresh failed")
                }
            }
        }

        self.set_recovery_http_bypass(false);
        self.state_observers().notify_session(self.snapshot());

        // Force a full loginCompleted-style batch so CF mid-refresh does not
        // leave home/notifications stuck on a partial failure.
        self.set_recovery_http_bypass(true);
        if let Err(error) = self
            .app_state_refresher()
            .refresh_all_forced(fire_models::RefreshTrigger::CloudflareResolved)
            .await
        {
            warn!(error = %error, "post-challenge app state refresh failed");
        }
        self.set_recovery_http_bypass(false);

        let generation = self
            .cloudflare_clearance_resolved_generation()
            .max(generation_hint);
        self.notify_clearance_resolved(generation);
    }
}

fn post_challenge_runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .thread_name("fire-post-challenge")
            .build()
            .expect("failed to create post-challenge runtime")
    })
}

pub(crate) fn spawn_post_challenge_task<F>(future: F)
where
    F: Future<Output = ()> + Send + 'static,
{
    if let Ok(handle) = Handle::try_current() {
        handle.spawn(future);
    } else {
        post_challenge_runtime().spawn(future);
    }
}
