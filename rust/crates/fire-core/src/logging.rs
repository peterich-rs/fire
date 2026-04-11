use std::{
    fs,
    fs::OpenOptions,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock},
};

use mars_xlog::{LogLevel, Xlog, XlogConfig};
use tracing_subscriber::prelude::*;
use tracing_subscriber::{filter::LevelFilter, fmt::writer::MakeWriter};

use crate::error::FireCoreError;

const FIRE_LOGGER_NAME_PREFIX: &str = "fire";
const FIRE_LOGS_DIR_NAME: &str = "logs";
const FIRE_LOG_CACHE_PARENT_DIR: &str = "cache";
const FIRE_LOG_CACHE_DIR_NAME: &str = "xlog";
const FIRE_DIAGNOSTICS_DIR_NAME: &str = "diagnostics";
const FIRE_READABLE_LOG_FILE_NAME: &str = "fire-readable.log";
const FIRE_HOST_LOG_TARGET: &str = "fire.host";
const FIRE_LOG_MAX_FILE_SIZE_BYTES: i64 = 8 * 1024 * 1024;
const FIRE_LOG_MAX_ALIVE_SECONDS: i64 = 7 * 24 * 60 * 60;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FireHostLogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

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
    readable_log_writer: Arc<Mutex<FileBackedMakeWriter>>,
    logger: FireLogger,
}

impl FireLoggerRuntime {
    fn initialize(workspace_path: PathBuf) -> Result<Self, FireCoreError> {
        let log_dir = workspace_path.join(FIRE_LOGS_DIR_NAME);
        let cache_dir = workspace_path
            .join(FIRE_LOG_CACHE_PARENT_DIR)
            .join(FIRE_LOG_CACHE_DIR_NAME);
        let diagnostics_dir = workspace_path.join(FIRE_DIAGNOSTICS_DIR_NAME);
        let readable_log_path = diagnostics_dir.join(FIRE_READABLE_LOG_FILE_NAME);

        fs::create_dir_all(&log_dir).map_err(|source| FireCoreError::WorkspaceIo {
            path: log_dir.clone(),
            source,
        })?;
        fs::create_dir_all(&cache_dir).map_err(|source| FireCoreError::WorkspaceIo {
            path: cache_dir.clone(),
            source,
        })?;
        fs::create_dir_all(&diagnostics_dir).map_err(|source| FireCoreError::WorkspaceIo {
            path: diagnostics_dir.clone(),
            source,
        })?;

        // Development phase: keep full-fidelity file logs in release packages too.
        let level = LogLevel::Debug;
        let readable_log_writer =
            Arc::new(Mutex::new(FileBackedMakeWriter::new(&readable_log_path)?));
        let logger = FireLogger::init(FireLoggerConfig {
            log_dir: log_dir.display().to_string(),
            cache_dir: Some(cache_dir.display().to_string()),
            name_prefix: FIRE_LOGGER_NAME_PREFIX.to_string(),
            level,
        })?;
        logger.inner.set_max_file_size(FIRE_LOG_MAX_FILE_SIZE_BYTES);
        logger.inner.set_max_alive_time(FIRE_LOG_MAX_ALIVE_SECONDS);
        logger.set_console_log_open(cfg!(debug_assertions));
        init_tracing(
            logger.inner.clone(),
            level,
            Arc::clone(&readable_log_writer),
        );

        Ok(Self {
            workspace_path,
            log_dir,
            cache_dir,
            readable_log_writer,
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
        if let Ok(mut writer) = self.readable_log_writer.lock() {
            let _ = writer.flush();
        }
    }
}

fn init_tracing(
    logger: Xlog,
    level: LogLevel,
    readable_log_writer: Arc<Mutex<FileBackedMakeWriter>>,
) {
    static TRACING_INIT: OnceLock<()> = OnceLock::new();
    let _ = TRACING_INIT.get_or_init(|| {
        let (layer, _handle) = mars_xlog::XlogLayer::with_config(
            logger,
            mars_xlog::XlogLayerConfig::new(level).enabled(true),
        );
        let readable_layer = tracing_subscriber::fmt::layer()
            .compact()
            .with_ansi(false)
            .with_writer(SharedFileMakeWriter {
                inner: readable_log_writer,
            })
            .with_filter(level_filter_for(level));
        let subscriber = tracing_subscriber::registry()
            .with(layer)
            .with(readable_layer);
        let _ = tracing::subscriber::set_global_default(subscriber);
    });
}

fn level_filter_for(level: LogLevel) -> LevelFilter {
    match level {
        LogLevel::Verbose | LogLevel::Debug => LevelFilter::DEBUG,
        LogLevel::Info => LevelFilter::INFO,
        LogLevel::Warn => LevelFilter::WARN,
        LogLevel::Error | LogLevel::Fatal => LevelFilter::ERROR,
        LogLevel::None => LevelFilter::OFF,
    }
}

pub fn log_host_message(
    level: FireHostLogLevel,
    target: &str,
    message: &str,
    diagnostic_session_id: Option<&str>,
) {
    let host_target = if target.trim().is_empty() {
        FIRE_LOGGER_NAME_PREFIX
    } else {
        target
    };
    let diagnostic_session_id = diagnostic_session_id.unwrap_or("unknown");

    match level {
        FireHostLogLevel::Debug => {
            tracing::debug!(
                target: FIRE_HOST_LOG_TARGET,
                host_target = host_target,
                diagnostic_session_id = diagnostic_session_id,
                "{}",
                message
            );
        }
        FireHostLogLevel::Info => {
            tracing::info!(
                target: FIRE_HOST_LOG_TARGET,
                host_target = host_target,
                diagnostic_session_id = diagnostic_session_id,
                "{}",
                message
            );
        }
        FireHostLogLevel::Warn => {
            tracing::warn!(
                target: FIRE_HOST_LOG_TARGET,
                host_target = host_target,
                diagnostic_session_id = diagnostic_session_id,
                "{}",
                message
            );
        }
        FireHostLogLevel::Error => {
            tracing::error!(
                target: FIRE_HOST_LOG_TARGET,
                host_target = host_target,
                diagnostic_session_id = diagnostic_session_id,
                "{}",
                message
            );
        }
    }
}

struct FileBackedMakeWriter {
    file: std::fs::File,
}

impl FileBackedMakeWriter {
    fn new(path: &Path) -> Result<Self, FireCoreError> {
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .map_err(|source| FireCoreError::WorkspaceIo {
                path: path.to_path_buf(),
                source,
            })?;
        Ok(Self { file })
    }

    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}

#[derive(Clone)]
struct SharedFileMakeWriter {
    inner: Arc<Mutex<FileBackedMakeWriter>>,
}

impl<'a> MakeWriter<'a> for SharedFileMakeWriter {
    type Writer = SharedFileWriterGuard;

    fn make_writer(&'a self) -> Self::Writer {
        SharedFileWriterGuard {
            inner: Arc::clone(&self.inner),
        }
    }
}

struct SharedFileWriterGuard {
    inner: Arc<Mutex<FileBackedMakeWriter>>,
}

impl Write for SharedFileWriterGuard {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.inner
            .lock()
            .expect("readable log writer lock poisoned")
            .file
            .write(buf)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.inner
            .lock()
            .expect("readable log writer lock poisoned")
            .flush()
    }
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
