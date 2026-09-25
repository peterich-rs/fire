use std::sync::Arc;

use fire_core::{FireCore, FireCoreConfig};

use crate::error::FireUniFfiError;
use crate::panic::PanicState;
use crate::runtime::constructor_guard;

pub struct SharedFireCore {
    pub core: Arc<FireCore>,
    pub panic_state: Arc<PanicState>,
}

impl SharedFireCore {
    pub fn bootstrap(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Self, FireUniFfiError> {
        constructor_guard("SharedFireCore::bootstrap", || {
            Ok(Self {
                core: Arc::new(FireCore::new(FireCoreConfig {
                    base_url: base_url.unwrap_or_else(|| "https://linux.do".to_string()),
                    workspace_path,
                })?),
                panic_state: Arc::new(PanicState::default()),
            })
        })
    }
}
