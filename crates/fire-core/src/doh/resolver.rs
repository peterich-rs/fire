use std::{
    collections::HashMap,
    io,
    net::{IpAddr, SocketAddr},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, RwLock},
    time::{Duration, Instant},
};

use fire_models::{DohPreset, DohProbeResult, DohSettings};
use openwire::{BoxFuture, CallContext, DnsResolver, WireError};
use tracing::{debug, info, warn};

use crate::{
    error::FireCoreError,
    sync_utils::{read_rwlock, write_rwlock},
};

use super::{
    transport::{endpoint_host, system_lookup, DohTransport, OpenWireDohTransport},
    wire::{DnsRecord, QTYPE_A, QTYPE_AAAA},
};

const CACHE_MIN_TTL: Duration = Duration::from_secs(30);
const CACHE_MAX_TTL: Duration = Duration::from_secs(300);
const SETTINGS_FILE_NAME: &str = "doh-settings.json";
const PROBE_HOST: &str = "linux.do";

#[derive(Clone)]
pub struct FireDohController {
    resolver: FireDohResolver,
    path: Option<PathBuf>,
}

impl FireDohController {
    pub fn load(workspace_path: Option<&Path>) -> Result<Self, FireCoreError> {
        let path = workspace_path.map(|root| root.join("cache").join(SETTINGS_FILE_NAME));
        let settings = match path.as_deref() {
            Some(path) if path.exists() => load_settings(path)?,
            _ => DohSettings::default(),
        };
        let settings = settings
            .normalize()
            .map_err(|error| FireCoreError::InvalidArgument {
                operation: "load doh settings",
                details: error.to_string(),
            })?;
        let transport = Arc::new(OpenWireDohTransport::new()?);
        let resolver = FireDohResolver::new(settings, transport);
        Ok(Self { resolver, path })
    }

    pub fn resolver(&self) -> FireDohResolver {
        self.resolver.clone()
    }

    pub fn settings(&self) -> DohSettings {
        self.resolver.settings()
    }

    pub fn set_settings(&self, settings: DohSettings) -> Result<DohSettings, FireCoreError> {
        let settings = settings
            .normalize()
            .map_err(|error| FireCoreError::InvalidArgument {
                operation: "set doh settings",
                details: error.to_string(),
            })?;
        self.resolver.replace_settings(settings.clone());
        if let Some(path) = &self.path {
            persist_settings(path, &settings)?;
        }
        info!(
            enabled = settings.enabled,
            endpoint = %settings.endpoint_url,
            "updated DoH settings"
        );
        Ok(settings)
    }

    pub async fn probe_settings(
        &self,
        settings: DohSettings,
        host: Option<&str>,
    ) -> Result<DohProbeResult, FireCoreError> {
        let settings = settings
            .normalize()
            .map_err(|error| FireCoreError::InvalidArgument {
                operation: "probe doh settings",
                details: error.to_string(),
            })?;
        let host = host
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or(PROBE_HOST)
            .to_string();
        let started = Instant::now();
        match self
            .resolver
            .resolve_with_settings(&settings, &host, 443)
            .await
        {
            Ok(addrs) => Ok(DohProbeResult {
                ok: true,
                host,
                resolved_addresses: addrs.iter().map(SocketAddr::to_string).collect(),
                elapsed_ms: elapsed_ms(started),
                error_message: None,
            }),
            Err(error) => Ok(DohProbeResult {
                ok: false,
                host,
                resolved_addresses: Vec::new(),
                elapsed_ms: elapsed_ms(started),
                error_message: Some(error.to_string()),
            }),
        }
    }
}

#[derive(Clone)]
pub struct FireDohResolver {
    inner: Arc<FireDohResolverInner>,
}

struct FireDohResolverInner {
    settings: RwLock<DohSettings>,
    cache: Mutex<HashMap<String, CacheEntry>>,
    transport: Arc<dyn DohTransport>,
}

#[derive(Clone)]
struct CacheEntry {
    addrs: Vec<SocketAddr>,
    expires_at: Instant,
}

impl FireDohResolver {
    fn new(settings: DohSettings, transport: Arc<dyn DohTransport>) -> Self {
        Self {
            inner: Arc::new(FireDohResolverInner {
                settings: RwLock::new(settings),
                cache: Mutex::new(HashMap::new()),
                transport,
            }),
        }
    }

    pub fn settings(&self) -> DohSettings {
        read_rwlock(&self.inner.settings, "doh settings").clone()
    }

    fn replace_settings(&self, settings: DohSettings) {
        *write_rwlock(&self.inner.settings, "doh settings") = settings;
        self.clear_cache();
    }

    fn clear_cache(&self) {
        self.inner
            .cache
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clear();
    }

    async fn resolve_with_settings(
        &self,
        settings: &DohSettings,
        host: &str,
        port: u16,
    ) -> Result<Vec<SocketAddr>, WireError> {
        if let Ok(ip) = host.parse::<IpAddr>() {
            return Ok(vec![SocketAddr::new(ip, port)]);
        }
        if !settings.enabled {
            return system_lookup(host, port).await;
        }
        if endpoint_host(&settings.endpoint_url).as_deref() == Some(host) {
            return resolve_doh_endpoint_host(host, port).await;
        }
        self.lookup_doh(settings, host, port).await
    }

    async fn lookup_doh(
        &self,
        settings: &DohSettings,
        host: &str,
        port: u16,
    ) -> Result<Vec<SocketAddr>, WireError> {
        let cache_key = format!("{host}:{port}");
        if let Some(cached) = self.cached(&cache_key) {
            debug!(host, port, "DoH cache hit");
            return Ok(cached);
        }

        let (a_result, aaaa_result) = tokio::join!(
            self.inner
                .transport
                .query(&settings.endpoint_url, host, QTYPE_A),
            self.inner
                .transport
                .query(&settings.endpoint_url, host, QTYPE_AAAA),
        );

        let mut records = Vec::new();
        let mut last_error: Option<FireCoreError> = None;
        match a_result {
            Ok(found) => records.extend(found),
            Err(error) => last_error = Some(error),
        }
        match aaaa_result {
            Ok(found) => records.extend(found),
            Err(error) => {
                if last_error.is_none() {
                    last_error = Some(error);
                }
            }
        }
        if records.is_empty() {
            let details = last_error
                .map(|error| error.to_string())
                .unwrap_or_else(|| "DoH returned no addresses".to_string());
            warn!(host, port, %details, "DoH lookup failed");
            return Err(WireError::dns(
                format!("DoH lookup failed for {host}"),
                io::Error::other(details),
            ));
        }

        let ttl = records
            .iter()
            .map(|record| Duration::from_secs(u64::from(record.ttl_secs)))
            .min()
            .unwrap_or(CACHE_MIN_TTL)
            .clamp(CACHE_MIN_TTL, CACHE_MAX_TTL);
        let addrs = records
            .into_iter()
            .map(|DnsRecord { address, .. }| SocketAddr::new(address, port))
            .collect::<Vec<_>>();
        self.store_cache(cache_key, addrs.clone(), ttl);
        debug!(
            host,
            port,
            count = addrs.len(),
            ttl_secs = ttl.as_secs(),
            "DoH lookup succeeded"
        );
        Ok(addrs)
    }

    fn cached(&self, key: &str) -> Option<Vec<SocketAddr>> {
        let mut cache = self
            .inner
            .cache
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let now = Instant::now();
        match cache.get(key) {
            Some(entry) if entry.expires_at > now => Some(entry.addrs.clone()),
            Some(_) => {
                cache.remove(key);
                None
            }
            None => None,
        }
    }

    fn store_cache(&self, key: String, addrs: Vec<SocketAddr>, ttl: Duration) {
        self.inner
            .cache
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .insert(
                key,
                CacheEntry {
                    addrs,
                    expires_at: Instant::now() + ttl,
                },
            );
    }
}

impl DnsResolver for FireDohResolver {
    fn resolve(
        &self,
        ctx: CallContext,
        host: String,
        port: u16,
    ) -> BoxFuture<Result<Vec<SocketAddr>, WireError>> {
        let resolver = self.clone();
        Box::pin(async move {
            ctx.listener().dns_start(&ctx, &host, port);
            let settings = resolver.settings();
            match resolver.resolve_with_settings(&settings, &host, port).await {
                Ok(addrs) => {
                    ctx.listener().dns_end(&ctx, &host, &addrs);
                    Ok(addrs)
                }
                Err(error) => {
                    ctx.listener().dns_failed(&ctx, &host, &error);
                    Err(error)
                }
            }
        })
    }
}

async fn resolve_doh_endpoint_host(host: &str, port: u16) -> Result<Vec<SocketAddr>, WireError> {
    if let Some(preset) = DohPreset::by_host(host) {
        let addrs: Vec<SocketAddr> = preset
            .bootstrap_ips
            .iter()
            .filter_map(|ip| ip.parse::<IpAddr>().ok())
            .map(|ip| SocketAddr::new(ip, port))
            .collect();
        if !addrs.is_empty() {
            return Ok(addrs);
        }
    }
    system_lookup(host, port).await
}

fn load_settings(path: &Path) -> Result<DohSettings, FireCoreError> {
    let payload = std::fs::read_to_string(path).map_err(|source| FireCoreError::WorkspaceIo {
        path: path.to_path_buf(),
        source,
    })?;
    serde_json::from_str(&payload).map_err(FireCoreError::PersistDeserialize)
}

fn persist_settings(path: &Path, settings: &DohSettings) -> Result<(), FireCoreError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|source| FireCoreError::WorkspaceIo {
            path: parent.to_path_buf(),
            source,
        })?;
    }
    let payload =
        serde_json::to_string_pretty(settings).map_err(FireCoreError::PersistSerialize)?;
    std::fs::write(path, payload).map_err(|source| FireCoreError::WorkspaceIo {
        path: path.to_path_buf(),
        source,
    })
}

fn elapsed_ms(started: Instant) -> u64 {
    started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::doh::transport::FakeDohTransport;
    use std::net::Ipv4Addr;

    fn record(octet: u8) -> DnsRecord {
        DnsRecord {
            address: IpAddr::V4(Ipv4Addr::new(1, 2, 3, octet)),
            ttl_secs: 120,
        }
    }

    #[tokio::test]
    async fn disabled_settings_do_not_call_transport() {
        let transport = FakeDohTransport::new(|_, _, _| {
            panic!("transport should not be used when DoH is disabled");
        });
        let resolver = FireDohResolver::new(
            DohSettings {
                enabled: false,
                endpoint_url: "https://dns.alidns.com/dns-query".into(),
            },
            Arc::new(transport),
        );
        // 127.0.0.1 is an IP literal, so even enabled mode would skip transport.
        let addrs = resolver
            .resolve_with_settings(&resolver.settings(), "127.0.0.1", 443)
            .await
            .unwrap();
        assert_eq!(addrs, vec!["127.0.0.1:443".parse().unwrap()]);
    }

    #[tokio::test]
    async fn enabled_lookup_uses_transport_and_cache() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_clone = calls.clone();
        let transport = FakeDohTransport::new(move |endpoint, name, qtype| {
            calls_clone.fetch_add(1, Ordering::SeqCst);
            assert_eq!(endpoint, "https://dns.alidns.com/dns-query");
            assert_eq!(name, "linux.do");
            if qtype == QTYPE_A {
                Ok(vec![record(10)])
            } else {
                Ok(Vec::new())
            }
        });
        let settings = DohSettings {
            enabled: true,
            endpoint_url: "https://dns.alidns.com/dns-query".into(),
        };
        let resolver = FireDohResolver::new(settings.clone(), Arc::new(transport));
        let first = resolver
            .resolve_with_settings(&settings, "linux.do", 443)
            .await
            .unwrap();
        let second = resolver
            .resolve_with_settings(&settings, "linux.do", 443)
            .await
            .unwrap();
        assert_eq!(first, vec!["1.2.3.10:443".parse().unwrap()]);
        assert_eq!(first, second);
        // A + AAAA once; second resolve is cached.
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn doh_endpoint_host_uses_bootstrap_not_transport() {
        let transport = FakeDohTransport::new(|_, _, _| {
            panic!("must not recurse into DoH for the DoH host");
        });
        let settings = DohSettings {
            enabled: true,
            endpoint_url: "https://dns.alidns.com/dns-query".into(),
        };
        let resolver = FireDohResolver::new(settings.clone(), Arc::new(transport));
        let addrs = resolver
            .resolve_with_settings(&settings, "dns.alidns.com", 443)
            .await
            .unwrap();
        let ips: Vec<_> = addrs.into_iter().map(|addr| addr.ip()).collect();
        assert!(ips.contains(&"223.5.5.5".parse().unwrap()));
    }

    #[tokio::test]
    async fn replacing_settings_clears_cache() {
        let transport = FakeDohTransport::new(|_, name, qtype| {
            if qtype != QTYPE_A {
                return Ok(Vec::new());
            }
            let octet = if name == "linux.do" { 1 } else { 2 };
            Ok(vec![record(octet)])
        });
        let settings = DohSettings {
            enabled: true,
            endpoint_url: "https://dns.alidns.com/dns-query".into(),
        };
        let resolver = FireDohResolver::new(settings.clone(), Arc::new(transport));
        let _ = resolver
            .resolve_with_settings(&settings, "linux.do", 443)
            .await
            .unwrap();
        resolver.replace_settings(settings.clone());
        let addrs = resolver
            .resolve_with_settings(&settings, "example.com", 443)
            .await
            .unwrap();
        assert_eq!(addrs, vec!["1.2.3.2:443".parse().unwrap()]);
    }

    #[test]
    fn persist_roundtrip() {
        let dir = std::env::temp_dir().join(format!(
            "fire-doh-test-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(SETTINGS_FILE_NAME);
        let settings = DohSettings {
            enabled: true,
            endpoint_url: "https://dns.google/dns-query".into(),
        };
        persist_settings(&path, &settings).unwrap();
        let loaded = load_settings(&path).unwrap();
        assert_eq!(loaded, settings);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
