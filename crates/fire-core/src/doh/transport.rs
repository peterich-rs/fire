use std::{
    io,
    net::{IpAddr, SocketAddr},
    time::Duration,
};

use bytes::Bytes;
use fire_models::{normalize_doh_endpoint_url, DohPreset};
use http::{header::CONTENT_TYPE, Method, Request};
use openwire::{BoxFuture, CallContext, Client, DnsResolver, RequestBody, WireError};
use url::Url;

use crate::error::FireCoreError;

use super::wire::{decode_addresses, encode_query, DnsRecord};

const DOH_CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const DOH_CALL_TIMEOUT: Duration = Duration::from_secs(12);
const DOH_CONTENT_TYPE: &str = "application/dns-message";

pub(crate) trait DohTransport: Send + Sync {
    fn query(
        &self,
        endpoint_url: &str,
        name: &str,
        qtype: u16,
    ) -> BoxFuture<Result<Vec<DnsRecord>, FireCoreError>>;
}

#[derive(Clone)]
pub(crate) struct OpenWireDohTransport {
    client: Client,
}

impl OpenWireDohTransport {
    pub(crate) fn new() -> Result<Self, FireCoreError> {
        let mut builder = Client::builder()
            .dns_resolver(BootstrapDnsResolver)
            .connect_timeout(DOH_CONNECT_TIMEOUT)
            .call_timeout(DOH_CALL_TIMEOUT);
        builder = crate::core::apply_platform_tls(builder);
        let client = builder
            .build()
            .map_err(|source| FireCoreError::ClientBuild { source })?;
        Ok(Self { client })
    }
}

impl DohTransport for OpenWireDohTransport {
    fn query(
        &self,
        endpoint_url: &str,
        name: &str,
        qtype: u16,
    ) -> BoxFuture<Result<Vec<DnsRecord>, FireCoreError>> {
        let client = self.client.clone();
        let endpoint_url = endpoint_url.to_string();
        let name = name.to_string();
        Box::pin(async move {
            let endpoint = normalize_doh_endpoint_url(&endpoint_url).map_err(|error| {
                FireCoreError::InvalidArgument {
                    operation: "doh query",
                    details: error.to_string(),
                }
            })?;
            let query = encode_query(next_query_id(), &name, qtype).map_err(|error| {
                FireCoreError::InvalidArgument {
                    operation: "doh query",
                    details: error.to_string(),
                }
            })?;
            let request = Request::builder()
                .method(Method::POST)
                .uri(&endpoint)
                .header(CONTENT_TYPE, DOH_CONTENT_TYPE)
                .header(http::header::ACCEPT, DOH_CONTENT_TYPE)
                .body(RequestBody::from_bytes(Bytes::from(query)))
                .map_err(FireCoreError::RequestBuild)?;
            let response = client
                .execute(request)
                .await
                .map_err(|source| FireCoreError::Network { source })?;
            let status = response.status();
            let body = response
                .into_body()
                .bytes()
                .await
                .map_err(|source| FireCoreError::Network { source })?;
            if !status.is_success() {
                return Err(FireCoreError::HttpStatus {
                    operation: "doh query",
                    status: status.as_u16(),
                    body: String::from_utf8_lossy(&body).into_owned(),
                });
            }
            decode_addresses(&body, qtype).map_err(|error| FireCoreError::InvalidArgument {
                operation: "doh query",
                details: error.to_string(),
            })
        })
    }
}

#[derive(Clone, Debug, Default)]
struct BootstrapDnsResolver;

impl DnsResolver for BootstrapDnsResolver {
    fn resolve(
        &self,
        ctx: CallContext,
        host: String,
        port: u16,
    ) -> BoxFuture<Result<Vec<SocketAddr>, WireError>> {
        Box::pin(async move {
            ctx.listener().dns_start(&ctx, &host, port);
            match resolve_bootstrap_host(&host, port).await {
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

async fn resolve_bootstrap_host(host: &str, port: u16) -> Result<Vec<SocketAddr>, WireError> {
    if let Ok(ip) = host.parse::<IpAddr>() {
        return Ok(vec![SocketAddr::new(ip, port)]);
    }
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

pub(crate) async fn system_lookup(host: &str, port: u16) -> Result<Vec<SocketAddr>, WireError> {
    match tokio::net::lookup_host((host, port)).await {
        Ok(addrs) => {
            let addrs: Vec<_> = addrs.collect();
            if addrs.is_empty() {
                Err(WireError::dns(
                    "DNS resolution returned no socket addresses",
                    io::Error::new(io::ErrorKind::NotFound, "empty DNS result"),
                ))
            } else {
                Ok(addrs)
            }
        }
        Err(error) => Err(WireError::dns("DNS resolution failed", error)),
    }
}

fn next_query_id() -> u16 {
    use std::sync::atomic::{AtomicU16, Ordering};
    static NEXT: AtomicU16 = AtomicU16::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

pub(crate) fn endpoint_host(endpoint_url: &str) -> Option<String> {
    Url::parse(endpoint_url)
        .ok()
        .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
}

#[cfg(test)]
type FakeDohHandler = std::sync::Arc<
    dyn Fn(String, String, u16) -> Result<Vec<DnsRecord>, FireCoreError> + Send + Sync,
>;

#[cfg(test)]
#[derive(Clone)]
pub(crate) struct FakeDohTransport {
    handler: FakeDohHandler,
}

#[cfg(test)]
impl FakeDohTransport {
    pub(crate) fn new(
        handler: impl Fn(String, String, u16) -> Result<Vec<DnsRecord>, FireCoreError>
            + Send
            + Sync
            + 'static,
    ) -> Self {
        Self {
            handler: std::sync::Arc::new(handler),
        }
    }
}

#[cfg(test)]
impl DohTransport for FakeDohTransport {
    fn query(
        &self,
        endpoint_url: &str,
        name: &str,
        qtype: u16,
    ) -> BoxFuture<Result<Vec<DnsRecord>, FireCoreError>> {
        let result = (self.handler)(endpoint_url.to_string(), name.to_string(), qtype);
        Box::pin(async move { result })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn bootstrap_uses_preset_ips() {
        let addrs = resolve_bootstrap_host("dns.alidns.com", 443)
            .await
            .expect("bootstrap");
        let ips: Vec<_> = addrs.into_iter().map(|addr| addr.ip()).collect();
        assert!(ips.contains(&"223.5.5.5".parse().unwrap()));
        assert!(ips.contains(&"223.6.6.6".parse().unwrap()));
    }

    #[tokio::test]
    async fn bootstrap_accepts_ip_literal() {
        let addrs = resolve_bootstrap_host("1.1.1.1", 443)
            .await
            .expect("ip literal");
        assert_eq!(addrs, vec!["1.1.1.1:443".parse().unwrap()]);
    }
}
