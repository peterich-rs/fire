use std::sync::{Arc, RwLock};

use http::header::HeaderName;
use http::{Request, Response};
use openwire::{
    BoxFuture, ClientBuilder, Exchange, HttpLogger, Interceptor, LogLevel as OpenWireLogLevel,
    LoggerInterceptor, Next, RequestBody, ResponseBody, WireError,
};
use tracing::debug;
#[cfg(target_os = "android")]
use tracing::info;
use url::Url;

use super::constants::FIRE_USER_AGENT;
use super::headers::{
    apply_common_profile_headers, request_origin, request_referer, request_uri_origin,
};
use super::traced::FireSkipCsrfHeader;
use super::FireRequestProfile;
use crate::diagnostics::FireDiagnosticsStore;
use crate::sync_utils::read_rwlock;

#[derive(Clone)]
pub(crate) struct FireCommonHeaderInterceptor {
    origin: String,
    referer: String,
    session: Arc<RwLock<super::super::FireSessionRuntimeState>>,
}

pub(super) struct FireCommonProfileHeaderContext<'a> {
    pub(super) profile: FireRequestProfile,
    pub(super) origin: &'a str,
    pub(super) referer: &'a str,
    pub(super) same_origin: bool,
    pub(super) user_agent: &'a str,
    pub(super) has_login_session: bool,
    pub(super) csrf_token: Option<&'a str>,
    pub(super) skip_csrf_header: bool,
}

#[derive(Clone)]
pub(crate) struct FireTraceSnapshotInterceptor {
    diagnostics: Arc<FireDiagnosticsStore>,
}

#[derive(Clone, Copy)]
struct FireOpenWireHttpLogger;

impl FireTraceSnapshotInterceptor {
    pub(crate) fn new(diagnostics: Arc<FireDiagnosticsStore>) -> Self {
        Self { diagnostics }
    }
}

impl FireCommonHeaderInterceptor {
    pub(crate) fn new(
        base_url: Url,
        session: Arc<RwLock<super::super::FireSessionRuntimeState>>,
    ) -> Self {
        Self {
            origin: request_origin(&base_url),
            referer: request_referer(&base_url),
            session,
        }
    }

    fn apply_headers(&self, request: &mut Request<RequestBody>) {
        let Some(profile) = request.extensions().get::<FireRequestProfile>().copied() else {
            return;
        };
        let snapshot = read_rwlock(&self.session, "session").snapshot.clone();
        let same_origin = request_uri_origin(request)
            .as_deref()
            .is_none_or(|request_origin| request_origin == self.origin);
        let context = FireCommonProfileHeaderContext {
            profile,
            origin: &self.origin,
            referer: &self.referer,
            same_origin,
            user_agent: snapshot
                .browser_user_agent
                .as_deref()
                .filter(|value| !value.is_empty())
                .unwrap_or(FIRE_USER_AGENT),
            has_login_session: snapshot.cookies.has_login_session(),
            csrf_token: snapshot.cookies.csrf_token.as_deref(),
            skip_csrf_header: request.extensions().get::<FireSkipCsrfHeader>().is_some(),
        };
        apply_common_profile_headers(request.headers_mut(), context);
    }
}

impl Interceptor for FireCommonHeaderInterceptor {
    fn intercept(
        &self,
        mut exchange: Exchange,
        next: Next,
    ) -> BoxFuture<Result<Response<ResponseBody>, WireError>> {
        self.apply_headers(exchange.request_mut());
        next.run(exchange)
    }
}

impl Interceptor for FireTraceSnapshotInterceptor {
    fn intercept(
        &self,
        exchange: Exchange,
        next: Next,
    ) -> BoxFuture<Result<Response<ResponseBody>, WireError>> {
        if let Some(metadata) = exchange
            .request()
            .extensions()
            .get::<crate::diagnostics::FireRequestTraceMetadata>()
        {
            self.diagnostics.record_request_headers_snapshot(
                metadata.trace_id,
                exchange.request(),
                exchange.attempt(),
            );
        }
        next.run(exchange)
    }
}

impl HttpLogger for FireOpenWireHttpLogger {
    fn log(&self, message: &str) {
        debug!(target: "openwire::http", "{}", message);
    }
}

pub(super) fn fire_openwire_logger_interceptor() -> LoggerInterceptor {
    LoggerInterceptor::with_logger(OpenWireLogLevel::Basic, FireOpenWireHttpLogger)
        .redact_header(HeaderName::from_static("x-csrf-token"))
}

pub(crate) fn apply_platform_tls(builder: ClientBuilder) -> ClientBuilder {
    #[cfg(target_os = "android")]
    {
        builder.tls_connector(android_tls_connector())
    }
    #[cfg(not(target_os = "android"))]
    {
        builder
    }
}

#[cfg(target_os = "android")]
fn android_tls_connector() -> openwire::RustlsTlsConnector {
    let roots = rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let root_count = roots.len();
    info!(
        target: "fire.network",
        tls_backend = "rustls",
        verifier_backend = "webpki-roots",
        root_count,
        "configured Android OpenWire TLS verifier"
    );
    let config = rustls::ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    openwire::RustlsTlsConnector::from_config(config)
}
