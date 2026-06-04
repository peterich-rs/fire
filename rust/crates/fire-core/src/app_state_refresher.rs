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
        self.refresh_core_batch(&trigger).await?;

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

    async fn refresh_core_batch(&self, _trigger: &RefreshTrigger) -> Result<(), FireCoreError> {
        self.core.refresh_bootstrap_if_needed().await?;
        Ok(())
    }

    async fn refresh_secondary_batch_inner(
        core: &FireCore,
        _trigger: &RefreshTrigger,
    ) -> Result<(), FireCoreError> {
        let snapshot = core.snapshot();
        let username = snapshot.bootstrap.current_username.clone();
        if let Some(username) = username {
            let _ = core.fetch_user_profile(&username).await;
        }
        Ok(())
    }
}
