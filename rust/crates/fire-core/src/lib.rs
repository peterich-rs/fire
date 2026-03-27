use std::sync::RwLock;

use fire_models::{BootstrapArtifacts, CookieSnapshot, SessionSnapshot};
use mars_xlog::{LogLevel, Xlog, XlogConfig, XlogError};
use openwire::Client;
use thiserror::Error;
use tracing::debug;
use url::Url;

#[derive(Debug, Clone)]
pub struct FireCoreConfig {
    pub base_url: String,
}

impl Default for FireCoreConfig {
    fn default() -> Self {
        Self {
            base_url: "https://linux.do".to_string(),
        }
    }
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
}

#[derive(Clone)]
pub struct FireCore {
    base_url: Url,
    client: Client,
    session: std::sync::Arc<RwLock<SessionSnapshot>>,
}

impl FireCore {
    pub fn new(config: FireCoreConfig) -> Result<Self, FireCoreError> {
        let base_url = Url::parse(&config.base_url)?;
        let client = Client::builder().build()?;
        let session = SessionSnapshot {
            cookies: CookieSnapshot::default(),
            bootstrap: BootstrapArtifacts {
                base_url: base_url.as_str().to_string(),
                ..BootstrapArtifacts::default()
            },
        };

        Ok(Self {
            base_url,
            client,
            session: std::sync::Arc::new(RwLock::new(session)),
        })
    }

    pub fn base_url(&self) -> &str {
        self.base_url.as_str()
    }

    pub fn snapshot(&self) -> SessionSnapshot {
        self.session.read().expect("session poisoned").clone()
    }

    pub fn apply_cookies(&self, cookies: CookieSnapshot) -> SessionSnapshot {
        let mut session = self.session.write().expect("session poisoned");
        session.cookies = cookies;
        debug!(has_login = session.cookies.has_login_session(), "updated session cookies");
        session.clone()
    }

    pub fn apply_bootstrap(&self, bootstrap: BootstrapArtifacts) -> SessionSnapshot {
        let mut session = self.session.write().expect("session poisoned");
        session.bootstrap = bootstrap;
        debug!(
            has_preloaded = session.bootstrap.has_preloaded_data,
            "updated bootstrap artifacts"
        );
        session.clone()
    }

    pub fn has_login_session(&self) -> bool {
        self.session
            .read()
            .expect("session poisoned")
            .cookies
            .has_login_session()
    }

    pub fn shared_client(&self) -> Client {
        self.client.clone()
    }
}

#[derive(Debug, Error)]
pub enum FireCoreError {
    #[error("invalid base url: {0}")]
    InvalidBaseUrl(#[from] url::ParseError),
    #[error("failed to build network client: {0}")]
    ClientBuild(#[from] openwire::WireError),
    #[error("failed to initialize logger: {0}")]
    Logger(#[from] XlogError),
}
