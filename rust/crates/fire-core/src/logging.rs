use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
};

use mars_xlog::{LogLevel, Xlog, XlogConfig};
use tracing_subscriber::prelude::*;

use crate::error::FireCoreError;

const FIRE_LOGGER_NAME_PREFIX: &str = "fire";
const FIRE_LOGS_DIR_NAME: &str = "logs";
const FIRE_LOG_CACHE_PARENT_DIR: &str = "cache";
const FIRE_LOG_CACHE_DIR_NAME: &str = "xlog";

#[derive(Debug, Clone)]
pub struct FireLoggerConfig {
    pub log_dir: String,
    pub cache_dir: Option<String>,
    pub name_prefix: String,
    pub level: LogLevel,
}

#[derive(Clone)]
pub struct FireLogger {
    inner: Xlog,
}

impl FireLogger {
    pub fn init(config: FireLoggerConfig) -> Result<Self, FireCoreError> {
        let mut xlog_config = XlogConfig::new(config.log_dir, config.name_prefix);
        if let Some(cache_dir) = config.cache_dir {
            xlog_config = xlog_config.cache_dir(cache_dir);
        }
        let inner = Xlog::init(xlog_config, config.level)?;
        Ok(Self { inner })
    }

    pub fn set_console_log_open(&self, open: bool) {
        self.inner.set_console_log_open(open);
    }

    pub fn flush(&self, sync: bool) {
        self.inner.flush(sync);
    }
}

#[derive(Clone)]
pub(crate) struct FireLoggerRuntime {
    workspace_path: PathBuf,
    pub(crate) log_dir: PathBuf,
    pub(crate) cache_dir: PathBuf,
    logger: FireLogger,
}

impl FireLoggerRuntime {
    fn initialize(workspace_path: PathBuf) -> Result<Self, FireCoreError> {
        let log_dir = workspace_path.join(FIRE_LOGS_DIR_NAME);
        let cache_dir = workspace_path
            .join(FIRE_LOG_CACHE_PARENT_DIR)
            .join(FIRE_LOG_CACHE_DIR_NAME);

        fs::create_dir_all(&log_dir).map_err(|source| FireCoreError::WorkspaceIo {
            path: log_dir.clone(),
            source,
        })?;
        fs::create_dir_all(&cache_dir).map_err(|source| FireCoreError::WorkspaceIo {
            path: cache_dir.clone(),
            source,
        })?;

        let level = if cfg!(debug_assertions) {
            LogLevel::Debug
        } else {
            LogLevel::Info
        };
        let logger = FireLogger::init(FireLoggerConfig {
            log_dir: log_dir.display().to_string(),
            cache_dir: Some(cache_dir.display().to_string()),
            name_prefix: FIRE_LOGGER_NAME_PREFIX.to_string(),
            level,
        })?;
        logger.set_console_log_open(cfg!(debug_assertions));
        init_tracing(logger.inner.clone(), level);

        Ok(Self {
            workspace_path,
            log_dir,
            cache_dir,
            logger,
        })
    }

    fn validate_workspace(&self, workspace_path: &Path) -> Result<(), FireCoreError> {
        if self.workspace_path != workspace_path {
            return Err(FireCoreError::LoggerWorkspaceMismatch {
                expected: self.workspace_path.clone(),
                found: workspace_path.to_path_buf(),
            });
        }
        Ok(())
    }

    pub(crate) fn flush(&self, sync: bool) {
        self.logger.flush(sync);
    }
}

fn init_tracing(logger: Xlog, level: LogLevel) {
    static TRACING_INIT: OnceLock<()> = OnceLock::new();
    let _ = TRACING_INIT.get_or_init(|| {
        let (layer, _handle) = mars_xlog::XlogLayer::with_config(
            logger,
            mars_xlog::XlogLayerConfig::new(level).enabled(true),
        );
        let subscriber = tracing_subscriber::registry().with(layer);
        let _ = tracing::subscriber::set_global_default(subscriber);
    });
}

pub(crate) fn logger_runtime_for_workspace(
    workspace_path: &Path,
) -> Result<&'static FireLoggerRuntime, FireCoreError> {
    static LOGGER_RUNTIME: OnceLock<FireLoggerRuntime> = OnceLock::new();
    static LOGGER_INIT_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    if let Some(runtime) = LOGGER_RUNTIME.get() {
        runtime.validate_workspace(workspace_path)?;
        return Ok(runtime);
    }

    let lock = LOGGER_INIT_LOCK.get_or_init(|| Mutex::new(()));
    let _guard = lock.lock().expect("logger init lock poisoned");

    if let Some(runtime) = LOGGER_RUNTIME.get() {
        runtime.validate_workspace(workspace_path)?;
        return Ok(runtime);
    }

    let runtime = FireLoggerRuntime::initialize(workspace_path.to_path_buf())?;
    let _ = LOGGER_RUNTIME.set(runtime);
    let runtime = LOGGER_RUNTIME
        .get()
        .expect("logger runtime should be initialized");
    runtime.validate_workspace(workspace_path)?;
    Ok(runtime)
}
