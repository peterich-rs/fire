use std::sync::Arc;
use std::time::{Duration, Instant};

use fire_models::RefreshTrigger;
use tracing::{info, warn};

use crate::core::FireCore;
use crate::error::FireCoreError;

const DEBOUNCE_DURATION: Duration = Duration::from_secs(2);
const SECONDARY_BATCH_DELAY: Duration = Duration::from_millis(1000);

pub struct AppStateRefresher {
    core: Arc<FireCore>,
    last_refresh: std::sync::Mutex<Option<Instant>>,
}

impl AppStateRefresher {
    pub fn new(core: Arc<FireCore>) -> Self {
        Self {
            core,
            last_refresh: std::sync::Mutex::new(None),
        }
    }

    pub async fn refresh_all(&self, trigger: RefreshTrigger) -> Result<(), FireCoreError> {
        {
            let mut last = self.last_refresh.lock().unwrap();
            if let Some(instant) = *last {
                if instant.elapsed() < DEBOUNCE_DURATION {
                    info!("app state refresh debounced, skipping");
                    return Ok(());
                }
            }
            *last = Some(Instant::now());
        }

        info!(?trigger, "starting app state refresh batch 1 (core)");
        let should_schedule_secondary = match self.refresh_core_batch(&trigger).await {
            Ok(should_schedule_secondary) => should_schedule_secondary,
            Err(error) => {
                warn!(error = %error, ?trigger, "core batch refresh failed");
                false
            }
        };

        if !should_schedule_secondary {
            return Ok(());
        }

        info!("scheduling app state refresh batch 2 (secondary) in 1s");
        let core = self.core.clone();
        tokio::spawn(async move {
            tokio::time::sleep(SECONDARY_BATCH_DELAY).await;
            if let Err(e) = Self::refresh_secondary_batch_inner(&core, &trigger).await {
                warn!(error = %e, "secondary batch refresh failed");
            }
        });

        Ok(())
    }

    async fn refresh_core_batch(&self, trigger: &RefreshTrigger) -> Result<bool, FireCoreError> {
        let snapshot = self.core.snapshot();
        if !snapshot.readiness().can_read_authenticated_api {
            info!(
                ?trigger,
                "skipping app state refresh because authenticated API access is unavailable"
            );
            return Ok(false);
        }

        self.core.refresh_bootstrap().await?;
        Ok(true)
    }

    async fn refresh_secondary_batch_inner(
        core: &FireCore,
        trigger: &RefreshTrigger,
    ) -> Result<(), FireCoreError> {
        let snapshot = core.snapshot();
        if !snapshot.readiness().can_read_authenticated_api {
            info!(
                ?trigger,
                "skipping secondary app state refresh because authenticated API access is unavailable"
            );
            return Ok(());
        }

        let username = snapshot.bootstrap.current_username.clone();
        if let Some(username) = username {
            if let Err(error) = core.fetch_user_summary(&username).await {
                warn!(error = %error, %username, "user summary refresh failed");
            }
            if let Err(error) = core.fetch_bookmarks(&username, None).await {
                warn!(error = %error, %username, "bookmarks refresh failed");
            }
        } else {
            warn!("secondary app state refresh skipped user-scoped endpoints: missing username");
        }

        if let Err(error) = core.fetch_read_history(None).await {
            warn!(error = %error, "read history refresh failed");
        }
        if let Err(error) = core.fetch_recent_notifications(None).await {
            warn!(error = %error, "recent notifications refresh failed");
        }
        Ok(())
    }
}
